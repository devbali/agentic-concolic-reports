#!/usr/bin/env python3
"""C18 — per-KEY drive analysis of a residue class (RUNBOOK Phase 2).

For every witness leaf of `_c16_residue.json` in the chosen class, join its
CONSTRUCTED runs (the C16A / C17A replays, found by the `__c13gap__` seed the
constructor writes) and report, per member of the cube:

    HONOURED         evaluated with the demanded outcome in >= 1 replay
    CONTRADICTED     evaluated, and NEVER with the demanded outcome
    NEVER-EVALUATED  no replay reached it

plus the per-run error class, so "UNEVALUATED" can be told apart from
"the run died before it got there".

  usage: CLASS=open|a0|remint python3 -u _c18_leafdrive.py [out.json]
"""
import glob, json, os, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals   # noqa: E402

CLASS = os.environ.get("CLASS", "open")
TAGS = os.environ.get("TAGS", "C16A,C17A").split(",")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, f"_c18_leafdrive_{CLASS}.json")
_UNLEN = re.compile(r"len\(([^()]+)\)")
_RT = re.compile(r"_row_target_photos_row_rows"
                 r"|_row_target_mentions_container_photos_row_rows"
                 r"|_row_target_mentions_container_commentable_photos_row_rows"
                 r"|find_by_1_person_id == SYM_RESULT_ActiveRecord__FinderMethods_"
                 r"devise_user_first_1_person_id")

res = json.load(open(os.path.join(HERE, "_c16_residue.json")))["leaves"]
gaps = {g["id"]: g for g in json.load(open(os.path.join(HERE, "_c16_gaps.json")))}
for g in json.load(open(os.path.join(HERE, "_c17_gaps.json"))):
    gaps.setdefault(g["id"] + "#c17", g)


def pick(x):
    if CLASS == "a0":
        return x["A0_at_gate_conjunction"]
    if CLASS == "remint":
        return x["rule_T_members"] > 0
    return (not x["A0_at_gate_conjunction"]) and x["rule_T_members"] == 0


leaves = [x for x in res if pick(x)]
want_gid = {gid for x in leaves for gid in x["batch_ids"]}
print(f"class {CLASS}: {len(leaves)} leaves, {len(want_gid)} constructed cube ids", flush=True)

files = []
for t in TAGS:
    files += sorted(glob.glob(os.path.join(HERE, f"dump_*_{t}*.json")))
print(f"replay dumps on disk: {len(files)}", flush=True)

runs = defaultdict(list)     # gid -> [(pcs, errtype)]
for fp in files:
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    gid = (d.get("concolic_seeds") or {}).get("__c13gap__")
    if gid not in want_gid:
        continue
    canonicalize_ordinals(d)
    pcs = defaultdict(set)
    for e in d.get("events") or ():
        if e.get("type") != "path_condition":
            continue
        ex = e["expr"]; pcs[ex].add(bool(e.get("taken")))
        ex2 = _UNLEN.sub(r"SYM_LEN_\1", ex)
        if ex2 != ex:
            pcs[ex2].add(bool(e.get("taken")))
    runs[gid].append((pcs, (d.get("error") or {}).get("type") or "-",
                      os.path.basename(fp)))
print(f"replays matched: {sum(len(v) for v in runs.values())} over {len(runs)} cubes",
      flush=True)

rows = []
blockers = Counter(); shapes = Counter()
for x in leaves:
    rr = [r for gid in x["batch_ids"] for r in runs.get(gid, ())]
    keys = []
    for k in x["keys"]:
        e, o = k["expr"], k["outcome"]
        hit = sum(1 for pcs, _, _ in rr if e in pcs and o in pcs[e])
        opp = sum(1 for pcs, _, _ in rr if e in pcs and o not in pcs[e])
        nev = sum(1 for pcs, _, _ in rr if e not in pcs)
        v = ("HONOURED" if hit else "CONTRADICTED" if opp else
             "NEVER-EVALUATED" if rr else "NOT-DRIVEN")
        keys.append({"expr": e, "outcome": o, "verdict": v,
                     "hit": hit, "opp": opp, "never": nev,
                     "A_others": k["A_others"],
                     "evaluated_under_others": k["evaluated_under_others"],
                     "rule_T": bool(_RT.search(e))})
    con = [k for k in keys if k["verdict"] == "CONTRADICTED"]
    nev = [k for k in keys if k["verdict"] == "NEVER-EVALUATED"]
    rows.append({"set": x["set"], "width": x["width"], "verdict": x["verdict"],
                 "runs": len(rr), "errors": dict(Counter(e for _, e, _ in rr)),
                 "contradicted": [(k["expr"], k["outcome"]) for k in con],
                 "never_evaluated": [(k["expr"], k["outcome"]) for k in nev],
                 "keys": keys})
    for k in con:
        blockers[("CON", k["expr"], k["outcome"])] += 1
    for k in nev:
        blockers[("NEV", k["expr"], k["outcome"])] += 1
    shapes[(tuple(sorted((k["expr"], k["outcome"]) for k in con)),
            tuple(sorted((k["expr"], k["outcome"]) for k in nev)))] += 1

print(f"\nleaves {len(rows)}   runs total {sum(r['runs'] for r in rows)}")
print("per-leaf verdict:", dict(Counter(r["verdict"] for r in rows)))
print("\nBLOCKING MEMBERS (CON = contradicted in every replay, "
      "NEV = never evaluated by any replay):")
for (t, e, o), n in blockers.most_common(40):
    print(f"  {t} x{n:3d}  {str(o):5s} {e}")
print(f"\ndistinct (contradicted, never-evaluated) SHAPES: {len(shapes)}")
for (con, nev), n in shapes.most_common(20):
    print(f"  x{n:3d}  CON={len(con)} NEV={len(nev)}")
    for e, o in con:
        print(f"        CON {str(o):5s} {e}")
    for e, o in nev[:6]:
        print(f"        NEV {str(o):5s} {e}")
    if len(nev) > 6:
        print(f"        NEV ... and {len(nev)-6} more")
json.dump({"class": CLASS, "leaves": rows}, open(OUT, "w"), indent=1)
print(f"\nC18-LEAFDRIVE-DONE {OUT}")
