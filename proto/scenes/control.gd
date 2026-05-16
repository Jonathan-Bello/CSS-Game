extends Control

const EmisClientScript = preload("res://proto/scenes/emis_client.gd")
@onready var panel: PanelContainer = $PanelContainer
@onready var web: Control = $PanelContainer/WebView

@export var window_size: Vector2 = Vector2(900, 600)
@export var content_padding: int = 8

var last_css: String = ""
var last_svg: String = ""
var last_bullet_profile_path: String = ""
var _web_hydration_payload: Dictionary = {}
var _emis_client: Node = null
var _emis_conversation_id: String = ""
var _last_loaded_html: String = ""

signal overlay_opened
signal overlay_closed

func _ready() -> void:
	add_to_group("web_overlay")
	visible = false
	panel.visible = false
	web.visible = false

	# Estado seguro WebView2
	web.set("url", "about:blank")
	web.set("transparent", true)
	web.set("devtools", true)

	if not web.is_connected("ipc_message", Callable(self , "_on_web_ipc_message")):
		web.connect("ipc_message", Callable(self , "_on_web_ipc_message"))

	_ensure_emis_client()
	_layout_and_sync()
	print("[WebOverlay] READY")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_and_sync()

func _layout_and_sync() -> void:
	var vp := get_viewport_rect().size
	panel.custom_minimum_size = window_size
	panel.size = window_size
	panel.position = (vp - panel.size) * 0.5

	web.position = panel.position + Vector2(content_padding, content_padding)
	web.size = panel.size - Vector2(content_padding * 2, content_padding * 2)

func _emit_overlay_opened() -> void:
	emit_signal("overlay_opened")

func _emit_overlay_closed() -> void:
	emit_signal("overlay_closed")

func open() -> void:
	print("[WebOverlay] open()")
	visible = true
	panel.visible = true
	web.visible = true

	# Mientras esté abierto, el panel debe “parar” el input de la escena
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	await get_tree().process_frame
	_layout_and_sync()
	_load_editor_html()
	web.call_deferred("focus")
	_emit_overlay_opened()
	print("[WebOverlay] open -> HTML cargado, focus defer")

func close() -> void:
	print("[WebOverlay] close()")

	# Quita el foco del WebView
	if web.has_method("focus_parent"):
		web.call_deferred("focus_parent")
	if web.has_method("unfocus"):
		web.call_deferred("unfocus")
	get_viewport().gui_release_focus()

	# Oculta overlay y deja de interceptar input
	web.visible = false
	panel.visible = false
	visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Limpia contenido para próximas aperturas
	web.set("html", "")
	web.set("url", "about:blank")

	_emit_overlay_closed()

func _input(ev: InputEvent) -> void:
	if visible and ev.is_action_pressed("ui_cancel"):
		close()

