#!/usr/bin/env python3
"""Self-test for cardinality_consistency_audit's key-count escape (2026-09-01).

The escape added after comments_index cycle 10 lets a MANY-row list emit `=`
when the step recorded `keys_many == False`. That is correct AR behaviour --
and it is also exactly the shape of a change that could quietly disarm the
check. These four synthetic dumps pin both directions: the escape must fire
where AR really emits `=`, and the audit must still RED where it does not.

usage: cardinality_audit_selftest.py     (exit 0 = all four behave)
"""
import json, os, shutil, subprocess, sys, tempfile

AUD = os.path.join(os.path.dirname(__file__), "..", "..", "..",
                   "src", "queries_from_runs", "audits", "cardinality_consistency_audit.py")
AUD = os.path.abspath(AUD)
BASE = "SYM_RESULT_ActiveRecord__Relation_records_1"


def dump(rows_many, note_binds, uses_in, keys_many=None, sibling_nf=False):
    ev = [{"type": "path_condition", "expr": f"(len({BASE}_rows) > 1)", "taken": rows_many}]
    if keys_many is not None:
        ev.append({"type": "path_condition",
                   "expr": f"({BASE}_row_person_keys_many == True)", "taken": keys_many})
    if sibling_nf:
        ev.append({"type": "path_condition",
                   "expr": f"({BASE}_row2_person_not_found == True)", "taken": True})
    binds = ", ".join("$$(%s)" % b for b in note_binds)
    pred = f'"people"."id" IN ({binds})' if uses_in else f'"people"."id" = {binds}'
    ev.append({"type": "symbolic_call", "target": "Anonymous.load_intermediate",
               "note": f'SELECT "people".* FROM "people" WHERE {pred}'})
    return {"concolic_scenario": {"name": "selftest"}, "symbolic_vars": [], "events": ev}


CASES = [
    # name,                                    dump,                                            must_red
    ("many rows, one key decided, `=`",
     dump(True, [f"{BASE}_row_person_id"], False, keys_many=False), False),
    ("many rows, sibling parent missing, `=`",
     dump(True, [f"{BASE}_row_person_id"], False, sibling_nf=True), False),
    ("many rows, key set decided MANY, `=`",
     dump(True, [f"{BASE}_row_person_id"], False, keys_many=True), True),
    ("many rows, NO key decision at all, `=`",
     dump(True, [f"{BASE}_row_person_id"], False), True),
]


def main():
    bad = 0
    for name, d, must_red in CASES:
        tmp = tempfile.mkdtemp()
        try:
            json.dump(d, open(os.path.join(tmp, "dump_selftest.json"), "w"))
            r = subprocess.run([sys.executable, AUD, tmp], capture_output=True, text=True)
            red = r.returncode != 0
            ok = (red == must_red)
            bad += 0 if ok else 1
            print(f"  {'ok  ' if ok else 'FAIL'}  {name}: "
                  f"{'RED' if red else 'pass'} (wanted {'RED' if must_red else 'pass'})")
            if not ok:
                print("        " + (r.stdout or r.stderr).strip().replace("\n", "\n        ")[:600])
        finally:
            shutil.rmtree(tmp)
    print("RESULT: " + ("pass — the escape fires only where AR really emits `=`"
                        if not bad else f"FAIL — {bad} case(s) behaved wrongly"))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
