# `reports/autolab/e2e/` — the per-endpoint issue inventory, and the repairs

> **Looking for `_round1/`, `logs/`, `dryrun/`, `fixtrial*/` or `results/`?**
> They were moved to `_trash/autolab_history_20260930/e2e/` on 2026-09-30 and
> nothing was deleted — see [`_MOVED.md`](_MOVED.md).

This directory answers, for **each of the 161 scaffolded endpoints
individually**: what ran, where it stopped and why, what it produced, and what
is wrong with it. The two shakedown runs before it answered a different
question — does the machinery work — and their "154 ran clean" concealed that
most endpoints reach almost nothing.

## Layout

```
tools/
  sweep.py            the sweep driver: one OS process per endpoint, par 3,
                      systemd scope per process (named, so it can be reaped),
                      per-endpoint checkpoint, disk budget
  pipeline.py         the Python half, per endpoint: dump IR -> reach ->
                      run_complete (WITH a CompletionConfig) -> build_policy
                      -> normalize -> policy text -> SQL render
  build_inventory.py  the artifacts -> one record per endpoint -> the ranked
                      issue list
  sweep_fixtrial.py   the same sweep pointed at a patched COPY of the driver
                      and targets, so a fix can be measured without touching
                      the tree a running sweep is reading
  diaspora-concolic-mod   RAILS_ENV=concolic_mod launcher (copy; the shared
                      scripts/diaspora-concolic hard-codes RAILS_ENV=concolic
                      and other people's jobs use it)

runs/<id>/            dump_*.json + exploration_summary.json
logs/<id>.log         the runner's stdout+stderr
results/<id>.json     the pipeline's per-endpoint result (+ .policy.txt, .sql)
manifest.jsonl        one checkpoint row per finished endpoint
INVENTORY.json        one record per endpoint
INVENTORY.csv         the same, flat
INVENTORY_RANKED.json issues ranked by how many endpoints each affects
REPORT.md             the written summary
findings/             write-ups for defects in trees I may not edit
fixes/                every repair, as an anchored, reversible patch script
probes/               one-question experiments and their raw output
fixtrial/             a patched copy of driver+targets, and its results
dryrun/               the `sweep.testbed` campaign spec
```

## The evidence standard this directory holds itself to

* **A stopping site is read off the live exception object**, never matched out
  of log text: exception class, `NameError#name`, `NameError#receiver.class`,
  and the real `backtrace`. The driver records these per RUN, including for a
  run whose dump was discarded as a duplicate path.
* **Two endpoints share an issue code only when they agree on
  `(exception class, missing method, receiver class, raising file:line)`.**
  The same message is never enough on its own. Where a code is assigned on
  something weaker, the code's own `basis` field says so.
* **A count is not a cause.** One measurement in this directory was WRONG and
  is corrected in place rather than quietly dropped: an early test appeared to
  show that killing a timed-out endpoint by process group left two descendants
  alive. It did not — the check was a `pgrep -f` inside `bash -c`, and it
  counted its own command line. See `tools/sweep.py:cage`.

## What one endpoint's record contains

`INVENTORY.json` is `{endpoint: record}`. Each record:

```
endpoint, entrypoint, signed_in, format, targets_tier, attempted

stages.run            rc, timed_out, seconds, runs_executed, distinct_paths,
                      dumps_written, worklist_exhausted, stack_remaining,
                      max_runs, dse_seconds, harness_errors
stages.dump_ir        verdict, dumps_accepted, refused[]
stages.run_complete   verdict, complete, coverage_complete, tree_complete,
                      missing_branches, truncated, solver_lost, total_runs,
                      gate_states{shims,note_check,assumptions,foreclosure},
                      blocking[]
stages.build_policy   verdict, atoms_unmerged, atoms_normalized, signatures,
                      minimal, policy_text_lines,
                      opaque{defects,by_design,unreferenced,all}
stages.normalize      verdict
stages.policy_text    verdict
stages.render_sql     verdict, views, unsupported_atoms, unrendered_atoms,
                      dropped_conditions, sql_lines,
                      atoms_lost_to_note_envelope

stops[]               one row per EXECUTED run, including runs whose dump was
                      discarded as a duplicate path:
                        label, dump_written, path_conditions,
                        type, message, missing_name, receiver_class,
                        receiver_inspect, raising_frame, raising_file_line,
                        raising_method, first_app_frame, first_autolab_frame,
                        backtrace[40], cause, param,
                        handled[]   -- exceptions a rescue_from took
stop_site_counts[]    the same, grouped by (type, name, receiver, file:line)
dominant_stop         the site most runs ended at

dumps[]               per dump: file, ir, path_conditions, event_counts,
                      declared_target_functions, declared_shims,
                      n_declarations, reach, reached[], call_targets[],
                      terminal_type, pc_exprs[]
reach_best            |declared target_functions ∩ called| in the best dump
reach_union           the same, unioned over every dump
declaration_table_sizes  §4.1.1f table size per dump — a process that reused
                      `install!` would show a table that grows

solver.failed_constraints   `Failed to parse constraint` from the pipeline's
                      own stderr. BLOCKING: `check_satisfiability` returns
                      UNSAT on a parse failure.
solver.failed_var_decls     `Failed to eval var decl`. NOT blocking — a
                      solver term is left unrenamed on purpose.

notes.census          accesses classified select / write / nonquery / prose /
                      absent, with the domain's own classifier
issues[]              {code, basis, evidence, blocking, note}
```

`INVENTORY_RANKED.json` groups the issue codes and ranks them by
`endpoints_affected`. That ranking is the worklist.

---

## Final state (2026-09-26)

Two full sweeps of all 161 endpoints:

* **round 1** — the inventory of what was wrong, archived at `_round1/`
  (`manifest.jsonl`, `runs/`, `logs/`, `results/`, `INVENTORY*`).
* **round 2** — the same corpus after thirteen repairs. `manifest.jsonl`,
  `runs/`, `logs/`, `results/`, `INVENTORY.json` / `.csv` /
  `INVENTORY_RANKED.json` at the top level.

Read in this order:

1. `VERDICT.md` — the answer: will a sweep complete, and what still blocks
   depth, ranked.
2. `REPORT.md` — the written report, numbers generated from `INVENTORY.json`
   by `tools/report.py`, prose from `REPORT_PROSE.md`.
3. `INVENTORY.csv` — one row per endpoint, for reading and diffing.
4. `INVENTORY_RANKED.json` — the issues ranked by endpoints affected: the
   worklist.
5. `findings/SRC_NEW_DEFECTS.md` — S-1…S-7, defects in a tree I may not edit.
6. `findings/AUTOLAB_GAPS.md` — G-1…G-5, things I could have changed and
   deliberately did not.
7. `fixes/SHARED_BOUNDARY_DECISION.md` — what I tried on the shared target
   library, what its own suite refused, and what I did instead.

`tools/compare_rounds.py _round1/INVENTORY.json INVENTORY.json` prints the
round-1→round-2 diff, regressions first.