# -----------------------------
# SECRET / ENV HELPERS
# -----------------------------
func _read_env_file(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out

	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var eq := line.find("=")
		if eq == -1:
			continue
		var k := line.substr(0, eq).strip_edges()
		var v := line.substr(eq + 1).strip_edges()
		# Quita comillas si vienen
		if (v.begins_with("\"") and v.ends_with("\"")) or (v.begins_with("'") and v.ends_with("'")):
			v = v.substr(1, v.length() - 2)
		out[k] = v
	return out

func _get_secret(key_name: String) -> String:
	# 1) variable de entorno real (ideal)
	var v := OS.get_environment(key_name)
	if v != "":
		return v

	# 2) modo dev: leer .env (NO recomendado para producción)
	# Puedes decidir moverlo a user://.env para no empacarlo en export.
	var env_res := _read_env_file("res://.env")
	if env_res.has(key_name) and String(env_res[key_name]) != "":
		return String(env_res[key_name])

	var env_user := _read_env_file("user://.env")
	if env_user.has(key_name) and String(env_user[key_name]) != "":
		return String(env_user[key_name])

	return ""

func _inject_window_var(var_name: String, value: String) -> void:
	if value == "":
		return
	if not web.has_method("eval"):
		return

	# Escapar para JS string literal simple
	var safe := value
	safe = safe.replace("\\", "\\\\")
	safe = safe.replace("'", "\\'")
	safe = safe.replace("\n", "\\n")
	safe = safe.replace("\r", "")

	var js := "window.%s='%s';" % [var_name, safe]
	web.call_deferred("eval", js)

# -----------------------------
# HTML LOADER
# -----------------------------
func _read_editor_html_template() -> String:
	var template_path := "res://proto/scenes/web_overlay_editor.html"
	if not FileAccess.file_exists(template_path):
		push_warning("[WebOverlay] No se encontró template HTML: %s" % template_path)
		return ""
	var file := FileAccess.open(template_path, FileAccess.READ)
	if file == null:
		push_warning("[WebOverlay] No se pudo abrir template HTML: %s" % template_path)
		return ""
	var html := file.get_as_text()
	# Hardening: si el template llega con escapes heredados del antiguo string
	# embebido (ej. [\\s\\S] o <\\/script>), normalizamos a regex JS válido.
	html = html.replace("\\\\s", "\\s")
	html = html.replace("\\\\S", "\\S")
	html = html.replace("<\\\\/script>", "<\\/script>")
	return html

func _read_overlay_font_data_uri() -> String:
	var font_path := "res://proto/assets/fonts/Quantico-Regular.ttf"
	if not FileAccess.file_exists(font_path):
		push_warning("[WebOverlay] No se encontró fuente OverlayDisplay: %s" % font_path)
		return ""
	var font_file := FileAccess.open(font_path, FileAccess.READ)
	if font_file == null:
		push_warning("[WebOverlay] No se pudo abrir fuente OverlayDisplay: %s" % font_path)
		return ""
	var bytes := font_file.get_buffer(font_file.get_length())
	if bytes.is_empty():
		push_warning("[WebOverlay] Fuente OverlayDisplay vacía: %s" % font_path)
		return ""
	return "data:font/ttf;base64,%s" % Marshalls.raw_to_base64(bytes)

func _load_editor_html() -> void:
	_web_hydration_payload = _read_bullet_hydration_payload()
	var html := _read_editor_html_template()
	if html == "":
		html = "<!doctype html><html><body style='margin:0;background:#111;color:#fff'>Editor no disponible</body></html>"

	var font_data_uri := _read_overlay_font_data_uri()
	html = html.replace("__OVERLAY_FONT_DATA_URI__", font_data_uri)

	_last_loaded_html = html
	var base_url := "https://overlay.local/"
	var supports_base_url := false
	for method_info in web.get_method_list():
		if str(method_info.get("name", "")) != "load_html":
			continue
		var argc := int(method_info.get("args", []).size())
		if argc >= 2:
			supports_base_url = true
			break
	if supports_base_url:
		web.call("load_html", html, base_url)
	else:
		print("[WebOverlay] load_html sin base URL: plugin expone firma de 1 parámetro")
		web.call("load_html", html)

func _debug_print_html_context(error_line: int, context_radius: int = 4) -> void:
	if _last_loaded_html == "":
		return
	if error_line <= 0:
		return
	var lines := _last_loaded_html.split("\n")
	var total := lines.size()
	if total == 0:
		return
	var start_line :Variant= max(1, error_line - context_radius)
	var end_line :Variant = min(total, error_line + context_radius)
	print("[WebOverlay][JS][ctx] around about:blank:%s (total=%s)" % [error_line, total])
	for idx in range(start_line, end_line + 1):
		var marker := ">>" if idx == error_line else "  "
		print("[WebOverlay][JS][ctx]%s L%s: %s" % [marker, idx, lines[idx - 1]])

func _on_web_ipc_message(msg: String) -> void:
	print("[WebOverlay] ipc_message: ", msg)

	if msg == "close":
		close()
		return

	if msg == "html_loaded":
		print("[WebOverlay] HTML cargado")
		if not _web_hydration_payload.is_empty():
			_hydrate_web_editor(_web_hydration_payload)
			_web_hydration_payload = {}
		return

	if msg == "img_error":
		push_warning("[WebOverlay] Error rasterizando SVG")
		return

	var data: Variant = JSON.parse_string(msg)
	if typeof(data) == TYPE_DICTIONARY:
		match str(data.get("type", "")):
			"debug_js_log":
				print("[WebOverlay][JS][log] %s" % str(data.get("message", "")))
			"debug_js_error":
				var message := str(data.get("message", ""))
				var source := str(data.get("source", ""))
				var line_number := int(data.get("line", 0))
				var column_number := int(data.get("column", 0))
				push_warning("[WebOverlay][JS] %s @%s:%s:%s" % [message, source, line_number, column_number])
				if source == "about:blank":
					_debug_print_html_context(line_number, 6)
			"debug_font_status":
				print("[WebOverlay][Font] estado=%s ready=%s distinct_metrics=%s active=%s computed=%s" % [
					str(data.get("requested", "OverlayDisplay")),
					str(data.get("ready", false)),
					str(data.get("distinct_metrics", false)),
					str(data.get("active_overlay_font", false)),
					str(data.get("computed_font_family", ""))
				])
			"close":
				close()
				return
			"save_css":
				_save_css_draft(data)
			"equip_bullet":
				_save_and_equip_bullet(data)
				close()
			"chat_request":
				_handle_chat_request(data)

func _handle_chat_request(data: Dictionary) -> void:
	var raw_message := String(data.get("message", ""))
	var message := raw_message.strip_edges()
	if message == "":
		push_warning("[Emis] chat_request inválido: message vacío")
		_send_emis_reply_to_web({
			"ok": false,
			"error": "message vacío",
			"code": "invalid_response"
		})
		return

	var incoming_context: Dictionary = {}
	var raw_context: Variant = data.get("context", {})
	if typeof(raw_context) == TYPE_DICTIONARY:
		incoming_context = raw_context

	var context := _build_emis_context(incoming_context)
	var payload := _build_emis_payload_for_backend(data, context, message)
	print("[Emis] solicitud -> %s" % JSON.stringify(payload))

	var response: Dictionary = {}
	var client := _get_emis_client()
	if client == null:
		var no_client_msg := "Cliente Emis no disponible"
		push_warning("[Emis] " + no_client_msg)
		response = {"ok": false, "error": no_client_msg, "code": "network"}
	elif client.has_method("request_chat"):
		var result: Variant = await client.call("request_chat", payload)
		if typeof(result) == TYPE_DICTIONARY:
			response = result
		else:
			response = {"ok": false, "error": "Respuesta inválida del cliente Emis", "code": "invalid_response"}
	elif client.has_method("chat_request"):
		var alt_result: Variant = await client.call("chat_request", payload)
		if typeof(alt_result) == TYPE_DICTIONARY:
			response = alt_result
		else:
			response = {"ok": false, "error": "Respuesta inválida del cliente Emis", "code": "invalid_response"}
	else:
		response = {"ok": false, "error": "Cliente Emis sin método de chat compatible", "code": "invalid_response"}

	if not bool(response.get("ok", false)):
		push_warning("[Emis] error <- %s (%s)" % [String(response.get("error", "desconocido")), String(response.get("code", "unknown"))])
	else:
		_update_emis_conversation_id(response)
		print("[Emis] respuesta <- %s" % JSON.stringify(response))
	_send_emis_reply_to_web(response)

func _build_emis_payload_for_backend(data: Dictionary, context: Dictionary, message: String) -> Dictionary:
	var normalized_message := message.substr(0, min(message.length(), 1200))
	var intent_mode := String(data.get("intent_mode", context.get("intent_mode", "auto"))).strip_edges().to_lower()
	if intent_mode != "tutor_css" and intent_mode != "guia_juego":
		intent_mode = "auto"

	var player_context := _build_player_context_for_emis(data, context)
	var css_snapshot_fragment := String(context.get("css_text", last_css)).strip_edges()
	if css_snapshot_fragment.length() > 10000:
		css_snapshot_fragment = css_snapshot_fragment.substr(0, 10000)

	var payload := {
		"message": normalized_message,
		"intent_mode": intent_mode,
		"player_context": player_context,
		"css_snapshot_fragment": css_snapshot_fragment
	}

	if _emis_conversation_id == "":
		_emis_conversation_id = _create_conversation_id()
	if _emis_conversation_id != "":
		payload["conversation_id"] = _emis_conversation_id

	return payload

func _build_player_context_for_emis(data: Dictionary, context: Dictionary) -> Dictionary:
	var snapshot: Dictionary = {}
	var raw_snapshot: Variant = context.get("snapshot", {})
	if typeof(raw_snapshot) == TYPE_DICTIONARY:
		snapshot = raw_snapshot

	var player_context: Dictionary = {}
	player_context["screen"] = String(data.get("screen", context.get("screen", "bullet_creator"))).strip_edges()
	player_context["level"] = String(data.get("level", context.get("level", ""))).strip_edges()
	player_context["objective"] = String(data.get("objective", context.get("objective", ""))).strip_edges()
	player_context["zone_id"] = String(data.get("zone_id", context.get("zone_id", ""))).strip_edges()
	player_context["quest_id"] = String(data.get("quest_id", context.get("quest_id", ""))).strip_edges()
	player_context["quest_step"] = String(data.get("quest_step", context.get("quest_step", ""))).strip_edges()

	var unlocked_css_raw: Variant = data.get("unlocked_css", context.get("unlocked_css", snapshot.get("detected_properties", [])))
	player_context["unlocked_css"] = _to_packed_string_array(unlocked_css_raw)
	player_context["nearby_npcs"] = _to_packed_string_array(data.get("nearby_npcs", context.get("nearby_npcs", [])))
	player_context["available_portals"] = _to_packed_string_array(data.get("available_portals", context.get("available_portals", [])))
	player_context["inventory_tags"] = _to_packed_string_array(data.get("inventory_tags", context.get("inventory_tags", [])))
	player_context["failed_attempts_css"] = _to_packed_string_array(data.get("failed_attempts_css", context.get("failed_attempts_css", [])))
	return player_context

func _create_conversation_id() -> String:
	return "conv_%s_%s" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]

