import json, sys

# Paren-depth-aware guard counter for node_constraint strings.
# Counts TOP-LEVEL POSITIVE guard conjuncts only.
# A conjunct is "at top level" if it appears at paren depth 1 (i.e. not nested
# inside a Not(...) wrapper at depth>=2).
#
# guard vars of interest:
GUARDS = [
    'FinderMethods_first_1_not_found',
    'FinderMethods_first_1_closed_account',
    'FinderMethods_first_2_not_found',
    'FinderMethods_first_2_closed_account',
    'Core__ClassMethods_find_by_1_not_found',
    'Core__ClassMethods_find_by_1_closed_account',
    'Core__ClassMethods_find_by_2_not_found',
    'Core__ClassMethods_find_by_2_closed_account',
    'via_user_closed_account',
    'via_user_not_found',
]

def split_top_conjuncts(s):
    """Split a node_constraint into top-level conjuncts (depth-aware on ' AND ')."""
    # We split on ' AND ' but only where paren depth back at baseline inside the string.
    out = []
    depth = 0
    cur = ''
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == '(':
            depth += 1
            cur += c
            i += 1
        elif c == ')':
            depth -= 1
            cur += c
            i += 1
        elif s[i:i+5] == ' AND ' and depth == 0:
            out.append(cur.strip())
            cur = ''
            i += 5
        else:
            cur += c
            i += 1
    if cur.strip():
        out.append(cur.strip())
    return out

def is_top_level_positive_guard(conj):
    """Return matching guard suffix if conj is a top-level positive guard
    conjunct like `(SYM_..._guard == True)` or `(SYM_..._guard == True)`.
    top-level positive = not wrapped in Not(...)."""
    t = conj.strip()
    # handle a conjunct that may itself be parenthesized: (...)
    inner = t
    if inner.startswith('(') and inner.endswith(')') and inner.count('(')==inner.count(')'):
        # strip one outer layer
        inner = inner[1:-1].strip()
    # reject negated: starts with Not( or contains '=='False' flag
    if inner.startswith('Not'):
        return None
    # must be of form X == True (a positive Bool literal)
    if '==' not in inner:
        return None
    lhs, rhs = inner.split('==', 1)
    lhs = lhs.strip().strip('(').strip()
    rhs = rhs.strip()
    if rhs not in ('True',):
        return None
    for g in GUARDS:
        if lhs.endswith(g):
            return g
    return None

def main(path):
    d = json.load(open(path))
    missing = d.get('missing', [])
    print(f"missing count: {len(missing)}")
    carry = 0
    neg_only = 0
    clean = 0
    detail = {}
    examples = {'pos': [], 'neg': [], 'clean': []}
    for it in missing:
        nc = it.get('node_constraint', '')
        conj = split_top_conjuncts(nc)
        has_pos_guard = False
        has_neg_guard = False
        for c in conj:
            m = is_top_level_positive_guard(c)
            if m:
                has_pos_guard = True
                detail.setdefault(m, 0)
                detail[m] += 1
            # detect negated guard forms
            if 'not_found' in c or 'closed_account' in c or 'via_user' in c:
                if 'Not' in c or '== False' in c:
                    has_neg_guard = True
        if has_pos_guard:
            carry += 1
            if len(examples['pos']) < 3:
                examples['pos'].append(nc[:140])
        elif has_neg_guard:
            neg_only += 1
            if len(examples['neg']) < 3:
                examples['neg'].append(nc[:140])
        else:
            clean += 1
            if len(examples['clean']) < 3:
                examples['clean'].append(nc[:140])
    print(f"carry POSITIVE guard: {carry}")
    print(f"negated-only:         {neg_only}")
    print(f"clean (no guard):     {clean}")
    print("guard var counts (positive hits):", detail)
    print("\n--- pos examples ---")
    for e in examples['pos']:
        print(' ', e)
    print("\n--- neg-only examples ---")
    for e in examples['neg']:
        print(' ', e)
    print("\n--- clean examples ---")
    for e in examples['clean']:
        print(' ', e)

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv)>1 else 'coverage_summary.json')
