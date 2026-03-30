extends RefCounted
class_name HeroSystem
## Creates and steps hero entities.
## Hero movement in headless mode is direct position lerp (no NavAgent).
## In visual mode, HeroPresenter uses NavigationAgent3D and reads sim position as target.

const MOVE_SPEED := 3.0       # units per second
const IDLE_TICKS  := 300      # ticks to idle at tavern (~5s at 60Hz)
const LEAVE_DISTANCE := 30.0  # units from map edge to despawn

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func reset(seed_value: int) -> void:
	_rng.seed = seed_value

func step(delta: float, building_system: Object) -> void:
	for id in GameState.heroes.keys():
		_step_hero(id, delta, building_system)

func _step_hero(id: int, delta: float, building_system: Object) -> void:
	var h: Dictionary = GameState.heroes[id]
	var state: String = h["state"]
	var pos := Vector3(h["position"]["x"], h["position"]["y"], h["position"]["z"])
	var target: Vector3 = Vector3(h["target"]["x"], h["target"]["y"], h["target"]["z"])

	match state:
		"arriving":
			# Move toward tavern
			var tavern_pos: Vector3 = building_system.get_tavern_position()
			target = tavern_pos
			_set_target(id, target)
			pos = _move_toward(pos, target, delta)
			_set_position(id, pos)
			if pos.distance_to(target) < 2.5:
				h["idle_ticks_remaining"] = IDLE_TICKS
				h["needs_lodging"] = true
				h["needs_meal"] = true
				h["service_cooldown_ticks"] = 30
				GameState.set_hero_state(id, "idling")

		"walking_to_tavern":
			pos = _move_toward(pos, target, delta)
			_set_position(id, pos)
			if pos.distance_to(target) < 2.5:
				h["idle_ticks_remaining"] = IDLE_TICKS
				h["needs_lodging"] = true
				h["needs_meal"] = true
				h["service_cooldown_ticks"] = 30
				GameState.set_hero_state(id, "idling")

		"walking_to_service":
			pos = _move_toward(pos, target, delta)
			_set_position(id, pos)
			if pos.distance_to(target) < 1.5:
				GameState.set_hero_state(id, "using_service")

		"idling":
			h["idle_ticks_remaining"] -= 1
			if h["idle_ticks_remaining"] <= 0:
				h["idle_ticks_remaining"] = 0

		"departing_quest":
			var quest_target: Vector3 = Vector3(0.0, 0.0, -LEAVE_DISTANCE)
			var quest_destination: Variant = h.get("quest_destination", null)
			if quest_destination is Dictionary:
				quest_target = Vector3(
					quest_destination.get("x", 0.0),
					quest_destination.get("y", 0.0),
					quest_destination.get("z", -LEAVE_DISTANCE)
				)
			elif quest_destination is Vector3:
				quest_target = quest_destination
			_set_target(id, quest_target)
			pos = _move_toward(pos, quest_target, delta)
			_set_position(id, pos)
			if pos.distance_to(quest_target) < 1.0:
				GameState.set_hero_state(id, "on_quest")

		"leaving":
			pos = _move_toward(pos, target, delta)
			_set_position(id, pos)
			if pos.distance_to(target) < 1.0:
				GameState.remove_hero(id)

		"returning":
			pos = _move_toward(pos, target, delta)
			_set_position(id, pos)
			if pos.distance_to(target) < 2.5:
				_finish_return(id)

		"recovering":
			pass

		"on_quest":
			pass

func spawn_hero() -> Dictionary:
	var name := DataLoader.random_hero_name(_rng)
	var career_data := DataLoader.random_career(_rng)
	var h := GameState.add_hero(name, career_data, DataLoader.generate_wfrp_starting_profile(career_data.get("id", ""), _rng))
	# Start position: random edge of map
	var spawn_x := _rng.randf_range(-8.0, 8.0)
	var spawn_pos := Vector3(spawn_x, 0.0, 15.0)
	_set_position(h["id"], spawn_pos)
	return h

func _move_toward(from: Vector3, to: Vector3, delta: float) -> Vector3:
	var dir := (to - from)
	if dir.length() < 0.01:
		return to
	return from + dir.normalized() * min(MOVE_SPEED * delta, dir.length())

func _set_position(id: int, pos: Vector3) -> void:
	if GameState.heroes.has(id):
		GameState.heroes[id]["position"] = {"x": pos.x, "y": pos.y, "z": pos.z}

func _set_target(id: int, target: Vector3) -> void:
	if GameState.heroes.has(id):
		GameState.heroes[id]["target"] = {"x": target.x, "y": target.y, "z": target.z}

func _finish_return(id: int) -> void:
	if not GameState.heroes.has(id):
		return
	var hero: Dictionary = GameState.heroes[id]
	var next_state: String = hero.get("post_quest_state", "idling")
	if next_state == "recovering":
		GameState.heroes[id]["wound_state"] = "minor_wounded"
		GameState.set_hero_state(id, "recovering")
		GameState.log_event("hero_recovering", {
			"hero_id": id,
			"hero_name": hero.get("name", "?")
		})
	else:
		GameState.heroes[id]["idle_ticks_remaining"] = int(hero.get("return_idle_ticks", 180))
		GameState.heroes[id]["needs_lodging"] = true
		GameState.heroes[id]["needs_meal"] = true
		GameState.heroes[id]["service_cooldown_ticks"] = 30
		GameState.heroes[id]["wound_state"] = "minor_wounded" if int(GameState.heroes[id].get("health", 0)) < int(GameState.heroes[id].get("max_health", 0)) else "healthy"
		GameState.set_hero_state(id, "idling")
	GameState.log_event("hero_returned_from_quest", {
		"hero_id": id,
		"hero_name": hero.get("name", "?"),
		"quest_name": hero.get("current_quest", {}).get("name", "?")
	})
	GameState.heroes[id].erase("current_quest")
	GameState.heroes[id].erase("quest_ticks_remaining")
	GameState.heroes[id].erase("quest_destination")
	GameState.heroes[id].erase("quest_status")
	GameState.heroes[id].erase("post_quest_state")
	GameState.heroes[id].erase("return_idle_ticks")
	GameState.heroes[id]["quest_party_id"] = -1
	GameState.heroes[id]["quest_party_size"] = 0
	GameState.heroes[id]["quest_party_leader_id"] = -1