func _update_emis_conversation_id(response: Dictionary) -> void:
	var raw: Dictionary = {}
	var raw_response: Variant = response.get("raw", {})
	if typeof(raw_response) == TYPE_DICTIONARY:
		raw = raw_response

	var from_raw := String(raw.get("conversation_id", "")).strip_edges()
	if from_raw != "":
		_emis_conversation_id = from_raw
		return

	var from_top_level := String(response.get("conversation_id", "")).strip_edges()
	if from_top_level != "":
		_emis_conversation_id = from_top_level

func _to_packed_string_array(raw: Variant) -> PackedStringArray:
	if raw is PackedStringArray:
		return raw
	if raw is Array:
		var mapped := PackedStringArray()
		for item in raw:
			var value := String(item).strip_edges().to_lower()
			if value != "":
				mapped.append(value)
		return mapped
	return PackedStringArray()

func _build_emis_context(data_from_js: Dictionary) -> Dictionary:
	# Contrato estable emis_chat_v1:
	# {
	#   contract_version: String,
	#   css_text: String,
	#   svg_text: String,
	#   bullet_equipped: bool,
	#   updated_at: String,
	#   detected_properties: PackedStringArray,
	#   css_rules: PackedStringArray,
	#   locked_properties: PackedStringArray,
	#   unlock_state: Dictionary,
	#   all_properties: PackedStringArray,
	#   history: Array[Dictionary]?,
	#   snapshot: Dictionary
	# }
	var context := data_from_js.duplicate(true)
	var hydration := _read_bullet_hydration_payload()
	var snapshot: Dictionary = {}
	var raw_snapshot: Variant = context.get("snapshot", {})
	if typeof(raw_snapshot) == TYPE_DICTIONARY:
		snapshot = raw_snapshot

	var css_text := String(snapshot.get("css_text", String(context.get("css_text", context.get("css", "")))))
	if css_text == "":
		css_text = String(hydration.get("css_text", last_css))

	var svg_text := String(snapshot.get("svg_text", String(context.get("svg_text", context.get("svg", "")))))
	if svg_text == "":
		svg_text = String(hydration.get("svg_text", ""))
	if svg_text == "":
		svg_text = last_svg

	var detected_from_js := _to_packed_string_array(snapshot.get("detected_properties", context.get("detected_properties", [])))
	var detected_backend := _extract_css_rules(css_text)
	var detected_properties := detected_from_js if not detected_from_js.is_empty() else detected_backend

	var locked_from_js := _to_packed_string_array(snapshot.get("locked_properties", context.get("locked_properties", [])))
	var locked_backend := _get_locked_properties_from_singleton(css_text)
	var locked_properties := locked_from_js if not locked_from_js.is_empty() else locked_backend

	var unlock_state := _get_unlock_state_from_singleton()
	var unlock_state_from_js: Variant = snapshot.get("unlock_state", context.get("unlock_state", {}))
	if typeof(unlock_state_from_js) == TYPE_DICTIONARY:
		var from_js_dict: Dictionary = unlock_state_from_js
		if not from_js_dict.is_empty():
			unlock_state = from_js_dict

	var bullet_equipped := bool(snapshot.get("bullet_equipped", context.get("bullet_equipped", hydration.get("bullet_equipped", false))))
	var updated_at := String(snapshot.get("updated_at", context.get("updated_at", hydration.get("updated_at", ""))))

	context["contract_version"] = String(context.get("contract_version", "emis_chat_v1"))
	context["css_text"] = css_text
	context["svg_text"] = svg_text
	context["css"] = css_text
	context["svg"] = svg_text
	context["bullet_equipped"] = bullet_equipped
	context["updated_at"] = updated_at
	context["detected_properties"] = detected_properties
	context["css_rules"] = detected_backend
	context["locked_properties"] = locked_properties
	context["unlock_state"] = unlock_state
	context["all_properties"] = _get_all_properties_from_singleton()

	context["snapshot"] = {
		"css_text": css_text,
		"svg_text": svg_text,
		"detected_properties": detected_properties,
		"locked_properties": locked_properties,
		"unlock_state": unlock_state,
		"bullet_equipped": bullet_equipped,
		"updated_at": updated_at
	}
	return context

