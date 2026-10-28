import json, glob
from collections import Counter

corpus = "reports/diaspora/results3/people_show/dump_*.json"
notes = Counter()
for f in sorted(glob.glob(corpus))[:400]:
    try:
        d = json.load(open(f))
    except Exception:
        continue
    for ev in d.get("events", []):
        if ev.get("type") != "symbolic_call":
            continue
        rn = ev.get("result_name", "")
        if "_rows" in rn:
            notes[(rn[:120], ev.get("note", "")[:150])] += 1

print("=== _rows var minting notes ===")
for (rn, note), c in notes.most_common(10):
    print("\n%4d %s\n     %s" % (c, rn, note))