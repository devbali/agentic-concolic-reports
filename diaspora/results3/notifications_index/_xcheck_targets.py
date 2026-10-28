#!/usr/bin/env python3
"""Cross-check the two implementations of "what is still missing".

`coverage_report.py` (the ENGINE's `CoverageChecker`) reports a capped sample
of missing combinations as `node_constraint` cubes. `_exact_enum.py` (this
batch's exact enumerator) enumerates the FULL remaining set. They are two
independent implementations of the same §16b semantics, so every cube the
checker calls missing must be witnessed by at least one assignment the
enumerator calls remaining — an assignment that AGREES with the cube on every
expression the cube fixes.

A cube with no such witness is a disagreement, and the owner wants it named.

usage: python3 -u _xcheck_targets.py <remaining.jsonl> [coverage_summary.json]
"""
import json, os, re, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REM = sys.argv[1]
SUM = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "coverage_summary.json")


def conjuncts(nc):
    out = {}
    for part in (nc or "").split(" AND "):
        part = part.strip(); w = True
        m = re.match(r"^Not\((.*)\)$", part, re.S)
        if m:
            part, w = m.group(1).strip(), False
        elif part.startswith("NOT "):
            part, w = part[4:].strip(), False
        if part:
            out[part] = w
    return out


rows = []
by_expr = defaultdict(list)          # expr -> row indices that fix it
n_reach = n_unreach = 0
with open(REM) as fh:
    for line in fh:
        if not line.strip():
            continue
        r = json.loads(line)
        full = dict(r.get("pre") or {})
        full.update(r.get("asg") or {})
        i = len(rows)
        rows.append((full, bool(r.get("reachable")), r.get("set")))
        if r.get("reachable"):
            n_reach += 1
        else:
            n_unreach += 1
        for e in full:
            by_expr[e].append(i)
print(f"enumerator remaining: {len(rows)} "
      f"(REACHABLE {n_reach}, MULTI-GATE-FORECLOSED {n_unreach})")

s = json.load(open(SUM))
miss = [m for m in s.get("missing", []) if not m.get("untracked")]
print(f"checker missing (blocking): {len(miss)} "
      f"(truncated={s.get('truncated')}, demand_sets={s.get('demand_sets')})")

matched = 0
unmatched = []
for m in miss:
    cube = conjuncts(m.get("node_constraint"))
    if not cube:
        continue
    # candidates: rows fixing the RAREST of the cube's expressions
    rare = min(cube, key=lambda e: len(by_expr.get(e, ())))
    cands = by_expr.get(rare, ())
    ok = False
    for i in cands:
        full, _rch, _st = rows[i]
        if all(full.get(e) == v for e, v in cube.items()):
            ok = True
            break
    if ok:
        matched += 1
    else:
        unmatched.append(m)

print(f"\nchecker cubes witnessed by an enumerator remaining assignment: "
      f"{matched} / {len(miss)}")
if unmatched:
    print(f"*** {len(unmatched)} checker cubes have NO witness in the "
          f"enumerator's remaining set — the two implementations DISAGREE ***")
    for m in unmatched[:5]:
        print("  " + (m.get("node_constraint") or "")[:400])
else:
    print("AGREE: every cube the checker calls missing is witnessed by at "
          "least one assignment the enumerator calls remaining.")
json.dump({"remaining": len(rows), "reachable": n_reach,
           "multigate": n_unreach, "checker_missing": len(miss),
           "matched": matched, "unmatched": len(unmatched),
           "unmatched_examples": [m.get("node_constraint") for m in unmatched[:20]]},
          open(os.path.join(HERE, "_xcheck_targets.json"), "w"), indent=1)
print("wrote _xcheck_targets.json")
