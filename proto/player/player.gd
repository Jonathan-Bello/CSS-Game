extends CharacterBody2D
# ============================================================================
# Player Controller 2D (estilo Hollow Knight) — DOCUMENTADO
#
# Qué hace:
# - Movimiento horizontal con aceleración/rozamiento suelo/aire.
# - Salto con coyote + buffer + salto variable (al soltar) + apex-hang + fast-fall.
# - Doble salto (opcional).
# - Dash “parabólico” (impulso X + leve impulso Y).
# - Wall slide / wall jump usando UN RayCast2D (no lo movemos por código).
# - Ataque frontal con Area2D (hooks listos para up/down).
# - Debug por Labels (estado/velocidad/flags).
#
# Requisitos en Input Map:
#   move_left, move_right, move_down, jump, dash, attack
#
# Árbol de nodos esperado (ajústalo si usas otros nombres):
#   Player
#     ├─ CollisionShape2D (tu cuerpo)
#     ├─ Skeleton2D
#     │    └─ AnimationPlayer         (animaciones: idle, run, jump, fall, dash, wall_slide, wall_jump, attack)
#     ├─ hitboxes
#     │    ├─ wall_probe : RayCast2D  (APUNTANDO “AL FRENTE”, Enabled ON, máscara correcta)
#     │    └─ atackArea  : Area2D     (CollisionShape2D con hitbox del golpe)
#     └─ debug
#          ├─ lbl_state : Label
#          ├─ lbl_vel   : Label
#          └─ lbl_flags : Label
# ============================================================================


# ─────────────────────────────────────────────────────────
# GRUPOS DE EXPORTS (para orden en el Inspector)
# ─────────────────────────────────────────────────────────
@export_group("Movimiento — Horizontal")
## Velocidad máxima en X.
@export var MAX_SPEED: float = 1000.0
## Aceleración en suelo.
@export var ACCEL_GROUND: float = 8000.0
## Desaceleración en suelo (fricción).
@export var DECEL_GROUND: float = 9000.0
## Aceleración en aire.
@export var ACCEL_AIR: float = 6000.0
## Desaceleración en aire.
@export var DECEL_AIR: float = 5000.0
## Umbral para considerar “corriendo” (para FSM/anims).
@export var RUN_THRESHOLD: float = 10.0
## Zona muerta para sticks (como en el script que pasaste).
@export var STICK_DEAD_ZONE: float = 0.5

@export_group("Salto y Gravedad — HK-like")
## Gravedad base (se escalará según estado).
@export var GRAVITY: float = 3800.0
## Límite de velocidad de caída.
@export var MAX_FALL_SPEED: float = 2800.0
## Velocidad vertical del salto (negativa = subir).
@export var JUMP_VELOCITY: float = -1500.0
## “Coyote time”: margen tras dejar el suelo para aún poder saltar.
@export var COYOTE_TIME: float = 0.09
## Buffer de entrada: si presionas salto un pelín antes de tocar el suelo.
@export var JUMP_BUFFER_TIME: float = 0.12
## Caída más pesada que el ascenso.
@export var FALL_MULTIPLIER: float = 1.9
## Cortar salto al soltar botón.
@export var LOW_JUMP_MULTIPLIER: float = 2.4
## Fast-fall al mantener abajo durante la caída.
@export var FAST_FALL_MULTIPLIER: float = 2.6
## Umbral de ápice (zona donde “flota” un poquito).
@export var APEX_THRESHOLD: float = 120.0
## Escala de gravedad en el ápice.
@export var APEX_GRAVITY_SCALE: float = 0.85

@export_group("Doble Salto")
## Habilita/Deshabilita.
@export var ENABLE_DOUBLE_JUMP: bool = true
## Fuerza del segundo salto.
@export var DOUBLE_JUMP_VELOCITY: float = -1000.0

