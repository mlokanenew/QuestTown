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

	var should_wait_for_hero := false
	for assertion in assertions:
		if assertion.get("assert", "") == "hero_count_gte" or assertion.get("assert", "") == "any_hero_state":
			should_wait_for_hero = true
			break

	if should_wait_for_hero:
		sim.run_until("hero_arrived_at_tavern", max_ticks)
		if max_ticks > 0:
			sim.step_ticks(max_ticks)
	elif max_ticks > 0:
		sim.step_ticks(max_ticks)

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
		"upgrade_building":
			var building_id: int = int(cmd.get("id", -1))
			if building_id < 0:
				var building: Dictionary = sim.get_building_of_type(cmd.get("type", ""))
				building_id = int(building.get("id", -1))
			sim.upgrade_building(building_id)
		"step_ticks":
			sim.step_ticks(cmd.get("n", 1))
		"set_quest_enabled":
			GameState.set_quest_enabled(cmd.get("id", ""), bool(cmd.get("enabled", true)))
		"save_world":
			sim.save_world(cmd.get("path", ""))
		"load_world":
			sim.load_world(cmd.get("path", ""))
		"reset_world":
			sim.reset_world(cmd.get("seed", 0))

func _check(assertion: Dictionary, state: Dictionary) -> bool:
	var kind: String = assertion.get("assert", "")
	match kind:
		"hero_count_gte":
			return state["heroes"].size() >= int(assertion.get("value", 1))
		"hero_count_lte":
			return state["heroes"].size() <= int(assertion.get("value", 1))
		"any_hero_state":
			var target_state: String = assertion.get("value", "")
			for h in state["heroes"]:
				if h["state"] == target_state:
					return true
			return false
		"building_count_gte":
			return state["buildings"].size() >= int(assertion.get("value", 1))
		"quest_count_gte":
			return state.get("quests", []).size() >= int(assertion.get("value", 1))
		"building_exists":
			for b in state["buildings"]:
				if b["type"] == assertion.get("type", ""):
					return true
			return false
		"building_level_eq":
			for b in state["buildings"]:
				if b["type"] == assertion.get("type", ""):
					return int(b.get("level", 1)) == int(assertion.get("value", 1))
			return false
		"gold_eq":
			return int(state.get("gold", -1)) == int(assertion.get("value", -1))
		"gold_gte":
			return int(state.get("gold", -1)) >= int(assertion.get("value", 0))
		"event_type_seen":
			for event in state.get("events", []):
				if event.get("type", "") == assertion.get("value", ""):
					return true
			return false
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
