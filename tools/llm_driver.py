#!/usr/bin/env python3
"""
QuestTown LLM Driver
====================
Starts a TCP server, launches Godot headless (which connects back),
and uses a local Ollama LLM to drive the simulation toward a scenario goal.

Architecture: Python LISTENS, Godot CONNECTS.
This avoids Godot's is_connection_available() WSAPoll bug on Windows.

Requirements:
  pip install requests
  ollama serve

Usage:
  python tools/llm_driver.py --scenario tests/scenarios/tavern_spawn.json
  python tools/llm_driver.py --scenario tests/scenarios/tavern_spawn.json --model phi3:mini
  python tools/llm_driver.py --scenario tests/scenarios/tavern_spawn.json --no-llm
"""

import argparse
import asyncio
import json
import socket
import subprocess
import sys
from pathlib import Path

import requests

GODOT_EXE = r"C:\Users\mloka\Downloads\godot_extracted\Godot_v4.6.1-stable_win64_console.exe"
PROJECT_DIR = str(Path(__file__).parent.parent)
OLLAMA_URL = "http://localhost:11434/api/chat"
OPENAI_COMPAT_URL = "http://127.0.0.1:8080/v1/chat/completions"
DEFAULT_MODEL = "phi3:mini"
CONNECT_TIMEOUT = 30
MAX_LLM_TURNS = 24
OLLAMA_TIMEOUT = 12
STARTING_GOLD = 70
RUN_UNTIL_EVENTS = {
    "hero_arrived_at_tavern",
    "hero_departed_for_quest",
    "hero_completed_quest",
    "hero_heading_home",
    "hero_returned_from_quest",
    "hero_spent_at_tavern",
    "hero_spent_at_weapons_shop",
    "hero_spent_at_temple",
    "quest_phase_changed",
    "quest_progress_event",
    "resource_unlocked",
    "resource_installed",
}

SYSTEM_PROMPT = """You control a medieval town-builder game test harness.

Return exactly ONE JSON object and nothing else.

Allowed commands:
{"cmd":"place_building","type":"tavern","x":0,"z":0}
{"cmd":"place_building","type":"weapons_shop","x":3,"z":0}
{"cmd":"place_building","type":"temple","x":-3,"z":0}
{"cmd":"upgrade_building","type":"tavern"}
{"cmd":"upgrade_building","type":"weapons_shop"}
{"cmd":"upgrade_building","type":"temple"}
{"cmd":"start_building_upgrade","type":"tavern"}
{"cmd":"set_building_output_mode","type":"tavern"}
{"cmd":"accept_quest","offer_id":1}
{"cmd":"accept_quest","offer_id":1,"hero_ids":[1,3]}
{"cmd":"install_building_resource","type":"tavern","resource_id":"southmere_travellers"}
{"cmd":"set_quest_enabled","id":"clear_rats_cellar","enabled":true}
{"cmd":"step_ticks","n":600}
{"cmd":"run_until","event":"hero_arrived_at_tavern","max_ticks":1800}
{"cmd":"get_world_state"}

Rules:
1. Never place a building if one of that type already exists.
2. New buildings start idle. If a building needs to generate quests, supplies, or healing, explicitly use set_building_output_mode.
3. Tavern rumours reveal blocker quests. After a quest succeeds it may unlock a route resource that should be installed into the matching building.
4. Quests do not launch automatically. If a quest is available and you want heroes to go, use accept_quest.
5. Prefer run_until or step_ticks once the needed building is placed and any required output mode is active.
6. If the world is already close to satisfying the goal, advance time instead of placing more buildings.
7. Output JSON only."""

ANALYSIS_PROMPT = """You are reviewing a fantasy town-sim MVP test run.

Judge whether the loop hangs together across blocker discovery, route clearing, resource unlocks, installs, economy, injuries, quest outcomes, and progression.
Be concrete. Call out if the game looks too easy, too hard, too rich, too poor, too safe, too punishing, or if the new blocker/resource loop is not actually closing.
Use the provided metrics and flags only. Do not invent missing data.

Return JSON only:
{
  "summary": "short overall judgment",
  "route_loop": "short judgment",
  "economy": "short judgment",
  "difficulty": "short judgment",
  "injury_pressure": "short judgment",
  "progression": "short judgment",
  "top_risks": ["risk 1", "risk 2"]
}"""


async def tcp_cmd(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, cmd: dict) -> dict:
    line = json.dumps(cmd) + "\n"
    writer.write(line.encode())
    await writer.drain()
    raw = await asyncio.wait_for(reader.readline(), timeout=120)
    if not raw:
        raise ConnectionError("Godot closed the connection")
    return json.loads(raw.decode().strip())


