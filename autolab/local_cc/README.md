# `reports/autolab/local_cc/` — one endpoint, the real chain, locally

**What this is.** The four-stage sweep chain driven for ONE endpoint
(`posts_destroy`) with the `host` execution backend and **Claude Code as the
agent backend**, on this machine, with no VM and no cloud spend. Every stage
goes through `sweep.binding.WorkerLayer.run(WorkRequest)` — the one method
`sweep/coordinator/driver.py`'s `Workers` protocol names. Nothing here
re-implements a worker stage, rebuilds a `WorkerSpec`, patches a plan, or names
an interpreter for a box.

It is `tests/sweep_e2e/test_cloud_chain_composes.py`'s co-located control
(`test_the_same_layer_on_a_colocated_backend_is_unchanged`) with the fakes
removed: the real `claude` binary behind the real `ClaudeCodeBackend`, the real
`concolic.check`, the real `python -m concolic.review`.

## Files

| path | what it is |
|---|---|
| `drive.py` | the CALLER. §7.8 makes constructing the agent adapter the caller's, and `binding.py` names four other things the seam does not carry. This is all of them and nothing else. One stage per invocation. |
| `sweep_local.json` | §4's spec. One endpoint, `home: local`, `box: md`, `agents.batch.backend: claude-code`. |
| `sweep_local_check.json` | the same spec with `boxes.md.max_wall_s` raised — see `SPEC_NOTES.md`. |
| `inputs/posts_destroy_config.json` | the endpoint's config. A COPY of `entrypoints/scaffold/posts_destroy/config.json` plus a `completion` block; the scaffold is shared and was not touched. The packet's `config_digest` binds to this file. |
| `addendum_local.md` | this campaign's operator addendum to the shipped `sweep/briefs/batch.md`, attached after `reports/autolab/docs/briefs_addendum.md`. Nine sections, every measured number in it measured here today. |
| `agent_config/` | the agent's `CLAUDE_CONFIG_DIR`: a symlink to the operator's `.credentials.json` (claude.ai subscription login — no `ANTHROPIC_*` override is set anywhere, per CLAUDE.md) and a `settings.json` that allow-lists the tools, grants the box's own directories, and DENIES writes to `src/`, `src_new/`, `reports/diaspora/`, the shared autolab trees, the app repo and the config. |
| `boxes/` | the box trees, one per attempt. On `host` a box IS a directory. |
| `layer/posts_destroy/batch/` | the `rw` batch directory, shared across attempts by design. |
| `state/` | what crosses a stage boundary: the response handed to each attempt, the packet path, the review items, the answers, the approval hash, each stage's outcome. |
| `attempts/` | preserved evidence from attempts that did not submit. |
| `probe/`, `probe_deep/`, `preflight/` | the operator's own feasibility probes, run BEFORE the campaign (see below). They are diagnostics, not part of any claim. |

## How to run it

```
python3 drive.py --stage batch   --attempt N     # §6.2, an agent in a box
python3 drive.py --stage review  --attempt N     # §5.2 steps 1-3, then STOP
#   ... write state/answers-N.json: one answer per item, with its own reason
#       and the consequence it would let through (§5.2 step 4)
python3 drive.py --stage approve --attempt N     # binds them: approval_hash
python3 drive.py --stage check   --attempt N     # §6.1, on its own box
```

There is deliberately no `--stage all`: §5.2 step 4 is a judgment, and a driver
that ran straight through would have to answer the review's items itself.

## What was probed before the campaign, and why

Three things had to be known before the config could be frozen, because the
packet's `config_digest` binds the config and a config change after a batch
invalidates its packet:

1. **`probe/`** — can the explorer run on this machine at all?
   Yes: 4 runs in 13.2 s after a 6 min 33 s cold Rails boot.
2. **`probe_deep/`** — is coverage-completeness REACHABLE for this endpoint, or
   would the campaign be chasing something impossible? `MAX_RUNS=150` drove 130
   runs / 29 distinct paths in 65.8 s and ended `worklist empty : true`; the
   checker's coverage layer over those 29 dumps reported `missing_branches 0`,
   `tree_complete true`. So it is reachable, and the campaign is a real test of
   whether an agent gets there rather than a test of whether the endpoint can.
3. **`preflight/`** — does the `completion` block's shim gate actually work?
   Run against the PREVIOUS attempt's packet it failed, and failed in the worst
   possible way: `shim_test_runner.rb` aborted with `shim_tests.rb must define
   SHIM_TESTS`, wrote no results file, and `concolic.checks.shims.test_shims`
   raised `RuntimeError` — which propagates out of `attach_to_summary`, out of
   `check()`, and leaves NO REPORT AT ALL. A malformed gate artefact therefore
   costs the whole pass, coverage verdict included, rather than costing its own
   gate a red. Two things came out of that: `addendum_local.md` §9, which tells
   the agent the format and tells it that omitting the key is safe and
   malformed Ruby is not; and `_gate_artefact_guard` in `drive.py`, which is the
   reviewer refusing to feed such a packet to a check box.

## The `completion` block, and the one gate that is not in it

`inputs/posts_destroy_config.json` configures the **shim gate** (extractor +
test runner) and the **assumption gate** (driver), taking `shim_tests` and
`assumption_cfg` from the PACKET, as `completion_config_of` requires.

`note_check` is **not** configured, and cannot honestly be. Its artefact is
`concrete_run.json`, a real-mode recording: `completion_config_of` excludes it
from the packet→config table by design ("it stays NOT CONFIGURED until real-mode
execution exists"), the checker's own `real_mode` step reports
`not_implemented`, this endpoint's config declares `fixtures: null` and
`real_mode_plan: null`, and `sweep/briefs/batch.md` forbids an agent from
supplying one. `run_completion` makes note_check MANDATORY, so `completion.complete`
— and therefore `complete` — cannot be true for this endpoint. That is stated
rather than worked around: a fabricated recording would make every downstream
gate lie.

## Result, 2026-09-30

Target: **coverage-complete** (blockers 1 and 2 of the 2026-09-29 report).
`complete: true` was assessed as unreachable for this endpoint before the run
started, for the reason in the section above, and it was not chased.

| | 2026-09-29 (cloud, inherited corpus) | 2026-09-30 (this run) |
|---|---|---|
| corpus | 14 dumps, `"inherited": true` | **29 dumps, produced in the box** |
| `coverage_complete` | false | **true** |
| `missing_branches` | 8 | **0** |
| `tree_complete` | false (2 missing prefixes) | **true** (0) |
| `truncated` / `solver_lost` | false / 0 | false / 0 |
| shim gate | not configured | **ok** — 22 extracted, 10 PASS + 12 PROTOCOL, 0 red |
| assumption gate | not configured | **ran** (627 s), 11 pairs tested |
| `note_check` | not configured | not configured (structural — see above) |
| `wall_clock_terminated` | false | false |
| `complete` | false | false |
| blocking lines | 3 | 12 (1 × note_check, 11 × confinement NOT-TESTABLE) |

Artefacts: packet `boxes/posts_destroy-batch-2-a64eb674/out/packet/`, review doc
`review/attempt-2.json`, answers `state/answers-2.json`, report
`boxes/posts_destroy-check-2-d3502fe7/out/report.json`, rows `out/workers.jsonl`.

Attempt 1 (`attempts/attempt1_write_denied/`) reached the same corpus and
submitted nothing: its sub-agent's `Write` to `batch/` was denied because on
`host` the `rw` batch directory is a symlink OUT of the box root and the harness
treats that as outside its working directory. Fixed by granting the box's own
directories in `agent_config/settings.json` (`permissions.additionalDirectories`).
