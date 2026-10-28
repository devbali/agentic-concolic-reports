import json, glob, re, collections
B = "/home/dev/project/reports/diaspora/results3/notifications_index"
# Scan events across a sample of dumps for roles/COUNT/SUM/pluck + key decisions
roles = collections.Counter()
sums = collections.Counter()
counts = collections.Counter()
plucks = collections.Counter()
txt = collections.Counter()
ntype = collections.Counter()
n = 0
for fp in sorted(glob.glob(B + "/dump_*.json"))[:1200]:
    try:
        with open(fp) as f: d = json.load(f)
    except Exception:
        continue
    n += 1
    for e in d.get("events") or []:
        note = e.get("note", "") or ""
        tgt = e.get("target", "") or ""
        rn = e.get("result_name", "") or ""
        if "roles" in note and "FROM" in note:
            roles[note[:130]] += 1
        if "COUNT(" in note or "count" in note.lower() and "FROM" in note:
            counts[note[:130]] += 1
        if "SUM(" in note:
            sums[note[:130]] += 1
        if "pluck" in tgt.lower() or "pluck" in rn.lower():
            plucks[(tgt, note[:110])] += 1
        if "SYM_NOTE_TYPE_PROFILE" in (note) or ("type" in note and "profile" in note.lower()):
            txt[note[:100]] += 1
print("dumps:", n)
print("\n=== roles-family events (sample) ===")
for k, c in roles.most_common(6):
    print(c, k)
print("\n=== COUNT-family events (sample) ===")
for k, c in counts.most_common(8):
    print(c, k)
print("\n=== SUM-family events (sample) ===")
for k, c in sums.most_common(5):
    print(c, k)
print("\n=== pluck-family events (sample) ===")
for k, c in plucks.most_common(8):
    print(c, k)