extends Node3D

# All visible architecture is instanced from Kenney's CC0 Modular Space Kit.
# Collision boxes only make the prefab floors and doorways reliably walkable.
const ROOM_PATH := "res://assets/kenney/modular-space-kit/Models/GLB format/room-large.glb"
const VARIATION_PATH := "res://assets/kenney/modular-space-kit/Models/GLB format/room-large-variation.glb"
const DOOR_PATH := "res://assets/kenney/modular-space-kit/Models/GLB format/gate-door.glb"
const CEILING_PATH := "res://assets/kenney/modular-space-kit/Models/GLB format/template-floor.glb"
const CONSOLE_PATH := "res://Models/Objects/doorConsole.tscn"
const STATION_SCREEN := preload("res://assets/third_party/space_station/display-wall-wide.glb")
const STATION_CONTAINER := preload("res://assets/third_party/space_station/container-wide.glb")
const GRID_SIZE := 7
const ROOM_SIZE := 20.0
const ORIGIN := Vector3(100, 0, 0)
const STAGE_CELLS := [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3), Vector2i(6, 4), Vector2i(5, 4), Vector2i(4, 4), Vector2i(3, 4), Vector2i(2, 4), Vector2i(1, 4)]
const BOSS_CELLS := [Vector2i(1, 4), Vector2i(0, 4), Vector2i(1, 5), Vector2i(0, 5), Vector2i(1, 6), Vector2i(0, 6)]

var room_scene: PackedScene = preload(ROOM_PATH)
var variation_scene: PackedScene = preload(VARIATION_PATH)
var door_scene: PackedScene = preload(DOOR_PATH)
var ceiling_scene: PackedScene = preload(CEILING_PATH)
var console_scene: PackedScene = preload(CONSOLE_PATH)
var flicker_lights: Array[OmniLight3D] = []
var flicker_clock := 0.0
var room_lights: Array[OmniLight3D] = []
var blackout_remaining := 0.0
var collision_cache: Dictionary = {}
var navigation_grid: AStarGrid2D
var navigation_ready := false
var stage_gates: Array[Node3D] = []

func _ready() -> void:
	add_to_group("sector_map")
	_build_sector()
	call_deferred("_build_navigation")

func _build_navigation() -> void:
	await get_tree().physics_frame
	navigation_grid = AStarGrid2D.new()
	navigation_grid.region = Rect2i(0, 0, 141, 141)
	navigation_grid.cell_size = Vector2.ONE
	navigation_grid.offset = Vector2(ORIGIN.x - 70, -70)
	navigation_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation_grid.update()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = [get_parent().get_node("Player").get_rid()]
	var space := get_world_3d().direct_space_state
	for z in 141:
		for x in 141:
			query.transform.origin = Vector3(ORIGIN.x - 70 + x, 0.95, -70 + z)
			var mapped_cell: Vector2i = get_cell(query.transform.origin)
			var outside_deck: bool = not STAGE_CELLS.has(mapped_cell) and not BOSS_CELLS.has(mapped_cell)
			navigation_grid.set_point_solid(Vector2i(x, z), outside_deck or not space.intersect_shape(query, 1).is_empty())
	navigation_ready = true

func _walkable_grid_point(point: Vector3) -> Vector2i:
	var cell := Vector2i(clampi(roundi(point.x - ORIGIN.x + 70), 0, 140), clampi(roundi(point.z + 70), 0, 140))
	if not navigation_grid.is_point_solid(cell):
		return cell
	for radius in [1, 2, 3]:
		for z in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := cell + Vector2i(x, z)
				if navigation_grid.is_in_boundsv(candidate) and not navigation_grid.is_point_solid(candidate):
					return candidate
	return cell

func _process(delta: float) -> void:
	if blackout_remaining > 0:
		blackout_remaining -= delta
		for light in room_lights:
			light.light_energy = 0.0
		if blackout_remaining <= 0:
			for light in room_lights:
				light.light_energy = light.get_meta("base_energy")
		return
	flicker_clock += delta
	if flicker_clock < 0.12:
		return
	flicker_clock = 0
	for light in flicker_lights:
		light.light_energy = float(light.get_meta("base_energy")) * (0.12 if randf() < 0.14 else randf_range(0.7, 1.0))

func blackout(seconds: float) -> void:
	blackout_remaining = seconds

