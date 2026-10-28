import json

data = json.load(open('coverage_summary.json'))
missing = data['missing']
print('missing:', len(missing))
for i, item in enumerate(missing[:12]):
    print(f'--- item {i} ---')
    print(item['node_constraint'][:380])
    print()