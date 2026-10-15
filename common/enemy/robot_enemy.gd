extends CharacterBody3D

enum Kind { GEORGE, LEELA, MIKE, STAN }

const MODELS := [
	"res://assets/third_party/animated_mechs/FBX/George.fbx",
	"res://assets/third_party/animated_mechs/FBX/Leela.fbx",
	"res://assets/third_party/animated_mechs/FBX/Mike.fbx",
	"res://assets/third_party/animated_mechs/FBX/Stan.fbx"
]
const TEXTURES := [
	"res://assets/third_party/animated_mechs/Textures/George_Texture.png",
	"res://assets/third_party/animated_mechs/Textures/Leela_Texture.png",
	"res://assets/third_party/animated_mechs/Textures/Mike_Texture.png",
	"res://assets/third_party/animated_mechs/Textures/Stan_Texture.png"
]
const VISUAL_SCALES := [0.39, 0.65, 0.34, 0.37]

var kind: Kind = Kind.LEELA
var max_health := 80.0
var current_health := 80.0
var move_speed := 5.0
var attack_damage := 12.0
var elite := false
var is_alive := true
var player
var sector_map: Node3D
var model: Node3D
var animations: AnimationPlayer
var attack_clock := 1.8
var path_clock := 0.0
var waypoint := Vector3.ZERO

func _ready() -> void:
	collision_layer = 3
	collision_mask = 1
	current_health = max_health
	player = get_node("/root/Global").player
	sector_map = get_tree().get_first_node_in_group("sector_map")
	var capsule := CapsuleShape3D.new()
	capsule.radius = (1.15 if kind == Kind.MIKE else 0.8) * (1.45 if elite else 1.0)
	capsule.height = (2.15 if kind == Kind.MIKE else 1.85) * (1.4 if elite else 1.0)
	var hitbox := CollisionShape3D.new()
	hitbox.shape = capsule
	hitbox.position.y = capsule.height * 0.5
	add_child(hitbox)
	model = load(MODELS[kind]).instantiate()
	model.name = "RobotVisual"
	model.scale = Vector3.ONE * VISUAL_SCALES[kind] * (1.5 if elite else 1.0)
	add_child(model)
	var finish := StandardMaterial3D.new()
	finish.albedo_texture = load(TEXTURES[kind])
	finish.metallic = 0.35
	finish.roughness = 0.72
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = finish
	animations = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animations:
		for clip in ["Idle", "Run", "Walk"]:
			if animations.has_animation(clip):
				animations.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_play("Idle")

func _physics_process(delta: float) -> void:
	if not is_alive or not is_instance_valid(player) or not player.is_alive:
		return
	attack_clock -= delta
	path_clock -= delta
	var difference: Vector3 = player.global_position - global_position
	var distance := difference.length()
	var ranged := kind == Kind.STAN
	var reach := 2.8 if elite else (2.5 if kind == Kind.MIKE else 1.9)
	if ranged:
		if distance < 28.0 and attack_clock <= 0.0:
			_telegraph_shot()
			attack_clock = 2.7 if elite else 3.4
		if distance < 8.0:
			waypoint = global_position - difference.normalized() * 4.0
		elif path_clock <= 0.0:
			waypoint = sector_map.get_enemy_waypoint(global_position, player.global_position)
			path_clock = 0.35
	else:
		if distance < reach:
			velocity.x = 0.0
			velocity.z = 0.0
			if attack_clock <= 0.0:
				_play("SwordSlash" if kind == Kind.GEORGE else "Punch")
				player.get_damage(attack_damage, difference.normalized(), true)
				attack_clock = 1.6 if kind == Kind.MIKE else 1.1
		else:
			if path_clock <= 0.0:
				waypoint = sector_map.get_enemy_waypoint(global_position, player.global_position)
				path_clock = 0.3
	var travel := waypoint - global_position
	travel.y = 0.0
	if ranged or distance >= reach:
		var direction := travel.normalized()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		if travel.length() > 0.2:
			_play("Run")
	velocity.y -= 20.0 * delta
	if distance > 0.01:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-difference.x, -difference.z), delta * 8.0)
	move_and_slide()

func _telegraph_shot() -> void:
	_play("Shoot")
	var predicted: Vector3 = player.global_position + player.velocity * 0.35
	var marker := Node3D.new()
	marker.set_script(preload("res://common/enemy/strike_marker.gd"))
	marker.position = Vector3(predicted.x, 0.05, predicted.z)
	marker.radius = 2.2 if elite else 1.8
	marker.damage = attack_damage
	get_parent().add_child(marker)

func get_damage(amount: float, _direction: Vector3) -> void:
	if not is_alive:
		return
	current_health -= amount
	if current_health > 0.0:
		_play("HitRecieve_1")
		return
	is_alive = false
	get_node("/root/Global").emit_signal("enemy_killed")
	_play("Death")
	collision_layer = 0
	collision_mask = 0
	var tween := create_tween()
	tween.tween_property(model, "position:y", -1.5, 1.8)
	tween.tween_callback(queue_free)

func _play(animation_name: String) -> void:
	if animations and animations.has_animation(animation_name) and animations.current_animation != animation_name:
		animations.play(animation_name)
