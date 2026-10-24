extends Node
## Client: menu, connection, input -> server commands, snapshot interpolation,
## visual effects. Builds its scene tree in code.

const Cfg = preload("res://scripts/config.gd")
const MapData = preload("res://scripts/map_data.gd")
const MapView = preload("res://scripts/client/map_view.gd")
const DoorView = preload("res://scripts/client/door_view.gd")
const EntityView = preload("res://scripts/client/entity_view.gd")
const VisionMask = preload("res://scripts/client/vision_mask.gd")
const Hud = preload("res://scripts/client/hud.gd")
const Voice = preload("res://scripts/client/voice.gd")
const Sfx = preload("res://scripts/client/sfx.gd")

# The arena is much larger than the viewport. Rendering its thousands of
# vector primitives directly every frame is expensive on integrated GPUs and
# in WebGL, so static scenery is cached and visibility uses an offscreen layer.
# Keep the scenery cache full-resolution: it is rendered rarely, so lowering
# its resolution saves little ongoing work but noticeably softens the artwork.
const MAP_CACHE_SCALE := 1.0
const FOG_MASK_SCALE := 0.5
const FOG_MASK_FPS := 30.0

enum GraphicsQuality { LOW, MEDIUM, HIGH }
const GRAPHICS_PRESETS := [
	{"name": "Low", "map_scale": 0.65, "fog_scale": 0.28, "fog_fps": 15.0,
		"effect_density": 0.42, "vision_pos_step": 6.0, "vision_angle_step": 0.06, "cone_step_deg": 12.0},
	{"name": "Medium", "map_scale": 0.82, "fog_scale": 0.40, "fog_fps": 24.0,
		"effect_density": 0.70, "vision_pos_step": 4.0, "vision_angle_step": 0.035, "cone_step_deg": 8.0},
	{"name": "High", "map_scale": 1.0, "fog_scale": 0.50, "fog_fps": 30.0,
		"effect_density": 1.0, "vision_pos_step": 2.0, "vision_angle_step": 0.02, "cone_step_deg": 6.0},
]
const SETTINGS_PATH := "user://settings.cfg"

const FOG_SHADER := """
shader_type canvas_item;
uniform float darkness = 0.74;
void fragment() {
	float m = texture(TEXTURE, UV).r;
	COLOR = vec4(0.01, 0.015, 0.03, darkness * (1.0 - m));
}
"""

var map := MapData.new()

# --- Match state (from server) --------------------------------------------
var slot := -1
var state := Cfg.State.WAITING
var deployment := 0.0
var countdown := 0.0
var winner := -1
var selected := 0
var own := []          # Array of Dictionary
var enemies := {}      # idx -> Dictionary
var ghosts := []       # last known enemy positions
var scanned := []      # [[idx, pos]]
var enemy_alive := [true, true, true, true]
var fogs := []         # [[pos, r, t_left]]
var cooldowns := []
var names := ["", ""]
var rematch_votes := [false, false]
var loadout_masks := Cfg.DEFAULT_LOADOUTS.duplicate()
var loadout_ready := [false, false]

# --- Effects -------------------------------------------------------------
var time := 0.0
var tracers := []
var magic_particles := []
var hurts := []
var card_hits := []
var card_shots := []
var corpses := []
var scan_fx := []
var blast_fx := []
var messages := []
var ability_flash := []
var ability_ready_flash := []
var damage_feedback := {}
var preview_ability := -1
var _particle_pool: Array[Dictionary] = []
var _tracer_pool: Array[Dictionary] = []

# Graphics settings default to the previous visual quality. Presets change
# render resolution and work frequency without affecting authoritative play.
var graphics_quality := GraphicsQuality.HIGH
var map_cache_scale := MAP_CACHE_SCALE
var fog_mask_scale := FOG_MASK_SCALE
var fog_mask_fps := FOG_MASK_FPS
var effect_density := 1.0
var vision_pos_step := 2.0
var vision_angle_step := 0.02
var cone_step_deg := 6.0
var screen_shake_enabled := true
var _screen_shake_time := 0.0
var _screen_shake_duration := 0.0
var _screen_shake_strength := 0.0

var world_rotation := 0.0
var voice_pings := []  # world markers for voice orders: {pos, label, t, max}
var _voice_dest := {}  # soldier idx -> destination of its last voice move
var _steer := {}  # soldier idx -> {heading, move, dist, dest, t} of its last steering order
var _sel_lock_until := 0.0
var _face_send_t := 0.0
var _connected := false
var _debug_loadout_sent := false

# --- Nodes -----------------------------------------------------------------
var world: Node2D
var camera: Camera2D
var map_vp: SubViewport
var map_view: Node2D
var map_sprite: Sprite2D
var breakable_view: Node2D
var door_view: Node2D
var entity_view: Node2D
var fog_vp: SubViewport
var vision_mask: Node2D
var fog_sprite: Sprite2D
var world_light: CanvasModulate
var hud: Control
var hud_layer: CanvasLayer
var menu_layer: CanvasLayer
var name_edit: LineEdit
var url_edit: LineEdit
var connect_btn: Button
var host_btn: Button
var status_label: Label
var mic_btn: Button
var menu_panorama: TextureRect
var loadout_layer: CanvasLayer
var loadout_overlay: ColorRect
var loadout_buttons := []
var loadout_slot_labels := []
var loadout_ready_button: Button
var loadout_status: Label
var _updating_loadout_ui := false
var pause_layer: CanvasLayer
var pause_overlay: ColorRect
var pause_main_panel: VBoxContainer
var pause_settings_panel: VBoxContainer
var voice: Node
var sfx: Node
var _host_server_pid := 0
var _host_server_port := 0
var _fog_refresh_elapsed := 0.0
var _last_map_revision := -1
var _last_door_state := -1
var _last_vision_signature := -1

# Prevent the countdown sting from restarting if its audio clip ends early.
var intro_sound_played: bool = false


func _ready() -> void:
	_load_graphics_settings()
	cooldowns.resize(Cfg.ABILITY_COUNT)
	cooldowns.fill(0.0)
	ability_flash.resize(Cfg.ABILITY_COUNT)
	ability_flash.fill(0.0)
	ability_ready_flash.resize(Cfg.ABILITY_COUNT)
	ability_ready_flash.fill(0.0)
	_reset_own()
	voice = Voice.new()
	add_child(voice)
	voice.command_spoken.connect(_on_voice_command)
	voice.status_changed.connect(func(s): print("[Voice] ", s))
	voice.spell_resolver = _voice_spell
	sfx = Sfx.new()
	add_child(sfx)
	_build_world()
	_build_hud()
	_build_menu()
	_build_loadout()
	_build_pause_menu()
	Net.welcomed.connect(_on_welcome)
	Net.snapshot_received.connect(_on_snapshot)
	Net.rejected.connect(_on_rejected)
	Net.connection_ok.connect(_on_connection_ok)
	Net.connection_lost.connect(_on_connection_lost)
	_show_menu(true, "")
	if _query_param("host") != "":
		_on_host_pressed()
	elif _query_param("auto") != "":
		_on_connect_pressed()
	_setup_debug_hooks()


func _exit_tree() -> void:
	_stop_host_server()


## Native-only testing helpers:
##   --screenshot=/path.png [--shot_delay=8]  save a frame and quit
##   --quit_after=3                            quit cleanly after N seconds
##   --demo                                     squad auto-advances toward the centre
##   --say="alpha go to kitchen;fireball mid"   feed voice commands once the match runs
func _setup_debug_hooks() -> void:
	if OS.has_feature("web"):
		return
	var say := _query_param("say")
	if say != "":
		var lines := Array(say.split(";", false))
		var timer := Timer.new()
		timer.wait_time = 1.2
		timer.autostart = true
		add_child(timer)
		timer.timeout.connect(func():
			if state == Cfg.State.PLAYING and not lines.is_empty():
				voice.inject(lines.pop_front()))
	var shot := _query_param("screenshot")
	if shot != "":
		var delay := float(_query_param("shot_delay")) if _query_param("shot_delay") != "" else 8.0
		get_tree().create_timer(delay).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(shot)
			print("screenshot saved: ", shot)
			get_tree().quit())
	if _query_param("demo") != "":
		var timer := Timer.new()
		timer.wait_time = 2.0
		timer.autostart = true
		add_child(timer)
		var step := [0]
		timer.timeout.connect(func():
			if state != Cfg.State.PLAYING:
				return
			step[0] += 1
			var idx: int = step[0] % Cfg.SQUAD_SIZE
			_select(idx)
			var target := Cfg.WORLD_SIZE * 0.5 + Vector2(randf_range(-200, 60) * (1 if slot == 0 else -1), randf_range(-200, 200))
			Net.c_move.rpc_id(1, target, false)
			if step[0] == 4:
				_use_ability(Cfg.Ability.FOG, false)
			if step[0] == 5:
				_use_ability(Cfg.Ability.OUTRAGE, false))
	if _query_param("pause") != "":
		get_tree().create_timer(4.0).timeout.connect(_open_pause)
	var quit_after := float(_query_param("quit_after"))
	if quit_after > 0.0:
		get_tree().create_timer(quit_after).timeout.connect(get_tree().quit)


# --------------------------------------------------------------------------
# Scene construction
# --------------------------------------------------------------------------

