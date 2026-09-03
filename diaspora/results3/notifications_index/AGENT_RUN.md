# notifications_index — AGENT_RUN (results3 completion drive, 2026-08-27)

Objective: drive `coverage_summary.json` to `complete: true`
(`complete = coverage_complete AND completion.complete`, engine-judged,
reference-free). This directory held a PRE-completion-engine port (old
coverage_summary.json had no `completion` section, coverage_complete=false);
the 8-violation repair chain (preload emission, pluck projection, owner-
qualified assoc names, find_by thread-local, TypeLinkedString STI pins) is
KEPT in concolic_targets.rb + targets.rb §5f/§5g. Everything else was ported
from the conversations_index template.

Endpoint: `NotificationsController#index` — signed-in ONLY
(`before_action :authenticate_user!`, no `except:`). No anonymous scenario by
construction. Principal is the Devise session user, resolved through the REAL
`User.serialize_from_session` with a SYMBOLIC session key (`SYM_USER_NI_id`).

Renderable formats (format_coverage_audit): html, json, mobile, xml —
notifications_controller.rb#index has explicit `format.html/xml/json`;
`index.mobile.haml`/`_notification.mobile.haml` are reached via mobile-fu +
ApplicationController#mobile_switch. All four are corpus VARIANTS
(html/json/mobile × plain/typed, plus xml_plain).

## Cycle 0 — port (2026-08-27)

Ported from conversations_index (kept the notifications 8-violation chain):
- `run_dse.rb` rebuilt: REAL Devise resolution (NotifDeviseUserNaming in
  targets.rb: devise_user_first alias, salt leaf shim, OrmAdapterGetNaming;
  unread_notifications manual-scoped); VARIANTS html/json/mobile/xml; replay
  knobs SEEDS_ONLY/EXTRA_SEEDS_JSON/LABEL_SUFFIX; FIFO prefix-directed DSE
  with var-vs-var flip; seeds+scenario(incl format) into every dump; `require
  "builder"` (env provisioning so `@notifications.to_xml` renders).
- `coverage_report.py` ported (attach_to_summary, share_run_objects,
  apply_len_bounds — EXTENDED to bound SYM_NOTE_TYPE_PROFILE 0..7 and
  SYM_POST_STI 0..1 so the checker never demands an out-of-range dispatch
  value).
- `completion_config.json` (all mandatory keys; extra_audit_cmds =
  format_coverage + note_fidelity).
- `coverage_assumptions.py` rebuilt as STRUCTURAL claims only (the gen3 file's
  empirical-count Tier 1 predated the mandatory gate): Tier 0a variant
  exclusivity, Tier 0b type/post-STI-value exclusivity (disjoint dispatch
  value-sets), Tier 2 disjoint-rep, guid one-side-untracked.
- `format_coverage_audit.py` (requires html/json/mobile/xml), `shim_tests.rb`
  (1 real test Person.name_from_attrs + asset-shim zero-target probe + rep-
  plumbing waivers), `concrete_manifest_{auth,mobile}.rb`,
  `concrete_aliases.json`, `assumption_manifest.json`,
  `merge_concrete_runs.py`, `pair_coeval_audit.py`, `demand_round.py`.

Smoke: all 7 variants render clean (0 run errors). Devise resolution mints
`SELECT users.* WHERE id = $$(SYM_USER_NI_id)` + has_one person
`SELECT people.* WHERE owner_id = $$(devise_user_first_1_id)`; recipient_id
binds to the symbolic principal.

## Cycle 1 — note fidelity repairs (from the first concrete run, before regen)

Concrete runs (auth html/json/xml + mobile, real Devise warden, real
dispatch, no mocks): status 200 on all; note_fidelity found 3 classes:
- R1 AGG-COLLAPSE: the `Calculations#count` note rendered `SELECT
  notifications.*` not `SELECT COUNT(*)`. Fix: COUNT(*) projection rewrite on
  the count target note (targets.rb §5b-iii). Class S (mis-shape). Check:
  note_fidelity AGG-COLLAPSE.
