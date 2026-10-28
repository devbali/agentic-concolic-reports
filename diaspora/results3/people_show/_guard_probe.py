import json, glob

corpus = "reports/diaspora/results3/people_show/dump_*.json"
runs = []
for f in sorted(glob.glob(corpus)):
    try:
        runs.append(json.load(open(f)))
    except Exception:
        pass

def run_exprs(d):
    out = set()
    for ev in d.get("events", []):
        if ev.get("type") == "path_condition":
            out.add((ev.get("expr", ""), bool(ev.get("taken"))))
    return out

GUARDS = [
    ("first_1_not_found", "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)"),
    ("find_by_1_not_found", "(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True)"),
    ("first_1_closed", "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account == True)"),
    ("via_user_closed", "(SYM_PERSON_via_user_closed_account == True)"),
]
STREAM_EXPRS = [
    ("to_a_1_row_comments_count==1", "(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_comments_count == 1)"),
    ("author_guid != ''", "(assoc_author_guid != StringVal(''))"),
    ("records_1_rows>0", "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows > 0)"),
    ("to_a_1_rows != 0", "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_1_rows != 0)"),
]

print("=== guard-T AND stream-expr co-occurrence (expect 0) ===")
for glabel, gexpr in GUARDS:
    for slabel, sexpr in STREAM_EXPRS:
        co = 0
        for d in runs:
            rs = run_exprs(d)
            if (gexpr, True) in rs and (sexpr, True) in rs:
                co += 1
        if co:
            print("  %-16s AND %-28s -> %d runs  <<< CO-OCCURS" % (glabel, slabel, co))
print("(only co-occurring pairs printed; silence = all 0)")

# Also: does first_1_not_found coexist with ANY stream row expr at all?
print()
print("=== does any not_found/closed guard coexist with any stream-family expr T? ===")
stream_family = [s for _, s in STREAM_EXPRS]
for glabel, gexpr in GUARDS:
    n = 0
    for d in runs:
        rs = run_exprs(d)
        if (gexpr, True) not in rs:
            continue
        if any((s, True) in rs for s in stream_family):
            n += 1
    print("  %-16s guard-T runs with ANY stream-T: %d" % (glabel, n))