func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	world_light = CanvasModulate.new()
	world_light.color = Color.WHITE
	world.add_child(world_light)

	map_vp = SubViewport.new()
	map_vp.size = Vector2i(ceil(Cfg.WORLD_SIZE.x * map_cache_scale), ceil(Cfg.WORLD_SIZE.y * map_cache_scale))
	map_vp.disable_3d = true
	map_vp.transparent_bg = false
	map_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(map_vp)
	map_view = MapView.new()
	map_view.map = map
	map_view.game = self
	map_view.scale = Vector2(map_cache_scale, map_cache_scale)
	map_vp.add_child(map_view)
	_last_map_revision = map.breakable_revision
	map_sprite = Sprite2D.new()
	map_sprite.centered = false
	map_sprite.scale = Vector2.ONE / map_cache_scale
	map_sprite.texture = map_vp.get_texture()
	map_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	world.add_child(map_sprite)
	breakable_view = MapView.new()
	breakable_view.map = map
	breakable_view.game = self
	breakable_view.draw_mode = MapView.DrawMode.BREAKABLES
	world.add_child(breakable_view)
	door_view = DoorView.new()
	door_view.map = map
	door_view.game = self
	world.add_child(door_view)
	camera = Camera2D.new()
	camera.name = "ArenaCamera"
	camera.position = Cfg.WORLD_SIZE * 0.5
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.5
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(Cfg.WORLD_SIZE.x)
	camera.limit_bottom = int(Cfg.WORLD_SIZE.y)
	add_child(camera)

	fog_vp = SubViewport.new()
	fog_vp.size = Vector2i(ceil(Cfg.WORLD_SIZE.x * fog_mask_scale), ceil(Cfg.WORLD_SIZE.y * fog_mask_scale))
	fog_vp.disable_3d = true
	fog_vp.transparent_bg = false
	fog_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(fog_vp)
	vision_mask = VisionMask.new()
	vision_mask.game = self
	vision_mask.scale = Vector2(fog_mask_scale, fog_mask_scale)
	fog_vp.add_child(vision_mask)

	fog_sprite = Sprite2D.new()
	fog_sprite.centered = false
	fog_sprite.scale = Vector2.ONE / fog_mask_scale
	fog_sprite.texture = fog_vp.get_texture()
	fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FOG_SHADER
	mat.shader = sh
	fog_sprite.material = mat
	world.add_child(fog_sprite)

	entity_view = EntityView.new()
	entity_view.game = self
	world.add_child(entity_view)
	world.visible = false


func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = Hud.new()
	hud.game = self
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(hud)
	# Block clicks on the bottom bar from reaching the world.
	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	blocker.offset_top = -Hud.BAR_H
	blocker.offset_bottom = 0.0
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_layer.add_child(blocker)
	mic_btn = Button.new()
	mic_btn.focus_mode = Control.FOCUS_NONE
	mic_btn.anchor_left = 1.0
	mic_btn.anchor_top = 1.0
	mic_btn.anchor_right = 1.0
	mic_btn.anchor_bottom = 1.0
	mic_btn.offset_left = -82.0
	mic_btn.offset_top = -Hud.BAR_H + 10.0
	mic_btn.offset_right = -10.0
	mic_btn.offset_bottom = -Hud.BAR_H + 32.0
	mic_btn.add_theme_font_size_override("font_size", 11)
	mic_btn.pressed.connect(_toggle_voice)
	hud_layer.add_child(mic_btn)
	hud_layer.visible = false


func _toggle_voice() -> void:
	if not voice.available:
		_msg("Voice needs Chrome / Edge / Safari (web build). Keys still work.", Color(1.0, 0.7, 0.4))
		return
	voice.toggle()


func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	menu_panorama = TextureRect.new()
	menu_panorama.name = "CampusFlythrough"
	menu_panorama.texture = load("res://assets/eth_campus_panorama_pixel.png")
	menu_panorama.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	menu_panorama.stretch_mode = TextureRect.STRETCH_SCALE
	menu_panorama.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	menu_panorama.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panorama_ratio := float(menu_panorama.texture.get_width()) / float(menu_panorama.texture.get_height())
	var menu_height: float = get_viewport().get_visible_rect().size.y
	menu_panorama.size = Vector2(menu_height * panorama_ratio, menu_height)
	menu_layer.add_child(menu_panorama)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.025, 0.065, 0.5)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(center)
	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.012, 0.03, 0.06, 0.96)
	panel_style.border_color = Color(0.72, 0.91, 1.0, 0.98)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(10)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	panel_style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(520, 0)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Campus Arcana"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.55, 0.85, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "1 vs 1 · 4 soldiers each · see them before they see you"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.38, 0.88, 1.0))
	box.add_child(sub)
	box.add_child(HSeparator.new())

	var name_label := Label.new()
	name_label.text = "Callsign"
	name_label.add_theme_color_override("font_color", Color(0.82, 0.93, 1.0))
	box.add_child(name_label)
	name_edit = LineEdit.new()
	name_edit.max_length = 16
	_style_menu_field(name_edit)
	var qn := _query_param("name")
	name_edit.text = qn if qn != "" else "Player%d" % (randi() % 900 + 100)
	box.add_child(name_edit)
	var url_label := Label.new()
	url_label.text = "Server"
	url_label.add_theme_color_override("font_color", Color(0.82, 0.93, 1.0))
	box.add_child(url_label)
	url_edit = LineEdit.new()
	url_edit.text = _default_url()
	_style_menu_field(url_edit)
	box.add_child(url_edit)
	var connection_actions := HBoxContainer.new()
	connection_actions.add_theme_constant_override("separation", 10)
	box.add_child(connection_actions)
	connect_btn = Button.new()
	connect_btn.text = "Deploy"
	connect_btn.custom_minimum_size = Vector2(0, 40)
	connect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_menu_button(connect_btn)
	connect_btn.pressed.connect(_on_connect_pressed)
	connection_actions.add_child(connect_btn)
	host_btn = Button.new()
	host_btn.text = "Host Game"
	host_btn.custom_minimum_size = Vector2(0, 40)
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.tooltip_text = "Start an authoritative game server on this computer"
	_style_menu_button(host_btn)
	host_btn.pressed.connect(_on_host_pressed)
	connection_actions.add_child(host_btn)
	if OS.has_feature("web"):
		host_btn.disabled = true
		host_btn.tooltip_text = "Browser builds can join games but cannot launch a local server"
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(1.0, 0.83, 0.28))
	status_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 2)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	box.add_child(HSeparator.new())
	var help := Label.new()
	help.text = "VOICE COMMANDS  ([who] [action] [direction/slot], mic starts on Deploy, V toggles)\n" \
		+ "- Who: \"Alpha\" / \"Bravo\" / \"Charlie\" / \"Delta\" / \"Squad\" (or nobody = selected soldier)\n" \
		+ "- Movement: \"Go left\", \"Alpha move up\", \"Advance\", \"Fall back a bit\", \"Stop\"\n" \
		+ "- Steering: \"Forward 5\", \"Alpha left 30\", \"Turn around\", \"Halt\"\n" \
		+ "- Aim: \"Watch left\", \"Bravo face up\"   - Chain: \"Bravo go left and watch up\"\n" \
		+ "- Abilities: Fog, Scan, Rush, Outrage, Flash, Break Magic, \"Fireball right\", Invisible, \"Spell two\"\n\n" \
		+ "Fallback: LMB move · RMB face · 1-4 / numpad select · W E R ability slots · V mic toggle"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.82, 0.9, 0.96))
	box.add_child(help)
	name_edit.text_submitted.connect(func(_t): _on_connect_pressed())
	url_edit.text_submitted.connect(func(_t): _on_connect_pressed())


