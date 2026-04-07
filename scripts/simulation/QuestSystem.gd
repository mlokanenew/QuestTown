extends RefCounted
class_name QuestSystem
## Maintains a small pool of available quests and resolves them off-screen.

const DEFAULT_MAX_VISIBLE_QUESTS := 4
const DEFAULT_BASE_VISIBLE_QUESTS := 2
const LEVEL_UP_XP := 15

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_offer_id: int = 1

func reset(seed_value: int) -> void:
	_rng.seed = seed_value + 101
	_next_offer_id = 1
	GameState.set_available_quests([])

func step(building_system: Object) -> void:
	_refresh_available_quests(building_system)
	_step_active_quests(building_system)
	_step_recovery()

func _refresh_available_quests(building_system: Object) -> void:
	_tick_offer_expiry()
	var quest_config: Dictionary = DataLoader.get_quest_config()
	var max_visible: int = int(quest_config.get("max_visible", DEFAULT_MAX_VISIBLE_QUESTS))
	var base_visible: int = int(quest_config.get("base_visible", DEFAULT_BASE_VISIBLE_QUESTS))
	var target_count: int = min(max_visible, base_visible + max(0, _tavern_level() - 1))
	var current: Array = []
	for existing: Dictionary in GameState.quests:
		if not _offer_is_still_valid(existing, building_system):
			continue
		current.append(existing)

	current = _restore_discovered_blocker_offers(current, target_count, building_system)

	while current.size() < target_count and _consume_tavern_rumour():
		var next_offer: Dictionary = _discover_next_blocker_offer(current, building_system)
		if next_offer.is_empty():
			_restore_tavern_rumour()
			break
		current.append(next_offer)

	if current.size() != GameState.quests.size():
		GameState.set_available_quests(current)

func _offer_is_still_valid(existing: Dictionary, building_system: Object) -> bool:
	var blocker_id: String = str(existing.get("blocker_id", ""))
	if blocker_id != "":
		var blocker_state: Dictionary = GameState.blockers.get(blocker_id, {})
		return not blocker_state.is_empty() and str(blocker_state.get("state", "")) == "discovered"
	if not GameState.is_quest_enabled(existing.get("template_id", "")):
		return false
	var template: Dictionary = DataLoader.quests_by_id.get(existing.get("template_id", ""), {})
	return not template.is_empty() and _quest_is_unlocked(template, building_system)

func _restore_discovered_blocker_offers(current: Array, target_count: int, building_system: Object) -> Array:
	var next_current: Array = current.duplicate(true)
	var existing_blocker_ids := {}
	for offer in next_current:
		var blocker_id: String = str(offer.get("blocker_id", ""))
		if blocker_id != "":
			existing_blocker_ids[blocker_id] = true
	for blocker_state in GameState.blockers.values():
		if next_current.size() >= target_count:
			break
		if str(blocker_state.get("state", "")) != "discovered":
			continue
		var blocker_id: String = str(blocker_state.get("blocker_id", ""))
		if existing_blocker_ids.has(blocker_id):
			continue
		if not _blocker_is_unlocked(blocker_state, building_system):
			continue
		var restored_offer: Dictionary = _create_offer_for_blocker(blocker_state)
		if restored_offer.is_empty():
			continue
		next_current.append(restored_offer)
		existing_blocker_ids[blocker_id] = true
	return next_current