- R2 blocks PRED-DIFF/NOTE-MISMATCH: `block_for -> blocks.find_by(person_id:)`
  (StartedSharing gon_load_contact -> is_blocked?) emitted the person_id
  predicate as a SYMBOLIC-VAR note (IterableSymbolicList#find_by), invisible
  to the note check. Fix: User#blocks returns a REAL scoped
  `Block.where(user_id:)` Relation so find_by routes through the declared
  finder target, emitting `WHERE user_id=$$ AND person_id=$$`. Class S.
- R3 mentions PRED-DIFF: the polymorphic `:target` includes-preload fires
  `SELECT mentions.* WHERE id=?` under the `records` frame concretely, but the
  corpus carries it as a `find_target` note (lazy). Fix: concrete_aliases maps
  `Relation.records` -> `SingularAssociation/BelongsToPolymorphicAssociation
  .find_target` (identical shape). Class S (frame attribution).

These change target notes + the blocks PC family, so the corpus is
regenerated with them in place.

(metric table appended at the end each cycle)

## Cycle 2 — coverage_assumptions rebuild + convergence (2026-08-27)

This endpoint had NEVER reached engine `coverage_complete` (the historical
71/71 was the reference diff; the pre-completion coverage_summary showed
coverage_complete=false, truncated). Building it fresh.

Balanced base corpus: 280 runs/variant × 7 = 1610 dumps (the blind FIFO
over-explored one variant; a per-variant cap balances it). `run errors: {}`
throughout.

Coverage convergence (each SOUND structural assumption tier collapses a
clique the checker would otherwise demand unobservable combos over; coverage
wall time dropped from 377s to ~44s once the type clique collapsed):
- baseline (tier0a variant + tier0b type-set + tier2 disjoint-rep + guid):
  136 blocking missing, all `TYPE==k AND <type-gated read>` combos.
- + TIER 0c dispatch-independence (every non-dispatch decision ⊥ each
  SYM_NOTE_TYPE_PROFILE / SYM_POST_STI compare — the STI seed is a separate
  input; flipping it only adds/removes a whole type-branch's reads, never a
  new shape in combination, so the flip-both probe licenses it): 136 -> 73.
- + TIER 1 same-rep foreclosure (`<rep>_not_found==True` forecloses the
  rep's `<rep>_*` attributes; `<rep>_text_nil==True` forecloses
  `_text_has_mention`/`_mention_inline_name`): 73 -> 64.

Remaining 64 are GENUINE within-rep decision combos (count values 0/1/<4,
own-profile `row_id == principal_person_id` compares, profile first/last-name
blank combos, text_has_mention × persisted) — coverable by EXPLORATION, not
assumptions. Driving them with demand rounds (demand_round.py turns each
missing combo's Z3 model into an EXTRA_SEEDS_JSON root per variant).

## Cycle 2 note-gate verification (2026-08-27)

After the three cycle-1 repairs, on the repaired base corpus (1610) + the
merged concrete run (auth html/json/xml + mobile):
- `mock_note_check`: GREEN — every SQL-issuing target's notes match its real
  statements (13 targets, 0 NOTE-MISSING/MISMATCH).
- `note_fidelity_audit` (`tools/`): GREEN — 24 EXACT, 0 MISSING / STAR-OVER /
  AGG-COLLAPSE / PROJ-DIFF / PRED-DIFF.
- `format_coverage_audit`: GREEN — html/json/mobile/xml all corpus scenarios.
- shim tests: 1 PASS @100% (Person.name_from_attrs) + 32 reasoned WAIVER,
  0 NO-TEST.

Remaining for `complete: true`: coverage_complete (demand rounds) and the
mandatory assumption gate.

## Cycle 2 coverage convergence — the full tier set (2026-08-27)

Per-STI-type exploration (seed each SYM_NOTE_TYPE_PROFILE 0..7, flip the rep
decisions under it) drove the type-gated cliques; the residual was resolved
by classifying each remaining decision as access-relevant (cover by
exploration) vs display-only (UntrackedPath — flip leaves the target trace
identical, engine-verifiable):

- UNTRACK own-profile compares (`<rep>_id == principal_person_id`,
  person_link_class CSS class only): 64 -> 52.
- UNTRACK display decision families (`_guid`, name blanks via the
  name_from_attrs SHIM, `_public_details`, `_birthday_year`, badge/actor/
  pluralization `_count` compares): 52 -> 41 (blocking 29).
- UNTRACK `_text_has_mention`/`_mention_inline_name` (only select the seeded
  text string; the title renderer X6l and people_from_string X6f are mocked,
  so no query reads the mention content) and `_sharing`/`_receiving`
  (PersonPresenter relationship label): -> 28 (blocking 12).
- INDEPENDENCE TYPE ⊥ POST_STI (two separate STI seeds; the Post-STI photos
  query has one shape under any type reaching a Post) and `_persisted` ⊥
  `_text_nil` on the same rep (disjoint query families: persisted gates the
  mentioned_people mentions query, text_nil gates the photos query): -> 19
  (blocking 3).
- Remaining 3 single-value misses (records_2 text_nil=True; find_by_2 /
  records_3 persisted=False) driven by a moderate demand round.

KEPT access-relevant and covered by exploration: `_persisted`, `_not_found`,
`_text_nil`, list `len(...)` cardinality. Every UntrackedPath / Independence
above is a checkable claim (the engine's flip probe verifies it in the gate);
none is a waiver.

## Cycle 2 — COVERAGE_COMPLETE reached (2026-08-27)

`coverage_complete: True`, BLOCKING 0, truncated False, 92 nodes, ~11.8k dumps,
672k PCs — the FIRST time this endpoint reaches engine coverage completeness.
The last two misses (`records_3`/`find_by_2` persisted=False — the
intentionally-modeled unpersisted side, whose 1=0-scoped association SQL is
access-relevant so it must be observed, not untracked) were closed by an
all-persisted-False seed under the StartedSharing (type 6) context.
The 15 residual `missing` entries are all UNTRACKED (display-only branches).

Now running the full engine (coverage + shim tests + note check + the
MANDATORY assumption gate + format_coverage/note_fidelity audits).

## Cycle 2 — full engine run (2026-08-27)

First full-engine pass (`coverage_report.py` -> `attach_to_summary`) on the
11,770-dump corpus:
- coverage_complete: **True** (BLOCKING 0, truncated False, 92 nodes, 672k PCs).
- completion.shims: **1 PASS @100% + 32 WAIVED, 0 NO-TEST** (green).
- completion.note_check: **green**.
- extra audits: format_coverage **green**, note_fidelity **green**.
- completion.assumptions: driver killed (driver_exit -15) — SELF-INFLICTED:
  a `pkill -f "assumption_checker.py .../notifications_index"` meant for a
  redundant sample-smoke ALSO matched the engine's own gate (same argv).
  Re-running the full engine untouched.

Operational note: the JRuby slot flock is a machine-global bottleneck shared
with the comments_index / conversations_index agents' gates; the assumption
gate on this 11.8k-dump / 4,134-declared corpus is slow under that
contention. 4,134 declared = 246 variant + 496 type-set + 840 dispatch-indep
+ 16 cross-dispatch + 4 persisted||text_nil + 30 foreclosure + 2,469
disjoint-rep + 53 own-profile-untrack + 48 display-untrack + guid one-sides.

## Cycle 2 — final engine + assumption gate (2026-08-27, cont.)

coverage_complete restored to **True** (BLOCKING 0) after confirming the
disjoint-rep tier must declare EVERY cross-rep pair: the coverage checker's
dependence graph is the COMPLETE graph minus declared independences, so a
never-co-evaluated pair still needs its declaration to leave the clique
(restricting to co-evaluated pairs reintroduced 260 blocking). 4,134 declared
is inherent to this subtractive model (conversations_index carries a
comparably sized disjoint-rep tier); a never-co-evaluated pair is a FREE PASS
in the gate (mutually exclusive, no probe), so the count does not drive the
gate's replay cost.

Final engine (`coverage_report.py` -> attach_to_summary, MemoryMax 5.8G, 6h
gate timeout) launched as the authoritative run. In parallel a 65-assumption
representative sample (>=4 from each of the 9 tiers) is run through the gate
for early soundness validation.

Operational reality: the JRuby slot flock is a machine-global mutex shared
with the comments_index / conversations_index agents' gates; the mandatory
assumption gate on an 11.8k-dump / 4,134-declared corpus is slow under that
contention (coordinator estimate ~2-3h; timeout raised to 6h).

## Cycle 2 — assumption gate: sample validation PASSES (2026-08-27)

Deadlock found + fixed: the batch's own `_gate_sample.sh` wrapper wrapped the
checker in an OUTER `flock /tmp/concolic-slot.lock`, but the checker already
flocks EACH replay internally via `assumption_manifest.json`'s `slot_lock` —
nested flock on the same lock deadlocked the replay child against its parent.
The engine's `completion_config.json` `assumption_cmd` correctly has NO outer
flock (checker self-serializes), so the full-engine gate was never affected;
only the hand-written sample wrapper was. Removed the outer flock.

65-assumption representative sample (>=4 from each of the 9 tiers), 71 distinct
probes replayed: **PASS 65 / FAIL 0 / NOT-TESTABLE 0**. Every tier's derived
flip-probe test passed — the UntrackedPath declarations diff empty
("access trace identical on both sides"), the Independence declarations add no
target-call shape. Strong evidence the full 4,134-declaration gate is sound.

Launching the authoritative full engine (no outer flock; checker self-flocks
each replay) to run the complete gate -> `complete: true`.

## METRIC TABLE (2026-08-27) — coverage complete; gate running/sample-validated

| axis | value |
|------|-------|
| coverage_complete | **True** (BLOCKING 0; truncated False; 92 nodes; 11,770 runs; 672k PCs) |
| missing_branches | 15 — ALL `untracked: True` (assumption-exempt display-only guid/text branches); blocking 0 |
| variants | 7 — html/json/mobile × plain/typed + xml_plain (all 4 renderable formats: format_coverage GREEN) |
| shims | 1 PASS @100% (Person.name_from_attrs) + 32 reasoned WAIVER; 0 NO-TEST |
| note_check | GREEN (13 targets, every real statement matched) |
| note_fidelity | GREEN (24 EXACT; 0 MISSING/STAR-OVER/AGG-COLLAPSE/PROJ-DIFF/PRED-DIFF) |
| assumptions (declared) | 4,134 (246 variant + 496 type-set + 840 dispatch-indep + 16 cross-dispatch + 4 persisted‖text_nil + 30 foreclosure + 2,469 disjoint-rep + 53 own-profile-untrack + 48 display-untrack + guid one-sides) |
| assumptions (sample gate) | **65/65 PASS, 0 FAIL, 0 NOT-TESTABLE** (>=4 per tier, 71 probes) |
| assumptions (full gate) | running (authoritative full engine, 6h timeout) — expected PASS from the sample |
| complete | pending the full gate (coverage_complete AND completion.complete) — every non-gate input is GREEN and the gate sample passed cleanly |

Genuine engine/operational limitations encountered:
1. The JRuby slot flock is a machine-GLOBAL mutex shared with the
   comments_index / conversations_index agents' gates; the mandatory
   assumption gate on an 11.8k-dump / 4,134-declared corpus is slow under that
   contention. The checker self-flocks each replay (`assumption_manifest.json`
   `slot_lock`); wrapping the checker in an OUTER flock deadlocks (fixed).
2. The engine's assumption-gate subprocess timeout was 2h (too short at this
   scale); the coordinator raised it to 6h.
3. Demand-seed replays cannot reach ordinal-specific type-gated combos once
   the type is declared independent (tier0c); per-STI-type exploration and an
   all-persisted-False type-6 seed were needed to observe the last combos.

## Cycle 2 — gate scalability fix: no-singles SEEDS_ONLY replay (2026-08-27)

Root-caused the gate's dominant cost: the assumption checker replays a batch
of probe roots in ONE runner launch, then RE-RUNS singly (a fresh JRuby boot
each) every root the runner deduped away — and run_dse.rb's PATH-dedup was
active even in SEEDS_ONLY replay mode, so most roots collided to one dump and
were re-run singly (batch 4 alone reached 18+ singles). Fix (batch-local
runner): PATH-dedup is DISABLED in SEEDS_ONLY mode, so every replayed root
writes its own seed-tagged dump and the checker matches all of them from the
single batch launch — zero singles. The checker deletes these transient probe
dumps after matching (no --keep), so the corpus is not polluted; the
state_key dedup still skips genuinely identical seed dicts. Verified. This
collapses each gate batch from up to ~40 JRuby boots to 1.

## Cycle 3 — the polymorphic notification-target chain (2026-08-27)

The first full gate (4134) passed 4131/4134; the 3 FAILs were target-chain
guid UntrackedPath declarations. Withdrawing them (HARD RULE 5) re-exposed
the deep interactions of the polymorphic notification-target render
(Post/Mention/Comment nested, each with guid/persisted/text_nil). Modeled
them from ground truth + the gate's own failure evidence:
- `persisted × text_nil` on the singular TARGET rep are DEPENDENT — flip-both
  fires the PHOTOS query (`SELECT photos.* / COUNT(*) FROM photos WHERE
  status_message_id = ?`: the post's photos association loads only when
  persisted, and the photos branch runs only when the message is blank). So
  `persisted ⊥ text_nil` was WITHDRAWN and the four combos OBSERVED (an
  all-persisted-True / all-text_nil-True seed fires photos).
- the target-chain guids are access-relevant (untrack rejected) but the guid
  compare runs ONLY on the unpersisted + blank-message path — verified:
  forcing persisted True drops the guid PC, and the guid PC is 100%
  co-recorded with text_nil==True. So `guid ⊥ persisted` and `guid ⊥ text_nil`
  are sound FORECLOSURES (declared; gate-verified) — they remove the
  unobservable guid combos.
- a CollectionProxy row rep's `_persisted` (a singular find_target? decision
  that never fires on collection rows) is never co-recorded with that row's
  `_text_nil`; a same-rep never-co-evaluated tier declares those independent
  (free PASS), unlike the singular target rep.
- the deepest container guid `== ''` (blank) side was observed by replaying a
  real snapshot with only that var forced blank (the checker's own flip
  mechanism, reproduced).

Result: coverage_complete True, BLOCKING 0, truncated False, DECLARED 4327;
sample gate across every tier (incl. all 6 guid-foreclosures + 8 never-
co-eval): 48/48 PASS. Launching the authoritative full gate.

## Cycle 3 — final gate (2026-08-27)

Second full gate (4327): 4326/4327 PASS, 1 FAIL — `len(records_2_rows) != 0`
(the post's PHOTOS collection, nested under the target's photos branch) ⊥
`target_guid == ''`. They interact (flip-both fires the photos COUNT: photos
length and target guid both live only on the text_nil==True/blank-message
path). Fix (HARD RULE 5): a narrow nested-pair exclusion keeps JUST the
photos-length × target-guid class DEPENDENT (its combo is observed;
BLOCKING stays 0); every other records×target pair is genuinely disjoint and
keeps its independence. coverage_complete True, BLOCKING 0, DECLARED 4327.
Running the final authoritative gate.

## Cycle 4 — final gate re-FAIL: `_nested_pair` predicate bug (2026-08-27)
The authoritative full engine (notif-final, 4327 declared) returned 4326 PASS / 1 FAIL:
`len(CollectionProxy_records_2_rows) != 0 ⊥ Relation_to_ary_1_row_target_guid == ''`
(flip-both fires the photos COUNT) — the exact pair `_nested_pair` was written to
withdraw. Root cause: `_istargetguid` tested `expr.rstrip("')").endswith("_guid")`
on the whole expression `(... _target_guid == '')`, which never ends in `_guid`, so
the exclusion never fired. Fixed to match on `_leftvar(expr)`. The fix also keeps
dependent the two sibling pairs photos-len × `_target_mentions_container[_commentable]_guid`
(same nesting mechanism; withdrawing an independence is never unsound). Nothing
re-declared. Re-running coverage-only (notif-cov1) to see whether the checker now
demands new combos, then the full engine.
Withdrawing the two sibling pairs made the checker demand 4 new combos
(`len(records_2_rows)==0` × `target_mentions_container[_commentable]_guid` ∈ {'', non-empty}).
`_demand_snapshot.py` could not reach them: the Z3 model's free `SYM_NOTE_TYPE_PROFILE=0`
overwrote the snapshot's type 4/5, and the mention chain is only evaluated for
MentionedInPost/MentionedInComment. Built `_seed_m0_<variant>.json` by hand from
type-4/5 reference dumps (records_2 length forced to 0, guid ''/'A'), `_m0_run.sh`
replayed 20 runs (5 variants × 4) — all four combos now observed in every variant.
Coverage-only after the m0 replay: 14927 runs, COMPLETE=True, MISSING=11 (all
untracked/assumption-exempt), BLOCKING=0, DECLARED=4324 (tier2 2574). Full engine
relaunched (notif-final).

### Phase-2 SQL-consumer audits (`_phase2_audits.sh`, not gating `complete`)
- identity_symbolicity: PASS (user_id 2323 / users.id 15728 symbolic, 0 literal)
- statement_note_lint: PASS (no red findings)
- bind_resolution: PASS (243008 binds, 0 ambiguous, 0 unresolvable)
- pc_visibility --gate type,unread,persisted,guid: PASS (all VISIBLE)
- skipped_pcs: `--patched` needs a batch-local `assoc_fold.py` (none exists in any
  batch) -> ran vanilla: RED — 200009 `(VAR == VAR)` + 3377 `(VAR != VAR)` PCs are
  dropped by the src/queries_from_runs fold (the own-profile / person_id-vs-
  current_user compares). This is a src/ pipeline limitation (Class B in fold-space);
  the runtime records the evidence, the engine's coverage/gate see it, only the SQL
  fold discards it. Not fixable batch-locally without a src change -> reported.

## Cycle 5 — full gate #2: 4321 PASS / 3 FAIL (2026-08-27 18:38)
FAIL (all IndependenceAssumption, flip-both fires `COUNT(*) FROM photos`):
`len(records_2_rows) != 0` ⊥ `target_persisted`, ⊥ `target_mentions_container_persisted`,
⊥ `target_mentions_container_commentable_persisted`. Withdrawn by extending
`_nested_pair` to target-chain `_persisted` vars (same nesting mechanism as the
`_guid` pairs). Nothing re-declared. Next: coverage-only -> explore demanded combos.
Coverage-only after withdrawing `_persisted`: BLOCKING=4, all `len(records_2)==0` ×
`target_mentions_container[_commentable]_author_persisted`. `_m1_run.sh` (24 replays,
run errors {}) could not observe them: with records_2 (= post.photos in Mention runs)
empty, `post_page_title` never reads `post.author_name` (`photos.present?` guard), so
the author decision is foreclosed. Those two pair classes were never gate failures
(PASS in gate #2) — my `_persisted` pattern had withdrawn them as collateral.
Narrowed `_nested_pair` to exclude `_author_persisted`; the three FAILed pairs stay withdrawn.

---

## Cycle 2 (2026-08-27) — adversary round 1 voided `complete: true`

`ADVERSARY_REPORT.md`: 2 blocking wins + 1 conditional, plus 4 near-miss
defects. Cycle-1's `complete: true` (4321/4321 assumptions PASS, 15 missing all
untracked) is void. Repairs below; the corpus is regenerated FROM SCRATCH
(cycle-1 dumps moved to `_archive_cycle1_dumps/`) because notes, decisions and
return kinds all changed.

### BOUNDARY CHANGES (Rule T3 — for harvest into `shared/target_boundary.rb`)

Every item below is a change to a TARGET DECLARATION, not to a shim. They are
implemented batch-locally in `concolic_targets.rb` / `targets.rb` only because
`shared/target_boundary.rb` does not exist yet; each voids every endpoint
(T2).

| # | target | OLD note / return | NEW note / return | real statement that justifies it |
|---|--------|-------------------|-------------------|----------------------------------|
| B1 | `Diaspora::MessageRenderer#title` | note `"Diaspora::MessageRenderer#title"` (non-SQL); returns a concrete title string | **WITHDRAWN** — no target; the real body runs | `title` -> `plain_text_without_markdown` (message_renderer.rb:176-183) -> `diaspora_links` (:100-105) -> `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?` (29 real calls over 5 requests, html/json/mobile). A non-SQL note over a body that reaches a target swallows it (T4 bullet 1). |
| B2 | `Diaspora::MessageRenderer::Processor.process` | note `"…Processor.process"`; returns the message unchanged, block NEVER executed | **WITHDRAWN** | it EXECUTES the renderer block; `plain_text_without_markdown`/`plain_text_for_json` both put `diaspora_links` in that block. Same swallow as B1, one level down. |
| B3 | `Diaspora::Mentionable.people_from_string` | note none; returns `[]` | **WITHDRAWN** | mentionable.rb:46-49 maps each scanned identifier through `find_or_fetch_person_by_identifier` -> `Person.find_or_fetch_by_identifier` -> a real people/profiles lookup (+ Discovery). `hardening_lint` H3 candidate; same class as B1. |
| B4 | `ActiveRecord::FinderMethods#exists?` | note `sql_for` = `SELECT "posts".* …` (whole-row read); returns a SymbolicBool ALWAYS (truthy at C level, so the false arm was unreachable) | note `SELECT 1 AS one FROM <t> WHERE <col> = $$(…) LIMIT 1`, emitted on BOTH arms (false arm routes it through the no-op probe, since `nil` carries no note); returns the SymbolicBool on the true arm, `nil` on the false arm | finder_methods.rb#exists? builds `except(:select,:distinct,:order).select("1 AS one").limit(1)`. T4 bullet 2. |
| B5 | `SingularAssociation#find_target` / `BelongsToPolymorphicAssociation#find_target` | `SELECT "t".* FROM "t" WHERE "t"."col" = $$(…)` | same + `"t"."type" IN ('<Klass>')` when `klass.finder_needs_type_condition?`, and + `LIMIT 1` | `Photo#status_message` (photo.rb:43, belongs_to keyed on `status_message_guid`/`guid`) is really `SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('StatusMessage') AND "posts"."guid" = ? LIMIT ?` (W2 shape 2 / N8). Every singular association load carries LIMIT 1. |
| B6 | `Relation#to_ary` (the paginated list) | length `ct.seed_for(...).to_i` — a frozen concrete 1 in all 14 951 runs | length is a seeded DECISION, recorded (`len == 0`, `len > 1`), domain {0, 1, 3} | `index.html.haml:56` `@group_days.length > 0` and `:76-79` `.no-notifications`; `page=3` over 30 rows is the real `count > 0 AND rows = []`. T4 last bullet. **Engine limitation:** "many" is 3, not 2 — `src/call_interceptor.rb:152` reads a 2-element Array return as the legacy `[value, sort]` tuple, so a 2-row list came back as the bare representative (TypeError in `pager.replace`). |
| B7 | `CollectionProxy#records` / `#load_target` + `FinderMethods#first/last/take` | every collection read minted the association's SCOPE SQL — for `note.actors` the `people INNER JOIN notification_actors` query (494 850 corpus notes, 51 330 of them COUNT) — and left the association UNLOADED, so `.size` minted `SELECT COUNT(*)` too (2 332 photos COUNTs) | the preloader's real semantics: `includes` emits the through-table fetch AND the target-table read, builds the representative rows, and leaves the association LOADED; `first/last/take` on a loaded relation answer from the target with NO note | `notifications_controller.rb:36 .includes(:target, :actors => :profile)`; `_notification.haml:12 note.actors.first`, `notifications_helper.rb:9 .size`, `posts_helper.rb:16-17 photos.present?` then `.size`. finder_methods.rb `find_nth` reads `@records[0]` when `loaded?`; collection_association.rb:216 `loaded? -> target.size`. Zero real occurrences of either family in 7 adversary runs + 3 batch concrete runs. |
| B8 | notification representative: `type` / `target_type` | `target_type` pinned per STI type, with `also_commented`/`comment_on_post` pinned to `"Comment"` | `target_type` is a DECISION over the real set: `{Post, Photo}` for the two commentable types (`_target_is_photo`), and the pin is corrected to the COMMENTABLE | `also_commented.rb:23` / `comment_on_post.rb:22` both pass `comment.commentable`, never the comment; `Photo` includes `Diaspora::Commentable` (commentable.rb:11). Real: `SELECT "photos".* FROM "photos" WHERE "photos"."id" = ?` (W2 shape 1). T4 bullet 3. |
| B9 | post/comment `text`; profile `bio`/`location` | concrete pins with NO link family ("text is never a query argument") | the link family is a decision: `_text_has_dlink`, `_text_dlink_is_post`, `_text_dlink_guid` (a SYMBOLIC var embedded in the text and rebound at the query boundary, so the probe's note binds `$$(…_text_dlink_guid)`); same family on `bio`/`location` (`_disp_*`) | the guid parsed OUT of the text IS the query argument (W1). `profile_presenter.rb:29` runs `plain_text_for_json` over `bio`, which also contains `diaspora_links`. |
| B10 | preloaded collection length | one representative row, frozen | seeded decision `len(<assoc>_rows)` over {0, 1, 4}, recorded (`== 0`, `> 3`) | `notifications_helper.rb:63` `number_of_actors < 4`, `:69` `others.count == 1`, `_notification.haml:12` `actors.first` on an empty set. |
| B11 | `DiasporaFederation::Discovery::Discovery` | wall on `#fetch_and_save` only, and the gem class is autoloaded so `defined?` could be false at install time (wall silently absent) | `require "diaspora_federation/discovery"` first; wall at the OBJECT boundary (`Discovery.new` -> inert object) as well | discovery.rb:43 `clean_diaspora_id` normalizes the handle in the CONSTRUCTOR, before `fetch_and_save`; the real path aborts the JVM (SIGSEGV, exit 134) — adversary A08, and the same crash on conversations_index A03 and comments_index C08-C10. |

`IterableSymbolicList#to_a` (batch-local list class, not a target): a splat
(`[*people]`, mentionable.rb:31) calls `#to_a`, which `SymbolicList` raises on
by design. The sampled-content model has contents — `length` copies of the
representative, exactly what `#each`/`#first` already yield — so `#to_a`
returns them. No new information invented.

### Answers to `hardening_lint` (2026-08-27)

- **H1 formats** — all seven renderable variants are corpus scenarios
  (html/json/mobile × plain/typed + xml); `format_coverage_audit.py` enforces
  it in `extra_audit_cmds`. (The lint run above sampled a single-variant smoke
  corpus.)
- **H2 link-bearing text** — repaired: B9 (decision) + B4 (probe note) + B1/B2
  (the swallowing mocks withdrawn). `1 AS one` notes are now in the corpus on
  both arms of the decision.
- **H3 opaque notes** — `to_param` (`ActiveRecord::Integration#to_param` =
  `id && id.to_s`, pure formatting) and `escape_segment`
  (`Journey::Router::Utils.escape_segment`, pure string escaping) are proven
  leaves: no SQL, no other target in the body. `User#blocks` returns a real
  `Block.where(user_id:)` RELATION — the statement is issued at
  materialization, by the collection target, with its own note; the reader
  itself issues none. `exists?` now carries the existence probe (B4).
  The two that were NOT provable leaves — `MessageRenderer#title` and
  `Processor.process` — are withdrawn (B1/B2), as is `people_from_string` (B3).
- **H4 collection lengths** — B6 (`@notifications`, {0,1,3}) and B10
  (preloaded associations, {0,1,4}); the other `len(...)` dimensions were
  already seeded and explored.
- **H5 pinned type columns** — `target_type` repaired as a decision (B8).
  `mentions_container_type` is DERIVED from `SYM_NOTE_TYPE_PROFILE`
  (MentionedInPost -> Post, MentionedInComment -> Comment): structurally
  determined by the STI type in the app, so it is a decision, not a free pin —
  both values occur in the corpus. `taggable_type = 'Profile'` is not a pin at
  all: it is the literal in the REAL scope of `profile.tags`
  (acts_as_taggable_on), and a Profile is the only taggable this endpoint
  renders (`plain_text_without_markdown` does not call `render_tags`).

### W3 (`Notifications::PrivateMessage` -> `conversations`) — documented pin

Not driven, and now recorded as a pin instead of silence:
`NOTE_TYPE_PROFILES` omits `Notifications::PrivateMessage` because
`app/models/notifications/private_message.rb:22-28` `notify` only does
`new(recipient: recipient).email_the_user(...)` — it NEVER persists a row, so
no pod running this code version can create one (`notification_service.rb:8-9`
wires the type, but nothing calls `create_notification` for it). A row of that
type is legacy/imported data; on html it is a real 500 in the i18n
interpolation (adversary A05), json renders. Pin ledger entry:
`private_message` — foreclosed at `private_message.rb:22-28` (no persistence);
consequence: the `SELECT "conversations".* FROM "conversations" WHERE
"conversations"."id" = ?` preload shape is absent from this endpoint's policy.

### RULE S (2026-08-27) — waivers abolished: every shim now RUNS

Result: **11 PASS, 22 PROTOCOL, 0 WAIVED, 0 NO-TEST** (was 1 PASS / 32 WAIVED).
`shim_tests.rb` was rewritten: a real sqlite fixture DB (the project's own
`concrete_env`, rows only — no app logic stubbed), the symbolic runtime loaded
for the rep constructor, and `install!` NEVER called (not one target is
declared in the shim-test process).

Two `targets.rb` refactors were needed to make shim bodies reachable at all —
same bodies, same install sites, just addressable:
- `NotifDeviseUserNaming.decorate_session_user!(u)` — the three session-user
  singletons (`persisted?`, `new_record?`, `unread_notifications`) were defined
  INSIDE the `devise_user_first` target's return lambda, so the only way to
  reach them was to invoke that target, which no shim test may do;
- `NotificationsIndexTargets::AssetPathShim` / `::GonPreloadsShim` — anonymous
  `Module.new` objects created inside `install!`; hoisted to named constants so
  the test can prepend them to a throwaway receiver. (The extractor then names
  their keys `<owner>.DYNAMIC`, which is what `shim_tests.rb` keys on.)

**Three shims cannot satisfy "zero target invocations" by construction —
for the coordinator to rule on.** Each is a DELEGATING WRAPPER whose body's
`super` (or whose only statement) IS a declared target:
| shim | why a zero-target run does not exist | targets excluded (exactly the ones its own body calls) |
|---|---|---|
| `ActiveRecord::Relation.pluck` | body is "stash the projection; `super`", and `super` is `Calculations#pluck`; the real body's LOADED arm is `records.pluck(...)` | `Calculations#pluck`, `Relation#records`, `Relation#to_a` |
| `ActiveRecord::Associations::CollectionAssociation.size` | the unloaded arm IS `count_records` -> `Calculations#count`; reaching the `loaded?` arm requires the association loaded (`CollectionProxy#load_target` -> `records`) | `Calculations#count`, `CollectionProxy#load_target`, `Relation#records`, `Relation#to_a` |
| `OrmAdapter::ActiveRecord#get` | the whole body is `klass.where(pk => id).first` — the finder is the call it exists to make (through `Relation#records`) | `FinderMethods#first`, `Relation#records`, `Relation#to_a` |
All three are exercised in EVERY arm with 100% line coverage; the exclusion is
named and justified in each entry. No other target may be touched.

**Runtime rep machinery (the structural exception) — the exact list from this
batch, all PROTOCOL, no waivers written:**
`obj.read_attribute`, `obj._read_attribute`, `obj.write_attribute`,
`obj._write_attribute`, `obj.attributes`, `obj.inspect`, `obj.concolic_attrs`,
`obj.concolic_note`, `obj.persisted?`, `obj.new_record?`, and the per-column
rep readers `obj.type`, `obj.mentions_container_type`, `obj.commentable_type`,
`obj.guid` (x2), `obj.language`, `obj.gender`, `obj.image_url`,
`obj.hidden_shareables`, `obj.post_location`; plus the two `value_class` keys
`ActiveRecord::Base.singleton_class.DYNAMIC` and `ActiveRecord::Relation.DYNAMIC`
(the shared `ConcolicKwargsToPositional` prepend). NOTE: three of the column
readers carry documented PINS/decisions rather than plain plumbing —
`type` and `mentions_container_type` (derived from `SYM_NOTE_TYPE_PROFILE`) and
`guid` (a render-safe ConcreteSymbolicString) — flagged in case the central
exclusion should treat those differently.

### Cycle-2 exploration mechanics (what actually moved the checker)

The repairs multiplied the decision space (94 PC nodes -> 232): the link family,
the Photo target, two length dimensions and the preloaded-collection length are
all new axes, and multi-row rendering creates DEEP call ordinals
(`CollectionProxy_records_4/6`, `find_by_4/5`) that only exist when the list has
3 rows. Three mechanisms, in the order they were needed:

1. **Per-type + dimension roots** (`_seed_type*.json`, `_seed_dims.json`,
   `_seed_multirow.json`) — plain seed dicts replayed as worklist roots.
2. **SUFFIX SEEDING** (`SEED_SUFFIXES`, new in `concolic_targets.seed_for`) —
   exact-name demand seeds are frequently INERT on deep decisions because a
   variable name carries the call ordinal of the mock that minted it, and the
   ordinal shifts as soon as an earlier decision changes the call sequence
   (measured: 11 runs seeded `find_by_1_profile_disp_has_dlink = true`, ZERO of
   them evaluated that variable; the 6 runs that did evaluate it carried a
   different ordinal). A suffix seed sets the DIMENSION whatever ordinal
   carries it — which is what a scenario means. Exact-name overrides still win.
3. **Demand -> suffix scenarios** (`_demand_suffix.py`): the checker's missing
   combinations, translated from variable names to dimensions and replayed.

Corpus hygiene: SEEDS_ONLY replays write one dump per root (the gate needs
that), so the corpus accumulates duplicate PATHS. `dump_*` files whose
(variant, PC-signature) already exists are moved to `_dup_path_dumps/` — 12 318
so far, with NO effect on coverage (verified: BLOCKING identical before/after)
and roughly half the peak RSS.

BLOCKING over the cycle: 153 -> 118 (suffix sweep) -> 85 (targeted sweep) ->
67 (multi-row sweep) -> [demand-suffix round running].

### Known real-app 500 in the corpus (not a rig fault)

`gon_load_contact(nil)` (`gon_helper.rb:6`) raises `NoMethodError` when the
preload list is NON-EMPTY and a later notification has no `contacts` row:
`Gon.preloads[:contacts].none? { |c| c[:person][:id] == contact.person_id }`
dereferences the nil contact. Reachable in the real app with two notifications
where the recipient has a contact for one actor and not the other — the
adversary's own A05/A02 hit the same class of real 500. It appears as
`dump_errors={'ActionView::Template::Error': N}` in the coverage summary; the
runs still record their path conditions up to the raise.

### BOUNDARY CHANGES applied from the coordinator harvest (2026-08-28)

- **B-1 `ActiveRecord::Base#reload` — now a TARGET** (`targets.rb`). Real body
  `self.class.unscoped { self.class.find(id) }` is a single-row read; this
  endpoint reaches it through `Person#name` -> `fix_profile` -> (Discovery
  wall) -> `reload`. Mints ONE note,
  `SELECT "<t>".* FROM "<t>" WHERE "<t>"."id" = $$(<receiver's id var>) LIMIT 1`,
  bound to the receiver's own id var, never a literal; returns the RECEIVER and
  clears its association cache as AR does. NOT-FOUND pinned found — PIN LEDGER:
  `fix_profile` reloads only after `Discovery#fetch_and_save`, which either
  saved the profile or raised `DiscoveryError` (a 500), and the row was read by
  id moments earlier in the same request. (The note is emitted through the
  declared no-op probe because `reload`'s return value is the receiver, whose
  own note is its original producing query.)
- **B-2 `Journey::Router::Utils.escape_segment` — no longer a TARGET**: a pure
  URL-escaping leaf that, as a target, minted a junk note on every route
  generation (over-emission). Replaced by `EscapeSegmentShim` (prepend) whose
  `super` IS the real escaper, plus a shim test that runs the real body at zero
  targets and full coverage of both arms.
- **RULE V (DISCIPLINE §10)**: the guids this batch PARSES OUT of a text body
  were named `<rep>_text_dlink_guid` / `<rep>_disp_dlink_guid`, so the fold
  bound them by their longest column-suffix — the row's OWN `guid` — asserting
  a join the app never performs (3 120 occurrences). They are policy
  PARAMETERS and are now minted as `SYM_PARAM_dlink_guid_<rep>` /
  `SYM_PARAM_disp_dlink_guid_<rep>`. `bind_resolution_audit` after the rename:
  **UNRESOLVABLE 0** (was 27), and the genuine derived class is gone.
  REMAINING 1 293 DERIVED-MISBOUND are a FALSE POSITIVE of the audit's own
  regex (`_(?:text|body|message|subject)_[a-z0-9_]+\Z`) matching the
  ASSOCIATION NAME `status_message`: `..._target_status_message_author_id` is
  the StatusMessage row's real `author_id` column (the note is the real
  `people.id = $$(author_id)` join) and `..._target_status_message_guid` is the
  photo's real `status_message_guid` column (photo.rb:43 keys the belongs_to on
  it). Neither is a value parsed out of a body. Reported, not worked around.
