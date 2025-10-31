extends Control

@onready var panel: PanelContainer = $PanelContainer
@onready var web: Control = $PanelContainer/WebView  # WebView es hijo de PanelContainer (tu caso)

@export var window_size: Vector2 = Vector2(900, 600)
@export var content_padding: int = 8

func _ready() -> void:
	add_to_group("web_overlay")   # ← asegúrate de que el grupo esté en el Control, NO en el WebView
	visible = false
	panel.visible = false
	web.visible = false

	# Estado inicial seguro (evita el 0x80070057)
	web.set("url", "about:blank")
	web.set("transparent", true)
	web.set("devtools", true)

	if not web.is_connected("ipc_message", Callable(self, "_on_web_ipc_message")):
		web.connect("ipc_message", Callable(self, "_on_web_ipc_message"))

	_layout_and_sync()
	print("[WebOverlay] READY. panel=", panel.get_path(), " web=", web.get_path())

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
	print("[WebOverlay] sync rect: panel.pos=", panel.position, " panel.size=", panel.size, " web.size=", web.size)

func open() -> void:
	print("[WebOverlay] open()")
	visible = true
	panel.visible = true
	web.visible = true

	await get_tree().process_frame
	_layout_and_sync()
	_load_editor_html()
	web.call_deferred("focus")
	print("[WebOverlay] open -> HTML cargado, focus defer")

func close() -> void:
	print("[WebOverlay] close()")
	web.visible = false
	web.set("html", "")
	web.set("url", "about:blank")
	panel.visible = false
	visible = false

func _input(ev: InputEvent) -> void:
	if visible and ev.is_action_pressed("ui_cancel"):
		print("[WebOverlay] ESC -> close()")
		close()

func _load_editor_html() -> void:
	print("[WebOverlay] load_html()…")
	var html := "<!doctype html><html><body style='margin:0;color:white;background:transparent'><h3>Editor</h3><script>ipc.postMessage('html_loaded')</script></body></html>"
	web.call("load_html", html)

func _on_web_ipc_message(msg: String) -> void:
	print("[WebOverlay] ipc_message: ", msg)
	if msg == "close":
		close()
	elif msg == "html_loaded":
		print("[WebOverlay] HTML cargado OK")
