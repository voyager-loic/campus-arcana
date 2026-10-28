extends Node

const MapData = preload("res://scripts/map_data.gd")
const Server = preload("res://scripts/server/server_game.gd")
const Cfg = preload("res://scripts/config.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
	print("PASS: " if condition else "FAIL: ", message)

func _ready() -> void:
	var original = MapData.new()
	var m = MapData.new("hg_e")
	check(original.map_id == "dining_hall" and original.W == 80 and original.tables.size() == 82, "original arena stays the default with its furniture intact")
	check(m.W * m.H > original.W * original.H * 3, "HG E has more than three times the map area")
	check(m.layout_overlaps.is_empty(), "HG E cover has no overlapping collision")
	for team in 2:
		for unit in 4:
			check(m._point_is_clear(m.spawn_position(team, unit), Cfg.SOLDIER_RADIUS), "formation %d/%d has full unit clearance" % [team, unit])
			check(not m.find_path(m.entry_position(team, unit), m.spawn_position(team, unit)).is_empty(), "unit %d/%d can deploy from its doorway" % [team, unit])
	check(not m.find_path(m.spawn_position(0, 0), m.spawn_position(1, 0)).is_empty(), "opposing entrances connect through the hall")
	var goals := [Vector2(29, 44), Vector2(138, 44), Vector2(29, 100), Vector2(138, 100), Vector2(67, 76), Vector2(100, 76), Vector2(42, 78), Vector2(124, 78), Vector2(55, 55), Vector2(119, 55), Vector2(15, 14), Vector2(151, 23)]
	for goal in goals:
		var destination: Vector2 = goal * m.T
		var path: PackedVector2Array = m.find_path(m.spawn_position(0, 0), destination)
		check(not path.is_empty() and path[-1].distance_to(destination) < m.T * 2, "region %s is connected to the playable floor" % goal)
	# Flood the floor so isolated patches can't masquerade as accessible rooms.
	var start := Vector2i(m.spawn_position(0, 0) / m.T)
	var queue: Array[Vector2i] = [start]
	var visited := {start: true}
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if not visited.has(next) and not m.is_wall_tile(next.x, next.y):
				visited[next] = true
				queue.append(next)
	var isolated := []
	for y in m.H:
		for x in m.W:
			if not m.is_wall_tile(x, y) and not visited.has(Vector2i(x, y)):
				isolated.append(Vector2i(x, y))
	check(isolated.is_empty(), "all floor cells are connected (%d isolated: %s)" % [isolated.size(), str(isolated.slice(0, 12))])
	m.set_doors_closed(true)
	check(m.is_wall_at(m.entry_position(0, 0)) and m.is_wall_at(m.entry_position(1, 0)), "both deployment doors block exit when closed")
	var server = Server.new()
	server.peers = [101, 202]
	server._enter_lobby()
	server.on_lobby_map(202, "hg_e")
	check(server.map.map_id == "dining_hall", "guest cannot change the selected map")
	server.lobby_ready = [true, true]
	server.on_lobby_map(101, "hg_e")
	check(server.map.map_id == "hg_e" and server.lobby_ready == [false, false], "host map change resets readiness and uses HG geometry")
	server.on_lobby_map(101, "invalid")
	check(server.map.map_id == "hg_e", "unknown map IDs are rejected")
	server.on_lobby_map(101, "dining_hall")
	check(server.map.map_id == "dining_hall", "host can return to the original arena")
	server.free()
	print("HG map failures: ", failures)
	get_tree().quit(1 if failures else 0)
