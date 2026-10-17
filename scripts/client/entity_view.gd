extends Node2D
## Draws all dynamic world entities: soldiers, firing cones, tracers, fog,
## scan pings, damage indicators. Lives inside the (possibly rotated) World node.

const Cfg = preload("res://scripts/config.gd")
var game  # ClientGame
var font: Font
var soldier_texture: Texture2D
var soldier_textures: Array[Texture2D] = []
var _cone_cache := {}


func _ready() -> void:
	font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists("res://assets/magic_student_sprites.png"):
		soldier_texture = load("res://assets/magic_student_sprites.png")
		for idx in Cfg.SQUAD_SIZE:
			var region := AtlasTexture.new()
			region.atlas = soldier_texture
			region.region = Rect2(Vector2(idx % 3, idx / 3) * 512.0, Vector2(512, 512))
			soldier_textures.append(region)


func _process(_dt: float) -> void:
	# Units and transient effects must follow display frames or movement and
	# lighting interactions visibly stutter on high-refresh screens.
	queue_redraw()


func _team_color(team: int) -> Color:
	return Cfg.TEAM_COLORS[team]


func clear_performance_caches() -> void:
	_cone_cache.clear()


func _draw() -> void:
	if game == null or game.slot < 0:
		return
	var my_team: int = game.slot
	var enemy_team: int = 1 - my_team
	var now: float = game.time
	var fogs: Array = game.fog_list()

	# Corpses
	for c in game.corpses:
		var col: Color = _team_color(c["team"]).darkened(0.5)
		var p: Vector2 = c["pos"]
		if not soldier_textures.is_empty():
			var corpse_texture := soldier_textures[int(c.get("idx", 0)) % soldier_textures.size()]
			draw_set_transform(p, c.get("facing", 0.0), Vector2.ONE)
			draw_texture_rect(corpse_texture, Rect2(-24, -18, 48, 36), false, Color(0.3, 0.25, 0.25, 0.55))
			draw_set_transform_matrix(Transform2D.IDENTITY)
		draw_circle(p, 9.0, Color(0.25, 0.05, 0.05, 0.6))
		draw_line(p + Vector2(-6, -6), p + Vector2(6, 6), col, 2.5)
		draw_line(p + Vector2(-6, 6), p + Vector2(6, -6), col, 2.5)

	# Vision/fire cones stay hidden throughout deployment and countdown.
	if game.state == Cfg.State.PLAYING:
		for o in game.own:
			if not o["alive"]:
				continue
			var is_sel: bool = o["idx"] == game.selected
			var weapon: int = Cfg.SQUAD_WEAPONS[o["idx"]]
			var a := 0.20 if is_sel else 0.09
			var enraged: bool = o["flags"] & 2 != 0
			var col: Color = Color(1.0, 0.48, 0.12) if enraged else _team_color(my_team)
			_draw_cone("own_%d" % o["idx"], o["disp"], o["disp_facing"], Cfg.weapon_cone(weapon), _display_range(weapon, o["flags"]), Color(col, a), Color(col, a + 0.25), fogs)

		# Visible enemy cones
		for idx in game.enemies:
			var e: Dictionary = game.enemies[idx]
			var weapon: int = Cfg.SQUAD_WEAPONS[idx]
			_draw_cone("enemy_%d" % idx, e["disp"], e["disp_facing"], Cfg.weapon_cone(weapon), _display_range(weapon, e["flags"]), Color(_team_color(enemy_team), 0.08), Color(_team_color(enemy_team), 0.3), fogs)

	# Selected soldier path / watch direction
	if game.state == Cfg.State.PLAYING and game.selected >= 0 and game.selected < game.own.size():
		var o: Dictionary = game.own[game.selected]
		if o["alive"]:
			var tgt: Vector2 = o["target"]
			if tgt.distance_to(o["disp"]) > 4.0:
				_draw_dashed(o["disp"], tgt, Color(1, 1, 1, 0.45))
				draw_arc(tgt, 6.0, 0.0, TAU, 16, Color(1, 1, 1, 0.7), 2.0)
			if o["watch"] != INF:
				var wp: Vector2 = o["disp"] + Vector2.from_angle(o["watch"]) * 46.0
				draw_line(o["disp"] + Vector2.from_angle(o["watch"]) * 30.0, wp, Color(1, 1, 0.6, 0.8), 2.0)
				draw_circle(wp, 3.0, Color(1, 1, 0.6, 0.8))

	# Path targets of the other (unselected) soldiers, so squad orders are visible
	for o in game.own:
		if o["alive"] and o["idx"] != game.selected and o["target"].distance_to(o["disp"]) > 4.0:
			_draw_dashed(o["disp"], o["target"], Color(1, 1, 1, 0.18))
			draw_arc(o["target"], 4.0, 0.0, TAU, 12, Color(1, 1, 1, 0.35), 1.5)

	_draw_voice_pings()

	# Last-known enemy positions (ghosts)
	for g in game.ghosts:
		var k: float = clampf(g["t"] / 2.0, 0.0, 1.0)
		draw_arc(g["pos"], Cfg.SOLDIER_RADIUS, 0.0, TAU, 20, Color(_team_color(enemy_team), 0.5 * k), 2.0)
		_draw_label(g["pos"] + Vector2(0, -1), "?", Color(1, 1, 1, 0.6 * k), 12)

	# Scan pings (enemies revealed by Scan)
	for s in game.scanned:
		var p: Vector2 = s[1]
		var pulse := 0.5 + 0.5 * sin(now * 10.0)
		draw_arc(p, 14.0 + pulse * 6.0, 0.0, TAU, 24, Color(1.0, 0.3, 0.3, 0.9), 2.0)
		draw_circle(p, 4.0, Color(1.0, 0.3, 0.3, 0.9))
	for fx in game.scan_fx:
		var k: float = 1.0 - fx["t"] / fx["max"]
		draw_arc(fx["origin"], fx["radius"] * k, 0.0, TAU, 96, Color(0.4, 1.0, 0.7, 0.6 * (1.0 - k)), 3.0)
	for fx in game.blast_fx:
		var k: float = 1.0 - fx["t"] / fx["max"]
		var radius: float = fx["radius"] * (0.25 + 0.75 * k)
		draw_circle(fx["origin"], radius, Color(1.0, 0.22, 0.03, 0.12 * (1.0 - k)))
		draw_arc(fx["origin"], radius, 0.0, TAU, 64, Color(1.0, 0.65, 0.12, 0.9 * (1.0 - k)), 5.0)
		draw_arc(fx["origin"], radius * 0.72, 0.0, TAU, 48, Color(1.0, 0.95, 0.55, 0.7 * (1.0 - k)), 2.0)

	# Enemies
	for idx in game.enemies:
		var e: Dictionary = game.enemies[idx]
		_draw_soldier(e["disp"], e["disp_facing"], enemy_team, idx, e["hp"], e["flags"], false, game.state != Cfg.State.DEPLOYMENT)

	# Own soldiers
	for o in game.own:
		if o["alive"]:
			_draw_soldier(o["disp"], o["disp_facing"], my_team, o["idx"], o["hp"], o["flags"], o["idx"] == game.selected and game.state == Cfg.State.PLAYING, game.state != Cfg.State.DEPLOYMENT)

	# Animated magical bolts with layered additive-looking neon glow.
	for tr in game.tracers:
		var tracer_scale: float = float(tr.get("scale", 1.0))
		var progress := clampf(1.0 - tr["t"] / tr["max"], 0.0, 1.0)
		var head_progress := minf(1.0, progress * 1.35)
		var tail_progress := maxf(0.0, head_progress - 0.20)
		var direction: Vector2 = (tr["b"] - tr["a"]).normalized()
		var side := direction.orthogonal() * sin(game.time * 58.0 + tr["seed"]) * 1.8
		var head: Vector2 = tr["a"].lerp(tr["b"], head_progress) + side
		var tail: Vector2 = tr["a"].lerp(tr["b"], tail_progress) - side * 0.35
		var fade := clampf(tr["t"] / 0.10, 0.0, 1.0)
		var col: Color = tr["color"]
		draw_line(tail, head, Color(col.r, col.g, col.b, 0.16 * fade), 11.0 * tracer_scale)
		draw_line(tail, head, Color(col.r, col.g, col.b, 0.42 * fade), 6.0 * tracer_scale)
		draw_line(tail, head, Color(0.92, 1.0, 1.0, 0.95 * fade), 2.2 * tracer_scale)
		draw_circle(head, 9.0 * tracer_scale, Color(col.r, col.g, col.b, 0.16 * fade))
		draw_circle(head, 4.0 * tracer_scale, Color(col.r, col.g, col.b, 0.88 * fade))
		draw_circle(head, 1.8 * tracer_scale, Color(1.0, 1.0, 1.0, fade))

	# Neon casting and impact sparks.
	for particle in game.magic_particles:
		var k: float = clampf(particle["t"] / particle["max"], 0.0, 1.0)
		var p: Vector2 = particle["pos"]
		var col: Color = particle["color"]
		var radius: float = particle["size"] * (0.5 + k * 0.5)
		draw_circle(p, radius * 3.2, Color(col.r, col.g, col.b, 0.10 * k))
		draw_circle(p, radius * 1.7, Color(col.r, col.g, col.b, 0.32 * k))
		draw_circle(p, radius, Color(0.9, 1.0, 1.0, 0.95 * k))

	# Fog clouds
	for fog in game.fogs:
		var p: Vector2 = fog[0]
		var r: float = fog[1]
		var t_left: float = fog[2]
		var fade := clampf(t_left / 1.0, 0.0, 1.0)
		for i in 5:
			var rr := r * (1.0 - i * 0.15)
			var wob := Vector2(sin(now * 0.7 + i * 1.7), cos(now * 0.6 + i * 2.3)) * 4.0
			draw_circle(p + wob, rr, Color(0.72, 0.74, 0.76, 0.22 * fade))
		draw_circle(p, r * 0.45, Color(0.8, 0.82, 0.84, 0.35 * fade))

	# Incoming-fire indicators from hidden shooters
	for h in game.hurts:
		if h["idx"] >= game.own.size():
			continue
		var o: Dictionary = game.own[h["idx"]]
		if not o["alive"]:
			continue
		var k: float = h["t"] / 1.2
		var col := Color(1.0, 0.15, 0.1, k) if h["dmg"] > 0 else Color(1.0, 0.7, 0.2, k * 0.8)
		var ang: float = h["angle"]
		draw_arc(o["disp"], 24.0, ang - 0.45, ang + 0.45, 12, col, 4.0)
		var tip: Vector2 = o["disp"] + Vector2.from_angle(ang) * 34.0
		draw_primitive(PackedVector2Array([tip, o["disp"] + Vector2.from_angle(ang - 0.18) * 27.0, o["disp"] + Vector2.from_angle(ang + 0.18) * 27.0]), PackedColorArray([col, col, col]), PackedVector2Array())


