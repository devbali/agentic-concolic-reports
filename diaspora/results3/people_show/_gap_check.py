import json, glob
from collections import Counter

corpus = "reports/diaspora/results3/people_show/dump_*.json"
runs = []
for f in sorted(glob.glob(corpus)):
    try:
        runs.append(json.load(open(f)))
    except Exception:
        pass
print("corpus:", len(runs))

# stream family clauses (mobile stream render)
STREAM = [
    "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows > 0)",
    "Not((SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1 != 0))",
    "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2_rows == 15)",
    "Not((SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2 != 0))",
    "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_3_rows > 0)",
    "(assoc_profile_nsfw == True)",
    "(assoc_author_guid == '')",
    "(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_provider_display_name == StringVal('mobile'))",
    "(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_public == True)",
    "(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_comments_count == 0)",
]

def stream_count(d):
    T = set()
    for ev in d.get("events", []):
        if ev.get("type") == "path_condition" and ev.get("taken"):
            T.add(ev.get("expr", ""))
    return sum(1 for s in STREAM if s in T)

def has(d, needle):
    for ev in d.get("events", []):
        if ev.get("type") == "path_condition" and needle in ev.get("expr", ""):
            return ev.get("taken")
    return None

# A=False (branch B): decision var value False
def branch_b(d):
    for v in d.get("symbolic_vars", []):
        if v.get("name", "").startswith("SYM_DECISION_diaspora_id"):
            return v.get("value") is False
    return None

# guard-T runs
def guard_t(d):
    return has(d, "person_disconnected") or has(d, "public_details")

b = branch_b_d = sum(1 for d in runs if branch_b(d))
print("branch-B (A=False) runs:", b)
print("branch-A (A=True)  runs:", sum(1 for d in runs if branch_b(d) is False))

# stream depth distribution for branch-B runs
depths_b = Counter(stream_count(d) for d in runs if branch_b(d))
print("stream-clause depth distribution among branch-B runs:", dict(sorted(depths_b.items())))

# max stream depth overall
maxd = max(stream_count(d) for d in runs)
print("max stream clauses in ANY run:", maxd)

# guard-T AND stream-T
gt = [d for d in runs if guard_t(d) is True]
print("guard-T runs:", len(gt), "| with any stream clause:", sum(1 for d in gt if stream_count(d) > 0))

# PD-T runs
pd = [d for d in runs if has(d, "public_details") is True]
print("PD-T runs:", len(pd), "| with stream clauses:", [stream_count(d) for d in pd][:10])

# blank-T ever?
blankT = 0
for d in runs:
    for ev in d.get("events", []):
        if ev.get("type") == "path_condition" and "== ''" in ev.get("expr", "") and ev.get("taken"):
            blankT += 1
            break
print("blank-T (empty-side taken) runs:", blankT)