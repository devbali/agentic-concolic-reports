import json, glob
from collections import Counter

corpus = "reports/diaspora/results3/people_show/dump_*.json"
runs = []
for f in sorted(glob.glob(corpus)):
    try:
        runs.append(json.load(open(f)))
    except Exception:
        pass

# What vars exist mentioning records_1 / records_2 / to_a_1?
names = Counter()
for d in runs:
    for v in d.get("symbolic_vars", []):
        n = v.get("name", "")
        if "records_1" in n or "records_2" in n or "to_a_1" in n or "records_3" in n:
            names[n] += 1
print("=== symbolic var names (records_1/2/3, to_a_1) ===")
for n, c in names.most_common(30):
    print("%6d  %s" % (c, n[:130]))

# Now the co-occurrence probes
def run_exprs(d):
    """Set of (expr, taken) pairs."""
    out = set()
    for ev in d.get("events", []):
        if ev.get("type") == "path_condition":
            out.add((ev.get("expr", ""), bool(ev.get("taken"))))
    return out

# candidate artifact pairs
pairs = [
    ("records_1 len==0", "Not((SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1 != 0))",
     "records_1 rows>0", "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows > 0)"),
    ("records_1 len==0", "Not((SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1 != 0))",
     "records_1 rows!=0", "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows != 0)"),
    ("records_2 len==0", "Not((SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2 != 0))",
     "records_2 rows>0", "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2_rows > 0)"),
    ("records_2 len==0", "Not((SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2 != 0))",
     "to_a_1 rows!=0", "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_1_rows != 0)"),
]

print()
print("=== co-occurrence probes (expect 0 for artifacts) ===")
for la, ea, lb, eb in pairs:
    co = 0
    for d in runs:
        rs = run_exprs(d)
        if (ea, True) in rs and (eb, True) in rs:
            co += 1
    print("  %-28s AND %-24s -> %d runs" % (la, lb, co))