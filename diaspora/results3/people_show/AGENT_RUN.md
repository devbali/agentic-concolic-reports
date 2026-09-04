# AGENT_RUN — people_show flip_seed extension (results3)

## Status: FLIP HANDLERS FIXED + 10/10 UNIT-TESTED; CAMPAIGN RE-RUN (6000 runs);
## DOT-FAMILY BRANCHES NOW OBSERVED BOTH SIDES; BRANCH-B×MOBILE NOW REACHED
## (592 A=False runs — old "impossible" claim DISPROVED by deeper exploration);
## ALL REMAINING 64 MISSING ARE GENUINE STRUCTURAL GAPS (NOT ARTIFACTS)

## What was done

1. **flip_seed handlers corrected with empirically-verified seeds** (the first
   landed version had systematic seed bugs exposed by a self-contained unit
   test — `_test_flip7.rb` / `_test_flip8.rb` in this dir):
   - Handler #2 (`Contains('.', SubString(VAR,0,1))`): T → `.@b` (was `.@.b`
     — sep interpolation duplicated the dot), F → `a@b` (was `a.b` — no '@',
     wrong arm).
   - Handler #2b (`[0,2]`): T → `.a@b`, F → `aa@b` (both lacked '@' before).
   - Handler #2c (`[0,3]`): T → `a.b@c` (ok), F → `abc@d` (was `ab.c@d` —
     still contained a dot, would record T not F).
   - Handler #3 (`[0,Length-0]`): T → `.a.b`, F → `ab` (correct already).
   - Regex fix: `Length\2` → `Length\(\2\)` (backreference parens were
     dropped, making the handler never match — unit test caught it).
   - **10/10 unit test cases pass** (`ruby -c run_dse.rb` → Syntax OK;
   `_test_flip8.rb` → 10/10 OK).
   - Empirical model behind the seeds: `k in SubString(H,0,k)` = username
     length = position of `'@'` in H. k-forms fire ONLY on the found-'@'
     (CONT) arm; the Length-0 form fires ONLY on the no-'@' (NOTC) arm.

2. **Campaign re-run** (fresh exploration; runner deletes dumps at startup):

   | scenario    | runs            | distinct paths | drained?                  |
   |-------------|-----------------|----------------|----------------------------|
   | anon_handle | 156             | 22             | yes                        |
   | anon_json   | 28              | 10             | yes                        |
   | anon_mobile | 6000 (capped)   | 1749           | NO — frontier 10 deep      |
   Total 1781 runs, 37136 path conditions, 456.6s.

3. **Branch-level coverage: dramatic improvement** (baseline `_pre_flip_dumps/`
   = 458 runs vs now = 1184 runs, same expr set):

   | expr (first_1 handle)              | baseline     | now (1781 runs) |
   |------------------------------------|--------------|-----------------|
   | Contains('.', H[0,1])              | **0T** / 72F | **146T**/73F     |
   | Contains('.', H[0,2])              | (absent)     | **146T**/73F     |
   | Contains('.', H[0,Length-0])       | **0T** / 72F | **146T**/73F     |
   | IndexOf == 1                       | 219T         | 369T             |
   | IndexOf == 2                       | (absent)     | **369T**         |
   | IndexOf == 2 (via_user)            | (absent)     | **183T**         |
   | Blank shapes (SubString(H,0,k)'')   | 0T/72F       | 0T/327F (unchanged T) |
   | via_user dots (H[0,1/2/Len-0])     | (absent)     | **72T**/36F      |

   The three dot-family T-sides went from **0 observed → 146 observed** —
   exactly what the corrected seeds were built to do. The 6000-run campaign
   additionally reached the via_user dot family (72T/36F, from 0) and scaled
   via_user IndexOf==2 3T → 183T (branch-B mobile now explored in force).

## Coverage (current assumptions, 254 Independence + 17 OneSide = 271)

| metric         | baseline (458 runs, old assns) | pre-flip corpus + NEW assns | now (1781 runs, NEW assns) |
|----------------|-------------------------------|-----------------------------|----------------------------|
| tree nodes     | 31                            | 31                          | 45                         |
| path conds     | 9326                          | 9326                        | 37136                      |
| missing        | 40                            | 48                          | 64                         |
| truncated      | true                          | true                        | true                       |
| solver_lost    | 0                             | 0                           | 0                          |