def check_assertions(assertions: list, state: dict) -> tuple[bool, list]:
    failures = []
    heroes = state.get("heroes", [])
    buildings = state.get("buildings", [])
    gold = state.get("gold", 0)

    for assertion in assertions:
        kind = assertion.get("assert", "")
        if kind == "hero_count_gte":
            if len(heroes) < assertion.get("value", 1):
                failures.append(assertion)
        elif kind == "hero_count_lte":
            if len(heroes) > assertion.get("value", 1):
                failures.append(assertion)
        elif kind == "any_hero_state":
            target = assertion.get("value", "")
            if not any(hero.get("state") == target for hero in heroes):
                failures.append(assertion)
        elif kind == "building_count_gte":
            if len(buildings) < assertion.get("value", 1):
                failures.append(assertion)
        elif kind == "building_type_count_eq":
            target_type = assertion.get("type", "")
            count = sum(1 for building in buildings if building.get("type") == target_type)
            if count != int(assertion.get("value", 0)):
                failures.append(assertion)
        elif kind == "quest_count_gte":
            if len(state.get("quests", [])) < assertion.get("value", 1):
                failures.append(assertion)
        elif kind == "quest_count_eq":
            if len(state.get("quests", [])) != int(assertion.get("value", 0)):
                failures.append(assertion)
        elif kind == "completed_quest_count_gte":
            if len(state.get("completed_quests", [])) < assertion.get("value", 1):
                failures.append(assertion)
        elif kind == "building_exists":
            if not any(building.get("type") == assertion.get("type", "") for building in buildings):
                failures.append(assertion)
        elif kind == "building_level_eq":
            target_type = assertion.get("type", "")
            target_level = int(assertion.get("value", 1))
            match = next((b for b in buildings if b.get("type") == target_type), None)
            if match is None or int(match.get("level", 1)) != target_level:
                failures.append(assertion)
        elif kind == "building_action_eq":
            target_type = assertion.get("type", "")
            target_action = str(assertion.get("value", ""))
            match = next((b for b in buildings if b.get("type") == target_type), None)
            if match is None or str(match.get("current_action", "")) != target_action:
                failures.append(assertion)
        elif kind == "building_output_stock_gte":
            target_type = assertion.get("type", "")
            target_value = int(assertion.get("value", 1))
            match = next((b for b in buildings if b.get("type") == target_type), None)
            if match is None or int(match.get("output_stock", 0)) < target_value:
                failures.append(assertion)
        elif kind == "building_installed_resource_count_gte":
            target_type = assertion.get("type", "")
            target_value = int(assertion.get("value", 1))
            match = next((b for b in buildings if b.get("type") == target_type), None)
            if match is None or len(match.get("installed_resource_ids", [])) < target_value:
                failures.append(assertion)
        elif kind == "building_has_installed_resource":
            target_type = assertion.get("type", "")
            target_value = str(assertion.get("value", ""))
            match = next((b for b in buildings if b.get("type") == target_type), None)
            if match is None or target_value not in match.get("installed_resource_ids", []):
                failures.append(assertion)
        elif kind == "gold_eq":
            if int(gold) != int(assertion.get("value", gold)):
                failures.append(assertion)
        elif kind == "gold_gte":
            if int(gold) < int(assertion.get("value", 0)):
                failures.append(assertion)
        elif kind == "any_hero_wound_state":
            target = assertion.get("value", "")
            if not any(str(hero.get("wound_state", "")) == target for hero in heroes):
                failures.append(assertion)
        elif kind == "completed_success_wound_seen":
            completed = state.get("completed_quests", [])
            if not any(bool(entry.get("success", False)) and str(entry.get("wound_state", "")) == "minor_wounded" for entry in completed):
                failures.append(assertion)
        elif kind == "completed_wound_seen":
            completed = state.get("completed_quests", [])
            if not any(str(entry.get("wound_state", "")) == "minor_wounded" for entry in completed):
                failures.append(assertion)
        elif kind == "event_type_seen":
            target = assertion.get("value", "")
            if not any(event.get("type", "") == target for event in state.get("events", [])):
                failures.append(assertion)
        elif kind == "quest_templates_only":
            allowed = set(assertion.get("value", []))
            quests = state.get("quests", [])
            if not quests or any(quest.get("template_id", "") not in allowed for quest in quests):
                failures.append(assertion)
        elif kind == "quest_templates_include":
            required = set(assertion.get("value", []))
            seen = {str(quest.get("template_id", "")) for quest in state.get("quests", [])}
            if not state.get("quests", []) or not required.issubset(seen):
                failures.append(assertion)
        elif kind == "quests_have_nonempty_field":
            field_name = assertion.get("value", "")
            quests = state.get("quests", [])
            if not quests:
                failures.append(assertion)
            else:
                for quest in quests:
                    field_value = quest.get(field_name)
                    if isinstance(field_value, list) and not field_value:
                        failures.append(assertion)
                        break
                    if isinstance(field_value, dict) and not field_value:
                        failures.append(assertion)
                        break
                    if field_value in (None, ""):
                        failures.append(assertion)
                        break
        elif kind == "blocker_count_gte":
            if len(state.get("blockers", [])) < int(assertion.get("value", 1)):
                failures.append(assertion)
        elif kind == "blocker_state_count_gte":
            target_state = str(assertion.get("state", ""))
            matched = sum(1 for blocker in state.get("blockers", []) if str(blocker.get("state", "")) == target_state)
            if matched < int(assertion.get("value", 1)):
                failures.append(assertion)
        elif kind == "blockers_have_nonempty_field":
            field_name = assertion.get("value", "")
            blockers = state.get("blockers", [])
            if not blockers:
                failures.append(assertion)
            else:
                for blocker in blockers:
                    field_value = blocker.get(field_name)
                    if isinstance(field_value, list) and not field_value:
                        failures.append(assertion)
                        break
                    if isinstance(field_value, dict) and not field_value:
                        failures.append(assertion)
                        break
                    if field_value in (None, ""):
                        failures.append(assertion)
                        break
        elif kind == "resource_unlocked":
            target_value = str(assertion.get("value", ""))
            if not any(str(resource.get("resource_id", "")) == target_value for resource in state.get("unlocked_resources", [])):
                failures.append(assertion)
        elif kind == "resource_active":
            target_value = str(assertion.get("value", ""))
            expected_active = bool(assertion.get("active", True))
            match = next((resource for resource in state.get("unlocked_resources", []) if str(resource.get("resource_id", "")) == target_value), None)
            if match is None or bool(match.get("active", False)) != expected_active:
                failures.append(assertion)
        elif kind == "quests_include_blocker_id":
            target_value = str(assertion.get("value", ""))
            if not any(str(quest.get("blocker_id", "")) == target_value for quest in state.get("quests", [])):
                failures.append(assertion)
        elif kind == "hero_careers_only":
            allowed = set(assertion.get("value", []))
            if not heroes or any(hero.get("career_id", "") not in allowed for hero in heroes):
                failures.append(assertion)
        elif kind == "heroes_have_nonempty_field":
            field_name = assertion.get("value", "")
            if not heroes:
                failures.append(assertion)
            else:
                for hero in heroes:
                    field_value = hero.get(field_name)
                    if isinstance(field_value, list) and not field_value:
                        failures.append(assertion)
                        break
                    if isinstance(field_value, dict) and not field_value:
                        failures.append(assertion)
                        break
                    if field_value in (None, ""):
                        failures.append(assertion)
                        break
        elif kind == "active_party_size_gte":
            target_size = int(assertion.get("value", 3))
            if not any(
                hero.get("state") in ["departing_quest", "on_quest", "returning"]
                and int(hero.get("quest_party_size", 0)) >= target_size
                for hero in heroes
            ):
                failures.append(assertion)
        elif kind == "hero_careers_include":
            required = set(assertion.get("value", []))
            seen = {str(hero.get("career_id", "")) for hero in heroes}
            if not required.issubset(seen):
                failures.append(assertion)
        elif kind == "any_urgent_quest":
            if not any(bool(quest.get("urgent", False)) for quest in state.get("quests", [])):
                failures.append(assertion)
        elif kind == "quest_expiry_lte":
            target = int(assertion.get("value", 0))
            if not any(int(quest.get("expiry_ticks_remaining", 0)) <= target for quest in state.get("quests", [])):
                failures.append(assertion)
        elif kind == "building_required_ticks_eq":
            target_type = assertion.get("type", "")
            target_value = int(assertion.get("value", 0))
            match = next((b for b in buildings if b.get("type") == target_type), None)
            if match is None or int(match.get("action_required_ticks", 0)) != target_value:
                failures.append(assertion)
    return len(failures) == 0, failures


def choose_port(port_arg: int) -> int:
    if port_arg > 0:
        return port_arg
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def scenario_requires_route_loop(scenario: dict) -> bool:
    route_assertions = {
        "blocker_count_gte",
        "blocker_state_count_gte",
        "blockers_have_nonempty_field",
        "resource_unlocked",
        "building_installed_resource_count_gte",
        "building_has_installed_resource",
        "quests_include_blocker_id",
    }
    for assertion in scenario.get("assertions", []):
        if assertion.get("assert", "") in route_assertions:
            return True
    return False


def any_hero_available_for_quest(heroes: list[dict]) -> bool:
    for hero in heroes:
        if hero.get("state") not in {"idling", "at_tavern", "using_service"}:
            continue
        if str(hero.get("wound_state", "healthy")) != "healthy":
            continue
        if hero.get("current_quest"):
            continue
        return True
    return False


def safe_div(numerator: float, denominator: float) -> float:
    if denominator == 0:
        return 0.0
    return float(numerator) / float(denominator)


def average(values: list[float]) -> float:
    if not values:
        return 0.0
    return float(sum(values)) / float(len(values))


def round2(value: float) -> float:
    return round(float(value), 2)


def event_count(events: list[dict], event_type: str, service: str | None = None) -> int:
    total = 0
    for event in events:
        if event.get("type") != event_type:
            continue
        if service is not None and event.get("service") != service:
            continue
        total += 1
    return total