func _discover_next_blocker_offer(existing: Array, building_system: Object) -> Dictionary:
	var used_location_ids: Dictionary = {}
	for offer in existing:
		var existing_location_id: String = str(offer.get("location_id", ""))
		if existing_location_id != "":
			used_location_ids[existing_location_id] = true

	var candidates := _discoverable_blockers(building_system)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var score_a := _blocker_priority_score(a)
		var score_b := _blocker_priority_score(b)
		if score_a == score_b:
			return str(a.get("blocker_id", "")) < str(b.get("blocker_id", ""))
		return score_a > score_b
	)
	for blocker in candidates:
		var offer: Dictionary = _create_offer_for_blocker(blocker)
		if offer.is_empty():
			continue
		if used_location_ids.has(str(offer.get("location_id", ""))):
			continue
		GameState.set_blocker_state(str(blocker.get("blocker_id", "")), "discovered", true, false)
		GameState.log_event("blocker_discovered", {
			"blocker_id": blocker.get("blocker_id", ""),
			"quest_name": offer.get("name", ""),
			"location_name": offer.get("location_name", "")
		})
		return offer
	return {}

func _create_offer_for_blocker(blocker: Dictionary) -> Dictionary:
	var location: Dictionary = DataLoader.get_map_location(str(blocker.get("location_id", "")))
	if location.is_empty():
		return {}
	var offer: Dictionary = {
		"offer_id": _next_offer_id,
		"template_id": blocker.get("blocker_id", ""),
		"blocker_id": blocker.get("blocker_id", ""),
		"name": blocker.get("name", "Unknown Threat"),
		"discovered_by": blocker.get("discovered_by", "tavern_rumours"),
		"quest_family": blocker.get("route_family", "town"),
		"required_building": blocker.get("required_building", "tavern"),
		"required_building_level": blocker.get("required_building_level", 1),
		"location_id": location.get("id", ""),
		"location_name": location.get("display_name", "Unknown Site"),
		"location_category": location.get("location_type", ""),
		"location_description": location.get("description", ""),
		"location_icon_key": location.get("icon_type", "road"),
		"flavour_text": blocker.get("flavour_text", ""),
		"type": blocker.get("blocker_type", "threat"),
		"difficulty": blocker.get("difficulty", 1),
		"party_size": blocker.get("party_size", 2),
		"duration_ticks": blocker.get("duration_ticks", 300),
		"gold_reward": blocker.get("gold_reward", 20),
		"xp_reward": blocker.get("xp_reward", 8),
		"risk_level": blocker.get("risk_level", 1),
		"risk_preview": blocker.get("expected_risk", "Risky"),
		"preferred_careers": blocker.get("preferred_careers", []).duplicate(true),
		"resolution_stat": blocker.get("resolution_stat", ""),
		"secondary_resolution_stat": blocker.get("secondary_resolution_stat", ""),
		"secondary_stat_weight": blocker.get("secondary_stat_weight", 0.0),
		"reward_resource_id": blocker.get("unlocks_resource_id", ""),
		"urgent": false,
		"expiry_ticks_remaining": 0
	}
	_next_offer_id += 1
	return offer

func _discoverable_blockers(building_system: Object) -> Array:
	var candidates: Array = []
	for blocker_state in GameState.blockers.values():
		if str(blocker_state.get("state", "")) != "known_blocked":
			continue
		if not _blocker_is_unlocked(blocker_state, building_system):
			continue
		candidates.append(blocker_state.duplicate(true))
	return candidates

func _blocker_priority_score(blocker: Dictionary) -> int:
	var score := 0
	var required_building: String = str(blocker.get("required_building", ""))
	if required_building != "" and GameState.get_building_count(required_building) > 0:
		score += 10
	var resource_id: String = str(blocker.get("unlocks_resource_id", ""))
	if resource_id != "" and not GameState.unlocked_resources.has(resource_id):
		score += 8
	if str(blocker.get("route_family", "")) == "town":
		score += 4
	score += max(0, 5 - int(blocker.get("difficulty", 1)))
	return score

func _blocker_is_unlocked(blocker: Dictionary, building_system: Object) -> bool:
	var required_building: String = str(blocker.get("required_building", ""))
	var required_level: int = int(blocker.get("required_building_level", 1))
	if required_building == "tavern":
		return _tavern_level() >= required_level
	return _building_level(building_system, required_building) >= required_level