func room_center(x: int, z: int) -> Vector3:
	return ORIGIN + Vector3((x - 3) * ROOM_SIZE, 0, (z - 3) * ROOM_SIZE)

func get_boss_cells() -> Array:
	return BOSS_CELLS

func get_cell(point: Vector3) -> Vector2i:
	return Vector2i(clampi(roundi((point.x - ORIGIN.x) / ROOM_SIZE) + 3, 0, 6), clampi(roundi((point.z - ORIGIN.z) / ROOM_SIZE) + 3, 0, 6))

func get_enemy_waypoint(from: Vector3, target: Vector3) -> Vector3:
	if navigation_ready:
		var path := navigation_grid.get_point_path(_walkable_grid_point(from), _walkable_grid_point(target))
		if path.size() > 1:
			return Vector3(path[1].x, from.y, path[1].y)
		return target
	var here := get_cell(from)
	var there := get_cell(target)
	if here == there:
		return target
	var middle := room_center(here.x, here.y)
	var dx := there.x - here.x
	var dz := there.y - here.y
	if abs(dx) >= abs(dz) and dx != 0:
		if absf(from.z - middle.z) > 0.45:
			return Vector3(from.x, from.y, middle.z)
		return room_center(here.x + signi(dx), here.y)
	if absf(from.x - middle.x) > 0.45:
		return Vector3(middle.x, from.y, from.z)
	return room_center(here.x, here.y + signi(dz))

func _build_sector() -> void:
	for stage_index in STAGE_CELLS.size():
		if stage_index == 9:
			continue
		var cell: Vector2i = STAGE_CELLS[stage_index]
		var x := cell.x
		var z := cell.y
		var room := (variation_scene if (x * 3 + z * 5) % 4 == 0 else room_scene).instantiate()
		room.name = "Deck_%d_%d" % [x, z]
		room.position = room_center(x, z)
		add_child(room)
		var ceiling := ceiling_scene.instantiate()
		ceiling.name = "Ceiling"
		ceiling.position.y = 4.22
		ceiling.rotation_degrees.x = 180
		ceiling.scale = Vector3(5.0, 1.0, 5.0)
		room.add_child(ceiling)
		_add_room_collision(room)
		_add_room_light(room, x, z)
		_add_set_dressing(room, x, z)
		for direction in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var neighbor: Vector2i = cell + direction
			var linked: bool = stage_index > 0 and neighbor == STAGE_CELLS[stage_index - 1]
			linked = linked or (stage_index < STAGE_CELLS.size() - 1 and neighbor == STAGE_CELLS[stage_index + 1])
			if not linked and not (stage_index == STAGE_CELLS.size() - 1 and direction == Vector2i(-1, 0)):
				_add_door(room, Vector3(direction.x * 10, 0, direction.y * 10), 90 if direction.x != 0 else 0)
	_build_boss_arena()
	for stage_index in STAGE_CELLS.size():
		_add_stage_gate(stage_index)

