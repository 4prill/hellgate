extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://main_ship.tscn").instantiate()
	root.add_child(game)
	for i in 5:
		await process_frame
	game._start_game()
	game._end_cutscene()
	var f10 := InputEventKey.new()
	f10.keycode = KEY_F10
	f10.pressed = true
	for target_stage in range(1, 10):
		game._unhandled_input(f10)
		assert(game.objective_index == target_stage)
		if target_stage < 9:
			assert(game.phase == "playing")
			assert(game.player.global_position.distance_to(game.sector.room_center(game.OBJECTIVE_CELLS[target_stage].x, game.OBJECTIVE_CELLS[target_stage].y)) < 1.0)
		else:
			assert(game.phase == "cutscene")
			assert(game.sector.get_node("ReactorChamber/ReactorCore") != null)
		for i in 2:
			await process_frame
	game._unhandled_input(f10)
	assert(game.cutscene_kind == "outro")
	game._end_cutscene()
	assert(game.phase == "won")
	print("STAGE_SKIP_OK")
	game.queue_free()
	for i in 2:
		await process_frame
	quit()
