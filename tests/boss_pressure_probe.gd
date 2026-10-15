extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://main_ship.tscn").instantiate()
	root.add_child(game)
	for i in 4:
		await process_frame
	game._start_game()
	game._end_cutscene()
	for i in 9:
		game._skip_stage()
		await process_frame
	game._end_cutscene()
	var boss = game.get_node("Enemies/InfectedCaptain")
	var ability: Node
	for child in boss.get_children():
		if child.get_script() == load("res://common/enemy/boss_abilities.gd"):
			ability = child
	assert(ability != null)
	var base_speed: float = boss.move_speed
	game.player.global_position = boss.global_position + Vector3(0, 0, -12)
	game.player.velocity = Vector3(0, 0, -8)
	ability._physics_process(0.1)
	assert(boss.move_speed > base_speed)
	var director = game.director
	var first_count: int = director.living_count()
	director.time_until_spawn = 0
	director._physics_process(0.1)
	assert(director.living_count() > first_count)
	assert(director.remaining_to_spawn == 0)
	print("BOSS_PRESSURE_OK")
	game.queue_free()
	for i in 2:
		await process_frame
	quit()
