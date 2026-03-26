extends Node
class_name ScenarioRunner
## Runs a scripted test scenario in headless mode.
## Loaded by World when --mode=test is set.
## Prints a JSON result to stdout and exits with code 0 (pass) or 1 (fail).

func run_scenario(sim: Node, scenario_path: String) -> void:
	var data: Variant = _load_scenario(scenario_path)
	if data == null:
		_exit(false, "failed to load scenario: %s" % scenario_path)
		return

	var name: String   = data.get("name", "unnamed")
	var goal: String   = data.get("goal", "")
	var max_ticks: int = data.get("max_ticks", 3600)
	var assertions: Array = data.get("assertions", [])

	print("[ScenarioRunner] running: %s" % name)
	if goal != "":
		print("[ScenarioRunner] goal: %s" % goal)

	# Reset and place tavern (MVP default setup)
	sim.reset_world(data.get("seed", 42))

	# Run commands if present
	var commands: Array = data.get("commands", [])
	for cmd in commands:
		_execute_command(sim, cmd)

	# Run until any assertion might be satisfied
	sim.run_until("hero_arrived_at_tavern", max_ticks)

	# Check assertions
	var state: Variant = sim.get_world_state()
	var passed := true
	var failures := []

	for assertion in assertions:
		var ok := _check(assertion, state)
		if not ok:
			passed = false
			failures.append(assertion)

	var result := {
		"scenario": name,
		"passed":   passed,
		"tick":     state["tick"],
		"heroes":   state["heroes"].size(),
		"buildings": state["buildings"].size(),
		"failures": failures
	}
	print(JSON.stringify(result))
	_exit(passed, "" if passed else "assertions failed")

func _execute_command(sim: Node, cmd: Dictionary) -> void:
	var c: String = cmd.get("cmd", "")
	match c:
		"place_building":
			var pos := Vector3(
				float(cmd.get("x", 0)),
				0.0,
				float(cmd.get("z", 0))
			)
			sim.place_building(cmd.get("type", ""), pos)
		"step_ticks":
			sim.step_ticks(cmd.get("n", 1))
		"reset_world":
			sim.reset_world(cmd.get("seed", 0))

func _check(assertion: Dictionary, state: Dictionary) -> bool:
	var kind: String = assertion.get("assert", "")
	match kind:
		"hero_count_gte":
			return state["heroes"].size() >= int(assertion.get("value", 1))
		"any_hero_state":
			var target_state: String = assertion.get("value", "")
			for h in state["heroes"]:
				if h["state"] == target_state:
					return true
			return false
		"building_count_gte":
			return state["buildings"].size() >= int(assertion.get("value", 1))
	push_warning("ScenarioRunner: unknown assertion type '%s'" % kind)
	return false

func _load_scenario(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	return JSON.parse_string(text)

func _exit(passed: bool, reason: String) -> void:
	if reason != "":
		printerr("[ScenarioRunner] %s" % reason)
	get_tree().quit(0 if passed else 1)
