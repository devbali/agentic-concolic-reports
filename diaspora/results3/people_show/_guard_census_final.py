#!/usr/bin/env python3
"""Census the ACTUAL ground-truth missing[] node_constraint strings in
coverage_summary.json to confirm which guard vars appear as POSITIVE
conjuncts (== True), NOT deriving from any truncated file.

This reads the checker's own summary (the source of truth), finds every
`<guard_var> == True` (positive) and `<guard_var> == False` (negated)
occurrence, and tallies per guard var, plus how many of the 64 items carry
at least one positive guard conjunct.
"""
import json
import re
import sys

PATH = "/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json"

# Candidate guard-var shapes (the four families, both _1 and _2 ordinals).
GUARD_SHAPES = [
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found",
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account",
    "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found",
    "SYM_RESULT_ActiveRecord__FinderMethods_first_2_closed_account",
    "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found",
    "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_closed_account",
    "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_2_not_found",
    "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_2_closed_account",
    "SYM_PERSON_via_user_closed_account",
]


def load_summary(path):
    with open(path) as f:
        return json.load(f)


def census(items):
    from collections import defaultdict
    pos = defaultdict(int)      # guard_var -> #items with a == True conjunct
    neg = defaultdict(int)      # guard_var -> #items with a == False conjunct
    items_with_pos_guard = 0
    items_with_neg_only = 0
    items_clean = 0
    for it in items:
        nc = it.get("node_constraint", "")
        if not isinstance(nc, str):
            nc = str(nc)
        has_pos = False
        has_neg = False
        for g in GUARD_SHAPES:
            # positive conjunct: ...(g == True)...  (also handles True)  )
            for m in re.finditer(re.escape(g) + r"\s*==\s*(True|False)\b", nc):
                if m.group(1) == "True":
                    pos[g] += 1
                    has_pos = True
                else:
                    neg[g] += 1
                    has_neg = True
        if has_pos:
            items_with_pos_guard += 1
        elif has_neg:
            items_with_neg_only += 1
        else:
            items_clean += 1
    return pos, neg, items_with_pos_guard, items_with_neg_only, items_clean


def main():
    s = load_summary(PATH)
    missing = s.get("missing", [])
    print(f"summary file: {PATH}")
    print(f"summary keys: {list(s.keys())}")
    print(f"len(missing) = {len(missing)}\n")

    pos, neg, n_pos, n_neg_only, n_clean = census(missing)

    print("== POSITIVE guard conjuncts (guard_var == True) per item ==")
    for g in GUARD_SHAPES:
        if pos[g]:
            print(f"  {pos[g]:3d}  {g}")
    print(f"\nitems with >=1 POSITIVE guard conjunct : {n_pos}")
    print(f"items negated-only (no positive guard) : {n_neg_only}")
    print(f"items clean (no guard conjunct at all) : {n_clean}")

    print("\n== NEGATED guard conjuncts (guard_var == False) per item ==")
    for g in GUARD_SHAPES:
        if neg[g]:
            print(f"  {neg[g]:3d}  {g}")

    # Show first 5 raw node_constraints so we can eyeball the actual shapes.
    print("\n== first 5 raw node_constraint strings (truncated to 260) ==")
    for it in missing[:5]:
        nc = it.get("node_constraint", "")
        print("  -", (nc[:260] + ("..." if len(nc) > 260 else "")))


if __name__ == "__main__":
    sys.exit(main())
