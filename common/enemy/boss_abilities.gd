extends Node

var boss
var player
var cooldown := 4.0
var volley := 0
var base_speed := 0.0

func _ready() -> void:
	boss = get_parent()
	player = get_node("/root/Global").player
	base_speed = boss.move_speed

func _physics_process(delta: float) -> void:
	if not boss.is_alive or not is_instance_valid(player) or not player.is_alive:
		return
	var toward_player: Vector3 = player.global_position - boss.global_position
	toward_player.y = 0.0
	var distance := toward_player.length()
	var retreat_speed: float = player.velocity.dot(toward_player.normalized()) if distance > 0.1 else 0.0
	boss.move_speed = base_speed * (1.45 if retreat_speed > 2.5 and distance > 5.5 else 1.0)
	boss.animation_tree.set("parameters/walk/TimeScale/scale", clampf(boss.move_speed / 3.5, 1.0, 2.8))
	cooldown -= delta
	if cooldown > 0.0:
		return
	volley += 1
	var origin: Vector3 = player.global_position
	var lateral := Vector3(player.velocity.z, 0.0, -player.velocity.x).normalized()
	var lead: Vector3 = player.velocity * 1.1
	if volley % 3 == 0:
		for offset in [-3.5, 3.5]:
			_mark(origin + lead + lateral * offset, 2.0, 13.0, 1.45)
		cooldown = 4.2
	else:
		_mark(origin + lead, 2.3, 15.0, 1.35)
		if retreat_speed > 2.5:
			_mark(origin + player.velocity * 1.35, 2.1, 13.0, 1.45)
		cooldown = 3.2
	if boss.global_position.distance_to(player.global_position) < 5.5:
		_mark(boss.global_position, 3.6, 11.0, 1.2)

func _mark(location: Vector3, radius: float, damage: float, delay: float) -> void:
	var marker := Node3D.new()
	marker.set_script(preload("res://common/enemy/strike_marker.gd"))
	marker.position = Vector3(location.x, 0.06, location.z)
	marker.radius = radius
	marker.damage = damage
	marker.warning_time = delay
	marker.color = Color(1.0, 0.12, 0.045) if boss.name == "InfectedCaptain" else Color(0.2, 0.6, 1.0)
	boss.get_parent().add_child(marker)