func _ensure_emis_client() -> void:
	if is_instance_valid(_emis_client):
		return
	_emis_client = EmisClientScript.new()
	_emis_client.name = "EmisClient"
	add_child(_emis_client)
	if _emis_client.has_method("add_to_group"):
		_emis_client.call("add_to_group", "emis_client")
	print("[Emis] Cliente local inicializado")

func _get_emis_client() -> Node:
	if is_instance_valid(_emis_client):
		return _emis_client

	var root := get_tree().root
	if root == null:
		return null
	var by_name := root.get_node_or_null("EmisClient")
	if by_name != null:
		return by_name
	var by_group := get_tree().get_first_node_in_group("emis_client")
	if by_group != null:
		return by_group
	return null

func _send_emis_reply_to_web(payload: Dictionary) -> void:
	if not web.has_method("eval"):
		push_warning("[Emis] WebView sin método eval para responder")
		return
	var safe_payload := payload
	if safe_payload.is_empty():
		safe_payload = {"error": "Respuesta vacía del backend Emis"}
	var js := "window.onEmisReply(%s);" % JSON.stringify(safe_payload)
	web.call_deferred("eval", js)

func _save_css_draft(data: Dictionary) -> void:
	last_css = String(data.get("css", ""))
	last_svg = String(data.get("svg", ""))
	var dir_path := "user://bullets"
	var mkdir_err := DirAccess.make_dir_recursive_absolute(dir_path)
	if mkdir_err != OK and mkdir_err != ERR_ALREADY_EXISTS:
		push_warning("[WebOverlay] No se pudo crear directorio de borradores. err=%s" % mkdir_err)
		return

	var draft_path := "%s/bullet_draft.json" % dir_path
	var now_iso := Time.get_datetime_string_from_system(true, true)
	var draft := {
		"css_text": last_css,
		"svg_text": last_svg,
		"updated_at": now_iso
	}
	var draft_file := FileAccess.open(draft_path, FileAccess.WRITE)
	if draft_file == null:
		push_warning("[WebOverlay] No se pudo guardar borrador editable")
		return
	draft_file.store_string(JSON.stringify(draft, "\t"))
	draft_file.flush()
	print("[WebOverlay] CSS draft persistido en %s" % draft_path)