func _build_loadout() -> void:
	var tooltip_style := StyleBoxFlat.new()
	tooltip_style.bg_color = Color(0.015, 0.025, 0.045, 0.97)
	tooltip_style.border_color = Color(0.28, 0.76, 0.96, 0.95)
	tooltip_style.set_border_width_all(2)
	tooltip_style.set_corner_radius_all(6)
	
	# Internal padding
	tooltip_style.content_margin_left = 14
	tooltip_style.content_margin_right = 14
	tooltip_style.content_margin_top = 8
	tooltip_style.content_margin_bottom = 8
	
	var current_theme := ThemeDB.get_default_theme()
	current_theme.set_stylebox("panel", "TooltipPanel", tooltip_style)
	
	# Increase this value to make the box wider and shorter vertically:
	current_theme.set_constant("max_width", "TooltipLabel", 580)
	
	loadout_layer = CanvasLayer.new()
	loadout_layer.layer = 15
	add_child(loadout_layer)
	loadout_overlay = ColorRect.new()
	loadout_overlay.color = Color(0.005, 0.012, 0.025, 0.97)
	loadout_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loadout_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	loadout_layer.add_child(loadout_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loadout_overlay.add_child(center)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(1160, 650)
	content.add_theme_constant_override("separation", 12)
	center.add_child(content)

	var title := Label.new()
	title.text = "SQUAD LOADOUT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.82, 0.95, 1.0))
	content.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Choose exactly three abilities for every character"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.52, 0.82, 0.96))
	content.add_child(subtitle)

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 12)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cards)
	var sprite_sheet: Texture2D = load("res://assets/magic_student_sprites.png")
	const SQUAD_NAMES := ["ALPHA", "BRAVO", "CHARLIE", "DELTA"]
	for unit_idx in Cfg.SQUAD_SIZE:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(278, 500)
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.035, 0.06, 0.09, 0.98)
		card_style.border_color = Cfg.TEAM_COLORS[0].lerp(Color.WHITE, 0.2)
		card_style.set_border_width_all(2)
		card_style.set_corner_radius_all(8)
		card_style.content_margin_left = 14
		card_style.content_margin_right = 14
		card_style.content_margin_top = 12
		card_style.content_margin_bottom = 12
		card.add_theme_stylebox_override("panel", card_style)
		cards.add_child(card)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 7)
		card.add_child(column)

		var unit_title := Label.new()
		unit_title.text = "%d  %s" % [unit_idx + 1, SQUAD_NAMES[unit_idx]]
		unit_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unit_title.add_theme_font_size_override("font_size", 22)
		unit_title.add_theme_color_override("font_color", Color.WHITE)
		column.add_child(unit_title)
		var weapon_label := Label.new()
		weapon_label.text = Cfg.WEAPONS[Cfg.SQUAD_WEAPONS[unit_idx]]["name"]
		weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		weapon_label.add_theme_color_override("font_color", Color(0.48, 0.9, 1.0))
		column.add_child(weapon_label)

		var sprite := TextureRect.new()
		sprite.custom_minimum_size = Vector2(0, 126)
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var region := AtlasTexture.new()
		region.atlas = sprite_sheet
		region.region = Rect2(Vector2(unit_idx % 3, unit_idx / 3) * 512.0, Vector2(512, 512))
		sprite.texture = region
		column.add_child(sprite)

		var slot_title := Label.new()
		slot_title.text = "ABILITY SLOTS  ·  3 / 3"
		slot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_title.add_theme_font_size_override("font_size", 12)
		slot_title.add_theme_color_override("font_color", Color(0.72, 0.83, 0.9))
		column.add_child(slot_title)
		var slots := HBoxContainer.new()
		slots.alignment = BoxContainer.ALIGNMENT_CENTER
		slots.add_theme_constant_override("separation", 4)
		column.add_child(slots)
		var unit_slots := []
		for slot_idx in 3:
			var slot_label := Label.new()
			slot_label.custom_minimum_size = Vector2(77, 30)
			slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			slot_label.add_theme_font_size_override("font_size", 10)
			var slot_style := StyleBoxFlat.new()
			slot_style.bg_color = Color(0.04, 0.27, 0.36)
			slot_style.border_color = Color(0.22, 0.72, 0.92)
			slot_style.set_border_width_all(1)
			slot_style.set_corner_radius_all(4)
			slot_label.add_theme_stylebox_override("normal", slot_style)
			slots.add_child(slot_label)
			unit_slots.append(slot_label)
		loadout_slot_labels.append(unit_slots)

		var choose_label := Label.new()
		choose_label.text = "AVAILABLE ABILITIES"
		choose_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		choose_label.add_theme_font_size_override("font_size", 11)
		choose_label.add_theme_color_override("font_color", Color(0.68, 0.72, 0.77))
		column.add_child(choose_label)
		var choices := GridContainer.new()
		choices.columns = 2
		choices.add_theme_constant_override("h_separation", 6)
		choices.add_theme_constant_override("v_separation", 6)
		column.add_child(choices)
		var unit_buttons := []
		for ability in Cfg.ABILITY_COUNT:
			var button := Button.new()
			button.text = "%s  ·  %d MP" % [Cfg.ABILITIES[ability]["name"], int(Cfg.ABILITIES[ability]["mp_cost"])]
			#button.tooltip_text = "%s\n\n%s\nCost: %d MP  ·  Cooldown: %.1fs" % [
				#Cfg.ABILITIES[ability]["name"],
				#Cfg.ABILITIES[ability]["description"],
				#int(Cfg.ABILITIES[ability]["mp_cost"]),
				#float(Cfg.ABILITIES[ability]["cooldown"]),
			#]
			
			var desc: String = Cfg.ABILITIES[ability]["description"]
			
			button.tooltip_text = "%s\n%s\nCost: %d MP  ·  Cooldown: %.1fs" % [
				Cfg.ABILITIES[ability]["name"],
				desc,
				int(Cfg.ABILITIES[ability]["mp_cost"]),
				float(Cfg.ABILITIES[ability]["cooldown"]),
			]
			
			button.toggle_mode = true
			button.custom_minimum_size = Vector2(117, 32)
			button.focus_mode = Control.FOCUS_NONE
			_style_menu_button(button)
			button.add_theme_font_size_override("font_size", 10)
			button.toggled.connect(_on_loadout_toggled.bind(unit_idx, ability))
			choices.add_child(button)
			unit_buttons.append(button)
		loadout_buttons.append(unit_buttons)

	loadout_status = Label.new()
	loadout_status.text = "Configure your squad while waiting for the opponent."
	loadout_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loadout_status.add_theme_font_size_override("font_size", 14)
	loadout_status.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34))
	content.add_child(loadout_status)
	loadout_ready_button = Button.new()
	loadout_ready_button.text = "LOCK IN LOADOUT"
	loadout_ready_button.custom_minimum_size = Vector2(0, 48)
	_style_menu_button(loadout_ready_button)
	loadout_ready_button.pressed.connect(_submit_loadout)
	content.add_child(loadout_ready_button)
	loadout_overlay.visible = false
	_refresh_loadout_ui()


func _loadout_ability_count(mask: int) -> int:
	var count := 0
	for ability in Cfg.ABILITY_COUNT:
		if mask & (1 << ability):
			count += 1
	return count


func _on_loadout_toggled(pressed: bool, unit_idx: int, ability: int) -> void:
	if _updating_loadout_ui or loadout_ready[slot if slot >= 0 else 0]:
		return
	var bit := 1 << ability
	if pressed:
		if _loadout_ability_count(loadout_masks[unit_idx]) >= 3:
			loadout_status.text = "Each character has only three slots. Deselect one first."
			_updating_loadout_ui = true
			loadout_buttons[unit_idx][ability].button_pressed = false
			_updating_loadout_ui = false
			return
		loadout_masks[unit_idx] |= bit
	else:
		loadout_masks[unit_idx] &= ~bit
	_refresh_loadout_ui()


func _refresh_loadout_ui() -> void:
	if loadout_buttons.is_empty():
		return
	_updating_loadout_ui = true
	var complete := true
	for unit_idx in Cfg.SQUAD_SIZE:
		var equipped := []
		for ability in Cfg.ABILITY_COUNT:
			var selected_ability: bool = (loadout_masks[unit_idx] & (1 << ability)) != 0
			loadout_buttons[unit_idx][ability].button_pressed = selected_ability
			loadout_buttons[unit_idx][ability].disabled = slot >= 0 and loadout_ready[slot]
			if selected_ability:
				equipped.append(ability)
		complete = complete and equipped.size() == 3
		for slot_idx in 3:
			loadout_slot_labels[unit_idx][slot_idx].text = "%s · %s" % [Cfg.ABILITY_SLOT_KEYS[slot_idx], Cfg.ABILITIES[equipped[slot_idx]]["name"].to_upper()] if slot_idx < equipped.size() else "%s · EMPTY" % Cfg.ABILITY_SLOT_KEYS[slot_idx]
	_updating_loadout_ui = false
	if loadout_ready_button:
		var mine_ready: bool = slot >= 0 and loadout_ready[slot]
		loadout_ready_button.disabled = not complete or mine_ready
		loadout_ready_button.text = "LOADOUT LOCKED" if mine_ready else "LOCK IN LOADOUT"


func _submit_loadout() -> void:
	for mask in loadout_masks:
		if _loadout_ability_count(mask) != 3:
			loadout_status.text = "Every character must have exactly three abilities."
			return
	loadout_ready_button.disabled = true
	loadout_status.text = "Locking in loadout..."
	Net.c_loadout.rpc_id(1, loadout_masks.duplicate())


func equipped_abilities(unit_idx: int) -> Array:
	var result := []
	if unit_idx < 0 or unit_idx >= loadout_masks.size():
		return result
	for ability in Cfg.ABILITY_COUNT:
		if loadout_masks[unit_idx] & (1 << ability):
			result.append(ability)
	return result


func has_equipped_ability(unit_idx: int, ability: int) -> bool:
	return unit_idx >= 0 and unit_idx < loadout_masks.size() \
		and ability >= 0 and ability < Cfg.ABILITY_COUNT \
		and (loadout_masks[unit_idx] & (1 << ability)) != 0


func ready_ability_casters(ability: int) -> int:
	var count := 0
	var mp_cost: float = Cfg.ABILITIES[ability]["mp_cost"]
	for unit_idx in own.size():
		var unit: Dictionary = own[unit_idx]
		if unit.get("alive", false) and has_equipped_ability(unit_idx, ability) \
				and float(unit.get("mp", Cfg.SOLDIER_MP)) >= mp_cost:
			count += 1
	return count


