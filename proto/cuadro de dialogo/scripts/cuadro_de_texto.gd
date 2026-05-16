extends CanvasLayer

@export_multiline var textos : Array[String]

var iterar =0

func _ready():
	iniciar_dialogo()

func show_text (txt: String):
	show()
	$"color cuadro tex/Label".hide()
	get_tree().paused = true
	$"color cuadro tex/texto".text =txt
	$"animacion cuadro de textois".play("texto")

func iniciar_dialogo ():
	show_text(textos[iterar])

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cambio cuadro de diaologo"):
		iterar += 1
		if iterar >= textos.size():
			get_tree().paused = false
			hide()
			iterar = 0
		show_text(textos[iterar])

func _on_animacion_cuadro_de_textois_animation_finished(anim_name: StringName) -> void:
	if anim_name == "texto":
		$"animacion cuadro de textois".play("texto cuadro continuar")
