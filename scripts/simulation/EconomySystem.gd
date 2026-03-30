extends RefCounted
class_name EconomySystem
## Handles hero spending while they are in town.

const SERVICE_COOLDOWN_TICKS := 90
const MAX_HEROES_BASE := 4
const MAX_HEROES_HARD_CAP := 5

func reset() -> void:
	pass

func step(building_system: Object) -> void:
	for hero_id in GameState.heroes.keys():
		_step_hero(hero_id, building_system)

func max_supported_heroes(building_system: Object) -> int:
	var tavern: Dictionary = building_system.get_building_of_type("tavern")
	if tavern.is_empty():
		return 0
	var support_bonus: int = _building_effect(building_system, "tavern", "adventurer_capacity")
	return min(MAX_HEROES_HARD_CAP, MAX_HEROES_BASE + support_bonus)

func _step_hero(hero_id: int, building_system: Object) -> void:
	var hero: Dictionary = GameState.heroes.get(hero_id, {})
	if hero.is_empty():
		return
	var state: String = hero.get("state", "")
	if state == "using_service":
		_complete_pending_service(hero_id, building_system)
		return
	if state not in ["idling", "recovering"]:
		return

	var cooldown: int = int(hero.get("service_cooldown_ticks", 0))
	if cooldown > 0:
		GameState.heroes[hero_id]["service_cooldown_ticks"] = cooldown - 1
		return

	if int(hero.get("health", 0)) < int(hero.get("max_health", 0)) and _handle_healing(hero_id, building_system):
		return
	if bool(hero.get("needs_lodging", false)) and _handle_lodging(hero_id, building_system):
		return
	if bool(hero.get("needs_meal", false)) and _handle_meal(hero_id, building_system):
		return
	if state == "idling" and int(hero.get("gear_bonus", 0)) <= 0 and _handle_gear_purchase(hero_id, building_system):
		return
	if state == "idling" and int(hero.get("blessing_bonus", 0)) <= 0 and _handle_blessing(hero_id, building_system):
		return

	GameState.heroes[hero_id]["service_cooldown_ticks"] = 60

func _handle_lodging(hero_id: int, building_system: Object) -> bool:
	var tavern: Dictionary = building_system.get_building_of_type("tavern")
	if tavern.is_empty():
		return false
	var service: Dictionary = DataLoader.get_service("tavern_lodging")
	var cost: int = max(
		1,
		int(service.get("base_cost", 1)) + _building_effect(building_system, "tavern", "lodging_income") - 1
	)
	return _transfer_gold(hero_id, cost, "hero_spent_at_tavern", {
		"building_type": "tavern",
		"service": "lodging",
		"service_id": service.get("id", "tavern_lodging")
	}, func() -> void:
		GameState.heroes[hero_id]["needs_lodging"] = false
		GameState.heroes[hero_id]["needs_meal"] = true
		GameState.heroes[hero_id]["service_cooldown_ticks"] = 10
	)

func _handle_meal(hero_id: int, building_system: Object) -> bool:
	var tavern: Dictionary = building_system.get_building_of_type("tavern")
	if tavern.is_empty():
		return false
	var service: Dictionary = DataLoader.get_service("tavern_meal")
	var cost: int = max(
		1,
		int(service.get("base_cost", 1)) + max(0, _building_effect(building_system, "tavern", "lodging_income") - 1)
	)
	return _transfer_gold(hero_id, cost, "hero_spent_at_tavern", {
		"building_type": "tavern",
		"service": "meal",
		"service_id": service.get("id", "tavern_meal")
	}, func() -> void:
		GameState.heroes[hero_id]["needs_meal"] = false
		GameState.heroes[hero_id]["service_cooldown_ticks"] = 10
	)

func _handle_gear_purchase(hero_id: int, building_system: Object) -> bool:
	var shop: Dictionary = building_system.get_building_of_type("weapons_shop")
	if shop.is_empty():
		return false
	if int(shop.get("output_stock", 0)) <= 0:
		return false
	var gear_offer: Dictionary = DataLoader.get_best_gear_offer(int(shop.get("level", 1)))
	var spend: int = max(1, int(gear_offer.get("cost", _building_effect(building_system, "weapons_shop", "gear_spending"))))
	var gear_bonus: int = max(1, int(gear_offer.get("gear_bonus", spend)))
	if int(GameState.heroes[hero_id].get("gold", 0)) < spend:
		return false
	return _send_hero_to_service(hero_id, "weapons_shop", building_system, {
		"service_type": "gear",
		"spend": spend,
		"gear_bonus": gear_bonus,
		"building_id": int(shop.get("id", 0)),
		"gear_id": gear_offer.get("id", ""),
		"return_state": "idling"
	})