func _build_pause_menu() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 20
	add_child(pause_layer)
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0.0, 0.006, 0.018, 0.88)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.visible = false
	pause_layer.add_child(pause_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 470)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018, 0.04, 0.07, 0.98)
	panel_style.border_color = Color(0.28, 0.82, 1.0, 0.92)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 34
	panel_style.content_margin_right = 34
	panel_style.content_margin_top = 28
	panel_style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var menu_content := Control.new()
	menu_content.custom_minimum_size = Vector2(356, 406)
	panel.add_child(menu_content)

	pause_main_panel = VBoxContainer.new()
	pause_main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_main_panel.add_theme_constant_override("separation", 12)
	menu_content.add_child(pause_main_panel)
	var pause_title := Label.new()
	pause_title.text = "PAUSE MENU"
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_title.add_theme_font_size_override("font_size", 32)
	pause_title.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0))
	pause_main_panel.add_child(pause_title)
	var warning := Label.new()
	warning.text = "ONLINE MATCH CONTINUES WHILE THIS MENU IS OPEN"
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_font_size_override("font_size", 14)
	warning.add_theme_color_override("font_color", Color(1.0, 0.52, 0.28))
	pause_main_panel.add_child(warning)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18
	pause_main_panel.add_child(spacer)
	var resume_button := Button.new()
	resume_button.text = "RESUME"
	resume_button.custom_minimum_size.y = 54
	_style_menu_button(resume_button)
	resume_button.pressed.connect(_close_pause)
	pause_main_panel.add_child(resume_button)
	var settings_button := Button.new()
	settings_button.text = "SETTINGS"
	settings_button.custom_minimum_size.y = 54
	_style_menu_button(settings_button)
	settings_button.pressed.connect(_show_pause_settings)
	pause_main_panel.add_child(settings_button)
	var leave_button := Button.new()
	leave_button.text = "LEAVE GAME"
	leave_button.custom_minimum_size.y = 54
	_style_menu_button(leave_button)
	leave_button.pressed.connect(_leave_match)
	pause_main_panel.add_child(leave_button)

	pause_settings_panel = VBoxContainer.new()
	pause_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_settings_panel.add_theme_constant_override("separation", 18)
	pause_settings_panel.visible = false
	menu_content.add_child(pause_settings_panel)
	var settings_title := Label.new()
	settings_title.text = "SETTINGS"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_font_size_override("font_size", 32)
	pause_settings_panel.add_child(settings_title)
	var volume_label := Label.new()
	volume_label.text = "MASTER VOLUME"
	volume_label.add_theme_font_size_override("font_size", 17)
	pause_settings_panel.add_child(volume_label)
	var volume_slider := HSlider.new()
	volume_slider.min_value = -30.0
	volume_slider.max_value = 0.0
	volume_slider.step = 1.0
	volume_slider.value = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	volume_slider.custom_minimum_size.y = 48
	volume_slider.value_changed.connect(_set_master_volume)
	pause_settings_panel.add_child(volume_slider)
	var quality_label := Label.new()
	quality_label.text = "GRAPHICS QUALITY"
	quality_label.add_theme_font_size_override("font_size", 17)
	pause_settings_panel.add_child(quality_label)
	var quality_select := OptionButton.new()
	quality_select.custom_minimum_size.y = 44
	for preset in GRAPHICS_PRESETS:
		quality_select.add_item(str(preset["name"]))
	quality_select.select(graphics_quality)
	quality_select.item_selected.connect(_on_graphics_quality_selected)
	pause_settings_panel.add_child(quality_select)
	var hint := Label.new()
	hint.text = "Low reduces map resolution, visibility updates and particles. Changes apply immediately and are saved."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.72, 0.82, 0.9))
	pause_settings_panel.add_child(hint)
	var shake_toggle := CheckButton.new()
	shake_toggle.text = "SCREEN SHAKE (NEARBY EXPLOSIONS)"
	shake_toggle.button_pressed = screen_shake_enabled
	shake_toggle.add_theme_font_size_override("font_size", 15)
	shake_toggle.toggled.connect(_on_screen_shake_toggled)
	pause_settings_panel.add_child(shake_toggle)
	var settings_spacer := Control.new()
	settings_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pause_settings_panel.add_child(settings_spacer)
	var back_button := Button.new()
	back_button.text = "BACK"
	back_button.custom_minimum_size.y = 54
	_style_menu_button(back_button)
	back_button.pressed.connect(_show_pause_main)
	pause_settings_panel.add_child(back_button)

	var controls_margin := MarginContainer.new()
	controls_margin.set_anchor(SIDE_LEFT, 1.0)
	controls_margin.set_anchor(SIDE_RIGHT, 1.0)
	controls_margin.set_anchor(SIDE_TOP, 0.5)
	controls_margin.set_anchor(SIDE_BOTTOM, 0.5)
	controls_margin.offset_left = -300
	controls_margin.offset_right = -20
	controls_margin.offset_top = -170
	controls_margin.offset_bottom = 170
	pause_overlay.add_child(controls_margin)
	var controls_panel := PanelContainer.new()
	var controls_style := StyleBoxFlat.new()
	controls_style.bg_color = Color(0.018, 0.04, 0.07, 0.96)
	controls_style.border_color = Color(0.24, 0.62, 0.8, 0.88)
	controls_style.set_border_width_all(2)
	controls_style.set_corner_radius_all(10)
	controls_style.content_margin_left = 20
	controls_style.content_margin_right = 20
	controls_style.content_margin_top = 18
	controls_style.content_margin_bottom = 18
	controls_panel.add_theme_stylebox_override("panel", controls_style)
	controls_margin.add_child(controls_panel)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	controls_panel.add_child(controls)
	var controls_title := Label.new()
	controls_title.text = "CONTROLS"
	controls_title.add_theme_font_size_override("font_size", 20)
	controls.add_child(controls_title)
	var help := Label.new()
	help.text = "1–4 / Numpad: select soldier\nTab: next living soldier\nLeft click: move / select\nRight click: face direction\nW/E/R: equipped abilities\nVoice: fog, scan, rush, outrage, flash, break magic, fireball, invisible\nVoice: \"spell one / two / three\" casts the W / E / R slot\nVoice: \"alpha forward\" · \"back\" · \"left 30\" · \"turn around\" · \"stop\"\nV: voice toggle\nEscape: close menu"
	help.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
	controls.add_child(help)


func _open_pause() -> void:
	if pause_overlay == null or slot < 0:
		return
	pause_overlay.visible = true
	pause_main_panel.visible = true
	pause_settings_panel.visible = false
	sfx.play("voice", -10.0)


func _close_pause() -> void:
	if pause_overlay == null:
		return
	pause_overlay.visible = false
	pause_main_panel.visible = true
	pause_settings_panel.visible = false
	sfx.play("voice", -10.0)


func _show_pause_settings() -> void:
	pause_main_panel.visible = false
	pause_settings_panel.visible = true
	sfx.play("voice", -10.0)


func _show_pause_main() -> void:
	pause_settings_panel.visible = false
	pause_main_panel.visible = true
	sfx.play("voice", -10.0)


func _set_master_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), clampf(value, -30.0, 0.0))


func _load_graphics_settings() -> void:
	var settings := ConfigFile.new()
	var default_quality := GraphicsQuality.MEDIUM if OS.has_feature("web") else GraphicsQuality.HIGH
	if settings.load(SETTINGS_PATH) == OK:
		graphics_quality = clampi(int(settings.get_value("graphics", "quality", default_quality)), GraphicsQuality.LOW, GraphicsQuality.HIGH)
		screen_shake_enabled = bool(settings.get_value("accessibility", "screen_shake", true))
	else:
		graphics_quality = default_quality
		screen_shake_enabled = true
	_set_quality_variables(graphics_quality)


func _set_quality_variables(quality: int) -> void:
	graphics_quality = clampi(quality, GraphicsQuality.LOW, GraphicsQuality.HIGH)
	var preset: Dictionary = GRAPHICS_PRESETS[graphics_quality]
	map_cache_scale = float(preset["map_scale"])
	fog_mask_scale = float(preset["fog_scale"])
	fog_mask_fps = float(preset["fog_fps"])
	effect_density = float(preset["effect_density"])
	vision_pos_step = float(preset["vision_pos_step"])
	vision_angle_step = float(preset["vision_angle_step"])
	cone_step_deg = float(preset["cone_step_deg"])


func _on_graphics_quality_selected(quality: int) -> void:
	_set_quality_variables(quality)
	if map_vp != null:
		map_vp.size = Vector2i(ceil(Cfg.WORLD_SIZE.x * map_cache_scale), ceil(Cfg.WORLD_SIZE.y * map_cache_scale))
		map_view.scale = Vector2(map_cache_scale, map_cache_scale)
		map_sprite.scale = Vector2.ONE / map_cache_scale
		map_view.queue_redraw()
		map_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if fog_vp != null:
		fog_vp.size = Vector2i(ceil(Cfg.WORLD_SIZE.x * fog_mask_scale), ceil(Cfg.WORLD_SIZE.y * fog_mask_scale))
		vision_mask.scale = Vector2(fog_mask_scale, fog_mask_scale)
		fog_sprite.scale = Vector2.ONE / fog_mask_scale
		_last_vision_signature = -1
		_fog_refresh_elapsed = 1.0
	if entity_view != null and entity_view.has_method("clear_performance_caches"):
		entity_view.clear_performance_caches()
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("graphics", "quality", graphics_quality)
	settings.save(SETTINGS_PATH)


func _on_screen_shake_toggled(enabled: bool) -> void:
	screen_shake_enabled = enabled
	if not enabled:
		_screen_shake_time = 0.0
		if camera != null:
			camera.offset = Vector2.ZERO
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("accessibility", "screen_shake", enabled)
	settings.save(SETTINGS_PATH)


func _leave_match() -> void:
	_close_pause()
	_connected = false
	slot = -1
	Net.leave()
	_stop_host_server()
	_show_menu(true, "Left online match.")


func _style_menu_field(field: LineEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.018, 0.055, 0.1, 0.98)
	normal.border_color = Color(0.28, 0.76, 0.96, 0.95)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var focus := normal.duplicate()
	focus.bg_color = Color(0.025, 0.12, 0.2, 1.0)
	focus.border_color = Color(1.0, 0.83, 0.28, 1.0)
	field.add_theme_stylebox_override("normal", normal)
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0))
	field.add_theme_color_override("caret_color", Color(0.38, 0.88, 1.0))
	field.add_theme_color_override("selection_color", Color(0.08, 0.45, 0.62, 0.9))


func _style_menu_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.32, 0.46, 0.98)
	normal.border_color = Color(0.28, 0.76, 0.96, 0.95)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(5)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.06, 0.45, 0.62, 1.0)
	hover.border_color = Color(0.82, 0.96, 1.0, 1.0)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.015, 0.2, 0.3, 1.0)
	pressed.border_color = Color(1.0, 0.83, 0.28, 1.0)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.02, 0.06, 0.09, 0.94)
	disabled.border_color = Color(0.24, 0.36, 0.43, 0.9)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.65, 0.72))
	button.add_theme_font_size_override("font_size", 16)