@export_group("Dash — Parabólico")
## Impulso horizontal del dash.
@export var DASH_SPEED: float = 1400.0
## Impulso vertical (normalmente negativo para levantar un poco).
@export var DASH_UP_VELOCITY: float = -500.0
## Duración del “estado dash” (afecta control/anim).
@export var DASH_TIME: float = 0.18
## Enfriamiento entre dashes.
@export var DASH_COOLDOWN: float = 0.20

@export_group("Pared — (RayCast2D orientado en la escena)")
## “Gravedad” durante wall slide (más suave).
@export var WALL_SLIDE_GRAVITY: float = 900.0
## Límite de velocidad de descenso pegado a pared.
@export var WALL_SLIDE_SPEED_MAX: float = 900.0
## Tiempo de bloqueo de control horizontal tras wall jump.
@export var WALL_JUMP_PUSH_TIME: float = 0.10
## Empuje horizontal del wall jump (hacia afuera).
@export var WALL_JUMP_PUSH_FORCE: float = 1000.0
## “Pegajosidad” al soltar dirección (aún te quedas un instante).
@export var WALL_STICK_TIME: float = 0.08
## Coyote desde pared (puedes saltar justo al soltar contacto).
@export var WALL_COYOTE_TIME: float = 0.05

@export_group("Ataque — Frontal (hooks para Up/Down)")
## Duración del ataque (ventana del Area2D).
@export var ATTACK_TIME: float = 0.18
## Pequeña pausa al atacar (sensación de impacto).
@export var ATTACK_KNOCK_PAUSE: float = 0.05

@export_group("Nodos / Paths")
## Nodo gráfico que se voltea (NO el Player): normalmente Skeleton2D.
@export_node_path("Node2D") var gfx_root_path: NodePath = ^"Skeleton2D"
## AnimationPlayer con tus clips.
@export_node_path("AnimationPlayer") var anim_path: NodePath = ^"Skeleton2D/AnimationPlayer"
## RayCast2D que toca la pared (no se mueve por código).
@export_node_path("RayCast2D") var wall_probe_path: NodePath = ^"hitboxes/wall_probe"
## Área de ataque frontal.
@export_node_path("Area2D") var attack_area_path: NodePath = ^"hitboxes/atackArea"
## Hueso del brazo derecho para la pose de disparo.
@export_node_path("Node2D") var shoot_arm_path: NodePath = ^"Skeleton2D/origen/cintura/torso/brazoD"
## Punto de salida del disparo.
@export_node_path("Node2D") var shoot_origin_path: NodePath = ^"Skeleton2D/origen/cintura/torso/brazoD"
## RayCast2D para apuntado hacia el mouse.
@export_node_path("RayCast2D") var aim_raycast_path: NodePath = ^"hitboxes/aim_raycast"

@export_group("Disparo CSS")
@export var bullet_scene: PackedScene = preload("res://proto/scenes/css_bullet.tscn")
@export var bullet_speed: float = 1300.0
@export var bullet_damage: int = 1
@export var bullet_balance_reference_size: Vector2 = Vector2(28, 16)
@export var bullet_speed_min_factor: float = 0.55
@export var bullet_speed_max_factor: float = 1.85
@export var bullet_damage_min_factor: float = 0.6
@export var bullet_damage_max_factor: float = 2.8
# Cadencia base y límites por escala de bala:
# - bala pequeña => cadence menor (dispara más seguido)
# - bala grande  => cadence mayor (dispara más lento)
@export var bullet_cadence_base: float = 0.18
@export var bullet_cadence_min_factor: float = 0.45
@export var bullet_cadence_max_factor: float = 2.0
@export var debug_show_raycast: bool = true

var bullet_profile_path: String = ""
var current_bullet_profile: Dictionary = {}
const DEFAULT_BULLET_CSS_TEXT := "background-color: #ff3b3b; width: 28px; height: 16px; border-radius: 6px;"
var _warned_missing_bullet_profile: bool = false

@export_group("Debug — Labels (opcional)")
@export_node_path("Label") var lbl_state_path: NodePath = ^"debug/lbl_state"
@export_node_path("Label") var lbl_vel_path: NodePath = ^"debug/lbl_vel"
@export_node_path("Label") var lbl_flags_path: NodePath = ^"debug/lbl_flags"


