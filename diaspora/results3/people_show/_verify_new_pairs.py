import importlib.util

spec = importlib.util.spec_from_file_location("ca", "reports/diaspora/results3/people_show/coverage_assumptions.py")
ca = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ca)
a = ca.build()
ind = [x for x in a.assumptions if type(x).__name__ == "IndependenceAssumption"]

REC1 = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1 != 0)"
REC2 = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2 != 0)"
REC1_ROWS = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows > 0)"
TOA_ROWS = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_to_a_1_rows != 0)"
REC2_15 = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2_rows == 15)"
REC3_POS = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_3_rows > 0)"
ROWCC1 = "(SYM_RESULT_ActiveRecord__Relation_to_a_1_row_comments_count == 1)"
AUTHGUID_NE = "(assoc_author_guid != StringVal(''))"
GUARDS = [
    "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True)",
    "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account == True)",
    "(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True)",
    "(SYM_PERSON_via_user_closed_account == True)",
]

pairs = set((x.expr_a, x.expr_b) for x in ind)
pairs |= set((x.expr_b, x.expr_a) for x in ind)

print("--- 6b same-query length-form pairs (expect 8) ---")
want6b = []
for rel in (REC1, REC2):
    for rows in (REC1_ROWS, TOA_ROWS, REC2_15, REC3_POS):
        want6b.append((rel, rows))
for p in want6b:
    print("OK " if p in pairs else "MISS", p[0][:60], "x", p[1][:60])

print("--- 4b guard x complement pairs (expect 8) ---")
want4b = []
for g in GUARDS:
    for c in (ROWCC1, AUTHGUID_NE):
        want4b.append((g, c))
for p in want4b:
    print("OK " if p in pairs else "MISS", p[0][:60], "x", p[1][:60])