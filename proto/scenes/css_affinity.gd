extends Node

# -----------------------------------------------------------------------------
# CssAffinity
# -----------------------------------------------------------------------------
# Este módulo concentra la lógica de:
# 1) Parsear propiedades CSS relevantes para combate.
# 2) Normalizar valores (sobre todo colores).
# 3) Calcular daño final (base / match de propiedad / crítico exacto).
#
# Se usa como singleton/autoload para poder llamarlo desde balas, enemigos y UI.
# -----------------------------------------------------------------------------

const CSS_NAMED_COLORS := {
	"black": "#000000",
	"white": "#ffffff",
	"red": "#ff0000",
	"green": "#008000",
	"blue": "#0000ff",
	"yellow": "#ffff00",
	"cyan": "#00ffff",
	"magenta": "#ff00ff",
	"orange": "#ffa500",
	"purple": "#800080",
	"gray": "#808080",
	"grey": "#808080",
	"pink": "#ffc0cb",
	"brown": "#a52a2a",
	"transparent": "#00000000"
}

const RELEVANT_PROPERTIES := {
	"background": true,
	"background-color": true,
	"color": true,
	"border": true,
	"border-color": true,
	"outline-color": true,
	"box-shadow": true,
	"text-shadow": true
}

# Recorre un texto CSS "key: value; key2: value2;" y se queda únicamente con
# las propiedades que el combate entiende (RELEVANT_PROPERTIES).
static func parse_relevant_properties(css_text: String) -> Dictionary:
	var parsed := {}
	for chunk in css_text.split(";"):
		var pair := chunk.strip_edges()
		if pair == "":
			continue
		var idx := pair.find(":")
		if idx == -1:
			continue
		var key := _normalize_property_name(pair.substr(0, idx).strip_edges().to_lower())
		if not RELEVANT_PROPERTIES.has(key):
			continue
		var value := pair.substr(idx + 1).strip_edges()
		parsed[key] = normalize_property_value(key, value)
	return parsed

# Normaliza el valor de una propiedad a formato comparable.
# Ejemplo:
# - "blue" -> "#0000ff"
# - "rgb(0, 0, 255)" -> "#0000ff"
# - "border: 1px solid red" -> "#ff0000"
static func normalize_property_value(key: String, value: String) -> String:
	if key in ["background", "background-color", "color", "border-color", "outline-color"]:
		var maybe_color := normalize_color(value)
		if maybe_color != "":
			return maybe_color
	if key == "border":
		var border_color := _extract_border_color(value)
		if border_color != "":
			return border_color
	if key in ["box-shadow", "text-shadow"]:
		var shadow_color := _extract_first_shadow_color(value)
		if shadow_color != "":
			return shadow_color
	return value.strip_edges().to_lower()

# Convierte colores de distintos formatos a un string canónico.
static func normalize_color(raw_color: String) -> String:
	var color_value := raw_color.strip_edges().to_lower()
	if color_value == "":
		return ""
	if CSS_NAMED_COLORS.has(color_value):
		color_value = String(CSS_NAMED_COLORS[color_value])

	if color_value.begins_with("#"):
		return _normalize_hex(color_value)

	if color_value.begins_with("rgb"):
		var rgba: Variant = _parse_rgb_string(color_value)
		if rgba == null:
			return ""
		return _to_hex_string(rgba)

	return ""

# Normaliza el diccionario de afinidad del enemigo (claves + valores) para que
# la comparación con la bala sea consistente y sin falsos negativos.
static func normalize_affinity(affinity: Dictionary) -> Dictionary:
	var normalized := {}
	for raw_key in affinity.keys():
		var key := _normalize_property_name(String(raw_key).strip_edges().to_lower())
		if not RELEVANT_PROPERTIES.has(key):
			continue
		normalized[key] = normalize_property_value(key, String(affinity[raw_key]))
	return normalized