# ─────────────────────────────────────────────────────────
# ESTADOS / ENUMS
# ─────────────────────────────────────────────────────────
enum State {IDLE, RUN, JUMP, FALL, DASH, WALL_SLIDE, ATTACK}
var state: State = State.IDLE
var current_anim: StringName = &"" # guarda el clip actual para evitar replays

# Para futuros ataques dirigidos (UP/DOWN).
enum Direction {FWD, UP, DOWN}


# ─────────────────────────────────────────────────────────
# TIMERS / FLAGS INTERNOS
# ─────────────────────────────────────────────────────────
var time_since_grounded := 0.0 # tiempo desde que dejamos el suelo
var time_since_jump_pressed := 999.0 # para buffer de salto
var can_double_jump := true # si nos queda el 2º salto

# Dash
var dash_cooldown := 0.0
var dash_timer := 0.0

# Pared
var wall_stick_timer := 0.0 # micro “pegajosidad”
var wall_coyote_timer := 0.0 # ventana para saltar tras soltar pared
var last_wall_dir := 0 # -1 pared izq, +1 pared der (para wall coyote)
var wall_jump_lock_timer := 0.0 # bloqueo de control tras wall jump

# Ataque
var attack_timer := 0.0
# Cooldown entre disparos/cadencia real (calculada por tamaño de bala).
var attack_cooldown_timer := 0.0
var lock_controls := false # micro “hit-stop” al atacar


# ─────────────────────────────────────────────────────────
# REFERENCIAS (@onready)
# ─────────────────────────────────────────────────────────
@onready var anim: AnimationPlayer = get_node_or_null(anim_path)
@onready var gfx_root: Node2D = get_node_or_null(gfx_root_path)
@onready var wall_probe: RayCast2D = get_node_or_null(wall_probe_path)
@onready var attack_area: Area2D = get_node_or_null(attack_area_path)
@onready var shoot_arm: Node2D = get_node_or_null(shoot_arm_path)
@onready var shoot_origin: Node2D = get_node_or_null(shoot_origin_path)
@onready var aim_raycast: RayCast2D = get_node_or_null(aim_raycast_path)
@onready var lbl_state: Label = get_node_or_null(lbl_state_path)
@onready var lbl_vel: Label = get_node_or_null(lbl_vel_path)
@onready var lbl_flags: Label = get_node_or_null(lbl_flags_path)


# ============================================================================
# CICLO DE VIDA
# ============================================================================
func _ready() -> void:
	# Consejos de wiring si algo falta:
	if anim == null: push_warning("AnimationPlayer no encontrado en '%s'." % anim_path)
	if gfx_root == null: push_warning("gfx_root no encontrado en '%s'." % gfx_root_path)
	if wall_probe == null: push_warning("RayCast2D wall_probe no encontrado en '%s'." % wall_probe_path)
	if debug_show_raycast and wall_probe:
		# get_tree().debug_collisions_hint = true
		wall_probe.force_raycast_update()
	if shoot_origin == null: push_warning("shoot_origin no encontrado en '%s'." % shoot_origin_path)
	if aim_raycast == null: push_warning("aim_raycast no encontrado en '%s'." % aim_raycast_path)
	if attack_area:
		attack_area.monitoring = false
		attack_area.visible = false
	# Arrancamos en idle
	_play_if_changed(&"idle", true)