func _quest_is_unlocked(quest: Dictionary, building_system: Object) -> bool:
	return (
		_tavern_level() >= int(quest.get("min_tavern_level", 1))
		and _building_level(building_system, "weapons_shop") >= int(quest.get("min_weapons_shop_level", 0))
		and _building_level(building_system, "temple") >= int(quest.get("min_temple_level", 0))
	)

func accept_quest_offer(offer_id: int, building_system: Object, requested_party_ids: Array = []) -> Dictionary:
	var quest_index: int = _find_offer_index(offer_id)
	if quest_index < 0:
		return {}
	var quest: Dictionary = GameState.quests[quest_index]
	var preview: Dictionary = get_acceptance_preview(offer_id, building_system, requested_party_ids)
	var party_ids: Array = preview.get("party_ids", []).duplicate()
	if party_ids.is_empty():
		return {}
	var updated_quests: Array = GameState.quests.duplicate(true)
	updated_quests.remove_at(quest_index)
	GameState.set_available_quests(updated_quests)
	var blocker_id: String = str(quest.get("blocker_id", ""))
	if blocker_id != "":
		GameState.set_blocker_state(blocker_id, "active_quest", true, true)
	GameState.log_event("quest_accepted", {
		"offer_id": offer_id,
		"quest_name": quest.get("name", "?"),
		"party_size": party_ids.size()
	})
	_launch_party_for_quest(quest, party_ids)
	return {
		"offer_id": offer_id,
		"quest_name": quest.get("name", "?"),
		"party_size": party_ids.size(),
		"party_ids": party_ids.duplicate()
	}

func get_acceptance_preview(offer_id: int, building_system: Object, requested_party_ids: Array = []) -> Dictionary:
	var quest_index: int = _find_offer_index(offer_id)
	if quest_index < 0:
		return {
			"can_accept": false,
			"reason": "Quest no longer available",
			"party_ids": [],
			"party_names": [],
			"risk_label": "Dangerous"
		}
	var quest: Dictionary = GameState.quests[quest_index]
	var selection_state: Dictionary = get_party_selection_state(offer_id, building_system, requested_party_ids)
	var party_ids: Array = selection_state.get("party_ids", []).duplicate()
	var party_names: Array = []
	for hero_id_variant in party_ids:
		var hero: Dictionary = GameState.heroes.get(int(hero_id_variant), {})
		if not hero.is_empty():
			party_names.append(str(hero.get("name", "?")))
	if party_ids.is_empty():
		return {
			"can_accept": false,
			"reason": str(selection_state.get("reason", "Need %d ready adventurers" % int(quest.get("party_size", 3)))),
			"party_ids": [],
			"party_names": [],
			"risk_label": str(selection_state.get("risk_label", "Dangerous"))
		}
	return {
		"can_accept": bool(selection_state.get("can_accept", true)),
		"reason": str(selection_state.get("reason", "")),
		"party_ids": party_ids.duplicate(),
		"party_names": party_names,
		"party_size": party_ids.size(),
		"risk_label": str(selection_state.get("risk_label", "Fair"))
	}