func _build_boss_arena() -> void:
	var arena := Node3D.new()
	arena.name = "ReactorChamber"
	add_child(arena)
	var structure := StaticBody3D.new()
	structure.name = "ArenaStructure"
	structure.collision_layer = 3
	arena.add_child(structure)
	_add_box(structure, Vector3(40, 0.3, 60), Vector3(50, -0.15, 40))
	for cell in BOSS_CELLS:
		var floor_tile := ceiling_scene.instantiate()
		floor_tile.position = room_center(cell.x, cell.y)
		floor_tile.scale = Vector3(5, 1, 5)
		arena.add_child(floor_tile)
		var ceiling := ceiling_scene.instantiate()
		ceiling.position = room_center(cell.x, cell.y) + Vector3(0, 6.4, 0)
		ceiling.rotation_degrees.x = 180
		ceiling.scale = Vector3(5, 1, 5)
		arena.add_child(ceiling)
		var lamp := OmniLight3D.new()
		lamp.position = room_center(cell.x, cell.y) + Vector3(0, 5.3, 0)
		lamp.omni_range = 24
		lamp.light_energy = 2.1
		lamp.light_color = Color(0.55, 0.78, 0.87) if cell.x == 0 else Color(0.9, 0.55, 0.36)
		arena.add_child(lamp)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.1, 0.16, 0.21)
	wall_material.metallic = 0.65
	wall_material.roughness = 0.45
	_add_arena_wall(structure, Vector3(40, 6.5, 0.5), Vector3(50, 3.25, 10), wall_material)
	_add_arena_wall(structure, Vector3(40, 6.5, 0.5), Vector3(50, 3.25, 70), wall_material)
	_add_arena_wall(structure, Vector3(0.5, 6.5, 48.2), Vector3(30, 3.25, 34.1), wall_material)
	_add_arena_wall(structure, Vector3(0.5, 6.5, 8.2), Vector3(30, 3.25, 65.9), wall_material)
	_add_arena_wall(structure, Vector3(0.5, 6.5, 8.2), Vector3(70, 3.25, 14.1), wall_material)
	_add_arena_wall(structure, Vector3(0.5, 6.5, 48.2), Vector3(70, 3.25, 45.9), wall_material)
	_add_reactor_core(arena, Vector3(50, 0, 43))
	for cover_position in [Vector3(39, 0, 32), Vector3(61, 0, 34), Vector3(39, 0, 53), Vector3(61, 0, 54)]:
		_add_blast_shield(arena, cover_position)
	var lane_material := StandardMaterial3D.new()
	lane_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lane_material.albedo_color = Color(0.09, 0.55, 0.61)
	lane_material.emission_enabled = true
	lane_material.emission = Color(0.03, 0.25, 0.29)
	for x in [34.0, 66.0]:
		var strip := MeshInstance3D.new()
		var strip_mesh := BoxMesh.new()
		strip_mesh.size = Vector3(0.16, 0.035, 54)
		strip.mesh = strip_mesh
		strip.material_override = lane_material
		strip.position = Vector3(x, 0.03, 40)
		arena.add_child(strip)
	for z in [20.0, 40.0, 60.0]:
		var overhead := MeshInstance3D.new()
		var overhead_mesh := BoxMesh.new()
		overhead_mesh.size = Vector3(32.0, 0.06, 0.22)
		overhead.mesh = overhead_mesh
		overhead.material_override = lane_material
		overhead.position = Vector3(50, 6.15, z)
		arena.add_child(overhead)

func _add_reactor_core(arena: Node3D, location: Vector3) -> void:
	var core := StaticBody3D.new()
	core.name = "ReactorCore"
	core.position = location
	core.collision_layer = 3
	arena.add_child(core)
	var shape := CylinderShape3D.new()
	shape.radius = 2.7
	shape.height = 3.8
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 1.9
	core.add_child(collision)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.07, 0.13, 0.17)
	metal.metallic = 0.8
	var shell := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 2.7
	cylinder.bottom_radius = 2.7
	cylinder.height = 3.8
	shell.mesh = cylinder
	shell.material_override = metal
	shell.position.y = 1.9
	core.add_child(shell)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.24, 0.77, 0.83)
	glow.emission_enabled = true
	glow.emission = Color(0.13, 0.58, 0.68)
	glow.emission_energy_multiplier = 2.5
	for height in [0.65, 2.9]:
		var band := MeshInstance3D.new()
		var band_mesh := CylinderMesh.new()
		band_mesh.top_radius = 2.8
		band_mesh.bottom_radius = 2.8
		band_mesh.height = 0.13
		band.mesh = band_mesh
		band.material_override = glow
		band.position.y = height
		core.add_child(band)
	var light := OmniLight3D.new()
	light.position.y = 3.5
	light.light_color = Color(0.2, 0.72, 0.8)
	light.light_energy = 1.2
	light.omni_range = 11
	core.add_child(light)

func _add_blast_shield(arena: Node3D, location: Vector3) -> void:
	var shield := StaticBody3D.new()
	shield.name = "BlastShield"
	shield.position = location
	shield.collision_layer = 3
	arena.add_child(shield)
	_add_box(shield, Vector3(5.5, 1.55, 0.7), Vector3(0, 0.775, 0))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.2, 0.26)
	material.metallic = 0.7
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.5, 1.55, 0.7)
	mesh.mesh = box
	mesh.material_override = material
	mesh.position.y = 0.775
	shield.add_child(mesh)
	var edge := MeshInstance3D.new()
	var edge_mesh := BoxMesh.new()
	edge_mesh.size = Vector3(5.5, 0.07, 0.75)
	edge.mesh = edge_mesh
	var edge_material := StandardMaterial3D.new()
	edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_material.albedo_color = Color(0.75, 0.35, 0.18)
	edge_material.emission_enabled = true
	edge_material.emission = Color(0.43, 0.13, 0.04)
	edge.material_override = edge_material
	edge.position.y = 1.56
	shield.add_child(edge)

