extends Node3D

const UNDEAD := preload("res://enemies/undead.tscn")
const ZOMBIE_VARIANT := preload("res://common/enemy/zombie_variant.gd")
const SAFE_SPAWN := Vector3(100, 0.2, 0)
const OBJECTIVE_CELLS := [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3), Vector2i(6, 4), Vector2i(5, 4), Vector2i(4, 4), Vector2i(3, 4), Vector2i(2, 4), Vector2i(1, 4)]
const OBJECTIVES := [
	"Recover the crew log", "Secure the med bay", "Restart the reactor", "Seal the cargo hold",
	"Restore navigation", "Purge the maintenance deck", "Open the armory", "Silence the comms array",
	"Reach the command bridge", "Defeat the infected captain"
]
const TARGET_NAMES := ["CREW LOG", "MED BAY", "REACTOR", "CARGO HOLD", "NAVIGATION", "MAINTENANCE", "ARMORY", "COMMS", "BRIDGE", "CAPTAIN"]
const KILLS_REQUIRED := [3, 4, 5, 6, 6, 7, 7, 8, 9, 0]
const ACTION_HINTS := ["[F] Read the log", "[F] Secure med bay", "[F] Restart reactor", "[F] Seal cargo hold", "[F] Restore navigation", "[F] Purge maintenance", "[F] Open armory", "[F] Silence comms", "[F] Access bridge", "[F] Evacuate"]
const UI_FONT := preload("res://resources/fonts/BarlowCondensed-Regular.ttf")
const DISPLAY_FONT := preload("res://resources/fonts/BarlowCondensed-SemiBold.ttf")
const INK := Color("040a0e")
const PANEL := Color("08151c")
const CYAN := Color("d1d4ce")
const WHITE := Color("ecece4")
const MUTED := Color("969c98")
const AMBER := Color("e9ad5a")
const RED := Color("e7514a")
const CREDITS_HEIGHT := 1100.0

@onready var player = $Player
@onready var director = $ThreatDirector
@onready var sector = $SectorMap

var phase := "menu"
var objective_index := 0
var gate_open := false
var boss_entry_sealed := false
var mission_layer: CanvasLayer
var mission_label: Label
var mission_chrome: Array[Control] = []
var prompt_label: Label
var story_label: Label
var menu_cover: ColorRect
var story_remaining := 0.0
var boss
var boss_label: Label
var ambient_player: AudioStreamPlayer
var combat_player: AudioStreamPlayer
var hints_seen: Dictionary = {}
var controls_return := "intro"
var settings = preload("res://world/game_settings.gd").new()
var settings_return := "intro"
var horror: Node3D
var cutscene_layer: CanvasLayer
var cutscene_title: Label
var cutscene_detail: Label
var cutscene_kicker: Label
var cutscene_counter: Label
var cutscene_speaker: Label
var cutscene_progress: ColorRect
var cutscene_fade: ColorRect
var cutscene_camera: Camera3D
var cutscene_sting: AudioStreamPlayer
var ui_audio: AudioStreamPlayer
const UI_CLICK := preload("res://audio/third_party/knife_swing.wav")
var cutscene_credits: ColorRect
var cutscene_credits_text: Label
var cutscene_kind := ""
var cutscene_shots: Array[Dictionary] = []
var cutscene_shot_index := 0
var cutscene_shot_elapsed := 0.0
var cutscene_start := Vector3.ZERO
var cutscene_end := Vector3.ZERO
var cutscene_target := Vector3.ZERO

func _ready() -> void:
	for node_name in ["Player", "InputManager", "Enemies", "ThreatDirector", "SectorMap"]:
		get_node(node_name).process_mode = Node.PROCESS_MODE_PAUSABLE
	process_mode = Node.PROCESS_MODE_ALWAYS
	player.global_position = SAFE_SPAWN
	Global.enemies_killed = 0
	for entry in [[Bullets.AmmoType.PISTOL, 48], [Bullets.AmmoType.ASSAULT, 160], [Bullets.AmmoType.LMG, 50]]:
		Bullets.ammo_inventory[entry[0]]["current"] = entry[1]
	Global.player_dead.connect(_on_player_dead)
	Global.activate_pressed.connect(_on_activate)
	settings.load_settings()
	settings.setup_buses()
	_build_mission_ui()
	_build_cutscene_ui()
	_build_audio()
	horror = Node3D.new()
	horror.set_script(preload("res://world/horror_director.gd"))
	horror.name = "HorrorDirector"
	add_child(horror)
	settings.apply(self)
	_show_menu("intro")
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(delta: float) -> void:
	if phase != "cutscene":
		return
	cutscene_shot_elapsed += delta
	var shot: Dictionary = cutscene_shots[cutscene_shot_index]
	var duration: float = shot["duration"]
	var progress: float = clampf(cutscene_shot_elapsed / duration, 0.0, 1.0)
	cutscene_progress.anchor_right = (float(cutscene_shot_index) + progress) / float(cutscene_shots.size())
	var eased: float = progress * progress * (3.0 - 2.0 * progress)
	cutscene_camera.global_position = cutscene_start.lerp(cutscene_end, eased)
	cutscene_camera.look_at(cutscene_target, Vector3.UP)
	if shot.get("credits", false):
		var viewport_height: float = get_viewport().get_visible_rect().size.y
		cutscene_credits_text.offset_top = lerpf(viewport_height, -CREDITS_HEIGHT, progress)
		cutscene_credits_text.offset_bottom = cutscene_credits_text.offset_top + CREDITS_HEIGHT
	var fade_alpha: float = 1.0 - minf(cutscene_shot_elapsed / 0.55, 1.0)
	if cutscene_shot_elapsed > duration - 0.55:
		fade_alpha = maxf(fade_alpha, (cutscene_shot_elapsed - duration + 0.55) / 0.55)
	cutscene_fade.color.a = clampf(fade_alpha, 0.0, 1.0)
	if cutscene_shot_elapsed >= duration:
		if cutscene_shot_index + 1 < cutscene_shots.size():
			_show_cutscene_shot(cutscene_shot_index + 1)
		else:
			_end_cutscene()

