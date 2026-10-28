extends RefCounted
## Traced architectural adaptation of ETH's HG E plan (HG_E_20171010).
## North on this drawing faces Rämistrasse. Cells are approximately one metre;
## doorways and circulation have been widened for squad clearance.
## Geometry is built once and shared by rendering, movement and line of sight.

static func build(m) -> void:
	m.grid.fill(m.SolidKind.VOID)
	# Public circulation: north/south side wings and the main E-floor body.
	_floor(m, Rect2i(25, 3, 8, 112), "WEST CORRIDOR", "corridor")
	_floor(m, Rect2i(134, 3, 8, 112), "EAST CORRIDOR", "corridor")
	_floor(m, Rect2i(10, 3, 32, 25), "NORTH WING", "wing")
	_floor(m, Rect2i(125, 3, 34, 25), "SOUTH WING", "wing")
	_floor(m, Rect2i(33, 40, 101, 65), "", "foyer")
	_floor(m, Rect2i(25, 98, 117, 7), "SOUTH CROSSING", "corridor")
	_floor(m, Rect2i(33, 46, 101, 6), "NORTH CROSSING", "corridor")
	_floor(m, Rect2i(25, 40, 117, 7), "", "corridor")
	_floor(m, Rect2i(74, 101, 20, 14), "POLYTERRASSE", "entry")
	_floor(m, Rect2i(76, 47, 18, 47), "HAUPTHALLE  ·  E 4", "hall")
	# Curved eastern entrance hall / Studicafé, joined to the central axis.
	var rotunda := PackedVector2Array([Vector2(67, 48), Vector2(67, 41)])
	for i in 25:
		var angle := PI + float(i) * PI / 24.0
		rotunda.append(Vector2(84, 42) + Vector2(cos(angle) * 17.0, sin(angle) * 18.0))
	rotunda.append(Vector2(101, 48))
	_polygon(m, rotunda, "VORHALLE  ·  STUDICAFÉ", "rotunda")
	_floor(m, Rect2i(80, 23, 8, 8), "RÄMISTRASSE", "entry")
	# The two main lecture rooms sit inside the western and eastern foyers.
	_room(m, [Vector2(75, 62), Vector2(68, 62), Vector2(63, 65), Vector2(60, 71), Vector2(60, 82), Vector2(64, 89), Vector2(69, 92), Vector2(75, 92)], "E 3", "lecture")
	_room(m, [Vector2(94, 62), Vector2(102, 62), Vector2(107, 67), Vector2(109, 74), Vector2(109, 81), Vector2(105, 88), Vector2(101, 92), Vector2(94, 92)], "E 5", "lecture")
	_open(m, Rect2i(73, 66, 4, 4))
	_open(m, Rect2i(73, 85, 4, 4))
	_open(m, Rect2i(92, 66, 4, 4))
	_open(m, Rect2i(92, 85, 4, 4))
	# Fan-shaped auditorium pair (E 1.1/E 1.2) and E 7, as on the plan.
	_room(m, [Vector2(37, 62), Vector2(42, 63), Vector2(48, 67), Vector2(52, 72), Vector2(53, 77), Vector2(50, 84), Vector2(45, 90), Vector2(37, 95), Vector2(34, 88), Vector2(33, 79), Vector2(34, 70)], "E 1.1 / E 1.2", "fan_west")
	_room(m, [Vector2(130, 62), Vector2(125, 63), Vector2(119, 67), Vector2(115, 72), Vector2(114, 78), Vector2(117, 85), Vector2(122, 91), Vector2(130, 95), Vector2(133, 87), Vector2(134, 79), Vector2(133, 70)], "E 7", "fan_east")
	_open(m, Rect2i(36, 61, 4, 5))
	_open(m, Rect2i(36, 91, 4, 6))
	_open(m, Rect2i(127, 61, 4, 5))
	_open(m, Rect2i(127, 91, 4, 6))
	# Public computer/seminar rooms across the north arm.
	_rect_room(m, Rect2i(33, 51, 15, 9), "E 26.1")
	_rect_room(m, Rect2i(48, 51, 14, 9), "E 26.3")
	_rect_room(m, Rect2i(104, 51, 10, 9), "E 33.1")
	_rect_room(m, Rect2i(114, 51, 10, 9), "E 33.3")
	_rect_room(m, Rect2i(124, 51, 10, 9), "E 33.5")
	for x in [39, 53, 107, 117, 127]:
		_open(m, Rect2i(x, 50, 3, 3))
	# E 27 and the small service block north of the crossing.
	_rect_room(m, Rect2i(42, 40, 24, 6), "E 27")
	_open(m, Rect2i(52, 44, 4, 4))
	for x in [103, 110, 117, 124]:
		_closed(m, Rect2i(x, 40, 7, 6), "SERVICE")
	# Office/classroom wings retain the actual rhythm of small rooms. Some are
	# sealed scenery; the larger numbered classrooms have traversable doors.
	for side in 2:
		var x := 33 if side == 0 else 125
		for i in 3:
			_rect_room(m, Rect2i(x, 7 + i * 10, 9, 10), ("E %d" % (21 + i)) if side == 0 else ("E %d" % (39 - i)))
			_open(m, Rect2i(x - 1 if side == 0 else x + 7, 11 + i * 10, 4, 3))
	for i in 7:
		_closed(m, Rect2i(20, 42 + i * 8, 6, 8), "OFFICE")
		_closed(m, Rect2i(141, 42 + i * 8, 6, 8), "OFFICE")
	for i in 8:
		_closed(m, Rect2i(33 + i * 5, 105, 5, 8), "OFFICE")
		_closed(m, Rect2i(95 + i * 5, 105, 5, 8), "OFFICE")
	# Outer north corners and small southern stair wings.
	_rect_room(m, Rect2i(10, 7, 12, 12), "E 19")
	_open(m, Rect2i(20, 12, 7, 3))
	_rect_room(m, Rect2i(146, 7, 13, 12), "E 41")
	_open(m, Rect2i(140, 12, 8, 3))
	_rect_room(m, Rect2i(146, 19, 13, 9), "E 42")
	_open(m, Rect2i(140, 22, 8, 3))
	_floor(m, Rect2i(21, 105, 12, 12), "WEST STAIR", "wing")
	_floor(m, Rect2i(134, 105, 13, 12), "E 53", "wing")
	# Peripheral auditoria appear in their characteristic projecting wings.
	_room(m, [Vector2(2, 51), Vector2(7, 47), Vector2(16, 47), Vector2(16, 70), Vector2(7, 70), Vector2(2, 66), Vector2(1, 59)], "E 3 ANNEX", "lecture")
	_room(m, [Vector2(153, 47), Vector2(162, 47), Vector2(167, 52), Vector2(168, 60), Vector2(166, 66), Vector2(161, 70), Vector2(153, 70)], "E 7 ANNEX", "lecture")
	_floor(m, Rect2i(15, 54, 11, 5), "", "corridor")
	_floor(m, Rect2i(141, 54, 13, 5), "", "corridor")
	# Wrap an impassable wall around the exact carved footprint.
	var boundary: Array[Vector2i] = []
	for y in range(1, m.H - 1):
		for x in range(1, m.W - 1):
			if m.solid_kind(x, y) != m.SolidKind.NONE:
				continue
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if m.solid_kind(x + d.x, y + d.y) == m.SolidKind.VOID:
					boundary.append(Vector2i(x, y))
	for cell in boundary:
		_put(m, cell.x, cell.y, m.SolidKind.WALL)
	# Door thresholds are independently animated and close after deployment.
	_open(m, Rect2i(81, 23, 6, 2))
	_open(m, Rect2i(81, 113, 6, 2))
	# Columns in the long main hall and the curved entrance foyer.
	for y in [53, 62, 72, 82, 91]:
		for x in [78, 91]:
			_put(m, x, y, m.SolidKind.WALL)
	for p in [Vector2i(72, 40), Vector2i(75, 34), Vector2i(78, 30), Vector2i(90, 30), Vector2i(94, 34), Vector2i(97, 40)]:
		_put(m, p.x, p.y, m.SolidKind.WALL)
	# Grazienbrunnen is a compact stone-and-water obstacle in the entrance hall.
	m._add_counter(Rect2i(83, 40, 3, 3))
	# Stairs are textures only and preserve ordinary planar movement.
	for stair in [Rect2i(69, 49, 5, 5), Rect2i(96, 49, 5, 5), Rect2i(69, 95, 5, 5), Rect2i(96, 95, 5, 5), Rect2i(27, 15, 4, 8), Rect2i(136, 15, 4, 8)]:
		m.stairs.append(stair)
	# Desks and benches provide cover in classrooms, leaving central aisles.
	for x in [35, 42, 50, 57, 106, 116, 126]:
		_table(m, Vector2i(x, 55), false)
	for x in [65, 70, 97, 102]:
		for y in [72, 78, 84]:
			_table(m, Vector2i(x, y), y == 78)
	for p in [Vector2i(56, 68), Vector2i(111, 89), Vector2i(35, 97), Vector2i(126, 97), Vector2i(29, 36), Vector2i(136, 37)]:
		_table(m, p, true)
	for p in [Vector2i(80, 58), Vector2i(88, 76), Vector2i(80, 87)]:
		_table(m, p, true)
	for p in [Vector2i(34, 43), Vector2i(129, 43), Vector2i(35, 99), Vector2i(130, 99)]:
		_put(m, p.x, p.y, m.SolidKind.PLANT)
	# Seating is recorded once for both drawing and collision. Radial aisles
	# and the interrupted central row leave paths across each fan auditorium.
	for center in [Vector2(51, 78), Vector2(116, 78)]:
		var west: bool = center.x < 84
		for radius in [5.0, 8.0, 11.0, 14.0]:
			for seat in 17:
				if seat in [7, 8, 9]:
					continue
				var angle: float = (PI * 0.63 if west else -PI * 0.37) + seat * PI * 0.74 / 16.0
				var cell := Vector2i((center + Vector2.from_angle(angle) * radius).floor())
				var clear := true
				for d in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if m.solid_kind(cell.x + d.x, cell.y + d.y) != m.SolidKind.NONE:
						clear = false
				if clear:
					_put(m, cell.x, cell.y, m.SolidKind.COUNTER)
					m.lecture_seats.append({"cell": cell, "angle": angle})
	for x in [12, 17, 149, 154]:
		for y in [9, 15]:
			_table(m, Vector2i(x, y), false)
	for x in [5, 10, 157, 162]:
		for y in [51, 61, 65]:
			_table(m, Vector2i(x, y), y == 61)


