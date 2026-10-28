"""Registry check against the REAL diaspora app config + schema (read-only)."""
import sys, os
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, "/home/dev/project/src/queries_from_runs")
import test_queries_from_runs as H
from queries_from_runs.transform import RunTransformer
from queries_from_runs import app_config

CFG = "/home/dev/project/reports/diaspora/queries_config/app.json"
APP = app_config.load(CFG)
NEW = ('SELECT "people".* FROM "people" WHERE "people"."owner_id" = '
       "$$(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id) LIMIT 1")
OLD = "User#person (has_one)"
# the real 12-name column set X1 measured
COLS = ["id", "closed_account", "guid", "diaspora_handle",
        "serialized_public_key", "owner_id", "pod_id", "fetch_status",
        "created_at", "updated_at"]

for label, note in (("OLD prose", OLD), ("NEW statement", NEW)):
    run = H.make_run(
        [H.q("ActiveRecord::Relation.records", H.RECORDS_1,
             'SELECT "posts".* FROM "posts" WHERE "posts"."author_id" = '
             "$$(SYM_PERSON_via_user_id)")],
        extra_vars=[H._person_var("SYM_PERSON_via_user_" + c, note) for c in COLS])
    rt = RunTransformer(run, param_pool=[], app_config=APP)
    print(f"{label:14} bind_producers={ {k: v.primary_table for k, v in rt.bind_producers.items()} }")
    print(f"{'':14} errors={rt.errors}")
    rq = rt.transform_all()
    (s,) = H.sqls(rq)
    print(f"{'':14} emitted: {s}")
