extends RefCounted
## Map geometry shared by server and client: wall grid, line of sight (grid DDA
## raycasts), fog occlusion, circle collision and A* pathfinding.
## Geometry follows the hand-drawn lecture/dining hall plan.  The drawing code
## uses the solid kind too, so server collision and client decoration cannot
## drift apart.

const Cfg = preload("res://scripts/config.gd")

const T := Cfg.TILE
const W := Cfg.MAP_W
const H := Cfg.MAP_H
const MAIN_H := 44
const MAIN_BOTTOM := MAIN_H - 1
const MATCH_SIZE := Vector2(W * T, MAIN_H * T)
const ROOM_LEFT := 27
const ROOM_RIGHT := 78
const ROOM_BREACH_LEFT := 72
const ROOM_BREACH_RIGHT := 76
const BREAKABLE_TABLE_HP := 70
const BREAKABLE_GLASS_HP := 84

enum SolidKind { NONE, WALL, TABLE, PLANT, COUNTER, VOID, RUBBLE, GLASS }
enum Zone { HALL, STAIR }

var grid := PackedByteArray()
var astar := AStarGrid2D.new()
var tables: Array[Dictionary] = []
var counter_rects: Array[Rect2i] = []
var service_fixtures: Array[Dictionary] = []
var breakable_fixtures: Array[Dictionary] = []
var layout_overlaps: Array[Vector2i] = []
var doors_closed := false
var breakable_revision := 0