func _station_model(parent: Node3D, scene: PackedScene, location: Vector3, yaw: float, size: Vector3) -> void:
	var model := scene.instantiate()
	model.position = location
	model.rotation_degrees.y = yaw
	model.scale = size
	parent.add_child(model)

func _station_cover(arena: Node3D, location: Vector3) -> void:
	var cover := StaticBody3D.new()
	cover.position = location
	cover.collision_layer = 3
	arena.add_child(cover)
	_add_box(cover, Vector3(3.0, 1.6, 2.3), Vector3(0, 0.8, 0))
	_station_model(cover, STATION_CONTAINER, Vector3.ZERO, 0, Vector3.ONE * 2.0)

func _add_arena_wall(body: StaticBody3D, size: Vector3, location: Vector3, material: Material) -> void:
	_add_box(body, size, location)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = location
	body.add_child(mesh)

func gate_position(stage_index: int) -> Vector3:
	if stage_index == STAGE_CELLS.size() - 1:
		return room_center(0, 6) + Vector3(-10, 0, 0)
	var cell: Vector2i = STAGE_CELLS[stage_index]
	var direction: Vector2i = STAGE_CELLS[stage_index + 1] - cell if stage_index < STAGE_CELLS.size() - 1 else Vector2i(-1, 0)
	return room_center(cell.x, cell.y) + Vector3(direction.x * 10, 0, direction.y * 10)

func _add_stage_gate(stage_index: int) -> void:
	var position_in_world := gate_position(stage_index)
	var cell: Vector2i = STAGE_CELLS[stage_index]
	var direction: Vector2i = STAGE_CELLS[stage_index + 1] - cell if stage_index < STAGE_CELLS.size() - 1 else Vector2i(-1, 0)
	var gate := Node3D.new()
	gate.name = "StageGate_%d" % (stage_index + 1)
	gate.position = position_in_world
	gate.rotation_degrees.y = 90 if direction.x != 0 else 0
	add_child(gate)
	var visual := door_scene.instantiate()
	visual.name = "DoorVisual"
	gate.add_child(visual)
	var blocker := StaticBody3D.new()
	blocker.name = "LockedBarrier"
	blocker.collision_layer = 3
	gate.add_child(blocker)
	_add_box(blocker, Vector3(3.6, 4.1, 0.4), Vector3(0, 2.05, 0))
	var indicator := OmniLight3D.new()
	indicator.name = "LockLight"
	indicator.position = Vector3(0, 2.6, 0)
	indicator.light_color = Color(0.9, 0.08, 0.04)
	indicator.light_energy = 0.65
	indicator.omni_range = 4
	gate.add_child(indicator)
	stage_gates.append(gate)

func open_stage_gate(stage_index: int) -> void:
	var gate := stage_gates[stage_index]
	var blocker: StaticBody3D = gate.get_node("LockedBarrier")
	var visual: Node3D = gate.get_node("DoorVisual")
	var indicator: OmniLight3D = gate.get_node("LockLight")
	blocker.queue_free()
	visual.hide()
	indicator.light_color = Color(0.12, 0.85, 0.3)

func close_stage_gate(stage_index: int) -> void:
	var gate := stage_gates[stage_index]
	var blocker := StaticBody3D.new()
	blocker.name = "LockedBarrier"
	blocker.collision_layer = 3
	gate.add_child(blocker)
	_add_box(blocker, Vector3(3.6, 4.1, 0.4), Vector3(0, 2.05, 0))
	var visual: Node3D = gate.get_node("DoorVisual")
	var indicator: OmniLight3D = gate.get_node("LockLight")
	visual.show()
	indicator.light_color = Color(0.9, 0.08, 0.04)

