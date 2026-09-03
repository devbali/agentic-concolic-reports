# PAUSED — notifications_index (cycle 6), 2026-08-29 09:52

Paused by coordinator directive (sequential mode; conversations_index goes
first). No unit is running; `ni-final9` was killed by the coordinator at
09:50:36 to free the heavy lock, mid-coverage. Nothing else is queued.
Full narrative: `AGENT_RUN.md` §§16–22. This file is the cold-start summary.

---

## 1. Corpus on disk

* `dump_*.json` — **39 956 dumps** (batch dir). Generated from the CURRENT
  `targets.rb` / `concolic_targets.rb` / `run_dse.rb`, i.e. every cycle-6
  modelling fix is IN the corpus except the pluck-projection repair (see §5).
* `_dup_path_dumps/` — deduplicated siblings. `_archive_c6*_dumps/`,
  `_archive_cycle5_dumps/` — earlier cycles, do not mix.
* `coverage_summary.json` on disk is a **coverage-ONLY pass** (big round,
  25 052 runs, `SKIP_COMPLETION=1`): its `completion.blocking` literally says
  "completion gate did not run". **Do not read it as a result.**
* The last COMPLETE engine report is **2026-08-29 06:34, rc=0**, preserved as
  `_report_0634_final_engine.log`; its numbers are the METRIC TABLE in
  `AGENT_RUN.md`.

## 2. Where the numbers come from

| | value | from |
|---|---|---|
| last FULL report | 20 869 runs, 133 nodes, **319 missing**, 8 430 assumptions (8 418 PASS / **12 FAIL**), shims 13 PASS / 20 PROTOCOL, note check green, all 4 engine audits green, `complete: false` | 06:34 report |
| current coverage-only | 25 052 runs, 136 nodes, **7 681 missing** | big round, 08:28 |
| corpus now | 39 956 dumps (big-round replay added ~15 k) | after `_dedup2.py` |

**Why 319 → 7 681 is not a regression.** The 12 gate FAILs were withdrawn as
classes **W-E** (a list-cardinality decision `(len(X) > 1)` is independent of
NOTHING — since Rule D the cardinality DETERMINES the statement shape, so it is
jointly dependent with every decision that gates a read; 9 of the 12) and
**W-F** (not-found × not-found, and identity × not-found, on the contact
finders; 3 of the 12). Withdrawing them moved independence declarations
withdrawn 255 → 1 323, and the combinations those declarations were exempting
are now DEMANDED. Every one is reachable by seeding. The withdrawals are in
`coverage_assumptions.py` (block `WITHDRAWN`, classes W-A…W-F) and must never
be re-declared in any form.

## 3. Step DONE / step NEXT

DONE, in order: the 28 first-round gate FAILs withdrawn (W-A…W-D) → §7
modelling fixes (SQL-keyed `one_fact`; preloaded associations answered from the
loaded target) → B-4, B-5, B-7, B-8 → M-5 (`set_locale`) modelled → M-6 / Rule G
ledgers → M-7 then **Rule D** (per-row preload keys) → corpus regenerated from
scratch → 06:34 full report → 12 new FAILs withdrawn (W-E/W-F) → demand-loop
root-cause found and fixed → one big demand round (+15 k dumps) → INSTR-1/2/3
rig fixes + all five concrete manifests re-run + judges re-run green.

**NEXT (in this order):**
1. `flock` a heavy slot and run the FULL engine report —
   `bash _final6b.sh` (systemd, `MemoryMax=6800M`). This is the killed step.
   It will report the post-withdrawal missing count and re-run the gate.
2. Converge with `_biground.sh` (coverage at `MISSING_CAP=12000`,
   `_demand_root.py`, replay at `MAX_RUNS=12000`), repeating until BLOCKING
   is 0. `_converge6.sh N MMC` is the multi-round form.
3. Re-run `_audits6.sh` (all ten checks + lint) and the full report; only then
   is `complete: true` meaningful.

**The demand loop is fixed and this is the single most important thing to
carry forward.** `demand_round.py` seeds only the clique variables, so every
other dimension falls back to its default — and the Z3 model assigns EVERY
variable in the clique's declaration set with default **0**, including every
list length. Seeding it therefore set `len(...to_ary_1_rows) = 0` and
FORECLOSED the very decisions being demanded: two full rounds moved BLOCKING
478 → 478. `_demand_root.py` now (a) roots each demanded assignment on a REAL
dump's seeds — the dump recording the most of the combination's expressions,
preferring the OTHER polarity — and (b) overlays ONLY the variables the
combination's constraint mentions. `_mkroots.py` separately replaces the 72
env-level `SEED_SUFFIXES` launches with ONE launch per variant over exact-name
roots expanded from the corpus's own variable table: a JRuby LAUNCH costs
~2.3 min and the exploration ~10 s, so generation is launch-bound (131 → 14).

## 4. Open items

* **12 assumption FAILs** — withdrawn as W-E/W-F in `coverage_assumptions.py`;
  NOT yet through a gate run. Verify the withdrawal count and that the
  combinations get explored, never re-declared.
