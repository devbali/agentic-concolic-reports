import json, glob
from collections import Counter

corpus = "reports/diaspora/results3/people_show/dump_*.json"
forms = Counter()
for f in sorted(glob.glob(corpus)):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    for ev in d.get("events", []):
        if ev.get("type") != "path_condition":
            continue
        e = ev.get("expr", "")
        if ("records_1" in e and "= 0" in e) or ("records_1_rows" in e) or ("records_2" in e and "= 0" in e) or ("to_a_1_rows" in e) or ("records_2_rows" in e):
            forms[(e, bool(ev.get("taken")))] += 1

print("=== PC text forms for the stream-length vars ===")
for (e, t), c in forms.most_common(25):
    print("%5d T=%s  %s" % (c, t, e[:130]))