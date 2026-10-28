import json

data = json.load(open('coverage_summary.json'))
missing = data['missing']

# classify each item: does it contain a NEGATED guard (Not(...==True)) and
# does it contain any bare-positive guard? Use the `))`-suffix heuristic on
# the `== True` regions to detect Not((...)) wrappers.
import re
def guard_regions(nc):
    out = []
    toks = ['first_1_not_found','first_1_closed_account',
            'first_2_not_found','first_2_closed_account',
            'find_by_1_not_found','find_by_2_not_found',
            'via_user_closed_account','via_user_not_found',
            'find_by_1_closed_account','find_by_2_closed_account']
    for t in toks:
        for m in re.finditer(re.escape(t) + r'\s*==\s*(True|False)', nc):
            e = m.end()
            tail = nc[e:e+3]
            startctx = nc[max(0,m.start()-6):m.start()]
            out.append((t, m.group(1), tail, startctx))
    return out

neg_items = 0
pos_items = 0
clean_items = 0
for it in missing:
    nc = it['node_constraint']
    regs = guard_regions(nc)
    has_pos = any(r[1]=='True' and 'Not(' not in r[3] and r[2][:1] != ')' for r in regs)
    has_neg = any(r[1]=='True' and ('Not(' in r[3] or r[2][:2]=='))') for r in regs)
    if has_pos:
        pos_items += 1
    elif has_neg:
        neg_items += 1
    else:
        clean_items += 1

print('items with >=1 BARE-POSITIVE guard  :', pos_items)
print('items with NEGATED guard only       :', neg_items)
print('items with NO guard conjunct        :', clean_items)
print('total                              :', len(missing))

# Show item 0 and a mid item's guard regions
for idx in [0, 4, 40]:
    print('\n=== item', idx, 'guard regions ===')
    for r in guard_regions(missing[idx]['node_constraint']):
        print('   ', r)