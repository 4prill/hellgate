extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://main_ship.tscn").instantiate()
	root.add_child(game)
	for i in 8:
		await process_frame
	game._start_game()
	for i in 12:
		await process_frame
	assert(game.phase == "cutscene")
	assert(not game.player.get_node("WeaponSubViewport").visible)
	game._show_cutscene_shot(1)
	game.cutscene_shot_elapsed = 1.0
	assert(game.cutscene_camera.cull_mask & 2 == 0)
	for i in 4:
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var image = root.get_viewport().get_texture().get_image()
	assert(image.save_png("res://artifacts/cutscene_hellgate.png") == OK)
	assert(game.cutscene_speaker.text == "H-07  /  EMERGENCY RECORD")
	assert(game.cutscene_progress.anchor_right > 0.0)
	game._end_cutscene()
	assert(game.phase == "playing")
	assert(game.player.get_node("WeaponSubViewport").visible)
	var toxic = load("res://enemies/undead.tscn").instantiate()
	game.get_node("Enemies").add_child(toxic)
	var mesh_count_before = toxic.character_root.find_children("*", "MeshInstance3D", true, false).size()
	var variant = Node.new()
	variant.set_script(load("res://common/enemy/zombie_variant.gd"))
	variant.kind = 2
	toxic.add_child(variant)
	assert(toxic.character_root.find_children("*", "MeshInstance3D", true, false).size() == mesh_count_before)
	print("CUTSCENE_UI_OK")
	game.queue_free()
	for i in 2:
		await process_frame
	quit()