func get_party_selection_state(offer_id: int, building_system: Object, selected_ids: Array = []) -> Dictionary:
	var quest_index: int = _find_offer_index(offer_id)
	if quest_index < 0:
		return {
			"can_accept": false,
			"reason": "Quest no longer available",
			"party_ids": [],
			"eligible": [],
			"ineligible": [],
			"risk_label": "Dangerous"
		}
	var quest: Dictionary = GameState.quests[quest_index]
	var normalized_selected_ids: Array = []
	var seen := {}
	for hero_id_variant in selected_ids:
		var hero_id: int = int(hero_id_variant)
		if hero_id <= 0 or seen.has(hero_id):
			continue
		seen[hero_id] = true
		normalized_selected_ids.append(hero_id)
	var eligible: Array = []
	var ineligible: Array = []
	for hero_id in GameState.heroes.keys():
		var hero: Dictionary = GameState.heroes[hero_id]
		var entry := _hero_selection_entry(int(hero_id), hero, quest)
		if bool(entry.get("eligible", false)):
			eligible.append(entry)
		else:
			ineligible.append(entry)
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a.get("score", 0.0)), float(b.get("score", 0.0))):
			return int(a.get("hero_id", 0)) < int(b.get("hero_id", 0))
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	ineligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("hero_id", 0)) < int(b.get("hero_id", 0))
	)
	var party_size: int = clamp(int(quest.get("party_size", 3)), 2, 5)
	var party_ids: Array = []
	var can_accept := false
	var reason := ""
	if normalized_selected_ids.is_empty():
		var available_heroes: Array = []
		for entry in eligible:
			available_heroes.append(int(entry.get("hero_id", -1)))
		party_ids = _choose_party_for_offer(available_heroes, quest)
		can_accept = party_ids.size() >= party_size
		reason = "" if can_accept else "Need %d ready adventurers" % party_size
	else:
		if normalized_selected_ids.size() != party_size:
			reason = "Select exactly %d heroes" % party_size
		else:
			var invalid_reasons: Array = []
			for hero_id in normalized_selected_ids:
				var selected_entry := _find_selection_entry(eligible, ineligible, hero_id)
				if selected_entry.is_empty() or not bool(selected_entry.get("eligible", false)):
					invalid_reasons.append(str(selected_entry.get("reason", "Unavailable")))
				else:
					party_ids.append(hero_id)
			can_accept = invalid_reasons.is_empty() and party_ids.size() == party_size
			reason = "" if can_accept else ", ".join(invalid_reasons)
	var risk_label := _party_risk_label(quest, party_ids, building_system)
	return {
		"can_accept": can_accept,
		"reason": reason,
		"party_ids": party_ids.duplicate(),
		"eligible": eligible,
		"ineligible": ineligible,
		"risk_label": risk_label
	}

func _find_selection_entry(eligible: Array, ineligible: Array, hero_id: int) -> Dictionary:
	for entry in eligible:
		if int(entry.get("hero_id", -1)) == hero_id:
			return entry
	for entry in ineligible:
		if int(entry.get("hero_id", -1)) == hero_id:
			return entry
	return {}

func _hero_selection_entry(hero_id: int, hero: Dictionary, quest: Dictionary) -> Dictionary:
	var reason := ""
	if hero.get("state", "") != "idling":
		reason = "Already away"
	elif not hero.get("current_quest", {}).is_empty():
		reason = "Already away"
	elif str(hero.get("wound_state", "healthy")) != "healthy" or int(hero.get("health", 0)) < int(hero.get("max_health", 0)):
		reason = "Wounded"
	elif int(hero.get("idle_ticks_remaining", 0)) > 120:
		reason = "Fatigued"
	var score := _hero_quest_score(hero, quest) if reason == "" else -999.0
	return {
		"hero_id": hero_id,
		"name": str(hero.get("name", "?")),
		"career_id": str(hero.get("career_id", "")),
		"career": str(hero.get("career_role", hero.get("career", ""))),
		"level": int(hero.get("level", 1)),
		"health": int(hero.get("health", 0)),
		"max_health": int(hero.get("max_health", 0)),
		"eligible": reason == "",
		"reason": reason,
		"score": score
	}