func _show_menu(show: bool, status: String) -> void:
	if show and pause_overlay != null:
		pause_overlay.visible = false
	if show and loadout_overlay != null:
		loadout_overlay.visible = false
	menu_layer.visible = show
	world.visible = not show
	hud_layer.visible = not show
	status_label.text = status
	connect_btn.disabled = false
	host_btn.disabled = OS.has_feature("web")


# --------------------------------------------------------------------------
# Connection
# --------------------------------------------------------------------------

func _query_param(key: String) -> String:
	if not OS.has_feature("web"):
		for a in OS.get_cmdline_user_args():
			if a == "--" + key:
				return "1"
			if a.begins_with("--" + key + "="):
				return a.substr(key.length() + 3)
		return ""
	var v = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s') || ''" % key, true)
	return str(v) if v != null else ""


func _default_url() -> String:
	var q := _query_param("server")
	if q != "":
		return q
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("""(function(){
			if (location.protocol === 'https:') return 'wss://' + location.host + '/ws';
			return 'ws://' + (location.hostname || 'localhost') + ':%d';
		})()""" % Cfg.DEFAULT_PORT, true)
		if v != null:
			return str(v)
	return "ws://127.0.0.1:%d" % Cfg.DEFAULT_PORT


func _on_connect_pressed() -> void:
	_stop_host_server()
	voice.start()
	var url := url_edit.text.strip_edges()
	_connect_to_url(url)


func _connect_to_url(url: String) -> void:
	if not (url.begins_with("ws://") or url.begins_with("wss://")):
		status_label.text = "Server address must start with ws:// or wss://"
		return
	connect_btn.disabled = true
	host_btn.disabled = true
	status_label.text = "Connecting to %s ..." % url
	var err := Net.join(url)
	if err != OK:
		_show_menu(true, "Could not start connection (error %d)" % err)


func _on_host_pressed() -> void:
	if OS.has_feature("web"):
		status_label.text = "Hosting is available in the desktop build. Browser players can join a host."
		return
	_stop_host_server()
	var requested_port := int(_query_param("host_port"))
	_host_server_port = requested_port if requested_port > 0 and requested_port <= 65535 else Cfg.DEFAULT_PORT
	var port_probe := TCPServer.new()
	var port_error := port_probe.listen(_host_server_port)
	port_probe.stop()
	if port_error != OK:
		_show_menu(true, "Port %d is already in use. Stop the other server or join it with Deploy." % _host_server_port)
		return
	voice.start()
	connect_btn.disabled = true
	host_btn.disabled = true
	status_label.text = "Starting a game server on port %d ..." % _host_server_port
	var args := PackedStringArray()
	args.append("--headless")
	if OS.has_feature("editor"):
		args.append("--path")
		args.append(ProjectSettings.globalize_path("res://"))
	args.append("--")
	args.append("--server")
	args.append("--port=%d" % _host_server_port)
	_host_server_pid = OS.create_process(OS.get_executable_path(), args, false)
	if _host_server_pid <= 0:
		_host_server_pid = 0
		_show_menu(true, "Could not start the local game server.")
		return
	await get_tree().create_timer(0.8).timeout
	if not OS.is_process_running(_host_server_pid):
		_host_server_pid = 0
		_show_menu(true, "The local game server stopped before it was ready.")
		return
	url_edit.text = "ws://127.0.0.1:%d" % _host_server_port
	_connect_to_url(url_edit.text)


func _stop_host_server() -> void:
	if _host_server_pid <= 0:
		return
	if OS.is_process_running(_host_server_pid):
		OS.kill(_host_server_pid)
	_host_server_pid = 0
	_host_server_port = 0


func _on_connection_ok() -> void:
	_connected = true
	Net.c_hello.rpc_id(1, name_edit.text)


func _on_welcome(s: int) -> void:
	slot = s
	world_rotation = PI if slot == 1 else 0.0
	world.rotation = world_rotation
	world.position = Cfg.WORLD_SIZE if slot == 1 else Vector2.ZERO
	_reset_round_visuals()
	_show_menu(false, "")
	sfx.play("start", -6.0)


func _on_rejected(reason: String) -> void:
	Net.leave()
	_stop_host_server()
	_show_menu(true, reason)


func _on_connection_lost(reason: String) -> void:
	_connected = false
	slot = -1
	Net.leave()
	_stop_host_server()
	_show_menu(true, reason + ". Is the server running?")


# --------------------------------------------------------------------------
# Snapshots
# --------------------------------------------------------------------------

func _reset_own() -> void:
	own.clear()
	for i in Cfg.SQUAD_SIZE:
		own.append({"idx": i, "pos": Vector2.ZERO, "disp": Vector2.ZERO, "facing": 0.0, "disp_facing": 0.0,
			"hp": Cfg.SOLDIER_HP, "mp": Cfg.SOLDIER_MP, "flags": 8, "alive": true, "target": Vector2.ZERO, "watch": INF, "init": false})


func _reset_round_visuals() -> void:
	_reset_own()
	enemies.clear()
	ghosts.clear()
	scanned.clear()
	_recycle_effects(tracers, _tracer_pool)
	_recycle_effects(magic_particles, _particle_pool)
	hurts.clear()
	card_hits.clear()
	card_shots.clear()
	corpses.clear()
	scan_fx.clear()
	blast_fx.clear()
	damage_feedback.clear()
	_screen_shake_time = 0.0
	if camera != null:
		camera.offset = Vector2.ZERO


func _on_snapshot(d: Dictionary) -> void:
	var prev_state := state
	state = d["st"]
	map.set_doors_closed(state != Cfg.State.DEPLOYMENT)
	map.apply_breakable_state(d.get("br", []))
	loadout_ready = d.get("rd", [false, false])
	if state == Cfg.State.LOADOUT:
		if prev_state != Cfg.State.LOADOUT or (slot >= 0 and loadout_ready[slot]):
			loadout_masks = d.get("lo", Cfg.DEFAULT_LOADOUTS).duplicate()
		loadout_overlay.visible = true
		hud_layer.visible = false
		var opponent := 1 - slot
		var connected: Array = d.get("conn", [false, false])
		if slot >= 0 and loadout_ready[slot]:
			loadout_status.text = "Waiting for opponent to lock in..." if not loadout_ready[opponent] else "Both squads ready."
		elif opponent >= 0 and opponent < connected.size() and not connected[opponent]:
			loadout_status.text = "Configure your squad while waiting for an opponent..."
		elif loadout_ready[opponent]:
			loadout_status.text = "Opponent is ready. Lock in your squad."
		else:
			loadout_status.text = "Both players are choosing abilities."
		_refresh_loadout_ui()
		if not OS.has_feature("web") and _query_param("auto_loadout") != "" and not _debug_loadout_sent:
			_debug_loadout_sent = true
			Net.c_loadout.rpc_id(1, loadout_masks.duplicate())
	elif loadout_overlay.visible:
		loadout_overlay.visible = false
		hud_layer.visible = not menu_layer.visible
	if state == Cfg.State.DEPLOYMENT and prev_state != Cfg.State.DEPLOYMENT:
		_reset_round_visuals()
		intro_sound_played = false
		sfx.intro_sound_player.stop()
		sfx.play("door_open", -4.0)
		for team in 2:
			_spawn_magic_burst(map.entry_position(team, 1), Color(Cfg.TEAM_COLORS[team]), Vector2.ZERO, 12)
	if state == Cfg.State.COUNTDOWN and prev_state == Cfg.State.DEPLOYMENT:
		sfx.play("door_close", -4.0)
		if not intro_sound_played:
			intro_sound_played = true
			sfx.play("intro_sound")
	if state == Cfg.State.PLAYING and prev_state == Cfg.State.COUNTDOWN:
		sfx.play("fight", -3.0)
	if state == Cfg.State.WAITING and prev_state != Cfg.State.WAITING:
		_reset_round_visuals()
	deployment = d.get("dp", 0.0)
	countdown = d["ct"]
	winner = d["win"]
	if time > _sel_lock_until:
		selected = d["sel"]
	for e in d["own"]:
		var o: Dictionary = own[e[0]]
		o["pos"] = e[1]
		o["facing"] = e[2]
		o["hp"] = e[3]
		o["flags"] = e[4]
		o["alive"] = e[4] & 8 != 0
		o["target"] = e[5]
		o["watch"] = e[6]
		o["mp"] = e[7] if e.size() > 7 else Cfg.SOLDIER_MP
		if not o["init"] or o["disp"].distance_to(o["pos"]) > 120.0:
			o["disp"] = o["pos"]
			o["disp_facing"] = o["facing"]
			o["init"] = true
	var seen := {}
	for e in d["en"]:
		var idx: int = e[0]
		seen[idx] = true
		if not enemies.has(idx):
			enemies[idx] = {"disp": e[1], "disp_facing": e[2]}
			for g in ghosts.duplicate():
				if g["idx"] == idx:
					ghosts.erase(g)
		var en: Dictionary = enemies[idx]
		if en.has("hp") and int(e[3]) < int(en["hp"]):
			_mark_damage_feedback(1 - slot, idx, int(en["hp"]) - int(e[3]))
		en["pos"] = e[1]
		en["facing"] = e[2]
		en["hp"] = e[3]
		en["flags"] = e[4]
	for idx in enemies.keys():
		if not seen.has(idx):
			ghosts.append({"idx": idx, "pos": enemies[idx]["disp"], "t": 2.0})
			enemies.erase(idx)
	scanned = d["sc"]
	enemy_alive = d["ea"]
	fogs = d["fg"]
	var previous_cooldowns: Array = cooldowns.duplicate()
	cooldowns = d["cd"]
	var cooldown_finished := false
	for ability in mini(previous_cooldowns.size(), cooldowns.size()):
		if float(previous_cooldowns[ability]) > 0.05 and float(cooldowns[ability]) <= 0.05:
			ability_ready_flash[ability] = 1.0
			if selected >= 0 and has_equipped_ability(selected, ability):
				cooldown_finished = true
	if cooldown_finished:
		sfx.play("cooldown_ready", -9.0)
	rematch_votes = d["rm"]
	names = d["names"]
	for ev in d["ev"]:
		_handle_event(ev)


