# P44 — STATE AT HANDOVER (2026-09-17, resume session)

## JOBS — CHECK THESE FIRST, DO NOT DUPLICATE

```
  p44pruneP44FRESH1.scope    STILL RUNNING. choom-capped (8G), single-process
                              _prune_corpus.py over a 652 914-dump snapshot
                              (_snapshot_p44_P44FRESH1.txt), no --shards, no
                              incremental progress line -- only prints once at
                              completion. At last check: ~105 min elapsed,
                              68% CPU, PID alive, not OOM'd, not stuck (CPU
                              time keeps climbing between checks).
  p44-census-fresh1.service  STILL RUNNING, blocked on the prune above --
                              its next step after prune is CENSUS_MODES=prod
                              emit, verdict lands in _p31_emit_P44FRESH1.out
                              as a `MODE prod:` line. THAT LINE IS THE THING
                              TO READ FIRST, per the previous handover's advice
                              (still true, still not landed).
  p44-enumnew1-drive2.service  DONE this session (both legs: +21524 dumps at
                              6.57 r/s, +21131 dumps at 8.36 r/s -> corpus grew
                              past 674 438 toward ~695k raw dumps). Unit no
                              longer listed -- fully exited, do not re-launch.
```
Dead, ignore: `p44-census-r24.service` (failed), `p44-gate-postidx.service`
(failed) -- both pre-existing, not from this session, not touched.

**Load dropped from 19-23 (enumnew1 legs active) to ~5.5 once they finished.**
The box has headroom now for a width>4 drive IF the prune/census chain's own
memory/CPU budget is respected (it's choom-capped at 8G and single-threaded,
so a few JRuby workers alongside it should be safe -- check `free -h` and
`uptime` before launching, per standing rule).

**Next agent's very first move: `systemctl --user list-units 'p44*'` and
`tail _p44_census_chain_P44FRESH1.log`. If `DONE P44FRESH1` is present, read
`_p31_emit_P44FRESH1.out`'s `MODE prod:` line before doing anything else — that
is the first fresh residue number since the corpus passed 650k, and every
number below (`_p44_missreason_BACKLOG_v2.out`'s 57/43 split, the reachnec
outputs) was measured against the older UNION2 index/corpus, not this one.**

## CLASS B — RE-CONFIRMED, NO REGRESSION, NOT YET RE-VALIDATED BY A FRESH DRIVE

`BASES_PER_GAP` default is 2 in both `_p31_construct.py:157` and
`_p44_construct.sh` (grepped directly, no hardcoded override anywhere). The
`hard_ok`/`scored_pin`/`scored_pin_gate` tiering at `_p31_construct.py:670-834`
was re-read line-by-line this session looking for the specific desync bug
class the task named — found none; the relax path correctly zeroes the pin/
gate scores rather than reusing pre-relax rows.

Current classification (unchanged from before this session, reconfirmed
current): `_p44_missreason_BACKLOG_v2.out` — **4111/7214 (57.0%) Class B,
3103/7214 (43.0%) Class C**, built against `_p44_index_UNION2.pkl` (113/120
exprs), post-relevance-filter.

**Still open: no drive was run this session targeting the 4111 Class-B misses
specifically to see the hit rate actually rise now that the box is free.**
That's the natural next step once the prune/census chain clears (don't compete
with it for CPU on a single 8-core-ish box at load 5.5 without checking
headroom first).

## CLASS C — NEW: 2-WAY CONJUNCTION REACH-NECESSITY TOOL, VALIDATED, NARROW YIELD

New file this session: `_p44_reachnec_conj.py` (read-only measurement, no
`src/` touch, no numpy — pure-Python bigint bitmasks, one bit per dump; fast:
~3s to build 252 atom masks over 87 663 dumps, ~0.1s to test ~15 300 pairs).
It extends `_p44_reachnec.py` (single-condition foreclosure) to genuine 2-way
CONJUNCTIONS: neither atom alone forecloses the target's evaluation, the pair
together does, at >=200 co-occurring runs. This is NOT §16f (no demand-tree
pruning, no completeness inference) — it only gives the seed constructor a new
kind of PIN candidate for a member it currently has zero pins for.

Usage: `P44_INDEX=<pkl> P44_TARGET='<expr text>' python3 _p44_reachnec_conj.py`

Ran against the 4 UNION2 expressions with ZERO single-sided reach condition
(from `_p44_reachnec_UNION2.json`):