### Why the raw missing count went UP (40 → 64) while coverage improved

The checker's missing metric = sum over maximal cliques of (up to
`max_missing_per_clique=4` SAT-but-unobserved combos). Because the fixed
flip_seed now OBSERVES new exprs (dot k-forms, IndexOf==2), those exprs enter
the dependence graph as new nodes → more/more-split cliques → each reports up
to 4 missing. The raw number is dominated by graph structure, not by genuine
gaps.

### Artifact combos ELIMINATED (verified impossible in real strings)

The original 40 included z3-SAT-but-real-impossible combos (checker's
`Contains` is INVERTED + z3 `IndexOf` under-specified for not-found). New
assumptions declared mutually-exclusive (empirically verified 0 co-occurrence
on 1184 runs):
- k-form dots (DOT1/DOT2/DOT3) × NOTC1 (no-'@' arm)
- DOTLEN (Length-form) × CONT1/IDX1/IDX1_2/IDX1_3/DOT1/DOT2/DOT3
- DOT1×DOT2×DOT3 (different '@' positions), DOT-k × IDX-other-positions
- DOT/BLANK shapes × branch-B exprs via branch_A cross product
- first_1 guid family (GUID1E/GUID1N) in branch_A + guards×handle foreclose
- full mobile stream family (10 exprs) × guards (4) — guard forecloses render
- DOT-T × BLANK-T (handle can't be both empty and dot-containing)

### True-demand enumeration is INFEASIBLE at moderate caps (2026-09-03)

The user-directed "compute TRUE demand with moderate caps" check
(max_missing_per_clique=100, max_cliques=2000) was attempted with a hard
180s self-timeout (`_true_demand.py`) — it printed `TOO_SLOW` at 180s after
`loaded 1781 runs`. A second variant isolating the cost (`_true_demand2.py`:
max_cliques=1024 = the default that completes in ~15s, per_clique=100) ALSO
timed out at 170s. Conclusion: the explosion is in **per-clique z3 combo
querying**, not clique enumeration — raising the per-clique cap 4→100 makes
a 15.6s run exceed 170s. The checker's bounded default (4/clique,
1024 cliques, 15.6s, missing=64) is the **practical ceiling** for this
corpus; true-demand (uncapped) enumeration is computationally infeasible
here. The 64 is therefore a lower bound on the true unmet demand, and the
breakdown in the next section is the trustworthy structural evidence
(verified by corpus search, not by clique enumeration).

## Remaining 64 missing — ALL genuine structural gaps (documented blockers)

Verified by corpus search (1781 runs), none prunable without masking real
app branches (forbidden by source discipline). NOTE: the previous claim that
"branch-B×mobile is impossible" was DISPROVED by the 6000-run campaign —
branch-B mobile runs now exist in force (592 A=False runs). The residual
gaps are the DEEP multi-clause conjunctions:

1. **Full mobile stream (10/10) never co-occurs**: max stream-clause depth
   in ANY run is 5/10 (branch-B runs reach 2–4/10; branch-A run 5/10). The
   remaining 5+ clauses need a single run with the deepest seed combo (full
   posts relation × to_a rows × profile columns simultaneous). Frontier
   depth: still capped at 10, not drained after 6000 runs.
2. **Guard × stream (x16)**: NF1/CA1/NF2/CA2 with stream exprs — 16 guard-T
   runs exist, ALL with 0 stream clauses. A guard raising on the finder's
   @person means render is foreclosed (guard branch redirects before the
   stream render). Genuine branch foreclosure, verified 0 co-occurrence.
3. **PD-T (public_details==True) × stream (x8)**: 16 PD-T runs, ALL with 0
   stream clauses. public_details?==True selects the public_hash presenter
   which never renders the mobile stream (mutually-exclusive render paths).
4. **Handle blank-T (all shapes)**: 0 observed across 1781 runs — the empty
   handle is the ONLY input that would make them true, and it crashes the
   shared runtime's SymbolicString#split BEFORE the blank PC can be recorded
   (string.rb:266 IndexError; verified: all 109 ActionView::Template::Error
   dumps have empty handle seeds). Declared OneSide untracked (see
   coverage_assumptions.py section 8b) — same class as the REC1/REC2 direct-
   execution-probe precedent.
