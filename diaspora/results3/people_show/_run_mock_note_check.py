#!/usr/bin/env python3
# _run_mock_note_check.py — run mock_note_check for all people_show C01-C09 concrete runs
import subprocess, sys, os, glob

BATCH = "/home/dev/project/reports/diaspora/results3/people_show"
ALIASES = os.path.join(BATCH, "concrete_aliases.json")
CHECKER = "/home/dev/project/src/end_to_end_completion_checker/mock/mock_note_check.py"
FIDELITY = "/home/dev/project/reports/diaspora/tools/note_fidelity_audit.py"

runs = sorted(glob.glob(os.path.join(BATCH, "adversary", "runs", "C0*.json")))
print(f"concrete runs: {len(runs)}")
for r in runs:
    name = os.path.basename(r)
    p = subprocess.run([sys.executable, CHECKER, r, BATCH, "--aliases", ALIASES],
                       capture_output=True, text=True, cwd="/home/dev/project")
    out = (p.stdout + p.stderr).strip().splitlines()
    verdict = " / ".join(l.strip() for l in out if any(k in l for k in
                        ["NOTE-OK", "NOTE-MISSING", "NOTE-MISMATCH", "PASS", "FAIL",
                         "OK ", "verdict", "summary"]))
    tail = out[-4:] if out else ["<no output>"]
    print(f"--- {name} (exit={p.returncode}) ---")
    for l in tail:
        print("   ", l[:150])
    if p.returncode != 0:
        print("    !! exit", p.returncode)