func _party_risk_label(quest: Dictionary, party_ids: Array, building_system: Object) -> String:
	if party_ids.is_empty():
		return "Dangerous"
	var power: float = 0.0
	for hero_id_variant in party_ids:
		var hero: Dictionary = GameState.heroes.get(int(hero_id_variant), {})
		if hero.is_empty():
			continue
		power += float(_hero_resolution_power(hero, quest))
		if quest.get("preferred_careers", []).has(hero.get("career_id", "")):
			power += 2.0
	power += float(_building_bonus(building_system, "weapons_shop", "quest_success_bonus"))
	power += float(_building_bonus(building_system, "temple", "survival_bonus")) * 0.5
	var target: float = float(int(quest.get("difficulty", 1)) * 3 * max(1, party_ids.size()) + int(quest.get("risk_level", 1)) * 2)
	var ratio: float = power / max(1.0, target)
	if ratio >= 1.4:
		return "Strong"
	if ratio >= 1.05:
		return "Fair"
	if ratio >= 0.82:
		return "Risky"
	return "Dangerous"

func _available_idle_heroes(building_system: Object) -> Array:
	var hero_ids: Array = []
	var shop: Dictionary = building_system.get_building_of_type("weapons_shop")
	var shop_has_stock: bool = not shop.is_empty() and int(shop.get("output_stock", 0)) > 0
	var best_gear_offer: Dictionary = DataLoader.get_best_gear_offer(int(shop.get("level", 1))) if not shop.is_empty() else {}
	var required_gear_cost: int = int(best_gear_offer.get("cost", 0))
	for hero_id in GameState.heroes.keys():
		var hero: Dictionary = GameState.heroes[hero_id]
		if hero.get("state", "") != "idling":
			continue
		if str(hero.get("wound_state", "healthy")) != "healthy":
			continue
		if int(hero.get("health", 0)) < int(hero.get("max_health", 0)):
			continue
		if int(hero.get("idle_ticks_remaining", 0)) > 120:
			continue
		if not hero.get("current_quest", {}).is_empty():
			continue
		if shop_has_stock and int(hero.get("gear_bonus", 0)) <= 0 and int(hero.get("gold", 0)) >= required_gear_cost:
			continue
		hero_ids.append(int(hero_id))
	hero_ids.sort()
	return hero_ids

func _choose_party_assignment(available_heroes: Array, quests: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for idx in range(quests.size()):
		var quest: Dictionary = quests[idx]
		var party_size: int = clamp(int(quest.get("party_size", 3)), 2, 5)
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
			var score_a := float(a.get("score", 0.0))
			var score_b := float(b.get("score", 0.0))
			if is_equal_approx(score_a, score_b):
				return int(a.get("hero_id", 0)) < int(b.get("hero_id", 0))
			return score_a > score_b
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

func _choose_party_for_offer(available_heroes: Array, quest: Dictionary) -> Array:
	var party_size: int = clamp(int(quest.get("party_size", 3)), 2, 5)
	if available_heroes.size() < party_size:
		return []
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
		var score_a := float(a.get("score", 0.0))
		var score_b := float(b.get("score", 0.0))
		if is_equal_approx(score_a, score_b):
			return int(a.get("hero_id", 0)) < int(b.get("hero_id", 0))
		return score_a > score_b
	)
	var party_ids: Array = []
	for entry in scored_heroes.slice(0, party_size):
		party_ids.append(int(entry.get("hero_id", -1)))
	return party_ids if party_ids.size() >= party_size else []

func _launch_party_for_quest(quest: Dictionary, party_ids: Array) -> void:
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

func _find_offer_index(offer_id: int) -> int:
	for index in range(GameState.quests.size()):
		if int(GameState.quests[index].get("offer_id", -1)) == offer_id:
			return index
	return -1

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
	var party_names: Array = []
	var any_wounded := false
	for hero_id_variant in party_members:
		var member_result := _resolve_party_member(int(hero_id_variant), quest, tavern, building_system, succeeded, member_gold_gain, member_xp_gain, survival_bonus)
		party_names.append(str(member_result.get("hero_name", "?")))
		any_wounded = any_wounded or bool(member_result.get("wounded", false))
	GameState.record_completed_quest({
		"party_id": party_id,
		"party_names": party_names.duplicate(),
		"hero_name": ", ".join(party_names),
		"quest_name": quest.get("name", "?"),
		"template_id": quest.get("template_id", ""),
		"location_id": quest.get("location_id", ""),
		"location_name": quest.get("location_name", ""),
		"success": succeeded,
		"wound_state": "minor_wounded" if any_wounded else "healthy",
		"gold_reward": party_gold_gain,
		"xp_reward": party_xp_gain,
		"party_size": party_members.size(),
		"completed_tick": GameState.tick
	})
	_resolve_blocker_outcome(quest, succeeded)