* **`hardening_lint` CHECKs** (run it with ONE `--runs` followed by all 13 run
  files — 6 concrete + `adversary/runs/A0*.json` — or H6 is skipped):
  * **H3 (1)** — `CollectionProxy#load_target`'s non-SQL note. Proven unable to
    reach a target (`CollectionAssociation#load_target` returns early when
    `loaded?`; on this endpoint the association is always preloaded, so the
    corpus has no SQL-noted `load_target` at all, checked at sample 2 000). H3's
    only escape hatch is the literal word `WALL`, which this is not — answered
    in `AGENT_RUN.md` §19 rather than by mislabelling the note.
  * **H4 (2)** — `…_target_mentions_container[_commentable]_photos_row_rows`
    have one polarity. An exploration gap; the domain is {0,1,4} and both edges
    are recorded decisions.
  * **H6 (3) — genuine over-emission, deliberately NOT declared answered:**
    two `SELECT "photos".* … "status_message_guid" = $$(…) AND (1=0)` shapes
    (Arel's empty-relation guard — the app issues `1=0` only for a `none`d
    scope), and `Core::ClassMethods.find_by … "diaspora_handle" = '…'`, which is
    reachable only through `mentions_container.rb:18`'s `persisted? == false`
    arm while a container loaded from the database is always persisted — the
    same open cross-endpoint class comments_index carries.
  * Declared-and-reasoned H6 families live in `completion_config.json`
    `h6_answered` (scope-constant literal vs bound value; key-set arity; the
    repaired pluck projection).
* **INSTR-1/2/3 — DONE.** INSTR-1 (per-warden principal memo) fixed in all 7
  manifest files; measured impact on this batch nil (one request per process)
  but required for multi-request bodies. INSTR-2 adopted from `src` (no batch
  change needed). **INSTR-3 was the one biting here**: 113 boolean fixture
  values written as `1`/`0`, all converted to `true`/`false`. After re-running
  all five manifests, ground truth grew from 225 to 249 statements
  (auth 76→81, mobile 34→36, links 40→42, photo 36→46, pages 39→44), and BOTH
  judges are green on it: `mock_note_check` all NOTE-OK, `note_fidelity_audit`
  MISSING 0 / every diff class 0 / **EXACT 34** (was 26).
  A concrete scenario was ADDED rather than a declaration written: a blank-text
  StatusMessage with two photos in `concrete_manifest_photo.rb`, which puts the
  `post.photos` scope read (`posts_helper.rb:14-17`) into ground truth.
  NOTE: `adversary/runs/A0*.json` were produced on the OLD rig and were not
  re-run (the adversary is the coordinator's actor).
* **T-t (writes conditional on dirtiness) — N/A here, with evidence**
  (`AGENT_RUN.md` §21): `#index` performs no write; `set_read_state` is
  `#update`/`#read_all` only; a 1 500-dump scan finds 0 write-ish target events
  and 0 `UPDATE|INSERT|DELETE|BEGIN|COMMIT` notes. For whoever models
  `notifications#update`: `set_read_state` uses `update_column`, which BYPASSES
  dirty tracking, so the "unchanged ⇒ no statement" decision does not apply
  there either. T-t's other two classes also checked: no query parameter this
  action reads can widen a finder to `IN (…)`, and there is no undeclared
  renderable format (only `index.html.haml` / `index.mobile.haml`).
* **M-5 three-armed domain — NOT YET APPLIED.** This batch models
  `set_locale` with a boolean `<rep>_stale_language` decision (true ⇒
  `"zz-dropped-locale"`, raises `I18n::InvalidLocale` after exactly one
  statement — matching the coordinator's re-derived multiset). The coordinator's
  refinement that the domain is THREE-armed (`""` raises like `"xx"`; `NULL`
  returns 200) is **not modelled yet** — the boolean covers the raise arm and
  the valid arm but not the NULL arm. Next cycle: make it three-valued.
  Also unchecked here: whether this batch's own runs carry the salt-cache
  pollution (a `find`-shaped `"id" = ? LIMIT ?` with no `ORDER BY`) the
  coordinator described.
* **Round-1 adversary wins — verified still closed** on the cycle-6 corpus
  (`AGENT_RUN.md` §18, 2 500-dump scan): N-1 `SELECT 1 AS one FROM "posts"
  WHERE "posts"."guid" = ? LIMIT 1` (1 600 events / 422 dumps); N-2 photos
  reads (359) and `"posts"."type" IN ('StatusMessage') AND "guid" = ? LIMIT 1`
  (234); N-3 `conversations` 0 occurrences (documented pin). Both over-emission
  families still 0 (`people INNER JOIN notification_actors`,
  `COUNT(*) FROM "photos"`), `params[:per_page]` a recorded pin, and every
  preload carries BOTH cardinalities.

## 5. Two code changes that the corpus does NOT yet reflect

1. **pluck projection** — `targets.rb` no longer appends ORDER columns to the
   pluck SELECT list (the old note `SELECT "tags"."name", "taggings"."id"`
   over-projected against 13 real runs showing `SELECT "tags"."name" … ORDER BY
   taggings.id`). Declared in `h6_answered` with that reason; the shape leaves
   the corpus at the next from-scratch regeneration.
2. **`coverage_report.py`** frees the parsed Runs before the completion section
   (43 519 runs put the unit over `MemoryMax=6G` and the 09:00 report was
   OOM-killed AFTER the coverage phase had succeeded). Use
   `MemoryMax=6800M` and run the report alone.

## 6. Audit standing (coordinator repaired three false-RED audits 2026-08-29)

`identity_symbolicity`, `statement_note_lint`, `pc_visibility` (all 10 gate
columns incl. `language`), `empty_relation_emission`, `noteless_call`,
`note_fidelity`, `format_coverage`, `bind_resolution`, `skipped_pcs`,
`cardinality_consistency` — **all green**. `hardening_lint` carries the 6
CHECKs above. Run `bind_resolution` and `skipped_pcs` with the
`queries_from_runs` venv interpreter (`_audits6.sh` does).