func _physics_process(delta: float) -> void:
	_update_aim_raycast()
	# 1) Timers base (suelo, coyote, cooldowns)
	if is_on_floor():
		time_since_grounded = 0.0
		can_double_jump = ENABLE_DOUBLE_JUMP
	else:
		time_since_grounded += delta

	time_since_jump_pressed += delta
	if dash_cooldown > 0.0: dash_cooldown = max(0.0, dash_cooldown - delta)
	if dash_timer > 0.0:
		dash_timer = max(0.0, dash_timer - delta)
		if dash_timer <= 0.0 and state == State.DASH:
			state = State.FALL # termina fase de dash

	if wall_stick_timer > 0.0: wall_stick_timer = max(0.0, wall_stick_timer - delta)
	if wall_coyote_timer > 0.0: wall_coyote_timer = max(0.0, wall_coyote_timer - delta)
	if wall_jump_lock_timer > 0.0: wall_jump_lock_timer = max(0.0, wall_jump_lock_timer - delta)

	if attack_timer > 0.0:
		attack_timer = max(0.0, attack_timer - delta)
		if attack_timer <= 0.0:
			_end_attack()

	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer = max(0.0, attack_cooldown_timer - delta)

	# 2) Entrada del jugador
	var raw_dir := Input.get_axis("move_left", "move_right")
	var dir := _apply_deadzone(raw_dir)
	var want_down := Input.is_action_pressed("move_down")

	# 3) Saltos (coyote+buffer+doble) y dash / ataque
	if not lock_controls:
		_handle_jump_buffer()
		_handle_dash(dir)
		_handle_attack_input()

	# 4) Movimiento horizontal (no durante dash/attack, ni en push lock)
	if state != State.DASH and state != State.ATTACK and wall_jump_lock_timer <= 0.0 and not lock_controls:
		_hmove(dir, delta)

	# 5) Gravedad HK-like
	_apply_gravity(delta, want_down)

	# 6) Lógica de pared usando SOLO el RayCast configurado en la escena
	_update_wall_slide_state(dir)

	# 7) Aplicar física
	move_and_slide()

	# 8) FSM y animaciones
	_update_state()
	_update_animation()

	# 9) Debug
	_debug_draw()


# ============================================================================
# HELPERS DE ENTRADA / ORIENTACIÓN
# ============================================================================
## Aplica zona muerta a sticks/teclas virtuales.
func _apply_deadzone(x: float) -> float:
	return 0.0 if abs(x) < STICK_DEAD_ZONE else sign(x)

## +1 si miras a la derecha, -1 si miras a la izquierda (según gfx_root).
func _facing_sign() -> int:
	return int(sign(gfx_root.scale.x)) if gfx_root else 1


# ============================================================================
# MOVIMIENTO HORIZONTAL (aceleración/rozamiento suelo/aire)
# ============================================================================
func _hmove(dir: float, delta: float) -> void:
	# Flip visual (solo el nodo gráfico, no el Player).
	if dir != 0.0 and gfx_root:
		var s := gfx_root.scale
		s.x = 1.0 if dir > 0.0 else -1.0
		gfx_root.scale = s

	var on_floor := is_on_floor()
	var target := dir * MAX_SPEED
	var acc := ACCEL_GROUND if on_floor else ACCEL_AIR
	var dec := DECEL_GROUND if on_floor else DECEL_AIR

	if dir != 0.0:
		velocity.x = move_toward(velocity.x, target, acc * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, dec * delta)


# ============================================================================
# SALTO (coyote + buffer + variable) y DOBLE SALTO
# ============================================================================
## Gestiona buffer/coyote/doble salto y el corte al soltar el botón.
func _handle_jump_buffer() -> void:
	# Registrar intento de salto (buffer)
	if Input.is_action_just_pressed("jump"):
		time_since_jump_pressed = 0.0

	var can_coyote := time_since_grounded <= COYOTE_TIME
	var has_buffer := time_since_jump_pressed <= JUMP_BUFFER_TIME

	# Salto con coyote+buffer (terreno)
	if has_buffer and can_coyote:
		_do_jump(JUMP_VELOCITY)
		time_since_jump_pressed = 999.0

	# “Coyote desde pared”: permite saltar tras soltar muro
	if has_buffer and wall_coyote_timer > 0.0:
		_wall_jump(last_wall_dir) # usa la última dirección de pared tocada
		time_since_jump_pressed = 999.0

	# Doble salto en aire (si queda)
	if ENABLE_DOUBLE_JUMP and not is_on_floor() and can_double_jump and Input.is_action_just_pressed("jump"):
		_do_jump(DOUBLE_JUMP_VELOCITY)
		can_double_jump = false

	# Salto variable: si suelta el botón durante ascenso, “corta”
	if velocity.y < 0.0 and not Input.is_action_pressed("jump"):
		velocity.y += GRAVITY * (LOW_JUMP_MULTIPLIER - 1.0) * get_physics_process_delta_time()

