"""B-2 ground-truth differential, part 2 (scratch; reads only).

(1) Does the NEW note register a BIND PRODUCER where the OLD one did not?
(2) With app.json's blanket `identity_prefix` veto retired -- which the
    BOUNDARY_NOTE_GAPS doc says becomes possible exactly once the mint records
    its statement -- does the recursion resolve the bind, and does it resolve
    it to the VIEWED person rather than to the principal?
"""
import copy, json, sys, tempfile, os
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, "/home/dev/project/src/queries_from_runs")
import test_queries_from_runs as H
from queries_from_runs.transform import RunTransformer
from queries_from_runs import app_config

OLD = "User#person (has_one)"
NEW = ('SELECT "people".* FROM "people" WHERE "people"."owner_id" = '
       "$$(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id) LIMIT 1")
COLS = ["id", "owner_id", "guid", "closed_account", "pod_id", "created_at"]

def build(note):
    return H.make_run(
        [H.q("ActiveRecord::Relation.records", H.RECORDS_1,
             'SELECT "posts".* FROM "posts" WHERE "posts"."author_id" = '
             "$$(SYM_PERSON_via_user_id)")],
        extra_vars=[H._person_var("SYM_PERSON_via_user_" + c, note) for c in COLS])

# --- (1) registry ---------------------------------------------------------
print("== (1) bind-producer registration (app config UNCHANGED)")
for label, note in (("OLD prose", OLD), ("NEW statement", NEW)):
    rt = RunTransformer(build(note), param_pool=[], app_config=H.APP_A)
    print(f"  {label:14} bind_producers={ {k: v.primary_table for k, v in rt.bind_producers.items()} }")

# --- (2) with the identity vetoes retired --------------------------------
raw = copy.deepcopy(H._APP_A_JSON)
b = raw["principal"]["binds"]
del b["identity_id"]; del b["identity_prefix"]
del b["non_principal_identity_name"]; del b["non_principal_identity_note"]
d = tempfile.mkdtemp()
# reuse APP_A's schema files
import shutil
for f in os.listdir(os.path.dirname(H.APP_A_PATH)):
    src = os.path.join(os.path.dirname(H.APP_A_PATH), f)
    if os.path.isfile(src) and f != "app.json":
        shutil.copy(src, d)
json.dump(raw, open(os.path.join(d, "app.json"), "w"))
APP_NOVETO = app_config.load(os.path.join(d, "app.json"))

print("== (2) identity_id / identity_prefix / both non_principal_* vetoes REMOVED")
for label, note in (("OLD prose", OLD), ("NEW statement", NEW)):
    rq = RunTransformer(build(note), param_pool=[], app_config=APP_NOVETO).transform_all()
    (s,) = H.sqls(rq)
    print(f"  {label:14} {s}")
    print(f"  {'':14} _MY_UID present: {'_MY_UID' in s}")
