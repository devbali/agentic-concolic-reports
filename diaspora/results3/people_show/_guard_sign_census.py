#!/usr/bin/env python3
"""Paren-depth-aware census of the 64 missing items' guard conjuncts.

Counts, for each candidate guard var *string token* (both _1 and _2 and
via_user forms), how many of the 64 missing node_constraints carry it as:
  - POSITIVE:  bare `<var> == True`  at top level (outside any Not(...))
  - NEGATED:   wrapped as `<var> == False` or inside a Not(...) at top level
Determines which guard var(s) are the authoritative POSITIVE conjuncts.

Reads ground truth from coverage_summary.json missing[] node_constraint.
"""
import json
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SUMMARY = os.path.join(HERE, "coverage_summary.json")

with open(SUMMARY) as f:
    data = json.load(f)

missing = data["missing"]
print(f"missing count: {len(missing)}")
print(f"summary keys: {list(data.keys())}")
print(f"truncated: {data.get('truncated')}  complete: {data.get('coverage_complete')}")


def top_level_split(s, sep):
    """Split s on sep occurrences at paren-depth 0, honoring quotes."""
    parts, cur, depth, in_str = [], "", 0, False
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if ch == '"':
            in_str = not in_str
            cur += ch
            i += 1
            continue
        if not in_str:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth = max(0, depth - 1)
            if depth == 0 and s.startswith(sep, i) and ch == " ":
                parts.append(cur)
                cur = ""
                i += len(sep)
                continue
        cur += ch
        i += 1
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts]


def classify_conj(conj):
    """Return (core_var, is_positive) or (None, None) if not a guard conjunct."""
    c = conj.strip()
    # unwrap one layer of parentheses and Not(...)
    while c.startswith("(") and c.endswith(")") and _balanced(c):
        c = c[1:-1].strip()
    neg = False
    while c.startswith("Not(") and c.endswith(")") and _balanced(c):
        neg = not neg
        c = c[4:-1].strip()
    m = re.fullmatch(r"(\S+)\s+==\s+(True|False)", c)
    if not m:
        return None, None
    core, truth = m.group(1), m.group(2)
    is_pos = (truth == "True") != neg
    return core, is_pos


def _balanced(s):
    d = 0
    for ch in s:
        if ch == "(":
            d += 1
        elif ch == ")":
            d -= 1
            if d < 0:
                return False
    return d == 0


GUARD_TOKENS = [
    "FinderMethods_first_1_not_found",
    "FinderMethods_first_1_closed_account",
    "FinderMethods_first_2_not_found",
    "FinderMethods_first_2_closed_account",
    "ClassMethods_find_by_1_not_found",
    "ClassMethods_find_by_1_closed_account",
    "ClassMethods_find_by_2_not_found",
    "ClassMethods_find_by_2_closed_account",
    "PERSON_via_user_closed_account",
    "PERSON_via_user_not_found",
]
FULL_TOKENS = {
    "FinderMethods_first_1_not_found": "FinderMethods_first_1_not_found",
    "FinderMethods_first_1_closed_account": "FinderMethods_first_1_closed_account",
    "FinderMethods_first_2_not_found": "FinderMethods_first_2_not_found",
    "FinderMethods_first_2_closed_account": "FinderMethods_first_2_closed_account",
    "ClassMethods_find_by_1_not_found": "ClassMethods_find_by_1_not_found",
    "ClassMethods_find_by_1_closed_account": "ClassMethods_find_by_1_closed_account",
    "ClassMethods_find_by_2_not_found": "ClassMethods_find_by_2_not_found",
    "ClassMethods_find_by_2_closed_account": "ClassMethods_find_by_2_closed_account",
    "PERSON_via_user_closed_account": "PERSON_via_user_closed_account",
    "PERSON_via_user_not_found": "PERSON_via_user_not_found",
}

from collections import Counter, defaultdict

pos = Counter()
neg = Counter()
pos_items = defaultdict(set)
neg_items = defaultdict(set)

for i, item in enumerate(missing):
    nc = item.get("node_constraint", "")
    if isinstance(nc, list):
        nc = " AND ".join(nc)
    for cj in top_level_split(nc, " AND "):
        core, is_pos = classify_conj(cj)
        if core is None:
            continue
        for tok in GUARD_TOKENS:
            if tok in core:
                if is_pos:
                    pos[tok] += 1
                    pos_items[tok].add(i)
                else:
                    neg[tok] += 1
                    neg_items[tok].add(i)
                break

print("\n=== POSITIVE guard conjunct counts (items of 64 carrying it) ===")
for tok in GUARD_TOKENS:
    print(f"  {FULL_TOKENS[tok]:<75} pos={pos.get(tok,0):<3}  neg={neg.get(tok,0)}")

# items with NO positive guard conjunct
no_pos = 0
for i, item in enumerate(missing):
    nc = item.get("node_constraint", "")
    if isinstance(nc, list):
        nc = " AND ".join(nc)
    found_pos = False
    for cj in top_level_split(nc, " AND "):
        core, is_pos = classify_conj(cj)
        if is_pos and any(tok in core for tok in GUARD_TOKENS):
            found_pos = True
            break
    if not found_pos:
        no_pos += 1
        if no_pos <= 3:
            print(f"\n  item [{i}] NO positive guard conjunct, nc head: {nc[:240]}")
print(f"\nitems with NO positive guard conjunct: {no_pos}")

# how many items carry positive _1/via_user family vs _2 family
f1 = set()
f2 = set()
for i, item in enumerate(missing):
    nc = item.get("node_constraint", "")
    if isinstance(nc, list):
        nc = " AND ".join(nc)
    for cj in top_level_split(nc, " AND "):
        core, is_pos = classify_conj(cj)
        if not is_pos or core is None:
            continue
        if "_1_" in core or "via_user" in core or core.endswith("_1"):
            f1.add(i)
        if "_2_" in core or core.endswith("_2"):
            f2.add(i)
print(f"\nitems with a POSITIVE _1-or-via_user guard conjunct: {len(f1)}")
print(f"items with a POSITIVE _2 guard conjunct:              {len(f2)}")