func _draw_soldier(p: Vector2, facing: float, team: int, idx: int, hp: int, flags: int, is_sel: bool, show_ui := true) -> void:
	var col := _team_color(team)
	var weapon: int = Cfg.SQUAD_WEAPONS[idx]
	var r := Cfg.SOLDIER_RADIUS

	# Selection highlight ring (pulsing)
	if show_ui and is_sel:
		var pulse := 0.5 + 0.5 * sin(game.time * 6.0)
		draw_arc(p, r + 7.0 + pulse * 2.5, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 2.5)

	# Rush speed lines behind unit
	if show_ui and flags & 4 != 0:  # rush
		var back := Vector2.from_angle(facing + PI)
		for i in 3:
			draw_line(p + back * (r + 3 + i * 4) + back.orthogonal() * (i - 1) * 5.0, p + back * (r + 10 + i * 4) + back.orthogonal() * (i - 1) * 5.0, Color(0.6, 1.0, 0.9, 0.7), 2.0)
	if show_ui and flags & 64 != 0:  # flash / evasive dash
		var back := Vector2.from_angle(facing + PI)
		draw_line(p + back * 5.0, p + back * 34.0, Color(0.35, 0.92, 1.0, 0.75), 5.0)

	# Shadow
	draw_circle(p + Vector2(2, 3), r + 2.0, Color(0, 0, 0, 0.35))

	# Team identification is hidden during the clean entrance cinematic.
	if show_ui:
		draw_circle(p, r + 2.0, Color(col.r, col.g, col.b, 0.35))
		draw_arc(p, r + 2.5, 0.0, TAU, 32, col, 2.0)

	if not soldier_textures.is_empty():
		# Each squad slot has a matching modern-student portrait and overhead sprite.
		var sprite_mod := Color(0.92, 0.96, 1.0) if team == 0 else Color(1.0, 0.88, 0.88)
		if flags & 16 != 0:
			sprite_mod.a = 0.34
		elif flags & 32 != 0:
			sprite_mod = sprite_mod.lerp(Color(1.0, 0.62, 0.18), 0.34)
		draw_set_transform(p, facing, Vector2.ONE)
		draw_texture_rect(soldier_textures[idx % soldier_textures.size()], Rect2(-24, -18, 48, 36), false, sprite_mod)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	else:
		# Fallback geometric soldier
		var dir := Vector2.from_angle(facing)
		var gun_len := 20.0
		var gun_w := 4.0
		match weapon:
			Cfg.Weapon.RIFLE:
				gun_len = 24.0
				gun_w = 3.0
			Cfg.Weapon.SHOTGUN:
				gun_len = 17.0
				gun_w = 6.0
		draw_line(p + dir * 4.0, p + dir * gun_len, Color(0.12, 0.12, 0.14), gun_w + 2.0)
		draw_line(p + dir * 4.0, p + dir * gun_len, Color(0.35, 0.35, 0.38), gun_w)
		draw_circle(p, r, col.darkened(0.25))
		draw_circle(p, r - 3.0, col)
		draw_circle(p + dir * 2.0, 4.5, col.lightened(0.35))

	if show_ui:
		# Health ring
		var frac := clampf(hp / float(Cfg.SOLDIER_HP), 0.0, 1.0)
		draw_arc(p, r + 3.0, 0.0, TAU, 32, Color(0, 0, 0, 0.55), 3.0)
		var hp_col := Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.25, 0.2), 1.0 - frac)
		if frac > 0.0:
			draw_arc(p, r + 3.0, -PI * 0.5 - game.world_rotation, -PI * 0.5 - game.world_rotation + TAU * frac, 32, hp_col, 3.0)

		if flags & 2 != 0:  # outrage
			var rage_pulse := 0.55 + 0.35 * sin(game.time * 20.0)
			draw_arc(p, r + 7.0, 0.0, TAU, 24, Color(1.0, 0.28, 0.04, rage_pulse), 3.0)
		if flags & 32 != 0:  # stick stance
			draw_arc(p, r + 6.0, -1.2, 1.2, 18, Color(1.0, 0.68, 0.18, 0.8), 2.0)
		if flags & 128 != 0:  # empowered wand
			draw_arc(p, r + 7.0, 0.0, TAU, 24, Color(0.45, 0.8, 1.0, 0.8), 2.0)

		# Label (counter-rotated so text is always upright)
		var label: String = str(idx + 1) if team == game.slot else ["A", "B", "C", "D"][idx]
		draw_circle(p + Vector2(0, 1), 6.5, Color(0, 0, 0, 0.55))
		_draw_label(p + Vector2(0, 2), label, Color.WHITE, 11)


