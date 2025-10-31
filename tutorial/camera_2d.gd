extends Camera2D

@export var object_to_follow:Node2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if object_to_follow:
		position = object_to_follow.position
	pass
