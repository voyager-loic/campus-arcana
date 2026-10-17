extends Node2D
## Large vector-rendered dining/lecture hall. MapData is the single source of
## truth for both collision and decoration, so visuals never create phantom walls.

const Cfg = preload("res://scripts/config.gd")

enum DrawMode { STATIC_MAP, BREAKABLES }

var map
var game
var font: Font
var draw_mode := DrawMode.STATIC_MAP


func _ready() -> void:
	font = ThemeDB.fallback_font
	queue_redraw()


func _draw() -> void:
	if map == null:
		return
	if draw_mode == DrawMode.BREAKABLES:
		_draw_breakable_layer()
		return
	var t := float(Cfg.TILE)

	# Warm terrazzo with the restrained palette of the restored small map.
	for y in Cfg.MAP_H:
		for x in Cfg.MAP_W:
			var r := Rect2(x * t, y * t, t, t)
			if map.solid_kind(x, y) == map.SolidKind.VOID:
				draw_rect(r, Color("11161c"))
			else:
				draw_rect(r, Color("35312c"))
				draw_circle(r.position + Vector2(8 + (x * 7 + y * 3) % 18, 7 + (x * 5 + y * 11) % 18), 0.8, Color(0.72, 0.67, 0.58, 0.14))

	_draw_team_entry_glow()
	_draw_explosion_scorch()
	_draw_lower_room_breach()
	_draw_floor_markings()
	_draw_spilled_glass()

	# Chairs and tabletops are both derived from the same 4/8-seat table record.
	for table in map.tables:
		if bool(table.get("breakable", false)):
			continue
		var table_rect: Rect2 = map.table_visual_rect(table)
		var anchor: Vector2i = table["anchor"]
		draw_set_transform(table_rect.get_center(), float(table.get("angle", 0.0)), Vector2.ONE)
		if not bool(table.get("tipped", false)) and not bool(table.get("destroyed", false)):
			_draw_table_chairs(Rect2(-table_rect.size * 0.5, table_rect.size), table["seats"], anchor.x + anchor.y * 83)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for y in Cfg.MAP_H:
		for x in Cfg.MAP_W:
			if map.is_wall_tile(x, y) and not map.is_table_tile(x, y) and map.solid_kind(x, y) not in [map.SolidKind.VOID, map.SolidKind.GLASS]:
				draw_rect(Rect2(x * t + 4, y * t + 5, t, t), Color(0, 0, 0, 0.34))
	for y in Cfg.MAP_H:
		for x in Cfg.MAP_W:
			var kind: int = map.solid_kind(x, y)
			var r := Rect2(x * t, y * t, t, t)
			match kind:
				map.SolidKind.WALL:
					_draw_wall(r, x, y)
				map.SolidKind.TABLE:
					pass # joined and rendered once per plan rectangle below
				map.SolidKind.PLANT:
					_draw_plant(r, x + y * 17)
				map.SolidKind.COUNTER:
					pass # joined and rendered once per service object below
				map.SolidKind.VOID:
					pass
				map.SolidKind.RUBBLE:
					_draw_rubble(r, x, y)
				map.SolidKind.GLASS:
					pass # rendered as one continuous framed wall below
	for table in map.tables:
		if bool(table.get("breakable", false)):
			continue
		var anchor: Vector2i = table["anchor"]
		var table_rect: Rect2 = map.table_visual_rect(table)
		draw_set_transform(table_rect.get_center(), float(table.get("angle", 0.0)), Vector2.ONE)
		_draw_table(Rect2(-table_rect.size * 0.5, table_rect.size), anchor.x, anchor.y, bool(table.get("damaged", false)), bool(table.get("tipped", false)), bool(table.get("destroyed", false)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for idx in map.counter_rects.size():
		_draw_counter(map.counter_visual_rect(map.counter_rects[idx]), idx)
	for fixture in map.service_fixtures:
		_draw_service_fixture(fixture)
	_draw_main_room_clutter()
	_draw_lower_room_clutter()

	_draw_door_frames()


func _draw_breakable_layer() -> void:
	# This small retained drawing layer is refreshed only after destruction.
	# The full arena texture never needs to be regenerated for a broken prop.
	for table in map.tables:
		if not bool(table.get("breakable", false)):
			continue
		var anchor: Vector2i = table["anchor"]
		var table_rect: Rect2 = map.table_visual_rect(table)
		draw_set_transform(table_rect.get_center(), float(table.get("angle", 0.0)), Vector2.ONE)
		if not bool(table.get("tipped", false)) and not bool(table.get("destroyed", false)):
			_draw_table_chairs(Rect2(-table_rect.size * 0.5, table_rect.size), table["seats"], anchor.x + anchor.y * 83)
		_draw_table(Rect2(-table_rect.size * 0.5, table_rect.size), anchor.x, anchor.y,
			bool(table.get("damaged", false)), bool(table.get("tipped", false)), bool(table.get("destroyed", false)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for fixture in map.breakable_fixtures:
		_draw_breakable_fixture(fixture)


func _draw_team_entry_glow() -> void:
	var t := float(Cfg.TILE)
	draw_rect(Rect2(2 * t, 36 * t, 15 * t, 7 * t), Color(Cfg.TEAM_COLORS[0], 0.055))
	draw_rect(Rect2(68 * t, 2 * t, 11 * t, 13 * t), Color(Cfg.TEAM_COLORS[1], 0.055))


func _draw_floor_markings() -> void:
	var t := float(Cfg.TILE)
	if font:
		draw_string(font, Vector2(6 * t, 7.2 * t), "B", HORIZONTAL_ALIGNMENT_CENTER, 26 * t, 24, Color(0.84, 0.79, 0.68, 0.12))
		draw_string(font, Vector2(42 * t, 7.2 * t), "A", HORIZONTAL_ALIGNMENT_CENTER, 26 * t, 24, Color(0.84, 0.79, 0.68, 0.12))
		draw_string(font, Vector2(2 * t, 42.3 * t), "ENTRANCE 1", HORIZONTAL_ALIGNMENT_CENTER, 13 * t, 12, Color(Cfg.TEAM_COLORS[0], 0.32))
		draw_string(font, Vector2(68 * t, 3.2 * t), "ENTRANCE 2", HORIZONTAL_ALIGNMENT_CENTER, 10 * t, 12, Color(Cfg.TEAM_COLORS[1], 0.32))
	_draw_graffiti("A", Vector2(39.0, 10.5) * t, -0.13)
	_draw_graffiti("B", Vector2(71.0, 35.0) * t, 0.09)


func _draw_graffiti(letter: String, position: Vector2, angle: float) -> void:
	if font == null:
		return
	draw_set_transform(position, angle, Vector2.ONE)
	var paint := Color("b52727")
	draw_string(font, Vector2(-18, 16), letter, HORIZONTAL_ALIGNMENT_CENTER, 36, 38, Color(0.25, 0.02, 0.02, 0.55))
	draw_string(font, Vector2(-20, 14), letter, HORIZONTAL_ALIGNMENT_CENTER, 40, 38, paint)
	draw_line(Vector2(-17, 20), Vector2(18, 17), paint, 3.0)
	for p in [Vector2(-22, -8), Vector2(20, 4), Vector2(13, 25), Vector2(-12, 27)]:
		draw_circle(p, 2.2, Color(paint, 0.82))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_explosion_scorch() -> void:
	var c := Vector2(19.0, 4.5) * float(Cfg.TILE)
	draw_circle(c, 106.0, Color(0.05, 0.035, 0.025, 0.46))
	draw_circle(c, 78.0, Color(0.12, 0.065, 0.025, 0.34))
	draw_circle(c, 46.0, Color(0.04, 0.025, 0.018, 0.62))
	for i in 18:
		var a := i * TAU / 18.0 + 0.17
		var length := 70.0 + float((i * 29) % 55)
		draw_line(c + Vector2.from_angle(a) * 38.0, c + Vector2.from_angle(a) * length, Color(0.12, 0.07, 0.035, 0.28), 3.0)


func _draw_lower_room_breach() -> void:
	var t := float(Cfg.TILE)
	var c := Vector2((map.ROOM_BREACH_LEFT + map.ROOM_BREACH_RIGHT + 1) * 0.5, map.MAIN_BOTTOM + 0.5) * t
	draw_circle(c, 82.0, Color(0.055, 0.035, 0.025, 0.44))
	draw_circle(c, 48.0, Color(0.15, 0.075, 0.025, 0.30))
	for i in 14:
		var a := i * TAU / 14.0 + 0.11
		var distance := 34.0 + float((i * 17) % 43)
		var p := c + Vector2.from_angle(a) * distance
		var size := Vector2(7 + (i % 3) * 3, 5 + ((i + 1) % 3) * 2)
		draw_rect(Rect2(p - size * 0.5, size), Color("82705c") if i % 2 == 0 else Color("b09b7d"))
	# Jagged remnants identify the blast opening without restoring collision.
	draw_colored_polygon(PackedVector2Array([
		Vector2(map.ROOM_BREACH_LEFT, map.MAIN_BOTTOM) * t,
		Vector2(map.ROOM_BREACH_LEFT + 0.7, map.MAIN_BOTTOM + 0.65) * t,
		Vector2(map.ROOM_BREACH_LEFT + 1.25, map.MAIN_BOTTOM) * t
	]), Color("8b7c68"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(map.ROOM_BREACH_RIGHT + 1.0, map.MAIN_BOTTOM) * t,
		Vector2(map.ROOM_BREACH_RIGHT + 0.25, map.MAIN_BOTTOM + 0.72) * t,
		Vector2(map.ROOM_BREACH_RIGHT - 0.3, map.MAIN_BOTTOM) * t
	]), Color("8b7c68"))


func _draw_spilled_glass() -> void:
	var c := Vector2(39.0, 23.0) * float(Cfg.TILE)
	var spill := PackedVector2Array([
		c + Vector2(-31, -5), c + Vector2(-18, -18), c + Vector2(6, -14),
		c + Vector2(29, -4), c + Vector2(20, 14), c + Vector2(-4, 19), c + Vector2(-27, 10)
	])
	draw_colored_polygon(spill, Color(0.35, 0.70, 0.88, 0.24))
	draw_polyline(PackedVector2Array([c + Vector2(-13, -6), c + Vector2(3, 5), c + Vector2(13, -10)]), Color(0.72, 0.90, 0.98, 0.72), 2.0)
	draw_circle(c + Vector2(12, 4), 7.0, Color(0.70, 0.90, 1.0, 0.72), false, 2.0)
	draw_line(c + Vector2(7, 9), c + Vector2(20, 18), Color(0.70, 0.90, 1.0, 0.72), 2.0)


func _draw_rubble(r: Rect2, x: int, y: int) -> void:
	draw_rect(r, Color("2d2925"))
	var seed := x * 41 + y * 73
	for i in 4:
		var p := r.position + Vector2(5 + (seed + i * 11) % 23, 5 + (seed * 3 + i * 17) % 23)
		var size := Vector2(7 + (i % 3) * 3, 5 + ((i + 1) % 3) * 3)
		draw_rect(Rect2(p - size * 0.5, size), Color("615548") if i % 2 == 0 else Color("8a745c"))
		draw_line(p - size * 0.4, p + size * 0.35, Color("211d1a"), 1.2)


func _draw_main_room_clutter() -> void:
	var t := float(Cfg.TILE)
	# Faded impact marks and two secondary spills.
	for mark in [Vector2(7, 33), Vector2(35, 17), Vector2(72, 14)]:
		var c: Vector2 = mark * t
		draw_circle(c, 25.0, Color(0.07, 0.045, 0.03, 0.24))
		draw_circle(c + Vector2(5, -3), 11.0, Color(0.16, 0.08, 0.035, 0.20))
	var coffee := Vector2(24, 18) * t
	draw_colored_polygon(PackedVector2Array([coffee + Vector2(-18, -4), coffee + Vector2(-8, -14), coffee + Vector2(12, -9), coffee + Vector2(20, 5), coffee + Vector2(4, 13), coffee + Vector2(-15, 9)]), Color(0.24, 0.12, 0.055, 0.42))
	var water := Vector2(60, 28) * t
	draw_colored_polygon(PackedVector2Array([water + Vector2(-21, 1), water + Vector2(-9, -12), water + Vector2(16, -9), water + Vector2(24, 7), water + Vector2(3, 15)]), Color(0.35, 0.70, 0.88, 0.20))

	# Loose notes and torn pages in asymmetric clusters.
	var papers := [
		[Vector2(6, 12), -0.25], [Vector2(20, 24), 0.18], [Vector2(31, 35), -0.10],
		[Vector2(47, 16), 0.31], [Vector2(55, 37), -0.28], [Vector2(74, 27), 0.12]
	]
	for entry in papers:
		_draw_paper(entry[0] * t, entry[1])

	# Broken chair legs and backs; purely visual, so they never become phantom
	# obstacles in the pathfinder.
	for chair in [Vector2(31, 15), Vector2(17, 29), Vector2(47, 36), Vector2(68, 22)]:
		_draw_broken_chair(chair * t, chair.x * 0.11)


func _draw_lower_room_clutter() -> void:
	var t := float(Cfg.TILE)
	# Scattered trays, papers and spills echo the damaged main hall without
	# affecting navigation.
	for entry in [
		[Vector2(31.5, 58.0), -0.32], [Vector2(41.0, 52.0), 0.18],
		[Vector2(60.0, 66.5), -0.13], [Vector2(34.0, 65.0), 0.41]
	]:
		_draw_paper(entry[0] * t, entry[1])
	var spill := Vector2(59.5, 53.5) * t
	draw_colored_polygon(PackedVector2Array([
		spill + Vector2(-24, -6), spill + Vector2(-10, -17), spill + Vector2(18, -12),
		spill + Vector2(27, 5), spill + Vector2(9, 16), spill + Vector2(-17, 12)
	]), Color(0.30, 0.55, 0.43, 0.25))
	for tray in [Vector2(32.0, 52.0), Vector2(61.0, 48.0), Vector2(34.0, 61.0)]:
		var c: Vector2 = tray * t
		draw_set_transform(c, (tray.x + tray.y) * 0.07, Vector2.ONE)
		draw_rect(Rect2(-14, -9, 28, 18), Color("58616a"))
		draw_rect(Rect2(-11, -6, 22, 12), Color("8d969d"), false, 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_paper(position: Vector2, angle: float) -> void:
	draw_set_transform(position, angle, Vector2.ONE)
	draw_rect(Rect2(-8, -6, 16, 12), Color(0.82, 0.79, 0.69, 0.82))
	draw_line(Vector2(-5, -2), Vector2(5, -2), Color(0.28, 0.27, 0.25, 0.48), 1.0)
	draw_line(Vector2(-5, 2), Vector2(2, 2), Color(0.28, 0.27, 0.25, 0.40), 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_broken_chair(position: Vector2, angle: float) -> void:
	draw_set_transform(position, angle, Vector2.ONE)
	draw_rect(Rect2(-7, -6, 14, 11), Color("795235"))
	draw_rect(Rect2(-7, -6, 14, 11), Color("c18d55"), false, 1.3)
	draw_line(Vector2(-9, 6), Vector2(-16, 14), Color("6b482f"), 3.0)
	draw_line(Vector2(8, 5), Vector2(15, 11), Color("6b482f"), 3.0)
	draw_line(Vector2(-5, -8), Vector2(10, -15), Color("6b482f"), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_wall(r: Rect2, x: int, y: int) -> void:
	var blast_damaged: bool = (y == 0 and x >= 14 and x <= 23) or (y == map.MAIN_BOTTOM and x in [70, 71, 77, 78])
	draw_rect(r, Color("665e54") if blast_damaged else Color("cbc2ae"))
	draw_rect(Rect2(r.position + Vector2(3, 3), r.size - Vector2(6, 6)), Color("8b7c68") if blast_damaged else Color("e1d8c2"))
	if not map.is_wall_tile(x, y - 1):
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color("fff2d5"))
	if not map.is_wall_tile(x, y + 1):
		draw_rect(Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x, 4)), Color("756f66"))
	if not map.is_wall_tile(x - 1, y):
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), Color("f3e8ce"))
	if not map.is_wall_tile(x + 1, y):
		draw_rect(Rect2(r.position + Vector2(r.size.x - 4, 0), Vector2(4, r.size.y)), Color("777066"))
	if blast_damaged:
		draw_line(r.position + Vector2(5, 3), r.position + Vector2(13, 15), Color("2b2722"), 2.0)
		draw_line(r.position + Vector2(13, 15), r.position + Vector2(8, 28), Color("2b2722"), 1.5)


func _draw_table(r: Rect2, x: int, y: int, damaged := false, tipped := false, destroyed := false) -> void:
	if destroyed:
		# A collapsed tabletop is debris only; its collision was removed in MapData.
		for i in 8:
			var p := Vector2(-21 + (i * 17) % 43, -35 + (i * 29) % 71)
			var size := Vector2(12 + (i % 3) * 5, 5 + ((i + 1) % 3) * 3)
			draw_rect(Rect2(p - size * 0.5, size), Color("754523") if i % 2 == 0 else Color("a96a31"))
			draw_line(p - size * 0.35, p + size * 0.35, Color("382217"), 1.3)
		return
	if tipped:
		var slab := Rect2(Vector2(-7, r.position.y), Vector2(14, r.size.y))
		draw_rect(Rect2(slab.position + Vector2(3, 4), slab.size), Color(0, 0, 0, 0.34))
		draw_rect(slab, Color("493321"))
		draw_rect(slab.grow(-2), Color("75502d"))
		draw_line(Vector2(-10, slab.position.y + 8), Vector2(-18, slab.position.y + 23), Color("38271d"), 3.0)
		draw_line(Vector2(10, slab.end.y - 8), Vector2(19, slab.end.y - 22), Color("38271d"), 3.0)
		return
	draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.34))
	draw_rect(r, Color("493321") if tipped else Color("815029"))
	draw_rect(r.grow(-2), Color("75502d") if damaged or tipped else Color("a96a31"))
	for grain_y in range(12, floori(r.size.y), 18):
		draw_line(r.position + Vector2(3, grain_y), r.position + Vector2(r.size.x - 3, grain_y), Color(0.28, 0.13, 0.06, 0.42), 1.0)
	draw_rect(r, Color("e8a95c"), false, 1.5)
	# A small water glass near one end, matching the objects marked on the plan.
	var glass_y := 12.0 if (x + y) % 2 == 0 else r.size.y - 12.0
	draw_circle(r.position + Vector2(r.size.x * 0.5, glass_y), 2.2, Color(0.42, 0.80, 0.95, 0.82))
	draw_circle(r.position + Vector2(r.size.x * 0.5, glass_y), 1.0, Color(0.75, 0.92, 1.0, 0.55), false, 1.0)
	if damaged:
		draw_line(r.position + Vector2(4, 18), r.position + Vector2(r.size.x - 5, 31), Color("332116"), 2.0)
		draw_line(r.position + Vector2(r.size.x - 5, 31), r.position + Vector2(8, 48), Color("332116"), 1.5)
	if tipped:
		draw_rect(Rect2(r.position + Vector2(4, r.size.y * 0.46), Vector2(r.size.x - 8, 7)), Color("35271e"))


