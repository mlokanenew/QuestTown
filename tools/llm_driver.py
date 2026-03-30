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
DEFAULT_MODEL = "phi3:mini"
CONNECT_TIMEOUT = 30
MAX_LLM_TURNS = 24
OLLAMA_TIMEOUT = 12
STARTING_GOLD = 500
RUN_UNTIL_EVENTS = {
    "hero_arrived_at_tavern",
    "hero_departed_for_quest",
    "hero_completed_quest",
    "hero_heading_home",
    "hero_returned_from_quest",
    "hero_spent_at_tavern",
    "hero_spent_at_weapons_shop",
    "hero_spent_at_temple",
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
{"cmd":"set_quest_enabled","id":"clear_rats_cellar","enabled":true}
{"cmd":"step_ticks","n":600}
{"cmd":"run_until","event":"hero_arrived_at_tavern","max_ticks":1800}
{"cmd":"get_world_state"}

Rules:
1. Never place a building if one of that type already exists.
2. Prefer run_until or step_ticks once the needed building is placed.
3. If the world is already close to satisfying the goal, advance time instead of placing more buildings.
4. Output JSON only."""

ANALYSIS_PROMPT = """You are reviewing a fantasy town-sim MVP test run.

Judge whether the loop hangs together across economy, injuries, quest outcomes, and progression.
Be concrete. Call out if the game looks too easy, too hard, too rich, too poor, too safe, or too punishing.
Use the provided metrics and flags only. Do not invent missing data.

Return JSON only:
{
  "summary": "short overall judgment",
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
        elif kind == "event_type_seen":
            target = assertion.get("value", "")
            if not any(event.get("type", "") == target for event in state.get("events", [])):
                failures.append(assertion)
        elif kind == "quest_templates_only":
            allowed = set(assertion.get("value", []))
            quests = state.get("quests", [])
            if not quests or any(quest.get("template_id", "") not in allowed for quest in quests):
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
    return len(failures) == 0, failures


def choose_port(port_arg: int) -> int:
    if port_arg > 0:
        return port_arg
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


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
    current_gold = int(state.get("gold", 0))
    town_profit = current_gold - STARTING_GOLD

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
    }

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
    }

    severe_flags: list[str] = []
    moderate_flags: list[str] = []

    if len(completed) == 0:
        severe_flags.append("no_completed_quests")
    if not loop_health["loop_closed"]:
        severe_flags.append("loop_not_closing")
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
        elif success_rate > 0.95:
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
    elif heroes and average(hero_hp_ratios) > 0.98 and len(completed) >= 3:
        moderate_flags.append("party_almost_never_takes_damage")

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
    severe = report.get("flags", {}).get("severe", [])
    moderate = report.get("flags", {}).get("moderate", [])
    if severe:
        parts.append("severe=" + ",".join(severe))
    elif moderate:
        parts.append("watch=" + ",".join(moderate[:3]))
    return "; ".join(parts)


def ask_llm(model: str, goal: str, state: dict, history: list, failures: list) -> dict | None:
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
        resp = requests.post(
            OLLAMA_URL,
            json={"model": model, "messages": messages, "stream": False},
            timeout=OLLAMA_TIMEOUT,
        )
        resp.raise_for_status()
        content = resp.json()["message"]["content"].strip()
        print(f"[LLM] raw: {content[:200]}")
        return extract_command(content)
    except Exception as exc:
        print(f"[LLM] error: {exc}", file=sys.stderr)
        return None


def ask_llm_analysis(model: str, scenario: dict, report: dict) -> dict | None:
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
        resp = requests.post(
            OLLAMA_URL,
            json={"model": model, "messages": messages, "stream": False},
            timeout=OLLAMA_TIMEOUT,
        )
        resp.raise_for_status()
        content = resp.json()["message"]["content"].strip()
        print(f"[LLM-analysis] raw: {content[:300]}")
        decoder = json.JSONDecoder()
        cleaned = content.replace("```json", "").replace("```", "").strip()
        parsed, _ = decoder.raw_decode(cleaned)
        if isinstance(parsed, dict):
            return parsed
    except Exception as exc:
        print(f"[LLM-analysis] error: {exc}", file=sys.stderr)
    return None


