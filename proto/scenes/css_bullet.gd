extends Area2D
class_name CssBullet

@export var lifetime: float = 3.0

var direction: Vector2 = Vector2.RIGHT
var speed: float = 1200.0
var damage: int = 1
var css_text: String = ""
var css_rules: PackedStringArray = PackedStringArray()
var texture_path: String = ""
var texture_size: Vector2 = Vector2(28, 16)

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if css_rules.is_empty() and css_text != "":
		css_rules = _extract_rules(css_text)
	if not _try_apply_texture_from_path(texture_path):
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
	texture_path = ""

func setup_from_profile(profile: Dictionary, facing: int, new_speed: float, new_damage: int) -> void:
	css_text = String(profile.get("css_text", ""))
	speed = new_speed
	damage = new_damage
	direction = Vector2(float(facing), 0.0)
	css_rules = _extract_rules(css_text)
	if profile.has("css_rules"):
		var explicit_rules := PackedStringArray()
		for raw_rule in Array(profile.get("css_rules", [])):
			var normalized := String(raw_rule).strip_edges().to_lower()
			if normalized != "":
				explicit_rules.append(normalized)
		if not explicit_rules.is_empty():
			css_rules = explicit_rules
	texture_path = String(profile.get("sprite_path", profile.get("image_path", "")))
	var meta: Dictionary = profile.get("meta", {})
	texture_size = Vector2(
		float(meta.get("w", 28)),
		float(meta.get("h", 16))
	)

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
	_apply_collision_size(Vector2(w, h))

func _try_apply_texture_from_path(path: String) -> bool:
	if path == "":
		return false
	if not FileAccess.file_exists(path):
		push_warning("[CssBullet] No existe textura de bala: %s" % path)
		return false

	var image := Image.new()
	if image.load(path) != OK:
		push_warning("[CssBullet] No se pudo cargar textura de bala: %s" % path)
		return false

	var tex := ImageTexture.create_from_image(image)
	sprite.texture = tex
	sprite.centered = true
	var hitbox_size := texture_size
	if hitbox_size.x <= 0.0 or hitbox_size.y <= 0.0:
		hitbox_size = Vector2(image.get_width(), image.get_height())
	_apply_collision_size(hitbox_size)
	return true

func _apply_collision_size(size: Vector2) -> void:
	if collision and collision.shape and collision.shape is RectangleShape2D:
		var rect_shape := collision.shape as RectangleShape2D
		rect_shape.size = Vector2(
			clamp(size.x, 6.0, 512.0),
			clamp(size.y, 6.0, 512.0)
		)

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
