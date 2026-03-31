#!/usr/bin/env python3
"""
Render QuestTown UI snapshot targets and exit automatically.

Usage:
  python tools/run_ui_snapshot_suite.py
  python tools/run_ui_snapshot_suite.py --targets town_idle,quest_board_open
  python tools/run_ui_snapshot_suite.py --out-dir snapshots/ui
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_GODOT = Path(r"C:\Users\mloka\Downloads\godot_extracted\Godot_v4.6.1-stable_win64.exe")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot-exe", default=str(DEFAULT_GODOT))
    parser.add_argument("--targets", default="")
    parser.add_argument("--out-dir", default="artifacts/ui_snapshots")
    parser.add_argument("--resolution", default="1920x1080")
    parser.add_argument("--seed", default="4242")
    parser.add_argument("--load-path", default="")
    args = parser.parse_args()

    cmd = [
        args.godot_exe,
        "--path",
        ".",
        "--",
        "--ui-snapshots",
        f"--seed={args.seed}",
        f"--snapshot-dir={args.out_dir}",
        f"--snapshot-resolution={args.resolution}",
    ]
    if args.targets:
        cmd.append(f"--snapshot-targets={args.targets}")
    if args.load_path:
        cmd.append(f"--snapshot-load={args.load_path}")

    result = subprocess.run(cmd, cwd=PROJECT_DIR)
    if result.returncode == 0:
        print(f"UI snapshots written to {args.out_dir}")
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
