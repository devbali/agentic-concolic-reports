# `sweep_out_or/chain/` — policies built from two cloud boxes' packets

Two `comments_index` boxes in this sweep submitted a verified packet of dumps
but no policy: a sweep box produces dumps, assumptions and shim tests, and
nothing in the box runs the downstream Python stack.  These two directories
hold the result of running that stack **locally**, against each box's own
packet dumps and nothing else:

```
<box-id>/
  comments_index.policy.txt   the policy IR, text
  comments_index.sql          the SQL the domain layer rendered from it
  policy_result.json          the pipeline result (stages, failures, per-dump)
  pipeline.stderr             captured verbatim
```

Produced 2026-09-29 by

```bash
cd /home/dev/project
venvs/queries_from_runs/bin/python3 reports/autolab/e2e/tools/pipeline.py \
    comments_index \
    reports/autolab/entrypoints/sweep_out_or/boxes/<box-id>/out/packet/dumps \
    reports/autolab/entrypoints/sweep_out_or/chain/<box-id>/policy_result.json
```

which is the same operation `sweep_out_w4/chain/` records for `posts_destroy`.

**The provenance is split, and the split matters.** The dumps are cloud
evidence — a cloud agent drove the app on a sweep box.  The policy and the SQL
are local evidence — this workstation's pipeline, this workstation's `src_new`.
No policy in the autolab corpus was produced by a cloud agent.
`reports/autolab/finished/` carries that split per artefact rather than
labelling the whole run "cloud".

Both runs recorded every stage `ok`, with one `quality`-severity
`RenderIncomplete` failure each (conditions dropped from the rendered SQL).
Neither is complete in the checker's sense; see
`reports/autolab/finished/README.md`.
