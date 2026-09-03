# notifications_index — FINAL REPORT (results3, closed 2026-08-21)

**Result: 71 / 71 reference queries covered, 0 rejected, 0 tried_unknown.**
The extracted policy fully reconstructs the reference policy for this
endpoint. Authoritative verdict ledger:
`../queries_from_runs/diff_gen10c/notifications_index/_progress.json`.

## 1. The two diff directions

**Reference vs ours (does our policy explain everything the reference
allows?)** — 71/71 covered:
- **64 proved at the 15s baseline** against the full 77-view set —
  including the `tags.name, taggings.id` query that had resisted four
  generations: once its view was shape-correct (right projection, right
  chain, right type predicate), it needed no escalation at all.
- **7 proved via table-subset views at 300s**, all CPU-bound in subset
  mode (subset conversion eliminated the memory-hard instances entirely
  this generation — no memory-bound residues remain). The seven are the
  mention/post-target chains; per-query subset sizes: 20, 19, 13, 13,
  12, 11, and 7 of the 77 views (each query's exact subset is the
  table-subset filter's output, recorded in its `reason` field in the
  ledger). Soundness: a subset proof implies the full set covers.

**Ours vs reference (did we extract anything the reference cannot
explain?)** — of our 77 usable views: **17 covered, 6 rejected
(proven-new), 54 tried_unknown** (subset-definitive for nearly all).
The six proven-new read families, each a full-set counterexample proof:
notifications re-read via the actors self-join; people-via-mentions
(target chain); people-via-post-author (target chain); the owner's
profile via users; mentions-by-container; `blocks WHERE user_id =
_MY_UID`. The asymmetry is the finding: the reference is fully
contained in our policy; ours is largely NOT reconstructible from the
reference — our extraction reads strictly more (auth-chain tables,
blocks, broadened target chains). Every provable containment points one
way. Details: `../queries_from_runs/OURS_SUBSET_SWEEP_REPORT.md`.

## 2. Corpus and pipeline

- 5,543 dumps, 15 DSE rounds (main, 7 STI-type rounds, auth-chain, 2
  regenerated saturation rounds, 1 regenerated context round),
  `run errors: {}` in every round.
- Extraction: 83 raw queries → 119 distinct → 36 subsumed → 80 emitted →
  77 usable views (1 placeholder excluded, 6 type-variant blocks
  complement-merged into 3 unscoped views).
- All heavy stages under systemd cgroup caps with per-query blast-radius
  scopes; extraction must run in a FRESH unit (page cache charged to a
  rounds-running unit OOMs the extractor at the same cap).

## 3. How the last 7 points were won (score 64 → 71)

Every one came from a discipline repair, not solver escalation — the
complete 8-violation record, the class analysis (all Class S or Class
B, including the fold-space mirrors), and the checks that would have
caught them in one pass (C1/C2) are in `../DISCIPLINE.md`:

| gen | repair | effect |
|---|---|---|
| gen6 | `emit_includes_preloads` — materialize mocks emit eager-load preload statements | +6 (profiles-via-mentions family) and the 2 mention-row queries at next diff |
| gen7 | pluck note: true projection + ORDER BY columns (ground-truth probe `_probe_tags_sql.rb`) | taggings view projection correct |
| gen8/8b | owner-qualified assoc var names + note-driven fold registration | chain attribution correct (three colliding `assoc_profile` producers separated) |
| gen9 | find_by conditions thread-local capture | the notifications-target → contacts link, severed in every prior corpus, restored |
| gen10/10b | `TypeLinkedString` + StringVal unwrapper for parse_pc | the app's `note.type == "Notifications::StartedSharing"` branch folds; string PCs fold at all (they never had) |
| gen10c | complement elimination at view build | actors-chain over-scoping regressions (2 proven rejections) resolved soundly; **71/71** |

## 4. Where everything lives

- `../DISCIPLINE.md` — the discipline: violations, classes, rules D1-D3,
  checks C1-C3, final score arc.