func _physics_process(delta: float) -> void:
	if phase != "playing":
		return
	if player.global_position.y < -4.0:
		var safe_cell: Vector2i = OBJECTIVE_CELLS[objective_index]
		player.global_position = sector.room_center(safe_cell.x, safe_cell.y) + Vector3(0, 0.2, 0)
		player.velocity = Vector3.ZERO
	if gate_open and objective_index < 9 and sector.get_cell(player.global_position) == OBJECTIVE_CELLS[objective_index + 1]:
		_advance_stage()
	if objective_index == 9 and not boss_entry_sealed and player.global_position.distance_to(sector.gate_position(8)) > 6.0:
		sector.close_stage_gate(8)
		boss_entry_sealed = true
	var target: Vector3 = _target_position()
	var distance: float = player.global_position.distance_to(target)
	var camera: Camera3D = player.get_node("CameraPivot/CameraHolder/MainCamera")
	var forward := -camera.global_transform.basis.z
	var to_target: Vector3 = (target - player.global_position).normalized()
	var cross: float = forward.x * to_target.z - forward.z * to_target.x
	var arrow := "↑" if forward.dot(to_target) > 0.75 else ("→" if cross > 0 else "←")
	var kills_left := _kills_remaining()
	mission_label.text = "SECTOR %02d / 10     %s  %s  %dm     %d HOSTILES" % [objective_index + 1, TARGET_NAMES[objective_index], arrow, roundi(distance), kills_left]
	var boss_alive: bool = objective_index == 9 and is_instance_valid(boss) and boss.is_alive
	prompt_label.text = (("Door open. Walk through." if gate_open else ("Defeat the captain" if boss_alive else ("Purge %d more hostiles" % kills_left if kills_left > 0 else "[F] Open the next door"))) if distance < 4.5 else "")
	boss_label.visible = boss_alive
	if boss_alive:
		boss_label.text = "INFECTED CAPTAIN  |  %d / %d" % [ceili(boss.current_health), ceili(boss.max_health)]
	story_label.visible = prompt_label.text.is_empty()
	if story_remaining > 0:
		story_remaining -= delta
		if story_remaining <= 0:
			story_label.text = ""
	var danger := false
	for enemy in $Enemies.get_children():
		if enemy.get("is_alive") == true and enemy.global_position.distance_to(player.global_position) < 24:
			danger = true
			break
	_update_guidance(danger)
	var duck: float = horror.audio_duck_db
	ambient_player.volume_db = move_toward(ambient_player.volume_db, (-24.0 if danger else -16.0) - duck, delta * 16)
	combat_player.volume_db = move_toward(combat_player.volume_db, (-14.0 if danger else -50.0) - duck, delta * 20)

func _show_hint(value: String, duration: float = 6.0) -> void:
	story_label.text = value
	story_remaining = duration

func _update_guidance(danger: bool) -> void:
	if story_remaining > 0 or not prompt_label.text.is_empty():
		return
	var weapons = player.get_node("WeaponsManager")
	if danger and not hints_seen.has("combat"):
		hints_seen["combat"] = true
		_show_hint("Left click to fire. Keep moving with WASD.")
	elif weapons.current_weapon and weapons.current_weapon.reload_required and weapons.get_current_mag() == 0 and not hints_seen.has("reload"):
		hints_seen["reload"] = true
		_show_hint("Empty magazine — press R to reload, or scroll to switch weapons.")
	elif not hints_seen.has("route") and player.global_position.distance_to(SAFE_SPAWN) > 4.0:
		hints_seen["route"] = true
		_show_hint(OBJECTIVES[objective_index] + ". Follow the arrow.", 8.0)

func _target_position() -> Vector3:
	return sector.gate_position(objective_index)

func _kills_remaining() -> int:
	if objective_index == 9:
		return (1 if is_instance_valid(boss) and boss.is_alive else 0) + director.living_count() + director.remaining_to_spawn
	return director.remaining_count()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		get_viewport().set_input_as_handled()
		if phase == "cutscene":
			_end_cutscene()
		elif phase == "paused":
			_resume_game()
		_skip_stage()
	elif phase == "cutscene" and event is InputEventKey and event.pressed and event.keycode in [KEY_SPACE, KEY_ENTER]:
		get_viewport().set_input_as_handled()
		_end_cutscene()
	elif event.is_action_pressed("exit") and phase in ["playing", "paused"]:
		get_viewport().set_input_as_handled()
		if phase == "playing":
			_pause_game()
		else:
			_resume_game()
	elif event.is_action_pressed("exit") and phase == "controls":
		get_viewport().set_input_as_handled()
		_show_menu(controls_return)
	elif event.is_action_pressed("exit") and phase == "settings":
		get_viewport().set_input_as_handled()
		_show_menu(settings_return)

func _on_activate() -> void:
	if phase != "playing":
		return
	if player.global_position.distance_to(_target_position()) > 4.5 or gate_open:
		return
	if objective_index == 9 and is_instance_valid(boss) and boss.is_alive:
		_show_hint("Defeat the infected captain first.", 3.0)
		return
	if _kills_remaining() > 0:
		_show_hint("Clear %d more hostiles to unlock the door." % _kills_remaining(), 3.5)
		return
	sector.open_stage_gate(objective_index)
	gate_open = true
	if objective_index == 9:
		_finish_game()
		return
	_show_hint("Door unlocked. Walk into the next stage.", 5.0)

func _advance_stage() -> void:
	objective_index += 1
	gate_open = false
	_show_hint("Stage %d. %s." % [objective_index + 1, OBJECTIVES[objective_index]], 6.0)
	if objective_index == 9:
		director.stop()
		for enemy in $Enemies.get_children():
			enemy.queue_free()
		_spawn_boss()
		_spawn_warden()
	else:
		director.begin_stage(objective_index, OBJECTIVE_CELLS[objective_index], KILLS_REQUIRED[objective_index])
		if objective_index in [3, 6, 8]:
			sector.blackout(3.5)
			_show_hint("Emergency lights failed. Watch for charging infected.", 5.0)
	var health_before: float = player.current_health
	player.current_health = minf(100.0, health_before + 40.0)
	Global.player_health_changed.emit(player.current_health - health_before, player.current_health, 100.0, false)
	Bullets._add_ammo(Bullets.AmmoType.PISTOL, 30)
	Bullets._add_ammo(Bullets.AmmoType.ASSAULT, 90)
	Bullets._add_ammo(Bullets.AmmoType.LMG, 45)
	Global.bullets_changed.emit()
	if objective_index == 9:
		_begin_cutscene("boss")

