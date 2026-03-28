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
  ollama serve   (in another terminal, already running)

Usage:
  python tools/llm_driver.py --scenario tests/scenarios/tavern_spawn.json
  python tools/llm_driver.py --scenario tests/scenarios/tavern_spawn.json --model phi3:mini
  python tools/llm_driver.py --scenario tests/scenarios/tavern_spawn.json --no-llm
"""

import argparse
import asyncio
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import requests

# ── Configuration ─────────────────────────────────────────────────────────────

GODOT_EXE = r"C:\Users\mloka\Downloads\godot_extracted\Godot_v4.6.1-stable_win64_console.exe"
PROJECT_DIR = str(Path(__file__).parent.parent)
TCP_PORT = 8765
OLLAMA_URL = "http://localhost:11434/api/chat"
DEFAULT_MODEL = "phi3:mini"
CONNECT_TIMEOUT = 30  # seconds to wait for Godot to connect back
MAX_LLM_TURNS = 20

SYSTEM_PROMPT = """You control a medieval town-builder game. Output ONE JSON command, nothing else.

Commands:
  {"cmd":"place_building","type":"tavern","x":0,"z":0}
  {"cmd":"step_ticks","n":600}
  {"cmd":"run_until","event":"hero_arrived_at_tavern","max_ticks":1800}
  {"cmd":"get_world_state"}
  {"cmd":"reset_world","seed":42}