func _save_and_equip_bullet(data: Dictionary) -> void:
	last_css = String(data.get("css", ""))
	last_svg = String(data.get("svg", ""))
	_save_css_draft(data)

	var data_url := String(data.get("data_url", ""))
	var prefix := "base64,"
	var base64_index := data_url.find(prefix)
	if base64_index == -1:
		push_warning("[WebOverlay] data_url inválida para bullet")
		return

	var bytes := Marshalls.base64_to_raw(data_url.substr(base64_index + prefix.length()))
	if bytes.is_empty():
		push_warning("[WebOverlay] PNG vacío para bullet")
		return

	var dir_path := "user://bullets"
	var mkdir_err := DirAccess.make_dir_recursive_absolute(dir_path)
	if mkdir_err != OK and mkdir_err != ERR_ALREADY_EXISTS:
		push_warning("[WebOverlay] No se pudo crear directorio bullets. err=%s" % mkdir_err)
		return

	var image_path := "%s/bullet_current.png" % dir_path
	var profile_path := "%s/bullet_current.json" % dir_path

	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		push_warning("[WebOverlay] PNG inválido para bullet")
		return
	if image.save_png(image_path) != OK:
		push_warning("[WebOverlay] No se pudo guardar imagen bullet")
		return

	var meta: Dictionary = data.get("meta", {})
	var now_iso := Time.get_datetime_string_from_system(true, true)
	var existing_created_at := ""
	if FileAccess.file_exists(profile_path):
		var existing_data = _read_json_file(profile_path)
		if typeof(existing_data) == TYPE_DICTIONARY:
			existing_created_at = String(existing_data.get("created_at", ""))
	if existing_created_at == "":
		existing_created_at = now_iso

	var normalized_properties: Dictionary = _parse_relevant_properties_from_singleton(last_css)
	var locked_properties: PackedStringArray = _get_locked_properties_from_singleton(last_css)
	var profile := {
		"sprite_path": image_path,
		"image_path": image_path,
		"meta": {
			"w": int(meta.get("w", image.get_width())),
			"h": int(meta.get("h", image.get_height()))
		},
		"css_text": last_css,
		"css_rules": _extract_css_rules(last_css),
		"css_properties": normalized_properties,
		"css_locked_properties": locked_properties,
		"css_properties_used": _extract_css_rules(last_css),
		"damage_base": 1,
		"svg_text": last_svg,
		"created_at": existing_created_at,
		"updated_at": now_iso
	}

	var json_file := FileAccess.open(profile_path, FileAccess.WRITE)
	if json_file == null:
		push_warning("[WebOverlay] No se pudo abrir perfil bullet para escritura")
		return
	json_file.store_string(JSON.stringify(profile, "\t"))
	json_file.flush()
	last_bullet_profile_path = profile_path
	print("[WebOverlay] Bullet guardada en %s" % profile_path)
	print("[WebOverlay] profile(user://): %s" % profile_path)
	print("[WebOverlay] profile(abs): %s" % ProjectSettings.globalize_path(profile_path))
	print("[WebOverlay] image(user://): %s" % image_path)
	print("[WebOverlay] image(abs): %s" % ProjectSettings.globalize_path(image_path))
	profile["profile_path"] = profile_path
	_notify_player_to_equip_bullet(profile)