func _skip_stage() -> void:
	if phase != "playing":
		return
	director.stop()
	for enemy in $Enemies.get_children():
		enemy.queue_free()
	sector.open_stage_gate(objective_index)
	if objective_index == OBJECTIVE_CELLS.size() - 1:
		_finish_game()
		return
	var next_cell: Vector2i = OBJECTIVE_CELLS[objective_index + 1]
	player.global_position = sector.room_center(next_cell.x, next_cell.y) + Vector3(0, 0.2, 0)
	player.velocity = Vector3.ZERO
	_advance_stage()

func _spawn_boss() -> void:
	boss = UNDEAD.instantiate()
	boss.name = "InfectedCaptain"
	boss.position = sector.room_center(0, 6) + Vector3(4, 0.2, -4)
	boss.scale = Vector3.ONE * 1.25
	boss.max_health = 1250.0
	boss.attack_damage = 18.0
	boss.attack_range = 2.6
	boss.move_speed = player.walk_speed * 1.13
	boss.vision_range = 160.0
	boss.chase_time = 120.0
	boss.show_health_bar = true
	$Enemies.add_child(boss)
	boss.is_chasing = true
	var variant := Node.new()
	variant.set_script(ZOMBIE_VARIANT)
	variant.kind = ZOMBIE_VARIANT.Kind.CAPTAIN
	boss.add_child(variant)
	var glow := OmniLight3D.new()
	glow.name = "CaptainGlow"
	glow.position = Vector3(0, 2.1, 0)
	glow.light_color = RED
	glow.light_energy = 1.4
	glow.omni_range = 5.0
	boss.add_child(glow)
	var abilities := Node.new()
	abilities.set_script(preload("res://common/enemy/boss_abilities.gd"))
	boss.add_child(abilities)

func _spawn_warden() -> void:
	var warden = UNDEAD.instantiate()
	warden.name = "InfectedWarden"
	warden.position = sector.room_center(1, 5) + Vector3(-2, 0.2, 3)
	warden.scale = Vector3.ONE * 1.12
	warden.max_health = 620.0
	warden.attack_damage = 13.0
	warden.attack_range = 2.3
	warden.move_speed = player.walk_speed * 1.06
	warden.vision_range = 160.0
	warden.chase_time = 120.0
	warden.show_health_bar = true
	$Enemies.add_child(warden)
	warden.is_chasing = true
	var variant := Node.new()
	variant.set_script(ZOMBIE_VARIANT)
	variant.kind = ZOMBIE_VARIANT.Kind.WARDEN
	warden.add_child(variant)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 1.9, 0)
	glow.light_color = Color(1.0, 0.3, 0.05)
	glow.light_energy = 1.1
	glow.omni_range = 4.5
	warden.add_child(glow)
	var abilities := Node.new()
	abilities.set_script(preload("res://common/enemy/boss_abilities.gd"))
	warden.add_child(abilities)

func _on_player_dead() -> void:
	if phase != "playing":
		return
	phase = "dead"
	director.stop()
	horror.stop()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_show_menu("dead")

func _start_game() -> void:
	menu_cover.visible = false
	get_tree().paused = false
	player.get_node("WeaponsManager").switch_weapon(1)
	ambient_player.play()
	combat_player.play()
	_begin_cutscene("intro")

