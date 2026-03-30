extends RefCounted
class_name QuestSystem
## Maintains a small pool of available quests and resolves them off-screen.

const MAX_VISIBLE_QUESTS := 4
const BASE_VISIBLE_QUESTS := 2
const LEVEL_UP_XP := 15
const MAX_STORED_RUMOURS := 4

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

	while current.size() < target_count and _consume_tavern_rumour():
		var next_offer: Dictionary = _generate_offer(current, building_system)
		if next_offer.is_empty():
			_restore_tavern_rumour()
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
		"party_size": template.get("party_size", 3),
		"duration_ticks": template["duration_ticks"],
		"gold_reward": template["gold_reward"],
		"xp_reward": template["xp_reward"],
		"risk_level": template["risk_level"],
		"preferred_careers": template.get("preferred_careers", []).duplicate(true),
		"resolution_stat": template.get("resolution_stat", ""),
		"min_tavern_level": template.get("min_tavern_level", 0),
		"min_weapons_shop_level": template.get("min_weapons_shop_level", 0),
		"min_temple_level": template.get("min_temple_level", 0)
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
	var available_heroes: Array = _available_idle_heroes()
	while not updated_quests.is_empty() and available_heroes.size() >= 3:
		var picked: Dictionary = _choose_party_assignment(available_heroes, updated_quests)
		if picked.is_empty():
			break
		var quest_index: int = int(picked.get("quest_index", -1))
		var party_ids: Array = picked.get("party_ids", [])
		if quest_index < 0 or party_ids.is_empty():
			break
		var quest: Dictionary = updated_quests[quest_index]
		updated_quests.remove_at(quest_index)
		changed = true
		var party_size: int = party_ids.size()
		var quest_destination: Vector3 = _pick_quest_destination()
		var party_id: int = int(quest.get("offer_id", _next_offer_id))
		var leader_id: int = int(party_ids[0])
		for hero_id_variant in party_ids:
			var hero_id: int = int(hero_id_variant)
			var hero: Dictionary = GameState.heroes.get(hero_id, {})
			if hero.is_empty():
				continue
			GameState.heroes[hero_id]["current_quest"] = quest.duplicate(true)
			GameState.heroes[hero_id]["quest_party_id"] = party_id
			GameState.heroes[hero_id]["quest_party_size"] = party_size
			GameState.heroes[hero_id]["quest_party_leader_id"] = leader_id
			GameState.heroes[hero_id]["quest_ticks_remaining"] = int(quest.get("duration_ticks", 300))
			GameState.heroes[hero_id]["quest_destination"] = {
				"x": quest_destination.x,
				"y": quest_destination.y,
				"z": quest_destination.z
			}
			GameState.set_hero_state(hero_id, "departing_quest")
			GameState.log_event("hero_departed_for_quest", {
				"hero_id": hero_id,
				"hero_name": hero.get("name", "?"),
				"quest_name": quest.get("name", "?"),
				"party_size": party_size
			})
			GameState.log_event("hero_started_quest", {
				"hero_id": hero_id,
				"hero_name": hero.get("name", "?"),
				"quest_name": quest.get("name", "?"),
				"party_size": party_size
			})
		available_heroes = _available_idle_heroes()

	if changed:
		GameState.set_available_quests(updated_quests)

func _available_idle_heroes() -> Array:
	var hero_ids: Array = []
	for hero_id in GameState.heroes.keys():
		var hero: Dictionary = GameState.heroes[hero_id]
		if hero.get("state", "") != "idling":
			continue
		if int(hero.get("idle_ticks_remaining", 0)) > 120:
			continue
		if not hero.get("current_quest", {}).is_empty():
			continue
		hero_ids.append(int(hero_id))
	return hero_ids

func _choose_party_assignment(available_heroes: Array, quests: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for idx in range(quests.size()):
		var quest: Dictionary = quests[idx]
		var party_size: int = clamp(int(quest.get("party_size", 3)), 3, 5)
		if available_heroes.size() < party_size:
			continue
		var scored_heroes: Array = []
		for hero_id_variant in available_heroes:
			var hero_id: int = int(hero_id_variant)
			var hero: Dictionary = GameState.heroes.get(hero_id, {})
			if hero.is_empty():
				continue
			scored_heroes.append({
				"hero_id": hero_id,
				"score": _hero_quest_score(hero, quest)
			})
		scored_heroes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
		)
		var party_ids: Array = []
		var total_score := 0.0
		for entry in scored_heroes.slice(0, party_size):
			party_ids.append(int(entry.get("hero_id", -1)))
			total_score += float(entry.get("score", 0.0))
		if party_ids.size() < party_size:
			continue
		if total_score > best_score:
			best_score = total_score
			best = {
				"quest_index": idx,
				"party_ids": party_ids
			}
	return best

