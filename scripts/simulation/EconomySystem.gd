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
	if state not in ["idling", "recovering"]:
		return

	var cooldown: int = int(hero.get("service_cooldown_ticks", 0))
	if cooldown > 0:
		GameState.heroes[hero_id]["service_cooldown_ticks"] = cooldown - 1
		return

	if bool(hero.get("needs_lodging", false)) and _handle_lodging(hero_id, building_system):
		return
	if int(hero.get("health", 0)) < int(hero.get("max_health", 0)) and _handle_healing(hero_id, building_system):
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
		GameState.heroes[hero_id]["service_cooldown_ticks"] = 30
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
	return _transfer_gold(hero_id, spend, "hero_spent_at_weapons_shop", {
		"building_type": "weapons_shop",
		"service": "gear",
		"gear_id": gear_offer.get("id", "")
	}, func() -> void:
		GameState.consume_building_output_stock(int(shop.get("id", 0)), 1)
		GameState.heroes[hero_id]["gear_bonus"] = gear_bonus
		GameState.heroes[hero_id]["service_cooldown_ticks"] = SERVICE_COOLDOWN_TICKS
	)

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
	return _transfer_gold(hero_id, cost, "hero_spent_at_temple", {
		"building_type": "temple",
		"service": "healing",
		"service_id": service.get("id", "temple_healing")
	}, func() -> void:
		GameState.consume_building_output_stock(int(temple.get("id", 0)), 1)
		var max_health: int = int(GameState.heroes[hero_id].get("max_health", 0))
		GameState.heroes[hero_id]["health"] = max_health
		GameState.heroes[hero_id]["wound_state"] = "healthy"
		if GameState.heroes[hero_id].get("state", "") == "recovering":
			var remaining: int = int(GameState.heroes[hero_id].get("recovery_ticks_remaining", 0))
			GameState.heroes[hero_id]["recovery_ticks_remaining"] = max(0, remaining - recovery_bonus * 120)
		GameState.heroes[hero_id]["service_cooldown_ticks"] = SERVICE_COOLDOWN_TICKS
	)

func _handle_blessing(hero_id: int, building_system: Object) -> bool:
	var temple: Dictionary = building_system.get_building_of_type("temple")
	if temple.is_empty():
		return false
	if _building_effect(building_system, "temple", "healing_service") <= 0:
		return false
	if int(temple.get("output_stock", 0)) <= 0:
		return false
	var service: Dictionary = DataLoader.get_service("temple_blessing")
	var spend: int = max(1, int(service.get("base_cost", 1)) + _building_effect(building_system, "temple", "recovery_bonus") - 1)
	var survival_bonus: int = max(1, _building_effect(building_system, "temple", "survival_bonus") + 1)
	return _transfer_gold(hero_id, spend, "hero_spent_at_temple", {
		"building_type": "temple",
		"service": "blessing",
		"service_id": service.get("id", "temple_blessing")
	}, func() -> void:
		GameState.consume_building_output_stock(int(temple.get("id", 0)), 1)
		GameState.heroes[hero_id]["blessing_bonus"] = survival_bonus
		GameState.heroes[hero_id]["service_cooldown_ticks"] = SERVICE_COOLDOWN_TICKS
	)

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
