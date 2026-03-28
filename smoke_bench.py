"""
smoke_bench.py — Compare qwen2.5-coder:7b vs qwen3-nothink:latest on three tiny tasks.
Uses Cline CLI 2.x in headless/yolo mode.

Usage:
  python smoke_bench.py                       # run all tasks against both models
  python smoke_bench.py --model 7b            # only qwen2.5-coder:7b
  python smoke_bench.py --task bench-001      # one task only
  python smoke_bench.py --report              # print last results without running

Results written to benchmark_logs/results.json and printed as a table.

Prerequisites:
  cline auth -p openai -k dummy -b http://localhost:11434/v1 -m qwen2.5-coder:7b
  ollama serve  (must be running)
"""

import argparse
import json
import shutil
import subprocess
import tempfile
import time
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).parent.resolve()
BENCH_DIR = REPO_ROOT / "benchmark_logs"
PYTHON = str(Path("C:/Users/mloka/.venvs/aider/Scripts/python.exe"))
CLINE = str(Path("C:/Users/mloka/AppData/Roaming/npm/cline.cmd"))
CLINE_TIMEOUT = 300  # seconds per Cline invocation

# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
MODELS = {
    "7b":      "qwen2.5-coder:7b",
    "nothink": "qwen3-nothink:latest",
}

ACCURACY_RUBRIC = {
    3: "tests pass, implementation minimal and in-scope",
    2: "tests pass but broad or messy",
    1: "partial progress, tests still failing",
    0: "no meaningful change",
}

