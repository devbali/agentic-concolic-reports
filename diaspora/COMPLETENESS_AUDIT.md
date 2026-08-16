# Cross-batch completeness audit — why `complete=true` is not the evidence

Generated 2026-08-15 over all 13 batches, after the per-batch `targets.rb` round.
Solver-independent: rebuilt from the dumps, not from the engine's verdict.

## Headline

| metric | value |
|---|---|
| entrypoints with dumps | 114 |
| path conditions recorded | 761,663 |
| branch expressions with **both sides observed** | **322 / 348** |
| entrypoints reporting `complete=true` **while one-sided expressions remain** | **17** |

## What the 17 do and do not mean

**They are not 17 bugs.** Some one-sided expressions are legitimately
unreachable and Z3 is right to prune them — e.g. `people_stream`'s
`(guid != '')` sits under a `(guid == '')` prefix, so the other side is UNSAT by
construction.

**The problem is that the engine's output cannot distinguish the two cases.**
`missing=0` is returned identically whether the other side was

- *proved unreachable* (correct, desirable), or
- *never checked* because the solver could not parse the constraint.

The second case demonstrably happens: `len(...)` expressions fail to parse
(`name 'len' is not defined`), `coverage.py` does `if not result.satisfiable:
continue`, the query is dropped — and **`solver_lost` still reads 0**. Found
independently by three batches (`people`, `streams`, `notifications_tags`).

`streams` measured the consequence directly: with only the shared targets, 7 of
its 8 entrypoints reported `complete=true, missing=0` while being visibly
one-sided (1 of 9 expressions had both sides). After its overlay: 11 of 11.

## Recommended completeness criterion

Do not rely on `coverage_complete`. Use the conjunction:

1. **DSE worklist drained** (`worklist_exhausted: true`, no `MAX_RUNS` /
   `TIME_BUDGET` stop) — the search reached a fixpoint, and
2. **`unflippable_pcs` empty** — every recorded condition could actually be
   inverted, and
3. **both sides observed** for every branch expression — or an explicit,
   justified note for each one-sided expression saying why it is UNSAT.

`complete=true` is then corroboration, not evidence.

## Entrypoints reporting complete with one-sided expressions

| entrypoint | both / total |
|---|---|
| `streams/streams_activity` | 1 / 2 |
| `streams/streams_commented` | 1 / 2 |
| `streams/streams_followed_tags` | 1 / 2 |
| `streams/streams_liked` | 1 / 2 |
| `streams/streams_mentioned` | 1 / 2 |
| `streams/streams_public` | 1 / 2 |
| `streams/streams_aspects` | 2 / 3 |
| `streams/streams_multi` | 2 / 4 |
| `people/people_hovercard` | 2 / 3 |
| `people/people_show` | 4 / 6 |
| `people/people_stream` | 3 / 4 (the UNSAT case above) |
| `people/people_index` | 10 / 11 |
| `notifications_tags/tags_show` | 2 / 3 |
| `oidc_federation_nodeinfo/webfinger` | 2 / 3 |
| `posts/status_messages_create` | 3 / 4 |
| `users_sessions/users_getting_started` | 4 / 5 |
| `users_sessions/users_public` | 2 / 3 |

**Correction (2026-08-15):** the note originally published here said `streams`'
remaining one-sided expressions were the SQLite `UNION ALL` environment wall.
That is wrong — a dump that crashes before any branch records **no** PC and
therefore cannot make an expression one-sided. The real cause was checked
site-by-site: **all 9 of `streams`' one-sided sites are the same one**,
`active_record/sanitization.rb:205`, always `taken: true` only.

That is `Sanitization#quote_bound_value` calling `empty?` on the bind value
while rendering `where("posts.author_id NOT IN (?)", people)` — ActiveRecord
re-recording the *same expression* the app already branched on at
`post.rb:93`. It can only ever execute on the true side, because the
`NOT IN (?)` clause is only built when `people.any?` was true. **UNSAT by
construction**, and the justified note this audit asks for. `streams`' own
`REPORT.md` describes the duplicate; it was simply never connected to this
table.

