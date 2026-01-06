# res://player/CssFollower.gd
extends Node2D
class_name CssFollower

@export var spacing: Vector2 = Vector2(22, 0)

func _ready() -> void:
	if owner and owner.has_method("_register_follower"):
		owner.call("_register_follower", self)