# ---------------------------------------------------------------------------
# Tasks — each has a red prompt, green prompt, test command
# Cline is an agent: no need to list files, it discovers and edits them itself
# ---------------------------------------------------------------------------
TASKS = [
    {
        "id": "bench-001",
        "name": "blacksmith_data_entry",
        "red_prompt": (
            "STRICT RED PHASE. "
            "Your ONLY job is to create the file tests/test_bench_001.py. "
            "STOP after creating that one file. Do not touch any other file. "
            "The test file must: load data/buildings.json and assert a dict with id='blacksmith' exists; "
            "assert cost==80; assert footprint==[2,2]. "
            "FORBIDDEN: editing data/buildings.json or any file other than tests/test_bench_001.py. "
            "The test MUST fail when you run it — if it passes you have violated the rules."
        ),
        "green_prompt": (
            "STRICT GREEN PHASE. Your ONLY job: run this exact Python one-liner in the terminal "
            "from the repo root to append a blacksmith entry to data/buildings.json — "
            "python -c \"import json,pathlib; p=pathlib.Path('data/buildings.json'); "
            "d=json.loads(p.read_text()); "
            "d.append({'id':'blacksmith','name':'Blacksmith','description':'Weapons and armour. "
            "Fighters and soldiers are drawn here.','cost':80,'hero_spawn_weight':1,"
            "'footprint':[2,2],'scene':'res://scenes/buildings/Blacksmith.tscn'}); "
            "p.write_text(json.dumps(d, indent=2))\" "
            "STOP after running that command. Do not edit any files manually."
        ),
        "test_command": f'"{PYTHON}" -m pytest tests/test_bench_001.py -q --tb=short',
    },
    {
        "id": "bench-002",
        "name": "scenario_json_valid",
        "red_prompt": (
            "STRICT RED PHASE. "
            "Your ONLY job is to create the file tests/test_bench_002.py. "
            "STOP after creating that one file. Do not touch any other file. "
            "The test must load tests/scenarios/blacksmith_test.json using: "
            "Path(__file__).parent.parent / 'tests' / 'scenarios' / 'blacksmith_test.json'. "
            "Assert: valid JSON; has keys name/seed/max_ticks/commands/assertions; "
            "commands has item with cmd='place_building' and type='blacksmith'; "
            "assertions has item where key 'assert'=='building_count_gte'. "
            "FORBIDDEN: creating or editing blacksmith_test.json or any file other than tests/test_bench_002.py. "
            "The test MUST fail when you run it — if it passes you have violated the rules."
        ),
        "green_prompt": (
            "GREEN PHASE — make tests/test_bench_002.py pass. "
            "Write tests/scenarios/blacksmith_test.json with exactly this content: "
            '{\"name\":\"Blacksmith can be placed\",\"seed\":42,\"max_ticks\":300,'
            '\"commands\":[{\"cmd\":\"place_building\",\"type\":\"blacksmith\",\"x\":5,\"z\":5}],'
            '\"assertions\":[{\"assert\":\"building_count_gte\",\"value\":1}]}'
        ),
        "test_command": f'"{PYTHON}" -m pytest tests/test_bench_002.py -q --tb=short',
    },
    {
        "id": "bench-003",
        "name": "python_utility_fn",
        "red_prompt": (
            "STRICT RED PHASE. "
            "Your ONLY job is to create the file tests/test_bench_003.py. "
            "STOP after creating that one file. Do not touch any other file. "
            "The test must import get_building_by_id from tools.building_utils and assert: "
            "get_building_by_id([{'id':'a'},{'id':'b'}], 'b') returns {'id':'b'}; "
            "get_building_by_id([], 'x') returns None. "
            "FORBIDDEN: creating tools/building_utils.py or any file other than tests/test_bench_003.py. "
            "The test MUST fail with ImportError — if it passes you have violated the rules."
        ),
        "green_prompt": (
            "GREEN PHASE — make tests/test_bench_003.py pass. "
            "Create tools/building_utils.py with a single function: "
            "get_building_by_id(buildings: list, id: str) -> dict | None "
            "that returns the first dict in buildings whose 'id' matches id, or None if not found. "
            "Minimal correct implementation only."
        ),
        "test_command": f'"{PYTHON}" -m pytest tests/test_bench_003.py -q --tb=short',
    },
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def run_cline(prompt: str, model: str, cwd: Path) -> tuple[int, str, float]:
    """Run Cline in yolo mode. Returns (returncode, output, elapsed_seconds)."""
    cmd = [
        CLINE,
        "-y",
        "-m", model,
        "-t", str(CLINE_TIMEOUT),
        "-c", str(cwd),
        prompt,
    ]
    start = time.time()
    try:
        r = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=CLINE_TIMEOUT + 10,
        )
        elapsed = round(time.time() - start, 2)
        return r.returncode, (r.stdout + r.stderr).strip(), elapsed
    except subprocess.TimeoutExpired:
        elapsed = round(time.time() - start, 2)
        return 1, f"TIMEOUT after {CLINE_TIMEOUT}s", elapsed


def run_tests(test_command: str, cwd: Path) -> tuple[bool, str]:
    r = subprocess.run(
        test_command,
        shell=True,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=60,
    )
    return r.returncode == 0, (r.stdout + r.stderr).strip()


def score(green_passed: bool, output: str, n_files: int) -> int:
    if not green_passed:
        return 1 if n_files > 0 else 0
    return 2 if (n_files > 3 or len(output) > 8000) else 3


def count_changed_files(work: Path, repo_root: Path) -> int:
    """Count files that differ between work copy and original repo."""
    changed = 0
    for p in work.rglob("*"):
        if p.is_file() and ".git" not in p.parts:
            rel = p.relative_to(work)
            src = repo_root / rel
            if not src.exists() or (src.stat().st_size != p.stat().st_size):
                changed += 1
    return changed


