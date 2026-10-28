#!/usr/bin/env python3
"""Print the definitive before/after table for FUTURE-WORK #3 (dual-format),
from committed baseline (git) vs current mixed-corpus coverage_summary.json."""
import json, subprocess

def git_summary(rev):
    raw = subprocess.run(["git","show",f"{rev}:diaspora/results3/people_show/coverage_summary.json"],
                         capture_output=True, text=True, cwd="/home/dev/project/reports")
    return json.loads(raw.stdout)

base = git_summary("fa9e4aa")
cur  = json.load(open("/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json"))

def row(d):
    return dict(
        complete=d.get("coverage_complete"),
        nodes=d.get("tree_nodes"),
        missing=d.get("missing_branches"),
        runs=d.get("total_runs"),
        pcs=d.get("total_path_conditions"),
        assns=d.get("assumptions_used"),
    )

print(f"{'metric':12s} {'BEFORE (fa9e4aa)':>18s} {'AFTER (mri dual)':>18s}")
for k, label in [("missing","MISSING"),("nodes","NODES"),("runs","total_runs"),
                 ("pcs","PCS"),("complete","complete"),("assns","assns_used")]:
    b = row(base)[k]; c = row(cur)[k]
    if label == "complete":
        b = "COMPLETE" if b else "incomplete"
        c = "COMPLETE" if c else "incomplete"
    print(f"{label:12s} {str(b):>18s} {str(c):>18s}")
print("\ncorpus composition (on-disk dumps by scenario):")
import glob, collections, os
cnt = collections.Counter()
for f in glob.glob("/home/dev/project/reports/diaspora/results3/people_show/dump_*.json"):
    b = os.path.basename(f)
    scen = b.split("_0")[0] if "_0" in b else b
    cnt[scen]+=1
for s,c in sorted(cnt.items()):
    print(f"   {s}: {c}")