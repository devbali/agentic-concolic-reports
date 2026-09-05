#!/usr/bin/env python3
"""R2: (a) per-scenario statement diff R2(fresh) vs R1(old) — any NEW shape
in the fresh signed-in runs that was NOT in R1's runs; (b) entry-point-frame
map: for the sanctioned families, which people_controller.rb line issued it.

Note: (b) needs the controller source + the run's statement->line mapping,
which the concrete_run_probe may not record. We do the best available:
the run json has target_calls (with line numbers?) — check structure first.
"""
import glob
import json
import os
import re
from collections import defaultdict

BATCH = "/home/dev/project/reports/diaspora/results3/people_show"
RUNS = os.path.join(BATCH, "adversary", "runs")

def stmts(f):
    out = set()
    for sc in json.load(open(f)):
        for st in sc.get("statements") or []:
            out.add(("records" if "records" in (st.get("under") or "") else st.get("under"), st["sql"].strip()))
    return out

pairs = [("R2C01_auth_self_html", "C01_auth_self_html"),
         ("R2C02_auth_other_html", "C02_auth_other_html"),
         ("R2C03_auth_other_mutual_html", "C03_auth_other_mutual_html"),
         ("R2C04_auth_blocked_json", "C04_auth_blocked_json"),
         ("R2C05_auth_mobile", "C05_auth_mobile"),
         ("R2C06_anon_self_html", "C06_anon_self_html"),
         ("R2C07_anon_remote_401", "C07_anon_remote_401"),
         ("R2C09_missing_person", "C09_missing_person")]

print("== (a) NEW statements in fresh R2 runs vs R1 runs (same scenario) ==")
for r2name, r1name in pairs:
    r2 = stmts(os.path.join(RUNS, r2name + ".json"))
    r1 = stmts(os.path.join(RUNS, r1name + ".json"))
    new = r2 - r1
    if new:
        print(f"### {r2name}: {len(new)} NEW statement(s) vs {r1name}")
        for u, s in sorted(new):
            print(f"   [{u}] {s[:160]}")
    else:
        print(f"### {r2name}: no new statements vs {r1name}")

# (b) check what target_calls contains (line numbers?)
print()
print("== (b) sample target_calls structure from R2C01 ==")
for sc in json.load(open(os.path.join(RUNS, "R2C01_auth_self_html.json"))):
    tc = sc.get("target_calls") or []
    print(f"  total target_calls: {len(tc)}")
    for t in tc[:6]:
        print("   ", str(t)[:200])