func _build_cutscene_ui() -> void:
	cutscene_layer = CanvasLayer.new()
	cutscene_layer.layer = 20
	cutscene_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	cutscene_layer.visible = false
	add_child(cutscene_layer)
	var atmosphere := ColorRect.new()
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var atmosphere_shader := Shader.new()
	atmosphere_shader.code = "shader_type canvas_item;\nvoid fragment(){vec2 p=UV*2.0-1.0;float edge=smoothstep(0.35,1.35,length(p*vec2(0.8,1.0)));float scan=0.012*sin(UV.y*820.0);COLOR=vec4(vec3(0.015,0.035,0.04),0.16+edge*0.34+scan);}"
	var atmosphere_material := ShaderMaterial.new()
	atmosphere_material.shader = atmosphere_shader
	atmosphere.material = atmosphere_material
	cutscene_layer.add_child(atmosphere)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = INK
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else -168.0
		bar.offset_bottom = 84.0 if top else 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cutscene_layer.add_child(bar)
	cutscene_kicker = Label.new()
	cutscene_kicker.anchor_left = 0.06
	cutscene_kicker.anchor_right = 0.76
	cutscene_kicker.offset_top = 21
	cutscene_kicker.offset_bottom = 58
	cutscene_kicker.add_theme_font_override("font", DISPLAY_FONT)
	cutscene_kicker.add_theme_font_size_override("font_size", 25)
	cutscene_kicker.add_theme_color_override("font_color", AMBER)
	cutscene_layer.add_child(cutscene_kicker)
	cutscene_counter = Label.new()
	cutscene_counter.anchor_left = 0.77
	cutscene_counter.anchor_right = 0.94
	cutscene_counter.offset_top = 24
	cutscene_counter.offset_bottom = 58
	cutscene_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cutscene_counter.add_theme_font_override("font", UI_FONT)
	cutscene_counter.add_theme_font_size_override("font_size", 20)
	cutscene_counter.add_theme_color_override("font_color", MUTED)
	cutscene_layer.add_child(cutscene_counter)
	var rule := ColorRect.new()
	rule.color = AMBER
	rule.anchor_left = 0.07
	rule.anchor_right = 0.93
	rule.anchor_top = 1.0
	rule.anchor_bottom = 1.0
	rule.offset_top = -160.0
	rule.offset_bottom = -158.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cutscene_layer.add_child(rule)
	cutscene_title = Label.new()
	cutscene_title.anchor_left = 0.07
	cutscene_title.anchor_right = 0.93
	cutscene_title.anchor_top = 1.0
	cutscene_title.anchor_bottom = 1.0
	cutscene_title.offset_top = -149.0
	cutscene_title.offset_bottom = -94.0
	cutscene_title.add_theme_font_override("font", DISPLAY_FONT)
	cutscene_title.add_theme_font_size_override("font_size", 39)
	cutscene_title.add_theme_color_override("font_color", WHITE)
	cutscene_layer.add_child(cutscene_title)
	cutscene_speaker = Label.new()
	cutscene_speaker.anchor_left = 0.07
	cutscene_speaker.anchor_right = 0.7
	cutscene_speaker.anchor_top = 1.0
	cutscene_speaker.anchor_bottom = 1.0
	cutscene_speaker.offset_top = -105.0
	cutscene_speaker.offset_bottom = -78.0
	cutscene_speaker.add_theme_font_override("font", DISPLAY_FONT)
	cutscene_speaker.add_theme_font_size_override("font_size", 18)
	cutscene_speaker.add_theme_color_override("font_color", AMBER)
	cutscene_layer.add_child(cutscene_speaker)
	cutscene_detail = Label.new()
	cutscene_detail.anchor_left = 0.07
	cutscene_detail.anchor_right = 0.93
	cutscene_detail.anchor_top = 1.0
	cutscene_detail.anchor_bottom = 1.0
	cutscene_detail.offset_top = -78.0
	cutscene_detail.offset_bottom = -37.0
	cutscene_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cutscene_detail.add_theme_font_override("font", UI_FONT)
	cutscene_detail.add_theme_font_size_override("font_size", 25)
	cutscene_detail.add_theme_color_override("font_color", CYAN)
	cutscene_layer.add_child(cutscene_detail)
	var skip := Label.new()
	skip.text = "SPACE  SKIP"
	skip.anchor_left = 0.78
	skip.anchor_right = 0.93
	skip.anchor_top = 1.0
	skip.anchor_bottom = 1.0
	skip.offset_top = -35.0
	skip.offset_bottom = -8.0
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skip.add_theme_font_override("font", UI_FONT)
	skip.add_theme_font_size_override("font_size", 17)
	skip.add_theme_color_override("font_color", MUTED)
	cutscene_layer.add_child(skip)
	cutscene_progress = ColorRect.new()
	cutscene_progress.color = RED
	cutscene_progress.anchor_left = 0.0
	cutscene_progress.anchor_right = 0.0
	cutscene_progress.anchor_top = 1.0
	cutscene_progress.anchor_bottom = 1.0
	cutscene_progress.offset_top = -3.0
	cutscene_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cutscene_layer.add_child(cutscene_progress)
	cutscene_sting = AudioStreamPlayer.new()
	cutscene_sting.stream = preload("res://audio/third_party/long_scifi_sting.ogg")
	cutscene_sting.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	cutscene_sting.volume_db = -9.0
	cutscene_layer.add_child(cutscene_sting)
	cutscene_credits = ColorRect.new()
	cutscene_credits.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cutscene_credits.color = Color("05070a")
	cutscene_credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cutscene_credits.visible = false
	cutscene_layer.add_child(cutscene_credits)
	cutscene_credits_text = Label.new()
	cutscene_credits_text.anchor_left = 0.22
	cutscene_credits_text.anchor_right = 0.78
	cutscene_credits_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cutscene_credits_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cutscene_credits_text.add_theme_font_override("font", DISPLAY_FONT)
	cutscene_credits_text.add_theme_font_size_override("font_size", 32)
	cutscene_credits_text.add_theme_color_override("font_color", WHITE)
	cutscene_credits_text.add_theme_constant_override("line_spacing", 14)
	cutscene_credits.add_child(cutscene_credits_text)
	var credits_skip := Label.new()
	credits_skip.text = "SPACE  SKIP"
	credits_skip.anchor_left = 0.78
	credits_skip.anchor_right = 0.94
	credits_skip.anchor_top = 1.0
	credits_skip.anchor_bottom = 1.0
	credits_skip.offset_top = -42.0
	credits_skip.offset_bottom = -12.0
	credits_skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credits_skip.add_theme_font_override("font", UI_FONT)
	credits_skip.add_theme_font_size_override("font_size", 18)
	credits_skip.add_theme_color_override("font_color", MUTED)
	cutscene_credits.add_child(credits_skip)
	cutscene_fade = ColorRect.new()
	cutscene_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cutscene_fade.color = Color(0, 0, 0, 1)
	cutscene_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cutscene_layer.add_child(cutscene_fade)