func _notify_player_to_equip_bullet(profile: Dictionary) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("[WebOverlay] No se encontró jugador para equipar bullet")
		return
	if player.has_method("equip_bullet_from_profile"):
		player.call("equip_bullet_from_profile", profile)
	elif player.has_method("equip_bullet_profile"):
		player.call("equip_bullet_profile", profile)
	else:
		push_warning("[WebOverlay] Jugador sin método equip_bullet_from_profile(profile)")

func _read_json_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	if text.strip_edges() == "":
		return null
	return JSON.parse_string(text)

func _read_bullet_hydration_payload() -> Dictionary:
	var unlock_state: Dictionary = _get_unlock_state_from_singleton()
	var all_properties: PackedStringArray = _get_all_properties_from_singleton()
	var base_payload := {
		"unlock_state": unlock_state,
		"all_properties": all_properties,
		"bullet_equipped": false,
		"updated_at": ""
	}
	var draft_path := "user://bullets/bullet_draft.json"
	var profile_path := "user://bullets/bullet_current.json"
	var css_text := ""
	var svg_text := ""
	var updated_at := ""
	var bullet_equipped := false

	if FileAccess.file_exists(draft_path):
		var draft_raw: Variant = _read_json_file(draft_path)
		if typeof(draft_raw) == TYPE_DICTIONARY:
			var draft_data: Dictionary = draft_raw
			css_text = String(draft_data.get("css_text", ""))
			svg_text = String(draft_data.get("svg_text", ""))
			updated_at = String(draft_data.get("updated_at", ""))

	if FileAccess.file_exists(profile_path):
		var profile_raw: Variant = _read_json_file(profile_path)
		if typeof(profile_raw) == TYPE_DICTIONARY:
			var profile_data: Dictionary = profile_raw
			bullet_equipped = true
			if updated_at == "":
				updated_at = String(profile_data.get("updated_at", ""))
			if css_text == "":
				css_text = String(profile_data.get("css_text", ""))
			if svg_text == "":
				svg_text = String(profile_data.get("svg_text", ""))

	base_payload["bullet_equipped"] = bullet_equipped
	base_payload["updated_at"] = updated_at
	if css_text != "":
		base_payload["css_text"] = css_text
	if svg_text != "":
		base_payload["svg_text"] = svg_text
	return base_payload

