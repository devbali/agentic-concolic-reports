#!/usr/bin/env python3
"""One ARM of the E12 old-vs-new reconstruction differential.

Runs the DEPLOYED pipeline (variant_d assoc_fold + AssocFoldingTransformer,
exactly what the extractors install) over a seeded random sample of one
corpus, and writes a per-run fingerprint of the emitted view list plus the
deduped global view set. Two arms (old src snapshot vs new src) are compared
by compare.py. Read-only over the corpora.

  usage: diffarm.py <corpus_dir> <sample> <seed> <out_prefix> [<list_file>]

<list_file> freezes the sample: the FIRST arm writes it, the second replays it
verbatim, so both arms see the same dumps even while other agents add more.
"""
import glob, hashlib, json, os, random, sys

os.environ.setdefault("QFR_APP_CONFIG",
                      "/home/dev/project/reports/diaspora/queries_config/app.json")
sys.path.insert(0, "/home/dev/project/reports/diaspora/results3/_experiment/variant_d")

import assoc_fold
assoc_fold.install()
from assoc_fold import AssocFoldingTransformer
from queries_from_runs.dump import _load_run, discover_param_pool

corpus, sample, seed, out_prefix = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
listfile = sys.argv[5] if len(sys.argv) > 5 else None
# BOTH ARMS MUST SEE THE SAME FILES: other agents add dumps to these corpora
# while this runs, so the first arm freezes the sample into <listfile> and the
# second arm replays it verbatim.
if listfile and os.path.exists(listfile):
    paths = [l for l in open(listfile).read().splitlines() if l]
    pop = int(open(listfile + ".pop").read().strip())
else:
    paths = sorted(glob.glob(os.path.join(corpus, "dump_*.json")))
    pop = len(paths)
    if sample and sample < pop:
        random.seed(seed)
        paths = sorted(random.sample(paths, sample))
    if listfile:
        with open(listfile, "w") as f:
            f.write("\n".join(paths) + "\n")
        with open(listfile + ".pop", "w") as f:
            f.write(str(pop) + "\n")
param_pool = discover_param_pool(list(paths))

per_run = {}
views = set()
n_runs = 0
n_views = 0
flags = {}
errs = 0
for p in paths:
    run = _load_run(p)
    if run is None:
        continue
    n_runs += 1
    try:
        rq = AssocFoldingTransformer(run, param_pool=param_pool).transform_all()
    except Exception as e:
        per_run[os.path.basename(p)] = ["EXC:" + type(e).__name__ + ":" + str(e)[:80], -1]
        errs += 1
        continue
    sqls = sorted(q.sql for q in rq.queries)
    n_views += len(sqls)
    views.update(sqls)
    for q in rq.queries:
        for f in q.flags:
            flags[f] = flags.get(f, 0) + 1
    per_run[os.path.basename(p)] = [
        hashlib.sha1("\n".join(sqls).encode()).hexdigest(), len(sqls)]

with open(out_prefix + ".views", "w") as f:
    for v in sorted(views):
        f.write(v + "\n")
with open(out_prefix + ".json", "w") as f:
    json.dump({"corpus": corpus, "population": pop, "sampled": len(paths),
               "runs": n_runs, "views_emitted": n_views,
               "distinct_views": len(views), "transform_exceptions": errs,
               "flags": flags, "per_run": per_run}, f)
print(f"{os.path.basename(corpus):22s} pop={pop:7d} sampled={len(paths):6d} "
      f"runs={n_runs:6d} views={n_views:7d} distinct={len(views):5d} exc={errs}")