func _resolve_party_member(hero_id: int, quest: Dictionary, tavern: Vector3, building_system: Object, succeeded: bool, gold_gain: int, xp_gain: int, survival_bonus: int) -> Dictionary:
	if not GameState.heroes.has(hero_id):
		return {}
	var hero: Dictionary = GameState.heroes[hero_id]
	var wounded := false
	if not succeeded:
		var wound_chance: float = clamp(0.6 + 0.1 * float(quest.get("risk_level", 1)) - 0.05 * float(survival_bonus), 0.3, 0.95)
		if _rng.randf() < wound_chance:
			var damage: int = max(1, int(quest.get("risk_level", 1)))
			GameState.heroes[hero_id]["health"] = max(1, int(hero.get("health", 1)) - damage)
			GameState.heroes[hero_id]["wound_state"] = "minor_wounded"
			wounded = true
			var recovery_bonus: int = _building_bonus(building_system, "temple", "recovery_bonus")
			GameState.heroes[hero_id]["recovery_ticks_remaining"] = max(120, 300 + int(quest.get("risk_level", 1)) * 90 - recovery_bonus * 60)
			GameState.heroes[hero_id]["post_quest_state"] = "recovering"
			GameState.heroes[hero_id]["return_idle_ticks"] = 0
		else:
			GameState.heroes[hero_id]["wound_state"] = "healthy"
			GameState.heroes[hero_id]["post_quest_state"] = "idling"
			GameState.heroes[hero_id]["return_idle_ticks"] = 180
	else:
		var wound_chance: float = 0.22 + 0.12 * float(quest.get("risk_level", 1))
		wound_chance = clamp(wound_chance - 0.03 * float(survival_bonus), 0.18, 0.65)
		if _rng.randf() < wound_chance:
			var chip_damage: int = max(1, int(quest.get("risk_level", 1)))
			GameState.heroes[hero_id]["health"] = max(1, int(hero.get("health", 1)) - chip_damage)
			GameState.heroes[hero_id]["wound_state"] = "minor_wounded"
			wounded = true
		else:
			GameState.heroes[hero_id]["wound_state"] = "healthy"
		GameState.heroes[hero_id]["post_quest_state"] = "idling"
		GameState.heroes[hero_id]["return_idle_ticks"] = 180

	GameState.heroes[hero_id]["gold"] = int(hero.get("gold", 0)) + gold_gain
	GameState.heroes[hero_id]["xp"] = int(hero.get("xp", 0)) + xp_gain
	GameState.heroes[hero_id]["gear_bonus"] = 0
	GameState.heroes[hero_id]["blessing_bonus"] = 0
	GameState.heroes[hero_id]["last_quest_success"] = succeeded
	GameState.heroes[hero_id]["last_quest_completed_tick"] = GameState.tick
	GameState.heroes[hero_id]["quest_status"] = "returning"
	_apply_level_up(hero_id)
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
		"xp_reward": xp_gain,
		"wound_state": GameState.heroes[hero_id].get("wound_state", "healthy"),
		"party_size": int(hero.get("quest_party_size", 1))
	})
	return {
		"hero_id": hero_id,
		"hero_name": hero.get("name", "?"),
		"wounded": wounded
	}

