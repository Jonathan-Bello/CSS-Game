extends CharacterBody2D
class_name CssRobotEnemy

@export var speed: float = 90.0
@export var max_health: int = 10
# Afinidad editable desde inspector:
# - properties: propiedades/valores CSS a los que reacciona el enemigo.
# - property_bonus: daño adicional por match de propiedad.
# - critical_bonus: daño adicional por match exacto propiedad+valor.
@export var css_affinity: Dictionary = {
	"properties": {
		"background-color": "blue"
	},
	"property_bonus": 1,
	"critical_bonus": 4
}
# Hook opcional para afinidades avanzadas compartidas mediante Resource.
@export var affinity_resource: Resource

var health: int
var move_dir: float = -1.0

@onready var robot_sprite: Polygon2D = $RobotSprite
@onready var life_label: Label = $LifeLabel

func _ready() -> void:
	health = max_health
	_update_label()

func _physics_process(delta: float) -> void:
	velocity.x = move_dir * speed
	move_and_slide()
	if is_on_wall():
		move_dir *= -1.0

func apply_css_bullet_hit(bullet_profile: Dictionary) -> void:
	# Resolver afinidad final (inspector + override por resource).
	var full_affinity := _resolve_affinity()
	# Delegar cálculo de daño a CssAffinity para mantener lógica centralizada.
	var result := CssAffinity.compute_damage(bullet_profile, full_affinity)
	var final_damage := int(result.get("damage", 0))
	if final_damage > 0:
		health -= final_damage
	_apply_hit_feedback(String(result.get("level", "none")))
	_update_label(String(result.get("reason", "")), final_damage)

	if health <= 0:
		queue_free()

# Fusiona configuración local con la que entregue el recurso externo.
func _resolve_affinity() -> Dictionary:
	var resolved := css_affinity.duplicate(true)
	if affinity_resource != null and affinity_resource.has_method("get_affinity_dictionary"):
		var from_resource: Variant = affinity_resource.call("get_affinity_dictionary")
		if typeof(from_resource) == TYPE_DICTIONARY:
			resolved.merge(from_resource, true)
	return resolved

# Feedback visual según nivel de impacto.
func _apply_hit_feedback(level: String) -> void:
	var target := Color(0.55, 0.0, 0.0, 1.0)
	if level == "high":
		target = Color(1.0, 0.75, 0.25, 1.0)
	elif level == "medium":
		target = Color(1.0, 0.35, 0.35, 1.0)

	var tw := create_tween()
	tw.tween_property(robot_sprite, "color", target, 0.09)
	tw.tween_property(robot_sprite, "color", Color(1.0, 0.0, 0.0, 1.0), 0.14)

# Texto de depuración de vida y motivo del último impacto.
func _update_label(reason: String = "", damage: int = 0) -> void:
	var affinity_summary := "affinity: none"
	var properties: Dictionary = css_affinity.get("properties", {})
	if not properties.is_empty():
		affinity_summary = "affinity: %s" % JSON.stringify(properties)
	life_label.text = "HP %d | dmg:%d | %s | %s" % [health, damage, affinity_summary, reason]
