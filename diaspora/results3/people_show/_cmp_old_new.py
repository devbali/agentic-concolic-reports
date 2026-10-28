import json

old = json.load(open('/tmp/coverage_summary_BEFORE_6c.json'))
new = json.load(open('coverage_summary.json'))

print("OLD: missing=%d assumptions_used=%s truncated=%s" % (
    len(old['missing']), old.get('assumptions_used'), old.get('truncated')))
print("NEW: missing=%d assumptions_used=%s truncated=%s" % (
    len(new['missing']), new.get('assumptions_used'), new.get('truncated')))

o = set(m['node_constraint'] for m in old['missing'])
n = set(m['node_constraint'] for m in new['missing'])
print("OLD-only:", len(o - n))
print("NEW-only:", len(n - o))
print("shared  :", len(o & n))

# are the guard-True items identical between old and new?
def has_tok(s, tok):
    return tok in s

guard_toks = [
    'FinderMethods_first_2_not_found', 'FinderMethods_first_2_closed_account',
    'ClassMethods_find_by_2_not_found', 'FinderMethods_first_1_not_found',
    'FinderMethods_first_1_closed_account', 'ClassMethods_find_by_1_not_found',
    'PERSON_via_user_closed_account',
]
print("\nNEW missing items carrying each guard token:")
for t in guard_toks:
    c = sum(1 for m in new['missing'] if t in m['node_constraint'])
    print(f"  {c:3d}  {t}")

# sample a NEW guard-True item fully
print("\n--- sample NEW item beginning with a guard-True conjunct ---")
for m in new['missing']:
    nc = m['node_constraint']
    if nc.startswith('(SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found == True)'):
        print(nc[:400])
        break