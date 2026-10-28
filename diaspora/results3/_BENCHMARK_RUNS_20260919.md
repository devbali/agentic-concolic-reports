# Benchmark runs — 2026-09-19 (session of 2026-09-18)

Four diaspora endpoints, graded against the **external**
`policy-extraction-bench` and against the project's own **policy-loadability**
audit. Candidate policy in every case is `<endpoint>_pcfold3_fix.sql` — the
`--reliable-pruning-witnesses` arm, established below as the intended-to-ship
one.

Two independent axes. They are not two views of the same thing.

| axis | tool | question |
|---|---|---|
| **benchmark match** | `bench.grade` (`disclosure_*`) | does our extracted policy name the same data as the benchmark's REFERENCE policy? |
| **policy loadable** | `policy_loadability_audit.py` | does the file that SHIPS actually load, every bind resolved? |

A third axis — the Z3 completion gate — was started and then **stopped by
direction**; see §4. No completeness verdict was obtained and nothing here
should be read as one.

---

## 1. Consolidated results

| endpoint | task_id | ref stmts | our stmts | disclosure P | disclosure R | table P/R | stmt F1 | policy loadable | containment |
|---|---|---:|---:|---:|---:|---|---:|---|---|
| comments_index | `diaspora/comments-index` | 23 | 155 | 0.9510 | **1.0000** | 1.000/1.000 | 0.1907 | **pass** 155/155 | infeasible |
| conversations_index | `diaspora/conversations-index` | 16 | 465 | 0.9211 | 0.8898 | 0.733/1.000 | 0.0413 | **pass** 465/465 | infeasible |
| notifications_index | `diaspora/notifications-index` | 71 | 142 | 0.9432 | 0.9940 | 0.900/1.000 | 0.3943 | **pass** 142/142 | infeasible |
| people_stream | `diaspora/people-stream` | 168 | 169 | 0.9695 | **1.0000** | 1.000/1.000 | 0.5242 | **RED** 146/169 | infeasible |

`bench.grade` aggregate over the four: **disclosure_precision 0.9462**,
**disclosure_recall 0.9709**, disclosure_f1 0.9581, table_f1 0.9484,
disclosure_macro_f1 0.8598, statement_f1 0.2876. **0 errored, 0 missed tables**
on any task.

Artifacts: `results3/_bench_20260919/ours_pcfold3_fix.jsonl` (candidate input),
`…/ours_pcfold3_fix.graded.jsonl` (per-task metrics), `…/_grade.log`.

### Reading these numbers

**`statement_f1` = 0.2876 is a factoring artifact, not a defect signal.** Our
candidates are 155/465/142/169 statements against references of 23/16/71/168.
`grade.py`'s own docstring says statement_f1 is "sensitive to factoring, so
read it alongside disclosure_*, not instead", and nominates `disclosure_*` as
"the headline number ... insensitive to how the policy is factored". The one
place it is informative is conversations_index at 0.0413, a ~29x factoring
difference.

**disclosure_precision < 1.0 is NOT a defect in our extraction.** A separate
investigation traced all 29 extra `(table, column)` pairs:
**`results3/queries_from_runs/_PRECISION_VS_BENCH_20260919.md`**.
Headline: **0 of 29 are a real extraction defect.** Causes are a
`RAILS_ENV`/`lazy_columns` driving-environment difference, the external
reference never driving diaspora's mobile layout (so it is *missing* real
disclosures we correctly capture — and this accounts for 100% of the
table-precision gap), a parser bug in `bench/sqlnorm.py` itself, and one
deliberate design choice in our `transform.py`. Removing these yields
**disclosure_precision = 1.0000 on all four**. See that report for the
per-bucket breakdown; it is not duplicated here.

That also explains the one row that looks weak: conversations_index's
table_precision of 0.733 means we name tables the reference does not — i.e.
over-disclosure relative to an *incomplete* reference, not under-coverage.

---

## 2. Which arm ships, and the stale-canonical warning

