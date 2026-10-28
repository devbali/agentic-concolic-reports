# people_stream — cannot close without a runner port (2026-09-09)

## Where it stands

First corpus ever generated, on the RE-SYNCED boundary (Rule T, verbatim copy
of the shared file + declaration filter; load-tested EXIT=0):

    201 dumps, 21 nodes, 31 missing, 1 614 PCs, truncated=True
    assumptions 172 (158 used), dump_errors {UnknownFormat: 6} -> declared, _WALLS.md

All three DSE scenarios report `drained=true, worklist drained`, so 201 is the
FULL reachable path set from base exploration. The corpus cannot grow further
by re-running base rounds.

## The blocker

All 31 missing entries are combinations involving ONE variable —
`SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_guid` — paired with
`_not_found`, `closed_account`, `nsfw`, `_text`, `comments_count`.

They are REACHABLE in principle: that variable IS co-evaluated with the others
(120 of 201 dumps record guid + not_found + nsfw together). These are specific
unobserved OUTCOME ASSIGNMENTS, not never-co-evaluated pairs — precisely what
demand seeding exists to reach.

**But this batch's `run_dse.rb` is a results2-era port and has none of the
demand machinery** that notifications_index's runner has:

| mechanism | notifications_index | people_stream |
|---|---|---|
| `EXTRA_SEEDS_JSON` (seed roots onto the worklist) | yes (l.370) | **missing** |
| `concolic_seeds` recorded into each dump | yes (l.259) | **missing** (dumps carry `{}`) |
| `LABEL_SUFFIX` | yes (l.408) | **missing** |
| `SEEDS_ONLY` | yes | **missing** |

Consequence observed: base round 2 wrote 0 new dumps because without
`LABEL_SUFFIX` it re-derives identical filenames; and no demand round can be
run at all because there is no way to inject a demanded assignment.

## What the port needs

From `results3/notifications_index/run_dse.rb`:
1. record `dump["concolic_seeds"] = seeds` (l.259) — without this a demand
   round cannot tell which root produced which dump;
2. `EXTRA_SEEDS_JSON` -> roots prepended to the worklist (l.370-374);
3. `LABEL_SUFFIX` in the dump label (l.408);
4. `SEEDS_ONLY` to replay roots without further flipping (l.402, 432, 450).

Then port `_demand_root.py` (it builds roots as BASE SEEDS OF A REAL DUMP +
the demanded assignment, which is what makes a demanded combination reachable
in context) and the endpoint should close quickly — 31 missing over 21 nodes
is small.

## Not attempted tonight
The port is a real change to a runner I have not tested against, and a wrong
seed mechanism produces a corpus that looks fine and is not. It is the next
task for this endpoint, not a five-minute edit.

---

# UPDATE (2026-09-09, after the runner port) — the real blocker is DIMENSION IDENTITY

## The port is DONE and works
`run_dse.rb` now has `LABEL_SUFFIX`, `EXTRA_SEEDS_JSON`/`SEEDS_ONLY`, and
records `concolic_seeds` into every dump. It also no longer WIPES the corpus on
every invocation (it did: base round 2 deleted round 1 and rewrote it — net 0
dumps — and the first demand round replaced the 201-dump base corpus with its
own 152). `_demand_root.py` is written and builds rooted seeds. Verified:
`[seeds] 31 extra roots` loaded in all three scenarios, corpus accumulates
(201 -> 353 -> 554).

## And it does not move the number

    baseline        201 runs -> missing 31
    naive seeds     353 runs -> missing 31
    ROOTED seeds    554 runs -> missing 31

## Why (measured)

Take missing[0]: `nsfw ∧ records_1_row_text='' ∧ records_1_row_comments_count=0
∧ guid=''`. Each conjunct is observed BOTH ways corpus-wide; no run has all of
them. 0 of 201 R1 dumps match fully, 129 match partially.

The cause is the CALL-ORDINAL identity problem — the same one that made
notifications_index diverge:

    in the R1 demand dumps:  records_4 evaluated 288x, records_1 only 72x
    seeds naming records_1 that landed in a run where records_1
    never occurred (seed inert): 10

