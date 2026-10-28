# DecisionAlias implementation report — notifications_index (2026-09-08)

Corpus frozen at 14 369 dumps. Baseline before this work (ordinal-named
results): nodes 167, missing 4 726 (= 945 cliques × MMC 5 + 1 untracked),
945 maximal cliques, **0** evaluated whole by any run.

## 0. Two passes ran; only the second is a combination-coverage number

**Uncapped pass (the one to report against) — completed 2026-09-09 00:03 as
user unit `notif-cov.service` (`Result=success`; the kill did not reach it):**

    NODES=396  MISSING=15 549  BLOCKING=15 545  PCS=934 932  runs=14 369
    TRUNCATED=True  SOLVER_LOST=0  coverage phase 9 451 s  peak RSS 970 MB
    MISSING_CAP=6 000 hit: the JSON holds 6 000 entries over 1 200 cliques

15 545 / 5 = **3 109 = every maximal clique** hit the per-clique cap, so —
exactly as at baseline (4 725 = 945 × 5) — this number is "cliques × MMC"
and measures the clique count, not the gap. The numbers that measure the
gap are in §1: 2 226 of 3 109 cliques are now evaluated whole by some run
(0 of 945 before) and 11 966 joint assignments are observed (0 before); at
baseline no clique could ever lose its cap, now every clique can. The
demand seeder on this summary builds 4 870 rooted seeds (0 without a base;
74 canonical lengths skipped because the base never issued that statement —
the fix that replaces the 164 inert seeds).