func _handle_healing(hero_id: int, building_system: Object) -> bool:
	var temple: Dictionary = building_system.get_building_of_type("temple")
	if temple.is_empty():
		return false
	if _building_effect(building_system, "temple", "healing_service") <= 0:
		return false
	if int(temple.get("output_stock", 0)) <= 0:
		return false
	var recovery_bonus: int = max(1, _building_effect(building_system, "temple", "recovery_bonus"))
	var service: Dictionary = DataLoader.get_service("temple_healing")
	var cost: int = max(1, int(service.get("base_cost", 1)) + recovery_bonus - 1)
	if int(GameState.heroes[hero_id].get("gold", 0)) < cost:
		return false
	return _send_hero_to_service(hero_id, "temple", building_system, {
		"service_type": "healing",
		"spend": cost,
		"recovery_bonus": recovery_bonus,
		"building_id": int(temple.get("id", 0)),
		"service_id": service.get("id", "temple_healing"),
		"return_state": GameState.heroes[hero_id].get("state", "recovering")
	})

func _handle_blessing(hero_id: int, building_system: Object) -> bool:
	var temple: Dictionary = building_system.get_building_of_type("temple")
	if temple.is_empty():
		return false
	if int(temple.get("level", 1)) < 3:
		return false
	if _building_effect(building_system, "temple", "healing_service") <= 0:
		return false
	if int(temple.get("output_stock", 0)) <= 0:
		return false
	var hero: Dictionary = GameState.heroes.get(hero_id, {})
	if hero.is_empty():
		return false
	if bool(hero.get("needs_lodging", false)) or bool(hero.get("needs_meal", false)):
		return false
	if int(hero.get("health", 0)) < int(hero.get("max_health", 0)):
		return false
	var service: Dictionary = DataLoader.get_service("temple_blessing")
	var spend: int = max(1, int(service.get("base_cost", 1)) + _building_effect(building_system, "temple", "recovery_bonus") - 1)
	if int(hero.get("xp", 0)) < 8 or int(hero.get("gold", 0)) < spend + 6:
		return false
	var survival_bonus: int = max(1, _building_effect(building_system, "temple", "survival_bonus") + 1)
	return _send_hero_to_service(hero_id, "temple", building_system, {
		"service_type": "blessing",
		"spend": spend,
		"survival_bonus": survival_bonus,
		"building_id": int(temple.get("id", 0)),
		"service_id": service.get("id", "temple_blessing"),
		"return_state": "idling"
	})

func _send_hero_to_service(hero_id: int, building_type: String, building_system: Object, payload: Dictionary) -> bool:
	var building: Dictionary = building_system.get_building_of_type(building_type)
	if building.is_empty() or not GameState.heroes.has(hero_id):
		return false
	var hero: Dictionary = GameState.heroes[hero_id]
	if hero.get("state", "") not in ["idling", "recovering"]:
		return false
	var position: Dictionary = building.get("position", {})
	var pending: Dictionary = payload.duplicate(true)
	pending["building_type"] = building_type
	GameState.heroes[hero_id]["pending_service"] = pending
	GameState.heroes[hero_id]["pre_service_state"] = hero.get("state", "idling")
	GameState.heroes[hero_id]["target"] = {
		"x": float(position.get("x", 0.0)),
		"y": float(position.get("y", 0.0)),
		"z": float(position.get("z", 0.0))
	}
	GameState.set_hero_state(hero_id, "walking_to_service")
	GameState.log_event("hero_heading_to_service", {
		"hero_id": hero_id,
		"hero_name": hero.get("name", "?"),
		"building_type": building_type,
		"service": payload.get("service_type", "service")
	})
	return true