`base` = `reliable_only=False` (pruning as historically shipped); `fix` = the
`--reliable-pruning-witnesses` arm, which `_PRUNE_DIAGNOSIS_20260916.md` treats
as the corrected behaviour — the defect was predicates dropped on the strength
of an *errored/truncated* run's silence, which is missing data, not a real
counter-witness. **`_pcfold3_fix.sql` is the intended-to-ship arm.**

Arms diverge on only two of the four: conversations_index 353 -> 465 statements
and notifications_index 135 -> 142; comments_index and people_stream report
equal counts (people_stream's two files are nonetheless not byte-identical).

### CANONICAL `.sql` FILES ARE STALE — NOTHING PROMOTED

The canonical `results3/queries_from_runs/<endpoint>.sql` files predate this
session's alias fix and redrives. **Nothing has promoted `_pcfold3_fix.sql` to
canonical, and this pass deliberately did not do so** — that is a decision for
the user. No canonical file was renamed, overwritten or touched.

people_stream is a partial exception: it was re-extracted 2026-09-18 03:00 over
its re-driven corpus, so its `_pcfold3_*.sql` are the freshest artifacts on the
box; its canonical `people_stream.sql` (Sep 11) is still stale and unpromoted.

---

## 3. Policy loadability

`src/queries_from_runs/audits/policy_loadability_audit.py` — the only audit in
the project that opens the file that SHIPS. Every other audit is dump-side. Per
its docstring, conversations_index once shipped **43 unresolved-bind
occurrences with every dump-side audit green**, which is why this axis is
independent.

| endpoint | written | loadable | % | distinct unresolved binds | verdict |
|---|---:|---:|---:|---:|---|
| people_stream | 169 | 146 | 86.39% | 1 (`_SYM_PERSON_via_user_id`, 23 stmts) | **RED** |
| conversations_index | 465 | 465 | 100.00% | 0 | **pass** |
| comments_index | 155 | 155 | 100.00% | 0 | **pass** |
| notifications_index | 142 | 142 | 100.00% | 0 | **pass** |

All four measured. **people_stream is the sole RED**, and its single bind family
is the only unresolved bind anywhere in the fixed extraction — 1,131 of 1,154
shipped statements load.

conversations_index passing is the notable one: the fixed extraction has
cleared the exact historical failure the audit was written to catch.

Statement counts here are the audit's own (`--` comments stripped, split on
`;`) and are authoritative over a raw semicolon grep, which over-counts.

### 3a. people_stream — the sole RED, and the extraction self-report is wrong

```
written=169  loadable=146  unloadable=23  86.39%
unresolved binds: 1 distinct, 23 statement occurrences

#53: rejected by solver-type probe: IllegalArgumentException:
     unrecognized constant: _SYM_PERSON_via_user_id

_SYM_PERSON_via_user_id  (in 23 statements)
   cause: RESOLVER DEFECT — a SELECT was recorded; it should join
   note : SELECT "people".* FROM "people"
          WHERE "people"."owner_id" = $$(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id)
          LIMIT 1
```

Audited with `batch_dir` = `_redrive_20260918/people_stream/`, the corpus the
`fix.sql` was extracted from, so the CAUSE lookup reads the matching corpus.

**This contradicts `_REDRIVE_AND_REEXTRACT_STATUS.md` §6**, which reports
people_stream at "unresolved `SYM_RESULT_` in SQL: **0**" and states
"people_stream's policy is now fully resolved — every bind has a producing
SELECT", dismissing this token as "a named principal leaf, not an unresolved
result placeholder". Three things undercut that:

1. The self-report counted only the `SYM_RESULT_` family.
   `SYM_PERSON_via_user_id` is a different family — 46 textual occurrences
   across 23 statements — so "0" was literally true and substantively
   misleading.
2. `reports/diaspora/queries_config/app.json` files this very name under
   **`non_principal_identity_name`** (`^SYM_PERSON_via_user(?:_|$)`) — the
   config itself says it is NOT the principal, the opposite of the
   "named principal leaf" justification.