func _init() -> void:
	grid.resize(W * H)
	grid.fill(0)
	_build_layout()
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(T, T)
	astar.offset = Vector2(T * 0.5, T * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in H:
		for x in W:
			if grid[y * W + x] != SolidKind.NONE:
				astar.set_point_solid(Vector2i(x, y), true)


func _set_solid(x: int, y: int, kind: int) -> void:
	if x >= 0 and y >= 0 and x < W and y < H:
		var old: int = grid[y * W + x]
		if kind != SolidKind.NONE and old != SolidKind.NONE and old != SolidKind.VOID and old != kind:
			layout_overlaps.append(Vector2i(x, y))
		grid[y * W + x] = kind


func _solid_line(from: Vector2i, to: Vector2i, kind := SolidKind.WALL) -> void:
	if from.x == to.x:
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			_set_solid(from.x, y, kind)
	else:
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			_set_solid(x, from.y, kind)


func _add_table(anchor: Vector2i, seats: int, angle := 0.0, tipped := false, damaged := false) -> void:
	assert(seats == 4 or seats == 8)
	var table := {"anchor": anchor, "seats": seats, "angle": angle, "tipped": tipped, "damaged": damaged}
	tables.append(table)
	for cell in table_collision_cells(table):
		_set_solid(cell.x, cell.y, SolidKind.TABLE)


## Tile approximation of the visible furniture. Upright tables keep their
## rectangular footprint; tipped tables use a narrow sampled line matching the
## rotated slab instead of retaining the much larger upright hitbox.
func table_collision_cells(table: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if bool(table.get("destroyed", false)):
		return cells
	var anchor: Vector2i = table["anchor"]
	if not bool(table.get("tipped", false)):
		var height := 2 if int(table["seats"]) == 4 else 3
		for y in range(anchor.y, anchor.y + height):
			for x in range(anchor.x, anchor.x + 2):
				cells.append(Vector2i(x, y))
		return cells
	var visual := table_visual_rect(table)
	var angle := float(table.get("angle", 0.0))
	var along := Vector2(-sin(angle), cos(angle))
	var half_length := visual.size.y * 0.5 - 5.0
	var samples := maxi(3, ceili(visual.size.y / (float(T) * 0.38)))
	for i in range(samples + 1):
		var p := visual.get_center() + along * lerpf(-half_length, half_length, float(i) / float(samples))
		var cell := Vector2i(floori(p.x / T), floori(p.y / T))
		if not cells.has(cell):
			cells.append(cell)
	return cells


func _table_group(y: int, start_x: int, count: int, seats: int) -> void:
	# Four-tile centres plus the 82px chair-to-chair furniture width leave a
	# consistent 46px aisle: almost exactly two 22px-wide soldiers.
	var x := start_x
	for _i in count:
		_add_table(Vector2i(x, y), seats)
		x += 4


func _disturb_table(anchor: Vector2i, angle: float, damaged := false, tipped := false) -> void:
	for table in tables:
		if table["anchor"] == anchor:
			for cell in table_collision_cells(table):
				grid[cell.y * W + cell.x] = SolidKind.NONE
			table["angle"] = angle
			table["damaged"] = damaged
			table["tipped"] = tipped
			for cell in table_collision_cells(table):
				_set_solid(cell.x, cell.y, SolidKind.TABLE)
			return


func _destroy_table(anchor: Vector2i) -> void:
	for table in tables:
		if table["anchor"] == anchor:
			var cells := table_collision_cells(table)
			table["destroyed"] = true
			for cell in cells:
				_set_solid(cell.x, cell.y, SolidKind.NONE)
			return


func _mark_table_breakable(anchor: Vector2i) -> void:
	for table in tables:
		if table["anchor"] == anchor:
			var id := breakable_count()
			table["breakable"] = true
			table["breakable_id"] = id
			table["hp"] = BREAKABLE_TABLE_HP
			table["damaged"] = true
			table["destroyed"] = false
			return
	push_error("Breakable table anchor not found: %s" % anchor)


func breakable_count() -> int:
	var count := 0
	for table in tables:
		if bool(table.get("breakable", false)):
			count += 1
	return count + breakable_fixtures.size()


func breakable_state() -> Array:
	var state := []
	state.resize(breakable_count())
	state.fill(0)
	for table in tables:
		if bool(table.get("breakable", false)):
			state[int(table["breakable_id"])] = int(table.get("hp", BREAKABLE_TABLE_HP))
	for fixture in breakable_fixtures:
		state[int(fixture["breakable_id"])] = int(fixture.get("hp", BREAKABLE_GLASS_HP))
	return state


func _set_breakable_hp(table: Dictionary, hp: int) -> bool:
	var next_hp := clampi(hp, 0, BREAKABLE_TABLE_HP)
	var old_hp := int(table.get("hp", BREAKABLE_TABLE_HP))
	if old_hp == next_hp:
		return false
	var was_destroyed := bool(table.get("destroyed", false))
	var destroyed := next_hp <= 0
	var old_cells: Array[Vector2i] = []
	if not was_destroyed:
		old_cells = table_collision_cells(table)
	table["destroyed"] = destroyed
	table["hp"] = next_hp
	if was_destroyed != destroyed:
		var new_cells: Array[Vector2i] = []
		if not destroyed:
			new_cells = table_collision_cells(table)
		for cell in old_cells:
			grid[cell.y * W + cell.x] = SolidKind.NONE
			astar.set_point_solid(cell, false)
		for cell in new_cells:
			grid[cell.y * W + cell.x] = SolidKind.TABLE
			astar.set_point_solid(cell, true)
	breakable_revision += 1
	return true


func _set_breakable_fixture_hp(fixture: Dictionary, hp: int) -> bool:
	var next_hp := clampi(hp, 0, BREAKABLE_GLASS_HP)
	var old_hp := int(fixture.get("hp", BREAKABLE_GLASS_HP))
	if old_hp == next_hp:
		return false
	var was_destroyed := bool(fixture.get("destroyed", false))
	var destroyed := next_hp <= 0
	fixture["destroyed"] = destroyed
	fixture["hp"] = next_hp
	if was_destroyed != destroyed:
		var rect: Rect2i = fixture["rect"]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				grid[y * W + x] = SolidKind.NONE if destroyed else SolidKind.GLASS
				astar.set_point_solid(Vector2i(x, y), destroyed == false)
	breakable_revision += 1
	return true


func apply_breakable_state(state) -> bool:
	var changed := false
	for table in tables:
		if not bool(table.get("breakable", false)):
			continue
		var id := int(table["breakable_id"])
		if id < state.size():
			var hp := (0 if bool(state[id]) else BREAKABLE_TABLE_HP) if typeof(state[id]) == TYPE_BOOL else int(state[id])
			changed = _set_breakable_hp(table, hp) or changed
	for fixture in breakable_fixtures:
		var id := int(fixture["breakable_id"])
		if id < state.size():
			var hp := (0 if bool(state[id]) else BREAKABLE_GLASS_HP) if typeof(state[id]) == TYPE_BOOL else int(state[id])
			changed = _set_breakable_fixture_hp(fixture, hp) or changed
	return changed


func reset_breakables() -> void:
	for table in tables:
		if bool(table.get("breakable", false)):
			_set_breakable_hp(table, BREAKABLE_TABLE_HP)
	for fixture in breakable_fixtures:
		_set_breakable_fixture_hp(fixture, BREAKABLE_GLASS_HP)


## Damage breakable cover touched by a circular blast. Every affected prop emits
## [id, centre, kind, destroyed, damage dealt, hp, max hp] for client feedback.
func damage_breakables(center: Vector2, radius: float, damage: int) -> Array:
	var hits := []
	if damage <= 0:
		return hits
	for table in tables:
		if not bool(table.get("breakable", false)) or bool(table.get("destroyed", false)):
			continue
		var touched := false
		for cell in table_collision_cells(table):
			var rect := Rect2(Vector2(cell) * float(T), Vector2(T, T))
			var nearest := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
			if center.distance_to(nearest) <= radius:
				touched = true
				break
		if not touched:
			continue
		var old_hp := int(table.get("hp", BREAKABLE_TABLE_HP))
		var next_hp := maxi(0, old_hp - damage)
		if _set_breakable_hp(table, next_hp):
			hits.append([int(table["breakable_id"]), table_visual_rect(table).get_center(), "table", next_hp <= 0, old_hp - next_hp, next_hp, BREAKABLE_TABLE_HP])
	for fixture in breakable_fixtures:
		if bool(fixture.get("destroyed", false)):
			continue
		var cells: Rect2i = fixture["rect"]
		var rect := Rect2(Vector2(cells.position) * float(T), Vector2(cells.size) * float(T))
		var nearest := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
		if center.distance_to(nearest) > radius:
			continue
		var old_hp := int(fixture.get("hp", BREAKABLE_GLASS_HP))
		var next_hp := maxi(0, old_hp - damage)
		if _set_breakable_fixture_hp(fixture, next_hp):
			hits.append([int(fixture["breakable_id"]), rect.get_center(), str(fixture["kind"]), next_hp <= 0, old_hp - next_hp, next_hp, BREAKABLE_GLASS_HP])
	return hits


func damage_breakable_at(point: Vector2, damage: int) -> Array:
	for table in tables:
		if not bool(table.get("breakable", false)) or bool(table.get("destroyed", false)):
			continue
		for cell in table_collision_cells(table):
			if Rect2(Vector2(cell) * float(T), Vector2(T, T)).has_point(point):
				return damage_breakables(point, 1.0, damage)
	for fixture in breakable_fixtures:
		if bool(fixture.get("destroyed", false)):
			continue
		var cells: Rect2i = fixture["rect"]
		var rect := Rect2(Vector2(cells.position) * float(T), Vector2(cells.size) * float(T))
		if rect.has_point(point):
			return damage_breakables(point, 1.0, damage)
	return []


func _add_breakable_glass(rect: Rect2i) -> void:
	var fixture := {
		"kind": "glass_wall", "rect": rect, "breakable_id": breakable_count(),
		"hp": BREAKABLE_GLASS_HP, "destroyed": false,
	}
	breakable_fixtures.append(fixture)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_set_solid(x, y, SolidKind.GLASS)


func _add_counter(rect: Rect2i) -> void:
	counter_rects.append(rect)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_set_solid(x, y, SolidKind.COUNTER)


func _add_service_fixture(kind: String, rect: Rect2i, damaged := false) -> void:
	service_fixtures.append({"kind": kind, "rect": rect, "damaged": damaged})
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_set_solid(x, y, SolidKind.COUNTER)


func _add_hollow_buffet(rect: Rect2i) -> void:
	var top_gap := Vector2i(6, 9)
	var bottom_gap := Vector2i(7, 10)
	service_fixtures.append({
		"kind": "buffet", "rect": rect, "damaged": true, "thickness": 1,
		"top_gap": top_gap, "bottom_gap": bottom_gap
	})
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var local_x := x - rect.position.x
			var local_y := y - rect.position.y
			var on_rim := local_x < 1 or local_x >= rect.size.x - 1 or local_y < 1 or local_y >= rect.size.y - 1
			var in_top_entry := local_y < 1 and local_x >= top_gap.x and local_x < top_gap.y
			var in_bottom_entry := local_y >= rect.size.y - 1 and local_x >= bottom_gap.x and local_x < bottom_gap.y
			if on_rim and not in_top_entry and not in_bottom_entry:
				_set_solid(x, y, SolidKind.COUNTER)


func _build_layout() -> void:
	# Space below the original hall is non-playable except for the new room.
	for y in range(MAIN_H, H):
		for x in W:
			_set_solid(x, y, SolidKind.VOID)

	# Outer shell.  The only breaks are the two opposing team entrances.
	_solid_line(Vector2i(0, 0), Vector2i(W - 1, 0))
	_solid_line(Vector2i(0, MAIN_BOTTOM), Vector2i(W - 1, MAIN_BOTTOM))
	_solid_line(Vector2i(0, 0), Vector2i(0, MAIN_BOTTOM))
	_solid_line(Vector2i(W - 1, 0), Vector2i(W - 1, MAIN_BOTTOM))
	for x in range(2, 8):
		_set_solid(x, MAIN_BOTTOM, SolidKind.NONE) # Entrance 1 (Blue)
	for y in range(2, 8):
		_set_solid(W - 1, y, SolidKind.NONE) # Entrance 2 (Red)

	# Central passage and the empty square room requested below the main hall.
	for y in range(MAIN_BOTTOM + 1, H - 1):
		for x in range(ROOM_LEFT, ROOM_RIGHT + 1):
			_set_solid(x, y, SolidKind.NONE)
	_solid_line(Vector2i(ROOM_LEFT, MAIN_BOTTOM), Vector2i(ROOM_LEFT, H - 2))
	_solid_line(Vector2i(ROOM_RIGHT, MAIN_BOTTOM), Vector2i(ROOM_RIGHT, H - 2))
	_solid_line(Vector2i(ROOM_LEFT, H - 2), Vector2i(ROOM_RIGHT, H - 2))
	# Wide opening into the lower room begins immediately after the left fountain.
	for x in range(32, 43):
		_set_solid(x, MAIN_BOTTOM, SolidKind.NONE)
	# A blast opened a second route at the far-right end of the shared wall.
	for x in range(ROOM_BREACH_LEFT, ROOM_BREACH_RIGHT + 1):
		_set_solid(x, MAIN_BOTTOM, SolidKind.NONE)

	# Fixed partitions A and B from the supplied plan. Their gaps are the aisles.
	_solid_line(Vector2i(8, 8), Vector2i(34, 8))
	_solid_line(Vector2i(42, 8), Vector2i(68, 8))
	_solid_line(Vector2i(8, 17), Vector2i(34, 17))
	_solid_line(Vector2i(42, 18), Vector2i(68, 18))
	_solid_line(Vector2i(8, 30), Vector2i(34, 30))
	_solid_line(Vector2i(42, 30), Vector2i(68, 30))

	# Exact furniture groups from the clean plan: 66 eight-chair tables and 24
	# four-chair tables. One record is one physical table, never a stacked pair.
	# North row is interrupted by the blast site. The adjacent tables survived
	# but are visibly damaged.
	for x in range(4, 73, 4):
		if x not in [16, 20]:
			_add_table(Vector2i(x, 1), 8, 0.0, false, x in [12, 24])
	_table_group(10, 9, 6, 4)
	_table_group(14, 9, 6, 8)
	_table_group(20, 9, 6, 8)
	# Only three displaced tables remain in this bombed-out part of the hall.
	_add_table(Vector2i(46, 10), 8, -0.24)
	_add_table(Vector2i(56, 9), 8, 0.18)
	_add_table(Vector2i(65, 10), 8, 1.08, true)
	_table_group(14, 45, 6, 8)
	_table_group(20, 45, 6, 8)
	_table_group(27, 10, 5, 4)
	_table_group(31, 9, 5, 4)
	_table_group(27, 43, 7, 4)
	_table_group(31, 50, 5, 4)
	_table_group(39, 8, 4, 8)
	_table_group(39, 50, 7, 8)

	# Subtle irregularities across the main room keep the furniture from reading
	# as a pristine mirrored grid while preserving its collision footprint.
	_disturb_table(Vector2i(13, 14), 0.10, true)
	_disturb_table(Vector2i(25, 20), -0.11)
	_disturb_table(Vector2i(53, 14), 0.08, true)
	_disturb_table(Vector2i(22, 27), -0.17, false, true)
	_disturb_table(Vector2i(62, 31), 0.12, true)
	_disturb_table(Vector2i(16, 39), -0.09)
	_disturb_table(Vector2i(62, 39), 0.62, true, true)
	_destroy_table(Vector2i(74, 39))
	# Cracked tables act as destructible cover. A fireball or the heavy return
	# projectile collapses them into walkable debris and opens a new route.
	for anchor in [Vector2i(12, 1), Vector2i(24, 1), Vector2i(13, 14), Vector2i(53, 14),
			Vector2i(25, 20), Vector2i(22, 27), Vector2i(62, 31), Vector2i(62, 39),
			Vector2i(65, 10), Vector2i(46, 10)]:
		_mark_table_breakable(anchor)

	# Plants and service furniture shown in the plan.
	for p in [Vector2i(2, 2), Vector2i(33, 11), Vector2i(32, 27), Vector2i(42, 19)]:
		_set_solid(p.x, p.y, SolidKind.PLANT)
	_add_counter(Rect2i(29, 31, 5, 1)) # left slim service table
	_add_counter(Rect2i(27, 41, 5, 2)) # left drinking fountain counter against wall
	_add_counter(Rect2i(42, 31, 4, 1)) # right slim service table
	_add_counter(Rect2i(46, 31, 3, 2)) # right square service station
	_add_counter(Rect2i(43, 41, 5, 2)) # right fountain shifted clear of lower passage
	# A broad glass security wall seals the main entrance to the lower cafeteria.
	# It is solid cover until shattered, while the smaller blast breach remains an
	# alternate route into the room.
	_add_breakable_glass(Rect2i(32, MAIN_BOTTOM, 11, 1))

	# Lower cafeteria room. The fixtures follow the annotated plan while leaving
	# broad circulation routes around every service area.
	_add_service_fixture("register", Rect2i(36, 45, 3, 2), true)
	_add_service_fixture("food_line", Rect2i(28, 47, 2, 9), true)
	_add_service_fixture("food_line", Rect2i(44, 47, 15, 2), true)
	_add_service_fixture("food_line", Rect2i(72, 51, 2, 12), true)
	_add_hollow_buffet(Rect2i(40, 55, 16, 9))

	# The former sealed doorway on the lower room's left wall is now a collapsed
	# passage. The pile extends into the room and remains fully collidable.
	var left_passage_rubble := [
		Vector2i(59, 29), Vector2i(60, 30), Vector2i(61, 31),
		Vector2i(62, 31), Vector2i(63, 30), Vector2i(64, 29), Vector2i(65, 28)
	]
	for span in left_passage_rubble:
		for x in range(ROOM_LEFT, span.y + 1):
			_set_solid(x, span.x, SolidKind.NONE)
			_set_solid(x, span.x, SolidKind.RUBBLE)

	# Solid wreckage closes the entire upper passage at the explosion site.
	var rubble_spans := [Vector2i(16, 21), Vector2i(15, 22), Vector2i(16, 21), Vector2i(17, 21), Vector2i(16, 22), Vector2i(17, 20), Vector2i(18, 19)]
	for y in range(1, 8):
		var span: Vector2i = rubble_spans[y - 1]
		for x in range(span.x, span.y + 1):
			_set_solid(x, y, SolidKind.RUBBLE)


func tile_zone(x: int, y: int) -> int:
	return Zone.HALL


func solid_kind(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return SolidKind.WALL
	return grid[y * W + x]


func is_table_tile(x: int, y: int) -> bool:
	return solid_kind(x, y) == SolidKind.TABLE


func table_visual_rect(table: Dictionary) -> Rect2:
	var anchor: Vector2i = table["anchor"]
	var seats: int = table["seats"]
	return Rect2(anchor.x * T + 8, anchor.y * T + 4, 48, 56 if seats == 4 else 88)


func counter_visual_rect(cells: Rect2i) -> Rect2:
	return Rect2(cells.position * T + Vector2i(3, 3), cells.size * T - Vector2i(6, 6))


func fixture_visual_rect(fixture: Dictionary) -> Rect2:
	return counter_visual_rect(fixture["rect"])


func is_wall_tile(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= W or y >= H:
		return true
	return (doors_closed and is_door_tile(x, y)) or grid[y * W + x] != SolidKind.NONE


func is_door_tile(x: int, y: int) -> bool:
	return (y == MAIN_BOTTOM and x >= 2 and x < 8) or (x == W - 1 and y >= 2 and y < 8)


func set_doors_closed(closed: bool) -> void:
	doors_closed = closed
	for x in range(2, 8):
		astar.set_point_solid(Vector2i(x, MAIN_BOTTOM), closed)
	for y in range(2, 8):
		astar.set_point_solid(Vector2i(W - 1, y), closed)


func is_wall_at(p: Vector2) -> bool:
	return is_wall_tile(floori(p.x / T), floori(p.y / T))


func spawn_position(team: int, idx: int) -> Vector2:
	var blue := [Vector2(4.0, 40.0), Vector2(6.0, 40.0), Vector2(4.0, 36.0), Vector2(7.0, 36.0)]
	var red := [Vector2(74.0, 4.0), Vector2(70.0, 4.0), Vector2(73.5, 12.0), Vector2(70.0, 13.0)]
	return (blue[idx] if team == 0 else red[idx]) * float(T)


func entry_position(team: int, idx: int) -> Vector2:
	# Units wait immediately behind their open threshold, then fan into the hall.
	var offset := (idx - (Cfg.SQUAD_SIZE - 1) * 0.5) * 5.0
	if team == 0:
		return Vector2(4.5 * T + offset, (MAIN_H - 0.65) * T)
	return Vector2((W - 0.65) * T, 4.5 * T + offset)


func spawn_facing(team: int) -> float:
	return -PI * 0.5 if team == 0 else PI


## How far a circle of radius r can walk from `from` along unit `dir` before
## touching a wall (capped at max_d).
func walk_distance(from: Vector2, dir: Vector2, max_d: float, r: float) -> float:
	var n := Vector2(-dir.y, dir.x) * (r - 1.0)
	var reach := max_d + r + 2.0
	var best := reach
	for off in [Vector2.ZERO, n, -n]:
		best = minf(best, raycast(from + off, dir, reach))
	return clampf(best - r - 2.0, 0.0, max_d)


## Distance along a normalised direction until the first wall (capped at max_d).
func raycast(o: Vector2, d: Vector2, max_d: float) -> float:
	var x := floori(o.x / T)
	var y := floori(o.y / T)
	if is_wall_tile(x, y):
		return 0.0
	var step_x := 1 if d.x > 0.0 else -1
	var step_y := 1 if d.y > 0.0 else -1
	var t_max_x := INF
	var t_max_y := INF
	var t_dx := INF
	var t_dy := INF
	if absf(d.x) > 1e-9:
		var nx := float((x + (1 if d.x > 0.0 else 0)) * T)
		t_max_x = (nx - o.x) / d.x
		t_dx = T / absf(d.x)
	if absf(d.y) > 1e-9:
		var ny := float((y + (1 if d.y > 0.0 else 0)) * T)
		t_max_y = (ny - o.y) / d.y
		t_dy = T / absf(d.y)
	var t := 0.0
	while true:
		if t_max_x < t_max_y:
			t = t_max_x
			if t >= max_d:
				return max_d
			x += step_x
			t_max_x += t_dx
		else:
			t = t_max_y
			if t >= max_d:
				return max_d
			y += step_y
			t_max_y += t_dy
		if is_wall_tile(x, y):
			return t
	return max_d


## Clip a ray (origin, unit dir, current length) by fog clouds.
## fogs: Array of [Vector2 centre, float radius]
static func fog_clip(o: Vector2, d: Vector2, length: float, fogs: Array) -> float:
	var best := length
	for s in fogs:
		var c: Vector2 = s[0]
		var r: float = s[1]
		var oc := c - o
		var proj := oc.dot(d)
		var h2 := oc.length_squared() - proj * proj
		if h2 >= r * r:
			continue
		var half := sqrt(r * r - h2)
		var t0 := proj - half
		var t1 := proj + half
		var enter := maxf(t0, 0.0)
		if t1 - enter > Cfg.FOG_SEE_DEPTH:
			best = minf(best, enter + Cfg.FOG_SEE_DEPTH)
	return best


## Visible distance along a ray, considering walls and fog.
func sight_distance(o: Vector2, d: Vector2, max_d: float, fogs: Array) -> float:
	var dist := raycast(o, d, max_d)
	if not fogs.is_empty():
		dist = fog_clip(o, d, dist, fogs)
	return dist


func has_los(a: Vector2, b: Vector2, fogs: Array) -> bool:
	var diff := b - a
	var length := diff.length()
	if length < 0.001:
		return true
	var d := diff / length
	return sight_distance(a, d, length, fogs) >= length - 0.5


## Is p inside the vision area of a soldier at `origin` facing `facing`?
## (Range/cone test only, no occlusion.)
static func in_view_shape(origin: Vector2, facing: float, p: Vector2) -> bool:
	var diff := p - origin
	var dist := diff.length()
	if dist <= Cfg.AWARE_RADIUS:
		return true
	if dist > Cfg.VIEW_RANGE:
		return false
	return absf(angle_difference(facing, diff.angle())) <= Cfg.VIEW_CONE * 0.5


func can_see(origin: Vector2, facing: float, p: Vector2, fogs: Array) -> bool:
	return in_view_shape(origin, facing, p) and has_los(origin, p, fogs)


## A circle of radius r can travel in a straight line from a to b.
func clear_walk(a: Vector2, b: Vector2, r: float) -> bool:
	var diff := b - a
	var length := diff.length()
	if length < 0.001:
		return true
	var d := diff / length
	var n := Vector2(-d.y, d.x) * (r + 1.0)
	for off in [Vector2.ZERO, n, -n]:
		if raycast(a + off, d, length) < length:
			return false
	return true


## Push a circle out of any overlapping wall tiles.
func resolve_circle(p: Vector2, r: float) -> Vector2:
	for _iter in 3:
		var moved := false
		var x0 := floori((p.x - r) / T)
		var x1 := floori((p.x + r) / T)
		var y0 := floori((p.y - r) / T)
		var y1 := floori((p.y + r) / T)
		for ty in range(y0, y1 + 1):
			for tx in range(x0, x1 + 1):
				if not is_wall_tile(tx, ty):
					continue
				var rmin := Vector2(tx * T, ty * T)
				var closest := Vector2(clampf(p.x, rmin.x, rmin.x + T), clampf(p.y, rmin.y, rmin.y + T))
				var diff := p - closest
				var dist := diff.length()
				if dist < r:
					if dist > 0.0001:
						p += diff / dist * (r - dist)
					else:
						var cdir := p - (rmin + Vector2(T, T) * 0.5)
						if cdir.length() < 0.001:
							cdir = Vector2.RIGHT
						p += cdir.normalized() * r
					moved = true
		if not moved:
			break
	p.x = clampf(p.x, r, Cfg.WORLD_SIZE.x - r)
	p.y = clampf(p.y, r, Cfg.WORLD_SIZE.y - r)
	return p


func _nearest_open_tile(t: Vector2i) -> Vector2i:
	if not is_wall_tile(t.x, t.y):
		return t
	for radius in range(1, 6):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c := t + Vector2i(dx, dy)
				if not is_wall_tile(c.x, c.y):
					var dd := Vector2(dx, dy).length()
					if dd < best_d:
						best_d = dd
						best = c
		if best.x >= 0:
			return best
	return t


## Returns waypoints (pixel coords) from `from` to `to` (excluding the start).
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	to.x = clampf(to.x, 1.0, Cfg.WORLD_SIZE.x - 1.0)
	to.y = clampf(to.y, 1.0, Cfg.WORLD_SIZE.y - 1.0)
	var ft := _nearest_open_tile(Vector2i(floori(from.x / T), floori(from.y / T)))
	var tt_raw := Vector2i(floori(to.x / T), floori(to.y / T))
	var tt := _nearest_open_tile(tt_raw)
	var pts := astar.get_point_path(ft, tt, true)
	var out := PackedVector2Array()
	for i in range(1, pts.size()):
		out.append(pts[i])
	# Final waypoint: the exact click location if it is on open floor.
	if tt == tt_raw and not pts.is_empty() and Vector2i(floori(pts[pts.size() - 1].x / T), floori(pts[pts.size() - 1].y / T)) == tt:
		var exact := resolve_circle(to, Cfg.SOLDIER_RADIUS)
		if out.is_empty():
			out.append(exact)
		else:
			out[out.size() - 1] = exact
	return out


func debug_print() -> void:
	for y in H:
		var s := ""
		for x in W:
			s += "#" if grid[y * W + x] == 1 else "."
		print(s)