func _begin_cutscene(kind: String) -> void:
	phase = "cutscene"
	cutscene_kind = kind
	cutscene_shots.clear()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	$InputManager.process_mode = Node.PROCESS_MODE_DISABLED
	$Enemies.process_mode = Node.PROCESS_MODE_DISABLED
	$HUD/Control.hide()
	player.get_node("WeaponSubViewport").hide()
	mission_label.hide()
	_set_mission_chrome(false)
	prompt_label.hide()
	story_label.hide()
	boss_label.hide()
	cutscene_layer.visible = true
	cutscene_fade.color.a = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if is_instance_valid(cutscene_camera):
		cutscene_camera.queue_free()
	cutscene_camera = Camera3D.new()
	cutscene_camera.fov = 72.0
	cutscene_camera.cull_mask = player.get_node("CameraPivot/CameraHolder/MainCamera").cull_mask
	add_child(cutscene_camera)
	var camera_light := OmniLight3D.new()
	camera_light.light_color = Color(0.42, 0.77, 0.85)
	camera_light.light_energy = 1.1
	camera_light.omni_range = 18.0
	camera_light.shadow_enabled = false
	cutscene_camera.add_child(camera_light)
	if kind == "intro":
		var center: Vector3 = sector.room_center(3, 3)
		_add_cutscene_shot("INCOMING SIGNAL  /  03:17", "THE LAST TRANSMISSION", "H-07, this is Command. Your station went silent eleven hours ago.", center + Vector3(-3, 2.2, 5), center + Vector3(-2, 2.0, 3), center + Vector3(0, 1.5, -2), 4.3, "COMMANDER")
		_add_cutscene_shot("SERVICE DECK  /  LIVE", "", "I reached the service deck. Quarantine doors are sealed from inside.", center + Vector3(3, 2.2, 4), center + Vector3(2, 2.0, 2), center + Vector3(-1, 1.5, -3), 4.2, "YOU")
		_add_cutscene_shot("MEDICAL LOG  /  RECOVERED", "", "A recovered organism escaped med bay. The crew changed within hours.", center + Vector3(-3, 2.1, -4), center + Vector3(-1.5, 1.9, -2), center + Vector3(2, 1.5, 3), 4.3, "COMMANDER")
		_add_cutscene_shot("SERVICE DECK  /  LIVE", "", "I can hear them behind the doors. Any survivors?", center + Vector3(3, 2.2, 4), center + Vector3(2, 2.0, 2), center + Vector3(-1, 1.5, -3), 3.7, "YOU")
		_add_cutscene_shot("BIOSCAN  /  ONE SIGNAL", "", "Only Captain Vale's signal remains. He locked ten sectors around the bridge.", center + Vector3(-3, 2.2, 5), center + Vector3(-2, 2.0, 3), center + Vector3(0, 1.5, -2), 4.5, "COMMANDER")
		_add_cutscene_shot("SERVICE DECK  /  LIVE", "", "Then I'll open them. Keep the evacuation channel clear.", center + Vector3(3, 2.2, 4), center + Vector3(2, 2.0, 2), center + Vector3(-1, 1.5, -3), 4.0, "YOU")
		_add_cutscene_shot("MISSION ORDER  /  PRIORITY ONE", "REACH THE BRIDGE", "End the lockdown, then take the last pod out. I'll be here.", center + Vector3(-3, 2.1, -4), center + Vector3(-1.5, 1.9, -2), center + Vector3(2, 1.5, 3), 4.5, "COMMANDER")
	elif kind == "boss":
		var captain_position: Vector3 = boss.global_position
		var warden: Node3D = $Enemies.get_node("InfectedWarden")
		_add_cutscene_shot("COMMAND BRIDGE  /  ACCESS GRANTED", "THE SIGNAL CAME FROM HERE", "Every door led to the bridge. The captain is still inside.", captain_position + Vector3(15, 6, 14), captain_position + Vector3(10, 4.5, 10), captain_position + Vector3(0, 1.4, 0), 3.7)
		_add_cutscene_shot("PERSONNEL FILE  /  CAPTAIN VALE", "THE FINAL ORDER", "Vale locked the crew in. The infection kept him alive.", captain_position + Vector3(8, 3.5, 7), captain_position + Vector3(5, 2.8, 5), captain_position + Vector3(0, 1.5, 0), 4.0)
		_add_cutscene_shot("THREAT ALERT  /  TWO OFFICERS", "BREAK THE LOCKDOWN", "Defeat Vale and his warden. The evacuation door will open.", warden.global_position + Vector3(-7, 4, 7), warden.global_position + Vector3(-4, 2.9, 5), warden.global_position + Vector3(0, 1.4, 0), 4.2)
	else:
		var exit_position: Vector3 = sector.gate_position(9)
		_add_cutscene_shot("EVACUATION CHANNEL  /  LIVE", "ONE SURVIVOR", "I have your beacon. The escape pod is clear of H-07.", exit_position + Vector3(7, 3, 9), exit_position + Vector3(4, 2.5, 6), exit_position + Vector3(0, 1.4, 0), 4.3, "COMMANDER")
		_add_cutscene_shot("ESCAPE POD  /  LIVE", "", "Vale is gone. He was the last signal on the bridge.", exit_position + Vector3(-6, 3, 7), exit_position + Vector3(-3, 2.5, 4), exit_position + Vector3(0, 1.4, 0), 4.0, "YOU")
		_add_cutscene_shot("FINAL ORDER  /  DECODED", "", "His final order contained the breach. The station stayed sealed.", exit_position + Vector3(7, 3, 9), exit_position + Vector3(4, 2.5, 6), exit_position + Vector3(0, 1.4, 0), 4.2, "COMMANDER")
		_add_cutscene_shot("ESCAPE POD  /  LIVE", "", "I thought he abandoned them. He stayed so I could leave.", exit_position + Vector3(-6, 3, 7), exit_position + Vector3(-3, 2.5, 4), exit_position + Vector3(0, 1.4, 0), 4.1, "YOU")
		_add_cutscene_shot("RESCUE VESSEL  /  APPROACHING", "", "We will quarantine your pod, then bring you home.", exit_position + Vector3(7, 3, 9), exit_position + Vector3(4, 2.5, 6), exit_position + Vector3(0, 1.4, 0), 3.9, "COMMANDER")
		_add_cutscene_shot("ESCAPE POD  /  LIVE", "", "Put every crew name in the record. Not just mine.", exit_position + Vector3(-6, 3, 7), exit_position + Vector3(-3, 2.5, 4), exit_position + Vector3(0, 1.4, 0), 4.0, "YOU")
		_add_cutscene_shot("EVACUATION CHANNEL  /  CLOSING", "", "Already done. H-07 will not disappear in silence.", exit_position + Vector3(7, 3, 9), exit_position + Vector3(4, 2.5, 6), exit_position + Vector3(0, 1.4, 0), 4.0, "COMMANDER")
		cutscene_shots.append({"kicker": "", "title": "", "detail": "", "speaker": "", "start": exit_position + Vector3(4, 2.5, 6), "finish": exit_position + Vector3(4, 2.5, 6), "target": exit_position + Vector3(0, 1.4, 0), "duration": 19.0, "credits": true})
	_show_cutscene_shot(0)
	cutscene_camera.make_current()
	cutscene_sting.play()

func _add_cutscene_shot(kicker: String, title: String, detail: String, start: Vector3, finish: Vector3, target: Vector3, duration: float, speaker: String = "H-07  /  EMERGENCY RECORD") -> void:
	cutscene_shots.append({"kicker": kicker, "title": title, "detail": detail, "speaker": speaker, "start": start, "finish": finish, "target": target, "duration": duration})