3. The audit's corpus-based classifier calls it a **resolver defect, not a
   boundary defect**: the runtime DID record a producing SELECT, so it should
   have been inlined rather than emitted as a bare token.

**Candidate mechanism, NOT traced end-to-end — verify before acting:** the
config's `identity_id` pattern is `^SYM_PERSON_[A-Za-z0-9]+_id$`; `via_user`
contains an underscore, so `SYM_PERSON_via_user_id` fails that match (verified
directly) while still matching `non_principal_identity_name`. Plausible route
to a bare token; an observation, not a proven root cause.

No config, resolver or `src/` change was made.

---

## 4. Containment — attempted, infeasible at our policy sizes, not pursued

**Status: attempted, infeasible without a minimization pass, not pursued
further. `disclosure_*` accepted as the headline metric instead.** This is a
closed decision, not an open question.

`bench.containment` on the cheapest task (`diaspora/comments-index`) ran
**15 minutes of 100%-CPU Z3 and produced no result** — no per-task line, no
output file. Stopped at cap.

Why, from `compare()`: it checks every candidate statement against the
reference views AND every reference statement against the **candidate** views.
Our candidate is the big side, so the second direction embeds 155 views
(comments) or 465 (conversations) per formula. The module's own
`--max-statements` default of **60** exists to refuse this shape — "the check
is superlinear in statement count". All four policies are 2.4x-7.8x over it
(155, 465, 142, 169 vs references 23, 16, 71, 168). At our factoring the
benchmark's routine per-submission grading check is being asked to do something
outside its intended size.

**Deliberately NOT done: lowering `--timeout` to force completion.** UNKNOWN
statements are *excluded* from the score rather than counted, so precision and
recall would look clean while being computed only over whichever statements
happened to be easy. A misleading number, not a cheap one.

### Two measurement errors of mine, recorded so they are not mistaken for findings

* A first timing probe reported `parse_policy` returning 2 statements and
  `AttributeError` on every check. **That was my bug** — `parse_policy` returns
  `(statements, skipped)` and I passed the tuple as views. Unchecked, it would
  have become a badly wrong "containment errors on every statement" finding.
* The corrected probe also hit its 280 s cap without emitting (output buffered
  through `tail`, killed before EOF). **No per-statement timing was ever
  obtained** — the 15-minute figure is whole-task wall clock, not a rate.

---

## 5. The completion-gate (Z3) line — STOPPED by direction

Halted on the grounds that it proves OUR OWN exploration's completeness, which
was not what was being asked, and at 14+ h/endpoint was the wrong tool.
**No `OVERALL_COMPLETE` verdict was obtained for any endpoint**; the single run
that reached the assumption stage was aborted mid-flight.

Findings produced before it stopped, which stand:

**(a) The premise about the `key` bug's history was wrong.** `run_completion()`
always calls `extract_shims()` then `test_shims()` — no reuse or bypass path —
and `test_shims()` writes `_shims_extracted.json` only after extraction
returns. Those files pre-date today for conversations_index (Sep 1),
comments_index (Sep 13) and notifications_index (Sep 15), and **all three lack
`key`**. Real gate runs therefore DID succeed on all four endpoints before
today. What is new is the `ShimSpec(key=row["key"])` requirement added to
`completion.py` between 2026-09-15 and the 2026-09-17 checkpoint `82dd362`;
`c4e1446` repaired the extractor contract it broke. The fix is confirmed
working — 34 rows emitted, all carrying `key`, no new error.

**(b) Every endpoint's shim tests predate the 2026-09-15 boundary re-sync.**
`concolic_targets.rb` was re-synced 2026-09-15 20:02 across all four, after
every one of their last gate runs; `extract_cmd` reads it.