func _hero_quest_score(hero: Dictionary, quest: Dictionary) -> float:
	var score: float = float(quest.get("gold_reward", 0)) + float(quest.get("xp_reward", 0))
	score -= float(quest.get("difficulty", 1)) * 2.0
	if quest.get("type", "") == hero.get("quest_bias", ""):
		score += 6.0
	var preferred_careers: Array = quest.get("preferred_careers", [])
	if preferred_careers.has(hero.get("career_id", "")):
		score += 7.0
	if hero.get("career_archetype", "") == "martial" and quest.get("type", "") == "combat":
		score += 3.0
	if hero.get("career_archetype", "") == "faith" and quest.get("type", "") == "spiritual":
		score += 3.0
	if hero.get("career_archetype", "") == "scout" and quest.get("type", "") in ["beast", "escort", "forage"]:
		score += 2.0
	if hero.get("career_archetype", "") == "rogue" and quest.get("type", "") in ["combat", "forage"]:
		score += 2.0
	score += _rng.randf_range(0.0, 1.0)
	return score

func _step_active_quests(building_system: Object) -> void:
	for hero_id in GameState.heroes.keys():
		var hero: Dictionary = GameState.heroes[hero_id]
		if hero.get("state", "") != "on_quest":
			continue
		if int(hero.get("quest_party_leader_id", hero_id)) != int(hero_id):
			continue
		GameState.heroes[hero_id]["quest_ticks_remaining"] = int(hero.get("quest_ticks_remaining", 0)) - 1
		if int(GameState.heroes[hero_id]["quest_ticks_remaining"]) <= 0:
			_resolve_quest_party(hero_id, building_system)

func _resolve_quest_party(leader_id: int, building_system: Object) -> void:
	if not GameState.heroes.has(leader_id):
		return
	var leader: Dictionary = GameState.heroes[leader_id]
	var quest: Dictionary = leader.get("current_quest", {})
	if quest.is_empty():
		GameState.set_hero_state(leader_id, "idling")
		return
	var party_id: int = int(leader.get("quest_party_id", -1))
	var party_members: Array = []
	for hero_id in GameState.heroes.keys():
		var candidate: Dictionary = GameState.heroes[hero_id]
		if candidate.get("state", "") not in ["on_quest", "departing_quest", "returning"]:
			continue
		if int(candidate.get("quest_party_id", -2)) == party_id and not candidate.get("current_quest", {}).is_empty():
			party_members.append(int(hero_id))
	if party_members.is_empty():
		party_members.append(leader_id)

	var power: int = 0
	for hero_id_variant in party_members:
		power += _hero_resolution_power(GameState.heroes[int(hero_id_variant)], quest)
	power += max(0, party_members.size() - 1)
	var success_bonus: int = _building_bonus(building_system, "weapons_shop", "quest_success_bonus")
	var survival_bonus: int = _building_bonus(building_system, "temple", "survival_bonus")
	for hero_id_variant in party_members:
		var hero: Dictionary = GameState.heroes[int(hero_id_variant)]
		if quest.get("preferred_careers", []).has(hero.get("career_id", "")):
			success_bonus += 2
		success_bonus += int(hero.get("gear_bonus", 0))
		survival_bonus += int(hero.get("blessing_bonus", 0))
	var roll: int = _rng.randi_range(1, 6)
	var threshold: int = int(quest.get("difficulty", 1)) * 3 * party_members.size()
	threshold += int(quest.get("risk_level", 1)) * 2
	threshold += max(0, party_members.size() - 3)
	var succeeded: bool = power + success_bonus + survival_bonus + roll >= threshold
	var party_gold_gain: int = int(quest.get("gold_reward", 0))
	var party_xp_gain: int = int(quest.get("xp_reward", 0))
	if not succeeded:
		party_gold_gain = int(max(0, party_gold_gain / 3))
		party_xp_gain = int(max(1, party_xp_gain / 2))
	var member_gold_gain: int = max(1, int(round(float(party_gold_gain) / float(max(1, party_members.size())))))
	var member_xp_gain: int = max(1, int(round(float(party_xp_gain) / float(max(1, party_members.size())))))
	var tavern := _tavern_position()
	for hero_id_variant in party_members:
		_resolve_party_member(int(hero_id_variant), quest, tavern, building_system, succeeded, member_gold_gain, member_xp_gain, survival_bonus)

