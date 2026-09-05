#!/usr/bin/env python3
"""Verify (a) corpus contains the DISTINCT posts + share_visibilities note,
(b) the 6 warden-401 dumps model finder-then-401 with no trailing SQL,
(c) C07 real run matches that model."""
import glob
import json
import os

BATCH = "/home/dev/project/reports/diaspora/results3/people_show"
RUNS = os.path.join(BATCH, "adversary", "runs")

# (a) DISTINCT posts note
print("== corpus notes with 'DISTINCT' + 'share_visibilities' ==")
found = 0
for f in glob.glob(os.path.join(BATCH, "dump_*.json")):
    d = json.load(open(f))
    for ev in d.get("events") or []:
        if ev.get("type") != "symbolic_call":
            continue
        n = str(ev.get("note") or "")
        if "DISTINCT" in n.upper() and "share_visibilities" in n.lower():
            found += 1
            if found <= 3:
                print(f"  [{ev.get('target')}] {n[:230]}")
print(f"  total distinct-posts notes: {found}")

# (a2) also var-carried
for f in glob.glob(os.path.join(BATCH, "dump_*.json")):
    d = json.load(open(f))
    for sv in d.get("symbolic_vars") or []:
        n = str(sv.get("note") or "")
        if "DISTINCT" in n.upper() and "share_visibilities" in n.lower():
            found += 1
print(f"  incl. var-carried: {found}")

# (b) warden-401 dumps: event sequence
print()
print("== the 6 warden-401 dumps ==")
warden_files = []
for f in sorted(glob.glob(os.path.join(BATCH, "dump_*.json"))):
    d = json.load(open(f))
    e = str(d.get("error") or "")
    if "Warden" in e:
        warden_files.append(f)
for f in sorted(warden_files):
    d = json.load(open(f))
    evs = d.get("events") or []
    calls = [ev for ev in evs if ev.get("type") == "symbolic_call"]
    print(f"  {os.path.basename(f)}: label={d.get('label')} error={str(d.get('error'))[:60]}")
    for ev in calls:
        print(f"     target={ev.get('target')} result={ev.get('result_name')}")
        print(f"       note={str(ev.get('note'))[:120]}")
    # script tail for the terminal
    scr = d.get("script") or ""
    print(f"     script_tail={scr[-140:]!r}")

# (c) C07 real run
print()
print("== C07 real run (anon remote 401) ==")
for sc in json.load(open(os.path.join(RUNS, "C07_anon_remote_401.json"))):
    print("  error:", sc.get("error"))
    for st in sc.get("statements") or []:
        print(f"  [{st.get('under')}] {st['sql'][:150]}")