## Aplica el salto con una velocidad vertical dada.
func _do_jump(vy: float) -> void:
	velocity.y = vy
	state = State.JUMP
	_play_if_changed(&"jump", false)


# ============================================================================
# GRAVEDAD (asimétrica), FAST-FALL y APEX-HANG
# ============================================================================
## Control de caída con multiplicadores estilo HK.
func _apply_gravity(delta: float, want_down: bool) -> void:
	# Durante DASH dejamos que caiga con gravedad normal (parabólico)
	if state == State.DASH:
		velocity.y += GRAVITY * delta
		return

	# En WALL_SLIDE: gravedad reducida + clamp de velocidad
	if state == State.WALL_SLIDE:
		velocity.y = min(velocity.y + WALL_SLIDE_GRAVITY * delta, WALL_SLIDE_SPEED_MAX)
		return

	# En suelo: limpia rebotes
	if is_on_floor():
		if velocity.y > 0.0: velocity.y = 0.0
		return

	var g := GRAVITY
	if velocity.y > 0.0: g *= FALL_MULTIPLIER # caer más pesado
	if want_down and velocity.y > 0.0: g *= FAST_FALL_MULTIPLIER # fast-fall
	if abs(velocity.y) <= APEX_THRESHOLD: g *= APEX_GRAVITY_SCALE # “flotita”

	velocity.y = min(velocity.y + g * delta, MAX_FALL_SPEED)


# ============================================================================
# DASH (impulso X + Y) con tiempo y cooldown
# ============================================================================
func _handle_dash(dir: float) -> void:
	if Input.is_action_just_pressed("dash") and dash_cooldown == 0.0:
		var d := dir if dir != 0.0 else float(_facing_sign())
		_do_dash(d)

## Ejecuta el dash.
func _do_dash(dir_x: float) -> void:
	state = State.DASH
	velocity.x = dir_x * DASH_SPEED
	velocity.y = DASH_UP_VELOCITY
	dash_timer = DASH_TIME
	dash_cooldown = DASH_COOLDOWN
	_play_if_changed(&"dash", false)


# ============================================================================
# WALL SLIDE / WALL JUMP usando SOLO el RayCast de la escena
# ============================================================================
## Si el RayCast está tocando una pared y empujas hacia ella → slide.
## Al soltar, queda una “pegajosidad” (stick) y un coyote desde pared.
func _update_wall_slide_state(dir: float) -> void:
	if wall_probe == null: return
	if state == State.DASH or state == State.ATTACK: return

	var on_front_wall := wall_probe.is_colliding()
	var pushing_front := (dir != 0.0 and int(sign(dir)) == _facing_sign())

	# --- Entrar / mantener el slide ---
	if not is_on_floor() and on_front_wall and pushing_front:
		if state != State.WALL_SLIDE:
			state = State.WALL_SLIDE
			_play_if_changed(&"wall_slide", true)
		last_wall_dir = _facing_sign() # recordamos lado (+1 der, -1 izq)
		wall_coyote_timer = WALL_COYOTE_TIME # refrescamos mientras haya contacto

		# Wall jump directo desde el slide
		if Input.is_action_just_pressed("jump"):
			_wall_jump(last_wall_dir)
		return

	# --- Salir del slide (dejó de empujar o dejó de colisionar) ---
	if state == State.WALL_SLIDE:
		# breve "stick" si SIGUE tocando pared (sensación pegajosa)
		if on_front_wall and wall_stick_timer > 0.0:
			return
		# Al soltar, damos coyote de pared y caemos
		wall_coyote_timer = WALL_COYOTE_TIME
		state = State.FALL


