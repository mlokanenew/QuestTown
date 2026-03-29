extends RefCounted
class_name QuestSystem
## Maintains a small pool of available quests and resolves them off-screen.

const MAX_VISIBLE_QUESTS := 4
const BASE_VISIBLE_QUESTS := 2
const LEVEL_UP_XP := 20

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_offer_id: int = 1

func reset(seed_value: int) -> void:
	_rng.seed = seed_value + 101
	_next_offer_id = 1
	GameState.set_available_quests([])

func step(building_system: Object) -> void:
	_refresh_available_quests(building_system)
	_assign_quests()
	_step_active_quests(building_system)
	_step_recovery()

func _refresh_available_quests(building_system: Object) -> void:
	var target_count: int = min(MAX_VISIBLE_QUESTS, BASE_VISIBLE_QUESTS + max(0, _tavern_level() - 1))
	var current: Array = []
	for existing: Dictionary in GameState.quests:
		if not GameState.is_quest_enabled(existing.get("template_id", "")):
			continue
		if not _quest_is_unlocked(DataLoader.quests_by_id.get(existing.get("template_id", ""), {}), building_system):
			continue
		current.append(existing)

	while current.size() < target_count:
		var next_offer: Dictionary = _generate_offer(current, building_system)
		if next_offer.is_empty():
			break
		current.append(next_offer)

	if current.size() != GameState.quests.size():
		GameState.set_available_quests(current)

func _generate_offer(existing: Array, building_system: Object) -> Dictionary:
	var blocked_ids: Dictionary = {}
	for offer in existing:
		blocked_ids[offer.get("template_id", "")] = true

	var candidates: Array = []
	for quest: Dictionary in DataLoader.quests:
		if not GameState.is_quest_enabled(quest.get("id", "")):
			continue
		if blocked_ids.has(quest.get("id", "")):
			continue
		if not _quest_is_unlocked(quest, building_system):
			continue
		candidates.append(quest)

	if candidates.is_empty():
		return {}

	var template: Dictionary = candidates[_rng.randi() % candidates.size()]
	var offer: Dictionary = {
		"offer_id": _next_offer_id,
		"template_id": template["id"],
		"name": template["name"],
		"type": template["type"],
		"difficulty": template["difficulty"],
		"duration_ticks": template["duration_ticks"],
		"gold_reward": template["gold_reward"],
		"xp_reward": template["xp_reward"],
		"risk_level": template["risk_level"]
	}
	_next_offer_id += 1
	return offer

func _quest_is_unlocked(quest: Dictionary, building_system: Object) -> bool:
	return (
		_tavern_level() >= int(quest.get("min_tavern_level", 1))
		and _building_level(building_system, "weapons_shop") >= int(quest.get("min_weapons_shop_level", 0))
		and _building_level(building_system, "temple") >= int(quest.get("min_temple_level", 0))
	)

func _assign_quests() -> void:
	if GameState.quests.is_empty():
		return

	var updated_quests: Array = GameState.quests.duplicate(true)
	var changed: bool = false
	for hero_id in GameState.heroes.keys():
		var hero: Dictionary = GameState.heroes[hero_id]
		if hero.get("state", "") != "idling":
			continue
		if updated_quests.is_empty():
			break
		if int(hero.get("idle_ticks_remaining", 0)) > 120:
			continue

		var picked_index: int = _choose_quest_index(hero, updated_quests)
		var quest: Dictionary = updated_quests[picked_index]
		updated_quests.remove_at(picked_index)
		changed = true

		GameState.heroes[hero_id]["current_quest"] = quest
		GameState.heroes[hero_id]["quest_ticks_remaining"] = int(quest.get("duration_ticks", 300))
		var quest_destination: Vector3 = _pick_quest_destination()
		GameState.heroes[hero_id]["quest_destination"] = {
			"x": quest_destination.x,
			"y": quest_destination.y,
			"z": quest_destination.z
		}
		GameState.set_hero_state(hero_id, "departing_quest")
		GameState.log_event("hero_departed_for_quest", {
			"hero_id": hero_id,
			"hero_name": hero.get("name", "?"),
			"quest_name": quest.get("name", "?")
		})
		GameState.log_event("hero_started_quest", {
			"hero_id": hero_id,
			"hero_name": hero.get("name", "?"),
			"quest_name": quest.get("name", "?")
		})

	if changed:
		GameState.set_available_quests(updated_quests)