# Lógica de daño por afinidad:
# - Si no existe propiedad en bala => daño base.
# - Si existe propiedad pero valor distinto => daño base + property_bonus.
# - Si coincide propiedad y valor exacto => daño base + critical_bonus.
static func compute_damage(bullet_profile: Dictionary, target_affinity: Dictionary) -> Dictionary:
	var base_damage := int(max(1, int(bullet_profile.get("base_damage", bullet_profile.get("damage", 1)))))
	var bullet_properties: Dictionary = bullet_profile.get("properties", {})
	var enemy_properties: Dictionary = normalize_affinity(target_affinity.get("properties", {}))
	var property_bonus := int(target_affinity.get("property_bonus", 1))
	var critical_bonus := int(target_affinity.get("critical_bonus", 4))

	var had_property_match := false
	var had_exact_match := false
	var reason := "No affinity match"

	for raw_prop in enemy_properties.keys():
		var prop := _normalize_property_name(String(raw_prop))
		# Si la propiedad no está desbloqueada para el jugador, no da bonus.
		if not _is_property_unlocked(prop):
			continue
		if not bullet_properties.has(prop):
			continue
		had_property_match = true
		var bullet_value := normalize_property_value(prop, String(bullet_properties[prop]))
		var enemy_value := String(enemy_properties[prop])
		if bullet_value != "" and bullet_value == enemy_value:
			had_exact_match = true
			reason = "Critical match: %s=%s" % [prop, enemy_value]
			break
		if reason == "No affinity match":
			reason = "Property match: %s" % prop

	var final_damage := base_damage
	var level := "none"
	if had_exact_match:
		final_damage = base_damage + critical_bonus
		level = "high"
	elif had_property_match:
		final_damage = base_damage + property_bonus
		level = "medium"

	return {
		"damage": final_damage,
		"multiplier": float(final_damage) / float(max(1, base_damage)),
		"level": level,
		"reason": reason,
		"matched": had_property_match,
		"critical": had_exact_match
	}

# Unifica aliases de propiedades.
static func _normalize_property_name(raw_key: String) -> String:
	if raw_key == "background":
		return "background-color"
	return raw_key

# Intenta extraer color dentro de la definición de borde.
static func _extract_border_color(value: String) -> String:
	for token in value.split(" "):
		var maybe_color := normalize_color(token)
		if maybe_color != "":
			return maybe_color
	return ""

# Intenta extraer el primer color dentro de box-shadow/text-shadow.
static func _extract_first_shadow_color(value: String) -> String:
	for token in value.split(" "):
		var maybe_color := normalize_color(token)
		if maybe_color != "":
			return maybe_color
	return ""

# Normaliza hex corto (#0af) y acepta hex largo (#00aaff / #00aaffcc).
static func _normalize_hex(value: String) -> String:
	var compact := value.strip_edges().to_lower()
	if compact.length() == 4:
		return "#%s%s%s" % [compact[1] + compact[1], compact[2] + compact[2], compact[3] + compact[3]]
	if compact.length() == 7 or compact.length() == 9:
		return compact
	return ""

# Convierte "rgb(...)" / "rgba(...)" a Color.
static func _parse_rgb_string(value: String):
	var start := value.find("(")
	var end := value.find(")")
	if start == -1 or end == -1 or end <= start:
		return null
	var numbers := value.substr(start + 1, end - start - 1).split(",")
	if numbers.size() < 3:
		return null
	var r := clampf(float(numbers[0].strip_edges()), 0.0, 255.0) / 255.0
	var g := clampf(float(numbers[1].strip_edges()), 0.0, 255.0) / 255.0
	var b := clampf(float(numbers[2].strip_edges()), 0.0, 255.0) / 255.0
	var a := 1.0
	if numbers.size() > 3:
		a = clampf(float(numbers[3].strip_edges()), 0.0, 1.0)
	return Color(r, g, b, a)

# Convierte Color a string hexadecimal estable.
static func _to_hex_string(color: Color) -> String:
	if color.a < 1.0:
		return "#%02x%02x%02x%02x" % [
			int(round(color.r * 255.0)),
			int(round(color.g * 255.0)),
			int(round(color.b * 255.0)),
			int(round(color.a * 255.0))
		]
	return "#%02x%02x%02x" % [
		int(round(color.r * 255.0)),
		int(round(color.g * 255.0)),
		int(round(color.b * 255.0))
	]

static func _is_property_unlocked(prop: String) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return true
	var unlocks := tree.root.get_node_or_null("CssUnlocks")
	if unlocks == null:
		return true
	if unlocks.has_method("is_property_unlocked"):
		return bool(unlocks.call("is_property_unlocked", prop))
	return true
