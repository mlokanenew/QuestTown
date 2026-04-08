#!/usr/bin/env python3
"""
Run the blocker-route-resource loop over multiple seeds using the deterministic
heuristic driver and emit an aggregated progression report.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_SCENARIO = "tests/scenarios/mvp_route_progression_heuristic.json"


def average(values: list[float]) -> float:
    return round(sum(values) / len(values), 2) if values else 0.0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", default=DEFAULT_SCENARIO)
    parser.add_argument("--seeds", type=int, default=8)
    parser.add_argument("--seed-start", type=int, default=1)
    parser.add_argument("--json-out", default="")
    args = parser.parse_args()

    scenario_path = PROJECT_DIR / args.scenario
    scenario = json.loads(scenario_path.read_text(encoding="utf-8"))

    runs: list[dict] = []
    first_blockers: list[int] = []
    first_clears: list[int] = []
    first_unlocks: list[int] = []
    first_installs: list[int] = []
    reblocks: list[int] = []
    open_routes: list[int] = []
    utilization: list[float] = []
    final_gold: list[int] = []
    success_rates: list[float] = []

    for seed in range(args.seed_start, args.seed_start + args.seeds):
        scenario["seed"] = seed
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as scenario_handle:
            json.dump(scenario, scenario_handle, indent=2)
            scenario_run_path = Path(scenario_handle.name)
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as result_handle:
            result_path = Path(result_handle.name)

        cmd = [
            sys.executable,
            "tools/llm_driver.py",
            "--scenario",
            str(scenario_run_path),
            "--heuristic",
            "--json-out",
            str(result_path),
        ]
        proc = subprocess.run(cmd, cwd=PROJECT_DIR, capture_output=True, text=True)
        if proc.returncode != 0:
            print(proc.stdout)
            print(proc.stderr, file=sys.stderr)
            return proc.returncode

        result = json.loads(result_path.read_text(encoding="utf-8"))
        balance = result.get("balance_report", {})
        progression = balance.get("progression", {})
        quests = balance.get("quests", {})
        economy = balance.get("economy", {})

        runs.append(
            {
                "seed": seed,
                "passed": bool(result.get("passed", False)),
                "tick": int(result.get("tick", 0)),
                "verdict": balance.get("verdict", "unknown"),
                "summary": balance.get("summary", ""),
                "progression": progression,
            }
        )

        if progression.get("first_blocker_discovered_tick", -1) >= 0:
            first_blockers.append(int(progression["first_blocker_discovered_tick"]))
        if progression.get("first_route_cleared_tick", -1) >= 0:
            first_clears.append(int(progression["first_route_cleared_tick"]))
        if progression.get("first_resource_unlocked_tick", -1) >= 0:
            first_unlocks.append(int(progression["first_resource_unlocked_tick"]))
        if progression.get("first_resource_installed_tick", -1) >= 0:
            first_installs.append(int(progression["first_resource_installed_tick"]))
        reblocks.append(int(progression.get("route_reblock_count", 0)))
        open_routes.append(int(progression.get("active_open_routes", 0)))
        utilization.append(float(progression.get("hero_utilization_ratio", 0.0)))
        final_gold.append(int(economy.get("current_gold", 0)))
        success_rates.append(float(quests.get("success_rate", 0.0)))

        scenario_run_path.unlink(missing_ok=True)
        result_path.unlink(missing_ok=True)

    payload = {
        "scenario": args.scenario,
        "seeds": args.seeds,
        "seed_start": args.seed_start,
        "aggregate": {
            "avg_first_blocker_discovered_tick": average(first_blockers),
            "avg_first_route_cleared_tick": average(first_clears),
            "avg_first_resource_unlocked_tick": average(first_unlocks),
            "avg_first_resource_installed_tick": average(first_installs),
            "avg_route_reblock_count": average(reblocks),
            "avg_active_open_routes": average(open_routes),
            "avg_hero_utilization_ratio": average(utilization),
            "avg_final_town_gold": average(final_gold),
            "avg_quest_success_rate": average(success_rates),
        },
        "runs": runs,
    }

    if args.json_out:
        out_path = Path(args.json_out)
        if not out_path.is_absolute():
            out_path = PROJECT_DIR / out_path
        out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