func _resolve_party_member(hero_id: int, quest: Dictionary, tavern: Vector3, building_system: Object, succeeded: bool, gold_gain: int, xp_gain: int, survival_bonus: int) -> void:
	if not GameState.heroes.has(hero_id):
		return
	var hero: Dictionary = GameState.heroes[hero_id]
	if not succeeded:
		var wound_chance: float = clamp(0.45 + 0.12 * float(quest.get("risk_level", 1)) - 0.05 * float(survival_bonus), 0.2, 0.9)
		if _rng.randf() < wound_chance:
			var damage: int = max(1, int(quest.get("risk_level", 1)))
			GameState.heroes[hero_id]["health"] = max(1, int(hero.get("health", 1)) - damage)
			GameState.heroes[hero_id]["wound_state"] = "minor_wounded"
			var recovery_bonus: int = _building_bonus(building_system, "temple", "recovery_bonus")
			GameState.heroes[hero_id]["recovery_ticks_remaining"] = max(120, 300 + int(quest.get("risk_level", 1)) * 90 - recovery_bonus * 60)
			GameState.heroes[hero_id]["post_quest_state"] = "recovering"
			GameState.heroes[hero_id]["return_idle_ticks"] = 0
		else:
			GameState.heroes[hero_id]["wound_state"] = "healthy"
			GameState.heroes[hero_id]["post_quest_state"] = "idling"
			GameState.heroes[hero_id]["return_idle_ticks"] = 180
	else:
		var wound_chance: float = 0.24 * float(quest.get("risk_level", 1))
		wound_chance = max(0.05, wound_chance - 0.04 * float(survival_bonus))
		if _rng.randf() < wound_chance:
			var chip_damage: int = max(1, int(quest.get("risk_level", 1)))
			GameState.heroes[hero_id]["health"] = max(1, int(hero.get("health", 1)) - chip_damage)
			GameState.heroes[hero_id]["wound_state"] = "minor_wounded"
		else:
			GameState.heroes[hero_id]["wound_state"] = "healthy"
		GameState.heroes[hero_id]["post_quest_state"] = "idling"
		GameState.heroes[hero_id]["return_idle_ticks"] = 180

	GameState.heroes[hero_id]["gold"] = int(hero.get("gold", 0)) + gold_gain
	GameState.heroes[hero_id]["xp"] = int(hero.get("xp", 0)) + xp_gain
	GameState.heroes[hero_id]["gear_bonus"] = 0
	GameState.heroes[hero_id]["blessing_bonus"] = 0
	GameState.heroes[hero_id]["quest_status"] = "returning"
	_apply_level_up(hero_id)
	GameState.heroes[hero_id]["target"] = {"x": tavern.x, "y": tavern.y, "z": tavern.z}
	GameState.set_hero_state(hero_id, "returning")
	GameState.record_completed_quest({
		"hero_id": hero_id,
		"hero_name": hero.get("name", "?"),
		"quest_name": quest.get("name", "?"),
		"template_id": quest.get("template_id", ""),
		"success": succeeded,
		"wound_state": GameState.heroes[hero_id].get("wound_state", "healthy"),
		"gold_reward": gold_gain,
		"xp_reward": xp_gain,
		"completed_tick": GameState.tick
	})
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
		"xp_reward": xp_gain,
		"wound_state": GameState.heroes[hero_id].get("wound_state", "healthy"),
		"party_size": int(hero.get("quest_party_size", 1))
	})

func _hero_resolution_power(hero: Dictionary, quest: Dictionary) -> int:
	var power: int = int(hero.get("level", 1))
	var stats: Dictionary = hero.get("stats", {})
	var resolution_stat: String = String(quest.get("resolution_stat", ""))
	match resolution_stat:
		"might":
			power += int(stats.get("might", 0))
		"agility":
			power += int(stats.get("agility", 0))
		"spirit":
			power += int(stats.get("spirit", 0))
		"wits":
			power += int(stats.get("wits", 0)) + 1
		_:
			match quest.get("type", ""):
				"combat":
					power += int(stats.get("might", 0))
				"beast":
					power += int(stats.get("agility", 0))
				"spiritual":
					power += int(stats.get("spirit", 0))
				"escort", "forage":
					power += int(stats.get("wits", 0)) + 1
				_:
					power += int(stats.get("wits", 0))
	return power

func _step_recovery() -> void:
	for hero_id in GameState.heroes.keys():
		var hero: Dictionary = GameState.heroes[hero_id]
		if hero.get("state", "") != "recovering":
			continue
		GameState.heroes[hero_id]["recovery_ticks_remaining"] = int(hero.get("recovery_ticks_remaining", 0)) - 1
		if int(GameState.heroes[hero_id]["recovery_ticks_remaining"]) <= 0:
			GameState.heroes[hero_id]["health"] = int(hero.get("max_health", hero.get("health", 1)))
			GameState.heroes[hero_id]["wound_state"] = "healthy"
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

func _consume_tavern_rumour() -> bool:
	for building_id in GameState.buildings.keys():
		var building: Dictionary = GameState.buildings[building_id]
		if building.get("type", "") == "tavern":
			return GameState.consume_building_output_stock(int(building_id), 1)
	return false

func _restore_tavern_rumour() -> void:
	for building_id in GameState.buildings.keys():
		var building: Dictionary = GameState.buildings[building_id]
		if building.get("type", "") == "tavern":
			GameState.add_building_output_stock(int(building_id), 1, MAX_STORED_RUMOURS + max(0, int(building.get("level", 1)) - 1))
			return

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
	return Vector3(direction * _rng.randf_range(18.0, 24.0), 0.0, -_rng.randf_range(14.0, 22.0))

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
