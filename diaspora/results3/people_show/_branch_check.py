import json, glob
from collections import Counter

corpus = "reports/diaspora/results3/people_show/dump_*.json"
obs = {}
for f in sorted(glob.glob(corpus)):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    for ev in d.get("events", []):
        if ev.get("type") != "path_condition":
            continue
        e = ev.get("expr", "")
        obs.setdefault(e, Counter())[bool(ev.get("taken"))] += 1

needles = [
    ("Contains('.', H[0,1])", "Contains(StringVal('.'), SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, 1))"),
    ("Contains('.', H[0,2])", "Contains(StringVal('.'), SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, 2))"),
    ("Contains('.', H[0,Len-0])", "Contains(StringVal('.'), SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, Length(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle) - 0))"),
    ("IndexOf == 1", "IndexOf(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, StringVal('@')) == 1"),
    ("IndexOf == 2", "IndexOf(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, StringVal('@')) == 2"),
    ("IndexOf == 2 (via_user)", "IndexOf(SYM_PERSON_via_user_diaspora_handle, StringVal('@')) == 2"),
    ("NOTC via_user", "Not(Contains(StringVal('@'), SYM_PERSON_via_user_diaspora_handle))"),
    ("CONT via_user", "Contains(StringVal('@'), SYM_PERSON_via_user_diaspora_handle)"),
    ("Contains('.', via_user H[0,1])", "Contains(StringVal('.'), SubString(SYM_PERSON_via_user_diaspora_handle, 0, 1))"),
]

for label, needle in needles:
    c = obs.get(needle, Counter())
    print("%-32s %5dT %5dF" % (label, c[True], c[False]))