- **has_one NOT-FOUND is a decision** (`concolic_targets.rb` W3,
  `SingularAssociation#find_target`) — the adversary's A08 class, and the
  reason B-1's `reload` target could never fire: with `profile` pinned found,
  `people_helper.rb:37`'s `person.profile.nil?` and `Person#name` ->
  `fix_profile` were dead code corpus-wide. Nothing in the schema forces a
  `profiles` row for a person, so the has_one load now carries
  `<rep>_not_found` and returns nil on its closing arm. BELONGS_TO stays
  pinned found (every belongs_to FK this endpoint loads is NOT NULL with an
  ON DELETE CASCADE foreign key — pin ledger). After a `reload` the receiver's
  has_one associations are pinned FOUND (pin ledger: `fix_profile` reloads
  only after `Discovery#fetch_and_save`, which either saved the profile or
  raised `DiscoveryError`); without that pin the not-found decision persisted
  across the reload and 50 of 60 runs died in the view on a nil profile.
  With it: `run errors : {}` and the reload statement
  (`SELECT "people".* … WHERE "people"."id" = $$(…) LIMIT 1`) in the corpus —
  the path the adversary could not run at all (its real Discovery aborts the
  JVM).

### Rule G (DISCIPLINE §11) — gate columns and pin ledger, disjoint and jointly complete

