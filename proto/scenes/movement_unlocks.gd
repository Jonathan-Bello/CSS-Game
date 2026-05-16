extends Node

# Sistema de progreso de habilidades de movimiento del jugador.
# - Si una habilidad está bloqueada, el jugador no puede usar esa mecánica.
# - El estado se persiste en user://progress/movement_unlocks.json

const SAVE_PATH := "user://progress/movement_unlocks.json"
const ABILITY_DASH := "dash"
const ABILITY_DOUBLE_JUMP := "double_jump"

var ALL_ABILITIES: PackedStringArray = PackedStringArray([
	ABILITY_DASH,
	ABILITY_DOUBLE_JUMP,
])

# En una partida nueva arrancan bloqueadas.
const DEFAULT_UNLOCKED := {
	ABILITY_DASH: false,
	ABILITY_DOUBLE_JUMP: false,
}

var _unlock_state: Dictionary = {}

func _ready() -> void:
	_load_state()

func get_all_abilities() -> PackedStringArray:
	return ALL_ABILITIES.duplicate()

func get_unlock_state() -> Dictionary:
	return _unlock_state.duplicate(true)

func has_ability(raw_ability: String) -> bool:
	var key := _normalize_ability(raw_ability)
	return bool(_unlock_state.get(key, false))

func unlock_ability(raw_ability: String) -> void:
	set_ability_unlocked(raw_ability, true)

func lock_ability(raw_ability: String) -> void:
	set_ability_unlocked(raw_ability, false)

func set_ability_unlocked(raw_ability: String, enabled: bool) -> void:
	var key := _normalize_ability(raw_ability)
	if key == "":
		return
	_unlock_state[key] = enabled
	_save_state()

func unlock_many(ability_list: PackedStringArray) -> void:
	for raw_ability in ability_list:
		var key := _normalize_ability(raw_ability)
		if key == "":
			continue
		_unlock_state[key] = true
	_save_state()

func lock_many(ability_list: PackedStringArray) -> void:
	for raw_ability in ability_list:
		var key := _normalize_ability(raw_ability)
		if key == "":
			continue
		_unlock_state[key] = false
	_save_state()

func _normalize_ability(raw_ability: String) -> String:
	var key := raw_ability.strip_edges().to_lower()
	if key == "doublejump":
		return ABILITY_DOUBLE_JUMP
	return key

func _load_state() -> void:
	_unlock_state.clear()
	for ability in ALL_ABILITIES:
		var normalized := _normalize_ability(ability)
		_unlock_state[normalized] = bool(DEFAULT_UNLOCKED.get(normalized, false))

	if not FileAccess.file_exists(SAVE_PATH):
		_save_state()
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	for raw_key in parsed.keys():
		var key := _normalize_ability(String(raw_key))
		if key == "":
			continue
		_unlock_state[key] = bool(parsed[raw_key])

func _save_state() -> void:
	var dir_path := "user://progress"
	var mkdir_err := DirAccess.make_dir_recursive_absolute(dir_path)
	if mkdir_err != OK and mkdir_err != ERR_ALREADY_EXISTS:
		push_warning("[MovementUnlocks] No se pudo crear directorio progress. err=%s" % mkdir_err)
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[MovementUnlocks] No se pudo guardar estado de desbloqueos")
		return
	file.store_string(JSON.stringify(_unlock_state, "\t"))
	file.flush()
