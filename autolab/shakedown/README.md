# `reports/autolab/shakedown/` — the one-or-two-dumps-per-endpoint shakedown

> **Looking for run 1, `results/` or `logs/`?** They were moved to
> `_trash/autolab_history_20260930/shakedown/` on 2026-09-30 and nothing was
> deleted — see [`_MOVED.md`](_MOVED.md).

The **scaffolded → verified** promotion (`src_new/README.md` §"The shakedown:
one or two dumps for EVERY endpoint") run over every scaffolded auto-lab
endpoint in `reports/autolab/entrypoints/scaffold/`.

This is a **shakedown of the machinery, not a coverage campaign**.
`complete: false` is the expected and correct result and is counted as a
PASS; a checker answering `true` on one or two dumps would itself be the
defect.

## What is run, per endpoint

| stage | what | tool |
|---|---|---|
| run | the generated runner, `MAX_RUNS=2` | `scripts/diaspora-concolic` |
| dump IR | `Run.from_dict` + `validate_provenance` (R1–R4) | `tools/pipeline.py` |
| reach | \|declared `target_function`s ∩ targets called\| | `tools/pipeline.py` |
| checker | `concolic.check.run_complete` | `tools/pipeline.py` |
| policy | `dumps_to_policy.build.build_policy` → `normalize_detailed` → `print_policy` | `tools/pipeline.py` |
| SQL | `domains.ruby_rails_sql.render.render_sql` | `tools/pipeline.py` |

## Layout

```
shakedown/
├── README.md          this file
├── REPORT.md          THE RESULT — per-endpoint counts, every failure named,
│                      plus the run-1 → run-2 before/after section
├── SUMMARY.json       the same numbers, machine-readable
├── BEFORE_AFTER.json  the full two-run comparison, machine-readable
├── manifest.jsonl     the resumable checkpoint, one line per finished endpoint
├── sweep.out          the sweep's own stdout
├── _run1_20260925/    RUN 1, preserved whole (REPORT.md, SUMMARY.json,
│                      manifest.jsonl, runs/, logs/, results/, sweep.out)
├── runs/<id>/         dump_*.json + exploration_summary.json  (DUMP_OUT)
├── logs/<id>.log      the runner's stdout/stderr
├── results/<id>.json  the per-endpoint pipeline result
├── results/<id>.policy.txt   the printed policy IR
├── results/<id>.sql          the rendered SQL views
└── tools/
    ├── sweep.py       orchestrator: 3-way concurrency, one OS process per
    │                  endpoint, systemd-run MemoryMax cage, checkpointing
    ├── pipeline.py    the python half, for ONE endpoint
    ├── repipe.py      re-run only the pipeline stage over dumps on disk
    ├── report.py      manifest + results -> SUMMARY.json
    └── compare_runs.py  two run trees -> BEFORE_AFTER.json (counts, DML
                       notes, reach, profiles, failures), drives nothing
```

Nothing is written into `entrypoints/scaffold/` — that tree is generated, so
the runner's `DUMP_OUT` is pointed here instead.  Nothing under `src/` or
`src_new/` is modified.

## Box discipline observed

At most 3 endpoints in flight; every process inside its own
`systemd-run --user --scope -p MemoryMax=…` cgroup; one OS process per
endpoint, never reused (`install!` is not idempotent).  The box's
pre-existing long-running jobs were left untouched.

## Resuming

`tools/sweep.py` skips every endpoint already in `manifest.jsonl`, so an
interruption costs one endpoint:

```bash
venvs/queries_from_runs/bin/python3 tools/sweep.py --par 3
```


## Runs

| run | when | library | result |
|---|---|---|---|
| 1 | 2026-09-25 21:12 → 00:10 | pre-D1–D8 | 154 clean / 0 no-paths / 7 failed; 322 kind conflicts |
| 2 | 2026-09-26 01:40 → 04:31 | D1–D8 + N1/N4/N5/N6 fixed, 2 reclassifications | 154 / 0 / 7; **0 kind conflicts** |

Run 2 used byte-identical harness files and identical knobs, so the diff is
interpretable. `REPORT.md` §9 is the at-a-glance comparison.

```bash
venvs/queries_from_runs/bin/python3 tools/compare_runs.py \
    _run1_20260925 . BEFORE_AFTER.json
```
