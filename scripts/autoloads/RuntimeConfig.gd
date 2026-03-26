extends Node
## Parses command-line args and exposes runtime configuration.
## Must be registered as an autoload before GameState.
##
## Launch examples:
##   godot --headless -- --mode=headless --port=8765 --seed=42
##   godot --headless -- --mode=test --scenario=res://tests/scenarios/tavern_spawn.json --seed=42

enum Mode { VISUAL, HEADLESS, TEST }

var mode: Mode = Mode.VISUAL
var seed_value: int = 0
var port: int = 8765
var scenario_path: String = ""

func _ready() -> void:
	_parse_args()
	if mode != Mode.VISUAL:
		print("[RuntimeConfig] mode=%s seed=%d port=%d scenario=%s" % [
			Mode.keys()[mode], seed_value, port, scenario_path
		])

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--mode="):
			var m := arg.substr(7).to_lower()
			match m:
				"headless": mode = Mode.HEADLESS
				"test":     mode = Mode.TEST
				_:          mode = Mode.VISUAL
		elif arg.begins_with("--seed="):
			seed_value = arg.substr(7).to_int()
		elif arg.begins_with("--port="):
			port = arg.substr(7).to_int()
		elif arg.begins_with("--scenario="):
			scenario_path = arg.substr(11)

func is_headless() -> bool:
	return mode == Mode.HEADLESS or mode == Mode.TEST

func is_test() -> bool:
	return mode == Mode.TEST
