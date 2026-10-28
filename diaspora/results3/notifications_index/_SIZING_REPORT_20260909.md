# notifications_index — diverse seeding + job sizing (2026-09-09 evening)

Every number below is measured on the artefacts named; comparisons of
`missing[]` names against dumps go through the engine's load path
(`canonicalize_ordinals -> fix_len_names -> Run.from_dict -> apply_len_bounds`).
Dump counts are `find -maxdepth 1 -name 'dump_*.json' | wc -l`.

## 1. The v1 diverse seeder is falsified (not merely slow)

`_diverse_seeds.py` (v1) only randomises the `len(...)` keys ALREADY PRESENT in
a template dump's `concolic_seeds`. Over its 6 000 seeds: 3 394 carry ZERO
length keys, 1 870 one, 652 two. The dominant demanded variable —
`SYM_LEN_..._records_notifications_8513a914_rows` (`len(..._records_1_rows)`
in every dump; conjunct of 1 854 of the 1 830 witnesses, demanded `> 1`) — is
left at its default of 1 in >90% of v1 seeds.

| run | dumps | `records_notifications > 1` outcomes | witnesses hit (all conjuncts, one run) |
|---|---|---|---|
| v1 `_DIV1` (old domain {0,1}/{0,1,3}) | 4 000 | **False 3 993 / True 0** | **0 / 1 826** |
| v2 pilot `_PV202547` (html_plain) | 300 | True 165 / False 134 | 24 / 1 826 |
| v2 drive `_DV2028` (4 of 7 variants before stop) | 16 569 | balanced (~50/50) | see §3 |

Corpus census (51 362 dumps, `_diverse_seeds2.py` header): that variable was
`> 1` in only 2 071 runs (4%) before v2. Seeded lengths hold: seed->observed
`2->3` 14 059, `2->4` 2 177, `0->0` 6 250, `1->1` 1 847; the runtime clamps
every value > 1 to "many" (targets.rb `len_i = 3 if len_i > 1`, actors
`an = 4 if an > 1`), so {0,1,2,4} is {0, 1, many, many}.

v2 = `_diverse_seeds2.py`: assigns EVERY length key in the runtime universe
(22 keys; 27 raw `len(...)` names minus the render/pluck probes), context
inherited from a real dump, type/STI re-rolled with p=1/2.

## 2. Coordinator's three measurements — re-verified on coverage_summary.json

1. `concrete_values` per entry: 47 x162, 48 x941, 49 x186, 50 x410, 51 x12,
   52 x20, 53 x26, 54 x32, 55 x20, 56 x11, 57 x10 (min 47, max 57). Confirmed.
2. Width: 1 x4 (untracked), 4 x24, 5 x373, 6 x733, 7 x429, 8 x134, 9 x10,
   10 x16, 11 x23, 12 x19, 13 x10, 14 x9, 15 x8, 16 x4, 17 x6, 18 x15, 19 x4,
   20 x5, 21 x4; mean 6.69. Confirmed. Each entry is its own expression set:
   1 830 entries = 1 830 cliques (1 826 blocking) at MMC=1.
3. Under naive per-conjunct independence, 954 random runs would hit ~1 726
   DISTINCT witnesses (29 133 hit-events); measured 94. Confirmed (~18x /
   ~300x below). Co-evaluation is the binding constraint: only 999/1 826
   witnesses had their whole clique evaluated by any of those 954 runs.

## 3. The real distance to `missing == 0` (`_size_job.py` -> `_size_job.json`)

Faithful to coverage.py step 6: clique = the entry's expression set;
satisfiable outcome assignments enumerated with Z3 under the engine's merged
declarations + `apply_len_bounds` bounds (the batch declares no
SymbolicConstraintAssumption), blocking-clause loop, cap 4 096/clique;
observed = every dump's outcome family for each clique it evaluated ENTIRELY
(an expr seen both ways in one run covers both outcomes, as the checker's
blocking clause does). Corpus at measurement: 68 231 dumps.

| | |
|---|---|
| blocking cliques | 1 826 |
| satisfiable assignments, summed | **491 040** (lower bound: 65 cliques of width >= 12 hit the 4 096 cap) |
| observed (covered) | **27 611** — 10 284 from the 51 362 pre-v2 runs, +17 327 from the 16 869 v2 runs |
| **remaining** | **463 429** |
| cliques closed now | 8 / 1 826 |
| cliques never co-evaluated by ANY run (0 whole-clique evaluations in 68 231) | **375** |
| MMC=1 witnesses now covered | 420 / 1 826 (38 "not in enumeration" are all in capped cliques) |

Per width (cliques / satisfiable / covered / remaining): w5 373/11 616/3 745/
7 871; w6 733/43 440/9 972/33 468; w7 429/48 656/9 257/39 399; w8 134/25 984/
2 828/23 156; w10-21 133 cliques / 357 576 / 1 544 / 356 032.

**Rates.** v2 random: 17 327 new assignments in 16 869 runs (~1.03/run, and
coupon-collector makes it fall). Targeted D rounds + base: 10 284 in 51 362
runs (~0.2/run; and the D-round loop pins ONE assignment per clique per
round, <= 1 826/round). Against 463 429 remaining: random needs >= 4.5e5 runs
(realistically millions as returns diminish); targeted needs >= 254 rounds,
each preceded by a coverage pass of the whole corpus.

**Verdict.** Under the engine's combination semantics at this clique width
(mean 6.7, tail to 21; 133 cliques of width >= 10 carry 73% of the demand)
neither seeding strategy can reach `missing == 0` in bounded time. The
distance is a property of the demand (2^k per clique, k = clique width, with
no independence declared inside the cliques), not of the seeder. 375 cliques
have never been co-evaluated by any of 68 231 runs; their demand cannot be met
by seeding at all unless some run can evaluate all their expressions together.

## 4. Coverage-pass cost on the 68 231-dump corpus
(see §4 addendum below when the pass lands; first attempt was OOM-killed at
21:00:39 at 2.5 GB peak because `app.slice` carries a collective
`MemoryMax=5G` — relaunched in its own slice `ndxcov.slice`, MemoryMax=10G.)

## 5. What was run tonight (labels are unique per invocation)
- `_PV202547` html_plain x300 (v2 pilot); `_DV2028{htmp,htmt,jsop,xmlp}` = 16 569
  dumps (v2 drive, stopped on coordinator instruction after 4 of 7 variants,
  JRubys SIGTERMed, all 16 569 dumps validated as JSON, 0 partial removed).
- `_demand_root.py` over all 1 826 witnesses (round-15 build, 20:01): 3 417
  rooted seeds across variants; 0 combinations without a corpus base, 0
  demanded lengths skipped for an unissued statement. NOT driven — §3 says
  the loop cannot converge, so the sweep was not started.
- Not modified: src/, the app, assumptions. No independence declared.
