extends StaticBody2D
class_name PuzzleDoor

@export var puzzle_group: StringName = &"puzzle_button"
@export var open_color: Color = Color(0.35, 1.0, 0.35, 0.35)
@export var closed_color: Color = Color(0.5, 0.2, 0.8, 1.0)

var is_open: bool = false

@onready var visual: Polygon2D = $DoorVisual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("puzzle_door")
	_register_button_signals()
	_evaluate_open_condition()

func _register_button_signals() -> void:
	for button in get_tree().get_nodes_in_group(puzzle_group):
		if button.has_signal("puzzle_button_destroyed"):
			if not button.puzzle_button_destroyed.is_connected(_on_button_destroyed):
				button.puzzle_button_destroyed.connect(_on_button_destroyed)

func _on_button_destroyed(_button: Node) -> void:
	_evaluate_open_condition()

func _evaluate_open_condition() -> void:
	var alive_count := 0
	for node in get_tree().get_nodes_in_group(puzzle_group):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			alive_count += 1

	if alive_count == 0:
		_open_door()
	else:
		_close_door()

func _open_door() -> void:
	if is_open:
		return
	is_open = true
	collision_shape.disabled = true
	visual.color = open_color

func _close_door() -> void:
	if not is_open:
		visual.color = closed_color
		return
	is_open = false
	collision_shape.disabled = false
	visual.color = closed_color
