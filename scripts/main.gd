extends Node
## Entry point. Starts the dedicated server when run headless / with --server,
## otherwise starts the (web) client.
##
##   Server:  godot --headless --path . -- --server [--port=9080] [--cert=fullchain.pem --key=privkey.pem]

const Cfg = preload("res://scripts/config.gd")
const MapData = preload("res://scripts/map_data.gd")


func _ready() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var opts := {}
	for a in args:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else ""
	var is_server: bool = (opts.has("server") and opts["server"] == "") or OS.has_feature("dedicated_server") \
		or (DisplayServer.get_name() == "headless" and not opts.has("client"))
	if is_server:
		var port := int(opts.get("port", str(Cfg.DEFAULT_PORT)))
		var map_id := str(opts.get("map", "dining_hall"))
		if not map_id in MapData.MAP_IDS:
			push_error("Unknown map: %s. Choose dining_hall or hg_e." % map_id)
			get_tree().quit(2)
			return
		var server: Node = load("res://scripts/server/server_game.gd").new()
		if map_id != "dining_hall":
			server.map = MapData.new(map_id)
		server.name = "Server"
		add_child(server)
		server.start(port, opts.get("cert", ""), opts.get("key", ""))
	else:
		var client: Node = load("res://scripts/client/client_game.gd").new()
		client.name = "Client"
		add_child(client)