## Aplica el salto desde pared, empujando hacia afuera.
func _wall_jump(wall_dir: int) -> void:
	var push := -wall_dir # empuje hacia afuera
	velocity.x = WALL_JUMP_PUSH_FORCE * push
	velocity.y = JUMP_VELOCITY
	wall_stick_timer = 0.0
	wall_coyote_timer = 0.0
	state = State.JUMP
	wall_jump_lock_timer = WALL_JUMP_PUSH_TIME
	_play_if_changed(&"wall_jump", false)


# ============================================================================
# ATAQUE (frontal) — hooks listos para UP/DOWN
# ============================================================================
func _handle_attack_input() -> void:
	# Evita disparar si aún no vence la cadencia dinámica.
	if Input.is_action_just_pressed("attack") and state != State.ATTACK and state != State.DASH and attack_cooldown_timer <= 0.0:
		# Para futuros ataques dirigidos:
		# if Input.is_action_pressed("move_up"):    _attack(Direction.UP)
		# elif Input.is_action_pressed("move_down"): _attack(Direction.DOWN)
		# else:
		_attack(Direction.FWD)

## Activa el Area2D de ataque según dirección (por ahora frontal).
func _attack(dir: Direction) -> void:
	state = State.ATTACK
	attack_timer = ATTACK_TIME
	velocity.x = 0.0

	if attack_area:
		match dir:
			Direction.FWD:
				attack_area.scale.x = float(_facing_sign())
				attack_area.rotation = 0.0
			Direction.UP:
				attack_area.scale.x = 1.0
				attack_area.rotation = - PI / 2
			Direction.DOWN:
				attack_area.scale.x = 1.0
				attack_area.rotation = PI / 2

		attack_area.monitoring = true
		attack_area.visible = true

	var clip := &"attack"
	if dir == Direction.UP: clip = &"attack_up"
	if dir == Direction.DOWN: clip = &"attack_down"
	_play_if_changed(clip, false)
	_play_shoot_pose()
	# Se calculan stats una sola vez por disparo para consistencia de velocidad,
	# daño y cadencia de esa bala.
	var tuned_stats := _compute_bullet_stats_from_profile()
	attack_cooldown_timer = float(tuned_stats.get("cadence", bullet_cadence_base))
	_spawn_css_bullet(tuned_stats)

	# Pequeño “hit-stop” opcional:
	if ATTACK_KNOCK_PAUSE > 0.0:
		lock_controls = true
		await get_tree().create_timer(ATTACK_KNOCK_PAUSE).timeout
		lock_controls = false

## Finaliza el ataque y limpia el área.
func _end_attack() -> void:
	if attack_area:
		attack_area.monitoring = false
		attack_area.visible = false
	state = State.FALL if not is_on_floor() else State.IDLE

func _spawn_css_bullet(precomputed_stats: Dictionary = {}) -> void:
	if bullet_scene == null:
		return
	var bullet := bullet_scene.instantiate()
	if bullet == null:
		return

	var spawn_pos := global_position
	if shoot_origin:
		spawn_pos = shoot_origin.global_position

	bullet.global_position = spawn_pos
	var aim_direction := _get_aim_direction()
	var facing := 1 if aim_direction.x >= 0.0 else -1
	var tuned_stats := precomputed_stats
	if tuned_stats.is_empty():
		# Fallback por seguridad si no nos pasaron stats precalculados.
		tuned_stats = _compute_bullet_stats_from_profile()
	var tuned_speed: float = tuned_stats.get("speed", bullet_speed)
	var tuned_damage: int = tuned_stats.get("damage", bullet_damage)

	if not current_bullet_profile.is_empty() and bullet.has_method("setup_from_profile"):
		bullet.call("setup_from_profile", current_bullet_profile, facing, tuned_speed, tuned_damage, aim_direction)
	elif bullet.has_method("setup_from_css"):
		var fallback_css := _get_active_bullet_css_text()
		bullet.call("setup_from_css", fallback_css, facing, tuned_speed, tuned_damage, aim_direction)
	elif "direction" in bullet:
		bullet.direction = aim_direction

	get_tree().current_scene.add_child(bullet)

