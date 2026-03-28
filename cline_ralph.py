"""
cline_ralph.py — Autonomous TDD loop using Cline CLI 2.x in yolo/headless mode.

Usage:
  python cline_ralph.py                          # run next todo story
  python cline_ralph.py --story US-001           # run specific story
  python cline_ralph.py --model qwen2.5-coder:7b
  python cline_ralph.py --dry-run                # print prompts, no Cline calls
  python cline_ralph.py --status                 # print backlog status

Stop gracefully: touch .ralph-stop or Ctrl+C.

Prerequisites:
  cline auth -p openai -k dummy -b http://localhost:11434/v1 -m qwen2.5-coder:7b
  ollama serve  (must be running)
"""

import argparse
import json
import os
import signal
import subprocess
import sys
import textwrap
import time
from datetime import datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).parent.resolve()
CLINE = str(Path("C:/Users/mloka/AppData/Roaming/npm/cline.cmd"))
BACKLOG_FILE = REPO_ROOT / "backlog.json"
STATE_FILE = REPO_ROOT / "ralph_state.json"
STOP_FILE = REPO_ROOT / ".ralph-stop"
LOGS_DIR = REPO_ROOT / "ralph_logs"
PROMPTS_DIR = REPO_ROOT / "prompts"
PYTHON = str(Path("C:/Users/mloka/.venvs/aider/Scripts/python.exe"))

DEFAULT_MODEL = "qwen2.5-coder:7b"
MAX_GREEN_ATTEMPTS = 5
CLINE_TIMEOUT = 300  # seconds per Cline invocation

# ---------------------------------------------------------------------------
# Graceful stop
# ---------------------------------------------------------------------------
_stop_requested = False


def _handle_signal(sig, frame):
    global _stop_requested
    print("\n[ralph] Stop signal received — will stop at next safe point.")
    _stop_requested = True


signal.signal(signal.SIGINT, _handle_signal)
signal.signal(signal.SIGTERM, _handle_signal)


def stop_requested() -> bool:
    if _stop_requested:
        return True
    if STOP_FILE.exists():
        print("[ralph] .ralph-stop file detected — stopping.")
        return True
    return False


# ---------------------------------------------------------------------------
# Backlog helpers
# ---------------------------------------------------------------------------
def load_backlog() -> dict:
    return json.loads(BACKLOG_FILE.read_text())


def save_backlog(backlog: dict) -> None:
    BACKLOG_FILE.write_text(json.dumps(backlog, indent=2))


def find_story(backlog: dict, story_id: str | None) -> tuple[dict, dict] | None:
    for epic in backlog["epics"]:
        for story in epic["stories"]:
            if story_id is None:
                if story["status"] == "todo":
                    return epic, story
            else:
                if story["id"] == story_id:
                    return epic, story
    return None


def set_story_status(backlog: dict, story_id: str, status: str) -> None:
    for epic in backlog["epics"]:
        for story in epic["stories"]:
            if story["id"] == story_id:
                story["status"] = status
                return


def print_status(backlog: dict) -> None:
    for epic in backlog["epics"]:
        print(f"\nEpic {epic['id']}: {epic['title']}")
        for story in epic["stories"]:
            icon = {"todo": "[ ]", "in_progress": "[~]", "done": "[x]", "blocked": "[!]"}.get(
                story["status"], "[?]"
            )
            print(f"  {icon} {story['id']}: {story['title']}  ({story['status']})")


# ---------------------------------------------------------------------------
# State persistence
# ---------------------------------------------------------------------------
def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def save_state(state: dict) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2))


# ---------------------------------------------------------------------------
# Prompt building
# ---------------------------------------------------------------------------
def build_prompt(template_name: str, story: dict, test_output: str = "") -> str:
    template_path = PROMPTS_DIR / f"{template_name}.txt"
    if not template_path.exists():
        raise FileNotFoundError(f"Prompt template not found: {template_path}")
    template = template_path.read_text()

    ac_lines = "\n".join(f"  - {c}" for c in story.get("acceptance_criteria", []))
    files_lines = "\n".join(f"  - {f}" for f in story.get("files_in_scope", []))

    return template.format(
        story_id=story["id"],
        story_title=story["title"],
        description=story.get("description", ""),
        acceptance_criteria=ac_lines,
        files_in_scope=files_lines,
        test_command=story.get("test_command", ""),
        test_output=test_output,
    )