func _handle_event(ev: Array) -> void:
	match ev[0]:
		"msg":
			_msg(ev[1], Color(1, 1, 1))
		"deny":
			_msg("%s: %s" % [Cfg.ABILITIES[ev[1]]["name"], ev[2]], Color(1.0, 0.5, 0.4))
			sfx.play("deny", -8.0)
		"ability":
			var a: int = ev[1]
			ability_flash[a] = 1.0
			var caster_name := _soldier_name(ev[2]).capitalize()
			var caster_count: int = ev[4] if ev.size() > 4 else 1
			var caster_label := caster_name if caster_count == 1 else "%s + %d squadmates" % [caster_name, caster_count - 1]
			_msg("%s! (%s%s)" % [Cfg.ABILITIES[a]["name"], caster_label, ", voice" if ev[3] else ""], Color(0.5, 1.0, 0.7))
			sfx.play("ability", -6.0)
		"scan":
			scan_fx.append({"origin": ev[1], "radius": ev[2], "t": 1.0, "max": 1.0})
			_msg("Scan: %d moving contact%s" % [ev[3], "" if ev[3] == 1 else "s"], Color(1.0, 0.6, 0.5))
		"fireball":
			blast_fx.append({"origin": ev[1], "radius": ev[2], "team": ev[3], "t": 0.55, "max": 0.55})
			_spawn_magic_burst(ev[1], Color(1.0, 0.34, 0.04), Vector2.ZERO, 18)
			_add_screen_shake(ev[1], 9.0, maxf(360.0, float(ev[2]) * 5.0))
			sfx.play("explosion", -6.0)
		"breakable":
			var debris_pos: Vector2 = ev[2]
			var is_glass: bool = ev.size() > 3 and str(ev[3]) == "glass_wall"
			var destroyed: bool = bool(ev[4]) if ev.size() > 4 else true
			if destroyed:
				_spawn_magic_burst(debris_pos, Color("8edcec") if is_glass else Color("b8793f"), Vector2.ZERO, 34 if is_glass else 30)
				_spawn_magic_burst(debris_pos, Color("d9fbff") if is_glass else Color("5d3b25"), Vector2.ZERO, 24 if is_glass else 18)
				_add_screen_shake(debris_pos, 3.5 if is_glass else 2.5, 260.0)
				sfx.play("glass_break" if is_glass else "wood_break", -2.0)
			else:
				_spawn_magic_burst(debris_pos, Color("bceef5") if is_glass else Color("c28a52"), Vector2.ZERO, 12 if is_glass else 9)
				sfx.play("glass_crack" if is_glass else "wood_hit", -5.0)
		"mega_shot":
			var team: int = ev[1]
			var from: Vector2 = ev[3]
			var endpoint: Vector2 = ev[4]
			var spell_color := Color(0.22, 0.88, 1.0) if team == slot else Color(1.0, 0.18, 0.78)
			_spawn_tracer(from, endpoint, 0.42, spell_color, ev[5] > 0, 3.2)
			_spawn_magic_burst(from, spell_color, (endpoint - from).normalized(), 18)
			_spawn_magic_burst(endpoint, spell_color.lerp(Color.WHITE, 0.4), (endpoint - from).normalized(), 28 if ev[5] > 0 else 15)
			if ev[5] > 0:
				_add_screen_shake(endpoint, 5.0, 300.0)
			if team == slot:
				card_shots.append({"idx": ev[2], "t": 0.65})
			sfx.play("cast_burst", -2.0)
			sfx.play("impact_hit" if ev[5] > 0 else "impact_miss", -7.0)
		"shot":
			var team: int = ev[1]
			var weapon: int = Cfg.SQUAD_WEAPONS[ev[2]]
			var from: Vector2 = ev[3]
			if team == slot:
				card_shots.append({"idx": ev[2], "t": 0.65})
			var spell_color := Color(0.12, 0.92, 1.0) if team == slot else Color(1.0, 0.16, 0.72)
			for end in ev[4]:
				_spawn_tracer(from, end, 0.26, spell_color, ev[5] > 0)
				_spawn_magic_burst(end, spell_color.lerp(Color.WHITE, 0.35), (end - from).normalized(), 7 if ev[5] > 0 else 3)
			_spawn_magic_burst(from, spell_color, Vector2.from_angle(own[ev[2]]["disp_facing"]) if team == slot and ev[2] < own.size() else Vector2.RIGHT, 8)
			var snd: String = ["cast", "cast_fast", "cast_burst"][weapon]
			sfx.play(snd, -10.0 if team == slot else -6.0)
			sfx.play("impact_hit" if ev[5] > 0 else "impact_miss", -6.0 if ev[5] > 0 else -12.0)
		"incoming":
			hurts.append({"idx": ev[1], "angle": ev[2], "dmg": ev[3], "t": 1.2})
			if ev[1] < own.size():
				var incoming_dir := Vector2.from_angle(ev[2])
				_spawn_magic_burst(own[ev[1]]["disp"] + incoming_dir * Cfg.SOLDIER_RADIUS, Color(1.0, 0.18, 0.72), -incoming_dir, 9)
			sfx.play("impact_miss" if ev[3] == 0 else "impact_hit", -12.0 if ev[3] == 0 else -3.0)
		"card_hit":
			card_hits.append({"idx": ev[1], "dmg": ev[2], "t": 0.75})
			_mark_damage_feedback(slot, int(ev[1]), int(ev[2]))
		"kill":
			var team: int = ev[1]
			var idx: int = ev[2]
			corpses.append({"pos": ev[3], "team": team, "idx": idx})
			var character_name := _soldier_name(idx).capitalize()
			if team == slot:
				_msg("%s is down!" % character_name, Color(1.0, 0.4, 0.3))
			else:
				_msg("Enemy %s eliminated!" % character_name, Color(0.5, 1.0, 0.5))
			sfx.play("kill", -3.0)


func _msg(text: String, col: Color) -> void:
	messages.append({"text": text, "color": col, "t": 3.0})
	while messages.size() > 4:
		messages.pop_front()


func _spawn_magic_burst(at: Vector2, col: Color, direction: Vector2, amount: int) -> void:
	var base_angle := direction.angle() if direction.length_squared() > 0.001 else 0.0
	var adjusted_amount := maxi(1, roundi(amount * effect_density))
	var particle_cap: int = int([70, 120, 190][graphics_quality])
	var spawn_count: int = maxi(0, mini(adjusted_amount, particle_cap - magic_particles.size()))
	for _i in spawn_count:
		var angle := base_angle + randf_range(-0.95, 0.95)
		var particle: Dictionary = _particle_pool.pop_back() if not _particle_pool.is_empty() else {}
		particle["pos"] = at + Vector2.from_angle(angle) * randf_range(0.0, 4.0)
		particle["vel"] = Vector2.from_angle(angle) * randf_range(35.0, 115.0)
		particle["t"] = randf_range(0.20, 0.42)
		particle["max"] = 0.42
		particle["color"] = col
		particle["size"] = randf_range(1.5, 3.3)
		magic_particles.append(particle)


func _spawn_tracer(from: Vector2, to: Vector2, lifetime: float, color: Color, hit: bool, scale := 1.0) -> void:
	var tracer: Dictionary = _tracer_pool.pop_back() if not _tracer_pool.is_empty() else {}
	tracer["a"] = from
	tracer["b"] = to
	tracer["t"] = lifetime
	tracer["max"] = lifetime
	tracer["color"] = color
	tracer["seed"] = randf() * TAU
	tracer["hit"] = hit
	tracer["scale"] = scale
	tracers.append(tracer)


func _recycle_effects(active: Array, pool: Array[Dictionary]) -> void:
	for effect in active:
		if effect is Dictionary:
			effect.clear()
			pool.append(effect)
	active.clear()


func _feedback_key(team: int, idx: int) -> String:
	return "%d_%d" % [team, idx]


func _mark_damage_feedback(team: int, idx: int, damage: int) -> void:
	if team < 0 or idx < 0 or damage <= 0:
		return
	var key := _feedback_key(team, idx)
	var prior: Dictionary = damage_feedback.get(key, {})
	damage_feedback[key] = {
		"t": 2.0,
		"flash": 0.22,
		"damage": damage + int(prior.get("damage", 0)) if float(prior.get("t", 0.0)) > 1.72 else damage,
	}


func damage_feedback_for(team: int, idx: int) -> Dictionary:
	return damage_feedback.get(_feedback_key(team, idx), {})


func _tick_damage_feedback(dt: float) -> void:
	for key in damage_feedback.keys():
		var feedback: Dictionary = damage_feedback[key]
		feedback["t"] = maxf(0.0, float(feedback["t"]) - dt)
		feedback["flash"] = maxf(0.0, float(feedback["flash"]) - dt)
		if float(feedback["t"]) <= 0.0:
			damage_feedback.erase(key)


