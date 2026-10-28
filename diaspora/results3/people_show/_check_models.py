#!/usr/bin/env python3
"""Paren-depth-aware classifier of missing[] items' node_constraints.

Counts only TOP-LEVEL POSITIVE guard conjuncts, recognizing `Not((X == True)`
(and `Not(Contains...`, etc.) wrappers as NEGATED, not positive.

Guard vars of interest (the foreclosure guards):
  _not_found == True   (FinderMethods.first_N / Core.find_by_N)
  _closed_account == True

A conjunct is POSITIVE-guard iff:
  - it parses as `(<var> == True)`   where <var> endswith _not_found/_closed_account
  - AND the whole conjunct is NOT wrapped in `Not(` ... `)`
"""
import json, re, sys

GUARD = ('_not_found', '_closed_account')

def split_top_and(expr):
    """Split on top-level ' AND ' (paren-depth aware)."""
    parts = []
    depth = 0
    cur = []
    i = 0
    n = len(expr)
    while i < n:
        c = expr[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth = max(0, depth - 1)
        if depth == 0 and expr[i:i+5] == ' AND ':
            parts.append(''.join(cur).strip())
            cur = []
            i += 5
            continue
        cur.append(c)
        i += 1
    if cur:
        parts.append(''.join(cur).strip())
    return [p for p in parts if p]

def is_positive_guard(conj):
    """True iff conj is a positive guard conjunct ((var==True), no Not wrapper)."""
    s = conj.strip()
    if s.startswith('Not('):
        return False
    m = re.fullmatch(r'\(([^()]+)\s*==\s*True\)', s)
    if not m:
        # allow not fully parenthesized e.g. `X == True`
        m = re.fullmatch(r'([^()]+)\s*==\s*True', s)
    if not m:
        return False
    var = m.group(1).strip()
    return var.endswith(GUARD)

def _guard_var(conj):
    """Return the guard var name from a positive guard conjunct, or None."""
    s = conj.strip()
    if s.startswith('Not('):
        return None
    m = re.fullmatch(r'\(([^()]+)\s*==\s*True\)', s)
    if not m:
        m = re.fullmatch(r'([^()]+)\s*==\s*True', s)
    if not m:
        return None
    var = m.group(1).strip()
    if var.endswith('_not_found') or var.endswith('_closed_account'):
        return var
    return None


def classify(expr):
    guards = []
    lens_pos = []
    for conj in split_top_and(expr):
        v = _guard_var(conj)
        if v:
            guards.append(v)
    # length/row guards: positive ==N / >0 / >=N forms
    for conj in split_top_and(expr):
        s = conj.strip()
        if s.startswith('Not('):
            continue
        m = re.fullmatch(r'\(?([^()]*_rows)\s*(==\s*\d+|>\s*0|>=\s*\d+)\)?', s)
        if m:
            lens_pos.append(conj)
    return guards, lens_pos

def main():
    src = sys.argv[1] if len(sys.argv) > 1 else 'coverage_summary.json'
    d = json.load(open(src))
    miss = d.get('missing', [])
    print(f"total missing: {len(miss)}")
    pos_guard_count = 0
    clean_count = 0
    rows_pos = 0
    for m in miss:
        nc = m.get('node_constraint', '')
        guards, lens_pos = classify(nc)
        has_pos_guard = len(guards) > 0
        fams = set('_closed_account' if '_closed_account' in g else '_not_found' for g in guards)
        contradict = set(('_not_found','_closed_account')).issubset(fams)
        if has_pos_guard:
            pos_guard_count += 1
        else:
            clean_count += 1
        if lens_pos:
            rows_pos += 1
        tag = 'GUARD' if has_pos_guard else 'CLEAN'
        cc = ' CONTRADICT' if contradict else ''
        print(f"  [{tag}{cc}] guards={guards} rows_guard={len(lens_pos)} :: {nc[:110]}")
    print(f"\nPOSITIVE-guard items: {pos_guard_count}")
    print(f"CLEAN (no positive guard): {clean_count}")
    print(f"items with positive _rows position/length guard: {rows_pos}")

if __name__ == '__main__':
    main()
