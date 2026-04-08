extends Area2D
class_name CssBullet

@export var lifetime: float = 3.0

var direction: Vector2 = Vector2.RIGHT
var speed: float = 1200.0
var damage: int = 1
var css_text: String = ""
var css_rules: PackedStringArray = PackedStringArray()

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if css_rules.is_empty() and css_text != "":
		css_rules = _extract_rules(css_text)
	_update_visual_from_css(css_text)
	var timer := get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * speed * delta

func setup_from_css(new_css_text: String, facing: int, new_speed: float, new_damage: int) -> void:
	css_text = new_css_text
	speed = new_speed
	damage = new_damage
	direction = Vector2(float(facing), 0.0)
	css_rules = _extract_rules(css_text)

func _extract_rules(text: String) -> PackedStringArray:
	var rules := PackedStringArray()
	for chunk in text.split(";"):
		var pair := chunk.strip_edges()
		if pair == "":
			continue
		var idx := pair.find(":")
		if idx == -1:
			continue
		var key := pair.substr(0, idx).strip_edges().to_lower()
		if key != "":
			rules.append(key)
	return rules

func _update_visual_from_css(text: String) -> void:
	var rule_map := _extract_rule_map(text)
	var w := int(clamp(rule_map.get("width", 28), 6, 256))
	var h := int(clamp(rule_map.get("height", 16), 6, 256))
	var radius := int(clamp(rule_map.get("border-radius", 0), 0, min(w, h) / 2))
	var color: Color = rule_map.get("background-color", Color(1, 1, 1, 1))

	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(w):
		for y in range(h):
			if _inside_rounded_rect(x, y, w, h, radius):
				img.set_pixel(x, y, color)

	var tex := ImageTexture.create_from_image(img)
	sprite.texture = tex
	sprite.centered = true
	collision.shape.size = Vector2(w, h)

func _extract_rule_map(text: String) -> Dictionary:
	var out := {}
	for chunk in text.split(";"):
		var pair := chunk.strip_edges()
		if pair == "":
			continue
		var idx := pair.find(":")
		if idx == -1:
			continue
		var key := pair.substr(0, idx).strip_edges().to_lower()
		var raw_value := pair.substr(idx + 1).strip_edges()
		out[key] = _parse_css_value(key, raw_value)
	return out

func _parse_css_value(key: String, raw_value: String) -> Variant:
	if key in ["width", "height", "border-radius"]:
		return float(raw_value.replace("px", "").strip_edges())
	if key == "background-color":
		if raw_value.begins_with("#"):
			return Color(raw_value)
		if raw_value.begins_with("rgb"):
			var inside := raw_value.substr(raw_value.find("(") + 1, raw_value.find(")") - raw_value.find("(") - 1)
			var numbers := inside.split(",")
			if numbers.size() >= 3:
				var r := float(numbers[0].strip_edges()) / 255.0
				var g := float(numbers[1].strip_edges()) / 255.0
				var b := float(numbers[2].strip_edges()) / 255.0
				return Color(r, g, b, 1.0)
	return raw_value

func _inside_rounded_rect(x: int, y: int, w: int, h: int, radius: int) -> bool:
	if radius <= 0:
		return true
	if x >= radius and x < w - radius:
		return true
	if y >= radius and y < h - radius:
		return true

	var corners := [
		Vector2(radius, radius),
		Vector2(w - radius - 1, radius),
		Vector2(radius, h - radius - 1),
		Vector2(w - radius - 1, h - radius - 1)
	]
	for c in corners:
		if Vector2(x, y).distance_to(c) <= float(radius):
			return true
	return false

func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if body.has_method("apply_css_bullet_hit"):
		body.call("apply_css_bullet_hit", css_rules, damage)
	queue_free()