def event_amount(events: list[dict], event_type: str, service: str | None = None) -> int:
    total = 0
    for event in events:
        if event.get("type") != event_type:
            continue
        if service is not None and event.get("service") != service:
            continue
        total += int(event.get("amount", 0))
    return total


def build_balance_report(state: dict, scenario: dict) -> dict:
    heroes = state.get("heroes", [])
    events = state.get("events", [])
    completed = state.get("completed_quests", [])
    buildings = state.get("buildings", [])
    blockers = state.get("blockers", [])
    unlocked_resources = state.get("unlocked_resources", [])
    current_gold = int(state.get("gold", 0))
    town_profit = current_gold - STARTING_GOLD
    route_loop_required = scenario_requires_route_loop(scenario)

    hero_gold_values = [int(hero.get("gold", 0)) for hero in heroes]
    hero_level_values = [int(hero.get("level", 1)) for hero in heroes]
    hero_hp_ratios = [
        safe_div(int(hero.get("health", 0)), max(1, int(hero.get("max_health", 1))))
        for hero in heroes
    ]
    wounded_heroes = [hero for hero in heroes if str(hero.get("wound_state", "healthy")) != "healthy"]
    recovering_heroes = [hero for hero in heroes if hero.get("state") == "recovering"]
    broke_heroes = [hero for hero in heroes if int(hero.get("gold", 0)) <= 1]

    success_count = sum(1 for entry in completed if bool(entry.get("success", False)))
    failure_count = len(completed) - success_count
    wound_count = sum(1 for entry in completed if str(entry.get("wound_state", "healthy")) != "healthy")
    success_wound_count = sum(
        1
        for entry in completed
        if bool(entry.get("success", False)) and str(entry.get("wound_state", "healthy")) != "healthy"
    )
    total_reward_gold = sum(int(entry.get("gold_reward", 0)) for entry in completed)
    total_reward_xp = sum(int(entry.get("xp_reward", 0)) for entry in completed)

    spending = {
        "tavern": {
            "count": event_count(events, "hero_spent_at_tavern"),
            "amount": event_amount(events, "hero_spent_at_tavern"),
        },
        "general_store": {
            "count": event_count(events, "hero_spent_at_weapons_shop"),
            "amount": event_amount(events, "hero_spent_at_weapons_shop"),
        },
        "temple": {
            "count": event_count(events, "hero_spent_at_temple"),
            "amount": event_amount(events, "hero_spent_at_temple"),
            "healing_count": event_count(events, "hero_spent_at_temple", "healing"),
            "blessing_count": event_count(events, "hero_spent_at_temple", "blessing"),
        },
    }

    quest_event_counts = {
        "started": event_count(events, "hero_started_quest"),
        "departed": event_count(events, "hero_departed_for_quest"),
        "completed": event_count(events, "hero_completed_quest"),
        "returned": event_count(events, "hero_returned_from_quest"),
        "leveled_up": event_count(events, "hero_leveled_up"),
        "phase_changed": event_count(events, "quest_phase_changed"),
        "progress_events": event_count(events, "quest_progress_event"),
        "resource_unlocked": event_count(events, "resource_unlocked"),
        "resource_installed": event_count(events, "resource_installed"),
    }

    blocker_state_counts: dict[str, int] = {}
    for blocker in blockers:
        state_name = str(blocker.get("state", "unknown"))
        blocker_state_counts[state_name] = blocker_state_counts.get(state_name, 0) + 1

    installed_resource_count = sum(len(building.get("installed_resource_ids", [])) for building in buildings)
    disrupted_resource_count = sum(
        1 for resource in unlocked_resources if bool(resource.get("installed", False)) and not bool(resource.get("active", True))
    )
    active_quests = [
        hero for hero in heroes if hero.get("state") in {"departing_quest", "on_quest", "returning"} and hero.get("quest_party_leader_id", -1) == hero.get("id")
    ]
    active_phase_names = sorted({str(hero.get("current_quest", {}).get("quest_phase", "")) for hero in active_quests if hero.get("current_quest")})

    loop_health = {
        "quests_generated": len(state.get("quests", [])) + len(completed) > 0,
        "quests_started": quest_event_counts["started"] > 0,
        "quests_completed": len(completed) > 0,
        "returns_seen": quest_event_counts["returned"] > 0,
        "spending_seen_in_all_services": all(entry["count"] > 0 for entry in spending.values()),
        "loop_closed": (
            quest_event_counts["started"] > 0
            and len(completed) > 0
            and sum(entry["count"] for entry in spending.values()) > 0
        ),
        "blockers_discovered": blocker_state_counts.get("discovered", 0) + blocker_state_counts.get("active_quest", 0) + blocker_state_counts.get("unblocked", 0) > 0,
        "resources_unlocked": len(unlocked_resources) > 0 or quest_event_counts["resource_unlocked"] > 0,
        "resources_installed": installed_resource_count > 0 or quest_event_counts["resource_installed"] > 0,
        "phased_quest_runtime_visible": quest_event_counts["phase_changed"] > 0 and quest_event_counts["progress_events"] > 0,
    }

    severe_flags: list[str] = []
    moderate_flags: list[str] = []

    if len(completed) == 0:
        severe_flags.append("no_completed_quests")
    if not loop_health["loop_closed"]:
        severe_flags.append("loop_not_closing")
    if route_loop_required and not loop_health["blockers_discovered"]:
        severe_flags.append("blocker_discovery_missing")
    if route_loop_required and not loop_health["resources_unlocked"]:
        severe_flags.append("resource_unlock_loop_missing")
    if route_loop_required and not loop_health["resources_installed"]:
        severe_flags.append("resource_install_loop_missing")
    if route_loop_required and not loop_health["phased_quest_runtime_visible"]:
        moderate_flags.append("active_quest_progress_missing")
    if town_profit < -150:
        severe_flags.append("town_bleeds_money")
    elif town_profit > 250:
        moderate_flags.append("town_gets_rich_too_fast")

    success_rate = safe_div(success_count, len(completed))
    wound_rate = safe_div(wound_count, len(completed))
    success_wound_rate = safe_div(success_wound_count, max(1, success_count))

    if len(completed) >= 3:
        if success_rate < 0.4:
            severe_flags.append("quests_too_hard")
        elif len(completed) >= 5 and success_rate > 0.95 and wound_rate < 0.35:
            moderate_flags.append("quests_too_easy")

        if wound_rate < 0.05:
            moderate_flags.append("injury_pressure_too_low")
        elif wound_rate > 0.7:
            severe_flags.append("injury_pressure_too_high")

        if average(hero_gold_values) <= 1.5:
            severe_flags.append("heroes_too_poor")
        elif average(hero_gold_values) >= 25:
            moderate_flags.append("heroes_hoard_too_much_gold")

    if wound_count > 0 and spending["temple"]["healing_count"] == 0:
        moderate_flags.append("wounds_not_driving_temple_usage")
    if quest_event_counts["started"] > 0 and spending["general_store"]["count"] == 0:
        moderate_flags.append("quest_prep_loop_missing")
    if heroes and spending["tavern"]["count"] == 0:
        moderate_flags.append("inn_spending_loop_missing")
    if heroes and average(hero_hp_ratios) < 0.45:
        severe_flags.append("party_health_too_low")
    elif heroes and average(hero_hp_ratios) > 0.98 and len(completed) >= 3 and wound_count == 0:
        moderate_flags.append("party_almost_never_takes_damage")
    if route_loop_required and len(unlocked_resources) > 0 and installed_resource_count == 0 and any_hero_available_for_quest(heroes):
        moderate_flags.append("unlocked_resources_left_uninstalled")
    if route_loop_required and blocker_state_counts.get("known_blocked", 0) > 0 and quest_event_counts["started"] == 0:
        moderate_flags.append("known_blockers_not_becoming_missions")

    target_overrides = scenario.get("analysis_targets", {})
    max_town_gold = target_overrides.get("max_town_gold")
    if max_town_gold is not None and current_gold > int(max_town_gold):
        moderate_flags.append("town_gold_above_target")
    min_town_gold = target_overrides.get("min_town_gold")
    if min_town_gold is not None and current_gold < int(min_town_gold):
        moderate_flags.append("town_gold_below_target")

    verdict = "healthy"
    if severe_flags:
        verdict = "unstable"
    elif moderate_flags:
        verdict = "watch"

    economy_band = "healthy"
    if town_profit < -50:
        economy_band = "starved"
    elif town_profit > 180:
        economy_band = "rich"

    difficulty_band = "healthy"
    if len(completed) >= 3:
        if success_rate < 0.45:
            difficulty_band = "hard"
        elif success_rate > 0.9:
            difficulty_band = "easy"

    injury_band = "healthy"
    if len(completed) >= 3:
        if wound_rate < 0.08:
            injury_band = "low"
        elif wound_rate > 0.55:
            injury_band = "high"

    report = {
        "verdict": verdict,
        "loop_health": loop_health,
        "routes": {
            "required": route_loop_required,
            "blocker_count": len(blockers),
            "blocker_states": blocker_state_counts,
            "unlocked_resource_count": len(unlocked_resources),
            "installed_resource_count": installed_resource_count,
            "disrupted_resource_count": disrupted_resource_count,
            "active_phase_names": active_phase_names,
        },
        "economy": {
            "starting_gold": STARTING_GOLD,
            "current_gold": current_gold,
            "town_profit": town_profit,
            "band": economy_band,
            "spending": spending,
        },
        "adventurers": {
            "count": len(heroes),
            "avg_level": round2(average(hero_level_values)),
            "max_level": max(hero_level_values) if hero_level_values else 0,
            "avg_gold": round2(average(hero_gold_values)),
            "avg_hp_ratio": round2(average(hero_hp_ratios)),
            "wounded_count": len(wounded_heroes),
            "recovering_count": len(recovering_heroes),
            "broke_count": len(broke_heroes),
        },
        "quests": {
            "completed_count": len(completed),
            "success_count": success_count,
            "failure_count": failure_count,
            "success_rate": round2(success_rate),
            "wound_count": wound_count,
            "wound_rate": round2(wound_rate),
            "success_wound_count": success_wound_count,
            "success_wound_rate": round2(success_wound_rate),
            "avg_gold_reward": round2(safe_div(total_reward_gold, max(1, len(completed)))),
            "avg_xp_reward": round2(safe_div(total_reward_xp, max(1, len(completed)))),
            "event_counts": quest_event_counts,
            "difficulty_band": difficulty_band,
            "injury_band": injury_band,
        },
        "flags": {
            "severe": severe_flags,
            "moderate": moderate_flags,
        },
    }
    report["summary"] = summarize_balance_report(report)
    return report


