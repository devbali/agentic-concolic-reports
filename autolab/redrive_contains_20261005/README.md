# `redrive_contains_20261005/` — the two endpoints re-driven after the `Contains` fix

`src_new` commit **`3c3aa88`** ("Contains took its arguments backwards in both
runtimes") fixed eight sites — four per runtime, `include?`/`__contains__` plus
three in `split`. `x.include?("@")` had been recording `Contains("@", x)`, and
Z3's `Contains(a, b)` means *a contains b*, so every containment predicate
either runtime ever emitted had its operands reversed.

The commit deliberately invalidated the affected corpora rather than
regenerating them. **Nine stored dumps across two endpoints** carried the old
text, and this directory is their re-drive, 2026-10-05.

```
e2e_round3/slice4/runs/diaspora_federation_h_card_hcard/   9 dumps  (8 affected)
e2e_round3/slice2/runs/status_messages_new/               21 dumps  (1 affected)
e2e_round3/slice{2,4}/results/<endpoint>.{json,policy.txt,sql}
prefix_backup/<endpoint>/                the evidence-store artefacts this
                                         replaced, verbatim — the pre-fix text
logs/                                    the driver and pipeline logs
```

The `e2e_round3/sliceN/` shape is **not a claim to be round 3**. It is the
layout `evidence_store/tools/sync_results.py::discover_local` reads, and the
names are chosen so that a sync of this root reproduces the run ids the store
already uses (`run_id = <root dir>.<slice dir>`). `source_root` in the resulting
provenance points here, which is the honest record.

## How it was driven

Exactly as the sweep drives an endpoint — same wrapper, same limits, read from
each endpoint's own `config.json` (`MAX_RUNS=24`, `TIME_BUDGET=300`, the values
round 3 drove):

```bash
systemd-run --user --scope -p MemoryMax=4G -p MemorySwapMax=0 \
  --setenv=DUMP_OUT=<this>/e2e_round3/sliceN/runs/<endpoint> \
  --setenv=MAX_RUNS=24 --setenv=TIME_BUDGET=300 \
  reports/autolab/e2e/tools/diaspora-concolic-mod \
  reports/autolab/entrypoints/scaffold/<endpoint>/run_dse.rb

venvs/queries_from_runs/bin/python3 reports/autolab/e2e/tools/pipeline.py \
  <endpoint> <this>/e2e_round3/sliceN/runs/<endpoint> \
  <this>/e2e_round3/sliceN/results/<endpoint>.json
```

## What changed, measured

**The path set did not move.** Measured against the artefacts in
`prefix_backup/`:

| | `h_card_hcard` | `status_messages_new` |
|---|---|---|
| dump filename set | identical (9) | identical (21) |
| per-dump path-condition count | identical, every dump | identical, every dump |
| distinct path signatures | 9 → 9 | 21 → 21 |
| `runs_executed` / `seed_sets_tried` / `distinct_paths` / `stack_remaining` | identical | identical |
| distinct PC atoms | 10 → 10 | 31 → 31 |
| PC atoms that changed | **1** | **1** |
| `unflippable_pcs` multiplicities | identical (8, 8) | identical (12, 1) |
| `policy.txt` | **byte-identical** | **byte-identical** |
| `rendered.sql` | byte-identical to what the build renders | byte-identical to what the build renders |
| pipeline `verdict`, `stages`, `reach_*`, `accepted_dumps`, `chosen_dump`, failure kinds | identical | identical |

The one changed atom per endpoint is exactly the swap:

```
old   Not(Contains(StringVal('@'), SYM_RESULT_…_diaspora_handle))        :: True
new   Not(Contains(SYM_RESULT_…_diaspora_handle, StringVal('@')))        :: True
```

Dump-for-dump, every file is either byte-identical or explained by that swap
alone, once two run-to-run nondeterminisms are normalised: JIT-compiled Haml
template method names (`_app_views_…_html_haml__<hash>_<id>`, a fresh hash per
JVM) and two source line numbers that moved because `autolab_dse.rb` and
`call_interceptor.rb` have gained lines since 2026-09-29.

### Why the path set could not move