func _hydrate_web_editor(payload: Dictionary) -> void:
	if payload.is_empty() or not web.has_method("eval"):
		return
	var js := "hydrateFromGodot(%s);" % JSON.stringify(payload)
	web.call_deferred("eval", js)

func _extract_css_rules(text: String) -> PackedStringArray:
	var rules := PackedStringArray()
	for chunk in text.split(";"):
		var pair := chunk.strip_edges()
		if pair == "":
			continue
		var idx := pair.find(":")
		if idx == -1:
			continue
		var key := pair.substr(0, idx).strip_edges().to_lower()
		if key != "":
			rules.append(key)
	return rules

func _get_css_affinity_singleton() -> Node:
	return get_tree().root.get_node_or_null("CssAffinity")

func _get_css_unlocks_singleton() -> Node:
	return get_tree().root.get_node_or_null("CssUnlocks")

func _parse_relevant_properties_from_singleton(css_text: String) -> Dictionary:
	var singleton := _get_css_affinity_singleton()
	if singleton != null and singleton.has_method("parse_relevant_properties"):
		var parsed: Variant = singleton.call("parse_relevant_properties", css_text)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return {}

func _get_locked_properties_from_singleton(css_text: String) -> PackedStringArray:
	var singleton := _get_css_unlocks_singleton()
	if singleton != null and singleton.has_method("get_locked_properties_from_css"):
		var locked: Variant = singleton.call("get_locked_properties_from_css", css_text)
		if locked is PackedStringArray:
			return locked
		if locked is Array:
			return PackedStringArray(locked)
	return PackedStringArray()

func _get_unlock_state_from_singleton() -> Dictionary:
	var singleton := _get_css_unlocks_singleton()
	if singleton != null and singleton.has_method("get_unlock_state"):
		var state: Variant = singleton.call("get_unlock_state")
		if typeof(state) == TYPE_DICTIONARY:
			return state
	return {}

func _get_all_properties_from_singleton() -> PackedStringArray:
	var singleton := _get_css_unlocks_singleton()
	if singleton != null and singleton.has_method("get_all_properties"):
		var all_props: Variant = singleton.call("get_all_properties")
		if all_props is PackedStringArray:
			return all_props
		if all_props is Array:
			return PackedStringArray(all_props)
	return PackedStringArray()