static func _put(m, x: int, y: int, kind: int) -> void:
	if x >= 0 and y >= 0 and x < m.W and y < m.H:
		m.grid[y * m.W + x] = kind


static func _open(m, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_put(m, x, y, m.SolidKind.NONE)


static func _floor(m, rect: Rect2i, label: String, kind: String) -> void:
	_open(m, rect)
	m.regions.append({"rect": rect, "label": label, "kind": kind})


static func _polygon(m, points: PackedVector2Array, label: String, kind: String) -> void:
	for y in m.H:
		for x in m.W:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
				_put(m, x, y, m.SolidKind.NONE)
	m.regions.append({"polygon": points, "label": label, "kind": kind})


static func _room(m, points: PackedVector2Array, label: String, kind: String) -> void:
	_polygon(m, points, label, kind)
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var steps := ceili(a.distance_to(b) * 2.0)
		for step in steps + 1:
			var cell := Vector2i(a.lerp(b, float(step) / maxi(1, steps)).floor())
			_put(m, cell.x, cell.y, m.SolidKind.WALL)


static func _rect_room(m, rect: Rect2i, label: String) -> void:
	var p := Vector2(rect.position)
	var end := Vector2(rect.end - Vector2i.ONE)
	_room(m, PackedVector2Array([p, Vector2(end.x, p.y), end, Vector2(p.x, end.y)]), label, "classroom")


static func _closed(m, rect: Rect2i, label: String) -> void:
	m.closed_rooms.append({"rect": rect, "label": label})
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_put(m, x, y, m.SolidKind.WALL)


static func _table(m, anchor: Vector2i, breakable: bool) -> void:
	for y in range(anchor.y - 1, anchor.y + 4):
		for x in range(anchor.x - 1, anchor.x + 3):
			if m.solid_kind(x, y) != m.SolidKind.NONE:
				return
	m._add_table(anchor, 4, -0.14 if breakable else 0.0, false, breakable)
	if breakable:
		m._mark_table_breakable(anchor)