func _draw_label(p: Vector2, text: String, col: Color, size: int) -> void:
	draw_set_transform(p, -game.world_rotation)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(-w * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _display_range(weapon: int, flags: int) -> float:
	var result: float = Cfg.WEAPONS[weapon]["range"]
	if flags & 32 != 0:
		result *= float(Cfg.ABILITIES[Cfg.Ability.BREAK_MAGIC]["stick_range_mult"])
	elif flags & 128 != 0:
		result *= float(Cfg.ABILITIES[Cfg.Ability.BREAK_MAGIC]["wand_range_mult"])
	return result


func _draw_cone(cache_key: String, origin: Vector2, facing: float, cone: float, radius: float, fill: Color, line: Color, fogs: Array) -> void:
	var signature: int = int(game.map.breakable_revision)
	signature = signature * 31 + roundi(origin.x / game.vision_pos_step)
	signature = signature * 31 + roundi(origin.y / game.vision_pos_step)
	signature = signature * 31 + roundi(facing / game.vision_angle_step)
	signature = signature * 31 + roundi(radius)
	for fog in fogs:
		signature = signature * 31 + roundi(float(fog[0].x) / game.vision_pos_step)
		signature = signature * 31 + roundi(float(fog[0].y) / game.vision_pos_step)
		signature = signature * 31 + roundi(float(fog[1]))
	var cached: Dictionary = _cone_cache.get(cache_key, {})
	var pts: PackedVector2Array
	if int(cached.get("signature", -2147483648)) == signature:
		pts = cached["points"]
	else:
		var ray_steps := maxi(3, int(ceil(cone / deg_to_rad(game.cone_step_deg))))
		pts = PackedVector2Array([origin])
		for i in ray_steps + 1:
			var a := facing - cone * 0.5 + cone * float(i) / ray_steps
			var d := Vector2.from_angle(a)
			pts.append(origin + d * game.map.sight_distance(origin, d, radius, fogs))
		_cone_cache[cache_key] = {"signature": signature, "points": pts, "origin": origin}
	var cached_origin: Vector2 = _cone_cache[cache_key].get("origin", origin)
	draw_set_transform(origin - cached_origin)
	var triangle_steps := pts.size() - 2
	var cols := PackedColorArray([fill, fill, fill])
	for i in triangle_steps:
		draw_primitive(PackedVector2Array([pts[0], pts[i + 1], pts[i + 2]]), cols, PackedVector2Array())
	draw_line(cached_origin, pts[1], line, 1.0)
	draw_line(cached_origin, pts[pts.size() - 1], line, 1.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var length := a.distance_to(b)
	var d := (b - a) / length
	var t := 0.0
	while t < length:
		draw_line(a + d * t, a + d * minf(t + 8.0, length), col, 2.0)
		t += 14.0


func _draw_voice_pings() -> void:
	for ping in game.voice_pings:
		var k: float = 1.0 - ping["t"] / ping["max"]
		var a: float = 1.0 - k
		var p: Vector2 = ping["pos"]
		var col := Color(0.4, 1.0, 0.7)
		draw_arc(p, 6.0 + 22.0 * k, 0.0, TAU, 28, Color(col, 0.9 * a), 2.5)
		draw_arc(p, 4.0 + 10.0 * k, 0.0, TAU, 20, Color(col, 0.6 * a), 1.5)
		draw_circle(p, 3.0, Color(col, a))
		if ping["label"] != "":
			_draw_label(p + Vector2(0, 26.0).rotated(-game.world_rotation), ping["label"], Color(col, a), 12)