def extract_command(text: str) -> dict | None:
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
        if isinstance(obj, dict) and "cmd" in obj:
            return obj
        if isinstance(obj, dict) and isinstance(obj.get("command"), dict) and "cmd" in obj["command"]:
            return obj["command"]
        idx = brace + max(end, 1)

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
    return {
        "tick": state.get("tick", 0),
        "gold": state.get("gold", 0),
        "buildings": [
            {
                "type": building.get("type"),
                "level": building.get("level", 1),
            }
            for building in state.get("buildings", [])
        ],
        "heroes": [
            {
                "name": hero.get("name"),
                "state": hero.get("state"),
                "level": hero.get("level", 1),
                "current_quest": hero.get("current_quest", {}).get("name", ""),
            }
            for hero in state.get("heroes", [])
        ],
        "quests": [
            {
                "id": quest.get("template_id", quest.get("id", "")),
                "name": quest.get("name", ""),
                "type": quest.get("type", ""),
                "difficulty": quest.get("difficulty", 1),
            }
            for quest in state.get("quests", [])
        ],
        "quest_summary": {
            "completed": len(completed),
            "successes": sum(1 for quest in completed if bool(quest.get("success", False))),
            "wounded_returns": sum(1 for quest in completed if str(quest.get("wound_state", "healthy")) != "healthy"),
        },
        "recent_events": state.get("events", [])[-8:],
    }


def choose_fallback_command(state: dict, failures: list) -> dict:
    buildings = state.get("buildings", [])
    building_types = {building.get("type") for building in buildings}
    building_levels = {building.get("type"): int(building.get("level", 1)) for building in buildings}
    heroes = state.get("heroes", [])
    required_buildings = set()

    for failure in failures:
        kind = failure.get("assert", "")
        if kind == "gold_gte":
            required_buildings.update({"tavern", "weapons_shop", "temple"})
        if kind == "quest_count_gte" or kind == "quest_templates_only":
            required_buildings.add("tavern")
        if kind == "event_type_seen":
            event_type = failure.get("value", "")
            if event_type == "hero_spent_at_tavern":
                required_buildings.add("tavern")
            elif event_type == "hero_spent_at_weapons_shop":
                required_buildings.add("weapons_shop")
            elif event_type == "hero_spent_at_temple":
                required_buildings.add("temple")

    for building_type in ("tavern", "weapons_shop", "temple"):
        if building_type in required_buildings and building_type not in building_types:
            placement = {
                "tavern": {"x": 0, "z": 0},
                "weapons_shop": {"x": 3, "z": 0},
                "temple": {"x": -3, "z": 0},
            }[building_type]
            return {"cmd": "place_building", "type": building_type, **placement}

    for failure in failures:
        kind = failure.get("assert", "")
        if kind in {"hero_count_gte", "any_hero_state"}:
            if "tavern" not in building_types:
                return {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0}
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
            return {"cmd": "step_ticks", "n": 300}
        if kind == "quest_templates_only":
            if "tavern" not in building_types:
                return {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0}
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
            if not heroes:
                return {"cmd": "run_until", "event": "hero_arrived_at_tavern", "max_ticks": 1800}
            if event_type == "hero_started_quest":
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

    if "tavern" not in building_types:
        return {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0}
    if not heroes:
        return {"cmd": "run_until", "event": "hero_arrived_at_tavern", "max_ticks": 1800}
    return {"cmd": "step_ticks", "n": 300}


def is_useful_command(cmd: dict, state: dict, last_cmd: dict | None, failures: list) -> bool:
    if cmd is None:
        return False

    buildings = state.get("buildings", [])
    building_types = {building.get("type") for building in buildings}
    required_buildings = set()
    for failure in failures:
        kind = failure.get("assert", "")
        if kind in {"quest_count_gte", "quest_templates_only"}:
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


async def run_llm(reader, writer, scenario: dict, model: str) -> dict:
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

        llm_cmd = ask_llm(model, goal, state, history, failures)
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
            final_state = await run_llm(reader, writer, scenario, args.model)

        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass

        passed, failures = check_assertions(scenario.get("assertions", []), final_state)
        balance_report = build_balance_report(final_state, scenario)
        llm_analysis = None
        if args.analysis_llm:
            llm_analysis = ask_llm_analysis(args.model, scenario, balance_report)
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
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Ollama model name")
    parser.add_argument("--port", type=int, default=0, help="TCP port for Godot callback; 0 chooses a free port")
    parser.add_argument("--no-llm", action="store_true", help="Use scripted sequence instead of LLM")
    parser.add_argument("--analysis-llm", action="store_true", help="Ask the LLM for a post-run balance assessment")
    asyncio.run(main(parser.parse_args()))
