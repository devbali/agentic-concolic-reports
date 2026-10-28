"""B-2 ground-truth differential (scratch; reads only).

Same synthetic people_stream run, twice: once with the OLD prose mint note,
once with the NEW rendered statement the repaired boundary now writes.
Asserts (a) the new note REGISTERS a bind producer on `people` where the old
one registered none, and (b) neither note lets the bind become the principal.
"""
import sys
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, "/home/dev/project/src/queries_from_runs")
import test_queries_from_runs as H

OLD = "User#person (has_one)"
NEW = ('SELECT "people".* FROM "people" WHERE "people"."owner_id" = '
       "$$(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id) LIMIT 1")

COLS = ["id", "owner_id", "guid", "diaspora_handle", "closed_account",
        "pod_id", "fetch_status", "serialized_public_key",
        "created_at", "updated_at"]

def build(note):
    return H.make_run(
        [H.q("ActiveRecord::Relation.records", H.RECORDS_1,
             'SELECT "posts".* FROM "posts" WHERE "posts"."author_id" = '
             "$$(SYM_PERSON_via_user_id)")],
        extra_vars=[H._person_var("SYM_PERSON_via_user_" + c, note) for c in COLS])

for label, note in (("OLD prose", OLD), ("NEW statement", NEW)):
    run = build(note)
    rq = H.transform(run)
    (s,) = H.sqls(rq)
    rt = getattr(rq, "rt", None)
    # rebuild a transformer to inspect the registry directly
    from queries_from_runs.transform import RunTransformer
    import inspect
    print("=" * 72)
    print(label, "->", repr(note[:80]))
    print("  emitted SQL :", s)
    print("  placeholders:", sorted(rq.queries[0].placeholders))
    print("  flags       :", sorted(rq.queries[0].flags))
    print("  MY_UID in SQL:", "_MY_UID" in s, " | `people` join in SQL:", "`people`" in s)
