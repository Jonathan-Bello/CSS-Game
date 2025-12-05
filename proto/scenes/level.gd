extends Node2D

@export var checkpoint_group_name: StringName = &"checkpoint_areas"
@export var trap_group_name: StringName = &"trap_areas"
@export var player_path: NodePath = ^"Player"
@export var boss_trigger_path: NodePath = ^"GameplayAreas/BossTrigger"
@export var boss_door_path: NodePath = ^"GameplayAreas/BossDoor"
@export var boss_door_shape_path: NodePath = ^"CollisionShape2D"

var current_checkpoint: Vector2

@onready var player: Node2D = get_node(player_path)
@onready var camera: Camera2D = player.get_node_or_null("Camera2D")
@onready var boss_trigger: Area2D = get_node_or_null(boss_trigger_path)
@onready var boss_door: Node = get_node_or_null(boss_door_path)
@onready var boss_door_shape: CollisionShape2D = boss_door.get_node_or_null(boss_door_shape_path) if boss_door else null

func _ready() -> void:
        current_checkpoint = player.global_position
        _setup_camera_limits()
        _connect_areas()
        _prepare_boss_door()

func _setup_camera_limits() -> void:
        if camera == null:
                return
        camera.limit_left = -1200
        camera.limit_right = 3600
        camera.limit_top = -400
        camera.limit_bottom = 900

func _connect_areas() -> void:
        for checkpoint in get_tree().get_nodes_in_group(checkpoint_group_name):
                if not checkpoint.is_connected("body_entered", Callable(self, "_on_checkpoint_entered")):
                        checkpoint.connect("body_entered", Callable(self, "_on_checkpoint_entered").bind(checkpoint))
        for trap in get_tree().get_nodes_in_group(trap_group_name):
                if not trap.is_connected("body_entered", Callable(self, "_on_trap_entered")):
                        trap.connect("body_entered", Callable(self, "_on_trap_entered").bind(trap))
        if boss_trigger and not boss_trigger.is_connected("body_entered", Callable(self, "_on_boss_trigger")):
                boss_trigger.connect("body_entered", Callable(self, "_on_boss_trigger"))

func _prepare_boss_door() -> void:
        if boss_door_shape:
                boss_door_shape.disabled = true

func _on_checkpoint_entered(body: Node, checkpoint: Area2D) -> void:
        if not body.is_in_group("player"):
                return
        current_checkpoint = checkpoint.global_position

func _on_trap_entered(body: Node, _trap: Area2D) -> void:
        if not body.is_in_group("player"):
                return
        body.global_position = current_checkpoint
        if "velocity" in body:
                body.velocity = Vector2.ZERO
        if body.has_method("reset_state"):
                body.call("reset_state")

func _on_boss_trigger(body: Node) -> void:
        if not body.is_in_group("player"):
                return
        _close_boss_door()
        boss_trigger.monitoring = false

func _close_boss_door() -> void:
        if boss_door_shape:
                boss_door_shape.disabled = false