func _draw_table_chairs(table_rect: Rect2, seats: int, seed: int) -> void:
	var chairs_per_side := seats / 2
	for row in chairs_per_side:
		var chair_y := table_rect.position.y + (row + 0.5) * table_rect.size.y / chairs_per_side
		for side in [-1.0, 1.0]:
			var chair_x := table_rect.position.x + (0.0 if side < 0.0 else table_rect.size.x)
			var p := Vector2(chair_x + side * 9.0, chair_y + float((seed + row) % 3) - 1.0)
			draw_circle(p + Vector2(1.5, 2), 5.0, Color(0, 0, 0, 0.3))
			draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Color("6c4930"))
			draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Color("c79a62"), false, 1.3)
			var back_x := -5.0 if side < 0.0 else 5.0
			draw_line(p + Vector2(back_x, -5), p + Vector2(back_x, 5), Color("e0bd86"), 2.0)


func _draw_breakable_fixture(fixture: Dictionary) -> void:
	if fixture["kind"] != "glass_wall":
		return
	var cells: Rect2i = fixture["rect"]
	var cell_r := Rect2(Vector2(cells.position) * float(Cfg.TILE), Vector2(cells.size) * float(Cfg.TILE))
	# The collision occupies one grid row, but the physical partition itself is
	# a slim glass sheet centred in that row.
	var r := Rect2(Vector2(cell_r.position.x, cell_r.get_center().y - 7.0), Vector2(cell_r.size.x, 14.0))
	var destroyed := bool(fixture.get("destroyed", false))
	if destroyed:
		# The recessed floor track remains, while translucent shards communicate
		# that the opening used to be sealed without retaining phantom collision.
		draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(r.size.x, 3)), Color("59656a"))
		for i in 34:
			var px := r.position.x + 7.0 + fmod(float(i * 47), r.size.x - 14.0)
			var py := cell_r.position.y + 6.0 + float((i * 19) % 21)
			var s := 3.0 + float(i % 4)
			var shard := PackedVector2Array([Vector2(px, py - s), Vector2(px + s * 0.7, py + s), Vector2(px - s * 0.55, py + s * 0.45)])
			draw_colored_polygon(shard, Color(0.48, 0.86, 0.94, 0.42 if i % 3 else 0.68))
		return

	# Thick steel frame with a continuous translucent glass surface. Mullions
	# divide it into large panes so its scale reads clearly from the game camera.
	draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color(0, 0, 0, 0.38))
	draw_rect(r.grow(-3), Color(0.25, 0.72, 0.82, 0.28))
	draw_rect(r.grow(-2), Color(0.67, 0.93, 0.98, 0.46), false, 1.5)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color("6f7d82"))
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(r.size.x, 3)), Color("465257"))
	draw_rect(Rect2(r.position, Vector2(5, r.size.y)), Color("849196"))
	draw_rect(Rect2(r.position + Vector2(r.size.x - 5, 0), Vector2(5, r.size.y)), Color("465257"))
	for x in range(int(r.position.x + 64), int(r.end.x), 64):
		draw_rect(Rect2(Vector2(x - 2, r.position.y), Vector2(4, r.size.y)), Color("68777c"))
	for fracture_x in [r.position.x + 103.0, r.position.x + 247.0]:
		var c := Vector2(fracture_x, r.position.y + r.size.y * 0.48)
		for end in [Vector2(-18, -10), Vector2(21, -13), Vector2(-24, 9), Vector2(17, 12)]:
			draw_line(c, c + end, Color(0.82, 0.96, 1.0, 0.62), 1.2)


