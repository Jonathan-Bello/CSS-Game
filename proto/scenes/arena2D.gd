extends Area2D

@export var overlay_path: NodePath = ^"../Player/Camera2D/Control"
@export var player_group: StringName = &"player"

var overlay: Node = null

func _ready() -> void:
	print("[CssTerminal] READY overlay_path=", overlay_path)
	var n := get_node_or_null(overlay_path)
	if n == null:
		n = get_tree().get_first_node_in_group("web_overlay")
	# Sube por los padres hasta encontrar uno con open()
	overlay = _find_overlay_node(n)
	if overlay:
		var scr: Script = overlay.get_script() as Script
		var scr_path: String = scr.resource_path if scr != null else "<sin script>"
		print("[CssTerminal] overlay FINAL -> ", overlay.get_path(),
			" class=", overlay.get_class(), " has_open?=", overlay.has_method("open"),
			" script.path=", scr_path)
	else:
		push_warning("[CssTerminal] No pude resolver overlay. Revisa overlay_path o el grupo 'web_overlay'.")

	if not is_connected("body_entered", Callable(self, "_on_body_entered")):
		connect("body_entered", Callable(self, "_on_body_entered"))

func _find_overlay_node(start: Node) -> Node:
	var p := start
	while p != null:
		if p.has_method("open"):
			return p
		p = p.get_parent()
	return null

func _on_body_entered(body: Node) -> void:
	print("[CssTerminal] body_entered: ", body.name, " groups=", body.get_groups())
	if body.is_in_group(player_group) and overlay:
		print("[CssTerminal] → overlay.open() en ", overlay.get_path())
		overlay.call("open")