```
  (Length(SYM_PARAM_id) < 16)==True             100.0% eval -- trivial, skip
  (assoc_profile_nsfw == True)                  100.0% eval -- 0 pairs found,
                                                 also effectively unconditional
  (assoc_status_message_text_has_mention==True)  86.6% eval -- 3 GENUINE pairs
  (assoc_status_message_text_empty==True)        65.9% eval -- SAME 3 pairs
```
The 3 conjunctions found (shared across both `assoc_status_message_text_*`
members, suggesting a common underlying guard):
```
  n=302  CollectionProxy_records_photos_9930492e_rows length==0
           AND evilq_like_public_1_not_found==True
  n=243  same length==0
           AND evilq_reshare_public_1_not_found==True
  n=208  CollectionProxy_records_photos_e035b5b3_rows length==0
           AND findpublic_reshare_1_public==False
```
**Honest assessment: real, mechanically-found, but narrow** (208-302 runs out
of 87 663; a few tenths of a percent). Confirms the previous handover's
conjunction hypothesis is correct and actionable without new driving, but does
NOT by itself resolve the bulk of the 3103-miss Class-C residue.

## WHAT THE NEXT AGENT SHOULD DO, IN ORDER

1. Check jobs (`systemctl --user list-units 'p44*'`), read `_p44_census_chain_P44FRESH1.log`.
   If done, read `_p31_emit_P44FRESH1.out`'s `MODE prod:` line FIRST.
2. If the box has headroom (check `uptime`/`free -h`), run a Class-B-targeted
   validation round (`_p44_round.sh` / `_p44_construct.sh` over the 4111 Class-B
   misses from `_p44_missreason_BACKLOG_v2.out`) and report the before/after
   hit rate — this closes the loop on item 3 of the prior handover, which was
   diagnosed-but-not-driven both last round and this one.
3. Wire the 3 conjunctive pins found by `_p44_reachnec_conj.py` into
   `_p44_missreason.py`'s `COND` table (extend it to accept 2-tuples) and into
   whatever pin layer `_p31_construct.py` uses for single conditions today, so
   the constructor can actually target them. Then re-run missreason and see how
   many of the ~3103 Class-C misses on the two `assoc_status_message_text_*`
   members move to B. Expect a SMALL number given the n=208-302 scale — measure,
   don't assume.
4. Consider running `_p44_reachnec_conj.py` more broadly: not just the 4
   zero-single-condition expressions, but any expression whose best single
   condition still leaves a large unexplained fraction (the earlier note that
   `assoc_status_message_text_has_mention` "has none below 58%" was about
   EXPLAINED FRACTION of a weak single condition, not just the zero-condition
   case — worth widening the sweep). If 2-way conjunctions keep yielding real
   but small hits, consider a 3-way extension (same bitmask technique scales,
   just O(n^3) pairs to test — may need atom-list pruning first).
5. Wire the admissibility filter (`_p44_admissible.py`) into the round script
   between `_p23_gaps.py` and `_p31_construct.py` — validated (drops 1.6% of
   hits, 61.5% of misses, 1.63x yield) but STILL not wired in as of this
   session either. Carried over from the prior handover, untouched.
6. Enumerate the real target list via `CENSUS_MODES=enum` if not already
   produced by the fresh census chain — carried over from the prior handover,
   status unknown pending item 1's read.
7. Once the fresh census/index lands and 2-3 make some progress, run the
   actual Z3 coverage checker on the freshest pruned corpus and report
   OVERALL_COMPLETE/MISSING/BLOCKING/DEMAND_SETS. **Not done this session** —
   the fresh census this session depends on had not completed at handoff
   (still true two sessions running now; if it's STILL not done next time,
   that itself is worth escalating — a single-process, no-progress-indicator
   prune of a 650k+ corpus taking multiple hours with no way to check progress
   is an operational problem worth fixing, e.g. by sharding `_prune_corpus.py`
   the way it already supports via `--shards`/`--part`, or adding a periodic
   counter print).

## `src/` UNTOUCHED. BOUNDARY UNTOUCHED. 0 DECLARED. (still true)

`src/concolic_engine/coverage.py` (9a458961) and
`src/end_to_end_completion_checker/assumption/assumption_checker.py`
(5ae1b13c) were not opened this session. `concolic_targets.rb` and
`_assumptions_declared.json` unchanged. No assumption declared, withdrawn, or
restored. The only new artifact this session is `_p44_reachnec_conj.py`
(read-only measurement tool) in this results directory.

## TOOLS ADDED THIS SESSION

```
  _p44_reachnec_conj.py   2-way conjunction reach-necessity (see above);
                          pure-python bitmasks, no numpy dependency
```
All tools from the prior handover's list are unchanged and still valid
(`_p44_round.sh`, `_p44_construct.sh`, `_p44_drive_par.sh`, `_p44_missreason.py`,
`_p44_admissible.py`, `_p44_reachnec.py`, etc. — see git history / prior
handover text in `_p44_status.md` §§ before this one for the full list).