func _draw_plant(r: Rect2, seed: int) -> void:
	var c := r.get_center()
	draw_circle(c + Vector2(2, 3), 12.5, Color(0, 0, 0, 0.35))
	draw_circle(c, 11.0, Color("78482a"))
	draw_circle(c, 8.0, Color("243827"))
	for i in 7:
		var a := float(i) * TAU / 7.0 + seed * 0.13
		var leaf := c + Vector2.from_angle(a) * 7.0
		draw_circle(leaf, 4.5, Color("439359") if i % 2 == 0 else Color("2e7146"))


func _draw_counter(r: Rect2, idx: int) -> void:
	draw_rect(Rect2(r.position + Vector2(4, 5), r.size), Color(0, 0, 0, 0.34))
	draw_rect(r, Color("4b3524"))
	draw_rect(r.grow(-3), Color("765234"))
	draw_rect(r.grow(-4), Color("b68452"), false, 1.5)
	# The two broad bottom counters carry the blue drinking fountains shown in
	# the plan; the right one also carries the cluster of glasses.
	if idx in [1, 4]:
		var fountain := r.position + Vector2(r.size.x - 14, r.size.y * 0.5)
		draw_circle(fountain, 9.0, Color("2d719b"))
		draw_circle(fountain, 5.8, Color("80c9e8"))
	if idx == 4:
		for gy in 3:
			for gx in 4:
				draw_circle(r.position + Vector2(16 + gx * 6, r.size.y * 0.5 - 6 + gy * 6), 1.8, Color("f5a623"))


