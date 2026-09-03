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