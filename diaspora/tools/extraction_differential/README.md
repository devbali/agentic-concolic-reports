# extraction_differential — old-vs-new rendering differential over the corpora

The harness behind `_E12_APP_AGNOSTIC_20260911.md` §3.3, kept because **any**
change that can move reconstruction output needs this evidence: a
`transform.py` / `pcs.py` / `schema.py` edit, a fold-patch change, or an edit
to `queries_config/app.json`'s `schema` / `principal` / `inflections` blocks.

```
diffarm.py <corpus_dir> <sample> <seed> <out_prefix> [<list_file>]
compare.py <old.json> <new.json>
run_diff.sh            # all six corpora, both arms, SAMPLE=3000 by default
```

**How it works.** `diffarm.py` runs ONE ARM: the deployed pipeline
(`variant_d/assoc_fold.install()` + `AssocFoldingTransformer`, i.e. exactly
what the extractors install) over a seeded random sample of one corpus, and
writes a per-run fingerprint (sha1 of the run's sorted emitted-view list, plus
the view count) and the deduped global view set. `compare.py` reports
`RUNS DIFFERING` (runs whose fingerprint moved) and `VIEWS DIFFERING` (the
symmetric difference of the two global view sets), plus any per-flag count
change.

Two arms, two `PYTHONPATH`s:

```sh
# OLD arm — a snapshot of the pre-change package, imported AS queries_from_runs
PYTHONPATH=<snapshot_dir>:/home/dev/project/src  python3 diffarm.py ...
# NEW arm
PYTHONPATH=/home/dev/project/src                 python3 diffarm.py ...
```

Make the snapshot with `tar` (exclude `blockaid/`), and if the snapshot
computes paths from `__file__`, repoint its `_HERE` at the real tree so its
defaults resolve as they did in place.

**The sample is frozen between arms.** Other agents add dumps to these
corpora while this runs, so the first arm writes its sampled paths to
`<list_file>` (+ `<list_file>.pop`) and the second arm replays that list
verbatim. Never compare two arms that each drew their own sample.

Read-only over the corpora, no checker, no JVM. Cage each arm:

```sh
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=1G \
  choom -n 1000 -- env PYTHONPATH=... python3 diffarm.py ...
```

Observed cost: ~2 minutes and ~45 MB per arm at `SAMPLE=3000`.
