import json, glob
from collections import Counter

corpus = "reports/diaspora/results3/people_show/dump_*.json"
runs = []
for f in sorted(glob.glob(corpus)):
    try:
        runs.append(json.load(open(f)))
    except Exception:
        pass

# Find symbolic_call events / notes that mint len(...records...) vars
notes = Counter()
for d in runs[:50]:
    for ev in d.get("events", []):
        if ev.get("type") == "symbolic_call":
            rn = ev.get("result_name", "")
            note = ev.get("note", "")
            if "records" in rn or "records" in note or "to_a" in rn or "to_a" in note:
                notes[(rn[:80], note[:120])] += 1
print("=== symbolic_call events minting records/to_a vars (first 50 runs) ===")
for (rn, note), c in notes.most_common(20):
    print("%4d  result=%s\n       note=%s" % (c, rn, note))

# Also check path_condition exprs mentioning both len forms to see context
print()
print("=== path conditions mentioning records_1 len or rows ===")
pc = Counter()
for d in runs[:200]:
    for ev in d.get("events", []):
        if ev.get("type") == "path_condition":
            e = ev.get("expr", "")
            if "records_1" in e and ("SYM_LEN" in e or "len(" in e) and "len(" not in e.replace("Load", ""):
                pc[(e[:150], bool(ev.get("taken")))] += 1
for (e, t), c in pc.most_common(12):
    print("%4d T=%s  %s" % (c, t, e))