Strategy:
1. If no tavern exists, place one with place_building.
2. After placing, use run_until to wait for a hero to arrive.
3. Output ONLY the JSON object. No text before or after it."""

# ── TCP helpers ────────────────────────────────────────────────────────────────

async def tcp_cmd(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, cmd: dict) -> dict:
    """Send one JSON command, receive one JSON response."""
    line = json.dumps(cmd) + "\n"
    writer.write(line.encode())
    await writer.drain()
    raw = await asyncio.wait_for(reader.readline(), timeout=120)
    if not raw:
        raise ConnectionError("Godot closed the connection")
    return json.loads(raw.decode().strip())

# ── Assertion checker ──────────────────────────────────────────────────────────

def check_assertions(assertions: list, state: dict) -> tuple[bool, list]:
    failures = []
    for a in assertions:
        kind = a.get("assert", "")
        if kind == "hero_count_gte":
            if len(state.get("heroes", [])) < a.get("value", 1):
                failures.append(a)
        elif kind == "any_hero_state":
            target = a.get("value", "")
            if not any(h["state"] == target for h in state.get("heroes", [])):
                failures.append(a)
        elif kind == "building_count_gte":
            if len(state.get("buildings", [])) < a.get("value", 1):
                failures.append(a)
    return len(failures) == 0, failures

# ── LLM call ──────────────────────────────────────────────────────────────────

def ask_llm(model: str, goal: str, state: dict, history: list) -> dict | None:
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    messages.extend(history)
    user_msg = (
        f"Goal: {goal}\n\n"
        f"Current world state:\n{json.dumps(state, indent=2)}\n\n"
        f"What is your next command?"
    )
    messages.append({"role": "user", "content": user_msg})

    try:
        resp = requests.post(
            OLLAMA_URL,
            json={"model": model, "messages": messages, "stream": False},
            timeout=90,
        )
        resp.raise_for_status()
        content = resp.json()["message"]["content"].strip()
        print(f"[LLM] raw: {content[:200]}")
        return _extract_json(content)
    except Exception as e:
        print(f"[LLM] error: {e}", file=sys.stderr)
        return None


def _extract_json(text: str) -> dict | None:
    """Extract first JSON object from model output, tolerating surrounding text."""
    text = re.sub(r"```[a-z]*\n?", "", text).strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    match = re.search(r"\{[^{}]*\}", text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group())
        except json.JSONDecodeError:
            pass
    print(f"[LLM] could not parse JSON from: {text[:200]}", file=sys.stderr)
    return None

# ── Scripted fallback (no LLM) ─────────────────────────────────────────────────

async def run_scripted(reader, writer, scenario: dict) -> dict:
    """Deterministic sequence — useful for CI without Ollama."""
    seed = scenario.get("seed", 42)
    max_ticks = scenario.get("max_ticks", 3600)

    r = await tcp_cmd(reader, writer, {"cmd": "reset_world", "seed": seed})
    print(f"[scripted] reset_world: {r}")
    r = await tcp_cmd(reader, writer, {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0})
    print(f"[scripted] place_building: {r}")
    r = await tcp_cmd(reader, writer, {"cmd": "run_until", "event": "hero_arrived_at_tavern", "max_ticks": max_ticks})
    print(f"[scripted] run_until: {r}")
    r = await tcp_cmd(reader, writer, {"cmd": "get_world_state"})
    return r.get("result", {})

# ── LLM-driven loop ────────────────────────────────────────────────────────────

async def run_llm(reader, writer, scenario: dict, model: str) -> dict:
    goal = scenario.get("goal", "Run the scenario.")
    assertions = scenario.get("assertions", [])
    history = []

    await tcp_cmd(reader, writer, {"cmd": "reset_world", "seed": scenario.get("seed", 42)})

    for turn in range(MAX_LLM_TURNS):
        state_resp = await tcp_cmd(reader, writer, {"cmd": "get_world_state"})
        state = state_resp.get("result", {})
        print(f"[turn {turn+1}] tick={state.get('tick',0)} "
              f"heroes={len(state.get('heroes',[]))} "
              f"buildings={len(state.get('buildings',[]))}")

        passed, _ = check_assertions(assertions, state)
        if passed:
            print("[LLM] all assertions passed!")
            return state

        cmd = ask_llm(model, goal, state, history)
        if cmd is None:
            print("[LLM] no valid command, stopping.", file=sys.stderr)
            break

        print(f"[LLM] cmd: {json.dumps(cmd)}")
        history.append({"role": "assistant", "content": json.dumps(cmd)})

        resp = await tcp_cmd(reader, writer, cmd)
        print(f"[LLM] resp: {json.dumps(resp)}")

    r = await tcp_cmd(reader, writer, {"cmd": "get_world_state"})
    return r.get("result", {})

# ── Main ───────────────────────────────────────────────────────────────────────

async def main(args):
    scenario_path = Path(args.scenario)
    with open(scenario_path) as f:
        scenario = json.load(f)
    print(f"[driver] scenario : {scenario.get('name', '?')}")
    print(f"[driver] goal     : {scenario.get('goal', '(none)')}")
    print(f"[driver] model    : {'--no-llm (scripted)' if args.no_llm else args.model}")

    # Start listening BEFORE launching Godot so Godot can connect immediately on startup
    reader_holder = []
    writer_holder = []
    connected = asyncio.Event()

    async def _handler(r, w):
        reader_holder.append(r)
        writer_holder.append(w)
        connected.set()

    server = await asyncio.start_server(_handler, "127.0.0.1", TCP_PORT)
    print(f"[driver] TCP server listening on 127.0.0.1:{TCP_PORT}")

    godot_cmd = [
        GODOT_EXE, "--headless", "--path", PROJECT_DIR,
        "--", "--mode=headless", f"--port={TCP_PORT}", f"--seed={scenario.get('seed', 42)}",
    ]
    print(f"[driver] launching Godot…")
    proc = subprocess.Popen(godot_cmd)

    try:
        print(f"[driver] waiting for Godot to connect…")
        try:
            await asyncio.wait_for(connected.wait(), timeout=CONNECT_TIMEOUT)
        except asyncio.TimeoutError:
            print("[driver] FAILED: Godot did not connect in time.", file=sys.stderr)
            sys.exit(1)

        reader = reader_holder[0]
        writer = writer_holder[0]
        print("[driver] Godot connected — starting scenario")

        if args.no_llm:
            final_state = await run_scripted(reader, writer, scenario)
        else:
            final_state = await run_llm(reader, writer, scenario, args.model)

        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass

        assertions = scenario.get("assertions", [])
        passed, failures = check_assertions(assertions, final_state)
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
    parser.add_argument("--model", default=DEFAULT_MODEL,
                        help="Ollama model (available: phi3:mini, llava:13b)")
    parser.add_argument("--no-llm", action="store_true",
                        help="Use scripted sequence instead of LLM")
    args = parser.parse_args()
    asyncio.run(main(args))