func _add_screen_shake(origin: Vector2, strength: float, radius: float) -> void:
	if not screen_shake_enabled or selected < 0 or selected >= own.size() or not bool(own[selected].get("init", false)):
		return
	var distance := origin.distance_to(own[selected]["disp"])
	if distance >= radius:
		return
	var proximity := 1.0 - distance / radius
	_screen_shake_duration = 0.34
	_screen_shake_time = _screen_shake_duration
	_screen_shake_strength = maxf(_screen_shake_strength, strength * proximity)


func _update_screen_shake(dt: float) -> void:
	if camera == null:
		return
	if not screen_shake_enabled or _screen_shake_time <= 0.0:
		camera.offset = Vector2.ZERO
		_screen_shake_strength = 0.0
		return
	_screen_shake_time = maxf(0.0, _screen_shake_time - dt)
	var fade := _screen_shake_time / maxf(_screen_shake_duration, 0.001)
	camera.offset = Vector2(sin(time * 83.0), cos(time * 97.0)) * _screen_shake_strength * fade


func fog_list() -> Array:
	var out := []
	for s in fogs:
		out.append([s[0], s[1]])
	return out


# --------------------------------------------------------------------------
# Frame update
# --------------------------------------------------------------------------

func _process(dt: float) -> void:
	time += dt
	_update_cached_layers(dt)
	if menu_layer != null and menu_layer.visible and menu_panorama != null:
		var travel := maxf(0.0, menu_panorama.size.x - get_viewport().get_visible_rect().size.x)
		var flythrough := 0.5 - 0.5 * cos(time * 0.15)
		menu_panorama.position = Vector2(-travel * flythrough, sin(time * 0.21) * 8.0)
	var k := 1.0 - exp(-18.0 * dt)
	for o in own:
		o["disp"] = o["disp"].lerp(o["pos"], k)
		o["disp_facing"] = lerp_angle(o["disp_facing"], o["facing"], k)
	if camera != null and slot >= 0 and selected >= 0 and selected < own.size() and own[selected]["init"]:
		var focus: Vector2 = own[selected]["disp"]
		if slot == 1:
			focus = Cfg.WORLD_SIZE - focus
		camera.position = focus
	_update_screen_shake(dt)
	for idx in enemies:
		var e: Dictionary = enemies[idx]
		e["disp"] = e["disp"].lerp(e["pos"], k)
		e["disp_facing"] = lerp_angle(e["disp_facing"], e["facing"], k)
	_tick_pooled_effects(tracers, _tracer_pool, dt)
	_tick_magic_particles(dt)
	_tick_list(hurts, dt)
	_tick_list(card_hits, dt)
	_tick_list(card_shots, dt)
	_tick_list(scan_fx, dt)
	_tick_list(blast_fx, dt)
	_tick_list(ghosts, dt)
	_tick_list(messages, dt)
	_tick_list(voice_pings, dt)
	_tick_damage_feedback(dt)
	if mic_btn:
		mic_btn.text = "Mic ON [V]" if voice.enabled else "Mic OFF [V]"
	for a in Cfg.ABILITY_COUNT:
		ability_flash[a] = maxf(0.0, ability_flash[a] - dt * 2.0)
		ability_ready_flash[a] = maxf(0.0, ability_ready_flash[a] - dt)
	if world_light:
		if state == Cfg.State.DEPLOYMENT:
			world_light.color = Color(1.0, 0.98, 0.90)
		elif state == Cfg.State.COUNTDOWN:
			var light_level := _countdown_light_level()
			world_light.color = Color(light_level, light_level * 0.96, light_level * 0.82)
		else:
			world_light.color = Color.WHITE
	# Continuous right-drag facing
	if slot >= 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not menu_layer.visible and not pause_overlay.visible:
		_face_send_t -= dt
		if _face_send_t <= 0.0:
			_face_send_t = 0.05
			Net.c_face.rpc_id(1, world.get_local_mouse_position())
	
	if state == Cfg.State.PLAYING and !sfx.gameplay_sound_player.playing:
		sfx.play("gameplay_music")
	
	if state == Cfg.State.ENDED and sfx.gameplay_sound_player.playing:
		sfx.gameplay_sound_player.stop()

func _update_cached_layers(dt: float) -> void:
	# The detailed arena remains cached. Destruction refreshes only the small
	# retained breakables overlay; deployment doors use their own overlay too.
	var map_revision_changed := map.breakable_revision != _last_map_revision
	if map_revision_changed:
		_last_map_revision = map.breakable_revision
		_last_vision_signature = -1
		if breakable_view != null:
			breakable_view.queue_redraw()
	if door_view != null and (state == Cfg.State.DEPLOYMENT or state != _last_door_state):
		_last_door_state = state
		door_view.queue_redraw()

	# Visibility is cosmetic; the server owns enemy visibility. Rebuild the mask
	# only when a unit/fog/occluder changed, capped by the selected quality preset.
	var reveal_all_now := state == Cfg.State.DEPLOYMENT or state == Cfg.State.COUNTDOWN or state == Cfg.State.ENDED
	if vision_mask != null:
		vision_mask.reveal_all = reveal_all_now
	var vision_signature := _vision_signature(reveal_all_now)
	_fog_refresh_elapsed += dt
	if vision_mask != null and fog_vp != null and vision_signature != _last_vision_signature \
			and _fog_refresh_elapsed >= 1.0 / fog_mask_fps:
		_fog_refresh_elapsed = fmod(_fog_refresh_elapsed, 1.0 / fog_mask_fps)
		_last_vision_signature = vision_signature
		vision_mask.queue_redraw()
		fog_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _vision_signature(reveal_all_now: bool) -> int:
	var signature := 1 if reveal_all_now else 0
	signature = signature * 31 + map.breakable_revision
	if reveal_all_now:
		return signature
	for unit in own:
		if not bool(unit.get("alive", false)):
			continue
		var p: Vector2 = unit.get("disp", Vector2.ZERO)
		signature = signature * 31 + roundi(p.x / vision_pos_step)
		signature = signature * 31 + roundi(p.y / vision_pos_step)
		signature = signature * 31 + roundi(float(unit.get("disp_facing", 0.0)) / vision_angle_step)
	for fog in fogs:
		signature = signature * 31 + roundi(float(fog[0].x) / vision_pos_step)
		signature = signature * 31 + roundi(float(fog[0].y) / vision_pos_step)
		signature = signature * 31 + roundi(float(fog[1]))
	return signature

func _countdown_light_level() -> float:
	var elapsed := clampf(Cfg.COUNTDOWN - countdown, 0.0, Cfg.COUNTDOWN)
	# One blink, a long pause, two blinks, three blinks, then a final shutdown.
	for centre in [0.18, 0.90, 1.08, 1.55, 1.71, 1.87]:
		var distance: float = absf(elapsed - centre)
		if distance < 0.065:
			return lerpf(0.12, 1.0, smoothstep(0.0, 0.065, distance))
	if elapsed >= 2.45:
		return lerpf(1.0, 0.12, smoothstep(2.45, 2.62, elapsed))
	return 1.0


func _tick_list(list: Array, dt: float) -> void:
	for i in range(list.size() - 1, -1, -1):
		list[i]["t"] -= dt
		if list[i]["t"] <= 0.0:
			list.remove_at(i)


func _tick_magic_particles(dt: float) -> void:
	for i in range(magic_particles.size() - 1, -1, -1):
		var p: Dictionary = magic_particles[i]
		p["t"] -= dt
		p["pos"] += p["vel"] * dt
		p["vel"] *= exp(-5.0 * dt)
		if p["t"] <= 0.0:
			magic_particles.remove_at(i)
			p.clear()
			_particle_pool.append(p)


func _tick_pooled_effects(active: Array, pool: Array[Dictionary], dt: float) -> void:
	for i in range(active.size() - 1, -1, -1):
		var effect: Dictionary = active[i]
		effect["t"] -= dt
		if effect["t"] <= 0.0:
			active.remove_at(i)
			effect.clear()
			pool.append(effect)


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if loadout_overlay != null and loadout_overlay.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		if slot >= 0 and not menu_layer.visible:
			if pause_overlay.visible and pause_settings_panel.visible:
				_show_pause_main()
			elif pause_overlay.visible:
				_close_pause()
			else:
				_open_pause()
			get_viewport().set_input_as_handled()
		return
	if slot < 0 or menu_layer.visible or not Net.is_online():
		return
	if pause_overlay.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		var mp := world.get_local_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Clicking one of your soldiers selects it.
			for o in own:
				if o["alive"] and o["disp"].distance_to(mp) <= Cfg.SOLDIER_RADIUS + 5.0:
					_select(o["idx"])
					return
			Net.c_move.rpc_id(1, mp, event.shift_pressed)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_face_send_t = 0.05
			Net.c_face.rpc_id(1, mp)
	elif event is InputEventKey and event.pressed and not event.echo:
		var number_selection := _number_key_selection(event)
		if number_selection >= 0:
			_select(number_selection)
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_TAB: _cycle_select()
			KEY_W: _use_ability_slot(0, false)
			KEY_E: _use_ability_slot(1, false)
			KEY_R: _use_ability_slot(2, false)
			KEY_V: _toggle_voice()
			KEY_ENTER, KEY_KP_ENTER:
				if state == Cfg.State.ENDED:
					Net.c_rematch.rpc_id(1)
			_: return
		get_viewport().set_input_as_handled()


func _number_key_selection(event: InputEventKey) -> int:
	for code in [event.keycode, event.physical_keycode]:
		match code:
			KEY_1, KEY_KP_1: return 0
			KEY_2, KEY_KP_2: return 1
			KEY_3, KEY_KP_3: return 2
			KEY_4, KEY_KP_4: return 3
	return -1