func _add_room_collision(room: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "WalkableDeck"
	body.collision_layer = 3
	room.add_child(body)
	# Shared concave shapes follow the imported pillars and wall supports exactly.
	for mesh_node in room.find_children("*", "MeshInstance3D", true, false):
		if mesh_node.get_parent().name == "Ceiling":
			continue
		var mesh: Mesh = mesh_node.mesh
		if not collision_cache.has(mesh):
			var faces := mesh.get_faces()
			var solid_faces := PackedVector3Array()
			for i in range(0, faces.size(), 3):
				# Ignore low floor trim: tall supports remain solid, footsteps do not snag.
				if maxf(faces[i].y, maxf(faces[i + 1].y, faces[i + 2].y)) <= 0.4:
					continue
				solid_faces.append(faces[i])
				solid_faces.append(faces[i + 1])
				solid_faces.append(faces[i + 2])
			var architecture := ConcavePolygonShape3D.new()
			architecture.set_faces(solid_faces)
			collision_cache[mesh] = architecture
		var shape := CollisionShape3D.new()
		shape.name = "ArchitectureCollision"
		shape.shape = collision_cache[mesh]
		body.add_child(shape)
		shape.global_transform = mesh_node.global_transform
	_add_box(body, Vector3(20, 0.2, 20), Vector3(0, -0.11, 0))
	# Two wall sections leave a clear 3.6 m opening centered on every side.
	for side in [-1, 1]:
		for offset in [-5.9, 5.9]:
			_add_box(body, Vector3(8.2, 4.1, 0.35), Vector3(offset, 2.05, side * 9.82))
			_add_box(body, Vector3(0.35, 4.1, 8.2), Vector3(side * 9.82, 2.05, offset))

func _add_box(parent: StaticBody3D, size: Vector3, location: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position = location
	parent.add_child(collision)

func _add_room_light(room: Node3D, x: int, z: int) -> void:
	var light := OmniLight3D.new()
	light.name = "EmergencyLighting"
	light.position = Vector3(0, 3.5, 0)
	light.omni_range = 10.5
	light.light_energy = 0.26 if (x + z) % 4 != 0 else 0.065
	light.light_color = Color(0.24, 0.38, 0.48) if (x + z * 2) % 5 != 0 else Color(0.85, 0.09, 0.045)
	light.set_meta("base_energy", light.light_energy)
	room_lights.append(light)
	room.add_child(light)
	if (x * 7 + z * 3) % 8 == 0:
		flicker_lights.append(light)

func _add_set_dressing(room: Node3D, x: int, z: int) -> void:
	var stage_index := STAGE_CELLS.find(Vector2i(x, z))
	var formations := [
		[Vector3(4, 0, 3)],
		[Vector3(-4, 0, -2)],
		[Vector3(4, 0, -3)],
		[Vector3(-4, 0, -4), Vector3(4, 0, 3)],
		[Vector3(5, 0, -4)],
		[Vector3(-5, 0, -4), Vector3(4, 0, 3)],
		[Vector3(-5, 0, 0), Vector3(4, 0, -5)],
		[Vector3(-4, 0, -5), Vector3(5, 0, 0)],
		[Vector3(-5, 0, -4), Vector3(5, 0, 4)]
	]
	if stage_index >= 0 and stage_index < formations.size():
		for location in formations[stage_index]:
			_station_cover(room, location)
		_station_model(room, STATION_SCREEN, Vector3(-9.35, 1.7, -4), 90, Vector3.ONE * 1.4)

func _add_door(room: Node3D, location: Vector3, yaw: float) -> void:
	var door := door_scene.instantiate()
	door.position = location
	door.rotation_degrees.y = yaw
	room.add_child(door)
	var body := StaticBody3D.new()
	body.name = "SealedOuterBulkhead"
	body.collision_layer = 3
	body.position = location
	body.rotation_degrees.y = yaw
	room.add_child(body)
	_add_box(body, Vector3(3.6, 4.1, 0.4), Vector3(0, 2.05, 0))

func _add_console(cell: Vector2i) -> void:
	var terminal := console_scene.instantiate()
	terminal.name = "MissionConsole_%d_%d" % [cell.x, cell.y]
	terminal.position = room_center(cell.x, cell.y) + Vector3(0, 0, -6)
	terminal.rotation_degrees.y = 180
	add_child(terminal)
	var glow := OmniLight3D.new()
	glow.position = terminal.position + Vector3(0, 1.4, 0)
	glow.omni_range = 5
	glow.light_energy = 0.6
	glow.light_color = Color(0.18, 0.8, 0.95)
	add_child(glow)