def summarize_balance_report(report: dict) -> str:
    parts = [
        f"verdict={report.get('verdict', 'unknown')}",
        f"town_profit={report.get('economy', {}).get('town_profit', 0)}",
        f"quest_success_rate={report.get('quests', {}).get('success_rate', 0)}",
        f"wound_rate={report.get('quests', {}).get('wound_rate', 0)}",
        f"avg_hero_gold={report.get('adventurers', {}).get('avg_gold', 0)}",
    ]
    if report.get("routes", {}).get("required", False):
        parts.append(
            "route_loop=%s/%s"
            % (
                report.get("routes", {}).get("unlocked_resource_count", 0),
                report.get("routes", {}).get("installed_resource_count", 0),
            )
        )
    severe = report.get("flags", {}).get("severe", [])
    moderate = report.get("flags", {}).get("moderate", [])
    if severe:
        parts.append("severe=" + ",".join(severe))
    elif moderate:
        parts.append("watch=" + ",".join(moderate[:3]))
    return "; ".join(parts)


def request_chat_completion(api_kind: str, api_url: str, model: str, messages: list[dict], timeout: int) -> str:
    if api_kind == "openai":
        resp = requests.post(
            api_url,
            json={"model": model, "messages": messages, "temperature": 0.2, "max_tokens": 220},
            timeout=timeout,
        )
        resp.raise_for_status()
        data = resp.json()
        return data["choices"][0]["message"]["content"].strip()

    resp = requests.post(
        api_url,
        json={"model": model, "messages": messages, "stream": False},
        timeout=timeout,
    )
    resp.raise_for_status()
    return resp.json()["message"]["content"].strip()


def ask_llm(model: str, goal: str, state: dict, history: list, failures: list, api_kind: str, api_url: str) -> dict | None:
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    messages.extend(history[-4:])

    user_msg = (
        f"Goal: {goal}\n\n"
        f"Unmet assertions:\n{json.dumps(failures, indent=2)}\n\n"
        f"Current world state:\n{json.dumps(summarize_state_for_llm(state), indent=2)}\n\n"
        "Return the single best next command."
    )
    messages.append({"role": "user", "content": user_msg})

    try:
        content = request_chat_completion(api_kind, api_url, model, messages, OLLAMA_TIMEOUT)
        print(f"[LLM] raw: {content[:200]}")
        return extract_command(content)
    except Exception as exc:
        print(f"[LLM] error: {exc}", file=sys.stderr)
        return None


def ask_llm_analysis(model: str, scenario: dict, report: dict, api_kind: str, api_url: str) -> dict | None:
    messages = [
        {"role": "system", "content": ANALYSIS_PROMPT},
        {
            "role": "user",
            "content": (
                f"Scenario: {scenario.get('name', '?')}\n"
                f"Goal: {scenario.get('goal', '')}\n\n"
                f"Balance report:\n{json.dumps(report, indent=2)}\n"
            ),
        },
    ]
    try:
        content = request_chat_completion(api_kind, api_url, model, messages, OLLAMA_TIMEOUT)
        print(f"[LLM-analysis] raw: {content[:300]}")
        parsed = extract_first_json_object(content)
        if isinstance(parsed, dict):
            return parsed
    except Exception as exc:
        print(f"[LLM-analysis] error: {exc}", file=sys.stderr)
    return None


def extract_first_json_object(text: str) -> dict | None:
    decoder = json.JSONDecoder()
    cleaned = text.replace("```json", "").replace("```", "").strip()
    idx = 0

    while idx < len(cleaned):
        brace = cleaned.find("{", idx)
        if brace == -1:
            break
        try:
            obj, end = decoder.raw_decode(cleaned[brace:])
        except json.JSONDecodeError:
            idx = brace + 1
            continue
        if isinstance(obj, dict):
            return obj
        idx = brace + max(end, 1)
    return None