func _select(idx: int) -> void:
	if idx < 0 or idx >= own.size() or not own[idx]["alive"]:
		return
	selected = idx
	_sel_lock_until = time + 0.4
	Net.c_select.rpc_id(1, idx)


func _cycle_select() -> void:
	for i in range(1, Cfg.SQUAD_SIZE + 1):
		var j := (selected + i) % Cfg.SQUAD_SIZE
		if own[j]["alive"]:
			_select(j)
			return


func _use_ability_slot(slot_idx: int, via_voice: bool) -> bool:
	var equipped := equipped_abilities(selected)
	if slot_idx < 0 or slot_idx >= equipped.size():
		return false
	return _use_ability(equipped[slot_idx], via_voice)


func _use_ability(ability: int, via_voice: bool) -> bool:
	return _use_ability_at(ability, world.get_local_mouse_position(), via_voice)


func _use_ability_at(ability: int, target: Vector2, via_voice: bool) -> bool:
	if not _ability_ready(ability):
		return false
	Net.c_ability.rpc_id(1, ability, target, via_voice)
	ability_flash[ability] = maxf(float(ability_flash[ability]), 0.8)
	return true


func _ability_ready(ability: int) -> bool:
	if ability < cooldowns.size() and cooldowns[ability] > 0.0:
		_msg("%s is cooling down (%.1fs)" % [Cfg.ABILITIES[ability]["name"], cooldowns[ability]], Color(0.72, 0.72, 0.76))
		sfx.play("deny", -8.0)
		return false
	if ready_ability_casters(ability) == 0:
		_msg("No ready squad member can cast %s" % Cfg.ABILITIES[ability]["name"], Color(0.35, 0.72, 1.0))
		sfx.play("deny", -8.0)
		return false
	return true


## A spoken spell is cast by every living squad member that has it equipped and
## enough MP, whoever was named. Fireballs fly from each caster along the spoken
## direction, or straight ahead of that caster.
func _voice_cast(cmd: Dictionary) -> void:
	var ab: int = cmd["ability"]
	if not _ability_ready(ab):
		return
	var dir: Vector2 = cmd.get("dir", Vector2.ZERO)
	var world_dir := _world_dir(dir) if dir != Vector2.ZERO else Vector2.ZERO
	Net.c_ability_dir.rpc_id(1, ab, world_dir)
	if ab != Cfg.Ability.FIREBALL:
		return
	var mp_cost: float = Cfg.ABILITIES[ab]["mp_cost"]
	for i in own.size():
		var o: Dictionary = own[i]
		if o["alive"] and has_equipped_ability(i, ab) and float(o["mp"]) >= mp_cost:
			var d := world_dir if world_dir != Vector2.ZERO else Vector2.from_angle(o["facing"])
			_ping(o["pos"] + d * Cfg.VOICE_CAST_DISTANCE, "FIREBALL")


## Ability in the W / E / R slot of the named soldier (or the selected one).
func _voice_spell(subj: int, slot_idx: int) -> int:
	var equipped := equipped_abilities(subj if subj >= 0 else selected)
	return equipped[slot_idx] if slot_idx >= 0 and slot_idx < equipped.size() else -1


func _soldier_name(idx: int) -> String:
	return Voice.SUBJECT_NAMES.get(idx, "SOLDIER")


func _on_voice_command(cmd: Dictionary) -> void:
	var ctype: int = cmd.get("type", Voice.CmdType.NONE)
	if ctype == Voice.CmdType.NONE:
		return

	if ctype == Voice.CmdType.DEPLOY:
		if menu_layer.visible and not connect_btn.disabled:
			_on_connect_pressed()
		return
	elif ctype == Voice.CmdType.REMATCH:
		if state == Cfg.State.ENDED and Net.is_online():
			Net.c_rematch.rpc_id(1)
		return

	if slot < 0 or not Net.is_online():
		return

	if state != Cfg.State.PLAYING and state != Cfg.State.COUNTDOWN:
		return
	sfx.play("voice", -8.0)
	var subj: int = cmd.get("subject", -2)
	var units := _voice_units(subj)
	if units.is_empty():
		_msg("%s is down" % _soldier_name(subj if subj >= 0 else selected), Color(1.0, 0.5, 0.4))
		return
	if subj >= 0:
		_select(subj)

	if ctype == Voice.CmdType.ABILITY:
		_voice_cast(cmd)
		return

	match ctype:
		Voice.CmdType.SELECT_NEXT:
			_cycle_select()

		Voice.CmdType.HALT:
			for i in units:
				Net.c_unit_stop.rpc_id(1, i)
				_steer.erase(i)
				_ping(own[i]["pos"], "")

		Voice.CmdType.STEER:
			for i in units:
				_voice_steer(i, cmd)

		Voice.CmdType.MOVE_DIR:
			var dir := _world_dir(cmd["dir"])
			var max_d: float = {"short": Cfg.VOICE_STEP_SHORT, "far": Cfg.VOICE_STEP_FAR}.get(cmd.get("dist", ""), Cfg.VOICE_STEP)
			var queue: bool = cmd.get("queue", false)
			for i in units:
				var from: Vector2 = _voice_dest.get(i, own[i]["pos"]) if queue else own[i]["pos"]
				var dest := _dir_destination(from, dir, max_d)
				_voice_move(i, dest, queue)
				_ping(dest, "")

		Voice.CmdType.WATCH_DIR:
			var dir := _world_dir(cmd["dir"])
			for i in units:
				Net.c_unit_face.rpc_id(1, i, own[i]["pos"] + dir * 100.0)
				_ping(own[i]["pos"] + dir * 48.0, "")


func _voice_move(idx: int, dest: Vector2, queue: bool) -> void:
	Net.c_unit_move.rpc_id(1, idx, dest, queue)
	_voice_dest[idx] = dest
	_steer.erase(idx)


## Drives a soldier relative to where it faces. Forward / back walk along the
## heading (backing up keeps facing forward); a turn bends a walk in progress or
## turns a standing soldier on the spot.
func _voice_steer(i: int, cmd: Dictionary) -> void:
	var o: Dictionary = own[i]
	var moving: bool = o["target"].distance_to(o["pos"]) > 4.0
	var st: Dictionary = _steer.get(i, {})
	# The last steering order is still in charge if it was just given (the
	# snapshot may lag) or the soldier is still walking toward its destination.
	var live: bool = not st.is_empty() and (time - st["t"] < 1.0 or (moving and o["target"].distance_to(st["dest"]) < Cfg.TILE))
	var heading: Vector2 = st["heading"] if live else Vector2.from_angle(o["facing"])
	heading = heading.rotated(deg_to_rad(cmd["turn"]))
	var move: int = cmd["move"]
	var max_d: float = Cfg.VOICE_STEP_FAR
	if cmd["tiles"] > 0:
		max_d = cmd["tiles"] * Cfg.TILE
	elif cmd["dist"] == "short":
		max_d = Cfg.VOICE_STEP_SHORT
	elif move == 0 and live and st["move"] != 0:
		max_d = st["dist"]
	if move == 0 and moving:
		move = st["move"] if live and st["move"] != 0 else 1
	if move == 0:
		Net.c_unit_face.rpc_id(1, i, o["pos"] + heading * 100.0)
		_steer[i] = {"heading": heading, "move": 0, "dist": 0.0, "dest": o["pos"], "t": time}
		_ping(o["pos"] + heading * 48.0, "")
		return
	var dest := _dir_destination(o["pos"], heading * move, max_d)
	_voice_move(i, dest, false)
	if move < 0:
		Net.c_unit_face.rpc_id(1, i, o["pos"] + heading * 100.0)
	_steer[i] = {"heading": heading, "move": move, "dist": max_d, "dest": dest, "t": time}
	_ping(dest, "")


## Soldiers a voice order applies to: the named one, the whole squad, or the
## selected soldier when nobody was named. Dead soldiers are skipped.
func _voice_units(subj: int) -> Array:
	var out := []
	for i in Cfg.SQUAD_SIZE:
		if own[i]["alive"] and (subj == -1 or i == (subj if subj >= 0 else selected)):
			out.append(i)
	return out


## Screen-relative direction (x right, y down) -> world direction. Red's world
## is rotated 180 degrees on screen.
func _world_dir(screen_dir: Vector2) -> Vector2:
	return screen_dir.rotated(-world_rotation)


## Walk straight until a wall; if something blocks the way right in front of the
## soldier, aim further out and let the server's A* path around it.
func _dir_destination(from: Vector2, dir: Vector2, max_d: float) -> Vector2:
	var d := map.walk_distance(from, dir, max_d, Cfg.SOLDIER_RADIUS)
	if d >= Cfg.TILE * 1.5:
		return from + dir * d
	var far := from + dir * minf(max_d, Cfg.VOICE_STEP)
	return Vector2(clampf(far.x, Cfg.TILE, Cfg.WORLD_SIZE.x - Cfg.TILE), clampf(far.y, Cfg.TILE, Cfg.WORLD_SIZE.y - Cfg.TILE))


## Spread squad members around a destination: one on the spot, two slightly
## behind on either side and one further back (from this player's point of view).
func _formation(target: Vector2, count: int) -> Array:
	var fwd := _world_dir(Vector2.RIGHT)
	var side := fwd.orthogonal()
	var offsets := [Vector2.ZERO, side * 28.0 - fwd * 16.0, -side * 28.0 - fwd * 16.0, -fwd * 36.0]
	var out := []
	for k in count:
		var p: Vector2 = target + offsets[k % offsets.size()]
		out.append(target if map.is_wall_at(p) else p)
	return out


func _ping(pos: Vector2, label: String) -> void:
	voice_pings.append({"pos": pos, "label": label, "t": 1.6, "max": 1.6})