func _choose_quest_index(hero: Dictionary, quests: Array) -> int:
	var best_index := 0
	var best_score := -INF
	for idx in range(quests.size()):
		var quest: Dictionary = quests[idx]
		var score: float = float(quest.get("gold_reward", 0)) + float(quest.get("xp_reward", 0))
		score -= float(quest.get("difficulty", 1)) * 2.0
		if quest.get("type", "") == hero.get("quest_bias", ""):
			score += 6.0
		if hero.get("career_archetype", "") == "martial" and quest.get("type", "") == "combat":
			score += 3.0
		if hero.get("career_archetype", "") == "faith" and quest.get("type", "") == "spiritual":
			score += 3.0
		if hero.get("career_archetype", "") == "scout" and quest.get("type", "") in ["beast", "escort"]:
			score += 2.0
		score += _rng.randf_range(0.0, 1.0)
		if score > best_score:
			best_score = score
			best_index = idx
	return best_index

func _step_active_quests(building_system: Object) -> void:
	for hero_id in GameState.heroes.keys():
		var hero: Dictionary = GameState.heroes[hero_id]
		if hero.get("state", "") != "on_quest":
			continue
		GameState.heroes[hero_id]["quest_ticks_remaining"] = int(hero.get("quest_ticks_remaining", 0)) - 1
		if int(GameState.heroes[hero_id]["quest_ticks_remaining"]) <= 0:
			_resolve_quest(hero_id, building_system)

func _resolve_quest(hero_id: int, building_system: Object) -> void:
	if not GameState.heroes.has(hero_id):
		return
	var hero: Dictionary = GameState.heroes[hero_id]
	var quest: Dictionary = hero.get("current_quest", {})
	if quest.is_empty():
		GameState.set_hero_state(hero_id, "idling")
		return

	var power: int = int(hero.get("level", 1))
	var stats: Dictionary = hero.get("stats", {})
	match quest.get("type", ""):
		"combat":
			power += int(stats.get("might", 0))
		"beast":
			power += int(stats.get("agility", 0))
		"spiritual":
			power += int(stats.get("spirit", 0))
		"escort":
			power += int(stats.get("wits", 0)) + 1
		_:
			power += int(stats.get("wits", 0))

	var success_bonus: int = _building_bonus(building_system, "weapons_shop", "quest_success_bonus")
	var survival_bonus: int = _building_bonus(building_system, "temple", "survival_bonus")
	success_bonus += int(hero.get("gear_bonus", 0))
	survival_bonus += int(hero.get("blessing_bonus", 0))
	var roll: int = _rng.randi_range(1, 6)
	var threshold: int = int(quest.get("difficulty", 1)) * 6 + int(quest.get("risk_level", 1))
	var succeeded: bool = power + success_bonus + survival_bonus + roll >= threshold

	var gold_gain: int = int(quest.get("gold_reward", 0))
	var xp_gain: int = int(quest.get("xp_reward", 0))
	if not succeeded:
		gold_gain = int(max(0, gold_gain / 3))
		xp_gain = int(max(1, xp_gain / 2))
		var damage: int = int(quest.get("risk_level", 1)) + max(0, 2 - survival_bonus)
		GameState.heroes[hero_id]["health"] = max(1, int(hero.get("health", 1)) - damage)
		var recovery_bonus: int = _building_bonus(building_system, "temple", "recovery_bonus")
		GameState.heroes[hero_id]["recovery_ticks_remaining"] = max(120, 360 + int(quest.get("risk_level", 1)) * 120 - recovery_bonus * 60)
		GameState.heroes[hero_id]["post_quest_state"] = "recovering"
		GameState.heroes[hero_id]["return_idle_ticks"] = 0
	else:
		GameState.heroes[hero_id]["post_quest_state"] = "idling"
		GameState.heroes[hero_id]["return_idle_ticks"] = 180

	GameState.heroes[hero_id]["gold"] = int(hero.get("gold", 0)) + gold_gain
	GameState.heroes[hero_id]["xp"] = int(hero.get("xp", 0)) + xp_gain
	GameState.heroes[hero_id]["gear_bonus"] = 0
	GameState.heroes[hero_id]["blessing_bonus"] = 0
	GameState.heroes[hero_id]["quest_status"] = "returning"
	_apply_level_up(hero_id)
	var tavern := _tavern_position()
	GameState.heroes[hero_id]["target"] = {"x": tavern.x, "y": tavern.y, "z": tavern.z}
	GameState.set_hero_state(hero_id, "returning")
	GameState.log_event("hero_heading_home", {
		"hero_id": hero_id,
		"hero_name": hero.get("name", "?"),
		"quest_name": quest.get("name", "?")
	})
	GameState.log_event("hero_completed_quest", {
		"hero_id": hero_id,
		"hero_name": hero.get("name", "?"),
		"quest_name": quest.get("name", "?"),
		"success": succeeded,
		"gold_reward": gold_gain,
		"xp_reward": xp_gain
	})