# ---------------------------------------------------------------------------
# Run one task against one model
# ---------------------------------------------------------------------------
def run_task(repo_root: Path, model_key: str, model: str, task: dict) -> dict:
    tid = task["id"]
    print(f"\n  [{model_key}] {tid}: {task['name']}")

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp) / "repo"
        shutil.copytree(repo_root, work, ignore=shutil.ignore_patterns(
            ".git", "__pycache__", "*.pyc", "ralph_logs", "benchmark_logs", "ralph_state.json"
        ))

        result = {
            "task_id": tid,
            "task_name": task["name"],
            "model_key": model_key,
            "model": model,
            "timestamp": datetime.utcnow().isoformat(),
            "red_elapsed": 0.0,
            "green_elapsed": 0.0,
            "red_passed": False,
            "green_passed": False,
            "files_changed": 0,
            "output_tail": "",
            "score": 0,
            "error": None,
        }

        try:
            # RED phase
            print(f"    red  ...", end="", flush=True)
            _, out, elapsed = run_cline(task["red_prompt"], model, work)
            result["red_elapsed"] = elapsed
            passed, _ = run_tests(task["test_command"], work)
            result["red_passed"] = passed
            verdict = "PASS (unexpected!)" if passed else "FAIL (expected)"
            print(f" {elapsed:.1f}s  tests={verdict}")

            # GREEN phase
            print(f"    green...", end="", flush=True)
            _, out2, elapsed2 = run_cline(task["green_prompt"], model, work)
            result["green_elapsed"] = elapsed2
            passed2, test_out = run_tests(task["test_command"], work)
            result["green_passed"] = passed2
            result["output_tail"] = out2[-800:]
            print(f" {elapsed2:.1f}s  tests={'PASS' if passed2 else 'FAIL'}")
            if not passed2:
                for line in test_out.splitlines()[-5:]:
                    print(f"      {line}")

            result["files_changed"] = count_changed_files(work, repo_root)
            result["score"] = score(passed2, out2, result["files_changed"])

        except Exception as exc:
            result["error"] = str(exc)
            print(f"    ERROR: {exc}")

    return result


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
def print_report(results: list[dict]) -> None:
    tasks = sorted({r["task_id"] for r in results})
    models = sorted({r["model_key"] for r in results})

    col = 16
    print(f"\n{'='*60}")
    print(f"{'Task':<20} " + "  ".join(f"{m:<{col}}" for m in models))
    print("-" * 60)

    for tid in tasks:
        row = f"{tid:<20} "
        for mk in models:
            r = next((x for x in results if x["task_id"] == tid and x["model_key"] == mk), None)
            if r is None:
                row += f"{'N/A':<{col}}"
            else:
                status = "PASS" if r["green_passed"] else "FAIL"
                t_total = r["red_elapsed"] + r["green_elapsed"]
                cell = f"{status} {r['score']}/3 {t_total:.0f}s"
                row += f"{cell:<{col}}"
        print(row)

    print(f"\n  Score: 3/3=clean pass  2/3=messy  1/3=partial  0/3=nothing")
    print(f"  Time:  red + green elapsed seconds per task\n")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", choices=list(MODELS.keys()), help="Only run this model key")
    parser.add_argument("--task", help="Only run this task ID")
    parser.add_argument("--report", action="store_true", help="Print last results only")
    args = parser.parse_args()

    BENCH_DIR.mkdir(exist_ok=True)
    results_path = BENCH_DIR / "results.json"

    if args.report:
        if not results_path.exists():
            print("No results yet.")
            return
        print_report(json.loads(results_path.read_text()))
        return

    selected_models = {k: v for k, v in MODELS.items() if args.model is None or k == args.model}
    selected_tasks = [t for t in TASKS if args.task is None or t["id"] == args.task]

    print(f"Models : {', '.join(selected_models)}")
    print(f"Tasks  : {', '.join(t['id'] for t in selected_tasks)}")
    print(f"Timeout: {CLINE_TIMEOUT}s per Cline call\n")

    all_results = []
    for model_key, model in selected_models.items():
        for task in selected_tasks:
            r = run_task(REPO_ROOT, model_key, model, task)
            all_results.append(r)

    prior = json.loads(results_path.read_text()) if results_path.exists() else []
    combined = [
        r for r in prior
        if not any(r["task_id"] == n["task_id"] and r["model_key"] == n["model_key"] for n in all_results)
    ] + all_results
    results_path.write_text(json.dumps(combined, indent=2))

    print_report(all_results)
    print(f"Full results -> {results_path}")


if __name__ == "__main__":
    main()