func _play_shoot_pose() -> void:
	if shoot_arm == null:
		return
	var aim_direction := _get_aim_direction()
	var target_rotation: Variant = clamp(aim_direction.angle(), deg_to_rad(-70.0), deg_to_rad(70.0))
	var tw := create_tween()
	tw.tween_property(shoot_arm, "rotation", target_rotation, 0.06)
	tw.tween_property(shoot_arm, "rotation", 0.0, 0.12)

func _update_aim_raycast() -> void:
	if aim_raycast == null:
		return
	var mouse_global := get_global_mouse_position()
	var from := aim_raycast.global_position
	aim_raycast.target_position = mouse_global - from
	aim_raycast.force_raycast_update()

func _get_aim_direction() -> Vector2:
	var from := shoot_origin.global_position if shoot_origin else global_position
	var target := get_global_mouse_position()
	if aim_raycast:
		target = aim_raycast.to_global(aim_raycast.target_position)
		if aim_raycast.is_colliding():
			target = aim_raycast.get_collision_point()
	var direction := target - from
	if direction.length_squared() <= 0.0001:
		return Vector2(float(_facing_sign()), 0.0)
	return direction.normalized()

func equip_bullet_from_profile(profile: Dictionary) -> void:
	if profile.is_empty():
		push_warning("[Player] Perfil de bullet vacío o inválido")
		return

	bullet_profile_path = String(profile.get("profile_path", bullet_profile_path))
	current_bullet_profile = profile.duplicate(true)
	current_bullet_profile["css_text"] = String(current_bullet_profile.get("css_text", ""))
	var runtime_rules := _to_packed_rules(current_bullet_profile.get("css_rules", current_bullet_profile.get("css_properties_used", [])))
	current_bullet_profile["css_rules"] = runtime_rules
	current_bullet_profile["css_properties_used"] = runtime_rules
	current_bullet_profile["damage_base"] = max(1, int(current_bullet_profile.get("damage_base", bullet_damage)))
	_warned_missing_bullet_profile = false

	var absolute_profile_path := ""
	if bullet_profile_path != "":
		absolute_profile_path = ProjectSettings.globalize_path(bullet_profile_path)
	var image_path := String(current_bullet_profile.get("sprite_path", current_bullet_profile.get("image_path", "")))
	var absolute_image_path := ""
	if image_path != "":
		absolute_image_path = ProjectSettings.globalize_path(image_path)
	var tuned_stats := _compute_bullet_stats_from_profile()
	print("[Player] Bullet equipada. profile=%s image=%s reglas=%d speed=%.1f damage=%d" % [
		absolute_profile_path,
		absolute_image_path,
		int(current_bullet_profile.get("css_rules", PackedStringArray()).size()),
		float(tuned_stats.get("speed", bullet_speed)),
		int(tuned_stats.get("damage", bullet_damage))
	])
	print("[Player] Archivos bala -> profile(user://): %s | image(user://): %s" % [
		bullet_profile_path,
		image_path
	])
	
