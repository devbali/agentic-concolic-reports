-- posts_show — PostsController#show  (GET /posts/:id)
--
--
-- CANONICAL HEADER. This text is maintained at
-- reports/diaspora/results3/posts_show/POLICY_HEADER.txt and MUST be
-- re-applied to the top of this file by every extraction. Under the M-17
-- resolution (comments C12), the declaration IS the safeguard: a policy file
-- that simply stops at a wall is indistinguishable from one that covers
-- everything, so every exclusion is stated HERE, not only in a report.
--
-- SCOPE (DISCIPLINE §15): the entrypoint is the POST-AUTH action with a
-- SYMBOLIC principal. The authentication stages run ABOVE the entrypoint and
-- are not part of this file; the endpoint's complete policy is THIS FILE
-- UNION §2 of results3/_auth_boundary/BOUNDARY_POLICY.md. On this controller
-- `authenticate_user!` is `only: %i(destroy mentionable)`, so `show` is
-- reachable ANONYMOUSLY and the principal is fetched lazily rather than by the
-- Devise filter — the same statements and hooks, so the boundary artifact
-- applies unchanged.
--
-- TWO in-action escapes back INTO authentication/authorization are part of
-- this action and their reads belong to this file, not to the boundary:
--     rescue_from Diaspora::NonPublic  -> authenticate_user!   (a non-public
--         post fetched anonymously re-enters the Devise filter)
--     rescue_from Diaspora::NotMine    -> render 403           (issues no SQL)
-- MEASURED on this corpus (stride-12 scan of the 99 448-dump snapshot, 8 036
-- dumps, terminal state per scenario):
--     Diaspora::NonPublic   WITNESSED — 543 dumps, all anon_html: an anonymous
--         request for a non-public post. It re-enters `authenticate_user!`,
--         which for an anonymous request cannot authenticate, so the action
--         contributes only the statements issued BEFORE the raise (the
--         `find_public!` read of `posts` by :id or :guid). The concrete round's
--         `posts-show-anon-nonpublic` scenario reproduces it end to end
--         (7 target calls, 1 statement, error=None).
--     Diaspora::NotMine     NOT WITNESSED — 0 of 8 036. DECLARED GAP: this
--         file contains no statement contributed by that arm, and its absence
--         is not evidence that the arm reads nothing. Its handler renders a
--         403 and issues no SQL of its own, but whatever raised NotMine ran
--         first.
--
-- Three render formats are reachable and each has its own statement set:
--     format.html   presenter.with_initial_interactions + gon
--     format.mobile render locals: {post: post}
--     format.json   presenter.with_interactions
-- MEASURED. `run_dse.rb` declares FOUR scenarios — auth/anon x html/json — so:
--     format.json    WITNESSED, and it is the only arm that RUNS TO COMPLETION:
--                    auth_json 1 861 of 1 862 sampled dumps error-free,
--                    anon_json 1 691 of 1 698.
--     format.html    DRIVEN BUT NEVER COMPLETED. **ZERO of 4 476 sampled html
--                    dumps reach the end of the action.** Every one that gets
--                    past the finder dies in the view with
--                    `ActionView::Template::Error: uninitialized constant
--                    PostsTargets::ConcreteSymbolicString` — a batch-local
--                    regression introduced by the 2026-09-09 Rule-T re-sync
--                    (it deleted the class's definition from this batch while
--                    ADDING a use of it at targets.rb:666, the `to_param` wall
--                    mock on the metas-render path). REPAIRED batch-locally on
--                    2026-09-10 with a ground-truth differential, but the arm
--                    still terminates one layer deeper, at
--                    `SymbolicString#scrub` via `Multibyte::Unicode.tidy_bytes`.
--                    **DECLARED GAP: none of the html VIEW's reads are in this
--                    file.** See _COMPLETION_20260910.md §12 and §14.
--     format.mobile  NOT DRIVEN AT ALL — no scenario exists for it. DECLARED
--                    GAP, not evidence that it reads nothing.
--
-- ============================================================================
-- ============================================================================
-- STATUS, 2026-09-15 — **THIS ENDPOINT IS NOT COMPLETE. THIS POLICY SHIPS
-- INCOMPLETE, BY OWNER DECISION.**  (P35; full record `_COMPLETION_20260910.md`
-- §103-§112)
-- ============================================================================
-- Every other diaspora endpoint shipped its policy after earning
-- `OVERALL_COMPLETE=True`. **posts_show did not, and no reader should mistake
-- this file for a closed one.** It is shipped because a policy for all six
-- endpoints gates a benchmark run, and because an honest incomplete policy with
-- its residue stated is worth more than no policy. What follows is that
-- residue.
--
-- THE VERDICT, from today's passes over the 49 568-profile snapshot
-- (49 568 = the 48 943-profile round-10 snapshot + 625 constructed witnesses):
--
--   COMPLETE=False   NODES=137   MISSING=706   BLOCKING=706   PCS=2 137 905
--   DEMAND_SETS=995  TREE_COMPLETE=True  TREE_MISSING=0  FORECL_PROVISIONAL=False
--   with §16e+§16f OFF entirely (P38NF):        MISSING=708
--
-- MISSING is capped at one leaf per demand set (`MAX_MISSING_PER_CLIQUE=1`), so
-- 706 means **706 of 995 demand sets carry at least one uncovered leaf (71 %)**.
-- The per-ASSIGNMENT residue is far larger — the §16b census, with NO
-- conjunction pruning at all:
--
--   sets 998   satisfiable 1 039 416   covered 74 192   REMAINING 965 224
--                                                       = **92.9 % UNCOVERED**
--
-- The headline is ROBUST to the §16f collapse described below: turning §16e and
-- §16f off entirely moves MISSING by 2 (706 -> 708).
--
-- ---------------------------------------------------------------------------
-- WHY IT IS NOT CLOSABLE — EVERY LEVER, MEASURED, EACH WITH ITS FALSIFIER
-- ---------------------------------------------------------------------------
--   base SELECTION         EXHAUSTED    2 genuine misses in 525 gaps (0.4 %)
--   base MANUFACTURE       IMPOSSIBLE   399 of 401 blocked gaps are foreclosed
--                                       on the §16b argument: in every run that
--                                       realises the cube's pins the blocking
--                                       gate is NEVER EVALUATED (median 185
--                                       such runs, 0 evaluations). A base
--                                       cannot be built, not merely not found.
--   §40.5a discriminators  NULL         124/525 admissible in BOTH arms; 0 of
--                                       525 gaps differ in base, gates or
--                                       admissibility. Corroborated: alias
--                                       coverage was already N/N in all 401
--                                       failures, so there was nothing to fix.
--   §16g conditioning      NULL         the pre-stated falsifier FIRED: -68
--                                       cubes, and 6 ordinal-2 (C,d) classes
--                                       against ~449 predicted. Cause measured:
--                                       for 161 of 281 the foreclosing
--                                       conjunction is not expressible from the
--                                       leaf's own literals at all.
--   §16f WIDTH (W=5)       WITHDRAWN    it prunes more but buys NO evidence:
--                                       0 PASS of 688 wide classes, and the
--                                       untestable share rises 10.1 % -> 50.3 %.
--   §16f ITSELF            REFUTED      see below — 484 FAIL / 0 PASS.
--   DRIVING                -4 cubes for 625 constructed runs (MISSING 710->706)
--
-- ---------------------------------------------------------------------------
-- §16f FORECLOSURE IS REFUTED ON THIS ENDPOINT — THE LARGEST FINDING
-- ---------------------------------------------------------------------------
-- Foreclosure (§16e/§16f/§16g) prunes demand on corpus evidence alone and had
-- never been probed. A gate was built for it (`foreclosure_gate.py`): for each
-- applied class `(C, d)` it CONSTRUCTS a run realising `C` and asks whether `d`
-- is evaluated, which is exactly what `B(C,d)=0` forbids.
--
--   856 applied classes -> PASS 0-2, FAIL 484-491, NOT-TESTABLE 363-372
--   positive control GREEN 537-561 of 856 (62-66 %) — the constructor
--   demonstrably builds, so silence is informative and not vacuous
--
-- **Of the classes that could be probed at all, 99.6 % were refuted by a
-- witness run.** Verified, not asserted: 36 of 36 sampled witnesses were
-- re-read from their raw dumps and every one realises every literal of `C` at
-- its demanded outcome and evaluates `d`; 0 false FAILs. And independently
-- confirmed from a code path that knows nothing about the gate — landing the
-- 625 witnesses in the corpus **halved the engine's own §16f count (848 -> 424)
-- and cut §16e by 37 % (555 -> 352)**.
--
-- NOT-TESTABLE is NEVER read as licence (the X12 lesson): a class whose control
-- did not come back green does not count toward any claim.
--
-- **Consequence for this file:** the residue quoted above must NOT be read as
-- resting on §16f. It does not — the §16b census is quoted with no conjunction
-- pruning, and the MISSING figure moves by 2 when §16e/§16f are removed.
--
-- ---------------------------------------------------------------------------
-- WHAT THE CONFINEMENT LICENCES REST ON (evidence grades)
-- ---------------------------------------------------------------------------
-- All 2 701 confinement pairs were probed for the first time on 2026-09-14/15
-- (this endpoint was previously 100 % unprobed). After a multi-base re-gate:
--
--   restored to licensed   610 pairs / 256 classes, by EXPLICIT verdict
--                          (PASS with >= 1 realising base), never by negation
--   still withdrawn        564 pairs — FAIL 506 | N-T 55 | N-C 2 | pinned 1
--       CORRECTED 2026-09-15 (P40). The earlier line read FAIL 477 | N-T 60
--       | N-C 26: `_p34_withdraw_v2.py` overrides the 1-base verdict only on
--       a PASS, so 29 pairs whose class came back **FAIL at 8 bases** (5 from
--       the N-T re-gate, 24 from the N-C re-gate) were reported under their
--       stale 1-base label. The WITHDRAWAL SET is unchanged (non-PASS is
--       withdrawn either way) — only the reason was wrong, and it was wrong
--       in the direction that OVERSTATES how much of this endpoint's
--       withdrawal rests on silence. 507 of 564 (89.9 %) are decisive
--       refutations; 57 (10.1 %) are unevidenced.
--       Refutation SHAPES of the 507 (P40): DOWNSTREAM 233 (flip changed the
--       partner's outcome) | LEAK 189 (flip moved a shape outside the
--       measured footprint) | REMOVAL 75 (flip left the partner UNEVALUATED)
--       | OTHER 10. The 75 REMOVAL pairs are the X11 shape: DISCIPLINE §16c
--       calls removal-shaped dependence FORECLOSURE's business, not a
--       confinement refutation, so withdrawing on it is conservative but
--       models the demand in the wrong direction (it GROWS demand where the
--       truth would shrink it). Their cost is measured in `_p40_widthprobe2.json`.
--
-- Evidence grades of the 610 restored pairs (`bases_realising/bases_probed`):
--   8/8 realising: 532 |  7/8: 2 |  6/8: 7 |  5/8: 13 |  4/8: 4 |  3/8: 28
--   2/8: 6 |  **1/8 realising: 18**
-- **The 18 pairs resting on a SINGLE realising base are the weakest evidence
-- this endpoint carries and are named here for that reason.**
--
-- **34 NOT-TESTABLE + 2 NOT-COMPARABLE classes (57 PAIRS: 55 N-T + 2 N-C)
-- remain unevidenced after 8 bases. That is SILENCE, NOT LICENCE**, and
-- nothing in this file depends on them being true. Every one of the 57 was
-- probed from 8 bases with ZERO realising: 32 pairs 'dead knob, flip did not
-- flip', 23 'snapshot records a member both ways', 2 NOT-COMPARABLE.
--
-- ---------------------------------------------------------------------------
-- RETIRED / WITHDRAWN CONVENTIONS — do not quote these against older numbers
-- ---------------------------------------------------------------------------
--   §92.4 booking convention  RETIRED. It held §16b `satisfiable` fixed at
--       27 359; the confinement gate changed the assumption set and it moved to
--       1 039 416 (38x). No two §16b figures are comparable across a change in
--       the withdrawn set.
--   §109 W=5 adoption         WITHDRAWN (see the lever table).
--   Every OR-refined/§16f figure in §§82-§103 carries an implicit `@W=3`.
--
-- ---------------------------------------------------------------------------
-- A TOOLING DEFECT RECORDED SO IT IS NOT REPEATED
-- ---------------------------------------------------------------------------
-- The step-6 parallelisation differential is **VOID and did not land.**
-- `coverage_report.py` does `sys.path.insert(0, "/home/dev/project/src")`,
-- which SHADOWS `PYTHONPATH` — so a differential that points `PYTHONPATH` at a
-- patched engine silently measures the UNPATCHED one, and both arms agree for
-- the wrong reason. This is very likely why that patch has failed to land
-- across several attempts. `src/concolic_engine/coverage.py` is unchanged at
-- `9a458961`. A fix that honours `COVERAGE_ENGINE_PATH` is written and unused.
-- ============================================================================
--
-- STANDING OF THIS FILE  (READ THIS BEFORE USING IT)
-- ============================================================================
-- THE ENGINE VERDICT THIS FILE QUOTES, and WHICH PASS IT IS.
--
-- >>> SUPERSEDED 2026-09-15. The verdict in THIS section is from 2026-09-11 and
-- >>> describes a 99 448-dump corpus, a 14 806-profile list and a PROVISIONAL,
-- >>> tree-INCOMPLETE pass. It is retained only as the record of what was true
-- >>> then. **The authoritative verdict for this file is the STATUS block
-- >>> above** (MISSING=706 / BLOCKING=706 over 995 demand sets, 49 568
-- >>> profiles, TREE_COMPLETE=True, foreclosures NOT provisional). Where the
-- >>> two disagree, the STATUS block governs; the numbers below are NOT
-- >>> comparable to it -- different corpus, different list, different pins.
--
-- ** NO PASS COULD BE RUN ON THE CURRENT POPULATION ON 2026-09-11. ** The box
-- was memory-constrained all evening by an editor language server OUTSIDE the
-- experiment's cgroup (3.1 GB at 18:49, 5.1 GB at 19:16, ~6 GB at 19:45); the
-- coordinator lowered the experiment cage twice, ending at MemoryMax=4G /
-- MemoryHigh=3G, and directed that nothing over ~3 G be launched until the
-- editor is closed. A `coverage_report.py` pass on the 32 305-profile pruned
-- list of this corpus is QUEUED behind a `free -g >= 6` gate (`_p13c.sh`) and
-- fires by itself when the box returns; so is the ENGINE SECTION (shims, note
-- check, and the gate on the confined pairs) and the blockaid subsumption.
--
-- The verdict below is therefore from the LAST PASS THAT COMPLETED on this
-- endpoint — 2026-09-11 01:58, `_covB2_p2_20260910.log` / `_cov_p2_pins.json`,
-- on the 14 806-profile p2 list of the then-99 448-dump corpus, with the seven
-- ARGUMENT P pins installed and `SKIP_COMPLETION=1`:
--
--     OVERALL_COMPLETE=False;COMPLETION=n/a
--     COMPLETE=False  NODES=102  MISSING=1414  DEMAND_SETS=567
--     GENUINE=True  TRUNCATED=True  SOLVER_LOST=0  UNEVALUABLE=[]
--     foreclosures=17776 (2359 ignored, PROVISIONAL)  tree_complete=False
--
-- It is quoted because a real verdict from a NAMED population is a fact and a
-- blank is not — but it is NOT a verdict on the population this file is
-- extracted from (183 335 dumps), and it may not be read as one.
--
-- WHAT STANDS BETWEEN THIS ENDPOINT AND `OVERALL_COMPLETE=True`, measured, in
-- four classes, plus the fact that dominates them (_COMPLETION_20260910.md §76):
--
--   (a) REAL DEPENDENCE — 52 of the 73 disqualified decisions are GENUINELY
--       TWO-SIDED on the corpus (19 text-has_mention, 11 findpublic
--       not_found, 7 text-empty, 4 find_by_N not_found, 4 guid, 2
--       CollectionProxy#size, 2 public, 1 Length(SYM_PARAM_id), 1 rendered
--       text, 1 assoc/dispatch), carrying 597 disqualified pairs. NOT
--       LICENSABLE: a confinement declaration over a decision the corpus shows
--       two-sided would be false, and the one available weakening was priced
--       at ZERO (§75: 0 of 73 are OR-shared-only).
--
--   (b) UNDECIDABLE — 21 decisions / 1 160 pairs have no matched context in
--       the corpus. Classified by WHY (`_undec_classify.py`), not by a name
--       heuristic: 5 SELF-COMPARES `(X != X)`, UNSAT, so no context can ever
--       exist (the DecisionAlias artefact, call_interceptor.rb:142-144);
--       7 ARGUMENT P PINNED expressions (4 guid + 3 NullRelation lengths),
--       declared one-sided after two falsifier rounds (3 069 seeds, HIT=0);
--       4 LENGTH GATES, where flipping changes which decisions are evaluated
--       so no EXACT context can exist at any corpus size; and **5 genuinely
--       ADDRESSABLE** text decisions. Only those 5 can be closed by a round,
--       and a 16-seed one-flip round for them is queued (`_p13b.sh`).
--
--   (c) UNEVALUATED-IN-THE-WALK — of 260 324 constructed gate outcomes in the
--       OD0911 round, 170 484 (65.5 %) were seeded and never reached, 89 641
--       realised, 199 contradicted. Cause, by §16b's own "never" test applied
--       to the gate CONJUNCTION: CONJUNCTION FORECLOSURE 491 pairs / 102 851
--       events (82.5 % of the tested class), REACHABLE 109 pairs / 21 822
--       events (17.5 %, a base-selection defect in this batch's constructor),
--       RENDER-ERROR 1 114 (0.65 %, and all of them APPLICATION terminals).
--
--   (d) MOCK-DOMAIN CONTRADICTION — one gate,
--       `..._CollectionProxy_size_1_size == 0`, whose mock domain is hard-coded
--       {0,1,2,4}; contradicted 167 times in the round and realised never. Not
--       impossibility evidence and not closeable by driving: it needs a ruling
--       on whether the mock domain IS the model (declare it) or a limit
--       (widen it — shared boundary, Rule T).
--
--   (e) AND THE FACT THAT DOMINATES ALL FOUR, measured 2026-09-11 on the
--       32 305-profile snapshot with the engine's own reachability split:
--       of the 20 227 633 assignments the confinement-refined demand still
--       asks for, **20 177 698 (99.75 %) lie in leaf groups NO RUN HAS EVER
--       WALKED** — 1 447 454 of 1 451 607 leaf groups have no observed
--       compatible walk. Only **49 935 (0.25 %) are REACHABLE**, i.e. some run
--       has walked those decisions under those gates. The residual is
--       therefore not one problem: ~3.6 hours of driving would address the
--       reachable part at this endpoint's own measured rate, and the other
--       99.75 % is demand that §16b's PAIRWISE foreclosure cannot prune
--       because the combination is foreclosed only by several gates at once.
--       See `_COMPLETION_20260910.md` §76.6 and the three proposals in
--       §76.5(c) — one of which (pruning unmatched prefixes) is NAMED AND
--       REFUSED as unsound on this project's own precedent.
--
-- NONE of the five is closed by extracting this file; they bound what the
-- CHECKER can assert about the corpus, not what the statements below say.
--
-- THE NAMED DEFECT: **DECLARED**, after being DRIVEN AT TWICE and failing both
-- times. Four instances here (`as_api_response_{1,2,3,4}_row_guid != ''`),
-- installed as a separate, counted, reversible tier (ARGUMENT P / P2 in
-- coverage_assumptions.py, `OVERNIGHT_PINS=` printed on the assumptions line,
-- `NO_PINS=1` builds without it).
--   falsifier round TR0910a  `_tree_root.py`, the 8 richest bases per
--                            (target, variant), VERBATIM base seeds + one flip
--                            -> 45 seeds, 43 runs, HIT=0
--   falsifier round TR0910w  `_tree_root_wide.py`, EVERY DISTINCT base seed
--                            dict in the corpus that reaches the site (capped
--                            at 300 distinct contexts per variant)
--                            -> 3 024 seeds, 3 024 runs, HIT=0, with the
--                            expression EVALUATED on the other side 514-1 209
--                            times per instance in the round's own runs.
--   corpus differential, re-measured through the engine's own load path on a
--   stride-8 scan of 96 422 dumps: 0 of 9 432 evaluations taken, in 4 788 runs
--   that evaluate it, and 530 runs exhibiting the other arm — the
--   journey/formatter.rb:40 break, with the `!=` absent entirely. Event sites,
--   byte-identical to the three people_stream instances already declared:
--   ('blank.rb', 126, 'blank?', '==') and
--   ('formatter.rb', 41, 'block in generate', '!=') — those two and no others.
--   FALSIFIER: any run recording the expression taken; at code level, a route
--   default on person_path's :id segment (config/routes.rb has none).
--
-- A SECOND, INDEPENDENT PIN TIER (ARGUMENT P / P1), on a different argument:
-- `SYM_LEN_..._records_{7,8,10}_rows != 0 :: taken`. Those three canonical
-- names denote ActiveRecord::NullRelation call sites — `canonicalize_ordinals`
-- aliases a result by its NOTE and a NullRelation has no SQL, so it is the one
-- `records` call that keeps its bare per-run ordinal — and targets.rb's
-- `rows_mock` hard-codes a NullRelation's length to 0 BEFORE consulting any
-- seed. Measured, not inferred: a rooted seed carrying `len=1` was ACCEPTED
-- into the dump's concolic_seeds and the recorded var was still 0 with the
-- NullRelation note. The hard-coded 0 is FAITHFUL — `.none.to_a` really is []
-- in the real app. Same two falsifier rounds; HIT=0 both times.
-- KNOWN LIMITATION, declared: the SET of such names is not closed, because a
-- future run that puts a NullRelation at a new ordinal mints a new canonical
-- name with the same unreachable side (the DecisionAlias defect,
-- call_interceptor.rb:142-144, reaching the one case with no note to alias on).
-- ADVERSARY ROUND: **NOT RUN.** This drive built this endpoint's first
-- Phase-4 assumption gate and first Phase-5 concrete round; an adversary
-- sub-agent round is the layer after those and was not reached. DECLARED OPEN,
-- not passed.
--
-- ============================================================================
-- EXTRACTION STANDING
-- ============================================================================
-- TODO(drive): the numbers below are from a SAMPLED DRY RUN (DUMP_SAMPLE=8000
-- of 96 357, random, seed 20260901 — never a sorted prefix). REPLACE THEM with
-- a FULL-CORPUS extraction before shipping; a sampled view count is a lower
-- bound on the policy.
--   views                 121   (328 453 raw -> 121 distinct)   [SAMPLED]
--   unparseable notes     0     (E11 RED silent)                [SAMPLED]
--   rotation residue      0     (R1 RED silent — this endpoint has NO
--                                bind-rotated notes at all; it is the control
--                                that showed the people_stream rotation defect
--                                is endpoint-local)
--   placeholders          11 families  TODO(drive): name them and declare or
--                                resolve each, as people_stream's X1 does.
--   flags                 type-mismatched-join 8 224, unscoped 3 998
--   subsumption           NOT ATTEMPTED (SKIP_SUBSUME=1 under the 2026-09-10
--                         memory freeze); 85 of 121 eligible.
--                         TODO(drive): run it and record the tri-state tally
--                         (subsumed / not-subsumed / UNDECIDED, null never
--                         folded into false).
--
-- ============================================================================
-- DECLARED WALLS — arms a real request CAN take that this corpus does not
-- ============================================================================
-- `posts_show/_WALLS.md` now exists (written 2026-09-10 by the completion
-- drive) and carries the full form for each. Summary, with the numbers:
--
--   W1  format.html — CLOSED IN THE CODE 2026-09-10, STILL OPEN FOR ANY
--       CORPUS EXTRACTED BEFORE THAT DATE. History, because both halves
--       matter to a reader of this file:
--         (a) for the whole life of the corpus, ZERO html dumps reached the
--             end of the action. 41 998 of 99 448 (42 %) terminated in
--             `ActionView::Template::Error: uninitialized constant
--             PostsTargets::ConcreteSymbolicString` at targets.rb:666 — a
--             REGRESSION from the 2026-09-09 Rule-T re-sync.
--         (b) the class was restored (§14), after which the arm died one
--             layer deeper at `SymbolicString#scrub`.
--         (c) §46 named the three strings that reach Rails' HTML-escape path
--             (`Processor.process`, `MessageRenderer#title`, `Photo#url` —
--             NOT `Person#name`, which §42 had inferred from the last call
--             event and whose wrap measured as a byte-identical no-op) and
--             carried them in a render-safe carrier. The html arm now
--             COMPLETES: 48-run four-variant smoke, 0 template errors, 0 rig
--             terminals, every terminal an application terminal.
--       CONSEQUENCE FOR THIS FILE, MEASURED ON THE POPULATION THIS FILE WAS
--       ACTUALLY EXTRACTED FROM (2026-09-11, `_html_error_rate.log`, stride-20
--       over all 183 335 dumps, split at `targets.rb`'s own mtime):
--         * the population HOLDS 11 043 POST-REPAIR html dumps
--           (5 842 auth_html + 5 201 anon_html);
--         * in the post-repair sample there are **ZERO rig terminals** in
--           3 668 dumps (503 of them html) and 84.9 % run to the end; every
--           post-repair terminal is an APPLICATION terminal (RecordNotFound
--           10.7 %, Diaspora::NonPublic 4.4 %);
--         * in the pre-repair sample 39.0 % terminated in
--           `ActionView::Template::Error` — 2 144 of 5 501 — and all 2 144 are
--           html.
--       So **the html view's own reads ARE in this file**, contributed by the
--       post-repair half of the corpus. What remains declared is that the
--       PRE-repair html dumps (the majority of the html population by count)
--       contribute only their pre-view statements — which removes nothing,
--       because a truncated walk contributes its own profile and retracts
--       nothing (DISCIPLINE §16b). See `_COMPLETION_20260910.md` §46, §48 and
--       §76.2(c).3.
--   W2  format.mobile is not driven at all — no scenario exists. DECLARED GAP.
--   W3  Diaspora::NotMine is not witnessed (0 of 8 036).
--   W4  DiasporaFederation::Discovery#fetch_and_save — the network-I/O wall
--       (DISCIPLINE §12: it ABORTS THE JVM in libcurl, not an exception). The
--       RETRY arm of Person.find_or_fetch_by_identifier contributes no
--       statement; the FIRST attempt does.
--   W5  the Phase-5 concrete round's html arms stop at an unvendored asset
--       chain (~40 `//= require`s in main.js). An ENVIRONMENT wall: it affects
--       the CHECKS (note_fidelity / H6 will report corpus shapes "never issued
--       concretely"), not this file's content.
--   W6  NullRelation reads are modelled as length 0 and that is FAITHFUL
--       (`.none.to_a` really is []). It issues no SQL; it removes three branch
--       outcomes from the demand (ARGUMENT P1).
--
-- ============================================================================
-- DECLARED OPEN — known gaps in THIS file
-- ============================================================================
--   X1  format.html — CLOSED 2026-09-11. The reads of the html view are IN
--       this file: the extraction population holds 11 043 post-repair html
--       dumps and the post-repair sample has ZERO rig terminals (W1). This
--       entry is kept, not deleted, because a reader of an earlier edition of
--       this file was told the opposite and must be able to see that it
--       changed and on what evidence.
--   X2  format.mobile is undriven (W2).
--   X3  Diaspora::NotMine is unwitnessed (W3).
--   X4  the retry arm behind the discovery wall contributes nothing (W4).
--   X5  the VANILLA skipped_pcs arm is RED — 79 923 `(VAR != VAR(_))` records
--       — and that RED is the SIGNAL, not the gate: the shipped pipeline
--       installs `_experiment/variant_d`'s AssocFoldingTransformer, under
--       which the PATCHED arm is the one that counts. Both exits are printed
--       in `_c7_audits.log`; neither is suppressed. Falsifier: extract without
--       variant_d and all 79 923 records vanish from the fold.
--   X6  ARGUMENT P — seven `OneSideUntracked` pins (4 guid + 3 NullRelation),
--       each driven at twice from every base that reaches the site before
--       being declared, each counted (`OVERNIGHT_PINS=` on the assumptions
--       line), each reversible (`NO_PINS=1`), each with a falsifier. The
--       counterfactual pass measures exactly what they change.
--   X7  B-8 and ConcreteSymbolicString are missing from the SHARED boundary
--       (_COMPLETION_20260910.md §23). Raised, not fixed (Rule T3).
--   X8  no adversary round.
--   X9  BOUNDARY-OVERRIDE TRAP (2026-09-10, §46.8): re-declaring an
--       already-declared target makes `declare_target` read the INTERCEPTOR
--       WRAPPER's parameter names, so a mock that reads an argument by name
--       gets `nil`. Measured on this endpoint: `Anonymous.process` args went
--       from {"message": …} to {"splat_args": …} and the rendered post
--       description became "". Fixed here by owning each declaration in ONE
--       place; RAISED because it is a property of the shared interceptor and
--       is reachable from the recommended Rule-T override pattern.
--   X10 THE `text` MODEL WAS TWO-VALUED until 2026-09-10 (§46.9): the shim
--       offered two non-empty constants, so `text.empty?` was False by
--       construction and the blank-text arm of `post_page_title`
--       (`posts.show.photos_by`, which READS `photos`) had never been driven.
--       W10 makes it seedable and W11 clears the `CollectionProxy#size`
--       wall behind it. Any corpus extracted before that date contains NO
--       run of that arm.
--   X11 `MessageRenderer#title` and `Photo#url` return values the MOCK
--       invents, so no comparison over them is recorded and their real
--       dependencies (the post text; the photo row) are NOT modelled.
--       DECLARED, deliberately not pinned: a pin there would assert a
--       property of this file rather than of the app.
--
--   X12 (this list's own series -- NOT the campaign-wide X12 defect id
--       referenced above) **THIS POLICY IS MISSING STATEMENTS, AND THE
--       MISSING ONES ARE THE RESHARE RELATIONS** (B-4 boundary defect, measured 2026-09-15,
--       _COMPLETION_20260910.md §115). The shared boundary's `collect_binds`
--       calls `#value` on an `Arel::Nodes::Casted`, which arel-9.0.0 does not
--       define, so EVERY STI relation raised and `sql_for`'s `rescue
--       Exception` stored the exception text AS THE NOTE. Full-corpus census
--       over all 237 175 dumps: **8 503 439 captured-exception notes in
--       193 420 dumps (81.55 %), 100 % of them naming the model class
--       `Reshare`**, over exactly 2 call sites
--       (`FinderMethods.find_by` 337 820 events,
--       `CollectionProxy.records` 153 180 events).
--       CONSEQUENCE, stated plainly: this file has **119 statements, ZERO
--       carrying a `type` predicate and ZERO mentioning reshare**, while the
--       app provably issues Reshare relations on both render branches
--       (`post_interaction_presenter.rb:12`, `post_presenter.rb:28`,
--       `ReshareService#find_for_post`, `Post#reshare_for` post.rb:136-139,
--       `Reshare.where(...).first` mobile_helper.rb:9-10, and the
--       `absolute_root` root-walk reshare.rb:70-74). At least four distinct
--       statements are missing (find_by ordinals 3, 6 and 9 plus the
--       `records_2` collection read) and the true number is UNRECOVERABLE
--       FROM THIS CORPUS: the SQL was never rendered, so no re-extraction can
--       produce it. Recovering it needs a RE-DRIVE on a repaired boundary,
--       which is not authorised at the time of writing. A consumer must read
--       this file as SILENT about reshare, not as evidence that reshare reads
--       nothing.
--       Secondary damage: 21 of the 26 statements carrying
--       `-- NOTE: unresolved symbolic binds kept as placeholders:` name a
--       variable whose PRODUCING statement's note is that exception text, so
--       those binds could not be folded back.
--       NOT damage: the DEMAND structure is untouched. A note reaches only
--       §16c confinement (`call_shape` at coverage.py:2323 and nowhere else);
--       the direct differential (`_p42_shapedrop.py`, one universe build per
--       arm) is BYTE-IDENTICAL with and without the two collapsed shapes on
--       every field, and 0 of the 117 LEAK-shaped gate-refutation classes
--       names an exception shape.
--
-- ============================================================================
-- WHAT THIS EXTRACTION MEASURED, 2026-09-15 (the shipping run)
-- ============================================================================
--   corpus          236 997 dumps, ALL parsed (n_runs_loaded == n_dumps)
--   raw queries     11 921 156  ->  124 distinct  ->  **119 shipped**
--   subsumption     RAN (one JVM, 6 solver threads, pairs NOT sharded)
--                   kept 119 | dropped 5 | **UNDECIDED/null 0**
--                   `subsume_errors` empty, `errors` empty.
--                   null = TIMEOUT = KEPT is the rule; no pair needed it.
--   scan            parallel, validated serial-vs-parallel on a random
--                   6 000-dump sample: SQL BYTE-IDENTICAL, 410s -> 111s (3.7x)
--
-- SKIPPED PATH CONDITIONS — DECLARED RESIDUE, 9 715 860 over 59 shapes.
-- These are decisions the runs MADE that do not become SQL predicates. The
-- largest families are result-level, not row-level:
--     1 599 740  (len(..._records_N_rows) != N)
--     1 077 945  (..._find_by_N_not_found == True)
--       743 665  (len(..._CollectionProxy_records_N_rows) != N)
--       698 662  (assoc_status_message_text_has_mention == True)
--       511 595  (assoc_profile_nsfw == True)
--       471 482  (..._as_api_response_N_row_guid == '')
-- They are the QUANTIFIED form of the METHOD caveat at the foot of this file:
-- the app fetches rows and then filters them in RUBY, so a consumer treating
-- this file as access control is OVER-PERMISSIVE by exactly this much. This is
-- a property of the app, not a defect of the extraction — but it is large, and
-- it is stated here rather than left to be inferred.
--
-- FLAGGED STATEMENTS carried into the file with their NOTE lines:
--     unscoped              84 457 occurrences
--     type-mismatched-join 150 735 occurrences
-- ============================================================================
--
-- ============================================================================
-- METHOD (applies to every extracted policy)
-- ============================================================================
-- Extracted policies are STATEMENT-level; the reference is REVEAL-level. A
-- consumer treating this file as access control is OVER-PERMISSIVE wherever
-- the app over-fetches and filters in Ruby.
-- ============================================================================

--
-- Extracted from 20000 dumps, 20000 runs loaded, 993680 raw queries,
--   150 distinct (query, conditions) pairs, 124 distinct statements,
--   4 subsumed, 120 views.  subsume_ran=None
--   PC predicates: 29 rendered, 23 kept — a predicate the corpus
--   shows this query running BOTH WITH AND WITHOUT does not constrain it and is dropped.
--   fold: src/queries_from_runs (no patches)

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `people` AS `people0` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `share_visibilities` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `people`.* FROM `people`, `participations`, `posts`, `share_visibilities`, `people` AS `people0` WHERE `people`.`id` = `participations`.`author_id` AND `participations`.`target_id` = `posts`.`id` AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people0`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `people0`.`owner_id` = _MY_UID;

SELECT 1 AS one FROM `participations`, `people`, `posts`, `share_visibilities` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `comments`, `posts`, `people` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `comments`, `posts`, `share_visibilities` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `people`, `posts`, `share_visibilities` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `mentions`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `participations`.* FROM `participations`, `people`, `posts`, `share_visibilities` WHERE `participations`.`target_id` = `posts`.`id` AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `people`.* FROM `people`, `comments`, `posts`, `people` AS `people0` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people`, `comments`, `posts`, `share_visibilities` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `people`.* FROM `people`, `likes`, `posts`, `people` AS `people0` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people`, `likes`, `posts`, `share_visibilities` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE;

SELECT `people`.* FROM `people`, `mentions`, `posts`, `people` AS `people0` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people`, `mentions`, `posts`, `share_visibilities` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `people`.* FROM `people`, `participations`, `posts`, `people` AS `people0` WHERE `people`.`id` = `participations`.`author_id` AND `participations`.`target_id` = `posts`.`id` AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people0`.`id` AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people`, `participations`, `posts`, `people` AS `people0` WHERE `people`.`id` = `participations`.`author_id` AND `participations`.`target_id` = `posts`.`id` AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people0`.`id` AND `posts`.`public` = TRUE AND `people0`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people`, `photos`, `posts`, `people` AS `people0` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people`, `photos`, `posts`, `share_visibilities` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = `posts`.`guid` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `poll_answers`.* FROM `poll_answers`, `polls`, `posts`, `people` WHERE `poll_answers`.`poll_id` = `polls`.`id` AND `polls`.`status_message_id` = `posts`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `poll_answers`.* FROM `poll_answers`, `polls`, `posts`, `share_visibilities` WHERE `poll_answers`.`poll_id` = `polls`.`id` AND `polls`.`status_message_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

-- NOTE: flag aggregate-as-rows
SELECT `poll_answers`.`id`, `poll_answers`.`vote_count` FROM `poll_answers`, `polls`, `posts`, `people` WHERE `poll_answers`.`poll_id` = `polls`.`id` AND `polls`.`status_message_id` = `posts`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

-- NOTE: flag aggregate-as-rows
SELECT `poll_answers`.`id`, `poll_answers`.`vote_count` FROM `poll_answers`, `polls`, `posts`, `share_visibilities` WHERE `poll_answers`.`poll_id` = `polls`.`id` AND `polls`.`status_message_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `poll_participations`.* FROM `poll_participations`, `polls`, `posts`, `people` WHERE `poll_participations`.`poll_id` = `polls`.`id` AND `polls`.`status_message_id` = `posts`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `poll_participations`.* FROM `poll_participations`, `polls`, `posts`, `share_visibilities` WHERE `poll_participations`.`poll_id` = `polls`.`id` AND `polls`.`status_message_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

-- NOTE: flag type-mismatched-join
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

-- NOTE: flag type-mismatched-join
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `share_visibilities` AS `share_visibilities0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `share_visibilities0`.`shareable_id` = `posts0`.`id` AND `share_visibilities0`.`shareable_type` = 'Post' AND `share_visibilities0`.`user_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `photos`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = `posts0`.`guid` AND `posts0`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `photos`, `posts` AS `posts0`, `share_visibilities` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = `posts0`.`guid` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `polls`, `posts` AS `posts0`, `people` WHERE `posts`.`id` = `polls`.`status_message_id` AND `polls`.`status_message_id` = `posts0`.`id` AND `posts0`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `polls`, `posts` AS `posts0`, `share_visibilities` WHERE `posts`.`id` = `polls`.`status_message_id` AND `polls`.`status_message_id` = `posts0`.`id` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

-- NOTE: flag type-mismatched-join
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `people`.`owner_id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `posts`, `people` AS `people0` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `posts`.`author_id` AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `posts`, `share_visibilities` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `posts`.`author_id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `posts`, `people` WHERE `taggings`.`taggable_id` = `posts`.`id` AND `taggings`.`taggable_type` = 'Post' AND `taggings`.`context` = 'tags' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `posts`, `share_visibilities` WHERE `taggings`.`taggable_id` = `posts`.`id` AND `taggings`.`taggable_type` = 'Post' AND `taggings`.`context` = 'tags' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT 1 AS one FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id`;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT 1 AS one FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT 1 AS one FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`public` = TRUE;

SELECT `comments`.* FROM `comments`, `posts`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `comments`.* FROM `comments`, `posts`, `share_visibilities` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `likes`.* FROM `likes`, `posts`, `people` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `likes`.* FROM `likes`, `posts`, `share_visibilities` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `locations`.* FROM `locations`, `posts`, `people` WHERE `locations`.`status_message_id` = `posts`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `locations`.* FROM `locations`, `posts`, `share_visibilities` WHERE `locations`.`status_message_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `comments`, `posts` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE;

SELECT `mentions`.* FROM `mentions`, `people`, `posts` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `mentions`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`public` = TRUE;

SELECT `mentions`.* FROM `mentions`, `posts`, `people` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `posts`, `share_visibilities` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `notifications`.* FROM `notifications`, `posts`, `people` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`target_type` = 'Post' AND `notifications`.`target_id` = `posts`.`id` AND `notifications`.`unread` = TRUE AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `notifications`.* FROM `notifications`, `posts`, `share_visibilities` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`target_type` = 'Post' AND `notifications`.`target_id` = `posts`.`id` AND `notifications`.`unread` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `o_embed_caches`.* FROM `o_embed_caches`, `posts`, `people` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `o_embed_caches`.* FROM `o_embed_caches`, `posts`, `share_visibilities` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `open_graph_caches`.* FROM `open_graph_caches`, `posts`, `people` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `open_graph_caches`.* FROM `open_graph_caches`, `posts`, `share_visibilities` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`target_id` = `posts`.`id` AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id`;

SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`target_id` = `posts`.`id` AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`public` = TRUE;

SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `people`.* FROM `people`, `likes`, `posts` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT `people`.* FROM `people`, `likes`, `posts` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `people`.* FROM `people`, `mentions`, `posts` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT `people`.* FROM `people`, `mentions`, `posts` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `people`.* FROM `people`, `photos`, `posts` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT `people`.* FROM `people`, `photos`, `posts` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`public` = TRUE;

SELECT `people`.* FROM `people`, `posts`, `people` AS `people0` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people`, `posts`, `share_visibilities` WHERE `people`.`id` = `posts`.`author_id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `photos`.* FROM `photos`, `posts`, `people` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `photos`.* FROM `photos`, `posts`, `share_visibilities` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

-- NOTE: flag aggregate-as-rows
SELECT `photos`.`id`, `posts`.`id`, `people`.`id` FROM `photos`, `posts`, `people` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

-- NOTE: flag aggregate-as-rows
SELECT `photos`.`id`, `posts`.`id`, `share_visibilities`.`id` FROM `photos`, `posts`, `share_visibilities` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `poll_answers`.* FROM `poll_answers`, `polls`, `posts` WHERE `poll_answers`.`poll_id` = `polls`.`id` AND `polls`.`status_message_id` = `posts`.`id` AND `posts`.`public` = TRUE;

-- NOTE: flag aggregate-as-rows
SELECT `poll_answers`.`id`, `poll_answers`.`vote_count` FROM `poll_answers`, `polls`, `posts` WHERE `poll_answers`.`poll_id` = `polls`.`id` AND `polls`.`status_message_id` = `posts`.`id` AND `posts`.`public` = TRUE;

SELECT `poll_participations`.* FROM `poll_participations`, `polls`, `posts` WHERE `poll_participations`.`poll_id` = `polls`.`id` AND `polls`.`status_message_id` = `posts`.`id` AND `posts`.`public` = TRUE;

SELECT `polls`.* FROM `polls`, `posts`, `people` WHERE `polls`.`status_message_id` = `posts`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `polls`.* FROM `polls`, `posts`, `share_visibilities` WHERE `polls`.`status_message_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

-- NOTE: flag type-mismatched-join
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `posts`.* FROM `posts`, `photos`, `posts` AS `posts0` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = `posts0`.`guid` AND `posts0`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT `posts`.* FROM `posts`, `photos`, `posts` AS `posts0` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = `posts0`.`guid` AND `posts0`.`public` = TRUE;

SELECT `posts`.* FROM `posts`, `polls`, `posts` AS `posts0` WHERE `posts`.`id` = `polls`.`status_message_id` AND `polls`.`status_message_id` = `posts0`.`id` AND `posts0`.`public` = TRUE;

-- NOTE: flag type-mismatched-join
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `posts0`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

-- NOTE: flag type-mismatched-join
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `posts0`.`public` = TRUE AND `people`.`owner_id` = _MY_UID;

-- NOTE: flag type-mismatched-join
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `posts0`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

-- NOTE: flag type-mismatched-join
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `posts` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `posts`.`author_id` AND `posts`.`public` = TRUE;

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `posts` WHERE `taggings`.`taggable_id` = `posts`.`id` AND `taggings`.`taggable_type` = 'Post' AND `taggings`.`context` = 'tags' AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_id
SELECT 1 AS one FROM `participations`, `people` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_id AND `people`.`owner_id` = _MY_UID;

SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `likes`.* FROM `likes`, `posts` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT `likes`.* FROM `likes`, `posts` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `locations`.* FROM `locations`, `posts` WHERE `locations`.`status_message_id` = `posts`.`id` AND `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT `locations`.* FROM `locations`, `posts` WHERE `locations`.`status_message_id` = `posts`.`id` AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `mentions`.* FROM `mentions`, `posts` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT `mentions`.* FROM `mentions`, `posts` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`public` = TRUE;

SELECT `notifications`.* FROM `notifications`, `posts` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`target_type` = 'Post' AND `notifications`.`target_id` = `posts`.`id` AND `notifications`.`unread` = TRUE AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `o_embed_caches`.* FROM `o_embed_caches`, `posts` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT `o_embed_caches`.* FROM `o_embed_caches`, `posts` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `open_graph_caches`.* FROM `open_graph_caches`, `posts` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT `open_graph_caches`.* FROM `open_graph_caches`, `posts` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_id
SELECT `people`.* FROM `people`, `likes` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_id AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `people`.* FROM `people`, `posts` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT `people`.* FROM `people`, `posts` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `photos`.* FROM `photos`, `posts` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT `photos`.* FROM `photos`, `posts` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`public` = TRUE;

-- NOTE: flag aggregate-as-rows
SELECT `photos`.`id`, `posts`.`id` FROM `photos`, `posts` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `polls`.* FROM `polls`, `posts` WHERE `polls`.`status_message_id` = `posts`.`id` AND `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

SELECT `polls`.* FROM `polls`, `posts` WHERE `polls`.`status_message_id` = `posts`.`id` AND `posts`.`public` = TRUE;

SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' WHERE `share_visibilities`.`user_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `people` WHERE `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

-- NOTE: flag type-mismatched-join
SELECT `posts`.* FROM `posts`, `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `posts0`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_id
SELECT `likes`.* FROM `likes` WHERE `likes`.`target_id` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_id AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Calculations_ids_1_ids
SELECT `notifications`.* FROM `notifications` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`target_type` = 'Mention' AND `notifications`.`target_id` = _SYM_RESULT_ActiveRecord__Calculations_ids_1_ids AND `notifications`.`unread` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_find_by_3_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _SYM_RESULT_ActiveRecord__FinderMethods_find_by_3_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_find_by_6_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _SYM_RESULT_ActiveRecord__FinderMethods_find_by_6_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_find_by_9_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _SYM_RESULT_ActiveRecord__FinderMethods_find_by_9_author_id;

SELECT `posts`.* FROM `posts`;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActsAsApi__Collection_as_api_response_2_row_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActsAsApi__Collection_as_api_response_2_row_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActsAsApi__Collection_as_api_response_3_row_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActsAsApi__Collection_as_api_response_3_row_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActsAsApi__Collection_as_api_response_4_row_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActsAsApi__Collection_as_api_response_4_row_id;