This is also why `streams/REPORT.md` says **11/11** where this table says
**10/19**: that report keys by branch *expression* (collapsing the duplicate),
this audit keys by source *site*. Both are right about what they measure. The
site-keyed count is the stricter one and is what `batch_stats.py` reports.

## Method

For every `<batch>/<entrypoint>/dump_*.json`, each path condition is keyed by
`(expr, file, lineno)` — the source SITE, not the expression string, since the
same expression can legitimately come from different call sites (proved by
`services_admin`, where one expression recurs from three distinct sites). An
expression counts as covered only when both `taken: true` and `taken: false`
were observed somewhere in that entrypoint's runs.

Reproduce: the audit is a pure read over the dumps; no runtime or dump state is
modified, and **no deduplication is performed anywhere** — the ordered PC
sequence is load-bearing for the execution tree.

The metric is now packaged as a reusable tool:

```
cd /home/dev/project && PYTHONPATH=src python3 reports/diaspora/batch_stats.py --all
```

It reproduces this audit exactly. (It reports 761,470 PCs and 308/334
expressions because it walks `results/<batch>/<entrypoint>/` only; the remaining
193 PCs and 14 expressions — all two-sided — are `posts/anonymous_scenario/`,
which this audit's `*/*/*` glob also picked up.)

---

## Addendum, 2026-08-15 — the two entrypoints this table did not cover

The headline row counts entrypoints *reporting* `complete=true`. Two did not.
**Both have since been worked, and every entrypoint in the experiment now has a
`coverage_summary.json`.**

### `users_sessions/registrations_create` — CLOSED

Was: `coverage_complete: false`, 5 blocking missing branches, capped at **one**
execution because its second DSE path SIGSEGVs the JVM from native FFI code,
which `rescue Exception` cannot catch — so the in-process worklist died with it.

Now: **5 dumps, 14 PCs, 4 nodes, 0 missing, `complete=true`, 4/4 two-sided,
worklist drained in 63 executions.**

Two steps, and the first is the reusable one:

1. **Crash-isolated DSE.** `run_registrations_isolated.rb` keeps the worklist in
   `state.json`, fsynced after **every** execution, and names the in-flight seed
   in `current_seed.json` before running it. `drive_registrations.py` restarts
   after each abort and marks exactly that one seed poisoned. The search
   continues past a crash instead of stopping at it — and the crash then names
   its own cause: **all four poisoned seeds shared `find_by_1_not_found = true`.**
2. That is `Person.by_account_identifier`, whose caller's not-found arm
   (`person.rb:325`) does a **real webfinger over libcurl** —
   `Discovery#fetch_and_save`. The identical native crash
   `search_links_reports_profiles` had already closed on `links#resolve`.
   Porting their §2 mock drains it in one process with zero crashes.

The earlier diagnosis in that batch's `targets.rb` §14 — "a real query reaching
the FFI sqlite driver" — was **wrong**, and the two crypto leaves it mocked and
measured were the wrong leaves. Guessing at the leaf was the mistake; isolating
the crash and letting it name its seed was what settled it.

### `posts/reshares_create` — CHECKED, by pruning

Was: no `coverage_summary.json` at all — 26,102 dumps / 398 MB, and the checker
holds every parsed `Run` plus the full tree in memory (>1.6 GB RSS).

Now **`coverage_complete: true` over 55 dumps in 25 s.** 26,102 was never the
right thing to check: `ResharesController#create` has exactly **one** decision
(`rescue` vs `else`), and everything after it is
`PostPresenter#with_interactions`, whose sibling hash-literal field-builders
strict-per-node demands as a Cartesian product. Classifying each branch
expression by whether it is ever evaluated before the presenter, declaring the
18 presenter-only ones `UntrackedPathAssumption(expr=...)`, then closing the run
set by fixpoint (49 → 54 → 55 runs, blocking 5 → 1 → 0) gives 912 nodes, 288
findings, all untracked.

The five round-1 blockers were **not** unexplored — each was realised by 132 to
2,931 dumps; the tracked-subsequence key had simply dropped their
representatives, because the checker is prefix-sensitive and those prefixes run
through untracked presenter decisions. Every run added to close them is a real
explored path from the corpus; no assumption was added to absorb them.

Read that `complete=true` **with its assumption set** (serialised into
`coverage_summary.json`, each entry naming its expression), never on its own: it
is completeness over the action's *tracked* decisions. The *unpruned* search
still fails criterion 1 (`worklist_exhausted: false`, `MAX_RUNS` cap plus
336,652 dropped frontier entries). Solver-independently the corpus is 24/24
two-sided, 26,102/26,102 dumps clean.

**A previously reported `complete=true` for this entrypoint was withdrawn and is
now re-earned on a sound basis.** The withdrawn version rewrote each PC's
`PathSource` to a synthetic action/presenter zone, untracking the presenter
*occurrences* of `find_by_1_not_found` — a decision that is also evaluated in
the action zone, and whose per-run call ordinal makes "the presenter occurrence"
unstable across runs. That excused a tracked decision instead of covering it.

### Two engine defects this exposed

1. **The strict-per-node continuation pass ignored every assumption — FIXED
   2026-08-16** (authorised change to `src/concolic_engine/coverage.py`).
   `coverage.py:532-582` appended `MissingCoverage` without consulting
   `_is_untracked` / `_is_side_untracked` and without setting `untracked=`, so
   its findings blocked `complete` whatever the assumption set said. Measured on
   `reshares_create` before the fix: **126/126 per-node findings honoured the
   assumptions; 30/30 continuation findings blocked, and all 30 were expressions
   explicitly declared untracked.** The assumption system therefore could not
   deliver `complete=true` on any entrypoint producing continuation findings —
   which is why `LOOP_ASSUMPTION_PROPOSAL.md` could truthfully say all 13
   batches reached their completeness "under strict per-node with **zero**
   assumptions": the assumption path had never been exercised.

   The pass now consults the continuation node's own source and reports exactly
   as the per-node pass does. Regression test
   `src/test_assumptions.py::test_continuation_pass_honours_untracked`, verified
   to fail before and pass after. The change is inert when no assumptions are
   declared, and that was checked rather than assumed: **all 113
   zero-assumption entrypoints re-check identically to their stored summaries**,
   and all 94 engine tests pass.
2. ~~**Assumptions cannot address decisions that share a source line.**~~
   **FIXED 2026-08-16** — assumptions can now be keyed by branch **expression**
   (`UntrackedPathAssumption(expr=...)`, `IndependenceAssumption(expr_a=...,
   expr_b=...)`), which is what names a decision when the source is a shared
   mock boundary.

   The earlier diagnosis here — "`caller_frame` returns the mock, not the app
   call site; add `concolic_targets.rb` to `SKIP_FILES`" — **was wrong and is
   withdrawn.** Recording a path condition inside a mock is *intended design*,
   not misattribution: a target standing in for an external boundary decides
   found/not-found with an explicit symbolic compare and returns a concrete
   value, because the app's own `rescue RecordNotFound` / bare `if row` is not
   interceptable. `caller_frame` reporting the mock is therefore correct — that
   is genuinely where the PC is created. Measured: **63.7% of this experiment's
   path conditions are recorded in mocks, 34.7% in framework internals, 1.7% at
   a line of app source**, and 129 of 146 distinct branch expressions (88%) sit
   at a source shared with at least one other expression.

   `SKIP_FILES` would also have made it *worse*, measured: walking up to the app
   frame maps `find_by_1/3/5/7` all to `post.rb:143 like_for` and
   `find_by_2/4/6/8` to `post.rb:138 reshare_for` — 4 distinct decisions per
   key, twice. Expression keys give one key per decision instead. See
   "Identifying a path condition" in `src/concolic_engine/assumptions.py` and
   the boundary-decided section of `src/TODO.txt`.
`reshares_create` also adds a fourth item to the recommended criterion in
practice: **an entrypoint large enough that the checker cannot be run on it at
all.** The fix is streaming/incremental tree construction, or pruning of the
kind `prune_reshares.py` does.

One further item from the audit round is closed:
`search_links_reports_profiles/search_search` was missing its
`coverage_summary.json` for the same reason (agent killed mid-check). That check
has now been run with the batch's own `coverage_report.py` — no dumps re-run —
and it reports `complete=true`, genuine, 2/2 two-sided.
