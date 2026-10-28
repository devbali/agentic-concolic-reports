import json

data = json.load(open('coverage_summary.json'))
missing = data['missing']

GUARD_POS_RE = [
    'first_1_not_found == True', 'first_1_closed_account == True',
    'first_2_not_found == True', 'first_2_closed_account == True',
    'find_by_1_not_found == True', 'find_by_2_not_found == True',
    'via_user_closed_account == True',
]
GUARD_NEG_RE = [
    'first_1_not_found == False', 'first_1_closed_account == False',
    'first_2_not_found == False', 'first_2_closed_account == False',
    'find_by_1_not_found == False', 'find_by_2_not_found == False',
    'via_user_closed_account == False',
]

# BARE positive: '(X == True)' NOT preceded by 'Not(' and not inside Not(( ... == True))
pos_count = {g: 0 for g in GUARD_POS_RE}
for it in missing:
    nc = it['node_constraint']
    for g in GUARD_POS_RE:
        # find all occurrences of g
        idx = 0
        while True:
            i = nc.find(g, idx)
            if i < 0:
                break
            # check char before the match (should be '(' for bare conjunct start)
            before = nc[max(0, i-6):i]
            # bare if the '==' is not preceded by 'Not(' directly
            ctx = nc[max(0, i-10):i]
            if 'Not(' not in ctx:
                pos_count[g] += 1
            idx = i + len(g)

print('== BARE POSITIVE guard conjunct occurrences (should be ~0 if pins work) ==')
for g, c in pos_count.items():
    if c:
        print(f'  {c:4d}  {g}')

# count items with ANY bare-positive guard
import re
items_with_bare_pos = 0
for it in missing:
    nc = it['node_constraint']
    has = False
    for g in GUARD_POS_RE:
        for m in re.finditer(re.escape(' == True'), nc):
            pass
        # check bare occurrences
        for m in re.finditer(re.escape(g), nc):
            ctx = nc[max(0, m.start()-8):m.start()]
            if 'Not(' not in ctx:
                has = True
    if has:
        items_with_bare_pos += 1
print('\nitems with >=1 BARE positive guard conjunct:', items_with_bare_pos)
print('total missing:', len(missing))