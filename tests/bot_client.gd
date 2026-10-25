extends SceneTree
## Headless bot used for automated testing of the server.
##   godot --headless --path . --script res://tests/bot_client.gd -- --url=ws://127.0.0.1:9080 --name=BotA --duration=40
## Moves its squad toward the map centre, uses abilities, and logs what it sees.

const Cfg = preload("res://scripts/config.gd")

var net
var slot := -1
var t := 0.0
var duration := 40.0
var last_state := -1
var stats := {"snaps": 0, "shots": 0, "kills": 0, "max_enemies_seen": 0, "incoming": 0, "abilities": 0, "denies": 0, "scanned": 0}
var phase := 0
var url := "ws://127.0.0.1:9080"
var bot_name := "Bot"
var loadout_sent := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--url="): url = a.substr(6)
		if a.begins_with("--name="): bot_name = a.substr(7)
		if a.begins_with("--duration="): duration = float(a.substr(11))
	net = root.get_node("Net")
	net.welcomed.connect(func(s, protocol): slot = s; print("[%s] welcomed as slot %d (protocol %d)" % [bot_name, s, protocol]))
	net.connection_ok.connect(func(): net.c_hello.rpc_id(1, bot_name, Cfg.PROTOCOL_VERSION))
	net.connection_lost.connect(func(r): print("[%s] lost: %s" % [bot_name, r]))
	net.rejected.connect(func(r): print("[%s] rejected: %s" % [bot_name, r]))
	net.snapshot_received.connect(_on_snap)


func _on_snap(d: Dictionary) -> void:
	stats["snaps"] += 1
	if d["st"] == Cfg.State.LOADOUT and not loadout_sent:
		loadout_sent = true
		net.c_loadout.rpc_id(1, Cfg.DEFAULT_LOADOUTS.duplicate())
	if d["st"] != last_state:
		print("[%s] state -> %d" % [bot_name, d["st"]])
		last_state = d["st"]
		if d["st"] == Cfg.State.ENDED:
			print("[%s] winner=%d (me=%d) stats=%s" % [bot_name, d["win"], slot, stats])
	stats["max_enemies_seen"] = maxi(stats["max_enemies_seen"], d["en"].size())
	stats["scanned"] = maxi(stats["scanned"], d["sc"].size())
	for ev in d["ev"]:
		match ev[0]:
			"shot": stats["shots"] += 1
			"kill":
				stats["kills"] += 1
				print("[%s] kill event: team %d soldier %d" % [bot_name, ev[1], ev[2]])
			"incoming": stats["incoming"] += 1
			"ability": stats["abilities"] += 1
			"deny": stats["denies"] += 1
			"msg": print("[%s] msg: %s" % [bot_name, ev[1]])
	if d["st"] != Cfg.State.PLAYING:
		return
	# Simple behaviour: every 2 s, move the next soldier toward the centre.
	var step := int(t / 2.0)
	if step != phase:
		phase = step
		var idx := phase % 3
		net.c_select.rpc_id(1, idx)
		var center := Cfg.WORLD_SIZE * 0.5 + Vector2(randf_range(-120, 120), randf_range(-150, 150))
		net.c_move.rpc_id(1, center, false)
		if phase % 4 == 1:
			net.c_ability.rpc_id(1, phase % 4 + (phase / 4) % 4, center, phase % 2 == 0)
		if phase == 3:
			net.c_ability.rpc_id(1, Cfg.Ability.SCAN, center, true)
			net.c_ability.rpc_id(1, Cfg.Ability.SCAN, center, true)  # must be denied (cooldown)


func _process(delta: float) -> bool:
	if t == 0.0:
		net.join(url)
	t += delta
	if t > duration:
		print("[%s] done. stats=%s" % [bot_name, stats])
		return true
	return false
