extends Node

enum Kind { WALKER, RUNNER, TOXIC, CAPTAIN, WARDEN }

var kind: Kind = Kind.WALKER
var enemy
var player
var attack_clock := 2.0

func _ready() -> void:
	enemy = get_parent()
	player = get_node("/root/Global").player
	_apply_look()

func _physics_process(delta: float) -> void:
	if kind != Kind.TOXIC or not enemy.is_alive or not is_instance_valid(player) or not player.is_alive:
		return
	attack_clock -= delta
	if attack_clock > 0.0:
		return
	if enemy.global_position.distance_to(player.global_position) < 16.0:
		_spit_at_player()
		attack_clock = 5.0

func _apply_look() -> void:
	var overlay := StandardMaterial3D.new()
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.albedo_color = _tint()
	for mesh in enemy.character_root.find_children("*", "MeshInstance3D", true, false):
		if mesh.name == "undead_mesh":
			mesh.material_overlay = overlay

func _tint() -> Color:
	match kind:
		Kind.RUNNER:
			return Color(0.75, 0.06, 0.05, 0.24)
		Kind.TOXIC:
			return Color(0.13, 0.7, 0.14, 0.30)
		Kind.CAPTAIN:
			return Color(0.8, 0.07, 0.04, 0.34)
		Kind.WARDEN:
			return Color(0.84, 0.4, 0.05, 0.30)
	return Color(0, 0, 0, 0)

func _spit_at_player() -> void:
	var marker := Node3D.new()
	marker.set_script(preload("res://common/enemy/strike_marker.gd"))
	var target: Vector3 = player.global_position + player.velocity * 0.2
	marker.position = Vector3(target.x, 0.05, target.z)
	marker.color = Color(0.22, 0.85, 0.15)
	marker.radius = 1.8
	marker.damage = 10.0
	marker.warning_time = 1.5
	enemy.get_parent().add_child(marker)