func _hero_resolution_power(hero: Dictionary, quest: Dictionary) -> int:
	var power: int = int(hero.get("level", 1))
	var stats: Dictionary = hero.get("stats", {})
	var resolution_stat: String = str(quest.get("resolution_stat", ""))
	power += _stat_contribution(stats, resolution_stat, str(quest.get("type", "")))
	var secondary_resolution_stat: String = str(quest.get("secondary_resolution_stat", ""))
	if secondary_resolution_stat != "":
		var secondary_power: int = _stat_contribution(stats, secondary_resolution_stat, str(quest.get("type", "")))
		power += int(round(float(secondary_power) * float(quest.get("secondary_stat_weight", 0.0))))
	return power

func _stat_contribution(stats: Dictionary, resolution_stat: String, quest_type: String) -> int:
	match resolution_stat:
		"might":
			return int(stats.get("might", 0))
		"agility":
			return int(stats.get("agility", 0))
		"spirit":
			return int(stats.get("spirit", 0))
		"wits":
			return int(stats.get("wits", 0)) + 1
		_:
			match quest_type:
				"combat":
					return int(stats.get("might", 0))
				"beast":
					return int(stats.get("agility", 0))
				"spiritual":
					return int(stats.get("spirit", 0))
				"escort", "forage", "road", "scouting", "stealth", "urban":
					return int(stats.get("wits", 0)) + 1
				_:
					return int(stats.get("wits", 0))

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
			var building_data: Dictionary = DataLoader.buildings_by_id.get("tavern", {})
			var levels: Array = building_data.get("levels", [])
			var level: int = int(building.get("level", 1))
			if level > 0 and level <= levels.size():
				var output_cap: int = int(levels[level - 1].get("output_cap", 1 + level))
				GameState.add_building_output_stock(int(building_id), 1, output_cap)
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

func _tick_offer_expiry() -> void:
	var quest_config: Dictionary = DataLoader.get_quest_config()
	if not bool(quest_config.get("offers_expire", true)):
		return
	if GameState.quests.is_empty():
		return
	var next_quests: Array = []
	var changed := false
	for offer_variant in GameState.quests:
		var offer: Dictionary = offer_variant
		var expiry: int = int(offer.get("expiry_ticks_remaining", 0))
		if expiry > 0:
			offer["expiry_ticks_remaining"] = expiry - 1
			if int(offer["expiry_ticks_remaining"]) <= 0:
				GameState.log_event("quest_offer_expired", {
					"offer_id": offer.get("offer_id", -1),
					"quest_name": offer.get("name", "?"),
					"urgent": bool(offer.get("urgent", false))
				})
				changed = true
				continue
		next_quests.append(offer)
	if changed:
		GameState.set_available_quests(next_quests)
	else:
		GameState.quests = next_quests

func _roll_expiry_ticks(urgent: bool) -> int:
	var quest_config: Dictionary = DataLoader.get_quest_config()
	if not bool(quest_config.get("offers_expire", true)):
		return 0
	if urgent:
		return _rng.randi_range(
			int(quest_config.get("urgent_expiry_min", 180)),
			int(quest_config.get("urgent_expiry_max", 240))
		)
	return _rng.randi_range(
		int(quest_config.get("default_expiry_min", 300)),
		int(quest_config.get("default_expiry_max", 420))
	)

func _resolve_blocker_outcome(quest: Dictionary, succeeded: bool) -> void:
	var blocker_id: String = str(quest.get("blocker_id", ""))
	if blocker_id == "":
		return
	if succeeded:
		GameState.set_blocker_state(blocker_id, "unblocked", true, false)
		var resource_id: String = str(quest.get("reward_resource_id", ""))
		if resource_id != "":
			GameState.unlock_resource(resource_id, blocker_id)
			var resource_data: Dictionary = DataLoader.get_world_resource(resource_id)
			GameState.log_event("resource_unlocked", {
				"resource_id": resource_id,
				"display_name": resource_data.get("display_name", resource_id),
				"source_blocker_id": blocker_id
			})
	else:
		GameState.set_blocker_state(blocker_id, "discovered", true, false)
