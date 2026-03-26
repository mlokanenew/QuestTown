#!/usr/bin/env python3
"""
QuestTown LLM Driver
====================
Launches Godot headless, connects via WebSocket, and uses a local Ollama LLM
to drive the simulation toward a scenario goal.

Requirements:
  pip install websockets requests
  ollama serve   (in another terminal)
  ollama pull llama3

Usage:
  python tools/llm_driver.py --scenario tests/scenarios/tavern_spawn.json
  python tools/llm_driver.py --scenario tests/scenarios/tavern_spawn.json --model qwen2.5:7b
  python tools/llm_driver.py --scenario tests/scenarios/tavern_spawn.json --no-llm
      (--no-llm runs a hardcoded scripted sequence — useful when Ollama is not running)
"""

import argparse
import asyncio
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import requests
import websockets

# ── Configuration ─────────────────────────────────────────────────────────────

GODOT_EXE = r"C:\Users\mloka\Downloads\Godot_v4.6.1-stable_win64.exe"
PROJECT_DIR = str(Path(__file__).parent.parent)
WS_PORT = 8765
OLLAMA_URL = "http://localhost:11434/api/chat"
DEFAULT_MODEL = "llama3:8b"
CONNECT_TIMEOUT = 15  # seconds to wait for Godot to start
MAX_LLM_TURNS = 20    # safety cap on LLM iterations

SYSTEM_PROMPT = """You are an AI controlling a medieval town-builder game called QuestTown.
You receive the current world state as JSON and a goal.
You must output EXACTLY ONE JSON command object and nothing else.

Available commands:
  {"cmd":"reset_world","seed":42}
  {"cmd":"place_building","type":"tavern","x":0,"z":0}
  {"cmd":"step_ticks","n":600}
  {"cmd":"get_world_state"}
  {"cmd":"run_until","event":"hero_arrived_at_tavern","max_ticks":1800}

Rules:
- Output only a raw JSON object, no markdown, no explanation.
- If a tavern is not placed yet and the goal requires heroes, place one first.
- After placing a building, use step_ticks or run_until to advance time.
"""

# ── Helpers ───────────────────────────────────────────────────────────────────

def load_scenario(path: str) -> dict:
    with open(path) as f:
        return json.load(f)

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

async def wait_for_godot(port: int, timeout: int) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            async with websockets.connect(f"ws://127.0.0.1:{port}", open_timeout=2):
                return True
        except Exception:
            await asyncio.sleep(0.5)
    return False

async def ws_cmd(ws, cmd: dict) -> dict:
    await ws.send(json.dumps(cmd))
    raw = await asyncio.wait_for(ws.recv(), timeout=30)
    return json.loads(raw)

def ask_llm(model: str, goal: str, state: dict, history: list) -> dict | None:
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    messages.extend(history)
    user_msg = f"Goal: {goal}\n\nCurrent world state:\n{json.dumps(state, indent=2)}\n\nWhat is your next command?"
    messages.append({"role": "user", "content": user_msg})

    try:
        resp = requests.post(
            OLLAMA_URL,
            json={"model": model, "messages": messages, "stream": False},
            timeout=60,
        )
        resp.raise_for_status()
        content = resp.json()["message"]["content"].strip()
        # Strip markdown fences if present
        if content.startswith("```"):
            lines = content.split("\n")
            content = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
        return json.loads(content)
    except Exception as e:
        print(f"[LLM] error: {e}", file=sys.stderr)
        return None

# ── Scripted fallback (no LLM) ────────────────────────────────────────────────

async def run_scripted(ws, scenario: dict) -> dict:
    """Simple deterministic sequence for CI without Ollama."""
    seed = scenario.get("seed", 42)
    max_ticks = scenario.get("max_ticks", 3600)

    await ws_cmd(ws, {"cmd": "reset_world", "seed": seed})
    await ws_cmd(ws, {"cmd": "place_building", "type": "tavern", "x": 0, "z": 0})
    resp = await ws_cmd(ws, {"cmd": "run_until", "event": "hero_arrived_at_tavern", "max_ticks": max_ticks})
    print(f"[scripted] run_until result: {resp}")
    r = await ws_cmd(ws, {"cmd": "get_world_state"})
    return r.get("result", {})

# ── LLM-driven loop ───────────────────────────────────────────────────────────

async def run_llm(ws, scenario: dict, model: str) -> dict:
    goal = scenario.get("goal", "Run the scenario.")
    assertions = scenario.get("assertions", [])
    history = []

    # Initial reset
    await ws_cmd(ws, {"cmd": "reset_world", "seed": scenario.get("seed", 42)})

    for turn in range(MAX_LLM_TURNS):
        state_resp = await ws_cmd(ws, {"cmd": "get_world_state"})
        state = state_resp.get("result", {})
        print(f"[turn {turn+1}] tick={state.get('tick', 0)} heroes={len(state.get('heroes', []))} buildings={len(state.get('buildings', []))}")

        passed, failures = check_assertions(assertions, state)
        if passed:
            print("[LLM] all assertions passed!")
            return state

        cmd = ask_llm(model, goal, state, history)
        if cmd is None:
            print("[LLM] no valid command returned, stopping.", file=sys.stderr)
            break

        print(f"[LLM] command: {json.dumps(cmd)}")
        history.append({"role": "assistant", "content": json.dumps(cmd)})

        resp = await ws_cmd(ws, cmd)
        print(f"[LLM] response: {json.dumps(resp)}")

    # Final state
    r = await ws_cmd(ws, {"cmd": "get_world_state"})
    return r.get("result", {})

# ── Main ──────────────────────────────────────────────────────────────────────

async def main(args):
    scenario = load_scenario(args.scenario)
    print(f"[driver] scenario: {scenario.get('name', '?')}")
    print(f"[driver] goal: {scenario.get('goal', '(none)')}")

    # Launch Godot headless
    godot_cmd = [
        GODOT_EXE,
        "--headless",
        "--path", PROJECT_DIR,
        "--",
        f"--mode=headless",
        f"--port={WS_PORT}",
        f"--seed={scenario.get('seed', 42)}",
    ]
    print(f"[driver] launching Godot: {' '.join(godot_cmd)}")
    proc = subprocess.Popen(godot_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    try:
        print(f"[driver] waiting for Godot on port {WS_PORT}...")
        connected = await wait_for_godot(WS_PORT, CONNECT_TIMEOUT)
        if not connected:
            print("[driver] FAILED: Godot did not start in time.", file=sys.stderr)
            sys.exit(1)

        async with websockets.connect(f"ws://127.0.0.1:{WS_PORT}") as ws:
            if args.no_llm:
                final_state = await run_scripted(ws, scenario)
            else:
                final_state = await run_llm(ws, scenario, args.model)

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
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="QuestTown LLM Driver")
    parser.add_argument("--scenario", required=True, help="Path to scenario JSON file")
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Ollama model name")
    parser.add_argument("--no-llm", action="store_true", help="Use scripted sequence instead of LLM")
    args = parser.parse_args()
    asyncio.run(main(args))
