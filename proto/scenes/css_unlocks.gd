extends Node

# Sistema de progreso de propiedades CSS desbloqueadas.
# - Si una propiedad está bloqueada, sigue escribiéndose en el CSS
#   pero no aporta bonus de combate.
# - El estado se persiste en user://progress/css_unlocks.json

const SAVE_PATH := "user://progress/css_unlocks.json"
const MAIN_PROPERTIES := PackedStringArray([
	"background",
	"background-color",
	"color",
	"border",
	"border-color",
	"border-radius",
	"box-shadow",
	"text-shadow",
	"outline-color",
	"width",
	"height",
	"opacity",
	"transform",
	"filter"
])

# Propiedades mínimas desbloqueadas al iniciar una partida nueva.
const DEFAULT_UNLOCKED := {
	"background": true,
	"background-color": true,
	"width": true,
	"height": true,
	"border-radius": true
}

var _unlock_state: Dictionary = {}

func _ready() -> void:
	_load_state()

func get_all_properties() -> PackedStringArray:
	return MAIN_PROPERTIES.duplicate()

func get_unlock_state() -> Dictionary:
	return _unlock_state.duplicate(true)

func is_property_unlocked(raw_property: String) -> bool:
	var key := _normalize_property(raw_property)
	return bool(_unlock_state.get(key, false))

func set_property_unlocked(raw_property: String, enabled: bool) -> void:
	var key := _normalize_property(raw_property)
	if key == "":
		return
	_unlock_state[key] = enabled
	_save_state()

func set_many_unlocks(changes: Dictionary) -> void:
	for raw_key in changes.keys():
		var key := _normalize_property(String(raw_key))
		if key == "":
			continue
		_unlock_state[key] = bool(changes[raw_key])
	_save_state()

func filter_unlocked_properties(css_properties: Dictionary) -> Dictionary:
	var filtered := {}
	for raw_key in css_properties.keys():
		var key := _normalize_property(String(raw_key))
		if is_property_unlocked(key):
			filtered[key] = css_properties[raw_key]
	return filtered

func get_locked_properties_from_css(css_text: String) -> PackedStringArray:
	var locked := PackedStringArray()
	for raw_key in _extract_keys(css_text):
		var key := _normalize_property(raw_key)
		if key != "" and not is_property_unlocked(key) and not locked.has(key):
			locked.append(key)
	return locked

func _normalize_property(raw_property: String) -> String:
	var key := raw_property.strip_edges().to_lower()
	if key == "background":
		return "background-color"
	return key

func _load_state() -> void:
	_unlock_state.clear()
	for prop in MAIN_PROPERTIES:
		var normalized := _normalize_property(prop)
		_unlock_state[normalized] = bool(DEFAULT_UNLOCKED.get(normalized, false))

	if not FileAccess.file_exists(SAVE_PATH):
		_save_state()
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	for raw_key in parsed.keys():
		var key := _normalize_property(String(raw_key))
		if key == "":
			continue
		_unlock_state[key] = bool(parsed[raw_key])

func _save_state() -> void:
	var dir_path := "user://progress"
	var mkdir_err := DirAccess.make_dir_recursive_absolute(dir_path)
	if mkdir_err != OK and mkdir_err != ERR_ALREADY_EXISTS:
		push_warning("[CssUnlocks] No se pudo crear directorio progress. err=%s" % mkdir_err)
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[CssUnlocks] No se pudo guardar estado de desbloqueos")
		return
	file.store_string(JSON.stringify(_unlock_state, "\t"))
	file.flush()

func _extract_keys(css_text: String) -> PackedStringArray:
	var keys := PackedStringArray()
	for chunk in css_text.split(";"):
		var pair := chunk.strip_edges()
		if pair == "":
			continue
		var idx := pair.find(":")
		if idx == -1:
			continue
		var key := _normalize_property(pair.substr(0, idx).strip_edges().to_lower())
		if key != "":
			keys.append(key)
	return keys
