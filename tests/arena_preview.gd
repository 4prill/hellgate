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
	for i in 9:
		game._skip_stage()
		for frame in 2:
			await process_frame
	game._end_cutscene()
	game.director.stop()
	game.player.global_position = Vector3(58, 0.2, 27)
	game.player.camera_pivot.rotation.y = PI + 0.45
	game.player.camera_holder.rotation = Vector3.ZERO
	for i in 8:
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var image = root.get_viewport().get_texture().get_image()
	assert(image.save_png("res://artifacts/reactor_chamber.png") == OK)
	print("ARENA_PREVIEW_OK")
	game.queue_free()
	for i in 2:
		await process_frame
	quit()
