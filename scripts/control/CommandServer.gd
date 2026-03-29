extends Node
class_name CommandServer
## Outbound TCP client — connects to the Python driver's server.
## Newline-delimited JSON protocol.
## Python starts first and listens; Godot connects on startup.

var _client: StreamPeerTCP = null
var _sim: Node = null
var _buf: String = ""   # accumulate partial lines

func start(port: int) -> void:
	_client = StreamPeerTCP.new()
	var err := _client.connect_to_host("127.0.0.1", port)
	if err != OK:
		push_error("CommandServer: connect_to_host failed (err %d)" % err)
		_client = null
		return
	print("[CMD] connecting to tcp://127.0.0.1:%d" % port)

func set_sim(sim: Node) -> void:
	_sim = sim

func _ready() -> void:
	print("[CMD] CommandServer _ready")

func _physics_process(_delta: float) -> void:
	if _client == null:
		return
	_client.poll()
	var status := _client.get_status()
	if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		return
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return  # still completing handshake

	var avail := _client.get_available_bytes()
	while avail > 0:
		# Read byte-by-byte to find newline boundary reliably
		var chunk: String = _client.get_string(avail)
		_buf += chunk
		avail = 0
		# Process all complete lines in buffer
		while "\n" in _buf:
			var nl := _buf.find("\n")
			var line := _buf.left(nl).strip_edges()
			_buf = _buf.substr(nl + 1)
			if line != "":
				print("[CMD] rx: %s" % line.left(120))
				var parsed: Variant = JSON.parse_string(line)
				if parsed == null or not (parsed is Dictionary):
					_respond({"ok": false, "error": "invalid JSON"})
				else:
					_handle(parsed)

func _respond(data: Dictionary) -> void:
	if _client == null:
		return
	var line := JSON.stringify(data) + "\n"
	_client.put_data(line.to_utf8_buffer())

func _handle(cmd: Dictionary) -> void:
	if _sim == null:
		_respond({"ok": false, "error": "simulation not ready"})
		return

	var c: String = cmd.get("cmd", "")
	match c:
		"reset_world":
			_sim.reset_world(cmd.get("seed", 0))
			_respond({"ok": true})

		"place_building":
			var pos := Vector3(
				float(cmd.get("x", 0)),
				0.0,
				float(cmd.get("z", 0))
			)
			var result: Variant = _sim.place_building(cmd.get("type", ""), pos)
			if result.is_empty():
				_respond({"ok": false, "error": "placement blocked or unknown type"})
			else:
				_respond({"ok": true, "result": result})

		"upgrade_building":
			var building_id: int = int(cmd.get("id", -1))
			if building_id < 0 and cmd.has("type"):
				var building: Dictionary = _sim.get_building_of_type(cmd.get("type", ""))
				building_id = int(building.get("id", -1))
			var upgrade_result: Variant = _sim.upgrade_building(building_id)
			if upgrade_result.is_empty():
				_respond({"ok": false, "error": "upgrade failed"})
			else:
				_respond({"ok": true, "result": upgrade_result})

		"step_ticks":
			_sim.step_ticks(cmd.get("n", 1))
			_respond({"ok": true, "tick": GameState.tick})

		"get_world_state":
			_respond({"ok": true, "result": _sim.get_world_state()})

		"set_quest_enabled":
			GameState.set_quest_enabled(cmd.get("id", ""), bool(cmd.get("enabled", true)))
			_respond({"ok": true})

		"save_world":
			_respond({"ok": _sim.save_world(cmd.get("path", ""))})

		"load_world":
			_respond({"ok": _sim.load_world(cmd.get("path", ""))})

		"get_heroes":
			_respond({"ok": true, "result": _sim.get_heroes()})

		"get_buildings":
			_respond({"ok": true, "result": _sim.get_buildings()})

		"run_until":
			var reached: Variant = _sim.run_until(
				cmd.get("event", ""),
				cmd.get("max_ticks", 3600)
			)
			_respond({"ok": true, "reached": reached, "tick": GameState.tick})

		"select_entity":
			_respond({"ok": true})

		"set_timescale":
			Engine.time_scale = float(cmd.get("value", 1.0))
			_respond({"ok": true})

		_:
			_respond({"ok": false, "error": "unknown command: %s" % c})