func _show_cutscene_shot(index: int) -> void:
	cutscene_shot_index = index
	cutscene_shot_elapsed = 0.0
	var shot: Dictionary = cutscene_shots[index]
	cutscene_start = shot["start"]
	cutscene_end = shot["finish"]
	cutscene_target = shot["target"]
	cutscene_kicker.text = shot["kicker"]
	cutscene_title.text = shot["title"]
	cutscene_speaker.text = shot["speaker"]
	cutscene_speaker.add_theme_color_override("font_color", CYAN if shot["speaker"] == "YOU" else AMBER)
	cutscene_detail.text = shot["detail"]
	cutscene_credits.visible = shot.get("credits", false)
	if cutscene_credits.visible:
		cutscene_credits_text.text = "THREE DAYS AFTER H-07\n\nRESCUE VESSEL  /  MEDICAL DECK\n\nTHE SURVIVOR'S TESTS CAME BACK CLEAR.\nNO INFECTION LEFT THE STATION.\n\nH-07 REMAINS SEALED IN SILENT ORBIT.\nITS FINAL TRANSMISSION WAS RECOVERED.\n\nCAPTAIN VALE HELD THE BRIDGE.\nHIS LAST ORDER KEPT THE BREACH INSIDE.\n\nEVERY CREW MEMBER HAS A NAME\nIN THE MEMORIAL BACK HOME.\n\nH-07  /  THE LAST TRANSMISSION\n\nONE SURVIVOR.\nNO ONE FORGOTTEN."
		var viewport_height: float = get_viewport().get_visible_rect().size.y
		cutscene_credits_text.offset_top = viewport_height
		cutscene_credits_text.offset_bottom = viewport_height + CREDITS_HEIGHT
	cutscene_counter.text = "%02d / %02d" % [index + 1, cutscene_shots.size()]
	cutscene_fade.color.a = 1.0
	cutscene_progress.anchor_right = float(index) / float(cutscene_shots.size())
	cutscene_camera.global_position = cutscene_start
	cutscene_camera.look_at(cutscene_target, Vector3.UP)

func _end_cutscene() -> void:
	if phase != "cutscene":
		return
	cutscene_layer.visible = false
	cutscene_sting.stop()
	player.get_node("CameraPivot/CameraHolder/MainCamera").make_current()
	player.get_node("WeaponSubViewport").show()
	cutscene_camera.queue_free()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	$InputManager.process_mode = Node.PROCESS_MODE_PAUSABLE
	$Enemies.process_mode = Node.PROCESS_MODE_PAUSABLE
	if cutscene_kind == "outro":
		_complete_victory()
		return
	$HUD/Control.show()
	mission_label.show()
	_set_mission_chrome(true)
	prompt_label.show()
	story_label.show()
	phase = "playing"
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if cutscene_kind == "intro":
		director.begin_stage(0, OBJECTIVE_CELLS[0], KILLS_REQUIRED[0])
		horror.start()
		_show_hint("WASD to move. Move the mouse to look around.", 6.0)
	else:
		director.begin_boss_stage(sector.get_boss_cells())
		_show_hint("Dodge marked strikes. Use cover to break pursuit.", 7.0)

func _pause_game() -> void:
	phase = "paused"
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_show_menu("pause")

func _resume_game() -> void:
	phase = "playing"
	$HUD/Control.show()
	mission_label.show()
	_set_mission_chrome(true)
	prompt_label.show()
	story_label.show()
	menu_cover.visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _finish_game() -> void:
	phase = "won"
	director.stop()
	horror.stop()
	_begin_cutscene("outro")

func _complete_victory() -> void:
	phase = "won"
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_show_menu("won")

func _restart_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _build_audio() -> void:
	for node in find_children("*", "AudioStreamPlayer3D", true, false):
		node.bus = "SFX"
	for node in find_children("*", "AudioStreamPlayer", true, false):
		node.bus = "SFX"
	ambient_player = AudioStreamPlayer.new()
	ambient_player.stream = preload("res://audio/third_party/lost_in_a_bad_place.ogg").duplicate()
	ambient_player.stream.loop = true
	ambient_player.volume_db = -16.0
	ambient_player.bus = "Ambience"
	add_child(ambient_player)
	combat_player = AudioStreamPlayer.new()
	combat_player.stream = preload("res://audio/third_party/infestation_control_room.mp3").duplicate()
	combat_player.stream.loop = true
	combat_player.volume_db = -50.0
	combat_player.bus = "Music"
	add_child(combat_player)
	# UI click ensures Web Audio unlocks on first user gesture (browsers block autoplay).
	ui_audio = AudioStreamPlayer.new()
	ui_audio.stream = UI_CLICK
	ui_audio.volume_db = -14.0
	ui_audio.bus = "SFX"
	add_child(ui_audio)

func _play_ui_click() -> void:
	if is_instance_valid(ui_audio):
		ui_audio.play()

func _exit_game() -> void:
	# get_tree().quit() does nothing on Web; return to the main menu instead.
	if OS.has_feature("web"):
		if is_instance_valid(director):
			director.stop()
		if is_instance_valid(horror) and horror.has_method("stop"):
			horror.stop()
		if is_instance_valid(cutscene_sting):
			cutscene_sting.stop()
		get_tree().paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_show_menu("intro")
		return
	get_tree().quit()

