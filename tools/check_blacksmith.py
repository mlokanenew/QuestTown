"""
Check script for architect loop: runs the blacksmith headless scenario.
Exit 0 = test passes (Green). Non-zero = test fails (Red).
"""
import os
import subprocess
import sys

SCENARIO = "res://tests/scenarios/blacksmith_test.json"
SCENARIO_FILE = os.path.join(
    os.path.dirname(__file__), "..", "tests", "scenarios", "blacksmith_test.json"
)
GODOT = r"C:\Users\mloka\Downloads\godot_extracted\Godot_v4.6.1-stable_win64_console.exe"
PROJECT = r"C:\Users\mloka\Documents\QuestTown"

if not os.path.exists(SCENARIO_FILE):
    print("FAIL: tests/scenarios/blacksmith_test.json does not exist yet (Red phase)")
    sys.exit(1)

result = subprocess.run(
    [GODOT, "--headless", "--path", PROJECT, "--", "--mode=test", f"--scenario={SCENARIO}", "--seed=42"],
    timeout=60,
)
sys.exit(result.returncode)
