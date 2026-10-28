#!/usr/bin/env python3
"""
defect_evidence.py — per-defect BEFORE / AFTER, straight from the executed runs.

For each defect it prints the REAL statement (ground truth, from
`sql.active_record`), the note BEFORE the fix, and the note AFTER, selecting
the differential case that exhibits the defect. Nothing here is typed by hand:
every line is read out of out/baseline_*.json and out/fixed_*.json.

    python3 defect_evidence.py
"""
import json
import sys
from collections import OrderedDict

sys.path.insert(0, ".")
from compare import normalize  # noqa: E402

# defect -> (stack, model, scenario, what it is about)
PROBES = OrderedDict([
    ("D6  core note carries no DML keyword",
     ("core", "Contact", "save_new")),
    ("D5  relation write noted as the relation's SELECT (update_all)",
     ("core", "Contact", "rel_update_all")),
    ("D5  relation write noted as the relation's SELECT (delete_all)",
     ("core", "Contact", "rel_delete_all")),
    ("D1  INSERT column set = every attribute, not the changed set",
     ("override", "Contact", "save_new")),
    ("D2  created_at/updated_at missing from every INSERT",
     ("override", "Contact", "save_new")),
    ("D2  updated_at missing from every save-UPDATE",
     ("override", "Contact", "save_changed")),
    ("D3  touch renders SET (no changed columns)",
     ("override", "Contact", "touch")),
    ("D4  no-change save fabricates an UPDATE",
     ("override", "Contact", "save_unchanged")),
    ("D8  association INSERT deferred to save vanishes",
     ("override", "Contact", "autosave_collection")),
    ("N1  update/update_attribute read the receiver, not the args",
     ("override", "Contact", "update_attribute")),
    ("N4  update_all's SET list leaks into the WHERE",
     ("override", "Contact", "rel_update_all")),
])


def load(path):
    d = json.load(open(path))
    return {(c["model"], c["scenario"]): c for c in d["cases"]}


def notes_of(case):
    if case is None:
        return ["<case absent>"]
    ns = case.get("notes") or []
    if not ns:
        return ["<no note>"]
    return [f"[{t}] {n}" for t, n in ns]


def main():
    B = {"core": load("out/baseline_core.json"),
         "override": load("out/baseline_override.json")}
    A = {"core": load("out/fixed_core.json"),
         "override": load("out/fixed_override.json")}

    for title, (stack, model, scen) in PROBES.items():
        b = B[stack].get((model, scen))
        a = A[stack].get((model, scen))
        print("=" * 78)
        print(f"{title}")
        print(f"   probe: {model}.{scen}   stack={stack}")
        print("-" * 78)
        real = (b or {}).get("real") or []
        if not real:
            print("   REAL  : (ActiveRecord issues NO statement)")
        for s in real:
            print(f"   REAL  : {s}")
        for n in notes_of(b):
            print(f"   BEFORE: {n}")
        for n in notes_of(a):
            print(f"   AFTER : {n}")
        # verdict
        rn = {normalize(s) for s in real}
        an = set()
        for t, n in (a.get("notes") or []) if a else []:
            for part in str(n).split(";\n"):
                an.add(normalize(part))
        lost = rn - an
        fab = {x for x in an if x and x not in rn and
               x.split(None, 1)[0] in ("insert", "update", "delete", "select", "with")}
        print(f"   VERDICT after fix: lost={len(lost)} fabricated={len(fab)}")
        for x in lost:
            print(f"      still LOST      : {x[:130]}")
        for x in fab:
            print(f"      still FABRICATED: {x[:130]}")
        print()


if __name__ == "__main__":
    main()