`pc_gate_columns` (columns the app COMPARES and this corpus EXPLORES, each
verified visible in the corpus's path conditions):
`type` (SYM_NOTE_TYPE_PROFILE / SYM_POST_STI / STI `type`), `unread` (8 694
PCs), `persisted` (19 879), `guid` (10 983), `text` (`_text_nil`,
`_text_has_mention`, `_mention_inline_name`, `_text_has_dlink`,
`_text_dlink_is_post` — 21 000+), `first_name` / `last_name` (5 518 each, the
`name_from_attrs` blank decision), `person_id` (identity equality against the
session user's person), `diaspora_handle` (73), `rows` (every `len(...)`
collection-length decision, {0,1,3} for the paginated list and {0,1,4} for a
preloaded association).

PIN LEDGER — columns/inputs this corpus does NOT explore, each with the source
line that forecloses it (disjoint from the gate list above):
| pin | where | why |
|---|---|---|
| `params[:type]` | `notifications_controller.rb:28` | `types.has_key?` is a Hash#eql? wall; driven as a VARIANT (`html_typed` etc.) instead of a symbolic value |
| `params[:page]` | `:32` | WillPaginate `Integer()`/`#to_i` wall; page 1. Its branch-relevant effect (rows on the page, incl. the empty page beyond the last) IS explored as the list-length decision |
| `params[:per_page]` | `:33` | same wall; 25. Same effect explored as the list length |
| `users.language` | rep pin | a real users column, but read only by `set_locale` (a before_action this runner does not dispatch); I18n locale wall |
| `notifications.target_type` for `PrivateMessage` | `private_message.rb:22-28` | `notify` never persists such a row on this code version — documented residue (adversary W3) |
| `taggings.taggable_type` = `'Profile'` | `profile.rb` acts_as_taggable scope | not a pin at all: the literal is in the REAL scope of `profile.tags`; a Profile is the only taggable this endpoint renders |
| `mentions.mentions_container_type` | derived | NOT a free pin: derived from `SYM_NOTE_TYPE_PROFILE` (MentionedInPost -> Post, MentionedInComment -> Comment); both values occur in the corpus (8 341 posts / 3 728 comments container reads) |
| belongs_to associations pinned found | schema.rb FKs | every belongs_to this endpoint loads is NOT NULL with ON DELETE CASCADE; has_one carries a real `_not_found` decision |
| has_one pinned found AFTER a reload | `fix_profile` | Discovery either saved the profile or raised DiscoveryError (a real 500) |
| `User#gender` | WITHDRAWN | was a pin over a delegation that reaches two association targets; removed (see BOUNDARY CHANGES) |

### What tier2 actually declared, and the modelling fix (coordinator question, 2026-08-28)

Measured on the 32 770-declaration set: **20 914 were tier2 "disjoint reps",
and 4 825 of those were pairs of the SAME query family differing only in CALL
ORDINAL** — `CollectionProxy_records_2` vs `_4` vs `_6`, `Relation_to_ary_1`
vs `_2`, `FinderMethods_find_by_1` vs `_4` vs `_5`. Verified by reading the
notes: the three `records_N` variables in one run carry the IDENTICAL
statement on the IDENTICAL receiver
(`SELECT "people".* FROM "people" WHERE "people"."id" = $$(<same rep>_id)`).

So the answer to the question is (b): an artefact of the modelling. The list
model repeats ONE representative row N times, so rendering N rows calls the
same association load / the same finder on the same receiver N times, and each
call minted its own variable — one FACT modelled as three, with the checker
then demanding every pairwise combination between them (combinations that are
unobservable by construction: the second call returns what the first returned).

**Fix: one fact, one variable** (`targets.rb` `one_fact`/`remember_fact`, a
per-RUN memo keyed on (target, receiver identity, rendered statement), reset in
`run_dse.rb` per run; applied to `Relation#records`/`#to_a`,
`CollectionProxy#records`/`#load_target` and the shared finder mock). Measured
after the fix on a 57-run smoke: distinct `CollectionProxy.records` variables
per run went from 3+ to **1 in 50 of 57 runs** (the runs with 2-3 are genuinely
different associations — photos vs actors vs mentions). The declaration set is
regenerated from the new corpus; the remaining tier2 entries are pairs of
GENUINELY different queries, and the blocking combinations that chased the
ordinal families (records_2/4/6 x target-chain guid) disappear with them.

### Over-emission scan (coordinator, 2026-08-28)

`_over_emission_scan.py` diffs every distinct corpus NOTE SHAPE against the
real statements of the five concrete runs. First run: 18 of 32 corpus shapes
had no real counterpart — and the cause was NOT a phantom family but note
FIDELITY: single-row finder notes carried neither `ORDER BY <pk>` nor
`LIMIT 1`, which every real Rails finder statement has (T4). Fixed in
`concolic_targets.rb` (`finder_note`, wired per finder kind, including the
`devise_user_first` alias). The scan is re-run on the regenerated corpus and
its result is reported with the metric table.

### B-4 / B-5 (coordinator harvest, 2026-08-28)

- **B-4 one load, one predicate**: `notifications.target_id` / `target_type`
  carry NO foreign key and are both nullable, so the polymorphic
  `find_target` (W3b) now mints a LIVE `<rep>_target_not_found` decision and
  attaches nothing on its nil arm. It exposes two REAL app 500s that the
  adversary's A04 did not reach (it tested a missing Post target, which the app
  handles via `linked_object.nil?`):
  `Notifications::Mentioned#linked_object` = `target.mentions_container`
  (`mentioned.rb:8`) and `opts_for_mentioned` -> `post.message`
  (`posts_helper.rb:14`) both raise `NoMethodError` on a deleted mention row.
  Recorded as `dump_errors` (the runs still record their PCs up to the raise) —
  the app's own defect on a real database state, not a rig fault.
- **B-5 nothing exists for an empty relation**: the three list mocks
  (`Relation#records`/`#to_a`, `CollectionProxy#records`/`#load_target`,
  `Relation#to_ary`) now read the length FIRST and, at 0, build NO
  representative row and emit NO preload step — the decisions over a
  non-existent row came from `symbolic_instance`, so gating only the preload
  left them alive. `empty_relation_emission_audit.py` is wired into
  `extra_audit_cmds` so the engine runs it on every report.
- `skipped_pcs_audit --patched` now points at `_experiment/variant_d`.

## Cycle 6 — the 28 gate FAILs withdrawn, B-4/B-5 closed, §7 finished (2026-08-28)

Handover state (14:08 report, rc=0): `coverage_complete: false`, **55 missing**
(44 blocking) at 188 nodes / 16 707 runs; assumption gate **17 471 PASS /
28 FAIL**; shims 13 PASS / 20 PROTOCOL; `empty_relation_emission` RED;
`complete: false`.

### 1. The 28 FAILs — WITHDRAWN, never re-declared

The gate's 28 rejections are withdrawn as CLASSES, not as the individual pairs
that happened to be probed. The probe picks ONE snapshot per declaration, so a
sibling PASS on another rep is a property of the probe corpus, not of the code:
narrowing a refuted class to "the rep that failed" is how a hollow declaration
survives. The withdrawal ledger lives in `coverage_assumptions.py` (block
`WITHDRAWN`), and every withdrawn pair stays in the generator's `already` set so
no later tier can re-declare it in another form.

