import json, glob

def run_state(f):
    d = json.load(open(f))
    T, F = set(), set()
    for ev in d.get('events', []):
        if ev.get('type') == 'path_condition':
            (T if ev.get('taken') else F).add(ev.get('expr',''))
    return d.get('label','?'), T, F

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
]
DOTLEN = "Contains(StringVal('.'), SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, Length(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle) - 0))"
GUID = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_guid == '')"

hits = []
for f in glob.glob('dump_anon_mobile_*.json'):
    lab, T, F = run_state(f)
    if DOTLEN in T and GUID in T:
        n_stream = sum(1 for s in stream_T if s in T)
        hits.append((lab, n_stream))
print('DOTLEN-T + guid-empty runs:', len(hits))
for lab, n in sorted(hits, key=lambda x: -x[1])[:12]:
    print('  %s  stream-clauses-T: %d/9' % (lab, n))
full = [h for h in hits if h[1] >= 8]
print('with >=8 stream clauses:', len(full))