func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _compute_bullet_stats_from_profile() -> Dictionary:
	# Lee tamaño objetivo del profile. El área define el "peso" de la bala.
	var meta: Dictionary = current_bullet_profile.get("meta", {})
	var width := float(meta.get("w", bullet_balance_reference_size.x))
	var height := float(meta.get("h", bullet_balance_reference_size.y))
	width = max(1.0, width)
	height = max(1.0, height)
	var damage_base: int = max(1, int(current_bullet_profile.get("damage_base", bullet_damage)))
	if current_bullet_profile.is_empty() and not _warned_missing_bullet_profile:
		push_warning("[Player] No hay perfil de bala equipado. Se usará CSS por defecto.")
		_warned_missing_bullet_profile = true

	var reference_area: float = max(1.0, bullet_balance_reference_size.x * bullet_balance_reference_size.y)
	var area_ratio: float = (width * height) / reference_area
	var scale_ratio: float = sqrt(area_ratio)
	# Bala pequeña: mayor velocidad. Bala grande: menor velocidad.
	var speed_factor: float = clamp(1.0 / scale_ratio, bullet_speed_min_factor, bullet_speed_max_factor)
	# Bala pequeña: menos daño. Bala grande: más daño.
	var damage_factor: float = clamp(scale_ratio, bullet_damage_min_factor, bullet_damage_max_factor)
	# Bala pequeña: menor cooldown (más cadencia). Bala grande: mayor cooldown.
	var cadence_factor: float = clamp(scale_ratio, bullet_cadence_min_factor, bullet_cadence_max_factor)

	return {
		"speed": bullet_speed * speed_factor,
		"damage": max(1, int(round(float(damage_base) * damage_factor))),
		"cadence": max(0.04, bullet_cadence_base * cadence_factor)
	}

func _get_active_bullet_css_text() -> String:
	var css_text := String(current_bullet_profile.get("css_text", ""))
	if css_text == "":
		return DEFAULT_BULLET_CSS_TEXT
	return css_text

func _to_packed_rules(source: Variant) -> PackedStringArray:
	var rules := PackedStringArray()
	var arr: Array = []
	if source is PackedStringArray:
		arr = Array(source)
	elif source is Array:
		arr = source
	else:
		return rules
	for rule in arr:
		var key := String(rule).strip_edges().to_lower()
		if key != "":
			rules.append(key)
	return rules

# ============================================================================
# FSM básica (elige anim cuando no hay estado dominante)
# ============================================================================
func _update_state() -> void:
	# Aterrizar SIEMPRE gana prioridad
	if is_on_floor():
		state = State.RUN if abs(velocity.x) > RUN_THRESHOLD else State.IDLE
		return

	# En aire: mantenemos estados especiales
	if state == State.DASH or state == State.ATTACK:
		return

	if state == State.WALL_SLIDE:
		# Si se perdió el contacto y ya no hay "stick", caer
		if wall_probe and not wall_probe.is_colliding() and wall_stick_timer <= 0.0:
			state = State.FALL
		return

	# Estado aéreo normal
	state = State.JUMP if velocity.y < 0.0 else State.FALL


# ============================================================================
# ANIMACIONES (AnimationPlayer)
# ============================================================================
func _update_animation() -> void:
	if anim == null: return
	match state:
		State.IDLE: _play_if_changed(&"idle", true)
		State.RUN: _play_if_changed(&"run", true)
		State.JUMP: _play_if_changed(&"jump", false)
		State.FALL: _play_if_changed(&"fall", false)
		State.DASH: _play_if_changed(&"dash", false)
		State.WALL_SLIDE: _play_if_changed(&"wall_slide", true)
		State.ATTACK: pass # el clip ya se eligió en _attack()

## Reproduce una animación sólo si cambió (evita reinicios).
func _play_if_changed(anim_name: StringName, loop: bool = true) -> void:
	if current_anim == anim_name:
		return
	if anim and anim.has_animation(String(anim_name)):
		var a := anim.get_animation(String(anim_name))
		if a:
			a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		anim.play(String(anim_name))
		current_anim = anim_name


# ============================================================================
# DEBUG — Labels
# ============================================================================
func _debug_draw() -> void:
	if lbl_state:
		lbl_state.text = "STATE: %s" % [State.keys()[state]]
	if lbl_vel:
		lbl_vel.text = "VEL: (%.1f, %.1f)" % [velocity.x, velocity.y]
	if lbl_flags:
		var on_wall := wall_probe != null and wall_probe.is_colliding()
		lbl_flags.text = "floor=%s  on_wall=%s  stick=%.2f  wcoyote=%.2f  djump=%s  dash_t=%.2f/cd=%.2f" % [
			str(is_on_floor()),
			str(on_wall),
			wall_stick_timer,
			wall_coyote_timer,
			str(can_double_jump),
			dash_timer, dash_cooldown
		]