The driver's four flip matchers (`autolab_dse.rb::flip_seed`,
`flip_len_seed`, `flip_len_many_seed`, `flip_length_seed`) are regexes over
`(X op lit)`, `len(X) != 0`, `len(X) > 1` and `Length(X) op n`. **None of them
matches `Contains(…)`**, so the atom is booked `unflippable` and no solver query
is ever made against it — before or after the fix. The unsoundness is real, but
on these two endpoints it lived entirely downstream of exploration.

And it never reached the policy either: `Contains(…)` is outside §7.2's
sub-language, so `build_policy` drops the carrying dump with
`DumpNotRepresentable` (severity `data`) in both the old and the new run. Hence
the byte-identical policy.

### One difference that is NOT the fix

The stored `result.json` recorded `completion.missing_branches = 3` for
`h_card_hcard`; the re-drive records `1`. That is **code vintage, not the
operand order**. A control — the *old* dumps pushed through *today's* pipeline
— also yields `1`. Both endpoints' `completion.blocking` lists likewise moved
because `note_check` has since left the generic engine's mandatory list. The
control run is reproducible from `prefix_backup/<endpoint>/dumps/`.

## What was refreshed, and what was deliberately left alone

Replaced in `evidence_store/endpoints/<endpoint>/local/e2e_round3.sliceN/`:
`dumps/*.json`, `exploration_summary.json`, `result.json`. Every new dump was
re-verified through the store's own gate (`concolic.model.run.load_run_dump`)
before it was written, and each artefact's `provenance.json` entry carries the
new `sha256`/`bytes`/`source` plus `sha256_before_redrive` and
`source_before_redrive`. A `redrive` block records the whole operation.

**Not** replaced:

* `policy.txt` — byte-identical, so there was nothing to replace.
* `rendered.sql` — the evidence store holds the **only surviving copy of the
  pre-fix renders** (`reports/autolab/README.md`), and `build_store.py` renders
  the deliverable's copy from `policy/policy.txt` anyway. Overwriting it would
  have destroyed history and changed nothing downstream.

Then `tools/build_store.py` (full run) and `tools/rerender.py` (dry: 164/164
already identical to a fresh render). The rebuild is idempotent — a second full
run leaves all 3109 files identical modulo `built_at`/`generated_at`.

## Still carrying the pre-fix text, and why

These are records of rounds that actually ran against the buggy runtime.
Rewriting them with a 2026-10-05 run would misattribute it, so they were left
intact:

| | |
|---|---|
| `e2e/runs/{diaspora_federation_h_card_hcard,status_messages_new}` | round 2 (9 + 1 affected dumps, plus 2 `exploration_summary.json`). Measured: all 30 of their dumps are identical to this re-drive's or explained by the swap alone, once Haml ids and `autolab_dse.rb`/`call_interceptor.rb` line numbers are normalised. Semantically the same explorations — but they are round 2's record |
| `shakedown/runs/diaspora_federation_h_card_hcard/dump_anon_html_dse0001.json` | round 1, a 2-run exploration (`MAX_RUNS=2`) against an 86-target library, not 87. Not the same run: its `status_messages_new` seed dump carries 2 path conditions where this re-drive's carries 16 |
| `entrypoints/sweep_out_or*/layer/*/batch/dumps/` | cloud-attempt records, 9 dumps each |
| `e2e/{INVENTORY.json,results_s6fix/*}`, `shakedown/{REPORT.md,SUMMARY.json,BEFORE_AFTER.json}` | dated analyses that quote the old text |
| `evidence_store/assumption_kinds_20261003/{default,conj}.json` | the 2026-10-03 confinement measurement. Its conclusion is a differential between two checker configurations over the *same* traces, so operand order cancels; only the quoted `missing_keys` string is stale |
| `_trash/autolab_history_20260930/…` | retired corpora, including round 3 |

### The one trap left open

`evidence_store/tools/sync_results.py` defaults `--local-root` to
`reports/autolab/archive/round3_local_verification`, which has since moved to
`_trash/autolab_history_20260930/archive/round3_local_verification` and still
holds the pre-fix dumps. **A verbatim re-sync would put the reversed text back
into the evidence store**, and the next `build_store.py` would carry it into the
deliverable. Point the sync at this directory's `e2e_round3/` for these two
endpoints, or fix the round-3 corpus, before trusting a re-sync.

Note also that `endpoints/` is built from `evidence_store/` **only** —
`build_store.py` never reads `e2e/` or `shakedown/`, so those corpora being
stale cannot by itself reintroduce anything.