func _build_mission_ui() -> void:
	mission_layer = CanvasLayer.new()
	mission_layer.layer = 10
	mission_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(mission_layer)
	var mission_panel := ColorRect.new()
	mission_panel.color = Color(0.015, 0.035, 0.046, 0.84)
	mission_panel.anchor_left = 0.27
	mission_panel.anchor_right = 0.73
	mission_panel.offset_top = 18
	mission_panel.offset_bottom = 88
	mission_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mission_layer.add_child(mission_panel)
	mission_chrome.append(mission_panel)
	var objective_tag := Label.new()
	objective_tag.text = "H-07  /  ACTIVE OBJECTIVE"
	objective_tag.anchor_left = 0.29
	objective_tag.anchor_right = 0.71
	objective_tag.offset_top = 22
	objective_tag.offset_bottom = 44
	objective_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_tag.add_theme_font_override("font", DISPLAY_FONT)
	objective_tag.add_theme_font_size_override("font_size", 17)
	objective_tag.add_theme_color_override("font_color", AMBER)
	mission_layer.add_child(objective_tag)
	mission_chrome.append(objective_tag)
	var objective_rule := ColorRect.new()
	objective_rule.color = AMBER
	objective_rule.anchor_left = 0.27
	objective_rule.anchor_right = 0.73
	objective_rule.offset_top = 18
	objective_rule.offset_bottom = 20
	objective_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mission_layer.add_child(objective_rule)
	mission_chrome.append(objective_rule)
	mission_label = Label.new()
	mission_label.anchor_left = 0.285
	mission_label.anchor_right = 0.715
	mission_label.offset_top = 46
	mission_label.offset_bottom = 80
	mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_label.add_theme_font_override("font", UI_FONT)
	mission_label.add_theme_font_size_override("font_size", 19)
	mission_label.add_theme_color_override("font_color", WHITE)
	mission_label.visible = false
	mission_layer.add_child(mission_label)
	boss_label = Label.new()
	boss_label.anchor_left = 0.25
	boss_label.anchor_right = 0.75
	boss_label.offset_top = 102
	boss_label.offset_bottom = 143
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_font_override("font", DISPLAY_FONT)
	boss_label.add_theme_font_size_override("font_size", 30)
	boss_label.add_theme_color_override("font_color", RED)
	boss_label.visible = false
	mission_layer.add_child(boss_label)
	prompt_label = Label.new()
	prompt_label.anchor_left = 0.3
	prompt_label.anchor_right = 0.7
	prompt_label.anchor_top = 0.73
	prompt_label.anchor_bottom = 0.81
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_override("font", UI_FONT)
	prompt_label.add_theme_font_size_override("font_size", 28)
	prompt_label.add_theme_color_override("font_color", AMBER)
	prompt_label.visible = false
	mission_layer.add_child(prompt_label)
	story_label = Label.new()
	story_label.anchor_left = 0.24
	story_label.anchor_right = 0.76
	story_label.anchor_top = 0.84
	story_label.anchor_bottom = 0.89
	story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_label.add_theme_font_override("font", UI_FONT)
	story_label.add_theme_font_size_override("font_size", 25)
	story_label.add_theme_color_override("font_color", CYAN)
	story_label.visible = false
	mission_layer.add_child(story_label)
	menu_cover = ColorRect.new()
	var veil := ShaderMaterial.new()
	var veil_shader := Shader.new()
	veil_shader.code = "shader_type canvas_item;\nvoid fragment(){float edge=1.0-smoothstep(0.1,0.95,UV.x);float grain=fract(sin(dot(UV,vec2(12.9898,78.233)))*43758.5453)*0.012;COLOR=vec4(vec3(0.008+grain),mix(0.18,0.94,edge));}"
	veil.shader = veil_shader
	menu_cover.material = veil
	menu_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	mission_layer.add_child(menu_cover)

func _show_menu(kind: String) -> void:
	$HUD/Control.hide()
	mission_label.hide()
	_set_mission_chrome(false)
	prompt_label.hide()
	story_label.hide()
	boss_label.hide()
	if kind == "controls":
		phase = "controls"
	elif kind == "intro":
		phase = "menu"
	elif kind == "pause":
		phase = "paused"
	elif kind == "settings":
		phase = "settings"
	menu_cover.visible = true
	for child in menu_cover.get_children():
		child.queue_free()
	if kind == "settings":
		_build_settings_menu()
		return
	if kind == "intro":
		_build_intro_menu()
		return

	var accent := RED if kind == "dead" else (AMBER if kind == "won" else CYAN)
	var title := "YOU DIED" if kind == "dead" else ("ESCAPED" if kind == "won" else ("HOW TO PLAY" if kind == "controls" else "PAUSED"))
	var body: String = "Try another route." if kind == "dead" else ("You made it out." if kind == "won" else ("WASD   Move       SHIFT   Sprint\nMOUSE   Look      LEFT CLICK   Fire\nR   Reload       WHEEL   Switch weapon\nF   Interact     ESC   Pause\nF10   Skip sector" if kind == "controls" else OBJECTIVES[objective_index]))
	var panel := _make_panel(Vector2(760, 700), true)
	var panel_style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
	panel.add_theme_stylebox_override("panel", panel_style)
	var column := _make_column(panel, 24)
	_add_menu_label(column, title, 65 if kind != "won" else 54, WHITE)
	_add_menu_label(column, body, 28, MUTED)
	_add_spacer(column, 32)
	if kind == "pause":
		_add_menu_button(column, "RESUME", _resume_game, true)
		_add_menu_button(column, "SETTINGS", func(): settings_return = "pause"; _show_menu("settings"))
		_add_menu_button(column, "HOW TO PLAY", func(): controls_return = "pause"; _show_menu("controls"))
		_add_menu_button(column, "RESTART RUN", _restart_game)
		_add_menu_button(column, "EXIT GAME", _exit_game)
	elif kind == "controls":
		_add_menu_button(column, "BACK", func(): _show_menu(controls_return), true)
	else:
		_add_menu_label(column, "KILLS  %d" % Global.enemies_killed, 22, accent)
		_add_menu_button(column, "PLAY AGAIN", _restart_game, true)
		_add_menu_button(column, "EXIT GAME", _exit_game)

func _set_mission_chrome(visible_now: bool) -> void:
	for control in mission_chrome:
		control.visible = visible_now