| endpoint | shim_tests.rb | targets.rb | concolic_targets.rb | staleness |
|---|---|---|---|---|
| people_stream | 09-11 05:45 | 09-15 20:03 | 09-15 20:03 | +4d14h |
| conversations_index | 08-31 20:41 | 08-31 21:18 | 09-15 20:02 | +14d23h |
| comments_index | 09-13 04:37 | 09-01 09:09 | 09-15 20:02 | +2d15h |
| notifications_index | 09-13 23:09 | 09-14 19:43 | 09-15 20:02 | +1d20h |

**(c) people_stream's `User.person` FAIL-COVERAGE is a confirmed stale-test
defect.** Coverage 90.9%, `missed_lines: [610]` — the `nil` body of a
`rescue Exception` arm opening at line 604. Differential against
`targets.rb.bak_pre_b23_20260915`: that file has `rescue Exception` at lines 91
and 261 **only**; the current file has a third at 604. The Sep 15 edit added
the arm and `shim_tests.rb` (Sep 11) was never updated. Not a defect in the
code under test, and unrelated to the `key` fix.

**(d) The gate is far more expensive than when these endpoints were
certified.** people_stream's Sep 11 gate tested 30 assumptions in ~18 min;
today the same endpoint wants `10350 distinct probes ... for 34 assumptions`,
stage 1 of 2. Consistent with the X10 gate-probe fix (flip-both probes that
previously never ran on canonicalizing endpoints) — **the old green verdicts
were cheaper than a correct one would have been.**

Units stopped: `bench-people-stream-20260919.scope`,
`bench-people-stream-20260919b.scope` — mine only, by exact name.
`p44-coveragecheck-real2.scope` matches the "p44-coveragecheck-style" wording
but belongs to **another agent's** posts_show run and was deliberately left
alone.

---

## 6. Operational finding — `timeout` does not bound a systemd scope

`timeout N systemd-run --user --scope ...` does **not** bound the work. Killing
the wrapper leaves the scope running: the containment smoke outlived its own
900 s cap and had to be stopped explicitly.

**Practice going forward:** always stop the compute with
`systemctl --user stop <unit>` **by exact unit name**. Never rely on `timeout`
wrapping alone. Corollary already observed in this project's own scripts: give
every scope a unique `--unit=` so it can be stopped by name, and never use
`pkill -f <pattern>` — runner filenames are shared across agents.

---

## Method notes

* `bench.grade`: `python3 -m bench.grade <candidates>.jsonl`, no judge. Ran in
  seconds; no resource caging needed.
* Loadability: `policy_loadability_audit.py <batch_dir> <policy.sql>
  --sample 2000`, with `QFR_APP_CONFIG=reports/diaspora/queries_config/app.json`,
  each in its own `systemd-run --user --slice=concolic-cov.slice --scope
  -p MemoryMax=<N> --unit=<unique>`.
* task_id mapping **verified, not assumed**: hyphenated
  (`diaspora/comments-index`), references at
  `policy-extraction-bench/data/answers/diaspora/<name>.sql`. Reference
  statement counts match the bench README exactly (23/16/71/168).
* Read-only, never written: `policy-extraction-bench/data/answers/`,
  `results3/posts_show/`, `results3/people_show/` (the latter two owned by other
  agents this session).
* For the abandoned Z3 line, `NO_PINS`/`SUMMARY_OUT`/`SKIP_COMPLETION` were
  **never set** — each silently forces counterfactual mode and a guaranteed
  `complete=False`.

### people_stream corpus caveat

`results3/people_stream/` holds the ORIGINAL 13,677 dumps dated 2026-09-11, not
the fresh redrive. The 2026-09-18 redrive deliberately moved its output to
`results3/_redrive_20260918/people_stream/` and restored the original in place
(`_REDRIVE_AND_REEXTRACT_STATUS.md` §4). The redrive was a **note-refresh
replay** targeting SQL bind resolution; "0 unresolved binds" is a
precision/extraction property, not a completeness one.

Consequence for the table above: people_stream's loadability figure is computed
over the **redrive** corpus (the one its `fix.sql` came from), so that row is
not a statement about a single artifact. Each check was run against the artifact
it is actually about.
