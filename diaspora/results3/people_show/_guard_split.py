#!/usr/bin/env python3
"""CORRECT depth-aware guard counter for people_show missing items.

Counts TOP-LEVEL POSITIVE guard conjuncts from the node_constraint STRING
(source of truth, /home/dev/project/reports/diaspora/results3/people_show/
coverage_summary.json).

A guard conjunct is POSITIVE iff the top-level split conjunct matches
    (SYM_RESULT_ActiveRecord__<FAMILY>_not_found == True)
or
    (SYM_RESULT_ActiveRecord__<FAMILY>_closed_account == True)
or
    (SYM_PERSON_via_user_closed_account == True)

and is NOT wrapped in a leading `Not(...)` at the SAME top level (Bali's
point: `Not((..._not_found == True))` is the NON-guard side — it forces the
guard FALSE, so it must NOT be counted as a guard-forced item).

Prints the true positive/negative/clean split.
"""
import json
import re

SRC = "/home/dev/project/reports/diaspora/results3/people_show/coverage_summary.json"

# guard var families seen in this corpus (incl. the _2 dual-format ordinals)
GUARD_FAMILIES = (
    "FinderMethods_first_1_not_found",
    "FinderMethods_first_1_closed_account",
    "Core__ClassMethods_find_by_1_not_found",
    "FinderMethods_first_2_not_found",
    "FinderMethods_first_2_closed_account",
    "Core__ClassMethods_find_by_2_not_found",
)
VIA_USER_CA = "(SYM_PERSON_via_user_closed_account == True)"

# positive: (SYM_RESULT_ActiveRecord__<family> == True)
POS_RE = re.compile(
    r"^\(SYM_RESULT_ActiveRecord__(?P<fam>"
    + "|".join(GUARD_FAMILIES)
    + r") == True\)$"
)
# negative: Not((SYM_RESULT_ActiveRecord__<family> == True))
NEG_RE = re.compile(
    r"^Not\(\(SYM_RESULT_ActiveRecord__(?P<fam>"
    + "|".join(GUARD_FAMILIES)
    + r") == True\)\)$"
)


def top_conjuncts(s):
    """Split on ' AND ' at top level (all order-1 conjuncts are depth 0)."""
    return [c.strip() for c in s.split(" AND ")]


def classify(item):
    nc = item["node_constraint"]
    cs = top_conjuncts(nc)
    pos = []
    neg = []
    for c in cs:
        if c == VIA_USER_CA:
            pos.append("via_user_closed_account")
        elif POS_RE.match(c):
            pos.append(POS_RE.match(c).group("fam"))
        elif NEG_RE.match(c):
            neg.append(NEG_RE.match(c).group("fam"))
    return pos, neg


def main():
    summary = json.load(open(SRC))
    items = summary["missing"]
    print(f"total missing items: {len(items)}")

    pos_items = []
    neg_only_items = []
    clean_items = []

    for i, it in enumerate(items):
        pos, neg = classify(it)
        if pos:
            pos_items.append((i, pos, neg))
        elif neg:
            neg_only_items.append((i, neg))
        else:
            clean_items.append(i)

    print(f"  POSITIVE-guard items (guard forced True): {len(pos_items)}")
    print(f"  NEGATIVE-guard-only items (guard Not eq True): {len(neg_only_items)}")
    print(f"  CLEAN items (no guard at all):            {len(clean_items)}")

    print("\n=== positive-guard items ===")
    for i, pos, neg in pos_items:
        print(f"  idx {i:2}: pos={pos}  neg={neg}")

    print("\n=== negative-only items ===")
    for i, neg in neg_only_items:
        print(f"  idx {i:2}: neg={neg}")

    print("\n=== clean item idxs ===")
    print(" ", clean_items)


if __name__ == "__main__":
    main()
