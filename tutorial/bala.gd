class_name bala
extends RigidBody2D

var touched_player = false
const TILE_SPIKE = preload("uid://cte078jbngyi3")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if position.y > 500:
		queue_free()
	pass


func _on_body_entered(body: Node) -> void:	
	if body is Personaje:
		print(touched_player)
		if not touched_player:
			touched_player = true
			$Sprite2D.texture = TILE_SPIKE
			queue_free()
			if body.has_method("damage_received"):
				body.damage_received()