def extract_command(text: str) -> dict | None:
    obj = extract_first_json_object(text)
    if isinstance(obj, dict) and "cmd" in obj:
        return obj
    if isinstance(obj, dict) and isinstance(obj.get("command"), dict) and "cmd" in obj["command"]:
        return obj["command"]

    cleaned = text.replace("```json", "").replace("```", "").strip()
    print(f"[LLM] could not parse JSON command from: {cleaned[:200]}", file=sys.stderr)
    return None


def normalize_command(cmd: dict) -> dict | None:
    if not isinstance(cmd, dict):
        return None

    name = cmd.get("cmd", "")
    if name == "place_building":
        building_type = cmd.get("type", "")
        if building_type not in {"tavern", "weapons_shop", "temple"}:
            return None
        return {
            "cmd": "place_building",
            "type": building_type,
            "x": int(cmd.get("x", 0)),
            "z": int(cmd.get("z", 0)),
        }
    if name == "upgrade_building":
        building_type = cmd.get("type", "")
        if building_type not in {"tavern", "weapons_shop", "temple"}:
            return None
        return {"cmd": "upgrade_building", "type": building_type}
    if name == "start_building_upgrade":
        building_type = cmd.get("type", "")
        if building_type not in {"tavern", "weapons_shop", "temple"}:
            return None
        return {"cmd": "start_building_upgrade", "type": building_type}
    if name == "set_building_output_mode":
        building_type = cmd.get("type", "")
        if building_type not in {"tavern", "weapons_shop", "temple"}:
            return None
        return {"cmd": "set_building_output_mode", "type": building_type}
    if name == "install_building_resource":
        building_type = cmd.get("type", "")
        resource_id = str(cmd.get("resource_id", ""))
        if building_type not in {"tavern", "weapons_shop", "temple"} or not resource_id:
            return None
        return {"cmd": "install_building_resource", "type": building_type, "resource_id": resource_id}
    if name == "accept_quest":
        offer_id = int(cmd.get("offer_id", -1))
        hero_ids = [int(hero_id) for hero_id in cmd.get("hero_ids", []) if int(hero_id) > 0]
        if offer_id < 0:
            return {"cmd": "accept_quest", "hero_ids": hero_ids} if hero_ids else {"cmd": "accept_quest"}
        normalized = {"cmd": "accept_quest", "offer_id": offer_id}
        if hero_ids:
            normalized["hero_ids"] = hero_ids
        return normalized
    if name == "step_ticks":
        n = max(1, min(int(cmd.get("n", 60)), 3600))
        return {"cmd": "step_ticks", "n": n}
    if name == "set_quest_enabled":
        quest_id = str(cmd.get("id", ""))
        if not quest_id:
            return None
        return {"cmd": "set_quest_enabled", "id": quest_id, "enabled": bool(cmd.get("enabled", True))}
    if name == "set_gold":
        return {"cmd": "set_gold", "value": int(cmd.get("value", 0))}
    if name == "run_until":
        event = cmd.get("event", "hero_arrived_at_tavern")
        if event not in RUN_UNTIL_EVENTS:
            event = "hero_arrived_at_tavern"
        max_ticks = max(1, min(int(cmd.get("max_ticks", 1800)), 7200))
        return {"cmd": "run_until", "event": event, "max_ticks": max_ticks}
    if name == "get_world_state":
        return {"cmd": "get_world_state"}
    return None


def summarize_state_for_llm(state: dict) -> dict:
    completed = state.get("completed_quests", [])
    blockers = state.get("blockers", [])
    unlocked_resources = state.get("unlocked_resources", [])
    blocker_summary: dict[str, int] = {}
    for blocker in blockers:
        blocker_state = str(blocker.get("state", "unknown"))
        blocker_summary[blocker_state] = blocker_summary.get(blocker_state, 0) + 1
    return {
        "tick": state.get("tick", 0),
        "gold": state.get("gold", 0),
        "buildings": [
            {
                "type": building.get("type"),
                "level": building.get("level", 1),
                "current_action": building.get("current_action", "idle"),
                "output_stock": building.get("output_stock", 0),
                "resource_slot_capacity": building.get("resource_slot_capacity", 0),
                "installed_resource_ids": building.get("installed_resource_ids", []),
            }
            for building in state.get("buildings", [])
        ],
        "heroes": [
            {
                "id": hero.get("id"),
                "name": hero.get("name"),
                "state": hero.get("state"),
                "level": hero.get("level", 1),
                "career_id": hero.get("career_id", ""),
                "wound_state": hero.get("wound_state", "healthy"),
                "current_quest": hero.get("current_quest", {}).get("name", ""),
            }
            for hero in state.get("heroes", [])
        ],
        "quests": [
            {
                "offer_id": quest.get("offer_id", -1),
                "id": quest.get("template_id", quest.get("id", "")),
                "name": quest.get("name", ""),
                "type": quest.get("type", ""),
                "difficulty": quest.get("difficulty", 1),
                "blocker_id": quest.get("blocker_id", ""),
                "reward_resource_id": quest.get("reward_resource_id", ""),
                "party_size": quest.get("party_size", 0),
            }
            for quest in state.get("quests", [])
        ],
        "routes": {
            "blocker_states": blocker_summary,
            "discovered_blockers": [
                {
                    "blocker_id": blocker.get("blocker_id", ""),
                    "name": blocker.get("name", ""),
                    "state": blocker.get("state", ""),
                    "unlocks_resource_id": blocker.get("unlocks_resource_id", ""),
                    "required_building": blocker.get("required_building", ""),
                }
                for blocker in blockers
                if str(blocker.get("state", "")) in {"discovered", "active_quest", "unblocked"}
            ],
            "unlocked_resources": [
                {
                    "resource_id": resource.get("resource_id", ""),
                    "building_type": resource.get("building_type", ""),
                    "installed": bool(resource.get("installed", False)),
                    "installed_building_id": resource.get("installed_building_id", -1),
                }
                for resource in unlocked_resources
            ],
        },
        "quest_summary": {
            "completed": len(completed),
            "successes": sum(1 for quest in completed if bool(quest.get("success", False))),
            "wounded_returns": sum(1 for quest in completed if str(quest.get("wound_state", "healthy")) != "healthy"),
        },
        "recent_events": state.get("events", [])[-8:],
    }


def first_installable_resource(state: dict, building_type: str | None = None) -> dict | None:
    buildings = state.get("buildings", [])
    for resource in state.get("unlocked_resources", []):
        if bool(resource.get("installed", False)):
            continue
        resource_building_type = str(resource.get("building_type", ""))
        if building_type is not None and resource_building_type != building_type:
            continue
        if any(building.get("type") == resource_building_type for building in buildings):
            return resource
    return None


def fallback_quest_party(quests: list[dict], heroes: list[dict]) -> dict | None:
    if not quests:
        return None
    available = [
        int(hero.get("id", -1))
        for hero in heroes
        if hero.get("state") in {"idling", "at_tavern", "using_service"}
        and str(hero.get("wound_state", "healthy")) == "healthy"
        and not hero.get("current_quest")
    ]
    if not available:
        return None
    quest = quests[0]
    party_size = max(1, int(quest.get("party_size", 1)))
    if len(available) < party_size:
        return None
    return {"cmd": "accept_quest", "offer_id": int(quest.get("offer_id", -1))}


