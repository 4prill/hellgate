extends Control

const UI_FONT := preload("res://resources/fonts/BarlowCondensed-SemiBold.ttf")
const CYAN := Color("a9c8d4")
const WHITE := Color("ecece4")
const MUTED := Color("88a4a7")
const RED := Color("e7514a")

@onready var enemies_label: Label = $EnemiesLabel
@onready var bullets_label: Label = $BulletsLabel
@onready var health_bar: ProgressBar = $HealthBar

var weapons_manager = null
var health_number: Label
var weapon_label: Label
var reserve_label: Label
var fear_bar: ColorRect
var fear_fill: ColorRect
var fear_label: Label


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_build_visuals()
	Global.bullets_changed.connect(_on_bullets_changed)
	Global.player_health_changed.connect(_on_player_health_changed)
	Global.enemy_count_changed.connect(_on_enemy_count_changed)
	
	# Get weapons manager from player
	if Global.player:
		weapons_manager = Global.player.get_node_or_null("WeaponsManager")
	
	# Initial display updates
	_on_bullets_changed()
	_on_enemy_count_changed(Global.enemies_killed)
	if Global.player:
		update_health_bar(Global.player.current_health, 100.0)

func _build_visuals() -> void:
	enemies_label.hide()
	var health_panel := _panel(Vector2(54, -184), Vector2(324, -20), false)
	var ammo_panel := _panel(Vector2(-330, -184), Vector2(-54, -28), true)
	var health_accent := _accent(Vector2(54, -184), Vector2(111, -181), false, CYAN)
	var ammo_accent := _accent(Vector2(-330, -184), Vector2(-273, -181), true, RED)
	move_child(health_panel, 0)
	move_child(ammo_panel, 1)
	move_child(health_accent, 2)
	move_child(ammo_accent, 3)
	var vitals_heading := _label("SUIT VITALS  /  HP", 19, MUTED)
	vitals_heading.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vitals_heading.offset_left = 78
	vitals_heading.offset_top = -170
	health_number = _label("100", 65, CYAN)
	health_number.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_number.offset_left = 78
	health_number.offset_top = -154
	var health_unit := _label("/ 100", 23, MUTED)
	health_unit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_unit.offset_left = 177
	health_unit.offset_top = -118
	weapon_label = _label("", 21, MUTED)
	weapon_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_label.offset_left = -308
	weapon_label.offset_right = -76
	weapon_label.offset_top = -170
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_set_label_style(bullets_label, 72, WHITE)
	bullets_label.offset_left = -306
	bullets_label.offset_top = -142
	bullets_label.offset_right = -158
	bullets_label.offset_bottom = -53
	bullets_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reserve_label = _label("", 25, MUTED)
	reserve_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	reserve_label.offset_left = -154
	reserve_label.offset_top = -99
	var ammo_heading := _label("ROUNDS  /  RESERVE", 17, MUTED)
	ammo_heading.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_heading.offset_left = -307
	ammo_heading.offset_top = -58
	health_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_bar.offset_left = 78
	health_bar.offset_top = -88
	health_bar.offset_right = 300
	health_bar.offset_bottom = -78
	health_bar.custom_minimum_size = Vector2.ZERO
	health_bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.5, 0.6, 0.62, 0.24)
	background.set_corner_radius_all(0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = CYAN
	fill.set_corner_radius_all(0)
	health_bar.add_theme_stylebox_override("background", background)
	health_bar.add_theme_stylebox_override("fill", fill)
	fear_label = _label("FEAR  0%", 18, Color("b9a274"))
	fear_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	fear_label.offset_left = 78
	fear_label.offset_top = -70
	fear_bar = ColorRect.new()
	fear_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fear_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	fear_bar.position = Vector2(78, -40)
	fear_bar.size = Vector2(222, 6)
	fear_bar.color = Color(0.6, 0.5, 0.3, 0.22)
	add_child(fear_bar)
	fear_fill = ColorRect.new()
	fear_fill.color = Color("b9a274")
	fear_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fear_fill.anchor_right = 0.0
	fear_fill.anchor_bottom = 1.0
	fear_bar.add_child(fear_fill)

func _panel(top_left: Vector2, bottom_right: Vector2, right_side: bool) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = Color(0.015, 0.035, 0.046, 0.88)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT if right_side else Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = top_left.x
	panel.offset_top = top_left.y
	panel.offset_right = bottom_right.x
	panel.offset_bottom = bottom_right.y
	add_child(panel)
	return panel

func _accent(top_left: Vector2, bottom_right: Vector2, right_side: bool, tint: Color) -> ColorRect:
	var accent := ColorRect.new()
	accent.color = tint
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	accent.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT if right_side else Control.PRESET_BOTTOM_LEFT)
	accent.offset_left = top_left.x
	accent.offset_top = top_left.y
	accent.offset_right = bottom_right.x
	accent.offset_bottom = bottom_right.y
	add_child(accent)
	return accent

func update_fear(value: float, threshold: float, debuffed: bool = false) -> void:
	fear_fill.anchor_right = clampf(value / 100.0, 0.0, 1.0)
	fear_label.text = "PANIC — DISORIENTED" if debuffed else "FEAR  %d%%" % roundi(value)
	var tint := RED if debuffed or value >= threshold else Color("b9a274")
	fear_label.add_theme_color_override("font_color", tint)
	fear_fill.color = tint

func _label(value: String, size_px: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_label_style(label, size_px, tint)
	add_child(label)
	return label

func _set_label_style(label: Label, size_px: int, tint: Color) -> void:
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)


func _on_bullets_changed() -> void:
	if not weapons_manager or not weapons_manager.current_weapon:
		bullets_label.text = "--"
		reserve_label.text = ""
		return
	
	var current_mag = weapons_manager.get_current_mag()
	var current_ammo = weapons_manager.get_current_ammo()
	
	if weapons_manager.current_weapon.reload_required:
		bullets_label.text = str(current_mag)
		reserve_label.text = "/ " + ("∞" if current_ammo == -1 else str(current_ammo))
	else:
		bullets_label.text = "∞" if current_ammo == -1 else str(current_ammo)
		reserve_label.text = ""
	weapon_label.text = str(weapons_manager.current_weapon.name).to_upper()


func _on_enemy_count_changed(count: int) -> void:
	enemies_label.text = "%02d" % count


func _on_player_health_changed(_health_change:float,current_health:float,max_health:float, _is_enemy_damage:bool) -> void:
	update_health_bar(current_health,max_health)
		

func update_health_bar(current_health,max_health) -> void:
	health_bar.value = current_health
	health_bar.max_value = max_health
	health_number.text = str(roundi(current_health))
	health_number.add_theme_color_override("font_color", RED if current_health <= 25.0 else CYAN)
	var fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill")
	fill.bg_color = RED if current_health <= 25.0 else CYAN
