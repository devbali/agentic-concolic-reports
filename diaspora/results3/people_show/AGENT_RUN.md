# AGENT_RUN — people_show flip_seed extension (results3)

## Status: FLIP HANDLERS FIXED + 10/10 UNIT-TESTED; CAMPAIGN RE-RUN (1184 runs);
## DOT-FAMILY BRANCHES NOW OBSERVED BOTH SIDES; ARTIFACT COMBOS PRUNED;
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
   | anon_mobile | 3000 (capped)   | 1152           | NO — frontier 12 deep      |
   Total 1184 runs, 25110 path conditions, 241.5s.

3. **Branch-level coverage: dramatic improvement** (baseline `_pre_flip_dumps/`
   = 458 runs vs now = 1184 runs, same expr set):

   | expr (first_1 handle)              | baseline     | now          |
   |------------------------------------|--------------|--------------|
   | Contains('.', H[0,1])              | **0T** / 72F | **144T**/72F |
   | Contains('.', H[0,2])              | (absent)     | **144T**/72F |
   | Contains('.', H[0,Length-0])       | **0T** / 72F | **144T**/72F |
   | IndexOf == 1                       | 219T         | 363T         |
   | IndexOf == 2                       | (absent)     | **363T**     |
   | IndexOf == 2 (via_user)            | (absent)     | 3T           |
   | Blank shapes (SubString(H,0,k)'')   | 0T/72F       | 0T/72F (unchanged) |

   The three dot-family T-sides went from **0 observed → 144 observed** —
   exactly what the corrected seeds were built to do. Also fixed k=2 arm was
   previously entirely absent.

## Coverage (current assumptions, 254 Independence + 11 OneSide = 265)

| metric         | baseline (458 runs, old assns) | pre-flip corpus + NEW assns | now (1184 runs, NEW assns) |
|----------------|-------------------------------|-----------------------------|----------------------------|
| tree nodes     | 31                            | 31                          | 37                         |
| path conds     | 9326                          | 9326                        | 25110                      |
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

Verified by corpus search (1184 runs), none prunable without masking real
app branches (forbidden by source discipline):

1. **via_user (branch B) × mobile-stream (x8)**: `Not(Contains('@', via_user))`
   + full stream. The mobile scenario ALWAYS takes branch A (1168×A-T vs 16×
   A-F across ALL scenarios; the 14 via_user runs are anon_handle/json, ZERO
   stream clauses). The seed structure couples format+branch — single-flip DSE
   cannot produce a branch-B mobile run.
2. **diaspora_id?==True + public_details==True + full stream (x8)**: profile
   presenter (PD/BY) and mobile stream never co-occur in any run (max 0 stream
   clauses in PD-T runs). Multi-render conjunction beyond single-flip reach.
3. **Guard × complement stream exprs (x16)**: NF1/CA1/NF2/CA2 with
   `comments_count==1` / `author_guid!=''` (complement forms not in the
   guard-foreclose product). REMOVED from assumptions — adding them split the
   graph and inflated the count worse (192). Genuine in the sense that no run
   has a guard-T with ANY stream expr (verified), but per the checker they
   remain demanded.
4. **DOTLEN/blank + guid + NOTC1 + stream conjunctions (x32)**: e.g.
   DOTLEN-T ∧ guid=='' ∧ NOTC1 ∧ full-stream. DOTLEN-T+guid-empty runs exist
   (41), but none reach the full stream (max 4/9 clauses). Multi-variable
   seed conjunctions the single-var flip_seed design cannot compose.
5. **Blank-check T-sides (all shapes)**: need H=='' which diverges upstream
   (empty-H seed → NOTC arm → path-signature dedup). Unflippable by design.

## Blocker summary (why missing stays ≥ 64)

- The remaining combos need EITHER multi-variable seed composition (out of
  scope for single-var flip_seed) OR structural harness changes (decouple
  format from branch; drain more frontier) — both beyond this run's mandate.
- Declaring them independent/OneSide would mask real app branches (blank?,
  include?, stream render decisions) — explicitly forbidden by source
  discipline.

## Files touched this run

- run_dse.rb (flip_seed handlers #2/#2b/#2c/#3 + regex fix) — tracked, diff
  +109 lines vs HEAD.
- coverage_assumptions.py — untracked (never committed); now 265 assumptions
  (was 114): added DOT1/2/3/DOTLEN, BLANK1/2/LEN, GUID1E/1N, stream family
  (REC1_ROWS/TOA_ROWS/NSFW/AUTHGUID/PROVMOB/ROWPUB/ROWCC0/REC2_15/REC3_POS/
  ROWGUID), section 2d dot-exclusivity pairs, 2a guid/stream complement pairs,
  branch_A/branch_B/handle/stream list extensions.
- AGENT_RUN.md (this file).
- coverage_summary.json + dump_*.json (1184 runs) replaced.

## Next steps (if continuing)

1. Multi-variable seed composition (seed guid='' AND handle='.a.b' AND
   stream-qualifying username in ONE run) — requires flip_seed to accept a
   base seed dict, or a second flip pass. Would clear blockers #4.
2. Decouple format from branch in the harness (allow mobile format on branch
   B) — clears #1. Harness change, ask first (source discipline).