extends Node3D

signal threat_changed(active_count: int)

const UNDEAD := preload("res://enemies/undead.tscn")
const ZOMBIE_VARIANT := preload("res://common/enemy/zombie_variant.gd")
const MAX_ATTEMPTS := 36

@export var enabled := false
@export var stage := 0

var time_until_spawn := 9.0
var remaining_to_spawn := 0
var stage_cell := Vector2i(3, 3)
var boss_mode := false
var boss_cells: Array[Vector2i] = []
var rng := RandomNumberGenerator.new()
var map
var player
var camera: Camera3D
var enemy_container: Node3D

func _ready() -> void:
	rng.randomize()
	map = get_parent().get_node("SectorMap")
	player = get_parent().get_node("Player")
	camera = player.get_node("CameraPivot/CameraHolder/MainCamera")
	enemy_container = get_parent().get_node("Enemies")

func begin_stage(stage_number: int, cell: Vector2i, enemy_count: int) -> void:
	boss_mode = false
	stage = stage_number
	stage_cell = cell
	remaining_to_spawn = enemy_count
	enabled = true
	time_until_spawn = 0.5

func begin_boss_stage(cells: Array) -> void:
	boss_mode = true
	boss_cells.clear()
	for cell in cells:
		boss_cells.append(cell)
	stage = 9
	remaining_to_spawn = 0
	enabled = true
	time_until_spawn = 4.5

func stop() -> void:
	enabled = false
	remaining_to_spawn = 0

func remaining_count() -> int:
	return remaining_to_spawn + living_count()

func living_count() -> int:
	var count := 0
	for enemy in enemy_container.get_children():
		if enemy.name != "InfectedCaptain" and enemy.get("is_alive") == true:
			count += 1
	return count

func _physics_process(delta: float) -> void:
	if not enabled or not player.is_alive:
		return
	time_until_spawn -= delta
	if time_until_spawn > 0:
		return
	if boss_mode:
		var captain: Node = enemy_container.get_node_or_null("InfectedCaptain")
		if captain == null or captain.get("is_alive") != true:
			stop()
			return
		var guard_limit := 4
		if living_count() < guard_limit:
			var guard_position := _pick_hidden_spawn()
			if guard_position != Vector3.INF:
				_spawn_at(guard_position)
		time_until_spawn = 6.0
		threat_changed.emit(living_count())
		return
	time_until_spawn = maxf(1.1, 2.0 - stage * 0.08)
	if remaining_to_spawn <= 0:
		return
	var alive := living_count()
	if alive >= mini(3 + floori(stage / 3.0), 5):
		return
	var candidate := _pick_hidden_spawn()
	if candidate != Vector3.INF:
		_spawn_at(candidate)
		remaining_to_spawn -= 1
	threat_changed.emit(living_count())

func _pick_hidden_spawn() -> Vector3:
	if rng.randf() < (0.7 if boss_mode else 0.45):
		var behind: Vector3 = camera.global_transform.basis.z
		behind.y = 0.0
		behind = behind.normalized()
		var side: Vector3 = camera.global_transform.basis.x
		side.y = 0.0
		for signum in [-1.0, 1.0]:
			var flank: Vector3 = player.global_position + behind * 6.5 + side * signum * 3.0
			flank.y = 0.2
			var flank_cell: Vector2i = map.get_cell(flank)
			var center: Vector3 = map.room_center(stage_cell.x, stage_cell.y)
			var inside_room: bool = absf(flank.x - center.x) < 8.0 and absf(flank.z - center.z) < 8.0
			var inside_arena: bool = flank.x > 31.0 and flank.x < 69.0 and flank.z > 11.0 and flank.z < 69.0
			if (boss_mode and inside_arena and boss_cells.has(flank_cell) or not boss_mode and inside_room and flank_cell == stage_cell) and is_spawn_clear(flank):
				return flank
	for attempt in MAX_ATTEMPTS:
		var cell: Vector2i = boss_cells[rng.randi_range(0, boss_cells.size() - 1)] if boss_mode else stage_cell
		var offset := 7.0 if boss_mode else 6.0
		var candidate: Vector3 = map.room_center(cell.x, cell.y) + Vector3(rng.randf_range(-offset, offset), 0.2, rng.randf_range(-offset, offset))
		var distance := candidate.distance_to(player.global_position)
		if distance < 4:
			continue
		if not is_spawn_clear(candidate):
			continue
		return candidate
	return Vector3.INF

func is_spawn_clear(candidate: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.55
	shape.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = candidate + Vector3(0, 1.0, 0)
	query.collision_mask = 1
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	for enemy in enemy_container.get_children():
		if enemy.get("is_alive") == true and enemy.global_position.distance_to(candidate) < 1.5:
			return false
	return true

func spawn_ambush() -> bool:
	return false

func _spawn_at(candidate: Vector3, ambush: bool = false) -> void:
	var roll := rng.randf()
	var kind := ZOMBIE_VARIANT.Kind.WALKER
	if boss_mode:
		kind = ZOMBIE_VARIANT.Kind.RUNNER if roll < 0.5 else ZOMBIE_VARIANT.Kind.WALKER
	elif stage == 0:
		kind = ZOMBIE_VARIANT.Kind.WALKER
	elif stage == 1:
		kind = ZOMBIE_VARIANT.Kind.RUNNER if roll < 0.55 else ZOMBIE_VARIANT.Kind.WALKER
	elif stage == 2:
		kind = ZOMBIE_VARIANT.Kind.TOXIC if roll < 0.25 else ZOMBIE_VARIANT.Kind.RUNNER
	elif stage == 3:
		kind = ZOMBIE_VARIANT.Kind.TOXIC if roll < 0.3 else ZOMBIE_VARIANT.Kind.WALKER
	else:
		var roster := [ZOMBIE_VARIANT.Kind.WALKER, ZOMBIE_VARIANT.Kind.WALKER, ZOMBIE_VARIANT.Kind.RUNNER, ZOMBIE_VARIANT.Kind.TOXIC]
		kind = roster[rng.randi_range(0, roster.size() - 1)]
	var enemy = UNDEAD.instantiate()
	enemy.name = ["ZombieWalker", "ZombieRunner", "ZombieToxic"][kind]
	enemy.position = candidate
	enemy.max_health = (65.0 if kind == ZOMBIE_VARIANT.Kind.RUNNER else 80.0) + stage * 8.0
	enemy.move_speed = player.walk_speed * (1.28 if kind == ZOMBIE_VARIANT.Kind.RUNNER else 1.04)
	enemy.attack_damage = 6.0 + stage * 0.8
	enemy.vision_range = 75.0
	enemy.chase_time = 20.0
	enemy.show_health_bar = false
	enemy.is_chasing = true
	if kind == ZOMBIE_VARIANT.Kind.RUNNER:
		enemy.scale = Vector3.ONE * 0.9
	if boss_mode:
		enemy.max_health = 125.0
		enemy.attack_damage = 11.0
	enemy_container.add_child(enemy)
	var variant := Node.new()
	variant.set_script(ZOMBIE_VARIANT)
	variant.kind = kind
	enemy.add_child(variant)
	for sound in enemy.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