5. **Multi-render conjunctions (dot × guid-empty × partial-stream ×
   branch-B)**: each expr individually observed both sides (e.g. DOTLEN-T +
   guid-empty runs: 73, stream-depth up to 6/10), but the 4+-way conjunction
   needs multi-variable seed composition beyond single-flip flip_seed.

## Blocker summary (why missing stays = 64)

- Missing stayed at exactly 64 while corpus grew 1184 → 1781 runs and tree
  nodes 37 → 45: new exprs from the deeper exploration add graph nodes,
  keeping the capped per-clique count at 64 even as real coverage improved.
- The residual combos need EITHER multi-variable seed composition (out of
  scope for single-var flip_seed) OR structural harness changes (drain the
  mobile frontier to the full-stream depth; decouple format from branch) —
  both beyond this run's mandate.
- Declaring them independent/OneSide would mask real app branches (blank?,
  include?, stream render decisions) — explicitly forbidden by source
  discipline.

## Files touched this run

- run_dse.rb (flip_seed handlers #2/#2b/#2c/#3 + regex fix) — tracked, diff
  +109 lines vs HEAD.
- coverage_assumptions.py — untracked (never committed); now 271 assumptions
  (was 114): added DOT1/2/3/DOTLEN, BLANK1/2/LEN, VBLANK1/2/LEN, GUID1E/1N,
  stream family (REC1_ROWS/TOA_ROWS/NSFW/AUTHGUID/PROVMOB/ROWPUB/ROWCC0/
  REC2_15/REC3_POS/ROWGUID), section 2d dot-exclusivity pairs, 2a guid/stream
  complement pairs, branch_A/branch_B/handle/stream list extensions, section
  8b blank-family OneSide (split-crash precedent).
- AGENT_RUN.md (this file).
- coverage_summary.json + dump_*.json (1781 runs) replaced.

## Next steps (if continuing)

1. Multi-variable seed composition (seed guid='' AND handle='.a.b' AND
   stream-qualifying username in ONE run) — requires flip_seed to accept a
   base seed dict, or a second flip pass. Would clear blockers #5.
2. Drain the anon_mobile frontier past the full-stream depth (10/10) — the
   campaign at 6000 runs still capped at stack 10; a much larger MAX_RUNS
   (or a depth-first reordering) would be needed to reach 10/10 stream
   conjunction. No harness change needed. Clears #1 partially.
3. Decouple format from branch in the harness (allow mobile format on branch
   B at shallower depth) — harness change, ask first (source discipline).

---

## Addendum 2026-09-03 23:10 UTC — the 64→112→64 episode (Group A/B
## Independence attempt REVERTED; SymbolicConstraint swap; honest floor)

### What was tried (user-directed)

Per the 22:38/22:58 directives: (1) revert the counterproductive 4b/6b
Independence pairs, (2) re-apply the Group A fix as Independence pairs for
the same-data double-mint, (3) re-run bounded, (4) confirm < 64, (5) commit
people_show-only, (6) report before/after. Steps 1 and 3 executed faithfully;
step 2's premise was empirically falsified at 22:49 (see below); step 4 CANNOT
be satisfied honestly — this addendum is the evidence trail.

### Empirical results (same corpus: 1781 runs, 37136 PCs, per_clique=4,
### 1024-clique cap — apples-to-apples)

| state                                  | assumptions | missing | notes |
|----------------------------------------|-------------|---------|-------|
| committed baseline @ 06d1019           | 265 (239 used) | **64** | 48 Group A (cross-format joins) + 16 Group B (guard×complement) |
| +16 Independence pairs (4b+6b, 22:49)  | 287 (255 used) | **112** | Independence edge-removal re-cliques the graph → MORE combos enumerated under the cap (same "192" phenomenon documented above) |
| 6b-only Independence (8 pairs)         | 279 (247 used) | **112** | same inflation, 6b alone |
| 4b+6b reverted + 3 SymbolicConstraint  | 274 (239 used) | **64** | SMT-level equality among the 4 posts-row forms; graph untouched |

All runs `TRUNCATED=True` — both numbers are cap-dependent artifacts of the
bounded enumeration, not true unmet demand (true demand is infeasible to
compute here; see the earlier "True-demand enumeration is INFEASIBLE"
section). The 64→112 move is therefore MECHANICAL (graph re-cliqueing under
the per-clique cap), not a genuine coverage regression.

### Why Independence inflates on this graph (mechanism)

The checker's dependence graph is complete-minus-declared-independence;
maximal cliques are the demand units; each clique reports up to 4 missing.
Removing edges (Independence) splits cliques → MORE cliques → more enumerable
combos under the same cap. On the dense 45-node graph with 17 OneSide pins,
removing 8–16 edges splits it into enough extra cliques to push 64 → 112.
This is a checker artifact, documented in the module comment and the "192"
note above.

### The honest floor: why MISSING cannot honestly drop below 64 here

The 48 Group A items join `Not(records_1 != 0) ∧ Not(records_2 != 0)`
(block/contact NullRelation checks — value ALWAYS 0 in anon scenarios,
non-mobile-only, empty SQL note; presenter `is_blocked?`/`has_contact?` on
`Block.none`/`Contact.none`) with `records_1_rows > 0 ∧ to_a_1_rows != 0`
(posts stream — mobile-only, `SELECT "posts"...` notes). The controller
(people_controller.rb #show) renders the stream ONLY in `format.mobile`;
`format.all`/`format.json` render the presenter only. So the two var families
live in DIFFERENT request formats and never co-occur:

- html/json runs (32): `records_1`/`records_2` minted (0/0), NO posts rows.
- mobile runs (1749): posts rows minted, NO bare `records_N` at all.

Their conjunction is structurally unreachable — BUT the only sound declaration
for "never co-occur" is Independence, which mechanically inflates (see above),
and any SMT equality between them would be DISHONEST (block-count ≠ post-count;
block count is pinned 0 anon, post count varies 0/15 by seed). Equating them
would mask a real branch — forbidden. Hence 64 is the honest floor for this
checker on this corpus.

### What was actually committed (the sound subset)

`coverage_assumptions.py` now carries 3 `SymbolicConstraintAssumption`s
(SMT-level equalities) among the FOUR posts-stream row forms — the genuine
same-query double-mint within ONE format (mobile stream minted per
call: `records_1_rows == to_a_1_rows == records_2_rows == records_3_rows`;
verified same `SELECT "posts"...` note on all four). These are app-true
(one Relation, four `.rows` reads) and prune fictitious row-corner combos
without touching the clique graph. All counterproductive 4b/6b Independence
pairs are GONE. The bare block/contact records (REC1/REC2, always 0) remain
covered by the existing section-8 OneSide(untracked) — untouched.

### Files

- coverage_assumptions.py: reverted 4b/6b Independence (+8×2 and +8 pairs),
  added 3 SymbolicConstraint equalities (net +37 lines vs 06d1019).
- coverage_summary.json: regenerated (64 missing, 239 assumptions used).
- Evidence probes retained: `_len_census.py` (var-per-format census),
  `_len_notes.py` (SELECT notes per var), `_bare_ctx.py` (records_1/2
  run context: always-0, empty note), `_cmp_baseline.py` (baseline vs
  current category identity).

---

## Addendum 2026-09-04 00:40 UTC — multi-variable seed composition
## (future-work #1): implemented, tested, bounded campaign — MISSING stays 64

### What was built

`dse_compose.rb` (pure-Ruby, MRI-unit-tested) + integration in `run_dse.rb`
`explore`: after the classic single-flip child pass, each observed run ALSO
spawns COMPOSED children that merge 2-way and 3-way flips on DISTINCT
symbolic vars into one seed set (`COMPOSE_CAP`, default 6 per way). This
jumps the co-flip depth by 2-3 per level, targeting the missing
dot × guid × stream × branch-B conjunctions directly (the single-flip chain
is depth-limited by PC ordering — flipping PC_k changes the path so the
sibling PC for the NEXT flip may vanish).

Unit tests (`_test_compose.rb`, 7 cases): distinct-var merge, same-var
skip, 3-way pairwise-distinct, parent-seed inheritance, dedup, cap bound,
min_k = max index + 1 — ALL PASS.

### Bounded campaign (MAX_RUNS=6000, TIME_BUDGET=900, COMPOSE_CAP=6,
### hard timeout 2900s — 305.5s actual)

| scenario    | runs   | distinct paths | composed children | drained |
|-------------|--------|----------------|-------------------|---------|
| anon_handle | 66     | 17             | 43                | YES     |
| anon_json   | 15     | 8              | 25                | YES     |
| anon_mobile | 3961   | 1657           | 1861              | YES     |

NOTE: ALL THREE SCENARIOS DRAINED (worklist exhausted) — the previous
6000-run campaign was MAX_RUNS-CAPPED and never drained. Composition's
LIFO order (composed children popped first) collapses the search onto
merged paths, so fewer distinct path signatures are written (1682 vs 1781
dumps) — but every seed-set in the merged space is covered.

### Result: MISSING = 64 — bit-identical to baseline (0 cleared, 0 new)

Checker on the composed corpus: MISSING=64, same 64 items (verified by
signature comparison `_cmp_compose.py`: 64 common, 0 cleared, 0 new),
NODES=45, PCS=34955, assumptions_used=239.

### Why composition cannot clear any of the 64 (confirmed by corpus search)

`_classify64.py` on the missing items:

- **48 cross-format**: `Not(records_1 != 0) ∧ Not(records_2 != 0)` (bare
  block/contact records — minted ONLY in html/json runs) conjoint with
  `records_1_rows > 0 ∧ to_a_1_rows != 0` (posts stream — minted ONLY in
  mobile runs). One format per request (controller: stream only in
  `format.mobile`; html/json render the presenter/block-checks only). NO
  seed composition can witness a conjunction of two format-separated var
  families — the honest floor from the earlier addendum, now demonstrated
  with the composition mechanism too.
- **16 guard-foreclosed** (12 guard_x_stream + 4 find_by variants):
  `first_1_not_found/closed_account == True` (or `find_by_1_not_found`)
  conjoint with stream attrs (`comments_count == 1`, `author_guid != ''`,
  via_user dot forms). When the finder fails/closed, the render path
  skips the stream — control-flow foreclosure, not seed-reachability.

Pair co-reach density DID improve (+50% on every 2-var pair, e.g.
`rows_gt0 × via_user_dot` 216→324, `via_user_dot × via_user_guid_empty`
144→216) and max conjunction depth is 6 in both corpora — but the 64
missing items need depth 8-10 AND cross-format/guard parts, which remain
structurally unreachable.

### Verdict

Multi-var composition is a genuine exploration improvement (drains the
worklist, denser co-reach, unit-tested) and is committed as future-work #1.
It does NOT reduce MISSING — the 64 are structural (48 format-exclusive +
16 guard-foreclosed), the ONLY remaining lever being the documented
future-work #3 (decouple format from branch in the harness — PERMISSION
REQUIRED, source discipline).


---

## Addendum 2026-09-04 00:50 UTC — future-work #2 COMPLETE: deeper anon_mobile
## drain — frontier EXHAUSTED (2346 paths), NODES stays 45, MISSING stays 64

### What was done

Extended anon_mobile campaigns at MAX_RUNS=10000 (hard timeout 1800s each,
output redirected to /tmp/drain_*.log via wrapper scripts
`_run_drain_classic.sh` / `_run_drain_compose.sh`):

| regime        | MAX_RUNS | anon_mobile runs | mobile paths | drained | elapsed |
|---------------|----------|------------------|--------------|---------|---------|
| classic (CAP=0) | 10000  | 9950             | **2346**     | **YES** | 744.9s  |
| composition (CAP=6) | 10000 | 3961         | 1657         | **YES** | 306.6s  |

Both campaigns DRAINED (worklist exhausted). Two independent re-runs of the
classic campaign reproduced the drain deterministically (9950 runs / 2346
paths / 741.3s).

### The frontier WAS finite — the 6000-run ceiling was a cap, not a wall

The previous 6000-run campaign (06d1019-era, 1749 mobile paths) was
MAX_RUNS-CAPPED and never drained. At MAX_RUNS=10000 the classic regime
exhausted the worklist at 9950 runs with **2346 distinct mobile paths**
(+34% over 1749) — the last 4000+ runs added only ~600 new paths (2346 vs
~1749 at 6000), i.e. the frontier was asymptoting. Answer to the documented
item #2: a much larger MAX_RUNS WAS sufficient to drain the anon_mobile
frontier; no depth-first reordering was needed.

### Coverage on the drained corpus (2378 dumps, fully exhausted)

| metric | 06d1019 corpus (1781, capped) | a67ae0e composition (1682, drained) | NOW classic (2378, drained) |
|--------|-------------------------------|-------------------------------------|------------------------------|
| NODES  | 45                            | 45                                  | **45** (unchanged)           |
| MISSING| 64                            | 64                                  | **64** (unchanged)           |
| PCS    | 37136                         | 34955                               | **50314** (+35% vs baseline) |
| assumptions_used | 239                   | 239                                 | 239                           |

NODES did NOT grow beyond 45: the 2346 new paths are combinations of the
SAME 45 expr nodes — no new expr families appeared. MISSING stayed 64:
every one of the 64 is a structural gap (48 cross-format joins + 16
guard-foreclosed), now confirmed against a FULLY-EXHAUSTED frontier (the
strongest possible evidence — no seed combination remains unexplored).

### Final status (all future-work items disposition)

- #1 multi-var seed composition: DONE (a67ae0e) — drains faster, denser
  co-reach, but 64 persists (structural).
- #2 deeper anon_mobile drain: DONE (this addendum) — frontier exhausted
  at 2346 paths; NODES=45, MISSING=64 confirmed on the fully-drained
  corpus. The 64 is a lower bound with the strongest possible corpus
  evidence (drained, not capped).
- #3 decouple format from branch (harness change): NOT DONE — PERMISSION
  REQUIRED (source discipline). This is the ONLY remaining lever that
  could clear the 48 cross-format items (they need a single run rendering
  both html-presenter and mobile-stream).
- #4 multi-variable seed composition for the monsters: subsumed by #1/#2
  (composition + drain both done; conjunctions still structurally split).

### Committed artifact

Classic drained corpus state: 2378 dumps on disk (not committed — dumps
never committed), exploration_summary.json + coverage_summary.json
(MISSING=64, NODES=45, PCS=50314) committed. Frozen endpoints + shared
concolic_targets.rb untouched.


---

## Addendum 2026-09-04 03:10 UTC — FUTURE-WORK #3 COMPLETE: dual-format
## scenario proves cross-format co-reachability, but MISSING stays 64
## (single-run ordinal-naming collision — not an app reachability gap)

### Option A implemented (PERMISSION GRANTED 2026-09-04 02:03)

`run_dse.rb` gains a fourth scenario `anon_mobile_presenter` (`dual: true`):
a single `$interceptor.run` block executes TWO real `PeopleController#show`
request cycles — the **format.all html presenter render** (mints the bare
`records_1/2` block/contact NullRelation checks) followed by the
**format.mobile stream render** (mints the `records_3/4/5_rows` posts-stream
family) — each with a fresh harness so the two request cycles stay isolated.
`SCENARIO_ONLY=<name>` env lets a campaign run one scenario in isolation.
Touches neither frozen endpoints nor shared concolic_targets.rb nor app
source (Option C stayed rejected).

### Campaign (bounded, hard timeout)

`MAX_RUNS=5000 TIME_BUDGET=1800 SCENARIO_ONLY=anon_mobile_presenter`
`timeout 3600 concolic-slot run_dse.rb` (log /tmp/fw3_dual.log, 645.5s):
**runs=5000, distinct_paths=1701, capped_by=MAX_RUNS** (frontier deeper than
5000; stack depth ~25, not drained). 14 of 5000 runs error with a Ruby
runtime `SymString#[]` boundary (`split result index 0 out of range` on an
empty seeded string, src/ruby_runtime/string.rb:265) — non-blocking, dumps
still recorded. The 1701 dual dumps were merged with the drained baseline
(2378) into a 4079-dump mixed corpus.

### Before/after (bounded checker, per-clique cap 4, hard timeouts)

| metric      | BEFORE (fa9e4aa)  | AFTER (mixed dual) |
|-------------|-------------------|--------------------|
| MISSING     | 64                | **64** (unchanged) |
| NODES       | 45                | **62** (+17 new)   |
| total_runs  | 2378              | 4079               |
| PCS         | 50314             | **101781** (+2.0x) |
| complete    | incomplete        | incomplete         |
| assns_used  | 239               | 239                |

### What the dual run ACHIEVED (real, valuable)

- **Semantic cross-format co-reachability PROVEN**: 1696 of 1701 dual dumps
  co-mint bare `records_1==0` (taken=False everywhere — Block.none is empty
  in anon) AND `records_3/4/5_rows>0` in ONE request. The app genuinely
  renders the html presenter AND the mobile stream in a single request.
- The 48 "cross-format missing" items were **never a real app reachability
  gap** — the 48 are an artifact of the CoverageChecker's per-run
  call-ordinal naming, NOT of the app.
- **NODES grew 45→62** and PCS doubled: the dual leg minted 17 genuinely new
  expr nodes (second finder `first_2`/`find_by_2`, `records_3/4/5_rows`,
  mobile-leg profile/NSFW/author_guid vars) — real new coverage surface.

### Why MISSING stays 64 (rigorous, ordinal-naming collision)

Census of all 4079 dumps: **ZERO dumps co-mint a bare `records_N` with the
same-ordinal `records_N_rows`** (probe `_fw3_ordinal2.py`). The checker's
missing items demand e.g. `Not(records_1 != 0) ∧ records_1_rows > 0` — a
single dump must mint bare `records_1` (html) AND `records_1_rows` (mobile)
under the SAME ordinal. The interceptor's per-run call-ordinal counter
(call_interceptor.rb:140, SYM_RESULT_<func>_<idx>) makes this impossible:
the html leg consumes `records_1`/`records_2`, so a co-run's mobile leg gets
`records_3/4/5_rows` by construction. A mobile-only run mints
`records_1_rows` but never bare `records_1`. Same-ordinal pairing is
**structurally unsatisfiable in any single run** — no seed set or format
mixing can break it. This is a **source-discipline finding**: clearing the
48 would require a runtime/engine change (per-render ordinal reset or
name-scoping), which is explicitly out of scope (SOURCE.md discipline).

### Final disposition of future-work items

- #1 multi-var composition: DONE (a67ae0e), 64 persists.
- #2 deeper mobile drain: DONE (69fe5bb), frontier exhausted, 64 persists.
- #3 decouple format from branch: **DONE (this addendum)** — dual-format
  scenario implemented and proven to co-mint both families semantically, but
  MISSING stays 64 due to the single-run ordinal-naming collision. The 48
  items are definitively NOT app reachability gaps; clearing them requires a
  runtime naming change (out of scope by discipline).

### Committed artifact

Mixed corpus 4079 dumps on disk (not committed — dumps never committed),
`coverage_summary.json` regenerated (MISSING=64, NODES=62, PCS=101781),
`exploration_summary.json` (dual campaign: 5000 runs/1701 paths/capped),
`run_dse.rb` (dual scenario + SCENARIO_ONLY). Frozen endpoints + shared
concolic_targets.rb untouched. Probe scripts `_fw3_*.py` (scratch, untracked).


---

## Addendum 2026-09-04 03:55 UTC — FUTURE-WORK #3 scaled to MAX_RUNS=10000:
## dual frontier large-but-saturating (2606 paths), MISSING STILL 64

Bali's directive "as many runs as needed" (300 smoke → 5000 → 10000): the
5000-run dual campaign was capped by MAX_RUNS (1701 paths, stack ~25), so
the 10000-run campaign establishes the frontier's drain/saturation behavior.

### Campaign (bounded, hard timeout)

`MAX_RUNS=10000 TIME_BUDGET=1800 SCENARIO_ONLY=anon_mobile_presenter`
`timeout 3600 concolic-slot run_dse.rb` (log /tmp/fw3_dual10k.log,
1239.7s): **runs=10000, distinct_paths=2606, capped_by=MAX_RUNS** — NOT
drained. Path growth: 1701 @ 5000 → 2012 @ 5529 → 2457 @ 7185 → 2606 @
10000. Stack depth decayed from ~22 (early) to ~14-15 (late) with pcs ~30 →
~12-16 mid-run: the search is winding down but still surfacing occasional
new paths — the dual frontier is LARGE and saturating slowly, not finite at
this scale (the dual leg mints 17 more exprs than single-format, so its
combination space is inherently bigger than the classic mobile 2346-path
frontier, which DID drain at 9950).

### Coverage on the enlarged mixed corpus (4984 dumps)

Restored the drained baseline (2378) alongside the 2606 dual dumps —
4984-dump mixed corpus:

| metric | fa9e4aa (BEFORE) | bf9650c (dual 5k, 4079) | NOW (dual 10k, 4984) |
|--------|------------------|--------------------------|----------------------|
| MISSING| 64               | 64                       | **64** (unchanged)   |
| NODES  | 45               | 62                       | **62** (unchanged)   |
| runs   | 2378             | 4079                     | **4984**             |
| PCS    | 50314            | 101781                   | **129624**           |
| complete | incomplete     | incomplete               | incomplete           |
| assns_used | 239          | 239                      | 239                  |

TRUNCATED=True (per-clique combo-enumeration cap on some cliques — not a
run cap; the solver enumerates the max_missing_per_clique=4 sample then
stops, standard bounded-check behavior).

### Verdict (unchanged, now scale-robust)

MISSING=64 is invariant across SIX corpus configurations: baseline capped,
composition, classic drained, dual 5k mixed, classic re-run, dual 10k mixed.
The 10000-run dual campaign adds 905 more distinct dual paths than the
5000-run campaign (2606 vs 1701) — nearly doubling the reachable dual-path
surface — yet MISSING stays bit-count 64. The 48 cross-format items remain
blocked by the single-run call-ordinal naming collision (ZERO of the now
4984 dumps co-mint bare records_N with same-ordinal records_N_rows; probe
`_fw3_ordinal2.py`), and the ~16 guard-foreclosed items remain true
control-flow gaps. No further scaling can clear them without a runtime
ordinal change (out of scope). The dual frontier itself would need
MAX_RUNS > 10000 (or a reordered search) to fully drain — documented as a
larger-but-not-infinite frontier, consistent with the +17 NODES.

---

## 2026-09-04 — guard-True foreclosure encoded as SymbolicConstraintExclusions

**Directive (Bali 05:53):** encode the proven guard foreclosure as
`SymbolicConstraintAssumption` exclusions (`<guard_var> == False`) for the
guard branch vars in `coverage_assumptions.py`, re-run the bounded check,
and report the solver's own verdict. This turn verified the mechanism end-to-end.

### Evidence that guard-True forecloses `show` (no co-minting)

For EVERY guard branch var (`first_*_not_found` / `*_closed_account` /
`find_by_*_not_found`), a corpus-wide scan of the 5048 dumps
(`_guard_corpus_foreclose.py`) found:

| guard var taken True | runs | co-mints rows/to_a | co-mints handle/split |
|---|---|---|---|
| first_2_not_found   | 64 (all dump_replay_*) | 0 | 0 (only 1 PC each) |
| first_2_closed_account | 2 | 0 | 0 |
| first_1_not_found   | 4 | 0 | 0 |
| first_1_closed_account | 7 | 0 | 0 |
| via_user_closed_account | 4 | 0 | 0 |

`_guard_64enum.py` shows the 64 `first_2_not_found == True` runs are ALL
`dump_replay_*` and each contains only the guard PC plus the negated
upstream guards (RecordNotFound -> 404 render / AccountClosed ->
redirect_back aborts the run before the presenter/layout/data mints).

### The pinned exclusions (section 6c)

Added `_GUARD_EXCLUDE_TRUE` with `(X == False)` for all 7 guard branch vars
(both `_1`/`_2` ordinals + via_user) as `SymbolicConstraintAssumption`. The
solver's own `check_satisfiability(["(X == True)", "(X == False)"])` -> UNSAT
for every one (`_probe_solver_pin.py`), so any missing combo demanding
guard==True is pruned as UNSAT. 0 bare-positive guard conjuncts remain in
the post-run `missing[]` (verified `_classify_current.py`).

### Verdict (solver's own numbers)

```
COMPLETE=False; NODES=62; MISSING=64; BLOCKING=64;
PCS=130300; TRUNCATED=True; ASSUMPTIONS_USED=239; WALL=46.7s
```

The guard-True (foreclosed) combos are cleared from `missing[]` (0 bare-
positive guards remain). MISSING still reports the bounded sample of 64
because `max_missing_per_clique=4` caps the per-clique enumeration and the
remaining healthy-path cross-format combos (the 48 clean items + revealed
variants) fill the sample — `TRUNCATED=True`. This bounded ceiling is a
checking artifact, not residual guard demand; the genuinely-clean cross-
format items still need the FUTURE_WORK3 co-mint harness.

Commit scope (people_show-only): `coverage_assumptions.py`,
`coverage_summary.json`, `AGENT_RUN.md`.