func _step_recovery() -> void:
	for hero_id in GameState.heroes.keys():
		var hero: Dictionary = GameState.heroes[hero_id]
		if hero.get("state", "") != "recovering":
			continue
		GameState.heroes[hero_id]["recovery_ticks_remaining"] = int(hero.get("recovery_ticks_remaining", 0)) - 1
		if int(GameState.heroes[hero_id]["recovery_ticks_remaining"]) <= 0:
			GameState.heroes[hero_id]["health"] = int(hero.get("max_health", hero.get("health", 1)))
			GameState.heroes[hero_id]["idle_ticks_remaining"] = 180
			GameState.heroes[hero_id].erase("recovery_ticks_remaining")
			GameState.set_hero_state(hero_id, "idling")
			GameState.log_event("hero_ready_again", {
				"hero_id": hero_id,
				"hero_name": hero.get("name", "?")
			})

func _apply_level_up(hero_id: int) -> void:
	if not GameState.heroes.has(hero_id):
		return
	var hero: Dictionary = GameState.heroes[hero_id]
	var next_level: int = int(hero.get("level", 1))
	while int(hero.get("xp", 0)) >= next_level * LEVEL_UP_XP:
		next_level += 1
	if next_level > int(hero.get("level", 1)):
		GameState.heroes[hero_id]["level"] = next_level
		GameState.heroes[hero_id]["max_health"] = int(hero.get("max_health", 10)) + (next_level - int(hero.get("level", 1)))
		GameState.heroes[hero_id]["health"] = int(GameState.heroes[hero_id]["max_health"])
		GameState.log_event("hero_leveled_up", {
			"hero_id": hero_id,
			"hero_name": hero.get("name", "?"),
			"level": next_level
		})

func _tavern_level() -> int:
	for building in GameState.buildings.values():
		if building.get("type", "") == "tavern":
			return int(building.get("level", 1))
	return 0

func _building_level(building_system: Object, building_type: String) -> int:
	var building: Dictionary = building_system.get_building_of_type(building_type)
	if building.is_empty():
		return 0
	return int(building.get("level", 1))

func _building_bonus(building_system: Object, building_type: String, effect_key: String) -> int:
	var building: Dictionary = building_system.get_building_of_type(building_type)
	if building.is_empty():
		return 0
	var building_data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
	var levels: Array = building_data.get("levels", [])
	var level: int = int(building.get("level", 1))
	if level <= 0 or level > levels.size():
		return 0
	var effects: Dictionary = levels[level - 1].get("effects", {})
	return int(effects.get(effect_key, 0))

func _pick_quest_destination() -> Vector3:
	var direction := -1.0 if _rng.randf() < 0.5 else 1.0
	return Vector3(direction * _rng.randf_range(22.0, 30.0), 0.0, -_rng.randf_range(18.0, 28.0))

func _tavern_position() -> Vector3:
	for building in GameState.buildings.values():
		if building.get("type", "") == "tavern":
			var p: Dictionary = building.get("position", {})
			return Vector3(p.get("x", 0.0), p.get("y", 0.0), p.get("z", 0.0))
	return Vector3.ZERO

func export_state() -> Dictionary:
	return {"next_offer_id": _next_offer_id}

func import_state(data: Dictionary) -> void:
	_next_offer_id = int(data.get("next_offer_id", 1))
