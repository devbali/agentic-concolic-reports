import json

data = json.load(open('coverage_summary.json'))
missing = data['missing']
print('total missing:', len(missing))
for i, it in enumerate(missing[:8]):
    nc = it['node_constraint']
    # print just the LEADING guard-ish conjuncts (first 3)
    head = nc[:180]
    print(f'--- item {i} ---')
    print(head)
    print()