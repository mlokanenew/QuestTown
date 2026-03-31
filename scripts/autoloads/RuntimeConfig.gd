extends Node
## Parses command-line args and exposes runtime configuration.
## Must be registered as an autoload before GameState.
##
## Launch examples:
##   godot --headless -- --mode=headless --port=8765 --seed=42
##   godot --headless -- --mode=test --scenario=res://tests/scenarios/tavern_spawn.json --seed=42

enum Mode { VISUAL, HEADLESS, TEST, SNAPSHOT }

var mode: Mode = Mode.VISUAL
var seed_value: int = 0
var port: int = 8765
var scenario_path: String = ""
var request_load_world: bool = false
var snapshot_targets: Array[String] = []
var snapshot_output_dir: String = "user://ui_snapshots"
var snapshot_load_path: String = ""
var snapshot_resolution: Vector2i = Vector2i(1920, 1080)

func _ready() -> void:
	_parse_args()
	if mode != Mode.VISUAL:
		print("[RuntimeConfig] mode=%s seed=%d port=%d scenario=%s snapshot_targets=%s" % [
			Mode.keys()[mode], seed_value, port, scenario_path, ",".join(snapshot_targets)
		])

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--mode="):
			var m := arg.substr(7).to_lower()
			match m:
				"headless": mode = Mode.HEADLESS
				"test":     mode = Mode.TEST
				"snapshot", "ui_snapshots": mode = Mode.SNAPSHOT
				_:          mode = Mode.VISUAL
		elif arg == "--ui-snapshots":
			mode = Mode.SNAPSHOT
		elif arg.begins_with("--seed="):
			seed_value = arg.substr(7).to_int()
		elif arg.begins_with("--port="):
			port = arg.substr(7).to_int()
		elif arg.begins_with("--scenario="):
			scenario_path = arg.substr(11)
		elif arg.begins_with("--snapshot-targets="):
			var raw_targets := arg.substr(19).split(",", false)
			snapshot_targets.clear()
			for target in raw_targets:
				var cleaned := String(target).strip_edges()
				if cleaned != "":
					snapshot_targets.append(cleaned)
		elif arg.begins_with("--snapshot-dir="):
			snapshot_output_dir = arg.substr(15)
		elif arg.begins_with("--snapshot-load="):
			snapshot_load_path = arg.substr(16)
		elif arg.begins_with("--snapshot-resolution="):
			var parts := arg.substr(22).split("x", false)
			if parts.size() == 2:
				snapshot_resolution = Vector2i(int(parts[0]), int(parts[1]))

	if mode == Mode.SNAPSHOT and snapshot_targets.is_empty():
		snapshot_targets = [
			"town_idle",
			"build_mode",
			"building_selected_tavern",
			"inspector_adventurer",
			"quest_board_open",
			"quest_selected_unavailable",
			"ready_to_launch",
		]

func is_headless() -> bool:
	return mode == Mode.HEADLESS or mode == Mode.TEST

func is_test() -> bool:
	return mode == Mode.TEST

func is_snapshot() -> bool:
	return mode == Mode.SNAPSHOT