def choose_fallback_command(state: dict, failures: list) -> dict:
    buildings = state.get("buildings", [])
    building_types = {building.get("type") for building in buildings}
    building_levels = {building.get("type"): int(building.get("level", 1)) for building in buildings}
    building_actions = {building.get("type"): str(building.get("current_action", "idle")) for building in buildings}
    heroes = state.get("heroes", [])
    quests = state.get("quests", [])
    unlocked_resources = state.get("unlocked_resources", [])
    active_quest_running = any(hero.get("state") in {"departing_quest", "on_quest", "returning"} for hero in heroes)
    required_buildings = set()
    required_output_buildings = set()
    required_resource_installs = set()
    wants_quest_progress = False

    for failure in failures:
        kind = failure.get("assert", "")
        if kind == "gold_gte":
            required_buildings.update({"tavern", "weapons_shop", "temple"})
            required_output_buildings.update({"tavern", "weapons_shop", "temple"})
        if kind in {"quest_count_gte", "quest_templates_only", "quest_templates_include"}:
            required_buildings.add("tavern")
            required_output_buildings.add("tavern")
        if kind == "building_output_stock_gte":
            required_output_buildings.add(failure.get("type", ""))
        if kind in {"building_installed_resource_count_gte", "building_has_installed_resource"}:
            required_resource_installs.add(failure.get("type", ""))
        if kind == "event_type_seen":
            event_type = failure.get("value", "")
            if event_type == "hero_spent_at_tavern":
                required_buildings.add("tavern")
                required_output_buildings.add("tavern")
            elif event_type == "hero_spent_at_weapons_shop":
                required_buildings.add("weapons_shop")
                required_output_buildings.add("weapons_shop")
            elif event_type == "hero_spent_at_temple":
                required_buildings.add("temple")
                required_output_buildings.add("temple")
            elif event_type == "resource_installed":
                required_resource_installs.update({"tavern", "weapons_shop", "temple"})
            elif event_type in {"hero_started_quest", "hero_departed_for_quest", "hero_completed_quest", "hero_heading_home", "hero_returned_from_quest"}:
                required_buildings.add("tavern")
                required_output_buildings.add("tavern")
                wants_quest_progress = True
            elif event_type in {"quest_phase_changed", "quest_progress_event", "resource_unlocked"}:
                wants_quest_progress = True
        elif kind in {"completed_quest_count_gte", "resource_unlocked", "building_installed_resource_count_gte", "building_has_installed_resource"}:
            wants_quest_progress = True

    for building_type in ("tavern", "weapons_shop", "temple"):
        if building_type in required_buildings and building_type not in building_types:
            placement = {
                "tavern": {"x": 0, "z": 0},
                "weapons_shop": {"x": 3, "z": 0},
                "temple": {"x": -3, "z": 0},
            }[building_type]
            return {"cmd": "place_building", "type": building_type, **placement}

    for building_type in ("tavern", "weapons_shop", "temple"):
        if building_type in required_output_buildings and building_type in building_types:
            if building_actions.get(building_type, "idle") == "idle":
                return {"cmd": "set_building_output_mode", "type": building_type}

    if active_quest_running:
        return {"cmd": "step_ticks", "n": 600}

    for building_type in ("tavern", "weapons_shop", "temple"):
        if building_type in required_resource_installs:
            resource = first_installable_resource(state, building_type)
            if resource is not None:
                return {
                    "cmd": "install_building_resource",
                    "type": building_type,
                    "resource_id": str(resource.get("resource_id", "")),
                }

    if unlocked_resources:
        resource = first_installable_resource(state)
        if resource is not None:
            return {
                "cmd": "install_building_resource",
                "type": str(resource.get("building_type", "")),
                "resource_id": str(resource.get("resource_id", "")),
            }

    if wants_quest_progress and quests:
        party_cmd = fallback_quest_party(quests, heroes)
        if party_cmd is not None:
            return party_cmd
        return {"cmd": "step_ticks", "n": 180}

    for failure in failures:
        kind = failure.get("assert", "")
        if kind in {"hero_count_gte", "any_hero_state"}:
            if "tavern" not in building_types:
                return {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0}
            if building_actions.get("tavern", "idle") == "idle":
                return {"cmd": "set_building_output_mode", "type": "tavern"}
            if not heroes:
                return {"cmd": "run_until", "event": "hero_arrived_at_tavern", "max_ticks": 1800}
            return {"cmd": "step_ticks", "n": 300}
        if kind == "building_exists":
            target_type = failure.get("type", "")
            if target_type and target_type not in building_types:
                placement = {
                    "tavern": {"x": 0, "z": 0},
                    "weapons_shop": {"x": 3, "z": 0},
                    "temple": {"x": -3, "z": 0},
                }.get(target_type, {"x": 0, "z": 0})
                return {"cmd": "place_building", "type": target_type, **placement}
        if kind == "building_level_eq":
            target_type = failure.get("type", "")
            if target_type not in building_types:
                placement = {
                    "tavern": {"x": 0, "z": 0},
                    "weapons_shop": {"x": 3, "z": 0},
                    "temple": {"x": -3, "z": 0},
                }.get(target_type, {"x": 0, "z": 0})
                return {"cmd": "place_building", "type": target_type, **placement}
            return {"cmd": "upgrade_building", "type": target_type}
        if kind == "quest_count_gte":
            if "tavern" not in building_types:
                return {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0}
            if building_actions.get("tavern", "idle") == "idle":
                return {"cmd": "set_building_output_mode", "type": "tavern"}
            return {"cmd": "step_ticks", "n": 300}
        if kind == "resource_unlocked":
            if "tavern" not in building_types:
                return {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0}
            if building_actions.get("tavern", "idle") == "idle":
                return {"cmd": "set_building_output_mode", "type": "tavern"}
                if quests:
                    party_cmd = fallback_quest_party(quests, heroes)
                    if party_cmd is not None:
                        return party_cmd
                    return {"cmd": "step_ticks", "n": 180}
                return {"cmd": "step_ticks", "n": 600}
        if kind in {"building_installed_resource_count_gte", "building_has_installed_resource"}:
            target_type = failure.get("type", "")
            resource = first_installable_resource(state, target_type)
            if resource is not None:
                return {"cmd": "install_building_resource", "type": target_type, "resource_id": str(resource.get("resource_id", ""))}
            if quests:
                party_cmd = fallback_quest_party(quests, heroes)
                if party_cmd is not None:
                    return party_cmd
                return {"cmd": "step_ticks", "n": 180}
            if building_actions.get("tavern", "idle") == "idle":
                return {"cmd": "set_building_output_mode", "type": "tavern"}
            return {"cmd": "step_ticks", "n": 600}
        if kind in {"blocker_count_gte", "blocker_state_count_gte", "blockers_have_nonempty_field", "quests_include_blocker_id"}:
            if "tavern" not in building_types:
                return {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0}
            if building_actions.get("tavern", "idle") == "idle":
                return {"cmd": "set_building_output_mode", "type": "tavern"}
            return {"cmd": "step_ticks", "n": 300}
        if kind in {"quest_templates_only", "quest_templates_include"}:
            if "tavern" not in building_types:
                return {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0}
            if building_actions.get("tavern", "idle") == "idle":
                return {"cmd": "set_building_output_mode", "type": "tavern"}
            return {"cmd": "step_ticks", "n": 600}
        if kind == "gold_gte":
            for building_type in ("tavern", "weapons_shop", "temple"):
                if building_type not in building_types:
                    placement = {
                        "tavern": {"x": 0, "z": 0},
                        "weapons_shop": {"x": 3, "z": 0},
                        "temple": {"x": -3, "z": 0},
                    }[building_type]
                    return {"cmd": "place_building", "type": building_type, **placement}
            for building_type in ("tavern", "weapons_shop", "temple"):
                if building_actions.get(building_type, "idle") == "idle":
                    return {"cmd": "set_building_output_mode", "type": building_type}
            return {"cmd": "step_ticks", "n": 900}
        if kind == "event_type_seen":
            event_type = failure.get("value")
            if event_type == "hero_spent_at_tavern" and "tavern" not in building_types:
                return {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0}
            if event_type == "hero_spent_at_weapons_shop" and "weapons_shop" not in building_types:
                return {"cmd": "place_building", "type": "weapons_shop", "x": 3, "z": 0}
            if event_type == "hero_spent_at_temple" and "temple" not in building_types:
                return {"cmd": "place_building", "type": "temple", "x": -3, "z": 0}
            if "tavern" not in building_types:
                return {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0}
            if event_type in {
                "hero_started_quest",
                "hero_departed_for_quest",
                "hero_completed_quest",
                "hero_heading_home",
                "hero_returned_from_quest",
            } and building_actions.get("tavern", "idle") == "idle":
                return {"cmd": "set_building_output_mode", "type": "tavern"}
            if event_type in {
                "hero_started_quest",
                "hero_departed_for_quest",
                "hero_completed_quest",
                "hero_heading_home",
                "hero_returned_from_quest",
            } and quests:
                party_cmd = fallback_quest_party(quests, heroes)
                if party_cmd is not None:
                    return party_cmd
                return {"cmd": "step_ticks", "n": 180}
            if event_type == "resource_unlocked":
                if quests:
                    party_cmd = fallback_quest_party(quests, heroes)
                    if party_cmd is not None:
                        return party_cmd
                    return {"cmd": "step_ticks", "n": 180}
                return {"cmd": "step_ticks", "n": 900}
            if event_type == "resource_installed":
                resource = first_installable_resource(state)
                if resource is not None:
                    return {
                        "cmd": "install_building_resource",
                        "type": str(resource.get("building_type", "")),
                        "resource_id": str(resource.get("resource_id", "")),
                    }
            if event_type == "hero_spent_at_weapons_shop" and building_actions.get("weapons_shop", "idle") == "idle":
                return {"cmd": "set_building_output_mode", "type": "weapons_shop"}
            if event_type == "hero_spent_at_temple" and building_actions.get("temple", "idle") == "idle":
                return {"cmd": "set_building_output_mode", "type": "temple"}
            if not heroes:
                return {"cmd": "run_until", "event": "hero_arrived_at_tavern", "max_ticks": 1800}
            if event_type in {"hero_started_quest", "hero_departed_for_quest"}:
                return {"cmd": "run_until", "event": "hero_departed_for_quest", "max_ticks": 1800}
            if event_type in {"hero_completed_quest", "hero_heading_home", "hero_returned_from_quest"}:
                return {"cmd": "run_until", "event": event_type, "max_ticks": 3600}
            if event_type in {"hero_spent_at_tavern", "hero_spent_at_weapons_shop", "hero_spent_at_temple"}:
                return {"cmd": "run_until", "event": event_type, "max_ticks": 3600}
            return {"cmd": "step_ticks", "n": 900}

    for building_type in ("tavern", "weapons_shop", "temple"):
        if building_type not in building_types:
            placement = {
                "tavern": {"x": 0, "z": 0},
                "weapons_shop": {"x": 3, "z": 0},
                "temple": {"x": -3, "z": 0},
            }[building_type]
            return {"cmd": "place_building", "type": building_type, **placement}

    for building_type in ("tavern", "weapons_shop", "temple"):
        if building_levels.get(building_type, 1) < 3:
            return {"cmd": "upgrade_building", "type": building_type}

    for building_type in ("tavern", "weapons_shop", "temple"):
        if building_type in building_types and building_actions.get(building_type, "idle") == "idle":
            return {"cmd": "set_building_output_mode", "type": building_type}

    resource = first_installable_resource(state)
    if resource is not None:
        return {
            "cmd": "install_building_resource",
            "type": str(resource.get("building_type", "")),
            "resource_id": str(resource.get("resource_id", "")),
        }

    if quests:
        party_cmd = fallback_quest_party(quests, heroes)
        if party_cmd is not None:
            return party_cmd
        return {"cmd": "step_ticks", "n": 180}

    if "tavern" not in building_types:
        return {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0}
    if building_actions.get("tavern", "idle") == "idle":
        return {"cmd": "set_building_output_mode", "type": "tavern"}
    if not heroes:
        return {"cmd": "run_until", "event": "hero_arrived_at_tavern", "max_ticks": 1800}
    return {"cmd": "step_ticks", "n": 300}


