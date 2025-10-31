class_name Enemigo
extends Node2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
const BALA = preload("uid://gxol7n07h5vq")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func launch_barrel():
	# crear bala
	var instancia_barril = BALA.instantiate() 
	# colocarla en mano
	instancia_barril.position = $CharacterRoundRed/CharacterHandRed.position
	add_child(instancia_barril)
	animation_player.play("reposo")


func _on_timer_timeout() -> void:
	animation_player.play("ataque")
	pass # Replace with function body.
