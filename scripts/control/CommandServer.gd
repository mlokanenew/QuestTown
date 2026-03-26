extends Node
class_name CommandServer
## Localhost WebSocket server that exposes the simulation JSON API.
## Started in both headless and visual modes so Python tools can connect.
##
## Protocol: send one JSON object per message, receive one JSON object back.

var _server: WebSocketMultiplayerPeer = null
var _sim: Node = null

func start(port: int) -> void:
	_server = WebSocketMultiplayerPeer.new()
	var err := _server.create_server(port)
	if err != OK:
		push_error("CommandServer: failed to bind port %d (error %d)" % [port, err])
		return
	print("[CommandServer] listening on ws://127.0.0.1:%d" % port)

func set_sim(sim: Node) -> void:
	_sim = sim

func _process(_delta: float) -> void:
	if _server == null:
		return
	_server.poll()
	while _server.get_available_packet_count() > 0:
		var pkt := _server.get_packet()
		var text := pkt.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		if parsed == null or not (parsed is Dictionary):
			_respond({"ok": false, "error": "invalid JSON"})
			continue
		_handle(parsed)

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

		"step_ticks":
			_sim.step_ticks(cmd.get("n", 1))
			_respond({"ok": true, "tick": GameState.tick})

		"get_world_state":
			_respond({"ok": true, "result": _sim.get_world_state()})

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
			# Visual mode: emit signal for UI; no-op in headless
			_respond({"ok": true})

		"set_timescale":
			Engine.time_scale = float(cmd.get("value", 1.0))
			_respond({"ok": true})

		_:
			_respond({"ok": false, "error": "unknown command: %s" % c})

func _respond(data: Dictionary) -> void:
	if _server == null:
		return
	var text := JSON.stringify(data)
	_server.put_packet(text.to_utf8_buffer())
