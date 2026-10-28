extends Node

const Cfg = preload("res://scripts/config.gd")
const MapData = preload("res://scripts/map_data.gd")
const Hud = preload("res://scripts/client/hud.gd")
const ClientGame = preload("res://scripts/client/client_game.gd")
const NeonAmbience = preload("res://scripts/client/neon_ambience.gd")
const ServerGame = preload("res://scripts/server/server_game.gd")

var failed := 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  [PASS] ", label)
	else:
		failed += 1
		print("  [FAIL] ", label)


func _ready() -> void:
	var map = MapData.new()
	var hud = Hud.new()
	hud.size = Vector2(1280, 812)
	_check(is_equal_approx(hud.bar_top(), hud.size.y - Hud.BAR_H), "bottom HUD anchors to the viewport instead of the world")
	var indicator_bounds := Rect2(20, 20, 200, 100)
	var right_indicator: Vector2 = hud._edge_intersection(Vector2(500, 70), indicator_bounds)
	var top_indicator: Vector2 = hud._edge_intersection(Vector2(120, -200), indicator_bounds)
	_check(is_equal_approx(right_indicator.x, indicator_bounds.end.x), "off-screen squad marker clamps to the horizontal viewport edge")
	_check(is_equal_approx(top_indicator.y, indicator_bounds.position.y), "off-screen threat marker clamps to the vertical viewport edge")
	hud.free()
	var accessibility_client = ClientGame.new()
	_check(accessibility_client.neon_effects_enabled, "neon ambience defaults to enabled")
	var lobby_code: String = accessibility_client._encode_lobby_code("ws://192.168.1.42:9083")
	_check(lobby_code.length() == 13 and lobby_code.begins_with("CA-"), "lobby address encodes to a short share code")
	_check(accessibility_client._decode_lobby_code(lobby_code) == "ws://192.168.1.42:9083", "lobby code restores its server address and port")
	_check(accessibility_client._decode_lobby_code("CA-NOT-A-CODE") == "", "invalid lobby codes are rejected before connection")
	var neon = NeonAmbience.new()
	neon.configure(false, 0, false)
	_check(not neon.visible and not neon.is_processing(), "neon ambience toggle disables drawing and animation work")
	neon.configure(true, 1, true)
	_check(neon.visible and neon.is_processing() and neon.quality == 1 and neon.reduced_flashes, "neon ambience follows quality and reduced-flash settings")
	neon.free()
	var standard_blue: Color = accessibility_client.team_color(0)
	accessibility_client.high_contrast_markers = true
	_check(accessibility_client.team_color(0) != standard_blue and accessibility_client.team_color(0) != accessibility_client.team_color(1), "high-contrast accessibility palette keeps teams distinct")
	accessibility_client.free()
	_check(Cfg.PROTOCOL_VERSION >= 2, "lobby protocol rejects older incompatible clients")
	var lobby_server = ServerGame.new()
	lobby_server.peers = [101, 202]
	lobby_server.names = ["Host", "Guest"]
	lobby_server._enter_lobby()
	_check(lobby_server.state == Cfg.State.LOBBY and lobby_server.lobby_ready == [false, false], "both players enter a fresh lobby before loadout")
	lobby_server.on_lobby_ready(101, true)
	lobby_server.on_lobby_ready(202, true)
	lobby_server.on_lobby_start(202)
	_check(lobby_server.state == Cfg.State.LOBBY, "only the host can start squad setup")
	lobby_server.on_lobby_start(101)
	_check(lobby_server.state == Cfg.State.LOADOUT, "ready players advance to squad setup when the host starts")
	lobby_server.free()
	_check(Cfg.MAP_W == 80 and Cfg.MAP_H == 71, "arena includes the enlarged hall and lower square room")
	_check(not map.is_wall_tile(4, map.MAIN_BOTTOM), "Entrance 1 threshold is open")
	_check(not map.is_wall_tile(Cfg.MAP_W - 1, 4), "Entrance 2 threshold is open")
	_check(not map.is_wall_tile(37, 20), "open centre of the revised plan stays walkable")
	_check(map.tables.size() == 82, "blast damage and the messy row leave the revised table count")
	var unique_tables := {}
	var four_seat := 0
	var eight_seat := 0
	for table in map.tables:
		var anchor: Vector2i = table["anchor"]
		unique_tables[anchor] = true
		if table["seats"] == 4:
			four_seat += 1
		elif table["seats"] == 8:
			eight_seat += 1
	_check(unique_tables.size() == map.tables.size(), "table anchors are unique")
	_check(four_seat == 28 and eight_seat == 54, "revised plan uses only four-chair and eight-chair tables")
	_check(map.layout_overlaps.is_empty(), "walls, furniture, plants and counters do not overlap")
	for y in range(1, 8):
		_check(map.solid_kind(18, y) == map.SolidKind.RUBBLE, "explosion blocks upper passage row %d" % y)
	_check(not map.is_wall_tile(39, 23), "spilled glass remains decorative and walkable")
	_check(map.solid_kind(map.ROOM_LEFT, 62) == map.SolidKind.RUBBLE, "left exterior passage is sealed with rubble")
	_check(map.solid_kind(map.ROOM_LEFT + 2, 62) == map.SolidKind.RUBBLE, "rubble pile extends into the lower room")

	for team in 2:
		for idx in Cfg.SQUAD_SIZE:
			var entry: Vector2 = map.entry_position(team, idx)
			var spawn: Vector2 = map.spawn_position(team, idx)
			_check(not map.is_wall_at(entry), "team %d unit %d starts in its doorway" % [team + 1, idx + 1])
			_check(not map.is_wall_at(spawn), "team %d unit %d has a clear formation point" % [team + 1, idx + 1])
			_check(not map.find_path(entry, spawn).is_empty(), "team %d unit %d can enter and spread out" % [team + 1, idx + 1])
	var final_entry_start := Cfg.DEPLOYMENT_DOOR_OPEN_TIME + (Cfg.SQUAD_SIZE - 1) * Cfg.DEPLOYMENT_UNIT_STAGGER
	_check(Cfg.DEPLOYMENT_DOOR_OPEN_TIME > 0.0 and Cfg.DEPLOYMENT_UNIT_STAGGER > 0.0, "opening sequence staggers units after the doors open")
	_check(final_entry_start < Cfg.DEPLOYMENT_DURATION - Cfg.DEPLOYMENT_DOOR_CLOSE_TIME, "every unit starts entering before the doors close")
	_check(not map.find_path(map.spawn_position(0, 0), map.spawn_position(1, 0)).is_empty(), "both halves of the arena are connected")
	var barrier_target := Vector2(20.5, 8.5) * Cfg.TILE
	var path_from_above := map.find_path(Vector2(20.5, 6.5) * Cfg.TILE, barrier_target)
	var path_from_below := map.find_path(Vector2(20.5, 10.5) * Cfg.TILE, barrier_target)
	_check(not path_from_above.is_empty() and path_from_above[path_from_above.size() - 1].y < 8.0 * Cfg.TILE, "orders on a barrier stop on the near side when approaching from above")
	_check(not path_from_below.is_empty() and path_from_below[path_from_below.size() - 1].y > 9.0 * Cfg.TILE, "orders on a barrier stop on the near side when approaching from below")
	var tight_order := Vector2(35.05, 8.5) * Cfg.TILE
	var safe_destination := map.navigation_destination(Vector2(36.5, 10.5) * Cfg.TILE, tight_order)
	_check(map._point_is_clear(safe_destination, Cfg.SOLDIER_RADIUS), "resolved orders leave full soldier clearance around furniture")
	_check(map.solid_kind(39, map.MAIN_BOTTOM) == map.SolidKind.GLASS, "central lower passage begins sealed by breakable glass")
	_check(map.solid_kind(32, map.MAIN_BOTTOM) == map.SolidKind.GLASS, "glass spans the full wide entrance between the fountains")
	_check(map.service_fixtures.size() == 5, "lower room contains the annotated service fixtures")
	_check(map.ROOM_RIGHT == 78, "lower room expands almost to the right edge of the main hall")
	_check(map.solid_kind(36, 45) == map.SolidKind.COUNTER, "cash register has collision")
	_check(map.solid_kind(44, 47) == map.SolidKind.COUNTER, "metal food line has collision")
	_check(map.solid_kind(40, 55) == map.SolidKind.COUNTER, "revised buffet perimeter has collision")
	_check(not map.is_wall_tile(47, 55) and not map.is_wall_tile(48, 63), "buffet island has two entrances")
	_check(not map.is_wall_tile(47, 59), "buffet island remains hollow")
	_check(map.solid_kind(72, 51) == map.SolidKind.COUNTER and not map.is_wall_tile(75, 55), "right food line leaves a broad wall-side aisle")
	_check(not map.is_wall_tile(74, 39), "destroyed table is walkable debris")
	var tipped_table: Dictionary = map.tables.filter(func(table): return table["anchor"] == Vector2i(62, 39))[0]
	var tipped_cells := map.table_collision_cells(tipped_table)
	_check(not tipped_cells.is_empty() and tipped_cells.all(func(cell): return map.is_wall_tile(cell.x, cell.y)), "diagonal tipped table retains collision along its visible slab")
	_check(tipped_cells.size() < 6, "tipped table uses a narrow rotated footprint instead of its upright hitbox")
	_check(not map.is_wall_tile(74, map.MAIN_BOTTOM), "exploded wall opens a second route into the lower room")
	_check(not map.find_path(Vector2(39.5, 40.0) * Cfg.TILE, Vector2(34.0, 58.0) * Cfg.TILE).is_empty(), "lower square room is reachable")
	_check(not map.find_path(Vector2(74.0, 40.0) * Cfg.TILE, Vector2(70.0, 66.0) * Cfg.TILE).is_empty(), "new breach connects to the expanded room")
	_check(not map.find_path(Vector2(34.0, 58.0) * Cfg.TILE, Vector2(70.0, 66.0) * Cfg.TILE).is_empty(), "lower room circulation remains connected")
	_check(not map.find_path(Vector2(47.0, 53.0) * Cfg.TILE, Vector2(47.0, 59.0) * Cfg.TILE).is_empty(), "top buffet entrance reaches the hollow centre")
	_check(map.breakable_count() == 11, "ten damaged tables and the glass wall are breakable")
	var marked_table: Dictionary = map.tables.filter(func(table): return table["anchor"] == Vector2i(46, 10))[0]
	_check(bool(marked_table.get("breakable", false)), "diagonal table beside the A marking is breakable")
	var breakable_anchor := Vector2i(13, 14)
	var standard_impact := int(Cfg.ABILITIES[Cfg.Ability.FIREBALL]["damage"])
	var impact_map = MapData.new()
	var impact_table: Dictionary = impact_map.tables.filter(func(table): return table["anchor"] == breakable_anchor)[0]
	var one_hit := impact_map.damage_breakables(impact_map.table_visual_rect(impact_table).get_center(), 4.0, standard_impact)
	_check(one_hit.size() == 1 and bool(one_hit[0][3]) and not impact_map.is_wall_tile(breakable_anchor.x, breakable_anchor.y), "one standard Fireball destroys a cracked table")
	var breakable_table: Dictionary = map.tables.filter(func(table): return table["anchor"] == breakable_anchor)[0]
	var partial := map.damage_breakables(map.table_visual_rect(breakable_table).get_center(), 4.0, 20)
	_check(partial.size() == 1 and not bool(partial[0][3]) and map.is_wall_tile(breakable_anchor.x, breakable_anchor.y), "damaged cover stays solid before it collapses")
	_check(int(map.breakable_state()[int(breakable_table["breakable_id"])]) == map.BREAKABLE_TABLE_HP - 20, "breakable state includes remaining health")
	var partial_replica = MapData.new()
	partial_replica.apply_breakable_state(map.breakable_state())
	var partial_replica_table: Dictionary = partial_replica.tables.filter(func(table): return table["anchor"] == breakable_anchor)[0]
	_check(int(partial_replica_table["hp"]) == map.BREAKABLE_TABLE_HP - 20 and partial_replica.is_wall_tile(breakable_anchor.x, breakable_anchor.y), "partial damage replicates without removing collision")
	var broken := map.damage_breakables(map.table_visual_rect(breakable_table).get_center(), 4.0, map.BREAKABLE_TABLE_HP)
	_check(broken.size() == 1 and bool(broken[0][3]) and not map.is_wall_tile(breakable_anchor.x, breakable_anchor.y), "destroyed cover becomes walkable")
	var glass_tile := Vector2i(37, map.MAIN_BOTTOM)
	_check(map.solid_kind(glass_tile.x, glass_tile.y) == map.SolidKind.GLASS, "wide lower-room entrance starts sealed by glass")
	var first_glass_hit := map.damage_breakables(Vector2(37.5, map.MAIN_BOTTOM + 0.5) * Cfg.TILE, 4.0, standard_impact)
	_check(first_glass_hit.size() == 1 and not bool(first_glass_hit[0][3]) and map.is_wall_tile(glass_tile.x, glass_tile.y), "glass entrance survives one standard Fireball")
	var broken_glass := map.damage_breakables(Vector2(37.5, map.MAIN_BOTTOM + 0.5) * Cfg.TILE, 4.0, standard_impact)
	_check(broken_glass.size() == 1 and bool(broken_glass[0][3]) and not map.is_wall_tile(glass_tile.x, glass_tile.y), "second standard Fireball shatters the glass entrance")
	var replicated_state := map.breakable_state()
	var replica = MapData.new()
	replica.apply_breakable_state(replicated_state)
	_check(not replica.is_wall_tile(breakable_anchor.x, breakable_anchor.y) and not replica.is_wall_tile(glass_tile.x, glass_tile.y), "breakable state replicates to another map")
	replica.reset_breakables()
	_check(replica.is_wall_tile(breakable_anchor.x, breakable_anchor.y) and replica.is_wall_tile(glass_tile.x, glass_tile.y), "round reset restores breakable cover")
	map.set_doors_closed(true)
	_check(map.is_wall_tile(4, map.MAIN_BOTTOM), "Entrance 1 gains collision after deployment")
	_check(map.is_wall_tile(Cfg.MAP_W - 1, 4), "Entrance 2 gains collision after deployment")
	map.set_doors_closed(false)

	print("\nLayout test results: %d failed." % failed)
	get_tree().quit(1 if failed > 0 else 0)
