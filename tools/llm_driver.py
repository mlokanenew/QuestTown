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
MAX_LLM_TURNS = 16
OLLAMA_TIMEOUT = 12

SYSTEM_PROMPT = """You control a medieval town-builder game test harness.

Return exactly ONE JSON object and nothing else.

Allowed commands:
{"cmd":"place_building","type":"tavern","x":0,"z":0}
{"cmd":"place_building","type":"weapons_shop","x":3,"z":0}
{"cmd":"place_building","type":"temple","x":-3,"z":0}
{"cmd":"upgrade_building","type":"tavern"}
{"cmd":"upgrade_building","type":"weapons_shop"}
{"cmd":"upgrade_building","type":"temple"}
{"cmd":"set_quest_enabled","id":"clear_wolves","enabled":true}
{"cmd":"step_ticks","n":600}
{"cmd":"run_until","event":"hero_arrived_at_tavern","max_ticks":1800}
{"cmd":"get_world_state"}

Rules:
1. Never place a building if one of that type already exists.
2. Prefer run_until or step_ticks once the needed building is placed.
3. If the world is already close to satisfying the goal, advance time instead of placing more buildings.
4. Output JSON only."""


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
        elif kind == "quest_count_gte":
            if len(state.get("quests", [])) < assertion.get("value", 1):
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
        elif kind == "gold_eq":
            if int(gold) != int(assertion.get("value", gold)):
                failures.append(assertion)
        elif kind == "gold_gte":
            if int(gold) < int(assertion.get("value", 0)):
                failures.append(assertion)
        elif kind == "event_type_seen":
            target = assertion.get("value", "")
            if not any(event.get("type", "") == target for event in state.get("events", [])):
                failures.append(assertion)
    return len(failures) == 0, failures


def choose_port(port_arg: int) -> int:
    if port_arg > 0:
        return port_arg
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


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
    if name == "step_ticks":
        n = max(1, min(int(cmd.get("n", 60)), 3600))
        return {"cmd": "step_ticks", "n": n}
    if name == "set_quest_enabled":
        quest_id = str(cmd.get("id", ""))
        if not quest_id:
            return None
        return {"cmd": "set_quest_enabled", "id": quest_id, "enabled": bool(cmd.get("enabled", True))}
    if name == "run_until":
        event = cmd.get("event", "hero_arrived_at_tavern")
        if event not in {"hero_arrived_at_tavern"}:
            event = "hero_arrived_at_tavern"
        max_ticks = max(1, min(int(cmd.get("max_ticks", 1800)), 7200))
        return {"cmd": "run_until", "event": event, "max_ticks": max_ticks}
    if name == "get_world_state":
        return {"cmd": "get_world_state"}
    return None


def summarize_state_for_llm(state: dict) -> dict:
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
                return {"cmd": "step_ticks", "n": 600}
            if event_type in {"hero_completed_quest", "hero_returned_from_quest"}:
                return {"cmd": "step_ticks", "n": 1200}
            if event_type in {"hero_spent_at_tavern", "hero_spent_at_weapons_shop", "hero_spent_at_temple"}:
                return {"cmd": "step_ticks", "n": 900}
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


def is_useful_command(cmd: dict, state: dict, last_cmd: dict | None) -> bool:
    if cmd is None:
        return False

    buildings = state.get("buildings", [])
    building_types = {building.get("type") for building in buildings}
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
        if not is_useful_command(cmd, state, last_cmd):
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
        result = {
            "scenario": scenario.get("name", "?"),
            "passed": passed,
            "tick": final_state.get("tick", 0),
            "heroes": len(final_state.get("heroes", [])),
            "buildings": len(final_state.get("buildings", [])),
            "failures": failures,
        }
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
    asyncio.run(main(parser.parse_args()))
