import json, glob, re
from collections import defaultdict, Counter

# people_show gap-analysis evidence collector (read-only over current dumps)
pattern = 'dump_*.json'

# --- stream family (10 exprs) + profile family + guards + handle family ---
stream_T = [
    '(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows > 0)',
    '(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_1_rows != 0)',
    '(assoc_profile_nsfw == True)',
    "(assoc_author_guid == '')",
    "(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_provider_display_name == StringVal('mobile'))",
    '(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_public == True)',
    '(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_comments_count == 0)',
    '(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2_rows == 15)',
    '(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_3_rows > 0)',
    "(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_guid == '')",
]
guards = [
    '(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)',
    '(SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account == True)',
    '(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True)',
    '(SYM_PERSON_via_user_closed_account == True)',
]
A = '(SYM_DECISION_diaspora_id_username == True)'
PD = '(assoc_profile_public_details == True)'
BY = '(assoc_profile_birthday_year <= 1004)'
NOTC2 = "Not(Contains(StringVal('@'), SYM_PERSON_via_user_diaspora_handle))"
DOTLEN = "Contains(StringVal('.'), SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, Length(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle) - 0))"
GUIDE = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_guid == '')"

def run_T(f):
    d = json.load(open(f))
    T = set()
    for ev in d.get('events', []):
        if ev.get('type') == 'path_condition' and ev.get('taken'):
            T.add(ev.get('expr',''))
    return d.get('label','?'), T

runs = [run_T(f) for f in glob.glob(pattern)]
labels = [lab for lab, _ in runs]
n = len(runs)
print(f'=== corpus: {n} runs ===')

def count(pred):
    return sum(1 for _, T in runs if pred(T))

# 1. Branch-B x mobile coupling
notc2_runs = [(lab, T) for lab, T in runs if NOTC2 in T]
print(f'\n[1] via_user no-@ (NOTC2) runs: {len(notc2_runs)}')
for lab, T in notc2_runs[:6]:
    scen = lab.split('_')[0]
    ns = sum(1 for s in stream_T if s in T)
    print(f'    {lab}: scenario={scen}, stream-clauses={ns}/10')

# 2. A=False distribution by scenario
a_false = [(lab, T) for lab, T in runs if A not in T]
print(f'\n[2] A=False runs: {len(a_false)} (A missing from trace = branch B)')
af_scen = Counter(lab.split('_')[0] for lab, _ in a_false)
print(f'    by scenario: {dict(af_scen)}')

# 3. PD-T runs and stream co-occurrence
pd_runs = [(lab, T) for lab, T in runs if PD in T]
best_pd = max((sum(1 for s in stream_T if s in T) for _, T in pd_runs), default=-1)
print(f'\n[3] PD-T runs: {len(pd_runs)}, max stream clauses in any PD-T run: {best_pd}/10')

# 4. DOTLEN-T + guid-empty runs, stream depth
dotg = [(lab, T) for lab, T in runs if DOTLEN in T and GUIDE in T]
depth = sorted((sum(1 for s in stream_T if s in T) for _, T in dotg), reverse=True)
print(f'\n[4] DOTLEN-T & guid-empty runs: {len(dotg)}, stream-depth distribution: {Counter(depth)}')

# 5. Guard runs with any stream clause
g_stream = [(lab, T) for lab, T in runs if any(g in T for g in guards) and any(s in T for s in stream_T)]
print(f'\n[5] runs with guard-T AND stream-T: {len(g_stream)}')

# 6. Full-stream runs (all 10 clauses) by scenario
full = [(lab, T) for lab, T in runs if all(s in T for s in stream_T)]
print(f'\n[6] full-stream runs: {len(full)}, scenarios: {Counter(lab.split("_")[0] for lab,_ in full)}')

# 7. Blank-T runs (any blank expr taken)
blanks = ["(SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, 1) == '')",
          "(SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, 2) == '')",
          "(SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, Length(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle) - 0) == '')"]
bk = [(lab, T) for lab, T in runs if any(b in T for b in blanks)]
print(f'\n[7] blank-T runs: {len(bk)}')

# 8. handle value for NOTC2 runs (what seed produces branch B?)
print()
for lab, T in notc2_runs[:6]:
    d = json.load(open(f'dump_{lab}.json')) if False else None
# find handle values from symbolic_vars
for f in glob.glob(pattern):
    lab = json.load(open(f)).get('label','?')
    if lab in [l for l,_ in notc2_runs[:3]]:
        d = json.load(open(f))
        for v in d.get('symbolic_vars', []):
            if 'diaspora_handle' in v.get('name','') and 'via_user' in v.get('name',''):
                print(f'    {lab}: via_user handle = {v.get("value")!r}')