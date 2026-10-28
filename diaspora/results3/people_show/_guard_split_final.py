#!/usr/bin/env python3
"""Classify the 64 missing items by guard structure — top-level POSITIVE guard
conjunct vs not. Paren-depth aware: a conjunct like `Not((..._guard == True)` is
NEGATED (excluded); `(..._guard == True)` at top level is POSITIVE.

Sources:
  /tmp/per_item_sat.json        rows[].node_constraint  (derived; may truncate)
  coverage_summary.json         missing[].node_constraint (checker ground truth)
"""
import json, re, sys

GUARD_VAR_SUFFIX = ("_not_found", "_closed_account")

def split_top_and(expr):
    parts = []
    depth = 0
    cur = ""
    i = 0
    n = len(expr)
    while i < n:
        c = expr[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth = max(0, depth - 1)
        if depth == 0 and expr[i:i+5] == " AND ":
            parts.append(cur.strip())
            cur = ""
            i += 5
            continue
        cur += c
        i += 1
    if cur.strip():
        parts.append(cur.strip())
    return parts

def _positive_guard_vars(conj):
    """Return list of guard vars in a POSITIVE top-level conjunct, else [].
    Handles `(<var> == True)` and bare `<var> == True`. Ignores Negated forms."""
    s = conj.strip()
    if s.startswith("Not("):
        return []
    # strip a single outer paren layer
    inner = s
    if inner.startswith("(") and inner.endswith(")") and inner.count("(") == inner.count(")"):
        inner = inner[1:-1].strip()
    if "==" not in inner:
        return []
    lhs, rhs = inner.split("==", 1)
    lhs = lhs.strip()
    rhs = rhs.strip()
    if rhs not in ("True",):
        return []
    # lhs may itself be parenthesized
    lhs = lhs.strip("()").strip()
    if not lhs.endswith(GUARD_VAR_SUFFIX):
        return []
    return [lhs]

def classify_items(node_constraints):
    res = []
    for nc in node_constraints:
        conjs = split_top_and(nc)
        pos_guards = []
        neg_guard = False
        for c in conjs:
            if c.startswith("Not("):
                neg_guard = True
                continue
            pv = _positive_guard_vars(c)
            if pv:
                pos_guards.extend(pv)
        res.append({"pos_guards": pos_guards, "neg_guard": neg_guard,
                     "conjs": len(conjs)})
    return res

def summarize(items, label):
    n_pos = sum(1 for it in items if it["pos_guards"])
    n_neg_only = sum(1 for it in items if not it["pos_guards"] and it["neg_guard"])
    n_clean = sum(1 for it in items if not it["pos_guards"] and not it["neg_guard"])
    n_restrict_neg = sum(1 for it in items if it["pos_guards"] and it["neg_guard"])
    print(f"[{label}] total={len(items)} pos_guard={n_pos} "
          f"neg_only={n_neg_only} clean={n_clean} "
          f"(pos+also_neg={n_restrict_neg})")
    return items

def main():
    # ground truth: coverage_summary.json
    cs = json.load(open("coverage_summary.json"))
    nc_gt = [m["node_constraint"] for m in cs["missing"]]
    items_gt = classify_items(nc_gt)
    summarize(items_gt, "coverage_summary.json ground truth")

    # derived: per_item_sat.json
    sat = json.load(open("/tmp/per_item_sat.json"))
    nc_sat = [r["node_constraint"] for r in sat["rows"]]
    items_sat = classify_items(nc_sat)
    summarize(items_sat, "/tmp/per_item_sat.json (derived)")

    # intersect: same idx guard var sets
    pos_gt = [set(it["pos_guards"]) for it in items_gt]
    pos_sat = [set(it["pos_guards"]) for it in items_sat]
    agree = sum(1 for a, b in zip(pos_gt, pos_sat) if a == b)
    print(f"guard-var agreement between sources: {agree}/{len(pos_gt)}")

if __name__ == "__main__":
    main()