The same logical read — a post row's `text` / `comments_count` — is
`records_1` on some paths and `records_4` on others, because the symbolic
result is named by WHEN the call happened (`SymbolicFunc.next_call_idx`), not
by WHAT it is. A seed keyed on an ordinal is inert whenever the path takes the
other one, and the checker demands combinations across ordinals that no single
path can realise.

## The fix already exists

`DecisionAliasAssumption` + the load-time canonicalization built for
notifications_index (see `notifications_index/_DECISION_ALIAS_REPORT.md`):
name each decision by the statement it resolved to (family + normalized note
INCLUDING binds) instead of by ordinal. On notifications that took cliques
evaluated-whole from 0/945 to 2 226/3 109.

For people_stream that means porting into this batch's `coverage_report.py`:
  - `canonicalize_ordinals()` at load (the P0 bridge), and
  - the alias declaration tier in `coverage_assumptions.py`,
then re-running the rooted demand round against canonical names — a seed
keyed on `records_<family>` is not inert the way `records_1` is.

## Do NOT
Do not "fix" this by declaring the 31 independent or untracking them. They are
combinations over decisions that DO co-occur (120 of 201 dumps record guid +
not_found + nsfw together); they are unreached, not impossible.

---

# FINAL DIAGNOSIS (2026-09-09) — the residual is UNOBSERVABLE COMBINATIONS

## Everything mechanical now works

| piece | state | evidence |
|---|---|---|
| runner: `concolic_seeds` recorded | DONE | 545 dumps carry seeds |
| runner: `EXTRA_SEEDS_JSON` / `SEEDS_ONLY` / `LABEL_SUFFIX` | DONE | `[seeds] 40 extra roots` in all scenarios |
| runner: corpus accumulates (was WIPING every invocation) | DONE | 201 -> 353 -> 554 -> 755 |
| `_demand_root.py` rooted seeding | DONE | 40 roots, 0 with no usable base |
| DecisionAlias canonicalization at load | DONE | nodes 21 -> 29 (universe re-keyed by statement) |
| seeder maps canonical -> ordinal | DONE | **0 untranslatable** demanded vars |
| **seeds actually honoured by the runs** | **YES** | **810 honoured, 0 CONTRADICTED**, 322 never evaluated |

## And the number does not move

    baseline            201 runs -> 31 missing (ordinal universe)
    naive seeds         353 runs -> 31
    rooted seeds        554 runs -> 31
    canonicalized       554 runs -> 40 (re-keyed universe, not comparable)
    canonical rooted    755 runs -> 40

## Why — measured, decisive

**All 40 missing combinations involve variables that NEVER all co-occur in a
single run, across all 755 dumps.** (0 of 40 have a run evaluating every
conjunct; 40 of 40 do not.)

They are not unreached — they are UNOBSERVABLE. The checker demands them
because the assignment is Z3-satisfiable over the declared variables, but no
execution path evaluates all those variables together. `coverage.py`'s own
docstring names this class: "Combinations that execution can never manifest
(an inner check guarded by an outer branch that ends the run — fetch-then-404)
are REPORTED MISSING until the caller declares the corresponding
independence."

The 322 "seeded var never evaluated" observations are the same fact from the
runtime side: the seed is honoured wherever the variable IS evaluated (810
times, never contradicted), and simply has no effect on paths that do not
reach it.

## The resolution, and why it is NOT mine to make

This is exactly what `_tier_samerep_never_coeval` (pre-existing, sanctioned)
and its generalisation `_tier_unobservable_pairs` do: declare independence for
decisions recorded in disjoint run sets, which the gate passes as "mutually
exclusive" WITHOUT a probe.

That is also its weakness, and the reason it is pending the coordinator's
ratification on notifications_index: **the corpus cannot distinguish
"impossible" from "not yet observed."** Declaring these 40 would close
people_stream immediately; it would also be 40 more unprobed exemptions, on an
endpoint whose corpus is only 755 dumps and whose exploration drained early.

So: people_stream is COMPLETE-able the moment that policy question is settled,
and not before. Deciding it silently here would manufacture a `complete: true`
that means less than the same word on conversations_index.
