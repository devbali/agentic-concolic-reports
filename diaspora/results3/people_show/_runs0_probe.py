import json, glob
from collections import Counter

corpus = "reports/diaspora/results3/people_show/dump_*.json"

# Find runs where len(records_1) != 0 is FALSE (i.e., records_1 == 0)
runs0 = []
for f in sorted(glob.glob(corpus)):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    for ev in d.get("events", []):
        if ev.get("type") != "path_condition":
            continue
        e = ev.get("expr", "")
        if e == "(len(SYM_RESULT_ActiveRecord__Relation_records_1) != 0)" and not ev.get("taken"):
            runs0.append(d)
            break

print("runs with records_1==0:", len(runs0))
labels = Counter(d.get("label", "?") for d in runs0)
print("labels:", dict(labels))

# For those runs: do they record ANY stream-row expr at all?
STREAM_ROWS = [
    "(len(SYM_RESULT_ActiveRecord__Relation_records_1_rows) > 0)",
    "(len(SYM_RESULT_ActiveRecord__Relation_to_a_1_rows) != 0)",
    "(len(SYM_RESULT_ActiveRecord__Relation_records_2_rows) == 15)",
]
with_rows = 0
for d in runs0:
    has_row = False
    for ev in d.get("events", []):
        if ev.get("type") == "path_condition" and ev.get("taken") and ev.get("expr") in STREAM_ROWS:
            has_row = True
            break
    if has_row:
        with_rows += 1
print("of those, runs with ANY stream-row expr TAKEN:", with_rows)

# What exprs DO those 24 runs record?
exprs = Counter()
for d in runs0:
    for ev in d.get("events", []):
        if ev.get("type") == "path_condition":
            exprs[(ev.get("expr","")[:110], bool(ev.get("taken")))] += 1
print()
print("=== exprs in the records_1==0 runs ===")
for (e, t), c in exprs.most_common(20):
    print("%4d T=%s %s" % (c, t, e))