| class | what it claimed | why the gate refuted it | withdrawn |
|---|---|---|---|
| **W-A** display-suffix UntrackedPath (`_first_name`, `_last_name`, `_public_details`, `_birthday_year`, `_text_has_mention`, `_mention_inline_name`, `_guid == ''`) | "the outcome changes only rendered text/CSS; no query differs" | 20 of the 28 FAILs. "flipping the branch changed 3 / 4 / 10 target-call shape(s)". Real mechanism: a blank first/last name reaches `Person#name` -> `fix_profile` -> `reload` (`SELECT "people".* … LIMIT 1`); `_text_has_mention` gates the `mentions` read; a blank actor guid changes 10 shapes | whole family; the ONLY survivors of the tier are the badge COUNT compare and the Journey formatter's `_guid != StringVal('')` (a different expression at `formatter.rb:41`, PASS on all three instances, and its True side is unreachable in actionpack) |
| **W-B** own-profile var-vs-var UntrackedPath | "`current_user.person == person` decides only a CSS class" | FAILed on `…_actors_row_id == …_devise_user_first_1_person_id` (3 shapes). The tier ALSO mis-matched `X == True` as a var-vs-var compare (its regex accepts `True` as a variable name) — which is how `…_devise_user_first_1_person_not_found == True`, a real has_one not-found DECISION, was ever declared display-only | whole tier (6 declarations) |
| **W-C** dispatch ⊥ `_not_found` | "flipping the STI type only adds/removes a whole type-branch's reads" | 4 FAILs on `SYM_POST_STI == 0/1` × `…_mentions_container[_commentable]_author_profile_not_found`: flip-both produced `find_target` ; `reload` ; `load_intermediate SELECT "people".* … LIMIT 1` — shapes absent from base and from both singles. The dispatch decides WHICH chain the not-found decision sits on | the pairs where the non-dispatch side is a `_not_found` decision (dispatch-independence survives for every other decision kind) |
| **W-D** profile-display link family ⊥ contact relationship / identity | tier-2 "disjoint reps" | 4 FAILs, all producing `exists?` + `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT 1`: `_sharing` is what makes `PersonPresenter` render the bio at all, so the bio's diaspora-link probe is gated by it | every tier-2 pair joining a `_disp_has_dlink`/`_disp_dlink_*` decision to a `_sharing`/`_receiving` decision or to a person-identity compare |

### 2. The assumption-set SHAPE — §7 finished (coordinator item 3)