# ---------------------------------------------------------------------------
# Cline invocation
# ---------------------------------------------------------------------------
def run_cline(prompt: str, model: str, log_path: Path, dry_run: bool = False) -> subprocess.CompletedProcess:
    log_path.parent.mkdir(parents=True, exist_ok=True)

    if dry_run:
        print("\n--- DRY RUN: Cline would receive this prompt ---")
        print(textwrap.indent(prompt, "  "))
        print("--- END PROMPT ---\n")
        return subprocess.CompletedProcess(args=[], returncode=0, stdout="", stderr="")

    cmd = [
        CLINE,
        "-y",
        "-m", model,
        "-t", str(CLINE_TIMEOUT),
        "-c", str(REPO_ROOT),
        prompt,
    ]
    print(f"[ralph] Running Cline (model={model}) ...")
    print(f"[ralph] Log -> {log_path}")

    start = time.time()
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=CLINE_TIMEOUT + 10,
    )
    elapsed = round(time.time() - start, 1)

    log_content = {
        "timestamp": datetime.utcnow().isoformat(),
        "model": model,
        "elapsed_seconds": elapsed,
        "returncode": result.returncode,
        "prompt": prompt,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    log_path.write_text(json.dumps(log_content, indent=2))
    print(f"[ralph] Cline finished in {elapsed}s (exit {result.returncode})")
    return result


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------
def run_tests(test_command: str, dry_run: bool = False) -> tuple[bool, str]:
    if dry_run:
        print(f"[ralph] DRY RUN: would run -> {test_command}")
        return False, "dry-run: no test output"

    print(f"[ralph] Running tests: {test_command}")
    result = subprocess.run(
        test_command,
        shell=True,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=90,
    )
    output = (result.stdout + result.stderr).strip()
    passed = result.returncode == 0
    print(f"[ralph] Tests: {'PASS' if passed else 'FAIL'}")
    if not passed:
        print(textwrap.indent(output[-800:], "  "))
    return passed, output


# ---------------------------------------------------------------------------
# Main TDD loop
# ---------------------------------------------------------------------------
def run_story(story: dict, model: str, dry_run: bool) -> str:
    sid = story["id"]
    test_cmd = story.get("test_command", "")
    ts = datetime.utcnow().strftime("%Y%m%dT%H%M%S")

    print(f"\n[ralph] === Story {sid}: {story['title']} ===")

    # RED phase
    print(f"[ralph] Phase: RED")
    red_prompt = build_prompt("red_phase", story)
    red_log = LOGS_DIR / f"{sid}_{ts}_red.json"
    run_cline(red_prompt, model, red_log, dry_run)

    if stop_requested():
        return "todo"

    passed, output = run_tests(test_cmd, dry_run)
    if passed:
        print("[ralph] WARNING: tests passed after red phase — red may have over-implemented.")
        return "done"

    # GREEN loop
    for attempt in range(1, MAX_GREEN_ATTEMPTS + 1):
        if stop_requested():
            return "todo"

        print(f"\n[ralph] Phase: GREEN attempt {attempt}/{MAX_GREEN_ATTEMPTS}")
        green_prompt = build_prompt("green_phase", story, test_output=output)
        green_log = LOGS_DIR / f"{sid}_{ts}_green_{attempt}.json"
        run_cline(green_prompt, model, green_log, dry_run)

        if stop_requested():
            return "todo"

        passed, output = run_tests(test_cmd, dry_run)
        if passed:
            print(f"[ralph] Story {sid} DONE after {attempt} green attempt(s).")
            return "done"

    print(f"[ralph] Story {sid} BLOCKED after {MAX_GREEN_ATTEMPTS} green attempts.")
    return "blocked"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Ralph — autonomous TDD loop via Cline CLI")
    parser.add_argument("--story", help="Story ID to run (default: next todo)")
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Ollama model name")
    parser.add_argument("--dry-run", action="store_true", help="Print prompts, don't call Cline")
    parser.add_argument("--status", action="store_true", help="Print backlog status and exit")
    args = parser.parse_args()

    backlog = load_backlog()

    if args.status:
        print_status(backlog)
        return

    pair = find_story(backlog, args.story)
    if pair is None:
        if args.story:
            print(f"[ralph] Story '{args.story}' not found.")
        else:
            print("[ralph] No stories with status 'todo' found.")
        return

    epic, story = pair
    set_story_status(backlog, story["id"], "in_progress")
    save_backlog(backlog)

    try:
        final_status = run_story(story, args.model, args.dry_run)
    except subprocess.TimeoutExpired:
        print(f"[ralph] Cline timed out ({CLINE_TIMEOUT}s). Marking blocked.")
        final_status = "blocked"
    except Exception as exc:
        print(f"[ralph] Unexpected error: {exc}")
        final_status = "blocked"

    set_story_status(backlog, story["id"], final_status)
    save_backlog(backlog)

    state = load_state()
    state[story["id"]] = {"status": final_status, "completed_at": datetime.utcnow().isoformat()}
    save_state(state)

    print(f"\n[ralph] Final status for {story['id']}: {final_status}")
    sys.exit(0 if final_status == "done" else 1)


if __name__ == "__main__":
    main()
