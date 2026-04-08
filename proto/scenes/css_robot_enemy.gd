extends CharacterBody2D
class_name CssRobotEnemy

@export var speed: float = 90.0
@export var max_health: int = 3
@export var required_css_rules: PackedStringArray = PackedStringArray(["background-color"])

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

func apply_css_bullet_hit(bullet_rules: PackedStringArray, damage: int) -> void:
	if _has_css_match(bullet_rules):
		health -= damage
		robot_sprite.color = Color(1.0, 0.4, 0.4, 1.0)
		_update_label()
		if health <= 0:
			queue_free()
			return
		var tw := create_tween()
		tw.tween_property(robot_sprite, "color", Color(1.0, 0.0, 0.0, 1.0), 0.15)
	else:
		var tw_miss := create_tween()
		tw_miss.tween_property(robot_sprite, "color", Color(0.55, 0.0, 0.0, 1.0), 0.1)
		tw_miss.tween_property(robot_sprite, "color", Color(1.0, 0.0, 0.0, 1.0), 0.12)

func _has_css_match(bullet_rules: PackedStringArray) -> bool:
	for enemy_rule in required_css_rules:
		if bullet_rules.has(enemy_rule.to_lower()):
			return true
	return false

func _update_label() -> void:
	life_label.text = "HP %d | rule: %s" % [health, ", ".join(required_css_rules)]
