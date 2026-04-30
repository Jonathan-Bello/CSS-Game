extends Node

func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Quantico", "Orbitron", "Rajdhani", "Segoe UI", "Arial"])
	ThemeDB.fallback_font = font
