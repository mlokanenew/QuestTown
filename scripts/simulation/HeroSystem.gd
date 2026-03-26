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
	var target := Vector3(h["target"]["x"], h["target"]["y"], h["target"]["z"])

	match state:
		"arriving":
			# Move toward tavern
			var tavern_pos: Vector3 = building_system.get_tavern_position()
			target = tavern_pos
			_set_target(id, target)
			pos = _move_toward(pos, target, delta)
			_set_position(id, pos)
			if pos.distance_to(target) < 0.5:
				h["idle_ticks_remaining"] = IDLE_TICKS
				GameState.set_hero_state(id, "idling")

		"walking_to_tavern":
			pos = _move_toward(pos, target, delta)
			_set_position(id, pos)
			if pos.distance_to(target) < 0.5:
				h["idle_ticks_remaining"] = IDLE_TICKS
				GameState.set_hero_state(id, "idling")

		"idling":
			h["idle_ticks_remaining"] -= 1
			if h["idle_ticks_remaining"] <= 0:
				# Pick a leave target off the map edge
				var leave_target := Vector3(
					_rng.randf_range(-LEAVE_DISTANCE, LEAVE_DISTANCE),
					0.0,
					-LEAVE_DISTANCE
				)
				_set_target(id, leave_target)
				GameState.set_hero_state(id, "leaving")

		"leaving":
			pos = _move_toward(pos, target, delta)
			_set_position(id, pos)
			if pos.distance_to(target) < 1.0:
				GameState.remove_hero(id)

func spawn_hero() -> Dictionary:
	var name := DataLoader.random_hero_name(_rng)
	var career_data := DataLoader.random_career(_rng)
	var h := GameState.add_hero(name, career_data["name"])
	# Start position: random edge of map
	var spawn_x := _rng.randf_range(-15.0, 15.0)
	var spawn_pos := Vector3(spawn_x, 0.0, 20.0)
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
