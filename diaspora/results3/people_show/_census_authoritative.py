#!/usr/bin/env python3
"""AUTHORITATIVE paren-aware census of positive guard conjuncts."""
import json
import re

data = json.load(open('coverage_summary.json'))
missing = data['missing']

GUARD_SUFFIX = ('_not_found', '_closed_account')


def split_top_and(s):
    parts, cur, depth, in_str = [], '', 0, False
    i, n = 0, len(s)
    while i < n:
        ch = s[i]
        if ch == '"':
            in_str = not in_str
            cur += ch
            i += 1
            continue
        if not in_str:
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth = max(0, depth - 1)
            if depth == 0 and s.startswith(' AND ', i) and ch == ' ':
                parts.append(cur)
                cur = ''
                i += 5
                continue
        cur += ch
        i += 1
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts]


def strip_outer_parens(s):
    while s.startswith('(') and s.endswith(')') and _bal(s):
        s = s[1:-1].strip()
    return s


def _bal(s):
    d = 0
    for ch in s:
        if ch == '(':
            d += 1
        elif ch == ')':
            d -= 1
            if d < 0:
                return False
    return d == 0


def eff_positive(conj):
    """Return (is_positive_guard_conjunct, guard_var) or (False,None).

    Handles explicit Not(...) wrappers and outer parens. A conjunct counts as
    a POSITIVE guard demand if, after unwrapping parens and toggling every
    explicit Not(...), the inner '<var> == True' with guard suffix survives.
    """
    core = conj
    neg = False
    # peel parens outer layers first (no negation)
    core = strip_outer_parens(core)
    # now peel Not(...) layers (each toggles)
    while core.startswith('Not(') and core.endswith(')') and _bal(core):
        neg = not neg
        core = core[4:-1].strip()
        core = strip_outer_parens(core)
    m = re.fullmatch(r'(\S+)\s*==\s*(True|False)', core)
    if not m:
        return False, None
    var, truth = m.group(1), m.group(2)
    if not (var.endswith('_not_found') or var.endswith('_closed_account')):
        return False, None
    eff_pos = (truth == 'True') != neg
    return eff_pos, var


from collections import Counter
pos_vars = Counter()
items_with_pos = 0
clean = 0
examples = {}
for it in missing:
    nc = it.get('node_constraint', '')
    ps = set()
    for conj in split_top_and(nc):
        ispos, var = eff_positive(conj)
        if ispos:
            ps.add(var)
    if ps:
        items_with_pos += 1
        for v in ps:
            pos_vars[v] += 1
        if not examples:
            examples['first'] = ps
    else:
        clean += 1

print('items with >=1 POSITIVE guard conjunct:', items_with_pos)
print('items CLEAN (no positive guard):', clean, '   total:', len(missing))
print('\npositive guard var : # items (of %d)' % len(missing))
for v, c in pos_vars.most_common():
    print('  %4d/64  %s' % (c, v))