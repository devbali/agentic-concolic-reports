#!/usr/bin/env python3
"""_run_mock_detail.py — full mock_note_check detail for selected runs."""
import subprocess, sys, os

BATCH = "/home/dev/project/reports/diaspora/results3/people_show"
ALIASES = os.path.join(BATCH, "concrete_aliases.json")
CHECKER = "/home/dev/project/src/end_to_end_completion_checker/mock/mock_note_check.py"

for r in sys.argv[1:]:
    path = os.path.join(BATCH, "adversary", "runs", r)
    p = subprocess.run([sys.executable, CHECKER, path, BATCH, "--aliases", ALIASES],
                       capture_output=True, text=True, cwd="/home/dev/project")
    print("=" * 70)
    print(f"### {r} (exit={p.returncode})")
    print("=" * 70)
    print((p.stdout + p.stderr).strip())