#!/usr/bin/env python3
"""C30 — print the BLOCKING gap sets of a coverage summary, one per stanza,
with each set's member literals split out of its `node_constraint`.

BLOCKING is exactly `_c27_coverage_report.py:586`'s definition: a `missing`
entry whose `untracked` flag is false. The four UNTRACKED transparency entries
are listed separately at the end so the reader can see they are the same four
and not something new.

  usage: python3 _c30_gaps.py <cov.json> [--json out.json]
"""
import json
import re
import sys

_SPLIT = re.compile(r"\s+AND\s+")


def members(nc):
    """The literals of a conjunctive node_constraint, in order.

    `node_constraint` is a flat `A AND B AND ...` string whose conjuncts are
    themselves parenthesised or `Not(...)`-wrapped, so a plain split on
    ` AND ` is exact here. It is CHECKED rather than assumed: every conjunct
    must be balanced, and an unbalanced one aborts instead of being silently
    mis-split.
    """
    if not nc:
        return []
    parts = _SPLIT.split(nc.strip())
    for p in parts:
        if p.count("(") != p.count(")"):
            raise SystemExit(f"unbalanced conjunct, refusing to guess: {p!r}")
    return parts


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    d = json.load(open(path))
    miss = d.get("missing") or []
    blocking = [m for m in miss if not m.get("untracked")]
    untracked = [m for m in miss if m.get("untracked")]

    print(f"summary       {path}")
    print(f"complete      {d.get('complete')}")
    print(f"tree_complete {d.get('tree_complete')}  tree_missing {d.get('tree_missing')}")
    print(f"total_runs    {d.get('total_runs')}")
    print(f"truncated     {d.get('truncated')}  solver_lost {d.get('solver_lost')}")
    print(f"MISSING={len(miss)}  BLOCKING={len(blocking)}  UNTRACKED={len(untracked)}")
    print()

    out = []
    for i, m in enumerate(blocking):
        mem = members(m.get("node_constraint"))
        print(f"=== BLOCKING[{i}]  width {len(mem)}  "
              f"branch={m.get('missing_branch')}  src={m.get('source_location') or '-'}")
        for lit in mem:
            print(f"      {lit}")
        cv = m.get("concrete_values")
        if cv:
            print(f"    witness: {json.dumps(cv)[:400]}")
        print()
        out.append({"i": i, "width": len(mem), "members": mem,
                    "branch": m.get("missing_branch"),
                    "source_location": m.get("source_location"),
                    "concrete_values": cv})

    print(f"=== UNTRACKED ({len(untracked)}) — the transparency entries")
    for i, m in enumerate(untracked):
        mem = members(m.get("node_constraint"))
        print(f"  untracked[{i}] width {len(mem)}  src={m.get('source_location') or '-'}")
        # the distinguishing literal is the last one; print it so the reader
        # can confirm these are the same four `_row_actors_row_guid` entries
        if mem:
            print(f"      last: {mem[-1]}")

    if "--json" in sys.argv:
        o = sys.argv[sys.argv.index("--json") + 1]
        json.dump({"blocking": out,
                   "untracked": [{"members": members(m.get("node_constraint")),
                                  "source_location": m.get("source_location")}
                                 for m in untracked]},
                  open(o, "w"), indent=1)
        print(f"\nwrote {o}")
    print("C30-GAPS-DONE")


if __name__ == "__main__":
    main()