- `README_TESTS.md` (this directory) — the executable test suite
  (T1/M/A/T-rules) and per-generation history.
- `../queries_from_runs/diff_gen10c/notifications_index/_progress.json` —
  per-query verdicts, budgets, subsets, reasons (both directions).
- `../queries_from_runs/diff_ours/notifications_index.sql` — the final
  77-view extracted policy.
- `../queries_from_runs/OURS_SUBSET_SWEEP_REPORT.md` — ours-direction
  detail (superseding note at top).
- Corpus archives: `_gen5_archive/` … `_gen9_archive/` in this directory;
  live dumps are gen10.

## 5. The final check suite

Moved to its own document: **`../CHECKS.md`** — every check in detail
with an example from this project's history, REFERENCE-FREE framing
(the completion criterion is C1/C2 against the app's own real execution;
a reference policy, when one exists, is only a bonus oracle).

The runnable suite lives in two homes (split 2026-08-25): the
language-agnostic auditors + C1 differ in
**`src/end_to_end_completion_checker/`** (Python, serves both runtimes),
the in-process probes in `src/ruby_runtime/completion_checker/` (see
each README). First run against this batch's final corpus:
- `statement_note_lint` — **green**: 0 WHERE-less finder notes, 0
  star-projected plucks (script-verifies the violation-4/6 repairs
  corpus-wide); 24,731 star-aggregate notes flagged as warn (COUNT/SUM
  notes broader than the real statement — sound, shape-infidelity).
- `placeholder_audit` — **found a live regression**: 3 placeholder views
  vs gen7's 1, all on an unresolved `first_1_person_id` bind in the
  auth-chain roles/conversation_visibilities family (open item 4 below).
- `complement_audit` — 0 remaining mergeable pairs (the gen10c merge is
  complete); single-variant census listed for review (47 views scoped
  `type <> StartedSharing`, 7 scoped `=`, plus the genuinely
  branch-gated taggings/mentions predicates).
- `pc_visibility_audit --gate type,unread,persisted,diaspora_handle` —
  type/unread/persisted VISIBLE; **`diaspora_handle` BLIND (Class B)**:
  the `Mentionable.format` person-lookup compare is still invisible in
  the final corpus (open item 5; did not affect the 71/71 because the
  profile reads come from the preload, not name resolution).
- `bind_chain` — traces the full taggings chain
  (profiles ← contacts(recipient, target) ← notifications ← `_MY_UID`)
  with no ambiguous producers.

## 6. Open items

1. **The concrete checker RAN GREEN (2026-08-25)**: real fixture env
   (`concrete_env.rb`, sqlite via bundled JDBC + schema + raw-insert
   fixtures), genuine end-to-end run of the endpoint (real Devise, real
   dispatch, real templates, real DB; status 200; 81 target-function
   invocations), every depth-0 target present in the gen10 corpus;
   nested-only calls structurally subsumed. Remaining: the coverage side
   (corpus-side coverage runner flag) and richer fixture scenarios per
   branch family.
2. **Upstreaming** the variant_d fold patches (StringVal unwrapper,
   note-driven producer registration, assoc_fold itself) into
   `src/queries_from_runs/` — awaiting sign-off.
3. **Rolling the toolkit to the other five endpoints** — all repairs are
   batch-local and portable (checklist in memory + DISCIPLINE.md §6);
   run the completion_checker auditors on each batch as the gate.
4. **Placeholder regression (checker-found):** 3 views on an unresolved
   `first_1_person_id` bind (auth-chain roles/conversation_visibilities
   family) vs gen7's 1 — introduced somewhere in gen8-10, likely by the
   owner-qualified renames; ours-side surface only, did not affect the
   71/71.
5. **`diaspora_handle` blind compare (checker-found):** the
   `Mentionable.format` person-lookup (`p.diaspora_handle == handle`)
   still records no PC — the compare runs against our list mock's
   internals. A T1c-style repair (PC-recording compare on the rep's
   handle) would make name-resolution branching explorable; no coverage
   impact on this endpoint.