func _build_intro_menu() -> void:
	var top_rule := ColorRect.new()
	top_rule.color = RED
	top_rule.anchor_left = 0.07
	top_rule.anchor_right = 0.93
	top_rule.offset_top = 70
	top_rule.offset_bottom = 72
	top_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_cover.add_child(top_rule)
	var header := Label.new()
	header.text = "H-07  /  EMERGENCY CHANNEL"
	header.anchor_left = 0.07
	header.anchor_right = 0.5
	header.offset_top = 38
	header.offset_bottom = 66
	header.add_theme_font_override("font", DISPLAY_FONT)
	header.add_theme_font_size_override("font_size", 21)
	header.add_theme_color_override("font_color", AMBER)
	menu_cover.add_child(header)
	var column := VBoxContainer.new()
	column.anchor_left = 0.07
	column.anchor_top = 0.22
	column.anchor_right = 0.43
	column.anchor_bottom = 0.87
	column.add_theme_constant_override("separation", 9)
	menu_cover.add_child(column)
	_add_menu_label(column, "HELLGATE", 102, WHITE)
	_add_menu_label(column, "THE LAST TRANSMISSION", 27, RED)
	_add_menu_label(column, "Ten sealed sectors. One missing crew.\nFollow the signal to the command bridge.", 23, MUTED)
	_add_spacer(column, 36)
	_add_menu_button(column, "NEW GAME", _start_game, true)
	_add_menu_button(column, "SETTINGS", func(): settings_return = "intro"; _show_menu("settings"))
	_add_menu_button(column, "HOW TO PLAY", func(): controls_return = "intro"; _show_menu("controls"))
	_add_menu_button(column, "EXIT GAME", _exit_game)
	var dossier := PanelContainer.new()
	dossier.anchor_left = 0.66
	dossier.anchor_top = 0.24
	dossier.anchor_right = 0.93
	dossier.anchor_bottom = 0.79
	var dossier_style := StyleBoxFlat.new()
	dossier_style.bg_color = Color(0.025, 0.055, 0.066, 0.84)
	dossier_style.border_color = Color(0.54, 0.64, 0.64, 0.46)
	dossier_style.set_border_width_all(1)
	dossier_style.set_content_margin_all(24)
	dossier.add_theme_stylebox_override("panel", dossier_style)
	menu_cover.add_child(dossier)
	var report := VBoxContainer.new()
	report.add_theme_constant_override("separation", 13)
	dossier.add_child(report)
	_add_menu_label(report, "INCIDENT REPORT   /   001", 22, AMBER)
	_add_spacer(report, 14)
	_add_menu_label(report, "CREW STATUS", 20, MUTED)
	_add_menu_label(report, "SIGNAL LOST", 42, RED)
	_add_spacer(report, 10)
	_add_menu_label(report, "Station H-07 stopped transmitting after a quarantine breach.", 24, WHITE)
	_add_menu_label(report, "Captain Vale sealed the bridge. The evacuation route remains locked.", 22, MUTED)
	_add_spacer(report, 20)
	_add_menu_label(report, "OBJECTIVE   /   CLEAR 10 SECTORS", 22, AMBER)
	var footer := Label.new()
	footer.text = "ENTER  SELECT     •     ESC  BACK                                      HELLGATE / SURVIVAL PROTOCOL"
	footer.anchor_left = 0.07
	footer.anchor_right = 0.93
	footer.anchor_top = 0.94
	footer.anchor_bottom = 0.98
	footer.add_theme_font_override("font", UI_FONT)
	footer.add_theme_font_size_override("font_size", 18)
	footer.add_theme_color_override("font_color", MUTED)
	menu_cover.add_child(footer)

func _build_settings_menu() -> void:
	var panel := _make_panel(Vector2(790, 790), true)
	var column := _make_column(panel, 14)
	_add_menu_label(column, "SETTINGS", 65, WHITE)
	_add_menu_label(column, "Changes apply and save automatically.", 21, MUTED)
	for entry in [["master", "MASTER VOLUME", 0.0, 1.0, 0.05], ["ambience", "AMBIENCE", 0.0, 1.0, 0.05], ["music", "COMBAT MUSIC", 0.0, 1.0, 0.05], ["effects", "SOUND EFFECTS", 0.0, 1.0, 0.05], ["sensitivity", "MOUSE SENSITIVITY", 0.001, 0.01, 0.0005], ["brightness", "BRIGHTNESS", 0.7, 1.7, 0.05]]:
		_add_setting_slider(column, entry)
	for entry in [["fullscreen", "FULLSCREEN"]]:
		var toggle := CheckButton.new()
		toggle.text = entry[1]
		toggle.button_pressed = settings.values[entry[0]]
		toggle.add_theme_font_override("font", DISPLAY_FONT)
		toggle.add_theme_font_size_override("font_size", 26)
		toggle.custom_minimum_size.y = 48
		column.add_child(toggle)
		toggle.toggled.connect(func(value: bool): _change_setting(entry[0], value))
	_add_menu_button(column, "BACK", func(): _show_menu(settings_return), true)

func _add_setting_slider(column: VBoxContainer, entry: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	column.add_child(row)
	var caption := Label.new()
	caption.text = entry[1]
	caption.custom_minimum_size.x = 255
	caption.add_theme_font_override("font", DISPLAY_FONT)
	caption.add_theme_font_size_override("font_size", 25)
	row.add_child(caption)
	var slider := HSlider.new()
	slider.name = entry[0]
	slider.custom_minimum_size = Vector2(320, 42)
	slider.min_value = entry[2]
	slider.max_value = entry[3]
	slider.step = entry[4]
	slider.value = settings.values[entry[0]]
	row.add_child(slider)
	var number := Label.new()
	number.custom_minimum_size.x = 65
	number.add_theme_font_override("font", UI_FONT)
	number.add_theme_font_size_override("font_size", 25)
	number.text = _setting_value_text(entry[0], slider.value)
	row.add_child(number)
	slider.value_changed.connect(func(value: float):
		number.text = _setting_value_text(entry[0], value)
		_change_setting(entry[0], value))

func _setting_value_text(key: String, value: float) -> String:
	return "%.1f" % (value * 1000.0) if key == "sensitivity" else "%d%%" % roundi(value * 100.0)

func _change_setting(key: String, value: Variant) -> void:
	settings.values[key] = value
	settings.apply(self)
	var error: Error = settings.save_settings()
	if error != OK:
		push_warning("Could not save settings: %s" % error_string(error))

func _make_panel(min_size: Vector2, centered: bool, parent: Control = menu_cover) -> PanelContainer:
	var target: Control = parent
	if centered:
		var center := MarginContainer.new()
		center.position = Vector2(110, 150)
		menu_cover.add_child(center)
		target = center
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.066, 0.88)
	style.border_color = Color(0.54, 0.64, 0.64, 0.42)
	style.set_border_width_all(1)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	target.add_child(panel)
	return panel

func _make_column(panel: PanelContainer, separation: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	panel.add_child(column)
	return column

func _add_spacer(parent: VBoxContainer, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)

func _add_menu_label(parent: VBoxContainer, value: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", UI_FONT)
	if font_size >= 50:
		label.add_theme_font_override("font", DISPLAY_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _add_menu_button(parent: VBoxContainer, title: String, action: Callable, primary: bool = false) -> void:
	var button := Button.new()
	button.text = ("▶   " if primary else "      ") + title
	button.custom_minimum_size = Vector2(0, 58)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", DISPLAY_FONT)
	button.add_theme_font_size_override("font_size", 27)
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.03, 0.06, 0.07, 0.74) if primary else Color(0.01, 0.025, 0.03, 0.48)
	normal.border_color = RED if primary else Color(0.47, 0.59, 0.61, 0.23)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(13)
	button.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = WHITE
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = AMBER
	button.add_theme_stylebox_override("pressed", pressed)
	button.pressed.connect(action)
	button.pressed.connect(_play_ui_click)
	parent.add_child(button)
	button.mouse_entered.connect(button.grab_focus)
	if primary:
		button.call_deferred("grab_focus")
