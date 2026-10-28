import json, glob
from collections import Counter

corpus = "reports/diaspora/results3/people_show/dump_*.json"

# collect all notes for records_1/2/3, to_a_1, and the _rows length vars
notes = Counter()
rows_notes = Counter()
for f in sorted(glob.glob(corpus))[:300]:
    try:
        d = json.load(open(f))
    except Exception:
        continue
    for ev in d.get("events", []):
        if ev.get("type") != "symbolic_call":
            continue
        rn = ev.get("result_name", "")
        note = ev.get("note", "")
        if rn.startswith("SYM_RESULT_ActiveRecord__Relation_records_") and not rn.endswith("_row_"):
            notes[(rn, note[:160])] += 1
        if "records_1_rows" in rn or "records_2_rows" in rn or "records_3_rows" in rn:
            rows_notes[(rn[:90], note[:160])] += 1
print("=== Relation_records_N minting ===")
for (rn, note), c in notes.most_common(8):
    print("\n%4d %s\n     %s" % (c, rn, note))
print()
print("=== _rows length vars minting ===")
for (rn, note), c in rows_notes.most_common(8):
    print("\n%4d %s\n     %s" % (c, rn, note))