The cycle-5 answer ("tier2 is the inherent complement of the subtractive
complete-graph model") was only half true. Measured on the cycle-5 corpus,
tier2 was still 10 270 declarations over **68 rep keys**, and the audit
(`_tier2_audit.py`, batch-local) found the remaining artefacts:

1. **Finder ordinals.** `one_fact` was keyed on `receiver.object_id`. That
   collapses repeated ASSOCIATION loads (the same association object answers
   twice) but never a FINDER: `Contact.where(...).find_by(...)` builds a FRESH
   relation per call, so rendering the ONE representative row three times minted
   `find_by_1` / `_4` / `_7`, `_2/_5/_8`, `_3/_6/_9` — three variables for a
   query with byte-identical binds. The checker then demanded their pairwise
   identity combinations (`find_by_1_person_id == find_by_4_person_id` and
   friends): **13 of the 44 blocking misses and 4 of the 8 independence FAILs**,
   i.e. states in which three copies of the SAME row have different contacts —
   unobservable by construction. FIX: `one_fact` is keyed on the RENDERED SQL
   (SELECT-shaped notes only), which carries every bind BY VARIABLE NAME, so
   identical SQL in one run is one fact. Measured: a 3-row html run went from
   9 find_by REP families to **3**, with all **9 EVENTS still recorded** (the
   memo returns the first call's row; the interceptor still logs each call, so
   the D1 multiset is unchanged).
2. **A preloaded association modelled twice.** `CollectionProxy#records` /
   `#load_target` re-described a load the preloader had already performed:
   it emitted a SECOND `SELECT "notification_actors".* … = ?` probe event
   (measured: **2 events per dump for 1 real statement**, 58 of 60 dumps) and
   built a SECOND REPRESENTATIVE for the same row
   (`…_CollectionProxy_records_1_row_*` beside the preloader's
   `…_to_ary_1_row_actors_row_*`) — one fact, two reps, and the entire cross-rep
   clique the checker then demanded between them. FIX: when the association is
   already `loaded?`, return the loaded target — same representative, the SAME
   length variable the preload step already recorded its {0,1,4} decision on,
   and NO note. Rails does exactly this (`load_target` returns early when
   loaded). Measured after: `notification_actors` note events **1 per dump**;
   `CollectionProxy_records_*` reps survive only for genuinely UNPRELOADED
   collections (`post.photos`, `contact.aspect_memberships`).

So the answer to the coordinator's question is (b) again — an artefact of the
modelling, in two more places — and it is fixed rather than declared away.

### 3. B-4 — one load, one predicate (and the belongs_to pin was factually wrong)

The cycle-5 pin read: *"BELONGS_TO stays pinned found — every belongs_to FK this
endpoint loads is NOT NULL with an ON DELETE CASCADE foreign key"*. Checked
against `db/schema.rb`'s `add_foreign_key` list (lines 615-645): **false**.
`mentions`, `photos` and `notifications` appear in NO `add_foreign_key` at all,
so `mentions.person_id`, `photos.status_message_guid`, `photos.author_id`,
`notifications.recipient_id` and `notifications.target_id` are all FK-LESS —
the exact shape comments_index's M-3 turned into a win.

The pin is therefore narrowed to what the schema actually licenses:
`ConcolicTargets::FK_BACKED_COLUMNS` transcribes the schema's FK list, and
`ConcolicTargets.fk_backed?(refl)` decides per reflection. A belongs_to over an
FK-LESS column now carries a **LIVE** not-found decision:

* on the `find_target` path (`SingularAssociation#find_target`, concolic_targets.rb),
  and
* on the PRELOAD path (`emit_includes_preloads`, targets.rb) — which previously
  had NO not-found arm at all and always attached a row plus its nested step.
  The preload arm mints **the same predicate name** `find_target` would use
  (`ConcolicTargets.assoc_base_name(owner, assoc) + "_not_found"`), and on its
  closing arm attaches `nil`, sets the association `loaded!`, emits NO read and
  SKIPS the nested step — so the load has exactly one decision whichever path
  performs it, and there is no dead decision paired with a phantom nested read.

New decisions the corpus now carries (verified live):
`…_Relation_records_2_row_person_not_found` (the `mentions.includes(person: :profile)`
preload — `mentions_container.rb:19`), `…_target_status_message_not_found`
(`Photo#status_message`, photo.rb:43), `…_target_author_not_found` (a Photo
target's `photos.author_id`), `…_row_recipient_not_found`.

They expose real app 500s on real database states, recorded as `dump_errors`
exactly as the polymorphic-target ones were: a dangling `mentions.person_id`
makes `mentionable.rb:35` `people.find {|p| p.diaspora_handle == …}`
dereference nil, and a Photo with no status message makes `posts_helper.rb:9-10`
`post.status_message_author_name` dereference nil.

### 4. B-5 — the residue the first pass left

`empty_relation_emission_audit` was RED on the handover corpus: **4 shapes,
1 483 dumps, 6 517 note events**. The cycle-5 fix gated the REPRESENTATIVE and
the preload step on the length, but not the NOTE: the `preloaded` branch of the
CollectionProxy mock rewrote `sql` to
`SELECT "people".* … "id" = $$(<name>_row_id)` BEFORE the length was read, and
that string became the list's note (and its `len(...)` var's note) even at
length 0 — a note binding a row variable the run never mints. Length is now
read FIRST and the per-representative note is built only when it is non-zero.
(The §7 fix above subsumes most of it: a preloaded association now carries no
note at all.) `empty_relation_emission_audit` is wired into `extra_audit_cmds`,
so the engine runs it on every report.

### 5. Rule G (DISCIPLINE §11) — gate list and pin ledger, now BOTH declared

`pc_gate_columns` carried `text` — which is **blind under the audit's own rule**
(`pc_visibility_audit` matches `name.endswith("_" + col)`, and this corpus mints
`_text_nil` / `_text_has_mention` / `_text_has_dlink` / `_text_dlink_is_post`,
never a bare `_text`). Measured on the handover corpus: 0 references. The
10-column list in the config had never been run through the audit — the audit
was invoked with only `type,unread,persisted,guid`.

Fixed in `completion_config.json`, and the pin half is now DECLARED rather than
living only in prose:

* **GATE** (asserted app-compared AND verified PC-visible): `type`, `unread`,
  `persisted`, `guid`, `first_name`, `last_name`, `person_id`,
  `diaspora_handle`, `rows`.
* **`pc_pin_ledger`** (each with its entry in `pc_gate_ledger_notes`):
  `text`, `bio`, `location` (concrete strings WITH the recorded decision family
  the app actually branches on inside them), `target_type`,
  `mentions_container_type`, `commentable_type` (derived from a recorded
  dispatch decision; BOTH values occur in the corpus, so no subclass family is
  foreclosed), `taggable_type` (the literal of the REAL acts_as_taggable scope),
  `language` (compared only by before_actions this batch does not dispatch).
  Request parameters `type` / `page` / `per_page` are recorded in the same block.
* The blanket **belongs_to-pinned-found** entry is REPLACED by the schema-derived
  `FK_BACKED_COLUMNS` rule (§3) — the pin now covers exactly the FKs the schema
  backs, and nothing else.

Gate ∩ pin = ∅; the union is checked against a re-read of
`notifications_controller.rb`, `index.html.haml`, `index.mobile.haml`,
`_notification.haml`, `notifications_helper.rb`, `people_helper.rb`,
`posts_helper.rb`, `mentionable.rb`, `mentions_container.rb` and
`person_presenter.rb`.

### 6. Round-1 adversary wins — still closed, verified in THIS corpus

| item | evidence in the cycle-6 corpus |
|---|---|
| **N-1** `Post.exists?` link family | `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT 1` present as its own note shape; `MessageRenderer#title`, `Processor.process` and `people_from_string` remain WITHDRAWN as targets (the bodies run). `hardening_lint` H2 = "an exists?-family target in the corpus: yes / any existence-probe note: yes"; H3's three remaining opaque-note CHECKs are answered below |
| **N-2** `Photo` notification target | `SELECT "photos".* FROM "photos" WHERE "photos"."id" = ? LIMIT 1` and `SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('StatusMessage') AND "posts"."guid" = ? LIMIT 1` both present; `target_type` is the `_target_is_photo` DECISION over {Post, Photo} |
| **N-3** `conversations` read | still absent by design — documented pin, now DECLARED (`private_message` in the pin block): `private_message.rb:22-28` `notify` never persists such a row |
| collection lengths are decisions (0/1/many) | `len(…_to_ary_1_rows)` {0,1,3} and `len(…_actors_row_rows)` {0,1,4}, both with `== 0` and `> 1` / `> 3` recorded explicitly |
| `people INNER JOIN notification_actors` | 0 occurrences (was 494 850) |
| `COUNT(*) FROM "photos"` | 0 occurrences (was 2 332) |
| `params[:per_page]` | recorded pin, now in `pc_gate_ledger_notes._params_pins`, with the branch-relevant effect explored as the `rows` length decision |

### 7. Answers to `hardening_lint`

* **H1 formats** — all seven variants are corpus scenarios; `format_coverage_audit.py`
  enforces it in `extra_audit_cmds`.
* **H2 link-bearing text** — the decision family and the `1 AS one` probe note are
  in the corpus on both arms.
* **H3 opaque notes** — three CHECKs, each a proven leaf or a documented wall:
  `ActiveRecord::Base.to_param` = `id && id.to_s` (pure formatting);
  `User#blocks` returns a real `Block.where(user_id:)` RELATION — the statement is
  issued at materialization by the collection target, with its own note, and the
  reader itself issues none; `Anonymous.new` is
  `DiasporaFederation::Discovery::Discovery.singleton_class#new` — the B11 federation
  WALL at the object boundary (`discovery.rb:43` normalizes the handle in the
  CONSTRUCTOR), whose real path aborts the JVM on all three endpoints.
* **H4 collection lengths** — see §6.
* **H5 pinned type columns** — every one is declared in `pc_pin_ledger` with a
  ledger entry (§5).

### 8. The coordinator's propagation matrix (2026-08-28), row by row

| item | this batch |
|---|---|
| **T-a** link-bearing text / no non-SQL note over a SQL-reaching body | closed in cycle 2 (N-1); re-verified: `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT 1` is a corpus note shape, `MessageRenderer#title` / `Processor.process` / `people_from_string` are withdrawn as targets, `statement_note_lint` shows 4 JUNK notes and each is answered (§7) |
| **T-c (B-4)** FK-less belongs_to | done this cycle, on BOTH paths, with one shared predicate — see §3 |
| **T-d (B-5)** nothing exists for an empty relation | `empty_relation_emission_audit` PASS and wired into `extra_audit_cmds` — see §4 |
| **T-e (Rule V)** DERIVED-MISBOUND 0 | one of the two names is fixed by a call-site-stable alias; the OTHER IS IRREDUCIBLE — see §9 |
| **T-f (M-5)** `set_locale` | MODELLED, not pinned — see §10 |
| **T-g (M-6)** STI `*_type` is a placeholder | reachability + consequence argument in the pin ledger for `notifications.type` and `target_type`; the consequence of an out-of-tree value is a request TRUNCATION whose statement set is a strict PREFIX of the modelled one — see `completion_config.json` `pc_gate_ledger_notes.type_STI_reachability` |
| **T-h** `reload` mints its single-row re-read; `escape_segment` / `Discovery.new` mint nothing | `reload` is a target minting exactly `SELECT "people".* … "id" = ? LIMIT 1` (B-1, cycle 5). `escape_segment` is already a SHIM here (`EscapeSegmentShim`), not a target — 0 events. `Discovery.new` is still a declared target minting an EMPTY note (147 events in a 2 747-dump sample): it is the object-boundary WALL, and demoting it to a shim is impossible to VERIFY under Rule S because the real body aborts the JVM (now diagnosed as Faraday typhoeus → Ethon → libcurl via JFFI). **Reported as a BOUNDARY item, not changed** |
| **T-i** length is a decision, one fact one variable | see §2 and §6 |
| **T-j** over-emission | `people INNER JOIN notification_actors` and `COUNT(*) FROM "photos"` are both 0 corpus-wide |
| `note_fidelity_audit` now judges `=` vs `IN`, `LIMIT`, `ORDER BY` | RE-RUN and REPAIRED — see §9 |

### 9. note_fidelity with the new judges, and the one irreducible DERIVED-MISBOUND

The re-run was **RED**: `PRED-OP-DIFF 7`, `LIMIT-DIFF 3`. Both had the same
root cause, and it was a real modelling defect, not a normalizer artefact:

* **LIMIT-DIFF** — the controller's `includes(:target, actors: :profile)`
  PRELOADS the polymorphic target, so the real statement is
  `SELECT "posts".* FROM "posts" WHERE "posts"."id" = ?` with **no LIMIT**
  (26x in this batch's concrete runs), while the corpus modelled that same load
  as a lazy `find_target` with `LIMIT 1`. `emit_includes_preloads` skipped every
  polymorphic reflection (`next unless r2 && !r2.polymorphic?`). It now emits
  the polymorphic step, attaches the row, and `find_target` no longer fires for
  it — so `posts.id = ?` (preload) and `posts.id = ? LIMIT ?` (the genuinely
  lazy `mentions_container` / `commentable`, 10x real) are BOTH in the corpus,
  each from the load that really issues it. `LIMIT-DIFF: 0`.
* **PRED-OP-DIFF** — ActiveRecord's `ArrayHandler` builds an EQUALITY for a
  one-element key set and `IN (…)` for several, so the endpoint really issues
  BOTH (`notification_actors.notification_id = ?` 4x and `IN (…)` 22x;
  `people.id = ?` 56x and `IN (…)` 2x; `profiles.person_id = ?` 48x and
  `IN (…)` 2x). The corpus had only `=`. The preload note now follows the
  modelled OWNER COUNT — which is already a recorded decision, the list length
  — so `len == 1` renders `=` and `len > 1` renders `IN (…)`, and both shapes
  are in the corpus for every preload step.

**DERIVED-MISBOUND** went 42 → 1 on the same sample. The fixed one was
`…_target_status_message_author_id`: the rep base came from the ASSOCIATION
name `status_message`, whose `_message_` matched the audit's
`DERIVED_RE`; a call-site-stable alias (`status_message` → `statusmessage`,
Rule T1 — naming only) removes the substring collision without changing what
the variable is.

The remaining one is **IRREDUCIBLE and is an AUDIT DEFECT**:
`…_target_status_message_guid` is the **real `photos` column
`status_message_guid`** (`db/schema.rb:338`), and the note it appears in is the
real join `photo.rb:43` performs
(`belongs_to :status_message, foreign_key: :status_message_guid, primary_key: :guid`
→ `SELECT "posts".* … "posts"."guid" = $$(<photo>_status_message_guid)`).
The fold resolves it CORRECTLY today: `status_message_guid` is the longest
suffix that is a real `photos` column. Renaming it to satisfy `DERIVED_RE`
would make the longest matching suffix `guid` — i.e. would make the fold assert
`posts.guid = photos.guid`, **creating exactly the Rule V defect the audit
exists to catch**. `DERIVED_RE` should key on the value's PROVENANCE (the
`SYM_PARAM_*` family) rather than on a substring of a column name; as written it
cannot distinguish `messages.text`-derived values from the column
`photos.status_message_guid`.

### 10. T-f (M-5) — `set_locale` is modelled, not pinned

`run_dse.rb` now dispatches the REAL `ApplicationController#set_locale` inside
the interceptor run, before the action body, and the User representative carries
a LAZY decision `<rep>_language_available` (minted only when the column is
actually read, so the notification's `recipient` User rep does not acquire a
consequence-free PC). Measured on a 60-run smoke: the decision is recorded on
BOTH polarities, and its closing arm raises the app's own
`I18n::InvalidLocale` after **exactly one target call** — the Devise principal
load — which is precisely M-5's shape. `language` therefore MOVES from the pin
ledger to the GATE list (Rule G: the two sets change in the same edit).

### 11. BOUNDARY CHANGES (Rule T3 — for harvest into `shared/target_boundary.rb`)

Every item is a change to a TARGET DECLARATION or to the shared association
toolkit, implemented batch-locally only because `shared/target_boundary.rb`
does not exist yet. Each voids every endpoint (T2).

| # | target / toolkit | OLD | NEW | the real statement that justifies it |
|---|---|---|---|---|
| C1 | `emit_includes_preloads` (shared preload toolkit) | skipped every POLYMORPHIC reflection, so `includes(:target)` was modelled as a lazy `find_target` with `LIMIT 1` | emits the polymorphic step, attaches the row and leaves the association loaded, so `find_target` does not fire for it | real: `SELECT "posts".* FROM "posts" WHERE "posts"."id" = ?` / `"mentions"."id" = ?` / `"photos"."id" = ?`, all WITHOUT `LIMIT` (26 / 12 / 4 occurrences in this batch's concrete runs) — the corpus had only the `LIMIT 1` form |
| C2 | `emit_includes_preloads` predicate shape | always `= $$(key)` | `IN ($$(key))` when the modelled OWNER COUNT > 1, `= $$(key)` when it is 1 | ActiveRecord's `PredicateBuilder::ArrayHandler` builds an equality for a one-element key set and `IN (…)` for several; both are real (`notification_actors.notification_id` `= ?` 4x / `IN (…)` 22x, `people.id` `= ?` 56x / `IN (…)` 2x, `profiles.person_id` `= ?` 48x / `IN (…)` 2x) |
| C3 | `emit_includes_preloads` belongs_to rep name | `<owner>_<assoc>_row` | `assoc_base_name(owner, assoc)` — the SAME base `find_target` uses | one fact, one variable: a load done by the preloader and a load done lazily must be one rep, and the belongs_to target's `id` IS the owner's FK (same value, same variable) |
| C4 | `SingularAssociation#find_target` belongs_to arm | pinned FOUND unconditionally ("every belongs_to FK … is NOT NULL with an ON DELETE CASCADE foreign key" — factually FALSE) | pinned found only when the FK column is in `FK_BACKED_COLUMNS` (transcribed from `db/schema.rb`'s `add_foreign_key` list); otherwise a LIVE not-found decision | `mentions`, `photos` and `notifications` appear in NO `add_foreign_key`: `mentions.person_id`, `photos.status_message_guid` (`optional: true`), `photos.author_id`, `notifications.recipient_id`, `notifications.target_id` can all dangle |
| C5 | `emit_includes_preloads` belongs_to arm | no not-found arm at all; always attached a row AND its nested step | the same LIVE decision as C4, attaching nil, emitting no read and skipping the nested step | comments_index M-3: a dead decision plus a phantom nested read |
| C6 | `CollectionProxy#records` / `#load_target` | re-described a load the preloader had already performed (a duplicate join-table probe event and a duplicate representative) | returns `@association.target` when the association is `loaded?` — same rep, same length variable, no note | Rails `CollectionAssociation#load_target` returns early when loaded; measured 2 `notification_actors` note events per dump for 1 real statement |
| C7 | `one_fact` memo key | `(kind, receiver.object_id, sql)` | `(kind, sql)` for SELECT-shaped notes | a finder builds a FRESH relation per call, so the same query rendered three times minted three variables |
| C8 | `Discovery.new` (`Anonymous.new`) | a declared TARGET minting an EMPTY note | **unchanged — reported, not changed.** T-h wants it to mint nothing, i.e. to be a shim; Rule S then requires the real body to RUN, and it aborts the JVM (Faraday typhoeus → Ethon → libcurl via JFFI). A shim that cannot be tested is not an improvement over a wall that is declared |

### 12. The second coordinator harvest (B-6 … B-8, M-5 … M-9, T-k … T-p)

| item | this batch |
|---|---|
| **B-6 / T-k** never raise inside a `returns` lambda | The only mock that raises is the SHARED `finder_mock(raise_on_missing: true)` (`concolic_targets.rb:739/749`, `ActiveRecord::RecordNotFound`). LEDGER ENTRY (the allowed close): that arm is **unreachable on this endpoint** — a 2 000-dump scan finds **0** events for every `raise_on_missing: true` target (`FinderMethods#find/find_by!/first!/last!/take!`, `Core::ClassMethods#find/find_by!`) and **0** `RecordNotFound` terminals; the only terminals in this corpus are raises by REAL APP CODE (`I18n::InvalidLocale` from `set_locale`, `ActionView::Template::Error` from the nil-mention / nil-status-message / nil-contact paths), which is what B-6 asks for. Reported as a BOUNDARY item for the shared finder mock; not changed here |
| **B-7 / T-l** length domain 0 / 1 / MANY | APPLIED. `Relation#to_a`/`#records` and `CollectionProxy#records`/`#load_target` now clamp to {0, 1, 3} and record BOTH edges (`len == 0`, `len > 1`) as decisions, exactly as `to_ary` already did; `coverage_report.apply_len_bounds` raises the solver bound for every `*_rows` variable from 1 to 3 (4 for a preloaded association, which carries the extra `>= 4` arm of `notifications_helper.rb:63`). BEFORE: `Relation_records_1/2_rows`, `CollectionProxy_records_*_rows` and `_target_photos_row_rows` were all {0,1} |
| **B-8 / M-9** a note-less target call loses its statement | APPLIED, `noteless_call_audit` PASS (was **5 624 events across 3 267 dumps**, 10 targets). Two distinct classes, fixed differently: (a) arms that DID issue a statement and returned falsy — `FinderMethods#exists?` false arm, `SingularAssociation#find_target` / `BelongsToPolymorphicAssociation#find_target` not-found arms, the shared `finder_mock` not-found arm, and the `emit_includes_preloads` belongs_to not-found arm (which now also EMITS the read it performed) — publish the real SQL via `Thread.current[:concolic_pending_note]`; (b) arms that issue NOTHING — `first`/`last`/`take` on a LOADED relation, `CollectionProxy#records` on a preloaded association, the same on an EMPTY preloaded association, the `Discovery.new` wall and `User#blocks` — publish an explicit NON-SQL note saying so, because "no statement" and "swallowed statement" must not look alike |
| **M-7 / T-o** the preload predicate follows the DISTINCT FK COUNT | APPLIED, and it WITHDREW a change made earlier in this same cycle: the preload note had been made cardinality-driven (`IN (…)` when the modelled owner count > 1) to clear `note_fidelity`'s new `PRED-OP-DIFF`. M-7 is right that a MANY list of N copies of ONE representative has ONE distinct key, so `= $$(key)` is the only shape this model can honestly emit. **Consequence, reported not hidden — see §13** |
| **M-8 / T-p** a nested preload step follows the parents actually loaded | APPLIED: `emit_includes_preloads` threads a `child_count` down (`ocount` through a belongs_to, `ocount * an` through a collection) instead of reusing the outer cardinality, and the nested step is skipped entirely when the parent was not loaded (the B-4 not-found arm) |
| **T-m** an n-valued column encoded as a compare chain | ALREADY SATISFIED, structurally: the dispatch variables are INTEGER seeds with a declared closed domain (`coverage_report.apply_len_bounds`: `SYM_NOTE_TYPE_PROFILE` 0..7, `SYM_POST_STI` 0..1), so `x == v1 ∧ x == v2` is UNSAT for the solver and is never demanded; the STI `type` string compares are compares of ONE string variable against distinct literals, which Z3 also refutes without a declaration |

### 13. The one thing this cycle could NOT close: the multi-key preload shape

With M-7 applied, `note_fidelity_audit` reports `PRED-OP-DIFF` for exactly one
family: the real bulk preloads issued when the page holds MORE THAN ONE
notification —

    real: SELECT "notification_actors".* … WHERE "notification_actors"."notification_id" IN (?, ?)      (22 occurrences)
    note: SELECT "notification_actors".* … WHERE "notification_actors"."notification_id" = $$(…_row_id)
    real: SELECT "people".*   … WHERE "people"."id"          IN (?, ?, ?, ?)
    real: SELECT "profiles".* … WHERE "profiles"."person_id"  IN (?, ?, ?, ?)

This is not a batch defect and no batch action fixes it:

* the app issues `= ?` for ONE owner key and `IN (…)` for several
  (`PredicateBuilder::ArrayHandler` builds an equality for a one-element key
  set) — both are real, and this batch's own concrete runs contain both;
* `src/ruby_runtime/list.rb`'s sampled list holds **one representative row**
  ("Honest limits: one rep row, not N distinct rows"), so a modelled list of
  length 3 is three copies of one row and has exactly ONE distinct key;
* M-7 therefore forbids the only note the model could otherwise render
  (`IN ($$(one_bind))`), and the multi-key state is INEXPRESSIBLE.

The two ways out both live outside a batch: give the sampled list N distinct
row KEYS (a `list.rb` change), or make the projection judge compare per STATE
(a real statement from a state the corpus cannot express is a Class-B gap, not
a Class-S mis-shape). Raised to the coordinator; `note_fidelity_audit` is left
WIRED into `extra_audit_cmds` rather than quietly unwired, so the residue stays
visible in every report.

### 14. Rule G repair found by running the gate audit for real

`pc_visibility_audit --gate` matches a column by `name.endswith("_" + col)`.
Two entries of the inherited `pc_gate_columns` list had never been run through
it (the audit had only ever been invoked with `type,unread,persisted,guid`),
and both were BLIND under that rule:

* **`text`** — this corpus mints `_text_nil`, `_text_has_mention`,
  `_text_has_dlink`, `_text_dlink_is_post`, never a bare `_text`: 0 references.
  `text` is a PIN here (a concrete string with a recorded decision family over
  what the app branches on inside it), so it MOVES to `pc_pin_ledger` with its
  entry — the Rule G edit that adds it to one set removes it from the other.
* **`language`** — the T-f decision was first named `<rep>_language_available`,
  i.e. named for the PREDICATE rather than for the COLUMN, so gating `language`
  read as a blind branch. Renamed to `<rep>_stale_language` (true = the stored
  value is no longer a shipped locale), which is both what the decision means
  and what the audit can see.

### 15. Instrument defects found and reported (not worked around)

1. **`bind_resolution_audit` DERIVED-MISBOUND is a FALSE POSITIVE on a real
   column** — `photos.status_message_guid`. `DERIVED_RE`
   (`_(?:text|body|message|subject)_[a-z0-9_]+\Z`) matches the `_message_guid`
   inside the COLUMN NAME. The audit has already RESOLVED the bind to a real
   `photos` column at that point and then overrides its own positive
   resolution on a name heuristic. The note is the real join `photo.rb:43`
   performs (`belongs_to :status_message, foreign_key: :status_message_guid,
   primary_key: :guid`), and renaming the variable to escape the regex would
   make the fold's longest-column-suffix matcher bind `photos.guid` instead —
   i.e. would CREATE the `posts.guid = photos.guid` join that Rule V exists to
   prevent. SUGGESTED ONE-LINE FIX: re-label as `derived` only when the matched
   suffix is NOT itself a real column of the producing row's table (the audit
   computes exactly that a few lines earlier). The other DERIVED name of this
   batch (`…_target_status_message_author_id`, from the ASSOCIATION name) IS
   fixed here, by a call-site-stable alias.
2. **`note_fidelity_audit` vs the sampled-content model** — see §13.
3. **`skipped_pcs_audit` needs the `queries_from_runs` venv** (`sqlglot`); run
   under plain `python3` it dies with `ModuleNotFoundError` and EXIT=1, which
   is indistinguishable from a RED. Now invoked with the venv interpreter in
   this batch's `_audits6.sh`, as `bind_resolution` already was.

### 16. DISCIPLINE §13 Rule D — derive what is determined (coordinator, 2026-08-29)

Rule D arrived mid-cycle and REVERSED M-7 for this endpoint, so the preload
key model was rebuilt a third time. The final position, and why it is the
right one:

* the predicate follows the KEY SET, and the key set is DERIVED from the rows
  actually loaded — `len > 1` on a list means N physical rows, and N physical
  rows have N distinct keys (M-7's `= ?` case is the one where the FK VALUE
  repeats, e.g. two comments by the same author, not the row count);
* Rule D(c) — one physical row, ONE variable: row j's key is its own variable
  `<list>_row<j>_<pk>`, minted with the producing query as its note, so the
  fold still resolves it to the same column of the same producer and the
  `people.id = <table>.<fk>` chain survives for rows 2..N;
* Rule D(a) / M-8 — a NESTED step's key count follows the parents actually
  loaded (`ocount * an`), never the outer cardinality, and the collection's own
  cardinality is now decided FIRST so everything below it can be derived from
  it (it also records `> 1` now, not just `== 0` / `> 3`, so
  `cardinality_consistency_audit` can read the decision back);
* an EMPTY preloaded collection loads as `[]` with no representative, no
  target-table read and no nested step (B-5 again, one level down).

Measured on a 60-run smoke, a 3-notification / 4-actor state now emits exactly
the real bulk shapes:

    SELECT "posts".*               … "posts"."id"                          IN ($$(…_row_target_id), $$(…_row2_target_id), …)
    SELECT "notification_actors".* … "notification_actors"."notification_id" IN ($$(…_row_id), $$(…_row2_id), …)
    SELECT "people".*              … "people"."id"                          IN ($$(…_row_actors_row_id), $$(…_row2_actors_row_id), …)
    SELECT "profiles".*            … "profiles"."person_id"                 IN ($$(…_row_actors_row_id), …)

and a 1-notification state emits the `= …` forms. `note_fidelity_audit`'s
PRED-OP-DIFF family went 7 → 3 on the smoke (the 3 residues are shapes a
51-dump single-variant smoke does not contain), so §13 of this file — the
"multi-key preload shape is unreachable" limitation — is WITHDRAWN: Rule D is
what makes it reachable, and the corpus now carries both cardinalities.

**Two false positives in the new audit, reported not worked around.**
`cardinality_consistency_audit` attributes a bind to a list by the NAME PREFIX
`<list-base>_row`, and a NESTED list's row variables are named as an EXTENSION
of the outer list's row variable
(`…_to_ary_1_row_actors_row_id` extends `…_to_ary_1_row`). So every note about
a nested list, and every lazy singular load hanging off one row, is attributed
to the OUTER list as well:

* `ONE-row state, multi-key IN` — the outer list has 1 row, the ACTORS list
  nested under that row has 4, and its correct `IN (…_row_actors_row_id, …)`
  is charged to the outer list;
* `MANY state, single-key (=)` — `SELECT "people".* … "id" = $$(…_row_target_author_id)`
  is a LAZY singular association load on ONE row (`find_target`, one statement
  per row, exactly what the app issues), charged to the outer list because its
  bind starts with that list's row prefix.

Suggested fix: attribute a bind to the INNERMOST list whose `_row` prefix it
extends (or require the bind to be `<base>_row_<column>` with no further
`_row`/association segment), which is what "reads THIS list's rows" means.

### METRIC TABLE — cycle 6 final engine report (2026-08-29 06:34, rc=0)

| metric | value |
|---|---|
| coverage_complete | `False` |
| missing branches | 319 (truncated=True, solver_lost=0) |
| tree nodes | 133 |
| runs / path conditions | 20869 / 1146456 |
| assumptions declared | 8430 |
| assumptions PASS / FAIL / NOT-TESTABLE | 8418 / 12 / 0 |
| shims | PASS 13, PROTOCOL 20 (of 33 extracted) |
| note check | green |
| dump_errors | {'I18n::InvalidLocale': 14, 'ActionView::Template::Error': 248} |
| **complete** | **`False`** |

| check | verdict |
|---|---|
| `identity_symbolicity` | green |
| `statement_note_lint` | green |
| `bind_resolution` | RED |
| `skipped_pcs` | RED |
| `pc_visibility` | green |
| `empty_relation` | green |
| `noteless_call` | green |
| `cardinality_consistency` | RED |
| `note_fidelity` | green |
| `hardening_lint` | RED |

Engine-run `extra_audit_cmds` (inside `completion`): empty_relation_emission green, format_coverage green, note_fidelity green, noteless_call green.

### 17. State at hand-off, and the three RED checks

`complete: false`. Two blocking items remain, and neither is a regression:

1. **coverage** — 319 missing at 133 nodes. The rise from the hand-over's 55 is
   the intended consequence of this cycle: 53 UntrackedPath declarations were
   withdrawn (so those display branches are now DECISIONS the checker demands),
   the B-4 not-found decisions and the T-f locale decision are new axes, and
   Rule D made the list cardinality interact with everything below it. The
   REASON convergence did not finish is diagnosed and FIXED in the tooling,
   which is the part worth carrying forward:
   * `demand_round.py` seeds ONLY the clique variables — everything else falls
     back to its default and the combination is never reached. Replaced by
     `_demand_root.py`, which roots each demanded assignment on a REAL dump's
     seeds (the dump that records the most of the combination's expressions,
     preferring the OTHER polarity).
   * That was still not enough, and the reason is worth writing down: the Z3
     model returned with a missing combination assigns EVERY variable in the
     clique's declaration set, and its defaults are 0 — including every list
     length. Overlaying the whole model therefore seeds
     `len(...to_ary_1_rows) = 0`, which FORECLOSES the very decisions the
     combination is about (they live on rows that then do not exist). Two full
     demand rounds moved BLOCKING 478 → 478 before this was found. `_demand_root.py`
     now overlays ONLY the variables the combination's constraint mentions.
     Its first replay after the fix is in the corpus; a full convergence loop
     from that point is the next cycle's first job.
   * `_mkroots.py` also replaces the 72 env-level `SEED_SUFFIXES` launches with
     ONE launch per variant over exact-name roots expanded from the corpus's own
     variable table: a JRuby LAUNCH costs ~2.3 min and the exploration ~10 s, so
     the generation plan was launch-bound. 131 launches → 14.
2. **the 12 remaining assumption FAILs** — read, classified and WITHDRAWN as
   classes W-E and W-F in `coverage_assumptions.py` (9 were "a list-cardinality
   decision is independent of X", which Rule D makes false by construction; 3
   were not-found × not-found on the contact finders). The withdrawal is in the
   file; it has not yet been through a gate run.

**The three RED checks, each dispositioned:**

* **`bind_resolution` — 1 shape, an AUDIT false positive** (§15.1):
  `photos.status_message_guid` is a real column and the note is the real join;
  renaming it to escape `DERIVED_RE` would create the very defect Rule V exists
  to prevent. UNRESOLVABLE 0, AMBIGUOUS 0.
* **`skipped_pcs` — 1 936 `(VAR != VAR)` + 54 `(VAR == VAR)`, dispositioned**:
  the site is `activerecord .../association.rb:69 stale_target?`, which compares
  the association's cached stale state to the current one. Both operands are the
  SAME variable (the owner's FK — and since Rule D(c) the belongs_to target's
  key IS the owner's FK, one physical row, one variable), so the compare is a
  tautology carrying no decision, and the fold is RIGHT to drop it. The other
  site is `gon_helper.rb:6`, where the §7 finder memo makes the two contacts one
  fact. Nothing is lost at fold time; no repair is possible without stubbing
  framework plumbing that reaches no target.
* **`cardinality_consistency` — 3 shapes, all AUDIT false positives** (§16):
  two are the nested-list prefix attribution (`…_to_ary_1_row_actors_row_id`
  extends `…_to_ary_1_row`, so the ACTORS list's correct `IN` is charged to the
  outer list), and the third is `"posts"."type" IN ('StatusMessage')` — the STI
  literal predicate, counted by the `uses_in` regex as a bulk key read. The real
  statement carries that literal `IN` (`finder_needs_type_condition?` builds
  `type IN (…)` even for one class), so the note is faithful.
* **`hardening_lint` — 2 CHECKs**: H3 lists `CollectionProxy.load_target`'s
  non-SQL note, which is the B-8 "no statement" note for a PRELOADED association
  (the body reaches no target: `load_target` returns early when `loaded?`, and
  the preloader's own reads are separate events); H4 lists
  `CollectionProxy_records_1_rows` with one polarity — a genuine exploration gap
  for the next cycle, not a modelling one (the domain is {0,1,3} and both edges
  are recorded decisions).

### 18. Round-1 adversary wins re-verified on the CYCLE-6 corpus (2 500-dump scan)

| item | evidence |
|---|---|
| N-1 `Post.exists?` link family | `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT 1` — 1 600 events / 422 dumps |
| N-2 `Photo` notification target | `SELECT "photos".* … "id" = ?` / `IN (?, ?, ?)` (359 events) and `SELECT "posts".* … "type" IN ('StatusMessage') AND "guid" = ? LIMIT 1` (234) |
| N-3 `conversations` | 0 occurrences — the documented `private_message.rb:22-28` pin |
| over-emission `people INNER JOIN notification_actors` | 0 (was 494 850) |
| over-emission `COUNT(*) FROM "photos"` | 0 (was 2 332) |
| collection length is a decision | both cardinalities are in the corpus for every preload step: `notification_actors.notification_id = ?` (1 527) beside `IN (?, ?, ?)` (950); `people.id = ?` (3 608) beside `IN (?, ?, ?)` (2 280) and `IN (?, ?, ?, ?)` (1 228); `profiles.person_id` likewise |
| `params[:per_page]` | recorded pin; `LIMIT 25 OFFSET 0` in the paginated note, effect explored as the `rows` decision |

### 19. Coordinator's audit fixes confirmed, and the hardening lint answered (2026-08-29)

All three audits this batch reported as instrument defects were fixed by the
coordinator and now PASS on this UNCHANGED corpus: `bind_resolution`
(0 unresolvable, 0 derived-misbound), `cardinality_consistency`, `skipped_pcs`
(966 700 parsed, 0 dropped, 179 756 by design). Audit standing is therefore
**identity, note lint, pc_visibility, empty_relation, noteless, note_fidelity,
format_coverage, bind_resolution, skipped_pcs, cardinality — all green.**

**`hardening_lint` now runs H6** (it needs ONE `--runs` followed by every run
file; this batch passes all 13 — its 6 concrete runs plus adversary round 1's
A01–A07). Answers:

* **H6** — 15 unissued shapes on the first real run, all classified and
  declared in `completion_config.json` `h6_answered` with the reason printed:
  * *scope-constant literal vs bound value* — `Notification.unread` puts
    `unread = true` INTO the relation and Arel inlines it, while the real
    statement logs `= ?`. Same tables, same predicate columns, same value;
    `note_fidelity_audit` scores every one EXACT.
  * *key-set arity* — since Rule D a preload renders one bind per row loaded;
    this model's MANY is 3 (4 for a preloaded association) while the concrete
    pages hold 2, 4, 5 and 25 rows, so `IN (@, @, @)` never matches
    `IN (@, @)` byte-for-byte. The projection judge wildcards the bind list and
    scores them EXACT, and `cardinality_consistency` confirms each agrees with
    its run's own `len > 1` decision.
  * *`ActiveRecord::Calculations.pluck`* — **a real defect, REPAIRED**: the
    pluck note appended the ORDER columns to the PROJECTION
    (`SELECT "tags"."name", "taggings"."id"`) on a 2026-08-21 claim that cited
    a REFERENCE trace. This batch's 13 real runs show
    `SELECT "tags"."name" … ORDER BY taggings.id` — the requested column only.
    `targets.rb` no longer appends order columns (Rule T4: pluck ⇒ its real
    projection + ORDER); the old shape leaves the corpus at the next
    from-scratch regeneration.
* **H3 — one CHECK, with its proof, and no mechanism to record it.**
  `CollectionProxy#load_target` carries the B-8 non-SQL note "preloaded
  association: answered from the loaded target, no statement". It is provably
  unable to reach a target: Rails' `CollectionAssociation#load_target` returns
  `target` early when `loaded?`, and on THIS endpoint the association is always
  preloaded by `notifications_controller.rb:36`, so the corpus contains no
  SQL-noted `load_target` call at all (checked at sample 2 000). H3's only
  escape hatch is the literal word `WALL` in the note — which this is not, so
  the CHECK is answered here rather than by mislabelling the note.
* **H4 — two preloaded-photos length dimensions with one polarity**
  (`…_target_photos_row_rows`, `…_commentable_photos_row_rows`). An exploration
  gap, not a modelling one: the domain is {0, 1, 4} and both edges are recorded
  decisions; the fixed demand loop targets them.
* **H6 residue at sample 2 000 — one honest open item, NOT declared answered:**
  `Core::ClassMethods.find_by: SELECT "people".* … "diaspora_handle" = 'concolic_mention@example.org'`.
  The shape is REACHABLE in the real app (a mention whose handle is not among
  the preloaded `mentioned_people` sends `Mentionable.find_or_fetch_person_by_identifier`
  to `Person.find_by(diaspora_handle:)`), so the right answer is a concrete
  scenario that exercises it, not a declaration. Recorded for the next cycle.

### 20. What the W-E withdrawal costs, measured

Withdrawing W-E (a list-cardinality decision is independent of NOTHING) is
correct and is what Rule D implies — the cardinality DETERMINES the statement
shape, so it is jointly dependent with every decision that gates a read. Its
price, measured on the same corpus:

| | before W-E/W-F | after |
|---|---|---|
| independence declarations withdrawn | 255 | **1 240** |
| assumptions declared | 8 430 | 7 445 |
| missing branches | 319 | **7 561** |

The 7 561 are not new blindness — they are the combinations the 12 gate FAILs
were exempting, now demanded. Every one is reachable by seeding: the fixed
`_demand_root.py` roots each on a real dump and overlays ONLY the variables the
combination constrains. What they need is machine time, not another modelling
decision; the demand loop is no longer inert (round 1 after the fix moved the
corpus from 20 869 to 25 052 dumps against a live demand set, where two rounds
of the old loop had moved BLOCKING 478 → 478).

### 21. T-t (conversations_index R3) checked on this endpoint — all three N/A, with evidence

**A write is conditional on dirtiness — NOT APPLICABLE: `#index` performs no
write at all.** `Notification#set_read_state` (`notification.rb:21-23`) is
called only from `NotificationsController#update` and `#read_all`; `#index`
(`:25-58`) builds `conditions`, paginates, groups and renders — no `save`,
`update`, `touch` or `update_column` on the action path or in
`index.html.haml` / `index.mobile.haml` / `_notification.haml`. Measured, not
just read: a 1 500-dump corpus scan finds **0** target events whose name
matches `save|update|touch|create|destroy|delete` and **0** notes beginning
`UPDATE|INSERT|DELETE|BEGIN|COMMIT`.
Worth passing on to whoever models `notifications#update`: `set_read_state`
uses `update_column`, which BYPASSES dirty tracking and the callback chain — it
issues its `UPDATE` unconditionally, so the "unchanged record ⇒ no statement"
decision that T-t demands does NOT apply to that path either; the decision it
does need is the `Notification.where(recipient_id:, id:).first` nil arm.

**Array-valued QUERY parameters — no `IN (…)` finder is reachable.** The action
reads four params, none of them a route segment
(`config/routes.rb` maps `/notifications` with no dynamic segment):
* `params[:type]` — used only as `types.has_key?(params[:type])`
  (`:28`), and `conditions[:type]` is then set to `types[params[:type]]`, a
  single STI string from the app's OWN hash. An Array key misses the hash, so
  the condition is not added at all — it can never reach the relation, let
  alone as an array;
* `params[:show]` — `params[:show] == "unread"` (`:31`); an Array is never `==`
  a String, so the `unread` condition is simply not added;
* `params[:page]` / `params[:per_page]` (`:32-33`) — go to
  `WillPaginate::Collection.create`, whose `Integer()` / `#to_i` raise on an
  Array BEFORE any statement (the same wall adversary A03 measured for
  `page=0` and `page=abc`).
So no query parameter on this endpoint can widen a finder to `IN (…)`; the only
`IN (…)` predicates in this corpus are the Rule D preload key sets.

**An undeclared format — measured, not argued.** `app/views/notifications/`
contains exactly four templates: `index.html.haml`, `index.mobile.haml`,
`_notification.haml`, `_notification.mobile.haml`. There is no `index.js.*`,
`.atom`, `.csv` or any other renderable, and `respond_to` (`:53-58`) declares
`html` / `xml` / `json`. A request for an undeclared format therefore reaches
`ActionController::UnknownFormat` with no template and no statement, rather
than silently rendering the full template as conversations_index's `.js` did.
Renderable = {html, mobile, json, xml}, which is exactly what the seven corpus
variants cover and what `format_coverage_audit` asserts.

### 22. INSTR-1/2/3 — the rig fixes, and what they changed in ground truth

**INSTR-1 (per-process principal memo) — FIXED in all 7 files**
(`concrete_manifest.rb`, `_auth`, `_pages`, `_photo`, `_links`, `_mobile`,
`adversary/_common.rb`): `wuser = lambda { @concrete_user ||= … }` bound the
memo to the lambda's enclosing `self` (`main`), i.e. one principal resolution
per PROCESS. It now binds to the per-request warden
(`warden.instance_variable_get(:@cc_user) || warden.instance_variable_set(…)`).
*Measured impact on THIS batch: none directly* — each manifest here holds ONE
scenario with ONE `tc.process`, so the memo was used once per process and every
existing run file already carried its `users` read and its `people.owner_id`
read. The fix matters the moment any manifest issues a second request, which is
exactly what the adversary's multi-request bodies do.

**INSTR-2 (query cache) — adopted from `src`**; no batch change was needed
(single-request bodies have no "later request" to lose a repeated statement to),
and the probe now clears the cache per scenario.

**INSTR-3 (integer booleans in fixtures) — the one that WAS biting this batch.**
113 boolean fixture values across the 7 files were written as `1`/`0`
(`unread`, `sharing`, `receiving`, `public`, `closed_account`, `searchable`,
`nsfw`, `public_details`, `getting_started`, `disable_mail`), which
`ConcreteEnv.quote` passes through as integers while ActiveRecord queries the
adapter's `quoted_true`. All converted to real `true`/`false`.

**What changed in ground truth after re-running all five manifests:**

| scenario | statements before | after |
|---|---|---|
| index-auth | 76 (users 2) | **81** (users 5) |
| index-mobile | 34 (users 1) | **36** (users 2) |
| index-links | 40 (users 1) | **42** (users 2) |
| index-photo | 36 (users 1) | **46** (users 2, + the photos-scope read) |
| index-pages | 39 (users 1) | **44** (users 4) |

**Both judges re-run on the new ground truth and GREEN:**
`mock_note_check` — "every SQL-issuing target's notes match its real
statements"; `note_fidelity_audit` — MISSING 0, STAR-OVER 0, AGG-COLLAPSE 0,
PROJ-DIFF 0, PRED-OP-DIFF 0, LIMIT-DIFF 0, ORDER-DIFF 0, PRED-DIFF 0,
**EXACT 34** (was 26 on the old, under-reporting ground truth). The corpus
survived a 30 % larger ground truth with no new mismatch.

**A concrete scenario was ADDED rather than a declaration written**: H6 flagged
`SELECT "photos".* … "status_message_guid" = ?` as issued by no real run. That
is the `post.photos` SCOPE read `posts_helper.rb:14-17` takes when the post's
message is BLANK — an association the controller does NOT preload. A blank-text
StatusMessage with two photos and a notification targeting it was added to
`concrete_manifest_photo.rb`; the read is now in ground truth (2 occurrences)
and the shape is matched.

**H6's three remaining shapes are genuine over-emission findings, NOT declared
answered:**
1-2. `SELECT "photos".* … "status_message_guid" = $$(…) AND (1=0)` on two target
   chains — Arel's rendering of an explicitly EMPTY relation. The app issues a
   `1=0` guard only for a `none`d/empty-array scope; no real run issues it, so
   the corpus asserts a read of a relation the endpoint cannot ask for.
3. `Core::ClassMethods.find_by: SELECT "people".* … "diaspora_handle" = '…'` —
   reachable ONLY through `mentions_container.rb:18`'s `persisted? == false`
   arm (`Mentionable.people_from_string` → `find_or_fetch_person_by_identifier`),
   and a container loaded from the database is always persisted. This is the
   SAME open near-miss comments_index carries ("the four `mention_lookup_*`
   targets emit `people.diaspora_handle` for a state no query-returned row can
   be in"); recorded here as the same cross-endpoint class rather than pinned,
   because `persisted` is a gated column whose OTHER use
   (`find_target?`'s `!owner.new_record?`) is a real decision.
