#!/usr/bin/env python3
"""
QuestTown regression suite runner.

Runs what we can verify locally in one pass:
- Godot headless boot / parse check
- scripted scenario sweep through llm_driver.py --no-llm
- optional rendered UI snapshot sweep
- optional LLM smoke scenario

Usage:
  python tools/run_regression_suite.py
  python tools/run_regression_suite.py --include-ui-snapshots
  python tools/run_regression_suite.py --include-llm --llm-model qwen2.5-coder:7b
  python tools/run_regression_suite.py --json-out regression_results.json
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_GODOT = Path(r"C:\Users\mloka\Downloads\godot_extracted\Godot_v4.6.1-stable_win64.exe")
DEFAULT_LLM_MODEL = "qwen2.5-coder:7b"
DEFAULT_LLM_SCENARIO = "tests/scenarios/mvp_full_loop.json"
DEFAULT_UI_SNAPSHOT_DIR = "artifacts/ui_snapshots_regression"
DEFAULT_LLM_API_KIND = "ollama"
DEFAULT_LLM_API_URL = "http://localhost:11434/api/chat"


@dataclass
class StepResult:
    name: str
    ok: bool
    duration_s: float
    command: list[str]
    stdout_tail: str
    stderr_tail: str


def tail(text: str, max_lines: int = 20) -> str:
    lines = [line for line in text.splitlines() if line.strip()]
    return "\n".join(lines[-max_lines:])


def run_step(name: str, command: list[str], timeout_s: int) -> StepResult:
    started = time.time()
    proc = subprocess.run(
        command,
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=timeout_s,
    )
    duration = time.time() - started
    return StepResult(
        name=name,
        ok=(proc.returncode == 0),
        duration_s=duration,
        command=command,
        stdout_tail=tail(proc.stdout),
        stderr_tail=tail(proc.stderr),
    )


def discover_scenarios(pattern: str) -> list[Path]:
    return sorted(PROJECT_DIR.glob(pattern))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot-exe", default=str(DEFAULT_GODOT))
    parser.add_argument("--scenario-glob", default="tests/scenarios/*.json")
    parser.add_argument("--include-llm", action="store_true")
    parser.add_argument("--include-ui-snapshots", action="store_true")
    parser.add_argument("--ui-snapshot-targets", default="")
    parser.add_argument("--ui-snapshot-dir", default=DEFAULT_UI_SNAPSHOT_DIR)
    parser.add_argument("--llm-model", default=DEFAULT_LLM_MODEL)
    parser.add_argument("--llm-scenario", default=DEFAULT_LLM_SCENARIO)
    parser.add_argument("--llm-api-kind", choices=["ollama", "openai"], default=DEFAULT_LLM_API_KIND)
    parser.add_argument("--llm-api-url", default=DEFAULT_LLM_API_URL)
    parser.add_argument("--analysis-llm", action="store_true")
    parser.add_argument("--stop-on-fail", action="store_true")
    parser.add_argument("--json-out", default="")
    args = parser.parse_args()

    results: list[StepResult] = []

    godot_cmd = [args.godot_exe, "--headless", "--path", ".", "--quit"]
    results.append(run_step("godot_headless_boot", godot_cmd, timeout_s=120))
    if args.stop_on_fail and not results[-1].ok:
        return emit(results, args.json_out)

    scenarios = discover_scenarios(args.scenario_glob)
    if not scenarios:
        print("No scenarios found.", file=sys.stderr)
        return 1

    for scenario in scenarios:
        cmd = [
            sys.executable,
            "tools/llm_driver.py",
            "--scenario",
            str(scenario.relative_to(PROJECT_DIR)),
            "--no-llm",
        ]
        results.append(run_step(f"scripted::{scenario.name}", cmd, timeout_s=300))
        if args.stop_on_fail and not results[-1].ok:
            return emit(results, args.json_out)

    if args.include_ui_snapshots:
        snapshot_cmd = [
            sys.executable,
            "tools/run_ui_snapshot_suite.py",
            "--out-dir",
            args.ui_snapshot_dir,
        ]
        if args.ui_snapshot_targets:
            snapshot_cmd.extend(["--targets", args.ui_snapshot_targets])
        results.append(run_step("ui_snapshot_smoke", snapshot_cmd, timeout_s=600))
        if args.stop_on_fail and not results[-1].ok:
            return emit(results, args.json_out)

    if args.include_llm:
        llm_cmd = [
            sys.executable,
            "tools/llm_driver.py",
            "--scenario",
            args.llm_scenario,
            "--model",
            args.llm_model,
            "--api-kind",
            args.llm_api_kind,
            "--api-url",
            args.llm_api_url,
        ]
        if args.analysis_llm:
            llm_cmd.append("--analysis-llm")
        results.append(run_step("llm_smoke", llm_cmd, timeout_s=600))

    return emit(results, args.json_out)


def emit(results: list[StepResult], json_out: str) -> int:
    passed = sum(1 for result in results if result.ok)
    failed = len(results) - passed

    payload = {
        "passed": passed,
        "failed": failed,
        "results": [
            {
                "name": result.name,
                "ok": result.ok,
                "duration_s": round(result.duration_s, 2),
                "command": result.command,
                "stdout_tail": result.stdout_tail,
                "stderr_tail": result.stderr_tail,
            }
            for result in results
        ],
    }

    if json_out:
        out_path = Path(json_out)
        if not out_path.is_absolute():
            out_path = PROJECT_DIR / out_path
        out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(f"Regression suite: {passed} passed, {failed} failed")
    for result in results:
        status = "PASS" if result.ok else "FAIL"
        print(f"[{status}] {result.name} ({result.duration_s:.1f}s)")
        if not result.ok:
            if result.stdout_tail:
                print(result.stdout_tail)
            if result.stderr_tail:
                print(result.stderr_tail, file=sys.stderr)

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