func _draw_service_fixture(fixture: Dictionary) -> void:
	var r: Rect2 = map.fixture_visual_rect(fixture)
	match String(fixture["kind"]):
		"register":
			_draw_cash_register(r, bool(fixture.get("damaged", false)))
		"food_line":
			_draw_food_line(r, bool(fixture.get("damaged", false)))
		"buffet":
			_draw_hollow_buffet(r)


func _draw_cash_register(r: Rect2, damaged: bool) -> void:
	draw_rect(Rect2(r.position + Vector2(4, 5), r.size), Color(0, 0, 0, 0.34))
	draw_rect(r, Color("343b40"))
	draw_rect(r.grow(-3), Color("7c8589"))
	draw_rect(r.grow(-4), Color("c0c8c8"), false, 1.5)
	var screen := Rect2(r.position + Vector2(18, 10), Vector2(32, 25))
	draw_rect(screen, Color("252c30"))
	draw_rect(screen.grow(-3), Color("558aa0"))
	for ky in 2:
		for kx in 5:
			draw_rect(Rect2(r.position + Vector2(62 + kx * 9, 11 + ky * 10), Vector2(6, 6)), Color("252b2e"))
	if damaged:
		draw_line(screen.position + Vector2(4, 3), screen.end - Vector2(5, 4), Color("b9e3ed"), 1.5)
		draw_line(r.position + Vector2(r.size.x - 21, 5), r.position + Vector2(r.size.x - 7, 18), Color("40474b"), 2.0)