def is_useful_command(cmd: dict, state: dict, last_cmd: dict | None, failures: list) -> bool:
    if cmd is None:
        return False

    buildings = state.get("buildings", [])
    building_types = {building.get("type") for building in buildings}
    building_actions = {building.get("type"): str(building.get("current_action", "idle")) for building in buildings}
    installed_resource_ids = {
        resource_id
        for building in buildings
        for resource_id in building.get("installed_resource_ids", [])
    }
    required_buildings = set()
    for failure in failures:
        kind = failure.get("assert", "")
        if kind in {"quest_count_gte", "quest_templates_only", "quest_templates_include"}:
            required_buildings.add("tavern")
        if kind == "gold_gte":
            required_buildings.update({"tavern", "weapons_shop", "temple"})
        if kind == "event_type_seen":
            event_type = failure.get("value", "")
            if event_type == "hero_spent_at_tavern":
                required_buildings.add("tavern")
            elif event_type == "hero_spent_at_weapons_shop":
                required_buildings.add("weapons_shop")
            elif event_type == "hero_spent_at_temple":
                required_buildings.add("temple")

    missing_required = [b for b in ("tavern", "weapons_shop", "temple") if b in required_buildings and b not in building_types]
    if missing_required:
        return cmd.get("cmd") == "place_building" and cmd.get("type") == missing_required[0]

    if cmd.get("cmd") == "place_building" and cmd.get("type") in building_types:
        return False
    if cmd.get("cmd") == "upgrade_building" and cmd.get("type") not in building_types:
        return False
    if cmd.get("cmd") == "set_building_output_mode":
        building_type = cmd.get("type")
        if building_type not in building_types:
            return False
        if building_actions.get(building_type, "idle") != "idle":
            return False
    if cmd.get("cmd") == "install_building_resource":
        building_type = cmd.get("type")
        resource_id = str(cmd.get("resource_id", ""))
        if building_type not in building_types or not resource_id:
            return False
        if resource_id in installed_resource_ids:
            return False
        matching_resource = next(
            (
                resource
                for resource in state.get("unlocked_resources", [])
                if str(resource.get("resource_id", "")) == resource_id
            ),
            None,
        )
        if matching_resource is None:
            return False
        if str(matching_resource.get("building_type", "")) != building_type:
            return False
    if cmd.get("cmd") == "accept_quest":
        offer_id = int(cmd.get("offer_id", -1))
        if offer_id < 0:
            return len(state.get("quests", [])) > 0
        if not any(int(quest.get("offer_id", -2)) == offer_id for quest in state.get("quests", [])):
            return False
        hero_ids = [int(hero_id) for hero_id in cmd.get("hero_ids", []) if int(hero_id) > 0]
        if hero_ids:
            hero_lookup = {int(hero.get("id", -1)): hero for hero in state.get("heroes", [])}
            for hero_id in hero_ids:
                hero = hero_lookup.get(hero_id)
                if hero is None:
                    return False
                if hero.get("state") not in {"idling", "at_tavern", "using_service"}:
                    return False
                if str(hero.get("wound_state", "healthy")) != "healthy":
                    return False
                if hero.get("current_quest"):
                    return False
    if last_cmd is not None and cmd == last_cmd and cmd.get("cmd") != "step_ticks":
        return False
    return True