func _complete_pending_service(hero_id: int, building_system: Object) -> void:
	if not GameState.heroes.has(hero_id):
		return
	var hero: Dictionary = GameState.heroes[hero_id]
	var pending: Dictionary = hero.get("pending_service", {})
	if pending.is_empty():
		GameState.set_hero_state(hero_id, str(hero.get("pre_service_state", "idling")))
		return
	var building_type: String = str(pending.get("building_type", ""))
	var spend: int = int(pending.get("spend", 0))
	var completed: bool = false
	match str(pending.get("service_type", "")):
		"gear":
			completed = _transfer_gold(hero_id, spend, "hero_spent_at_weapons_shop", {
				"building_type": building_type,
				"service": "gear",
				"gear_id": pending.get("gear_id", "")
			}, func() -> void:
				GameState.consume_building_output_stock(int(pending.get("building_id", 0)), 1)
				GameState.heroes[hero_id]["gear_bonus"] = int(pending.get("gear_bonus", 0))
				GameState.heroes[hero_id]["service_cooldown_ticks"] = SERVICE_COOLDOWN_TICKS
			)
		"healing":
			completed = _transfer_gold(hero_id, spend, "hero_spent_at_temple", {
				"building_type": building_type,
				"service": "healing",
				"service_id": pending.get("service_id", "temple_healing")
			}, func() -> void:
				GameState.consume_building_output_stock(int(pending.get("building_id", 0)), 1)
				var max_health: int = int(GameState.heroes[hero_id].get("max_health", 0))
				GameState.heroes[hero_id]["health"] = max_health
				GameState.heroes[hero_id]["wound_state"] = "healthy"
				var remaining: int = int(GameState.heroes[hero_id].get("recovery_ticks_remaining", 0))
				if remaining > 0:
					GameState.heroes[hero_id]["recovery_ticks_remaining"] = max(0, remaining - int(pending.get("recovery_bonus", 1)) * 120)
				GameState.heroes[hero_id]["service_cooldown_ticks"] = SERVICE_COOLDOWN_TICKS
			)
		"blessing":
			completed = _transfer_gold(hero_id, spend, "hero_spent_at_temple", {
				"building_type": building_type,
				"service": "blessing",
				"service_id": pending.get("service_id", "temple_blessing")
			}, func() -> void:
				GameState.consume_building_output_stock(int(pending.get("building_id", 0)), 1)
				GameState.heroes[hero_id]["blessing_bonus"] = int(pending.get("survival_bonus", 0))
				GameState.heroes[hero_id]["service_cooldown_ticks"] = SERVICE_COOLDOWN_TICKS
			)
		_:
			pass
	if completed:
		GameState.log_event("hero_used_service", {
			"hero_id": hero_id,
			"hero_name": hero.get("name", "?"),
			"building_type": building_type,
			"service": pending.get("service_type", "service")
		})
	GameState.heroes[hero_id]["pending_service"] = {}
	GameState.heroes[hero_id].erase("pre_service_state")
	var return_state: String = str(pending.get("return_state", "idling"))
	GameState.set_hero_state(hero_id, return_state)

func _transfer_gold(hero_id: int, amount: int, event_type: String, extra: Dictionary, on_success: Callable) -> bool:
	if not GameState.heroes.has(hero_id):
		return false
	var hero: Dictionary = GameState.heroes[hero_id]
	var hero_gold: int = int(hero.get("gold", 0))
	if hero_gold < amount:
		return false
	GameState.heroes[hero_id]["gold"] = hero_gold - amount
	GameState.add_gold(amount)
	on_success.call()
	var event := {
		"hero_id": hero_id,
		"hero_name": hero.get("name", "?"),
		"amount": amount
	}
	event.merge(extra)
	GameState.log_event(event_type, event)
	return true

func _building_effect(building_system: Object, building_type: String, effect_key: String) -> int:
	var building: Dictionary = building_system.get_building_of_type(building_type)
	if building.is_empty():
		return 0
	var building_data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
	var levels: Array = building_data.get("levels", [])
	var level: int = int(building.get("level", 1))
	if level <= 0 or level > levels.size():
		return 0
	var effects: Dictionary = levels[level - 1].get("effects", {})
	var value: Variant = effects.get(effect_key, 0)
	if value is bool:
		return 1 if value else 0
	return int(value)
