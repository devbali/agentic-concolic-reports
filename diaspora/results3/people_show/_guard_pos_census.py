import json

d = json.load(open('coverage_summary.json'))
miss = d['missing']

cands = [
    'SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found',
    'SYM_RESULT_ActiveRecord__FinderMethods_first_2_closed_account',
    'SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_2_not_found',
    'SYM_PERSON_via_user_closed_account',
    'SYM_PERSON_via_user_not_found',
    'SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found',
    'SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account',
    'SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found',
]

def split_conjuncts(nc):
    return [t.strip() for t in nc.split(' AND ')]

positive_counts = {c: 0 for c in cands}
item_bits = []
for it in miss:
    cs = split_conjuncts(it['node_constraint'])
    pos = set()
    for t in cs:
        for c in cands:
            if t == '(' + c + ' == True)':
                pos.add(c)
    for c in cands:
        if c in pos:
            positive_counts[c] += 1
    item_bits.append(pos)

print('items:', len(miss))
for c in cands:
    print('%3d/64  %s' % (positive_counts[c], c))
print()
for c in cands:
    lacking = [i for i, p in enumerate(item_bits) if c not in p]
    if lacking:
        print('%-72s missing in %d items: %s' % (c, len(lacking), lacking[:15]))