async def execute_scenario_commands(reader, writer, scenario: dict) -> dict:
    max_ticks = int(scenario.get("max_ticks", 0))
    for cmd in scenario.get("commands", []):
        resp = await tcp_cmd(reader, writer, cmd)
        print(f"[scripted] {cmd['cmd']}: {resp}")

    assertions = scenario.get("assertions", [])
    if any(a.get("assert") in {"hero_count_gte", "any_hero_state"} for a in assertions):
        resp = await tcp_cmd(
            reader, writer, {"cmd": "run_until", "event": "hero_arrived_at_tavern", "max_ticks": max_ticks}
        )
        print(f"[scripted] run_until: {resp}")
        if max_ticks > 0:
            resp = await tcp_cmd(reader, writer, {"cmd": "step_ticks", "n": max_ticks})
            print(f"[scripted] step_ticks: {resp}")
    elif max_ticks > 0:
        resp = await tcp_cmd(reader, writer, {"cmd": "step_ticks", "n": max_ticks})
        print(f"[scripted] step_ticks: {resp}")

    final = await tcp_cmd(reader, writer, {"cmd": "get_world_state"})
    return final.get("result", {})


async def run_scripted(reader, writer, scenario: dict) -> dict:
    seed = scenario.get("seed", 42)
    resp = await tcp_cmd(reader, writer, {"cmd": "reset_world", "seed": seed})
    print(f"[scripted] reset_world: {resp}")
    return await execute_scenario_commands(reader, writer, scenario)


async def run_llm(reader, writer, scenario: dict, model: str, api_kind: str, api_url: str) -> dict:
    goal = scenario.get("goal", "Run the scenario.")
    assertions = scenario.get("assertions", [])
    history = []
    last_cmd = None

    await tcp_cmd(reader, writer, {"cmd": "reset_world", "seed": scenario.get("seed", 42)})
    if scenario.get("llm_bootstrap_commands", False) or int(scenario.get("max_ticks", 0)) == 0:
        for cmd in scenario.get("commands", []):
            resp = await tcp_cmd(reader, writer, cmd)
            history.append({"role": "assistant", "content": json.dumps({"command": cmd, "response": resp})})

    for turn in range(MAX_LLM_TURNS):
        state_resp = await tcp_cmd(reader, writer, {"cmd": "get_world_state"})
        state = state_resp.get("result", {})
        passed, failures = check_assertions(assertions, state)

        print(
            f"[turn {turn + 1}] tick={state.get('tick', 0)} "
            f"heroes={len(state.get('heroes', []))} "
            f"buildings={len(state.get('buildings', []))}"
        )

        if passed:
            print("[LLM] all assertions passed!")
            return state

        llm_cmd = ask_llm(model, goal, state, history, failures, api_kind, api_url)
        cmd = normalize_command(llm_cmd)
        if not is_useful_command(cmd, state, last_cmd, failures):
            cmd = choose_fallback_command(state, failures)
            print(f"[LLM] fallback cmd: {json.dumps(cmd)}")
        else:
            print(f"[LLM] cmd: {json.dumps(cmd)}")

        resp = await tcp_cmd(reader, writer, cmd)
        print(f"[LLM] resp: {json.dumps(resp)}")

        history.append(
            {
                "role": "assistant",
                "content": json.dumps({"command": cmd, "response": resp}),
            }
        )
        last_cmd = cmd

    final = await tcp_cmd(reader, writer, {"cmd": "get_world_state"})
    return final.get("result", {})


async def main(args):
    scenario_path = Path(args.scenario)
    with open(scenario_path, encoding="utf-8") as handle:
        scenario = json.load(handle)
    tcp_port = choose_port(args.port)

    print(f"[driver] scenario : {scenario.get('name', '?')}")
    print(f"[driver] goal     : {scenario.get('goal', '(none)')}")
    print(f"[driver] model    : {'--no-llm (scripted)' if args.no_llm else args.model}")
    print(f"[driver] backend  : {args.api_kind} @ {args.api_url}")
    print(f"[driver] tcp port : {tcp_port}")

    reader_holder = []
    writer_holder = []
    connected = asyncio.Event()

    async def handler(reader, writer):
        reader_holder.append(reader)
        writer_holder.append(writer)
        connected.set()

    server = await asyncio.start_server(handler, "127.0.0.1", tcp_port)
    print(f"[driver] TCP server listening on 127.0.0.1:{tcp_port}")

    godot_cmd = [
        GODOT_EXE,
        "--headless",
        "--path",
        PROJECT_DIR,
        "--",
        "--mode=headless",
        f"--port={tcp_port}",
        f"--seed={scenario.get('seed', 42)}",
    ]
    print("[driver] launching Godot...")
    proc = subprocess.Popen(godot_cmd)

    try:
        print("[driver] waiting for Godot to connect...")
        try:
            await asyncio.wait_for(connected.wait(), timeout=CONNECT_TIMEOUT)
        except asyncio.TimeoutError:
            print("[driver] FAILED: Godot did not connect in time.", file=sys.stderr)
            sys.exit(1)

        reader = reader_holder[0]
        writer = writer_holder[0]
        print("[driver] Godot connected - starting scenario")

        if args.no_llm:
            final_state = await run_scripted(reader, writer, scenario)
        else:
            final_state = await run_llm(reader, writer, scenario, args.model, args.api_kind, args.api_url)

        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass

        passed, failures = check_assertions(scenario.get("assertions", []), final_state)
        balance_report = build_balance_report(final_state, scenario)
        llm_analysis = None
        if args.analysis_llm:
            llm_analysis = ask_llm_analysis(args.model, scenario, balance_report, args.api_kind, args.api_url)
        result = {
            "scenario": scenario.get("name", "?"),
            "passed": passed,
            "tick": final_state.get("tick", 0),
            "heroes": len(final_state.get("heroes", [])),
            "buildings": len(final_state.get("buildings", [])),
            "failures": failures,
            "balance_report": balance_report,
        }
        if llm_analysis is not None:
            result["llm_analysis"] = llm_analysis
        print(f"[analysis] {balance_report['summary']}")
        print(json.dumps(result, indent=2))
        sys.exit(0 if passed else 1)

    finally:
        server.close()
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="QuestTown LLM Driver")
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Model name for the selected backend")
    parser.add_argument("--api-kind", choices=["ollama", "openai"], default="ollama", help="LLM API backend")
    parser.add_argument("--api-url", default=OLLAMA_URL, help="LLM API endpoint URL")
    parser.add_argument("--port", type=int, default=0, help="TCP port for Godot callback; 0 chooses a free port")
    parser.add_argument("--no-llm", action="store_true", help="Use scripted sequence instead of LLM")
    parser.add_argument("--analysis-llm", action="store_true", help="Ask the LLM for a post-run balance assessment")
    asyncio.run(main(parser.parse_args()))