func _draw_food_line(r: Rect2, damaged: bool) -> void:
	draw_rect(Rect2(r.position + Vector2(4, 5), r.size), Color(0, 0, 0, 0.34))
	draw_rect(r, Color("3d464b"))
	draw_rect(r.grow(-3), Color("8b9497"))
	draw_rect(r.grow(-5), Color("c1c7c6"), false, 1.5)
	var horizontal := r.size.x > r.size.y
	var length := r.size.x if horizontal else r.size.y
	var sections := maxi(2, floori(length / 94.0))
	for i in range(1, sections):
		var ratio := float(i) / sections
		if horizontal:
			draw_line(Vector2(lerpf(r.position.x, r.end.x, ratio), r.position.y + 5), Vector2(lerpf(r.position.x, r.end.x, ratio), r.end.y - 5), Color("4c5559"), 2.0)
		else:
			draw_line(Vector2(r.position.x + 5, lerpf(r.position.y, r.end.y, ratio)), Vector2(r.end.x - 5, lerpf(r.position.y, r.end.y, ratio)), Color("4c5559"), 2.0)
	# Pale cyan guard rails make the food lines read as glass and steel.
	var inset := r.grow(-8)
	draw_rect(inset, Color(0.58, 0.82, 0.86, 0.34), false, 2.0)
	if damaged:
		var c := r.get_center()
		draw_line(c + Vector2(-13, -8), c + Vector2(2, 5), Color("d4eff0"), 1.5)
		draw_line(c + Vector2(2, 5), c + Vector2(14, -4), Color("d4eff0"), 1.5)


