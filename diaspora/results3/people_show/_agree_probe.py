import json, glob
from collections import Counter

corpus = "reports/diaspora/results3/people_show/dump_*.json"

# For each run: find len(records_1) and len(records_1_rows) PC values; check agreement
agree = 0
disagree = 0
both = 0
samples = []
for f in sorted(glob.glob(corpus)):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    v1 = None  # len(records_1) as recorded via its ==0 / !=0 text
    v1r = None
    for ev in d.get("events", []):
        if ev.get("type") != "path_condition":
            continue
        e = ev.get("expr", "")
        t = bool(ev.get("taken"))
        if "len(SYM_RESULT_ActiveRecord__Relation_records_1)" in e:
            # text forms: (len(...) != 0) or (len(...) == 0)
            if "== 0" in e: v1 = (t == False)
            elif "!= 0" in e: v1 = t
        if "len(SYM_RESULT_ActiveRecord__Relation_records_1_rows)" in e:
            if "== 0" in e: v1r = (t == False)
            elif "!= 0" in e: v1r = t
            elif "> 0" in e: v1r = t
    if v1 is not None and v1r is not None:
        both += 1
        if v1 == v1r:
            agree += 1
        else:
            disagree += 1
            if len(samples) < 5:
                samples.append((d.get("label"), v1, v1r))

print("runs with BOTH len(records_1) and len(records_1_rows):", both)
print("  agree:", agree, "| disagree:", disagree)
for s in samples:
    print("  DISAGREE:", s)

# Same for records_2 vs to_a_1_rows
agree2 = 0; both2 = 0; dis2 = 0
for f in sorted(glob.glob(corpus)):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    v2 = None
    v2a = None
    for ev in d.get("events", []):
        if ev.get("type") != "path_condition":
            continue
        e = ev.get("expr", "")
        t = bool(ev.get("taken"))
        if "len(SYM_RESULT_ActiveRecord__Relation_records_2)" in e:
            if "== 0" in e: v2 = (t == False)
            elif "!= 0" in e: v2 = t
        if "len(SYM_RESULT_ActiveRecord__Relation_to_a_1_rows)" in e:
            if "== 0" in e: v2a = (t == False)
            elif "!= 0" in e: v2a = t
            elif "> 0" in e: v2a = t
    if v2 is not None and v2a is not None:
        both2 += 1
        if v2 == v2a: agree2 += 1
        else: dis2 += 1
print()
print("runs with BOTH len(records_2) and len(to_a_1_rows):", both2)
print("  agree:", agree2, "| disagree:", dis2)