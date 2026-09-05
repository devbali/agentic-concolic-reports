#!/usr/bin/env python3
"""R2 re-judge: run mock_note_check + note_fidelity_audit on the R1 concrete
runs (C01-C09 JSONs) against the CURRENT (fresh 12,997-path) corpus.

Forensics value: the R1 judge.txt files in runs/ were produced Sep 4 18:xx
against the OLD pre-repair corpus (55 dumps). The drain campaign (078f90c)
promises the families are now minted. This re-judges the SAME real captures
against the CURRENT corpus — a pure comparison of real SQL vs current notes.
"""
import glob
import json
import os
import subprocess
import sys

BATCH = "/home/dev/project/reports/diaspora/results3/people_show"
RUNS = os.path.join(BATCH, "adversary", "runs")
ALIASES = os.path.join(BATCH, "concrete_aliases.json")
TOOLS = "/home/dev/project/src/end_to_end_completion_checker/mock"
NFA = "/home/dev/project/reports/diaspora/tools/note_fidelity_audit.py"

def run_judge(tool, args):
    p = subprocess.run([sys.executable, tool] + args,
                       capture_output=True, text=True)
    return p.returncode, p.stdout

summary = []
for f in sorted(glob.glob(os.path.join(RUNS, "C*.json"))):
    name = os.path.basename(f)
    rc1, out1 = run_judge(os.path.join(TOOLS, "mock_note_check.py"),
                          [f, BATCH, "--aliases", ALIASES])
    rc2, out2 = run_judge(NFA, [BATCH, f, "--aliases", ALIASES])
    # compact verdict: NOTE-OK / NOTE-MISSING / NOTE-MISMATCH lines + RESULT
    def compact(out):
        lines = []
        for ln in out.splitlines():
            if ln.startswith(("NOTE-", "RESULT", "EXIT", "-- MISSING",
                              "-- STAR-OVER", "-- AGG-COLLAPSE", "-- PRED-DIFF",
                              "-- PRED-OP-DIFF", "-- LIMIT-DIFF", "-- ORDER-DIFF",
                              "-- EXACT")):
                lines.append(ln)
        return lines
    summary.append((name, rc1, rc2, compact(out1), compact(out2)))

for name, rc1, rc2, c1, c2 in summary:
    print("=" * 100)
    print(f"### {name}  mock_note_check rc={rc1}  note_fidelity rc={rc2}")
    for ln in c1:
        print("  M|" + ln)
    for ln in c2:
        print("  F|" + ln)