func _draw_hollow_buffet(r: Rect2) -> void:
	var t := float(Cfg.TILE)
	var thickness := t
	var top_gap_start := 6.0 * t
	var top_gap_end := 9.0 * t
	var bottom_gap_start := 7.0 * t
	var bottom_gap_end := 10.0 * t
	var strips := [
		Rect2(r.position, Vector2(top_gap_start, thickness)),
		Rect2(r.position + Vector2(top_gap_end, 0), Vector2(r.size.x - top_gap_end, thickness)),
		Rect2(r.position + Vector2(0, r.size.y - thickness), Vector2(bottom_gap_start, thickness)),
		Rect2(r.position + Vector2(bottom_gap_end, r.size.y - thickness), Vector2(r.size.x - bottom_gap_end, thickness)),
		Rect2(r.position + Vector2(0, thickness), Vector2(thickness, r.size.y - 2.0 * thickness)),
		Rect2(r.position + Vector2(r.size.x - thickness, thickness), Vector2(thickness, r.size.y - 2.0 * thickness))
	]
	for strip in strips:
		draw_rect(Rect2(strip.position + Vector2(4, 5), strip.size), Color(0, 0, 0, 0.34))
		draw_rect(strip, Color("394247"))
		draw_rect(strip.grow(-3), Color("8f9899"))
		draw_rect(strip.grow(-5), Color("b8d3d3"), false, 1.6)
	var inner := r.grow(-thickness)
	# Glass guard panels stop at both entrances and are cracked in several spots.
	draw_line(inner.position, inner.position + Vector2((top_gap_start - thickness), 0), Color(0.62, 0.88, 0.90, 0.62), 3.0)
	draw_line(inner.position + Vector2(top_gap_end - thickness, 0), Vector2(inner.end.x, inner.position.y), Color(0.62, 0.88, 0.90, 0.62), 3.0)
	draw_line(Vector2(inner.position.x, inner.end.y), inner.position + Vector2(bottom_gap_start - thickness, inner.size.y), Color(0.62, 0.88, 0.90, 0.62), 3.0)
	draw_line(inner.position + Vector2(bottom_gap_end - thickness, inner.size.y), inner.end, Color(0.62, 0.88, 0.90, 0.62), 3.0)
	draw_line(inner.position, Vector2(inner.position.x, inner.end.y), Color(0.62, 0.88, 0.90, 0.62), 3.0)
	draw_line(Vector2(inner.end.x, inner.position.y), inner.end, Color(0.62, 0.88, 0.90, 0.62), 3.0)
	draw_line(inner.position + Vector2(inner.size.x * 0.23, 0), inner.position + Vector2(inner.size.x * 0.28, 15), Color("e0f2f2"), 1.7)
	draw_line(inner.position + Vector2(inner.size.x * 0.28, 15), inner.position + Vector2(inner.size.x * 0.34, 0), Color("e0f2f2"), 1.7)
	# Food trays on the thick display frame.
	var foods := [Color("c97832"), Color("7f9f45"), Color("d4b052"), Color("a94e3f")]
	for i in 9:
		var p := r.position + Vector2(42 + i * 45, 30 if i % 2 == 0 else r.size.y - 31)
		draw_rect(Rect2(p - Vector2(14, 8), Vector2(28, 16)), Color("4b5356"))
		draw_circle(p, 6.0, foods[i % foods.size()])
		draw_circle(p + Vector2(7, 2), 3.5, foods[(i + 1) % foods.size()])
	# Loose shards sit beside the top entrance and remain decorative.
	var shard_origin := r.position + Vector2(top_gap_start + 14, thickness + 9)
	for offset in [Vector2(-16, 3), Vector2(0, -4), Vector2(15, 7), Vector2(24, -6)]:
		var p: Vector2 = shard_origin + offset
		draw_polyline(PackedVector2Array([p + Vector2(-5, 3), p + Vector2(1, -5), p + Vector2(6, 4)]), Color(0.70, 0.92, 0.95, 0.72), 1.4)


func _draw_door_frames() -> void:
	var t := float(Cfg.TILE)
	draw_rect(Rect2(2 * t - 3, map.MAIN_BOTTOM * t - 7, 6 * t + 6, 10), Color("555d69"))
	draw_rect(Rect2((Cfg.MAP_W - 1) * t - 7, 2 * t - 3, 10, 6 * t + 6), Color("555d69"))
