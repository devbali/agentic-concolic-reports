# FUTURE-WORK #3 PLAN — decouple format from branch (people_show)
# Status: PLAN ONLY — NOT IMPLEMENTED. Harness change ⇒ PERMISSION REQUIRED
# (source discipline: ask before deviating from intended design).
# Prepared 2026-09-04 so execution is immediate upon approval.

## Why

The 48 cross-format missing items demand a single run witnessing BOTH var
families that today never co-occur:

- bare `len(Relation_records_1/2)` — block/contact NullRelation checks
  (presenter `is_blocked?`/`has_contact?`), minted ONLY in non-mobile
  (html/json) runs, value ALWAYS 0 in anon, empty SQL note.
- `len(Relation_*_rows)` / `len(Relation_to_a_1_rows)` — the posts stream,
  minted ONLY in mobile runs, `SELECT "posts"...` note.

Root cause (people_controller.rb #show):
- `format.all` / `format.json` → `@presenter.as_json` + `respond_with
  @presenter` — presenter/block-checks run, stream does NOT render.
- `format.mobile` → `person_stream` (**stream renders here**) then
  `respond_with @presenter` — but the mobile template does not fire the
  block/contact checks (census: ZERO bare records_N in 1749 mobile dumps).

So no single REQUEST renders both. A run can only witness the conjunction if
one execution renders BOTH the html-presenter path AND the mobile stream.

## Options (in increasing invasiveness)

### Option A — dual-format run (preferred; NO app-source change)
Add a FOURTH scenario ("anon_mobile_presenter") whose `run_one` block
executes TWO controller actions in one run: `tc.process(:show, format: nil)`
(html presenter path — mints bare records_N) followed by
`tc.process(:show, format: :mobile)` (stream — mints rows_N), inside the
same `$interceptor.run` block. Both var families land in ONE dump ⇒ the
cross-format conjunction co-records naturally (block/contact still 0:
Block.none in anon).

- Scope: runner-local `run_dse.rb` + a scenario entry only. Touches NO
  shared concolic_targets.rb, NO frozen endpoint files, NO app source.
- Effect on coverage: the 48 cross-format items need
  `records_1==0 ∧ records_2==0 ∧ stream rows>0 ∧ PD ∧ NOTC ∧ ...` — a
  dual-format run with empty blocks + a non-empty stream witnesses exactly
  this (modulo the remaining profile/guid conjuncts, which the existing
  flips already reach in mobile runs). Expectation: MISSING 64 → ~16-20
  (the guard-foreclosed + residual deep conjunctions).
- Risk: two `process` calls in one interceptor run share the same
  SymbolicFunc call-counter space ⇒ result-name collisions for same-named
  methods (records_1 both in presenter and stream). Check `next_call_idx`
  semantics: counter is per-func-name, so the SECOND `records` call gets
  `_2` — names stay distinct. Prefix-replay drift bounded by path-signature
  dedup (established pattern).

### Option B — format-as-seed (runner-local, lighter)
Add a synthetic seed key "render_format" → "mobile" that makes
`run_one` use format: :mobile for the presenter-driven scenarios. Weaker:
doesn't add the second render, just re-targets — does NOT co-mint both
families in one run (mobile template still skips block/contact checks).
Rejected: it cannot clear the join.

### Option C — shared-file harness change (REJECTED)
Extend the frozen shared `concolic_targets.rb` to force-mint bare records
on mobile. Violates the freeze + discipline (runtime must stay generic).
Never.

## Implementation sketch (Option A, ~30 lines, all in run_dse.rb)

```ruby
# scenario: anon_dual => run_one gains:
#   $interceptor.run(-> {
#     tc.process(:show, method: "GET", params: { username: sym_username }, format: nil)     # html presenter
#     tc.process(:show, method: "GET", params: { username: sym_username }, format: :mobile)  # stream
#     :ok
#   }, {}, label: label, script: "run_dse.rb")
# Keep format: nil first (mints records_1/2), mobile second (mints rows) —
# order affects call ordinals only, not satisfiability.
```

## Verification plan
1. Unit-test: none needed (no new pure logic) — but run ONE small smoke
   campaign (MAX_RUNS=300, TIME_BUDGET=120) and confirm a single dump
   contains BOTH `..._records_1` (bare) AND `..._records_1_rows`.
2. Bounded checker (timeout 180 bash _run_coverage.sh): MISSING should drop
   below 64. Report before/after.
3. If MISSING drops: re-classify the residual (expect 16 guard-foreclosed +
   a few deep conjunctions); update AGENT_RUN.md + STRUCTURAL_GAPS.md;
   commit people_show-only (run_dse.rb + docs + summaries).
4. If MISSING does NOT drop: the join may need additional conjuncts
   (PD/NSFW/guid) in the same dual run — extend with seeded flips in the
   dual scenario's seed set; iterate bounded.

## Permission request
"Approve future-work #3 Option A (dual-format scenario in run_dse.rb,
runner-local, no frozen-file/app-source changes)? Runs an html then mobile
render in one interceptor run to co-mint block/contact + stream vars and
witness the 48 cross-format items. Bounded coverage checks only; commit
people_show-only."