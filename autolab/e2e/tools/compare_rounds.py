#!/usr/bin/env python3
"""compare_rounds.py — round 1 vs round 2, endpoint by endpoint.

Reads two INVENTORY.json files and reports, per endpoint and in aggregate,
what moved. A regression (a stage that stopped returning, a dump that stopped
being accepted, reach that went down) is called out first and by name, because
that is the number that decides whether the repairs were safe.

Usage: compare_rounds.py <round1 INVENTORY.json> <round2 INVENTORY.json>
"""
from __future__ import annotations
import collections, json, sys

STAGES = ("dump_ir", "run_complete", "build_policy", "normalize",
          "policy_text", "render_sql")


def main():
    a = json.load(open(sys.argv[1]))
    b = json.load(open(sys.argv[2]))
    ids = sorted(set(a) | set(b))

    regress, improve = [], []
    moved = []
    for eid in ids:
        x, y = a.get(eid), b.get(eid)
        if not x or not y or not x["attempted"] or not y["attempted"]:
            continue
        rx = x.get("reach_best") or 0
        ry = y.get("reach_best") or 0
        px = x.get("path_conditions_max") or 0
        py = y.get("path_conditions_max") or 0
        dx = len([d for d in x.get("dumps") or () if d.get("ir") == "ok"])
        dy = len([d for d in y.get("dumps") or () if d.get("ir") == "ok"])
        sx = sum(1 for s in STAGES if x["stages"][s].get("verdict") == "ok")
        sy = sum(1 for s in STAGES if y["stages"][s].get("verdict") == "ok")
        if ry < rx or sy < sx or (dx and dy == 0):
            regress.append((eid, f"reach {rx}->{ry}, stages_ok {sx}->{sy}, "
                                 f"accepted_dumps {dx}->{dy}"))
        if ry > rx or py > px or sy > sx:
            improve.append((eid, f"reach {rx}->{ry}, pcs {px}->{py}, "
                                 f"stages_ok {sx}->{sy}"))
        if (rx, px, dx) != (ry, py, dy):
            moved.append((eid, rx, ry, px, py, dx, dy))

    print("## REGRESSIONS\n")
    if regress:
        for eid, why in regress:
            print(f"* `{eid}` — {why}")
    else:
        print("none: no endpoint lost a stage, a dump or any reach.")
    print(f"\n## IMPROVED — {len(improve)} endpoints\n")
    for eid, why in improve[:60]:
        print(f"* `{eid}` — {why}")
    if len(improve) > 60:
        print(f"* … and {len(improve)-60} more")

    def dist(inv, key):
        return collections.Counter(
            (s.get(key) or 0) for s in inv.values() if s["attempted"])

    print("\n## AGGREGATE\n")
    for key, label in (("reach_best", "target functions reached (best dump)"),
                       ("path_conditions_max", "path conditions (richest dump)")):
        da, db = dist(a, key), dist(b, key)
        print(f"* {label}")
        print(f"    round 1: {dict(sorted(da.items()))}")
        print(f"    round 2: {dict(sorted(db.items()))}")
    for inv, name in ((a, "round 1"), (b, "round 2")):
        att = [s for s in inv.values() if s["attempted"]]
        ok = sum(1 for s in att
                 if all(s["stages"][t].get("verdict") == "ok" for t in STAGES))
        acc = sum(1 for s in att if not s["stages"]["dump_ir"].get("refused"))
        union = set()
        for s in att:
            union |= set(s.get("reach_union") or ())
        print(f"* {name}: {len(att)} attempted, {ok} with every stage ok, "
              f"{acc} with every dump accepted, {len(union)} distinct targets "
              f"ever called")


if __name__ == "__main__":
    main()