What the failing side is made of: all 1 200 sampled failing cliques contain
a `> 1` length expression and 1 100 of them contain
`services > 1` — i.e. the residual demand is the W-E product (a root
family's many-arm × every decision it co-occurs with). That is precisely
the territory of the root-family many-arm UntrackedPath tier awaiting the
owner's adjudication (not implemented, per instruction).

**Capped pass (`cov_capped.log`, 134 s): `NODES=396 MISSING=88 BLOCKING=84
TRUNCATED=True` — not a combination number.**
That pass ran with the engine's default `CoverageChecker(max_cliques=1024)`.
The canonical universe has **3 109** maximal cliques (measured with the
batch's real `build()`, `scratchpad/sim_canon.log`); `coverage.py`
`_maximal_cliques` returns None above the cap and `check_coverage` then
falls back to `cliques = [[e] for e in active]` — **one singleton clique per
expression**, i.e. a per-expression both-sides check, signalled only by
`truncated=True`. Every one of the 84 blocking entries is a single conjunct
(conjunct-size histogram `{1: 84}`), which is that fallback's signature.
The old universe had 945 cliques and never hit the cap, so the 4 726 IS a
combination number and the 88 is not; they are not comparable.

The two passes were not identical: `coverage_report.py` passes
`max_cliques=int(os.environ.get("MAX_CLIQUES", "16384"))` (patched after the
capped run), so the second enumerated the real 3 109 cliques with one
blocking clause per co-evaluating run each — 9 451 s. Cost control for the
loop: `MAX_MISSING_PER_CLIQUE=1` proves the passing side identically (a
covered clique is one UNSAT regardless of the cap) and cuts the failing
side 5×; run it in a memory-capped unit outside `app.slice` (the first
attempt was OOM-collateral of the 2 GB `java` subsume job under the 5 GB
`app.slice` cap, rc=137 at 808 MB RSS; the completed run used
`systemd-run --user --slice=concolic-cov.slice -p MemoryMax=3000M`).
`_c7_drive2.sh` inherits the new default and the standing
`coverage_summary.json` (00:03) is this pass's.

## 1. Numbers vs. simulation

| quantity | baseline | predicted (sim, family-only names) | measured (real P0 names) |
|---|---|---|---|
| exprs (nodes) | 167 | 220 | **396** |
| assumptions | 10 993 | — | 72 946 (71 051 used) |
| maximal cliques | 945 | 319 | **3 109** |
| cliques evaluated whole by ≥1 run | 0 | 306 | **2 226** (883 not) |
| observed joint assignments | 0 | 3 303 | 11 966 |
| missing (= cliques × MMC 5, both) | 4 726 | — | **15 549** (every clique capped, as at baseline) |
| coverage phase | ~20 min | — | 134 s (capped, per-expr) / 9 451 s (uncapped, completed) |

Where the measurement departs from the simulation, and why:

- The simulation keyed identity by table only. The implementation keys by
  the *statement with binds* (the rule you set), and the paginated list
  `Relation#to_ary` resolves to **four** statements (plain, `type = ?`,
  `unread = true`, both), so every row-chain decision under it splits
  four ways: 396 exprs, not 220. Photos are 4 names (3 owner chains + one
  run with a `1=0` scope), mentions 3, aspect_memberships 2,
  aspects/services/tags/unread 1 each — 17 identities from 35 (name,
  ordinal) pairs (`_canonical_legend.json`). A first version cascaded the
  upstream hash into nested binds (photos 8 names, mentions 12); the
  shipped key references an upstream result by its chain identity
  `<stem>_<table>` (the runtime's own one-fact rule: rendered SQL with bind
  NAMES carries no upstream variant), which restored the census counts.
- More exprs → more cliques (3 109 vs 319) and 20 024 variant-exclusivity
  declarations; the realizable fraction is what matters: 2 226 of 3 109
  cliques are evaluated whole by some run, against 0 of 945.
- The 88 is explained in §0; the simulation never predicted it.

## 2. The gate: per-alias verdicts and the validation runs

Derived test (`assumption_checker.py::_test_alias`, reachable from
`assumption_manifest.json` via `"canonicalize": "coverage_report:canonicalize_ordinals"`,
one verdict row per canonical name): a name is one decision iff
(i) every (ordinal, statement) mapped to it has ONE statement key (binds
kept, whatever key mode the declaration chose), and (ii) from a snapshot of
each member at the same base length, setting the length to every other
observed value adds and removes the same statement multisets (binds kept,
modulo the alias). PASS only on that evidence; FAIL on a differing key or
effect; NOT-TESTABLE when a member has no snapshot at the base length;
NOT-COMPARABLE when a flip produced no run or changed what the member's
ordinal resolved to. A single-member name is PASS "by construction" and says
so — it makes no cross-ordinal claim.

**Validation, deliberately unsound alias** (`key="shape"`, binds wildcarded;
`scratchpad/alias_bad_results.json`, 58 probes replayed, 3 launches):

| canonical (shape) | verdict | detail |
|---|---|---|
| CollectionProxy_records_photos_92ada145 | **FAIL** | (i) 3 distinct statements under one name; (ii) intervention effects DIFFER across the 3 members — e.g. length 0 removes `SingularAssociation.find_target SELECT "people".* … = $$(…)` bound to a different owner chain per member |
| Relation_records_mentions_966a71e1 | **FAIL** | (i) 3 distinct statements; (ii) effects identical |
| CollectionProxy_records_aspect_memberships_d642406a | **FAIL** | (i) 2 distinct statements; (ii) effects identical |
| aspects / services / tags (shape) | PASS | 8 / 8 / 5 members, identical effects |
| 6 single-member names | PASS | by construction |

**Sound alias** (`key="statement"`, what P0 declares;
`scratchpad/alias_sound_results.json`, 42 probes, 2 launches, all matched):

| canonical | members | verdict | evidence |
|---|---|---|---|
| CollectionProxy_records_aspects_c9638cc0 | ordinals 1,2,3,4,5,6,7,10 | PASS | (i) one statement; (ii) 8 members × flips [0,3] from length 1: identical added/removed multisets |
| CollectionProxy_records_services_3c4f9abb | 2,3,4,5,6,7,8,11 | PASS | same, 8 members |
| CollectionProxy_records_tags_5fc4a296 | 5,6,7,8,11 | PASS | same, 5 members |
| CollectionProxy_records_photos_{2a9cc6c3,98c65ca3,ab85baa9,4bc79851} | ordinal 2 each | PASS | single member (by construction) |
| CollectionProxy_records_aspect_memberships_{ae3fcf22,6f13edc1} | 1 / 2 | PASS | single member |
| Relation_records_mentions_{857a1e6b,d25799cb,fbb27183} | 2 | PASS | single member |
| Relation_records_notifications_8513a914 | 1 | PASS | single member |
| Relation_to_ary_notifications_{c7e6a7ca,cf379872,3aa8587a,10254800} | 1 | PASS | single member |

17 declared, 17 PASS, 0 FAIL / NOT-TESTABLE / NOT-COMPARABLE. Nothing is
declared that came back FAIL or NOT-TESTABLE.

Honest limit of part (ii): when two different statements have
bind-identical downstream effects modulo the alias (mentions' three
container chains, aspect_memberships' two contacts), only part (i) can fail
them. Part (i) is a corpus differential against the recorded statements,
not an instance test, and it is what caught them.

## 3. What changed, file by file

Batch (`reports/diaspora/results3/notifications_index/`):
- `coverage_report.py` — P0: `alias_map()`, `canonicalize_ordinals()`
  (rewrites `symbolic_vars`, PC exprs, result names, notes,
  `concrete_values`, `symbolic_results` in place; seeds untouched), applied
  before `fix_len_names`; writes `_canonical_legend.json`; passes
  `max_cliques` from `MAX_CLIQUES` (default 16384).
- `coverage_assumptions.py` — declares `ALIASES` (the
  `DecisionAliasAssumption`, so it is in the report and probed by the
  gate); `_tier_unobservable_pairs` review fix (§4); `_tier_c7a_by_family`
  (§6); `IndexedAssumptionSet` (O(1) expr-pair lookup, same semantics,
  2 000-pair self-check against the base implementation each build —
  needed because `are_independent` is a linear scan per pair and the
  canonical universe is 73k declarations × 76k pairs).
- `_demand_root.py` — indexes dumps after canonicalization, maps a
  demanded canonical length back to the base dump's ordinal, and SKIPS a
  length whose statement the base never issued (the 164 inert
  `records_11` seeds). Dry run on the standing summary: 188 rooted seed
  dicts, 0 without a base, 0 skipped.
- `assumption_manifest.json` — `"canonicalize": "coverage_report:canonicalize_ordinals"`.

src (all additive; inert when no alias is declared; 99 tests pass, the
one failure `test_untracked_by_expression_at_a_shared_source` pre-exists
the task — it fails identically with my hook neutralised and is caused by
the earlier uncommitted combination-semantics rewrite):
- `concolic_engine/assumptions.py` — `DecisionAliasAssumption` (fifth
  kind, `result_pattern`, `key ∈ {statement, shape}`), `statement_key`,
  `canonical_result_name`, `is_statement_note`, `_alias_core` /
  `alias_map_for` / `alias_keys_for`, `renamer`, `rename_with`;
  `AssumptionSet.aliases/alias_map/apply_aliases`.
- `concolic_engine/coverage.py` — **two lines, mine, at 19:41**: the
  constructor now does `self.runs = self.assumptions.apply_aliases(runs)`
  (identical list object when nothing is declared), and
  `assumptions_to_dict` also serialises `result_pattern`/`key` (without
  it the gate's alias test has no pattern to expand). Your reading that
  the engine needed no hook is not correct: the *renaming* on this batch
  is done by P0 (notes are dropped at load so `apply_aliases` finds nothing
  to rename), but the declaration must be carried to the summary for the
  gate, and a batch that keeps notes gets the engine-native path.
- `end_to_end_completion_checker/assumption/assumption_checker.py` —
  canonicalize hook (`_load_dump_uncached`), alias member index, bind-keeping
  trace, `_runtime_key` (canonical seed keys → the snapshot's ordinal keys),
  `_reading_changed` → NOT-COMPARABLE in the Independence and Untracked
  branches, `_test_alias`, per-canonical expansion in `run_declared`,
  NOT-COMPARABLE in the RESULT line.
- `test_assumptions.py` — `test_decision_alias_rekeys_by_statement_and_is_inert_when_absent`.

NOT changed: `ruby_runtime/call_interceptor.rb` (its ` M` in `git status`
predates this task — it was in the first `git diff --stat` I took), the
application, `targets.rb`, `concolic_targets.rb`, any dump, the shipped
`_C7A_LEN_PAIRS` constants, `demand_round.py` (the non-rooted seeder; not
used by the drive, but it still indexes raw ordinal exprs and would need the
same canonicalization if anyone runs it).

## 4. `_tier_unobservable_pairs` — review and the collapse attribution

Placement: correct (after C7-A, before tier2). Withdrawal bypass: correct
in intent, **wrong in one detail** — it skipped every key in `already`, and
`already` also holds the pairs an earlier tier tried to declare and W-E
withdrew (`_addi` keeps withdrawn keys there on purpose). Those are exactly
the variant-/type-disjoint `> 1` pairs the tier exists for. Fixed: `_addi`
records withdrawn keys; the tier skips a key only if it is in `already` and
not withdrawn.

Attribution, measured with the real `build()` on the canonical corpus
(`scratchpad/sim_canon*.log`), maximal cliques / evaluated whole by some run:

| model | cliques | jointly evaluable |
|---|---|---|
| ordinal names, no P1 (baseline) | 945 | 0 |
| ordinal names + never-co-evaluated pairs independent | 1 276 | 498 |
| canonical names, P1 OFF | 2 223 | **0** |
| canonical names, P1 OFF, variant/type exclusivity exempt from W-E | 2 411 | **0** |
| canonical names + P1 (shipped) | 3 109 | **2 226** |

So: canonicalization alone realizes nothing — it makes names mean one
thing, but W-E still glues every `> 1` expression to every decision it
never co-occurs with, and those cliques are unrealizable. The structural
exclusivities (a run has one format and one type) are not enough either.
The realizability comes from P1, and the part that matters is beyond
tier0a/0b: pairs never co-evaluated for path reasons (a read under one
owner chain vs. a decision under another). On the 4 726 → 88 headline: that
collapse is mostly the clique cap (§0); it should not be attributed to
either change until the uncapped pass runs.

Straight answer to "17 874 unprobed claims": each claims that no run in the
corpus evaluates both expressions, which the gate checks against the whole
corpus (verdict "mutually exclusive: both recorded, never co-evaluated") —
the same status as `_tier_samerep_never_coeval` and the corpus half of
tier1c, both accepted. It is not a claim that the combination is impossible
in the program; it is a claim that the corpus holds no combination to
demand, with a tripwire: the first run that co-evaluates a pair turns its
gate entry into a real flip-both probe, and a FAIL withdraws it. Restricting
it to same-rep pairs returns to the second-to-last row: 0 jointly evaluable
cliques and a loop that cannot converge. The defensible middle, if you want
one, is to keep P1 but print the pair census by class (variant-disjoint /
type-disjoint / neither) so the "neither" residue is auditable; the run that
separates it is the 3-minute `sim_canon` with per-class tier counters.

## 5. The residual

Real residual (uncapped pass): every one of the 3 109 cliques still has
≥5 unobserved satisfiable combinations, all 1 200 sampled failing cliques
contain a `> 1` length expression and 1 100 contain `services > 1` — the
W-E product of the root families' many-arms with the decisions they
co-occur with. 2 226 of those cliques are evaluated whole by some run, so
their combinations are reachable by the rooted seeder (4 870 seeds built,
0 without base); the 883 cliques no run evaluates whole are pairwise
co-evaluated but never jointly (e.g. `aspect_memberships` under contact
find_by_1 × find_by_2 × `aspects > 1` × unread × actors) — those need
either a run that reaches all of them or a declaration, and the loop will
show which by not closing them.

The 84 of the capped pass are the single-expression, one-polarity misses
(the per-expression fallback's output). Population: row decisions of the mobile header's
UNREAD list variants (`Relation_to_ary_notifications_3aa8587a` /
`_10254800`) — `_target_statusmessage_text_nil`, `_mentions_container_*`,
`_author_profile_first_name == ''`, … — 55 of 84; the `1=0`-scope photos
name `4bc79851` (6); aspect_memberships under contact `find_by_2` (2);
`Core::ClassMethods.find_by_1_*` (5); target/container guids under
the typed and plain lists; `devise_user_first_1_username == ''`. They are
real: under ordinal naming the unread list shared `to_ary_1` with the plain
list and its rows' other polarity was credited from plain-list runs. All
are reachable by seeding on a base that records them (`_demand_root.py`:
0 without base, 0 skipped); none is structurally unrealizable. The
combination residual is unknown until §0's re-run.

## 6. C7-A re-instantiation per reading

The 14 ordinal-keyed pairs no longer match any expression (the names do not
exist) and are inert; `_tier_c7a_by_family` re-declares only the five whose
probe snapshot readings were the declared families, on canonical names:
aspects×services, aspects×tags, services×tags, services×unread,
tags×unread (all resolved: C7-A=5 in the build line). The other nine
carried a PASS earned on another reading: `records_2×to_ary_1`,
`records_2×Relation_records_1` (snapshot photos×unread), `records_2×records_1`
(services×aspects), `records_3×to_ary_1`, `records_6×to_ary_1` (×unread, not
list), `records_3×records_1` (aspects×am), `to_ary_1×records_1`,
`Relation_records_1×records_1` (unread×aspects), `records_6×records_1` (no
run co-records tags and aspect_memberships at all).

What re-instantiation requires now, per family pair (fA, fB): declare
`(SYM_LEN_<canonical fA>_rows > 1) ⊥ (SYM_LEN_<canonical fB>_rows > 1)`
for each canonical name of fA × each of fB (photos and mentions are several
names each), and run the gate. With canonical names the snapshot
`pick_snapshot_with` chooses necessarily has the declared readings — that
is the snapshot filter — and `_reading_changed` returns NOT-COMPARABLE if a
flip re-routes an ordinal. Pairs on the STAY-DEPENDENT list must not be
declared at all: to_ary × photos (any chain), to_ary × mentions, list ×
unread, same-family pairs (aspect_memberships ae3f × 6f13 are two contacts
of one row: dependent).

## Artefacts

`scratchpad` = `/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad/`:
`alias_sound.log/json`, `alias_bad.log/json`, `cov_capped.log`, `cov.log`,
`sim_canon.log`, `sim_canon_noP1.py`, `sim_canon_struct.py`, `legend.out`,
`declared_sound.json`, `declared_bad.json`. Batch:
`_canonical_legend.json`, `coverage_summary.json` (the capped pass).
