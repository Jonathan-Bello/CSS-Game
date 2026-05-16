extends StaticBody2D
class_name PuzzleButton

signal puzzle_button_destroyed(button: PuzzleButton)

@export var max_health: int = 1
@export var css_affinity: Dictionary = {
	"properties": {
		"background-color": "blue"
	},
	"property_bonus": 1,
	"critical_bonus": 4
}
@export var affinity_resource: Resource
@export var solid_color: Color = Color(0.2, 0.5, 0.9, 1.0)
@export var button_texture: Texture2D

var health: int

@onready var sprite: Sprite2D = $Sprite2D
@onready var fallback_visual: Polygon2D = $FallbackVisual

func _ready() -> void:
	health = max_health
	_update_visual()
	add_to_group("puzzle_button")

func apply_css_bullet_hit(bullet_profile: Dictionary) -> void:
	var full_affinity := _resolve_affinity()
	var result := CssAffinity.compute_damage(bullet_profile, full_affinity)

	# Regla especial del puzzle: si no coincide al menos la propiedad,
	# el disparo no hace daño aunque tenga daño base.
	if not bool(result.get("matched", false)):
		return

	var final_damage := int(result.get("damage", 0))
	if final_damage <= 0:
		return

	health -= final_damage
	if health <= 0:
		emit_signal("puzzle_button_destroyed", self)
		queue_free()

func _resolve_affinity() -> Dictionary:
	var resolved := css_affinity.duplicate(true)
	if affinity_resource != null and affinity_resource.has_method("get_affinity_dictionary"):
		var from_resource: Variant = affinity_resource.call("get_affinity_dictionary")
		if typeof(from_resource) == TYPE_DICTIONARY:
			resolved.merge(from_resource, true)
	return resolved

func _update_visual() -> void:
	if button_texture != null:
		sprite.texture = button_texture
		sprite.visible = true
		fallback_visual.visible = false
	else:
		sprite.texture = null
		sprite.visible = false
		fallback_visual.color = solid_color
		fallback_visual.visible = true
