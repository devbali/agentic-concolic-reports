# P32 — STATE AT HANDOVER (2026-09-14 19:3x)

## >>> STOOD DOWN FOR THE BOX REBOOT (core upgrade). LAUNCH NOTHING. <<<

The coordinator stopped both jobs at 19:14 so their tails flushed rather than
being cut by the reboot. **The standing "the gate runs to completion" rule is
REVOKED for this stop.** Nothing is running; nothing is to be launched until
after the reboot.

```
  processes 0   units 0
  _p32_regate_probes.ckpt.jsonl   75 226 records   19:13:43   (~15 h of CPU)
  _p32_regate_derive.ckpt.jsonl       98 records   19:30:02
  _p_achk_index.ckpt.jsonl       234 251 records   18:20:45
  assumption_checker.py  5ae1b13c  (frozen, matches the bank)
  stage 1: 75 226 of 102 178       stage 2: <= 5 103 probes (~5 % of stage 1)
```

**RESUME WITH BOTH SPEED LEVERS — do not restore the old settings** (costed in
`_p33_gate_speed_plan.md` §94.4-§94.6; the restart makes them free):

```
  ACHK_PROBE_BATCH=800        hard cap 1000 (run_probe's 900 s timeout binds)
  VARIANTS=<single scenario>  no src/ edit needed
      together: 10.5 probes/s at 2 workers vs the 3.50 it was stopped at (3.0x)
  CONCOLIC_PROBE_WORKERS = min( floor(cores-1.5), floor((cage-20G)/1.3G) )
      recompute AFTER the reboot; with a 32 G cage the memory term gives 9,
      so the core count will bind
  MemoryMax=24G   KEEP — peak 16.8 G measured, sawtooth 14.7-16.5 G, v3 17.4 G
```

**The VARIANTS differential must assert DUMP-SET CARDINALITY AND MEMBERSHIP,
not per-dump equality.** The runner writes a dump only for a NEW path
signature; if novelty is per-launch rather than per-scenario, dropping three
scenarios silently changes the surviving scenario's dump set — and it fails in
the direction that LOOKS like success. Assert `200/200 matched, 0 replayed
singly` plus an identical set of dump basenames-modulo-suffix. If it does not
hold, the lever is dead — stop, do not take it. Run it in a scratch rig; not
one dump may land in `posts_show/`.

**And repoint the bank's `cfg` digest when you add `env_by_scenario`** — the
manifest edit changes `_ckpt.digest(cfg)` and would otherwise DISCARD the
3.2 GB / 75 226-record bank (~10 h). §90.4's technique.

---

# (earlier, 13:5x)

## THE GATE LANDED, AND ITS WITHDRAWAL IS PARTLY REFUTED (§96)

```
  GATE (16 624 s, all 1363 classes)  PASS 785  FAIL 274  N-T 243  N-C 61
  WITHDRAWN class-whole              1174 pairs of 2701 (43.5 %); 1527 kept
                                     FAIL 477 | N-T 495 | N-C 202
```
**The 785 PASSes stand** (40/40 held at 8 bases). **The 697 N-T+N-C pairs do
not**: they exit before criterion (vi) ever runs, so they are facts about one
base; ~87 % are expected to restore. **Any post-withdrawal residue is therefore
OVERSTATED.** Only the 477 FAIL pairs are decisive at one base.

**IN FLIGHT: `_p32_regate.sh`** (unit `posts-p32-regate-20260914`, cap 14 G),
the 243 N-T classes ONLY, `ACHK_BASES=8`, merged checker md5 `5ae1b13c…`.
Stage 1 needs **101 154 probes at 2.22/s = ~12.5 h**, then stage 2. Checkpointed
at `_p32_regate_probes.ckpt.jsonl`. **Do not restart it with a different
`--declared` list** — `declared` is a checkpoint input key and a change discards
every probe. **Never stop it casually**: the original gate is 10 h and its probe
bank is unresumable.

## ONE INDEX LOG FOR THIS ENDPOINT — ADOPT THIS (coordinator, 2026-09-14)

**Canonical path: `_p_achk_index.ckpt.jsonl`. Use it for EVERY future gate in
this batch.** posts_show currently uses THREE names — `_x12_index.ckpt.jsonl`,
`_p26_achk_index.ckpt.jsonl`, `_p30_achk_index.ckpt.jsonl` — so every new gate
name starts from zero and pays a full corpus index: **13-28 min thrown away per
relaunch** on 233 515 dumps, against ~20 s-1.8 min to resume. This round paid
it — the re-gate's index rebuild cost **660 s**.
**The saving is TIME, not disk**: the three logs look like ~1.5 GB by `ls`, but
`du` says **237 MB total** (the pool is compressed). Do not argue it on space.

**DO THIS THE MOMENT THE RE-GATE EXITS** (it holds the file and its `.lock`):

```bash
cd .../posts_show
mv _p26_achk_index.ckpt.jsonl _p_achk_index.ckpt.jsonl
#   Rename is safe: the checkpoint is keyed by input keys stored INSIDE the
#   file, not by its filename.
#   Do NOT hardlink it while a gate runs — on a discard the checker renames the
#   old log aside to `.stale` (that file exists from this round) and a hardlink
#   would silently keep pointing at the dead inode.
rm -f _p26_achk_index.ckpt.jsonl.stale _p30_achk_index.ckpt.jsonl
#   dead once the canonical file exists (~990 MB apparent, ~160 MB actual)
```

`_p32_regate_NC.sh` (the 61 NOT-COMPARABLE classes, the successor run) is
ALREADY wired to the canonical path. `_p32_regate.sh` is NOT — it was running
when this landed, and a running script is never edited.

**Why this is newly safe.** Since the X12 merge the index is INCREMENTAL:
resuming an index built under one declared set and then running a *materially
different* declared set against it parses ZERO dumps and yields a byte-identical
fingerprint, and a from-scratch run of that set yields the same fingerprint.
**Changing what you declare between rounds no longer costs an index.** Adding an
`AliasAssumption` still forces a full rebuild, correctly, with `input keys
changed: canonicalize`.

**THE DERIVE CHECKPOINT CANNOT SURVIVE A RELAUNCH HERE — STRUCTURAL (§100.5).**
The gate writes its replay dumps INTO the batch directory the corpus glob reads,
so it grows the corpus its own checkpoints are keyed on. Measured: corpus moved
233 501 -> 234 251 mid-run; the index resumed (incremental, per-dump) but the
derive checkpoint was DISCARDED on `input keys changed: corpus` and rebuilt from
zero. Refined by a second restart: the derive checkpoint survives **iff the
corpus did not move in between**, and it is PROBING that moves it. A relaunch
after a run that probed (every OOM, every long kill) pays the ~23 min re-derive;
a quick stop/start with no probing between pays nothing (measured both ways,
§100.5). **Budget ~23 min of re-derive whenever you restart a gate that had got
as far as probing.** The canonical index buys the INDEX resume
only. Plausible fix (NOT implemented, do not attempt mid-gate): write replay
dumps outside the batch directory, or where the corpus glob excludes them. It
touches `assumption_checker.py`, frozen at `5ae1b13c`, and EVERY edit to it
discards all probe banks — so it belongs to the next BATCHED change, after this
gate lands.

**MEMORY — SIZE FROM THE PREVIOUS FULL GATE, NEVER FROM THE HEARTBEATS (§100.2).**
The heartbeats stop when probing starts, so their ceiling is not the peak: 14 G
sized from a 5 335 MB heartbeat was OOM-killed after 13 h of CPU. Gate v3's real
peak was **17 431 MB**. A RESUME also costs more than a cold start (it pulls a
233 501-row index into memory rather than building one): this run passed 12 GB
in `derive-probes` alone. **Current cap 24 G, and do not go below it.**

**CAVEAT — never run two gates in this directory at once expecting both to be
cheap.** The second takes a non-blocking lock on the index log and indexes
WITHOUT the checkpoint: safe and never corrupt, but uncached, so it pays the
full 13-28 min.

(This batch's `_engine_section.py` header still claimed the index is "keyed on
the corpus, the declared set, ..." — corrected in place; backup
`_bak_engine_section_pre_indexnote_20260914.py`.)

### WHEN IT FINISHES
1. Restore every class that comes back **PASS** to the licensed set — **EXCEPT
   the pinned refutation below** — by removing its pairs from
   `_confinement_withdrawn.json`.
2. **PINNED, NEVER AUTO-RESTORE:** `findpublic_like_1_not_found ×
   as_api_response_1_row_text_empty`. Genuinely refuted (FAIL on 6 of 8 bases,
   "(i) flip-A changed 1 shape OUTSIDE footprint(A): Photo.url"). It currently
   reads **NOT-TESTABLE** in `_p26_gate_results.json`, so it is INSIDE the
   re-gate bucket and a blanket "restore everything non-FAIL" rule WILL wrongly
   restore it.
3. Book the **evidence grade** with each restored PASS — every row now carries
   `bases_probed` / `bases_realising` / `bases_passing` / `bases_failing` /
   `base_verdicts`. A licence resting on 1 realising base is not the same as one
   resting on 8, and POLICY_HEADER needs that at closure.
4. Re-pass and re-census; expect the residue back toward or below 4 093.
5. The 202 N-C pairs are in the same boat as the N-T ones but were NOT in this
   re-gate (`_p32_regate_NC.json` is prepared, 61 classes).

### THE CONTROL IS DONE — §16g MOVED NOTHING (§98)
`d08df10a` vs `9a458961` on round 9's list, same flags, `NO_WITHDRAWN_PAIRS=1`:
the ENTIRE summary block is **byte-identical** (MISSING=151, PCS=2098051,
DEMAND_SETS=836, every foreclosure and confinement number). Rounds 9 and 10
carry forward; the post-restore number may be compared to them directly.
Trap: that control reads **151**, not 147, because `_snapshot_pruned_P31A2.txt`
is round 9's list. Round 10's list is `_snapshot_pruned_P31AB2.txt` = 147.

### CLASS D IS FIXED (§97)
`_p23_index.py` dropped every length variable not ending `_rows`; class D's pin
ends `_ids`. Fixed, flag-gated, `P23_LENS=all` is the new default
(`P23_LENS_ROWS_ONLY=1` reproduces the old defective index). Proved by a
three-way differential over one list: lens **32 -> 39**, rawlens 17 -> 24,
nothing lost, and 39 is exactly the number of distinct `SYM_LEN_` names measured
independently in the corpus. Round 11's index must be built with the default;
the 12 gaps that carried "UNREALISED PIN" should then stop carrying it.
NOT driven — round 10's `_p31_index_P31AB.pkl` is untouched.

### (superseded) AN OWED CONTROL
`src/concolic_engine/coverage.py` moved AGAIN, `d08df10a` -> `9a458961` at
07:50. Round 10's MISSING=147 was measured under `d08df10a`. **Before any
post-restore number is compared to 147, run the §89.1 control**: same list, same
flags, `NO_WITHDRAWN_PAIRS=1`, current engine — expect MISSING=147. No pristine
`d08df10a` copy is on disk to diff.

### STOPPED ON PURPOSE
`P32W` (the post-withdrawal pass) reached 1 367 demand sets and was stopped:
the number it was computing is the overstated one. Checkpoint intact at
`_cov_p31_p32w.ckpt.jsonl`; resume only if the conservative bound is wanted.
Note it passed 836 sets — withdrawing licences ENLARGES the projection.

---

# (earlier, 06:1x)

Rounds 9 and 10 are DONE and booked (`_COMPLETION_20260910.md` §92, §93).
§91.6's stale STATE block was corrected in place, as the coordinator asked.

## THE HEADLINE

**The base rule is right. S6's contradicted-length-gate column went 1 636 -> 0
-> 0**, over two rounds, two residues and 78 704 cube literals. The length-gate
family sits at 99.8 % honoured in both rounds.

## BOOKED

```
  MISSING 161 -> 151 (round 9) -> 147 (round 10)   NODES=137  DEMAND_SETS=836
  §16b   REMAINING 5 097 -> 4 644 -> 4 404 -> 4 371
  OR-ref REMAINING 4 093 -> 3 849 -> 3 901 -> 3 868   over 236 sets
  closed/run (§16b) 0.796 -> 0.435 -> 0.062      (stop rule is 0.05, two rounds)
  model-less 0 throughout; tree complete; foreclosures NOT provisional
```

## WHY THE YIELD COLLAPSED (§93.3)

97 % of round 10's never-evaluated literals are **guid**. The cube's emptiness
pins (now a HARD filter, which is what fixed the contradictions) force a base
with FEW rendered API rows, and the guid literals are indexed by API ordinal —
so the ordinal is never made and the literal is never reached. For **400 of 530
gaps no base in the corpus realises the pins and walks the gates at once**;
that is a completed search, not a heuristic miss. Base SELECTION is exhausted.

## BOOKING CONVENTION (coordinator, 2026-09-14)

**§16b is the YIELD. The OR-refined figure is a PROJECTION, not a countdown.**
Under §16b `satisfiable` is 27 359 in every census, so Δcovered is exactly what
the runs achieved. The OR-refined number moves with the corpus because §16e/§16f
coarsening is measured on it — round 9 closed 240 cubes and its OR-refined
residue still ROSE 3 849 -> 3 901. **A rise there is not a regression.** Say so
wherever both numbers appear (§92.4 derives it).

## DO THIS NEXT, IN THIS ORDER

1. **THE GATE FIRST.** `posts-p26-gate-v3-20260914` is active, 68.8 % done
   (76 481 / 111 241 probes), ~3 h left at its measured 2.7-3.2 probes/s.
   It is testing all 2 701 of this endpoint's confinement pairs, **100 % of
   which have never been probed, and the whole residue rests on them.** When it
   lands: withdraw the FAILs, re-pass, drive what reopens. THAT IS ROUND 11.
   **NEVER STOP IT.**
2. **Class D — the index defect** (§94.2). `Calculations_ids_1_ids` is minted
   in 68 % of runs and is ZERO in 19 %, but `idx["lens"]` does not carry it, so
   the constructor calls it "unminted" and cannot filter on it. Cheapest fix;
   a wrong "unminted" silently loses filtering wherever else it occurs.
3. **Class A — base SELECTION** (§94.1). For **71 %** of the residue a
   compatible base ALREADY EXISTS (pins + required API ordinal jointly
   witnessed). The constructor is not finding it. Suspects: the D1 both-ways
   filter (6 329 435 bases rejected in round 10) and group-level gate
   agreement. Both are already instrumented.
4. **Class A — base MANUFACTURE**, the two-phase construction, and ONLY for the
   **26 %** whose pin-conjunction no run has walked. Provably the smallest part.

**Round 11 is a DRIVER round, not a modelling one** (§94.3): measured offline,
NO pin is unachievable and there is NO logical tension between the emptiness
pins and the API ordinal in any cube. No declaration, no `src/` inference, no
Rule T is required by either class.

**NAME-BOUNDARY RE-RUNS (§95).** `_unev_why.py` and `_mk_residual_classes.py`
were re-run on their original inputs after another agent's `concolic_engine.names`
fix. REALISED went **89 641 -> 184 581 (2.06x)** — the gates were realised all
along and were invisible. Both verdict classes collapsed: **CONJUNCTION-
FORECLOSURE 491 -> 0 and REACHABLE 109 -> 0**, all 600 pairs now NO-MATCH (no
corpus run matches the honoured prefix). So that instrument now proves NOTHING
in either direction — every "still driveable" AND every "impossible" verdict
from it is withdrawn. `_gc_realise` dropped the two `as_api_response_N_row_guid`
gates from "contradicted and never realised": only `CollectionProxy_size_1_size
== 0` remains, and it is a mock-domain ruling, not a driving target.
**TODO for whoever owns `_mk_residual_classes.py`:** class (c)'s closing
sentence is still the pre-fix narrative naming the foreclosure and REACHABLE
shares, both now 0. Template line, reported not hand-edited.

**Beware the name join** (§94.0): dumps spell lengths `len(X)`, the checker
`SYM_LEN_X`, and ordinals are canonicalised to semantic names. Always put a
dump through `canonicalize_ordinals` + `fix_len_names` before comparing names —
a missing conversion fails SILENTLY as "no compatible base". P32's first
class-A answer was wrong for exactly this reason and is retracted in §94.0.

## RUNNERS

```
  _p32_round.sh    TAG= P32_LIST= P32_OLD_INDEX= P32_SKIP_S1=1 P31_FROM=n
                   stage-skipping, idempotent. Round 10 was:
                   TAG=P31AB P31_FROM=3 P32_SKIP_S1=1 \
                   P32_LIST=$PWD/_snapshot_pruned_P31A2.txt \
                   P32_OLD_INDEX=$PWD/_p31_index_P31A.pkl
  _p32_guard.sh    counts PROBES (reads "N roots" from the log, does not assume
                   40), 900 s window, stands down only below 0.60 x a MEASURED
                   baseline, and never when no baseline exists.
  _p32_gate_baseline.txt = 2.667 probes/s (v3, clean). Stand-down line 1.60.
  GATE_LOG/GATE_UNIT now default to v3.
```

`_p31_round.sh` and `_p31_guard.sh` were NOT edited — they are the record of
rounds 8-9 as run. `_p26_gate_v2.log` is a symlink to v3's log so the samplers
track the live gate; v2's own 820 batches are `_p26_gate_v2_FINAL_20260914.log`.

## HOLDS — REDUCED BY THE COORDINATOR, 2026-09-14 04:00

The whole notifications hold list (engine section, assumption_checker,
`_c7_audits`, AUDITS_CHECKPOINT, `notif-*`, any coverage_report.py) is
**WITHDRAWN** — it cost this round ~5 h for no resource reason. Exactly two
rules remain: the memory invariant against the live cap (enforced in
`_cage.sh:gate_launch`) and the gate CPU guard above.

---

# P35 — STATE AT HANDOVER (2026-09-15 03:4x)

## THE GATE IS COMPLETE. DRIVING IS STOPPED ON EVIDENCE. SEE §103-§104.

```
  re-gate NT  posts-p32-regate6-20260915     PASS 204 FAIL 5 N-T 34   wall 2379s
  re-gate NC  posts-p32-regate-nc2-20260915  PASS 52  FAIL 7 N-C 2    wall  502s
  restore     610 pairs / 256 classes        withdrawn 1174 -> 564
  post-pass   MISSING 147 -> 710   DEMAND_SETS 836 -> 998   (clean differential)
  §16b        REMAINING 4 371 -> 965 224   satisfiable 27 359 -> 1 039 416 (38x)
  round 11    §40.5a differential NULL: 124/525 in BOTH arms, 0 gaps differ
  BLOCKING    710  -- closure NOT reached, and not reachable by base selection
```

## STILL IN FLIGHT

`_p35_emit.sh P35` (scope `p31emitP35.scope`, ~5 GB, one core) — the §16f
EMISSION arm of the post-restore census. The `prod`/§16b arm it accompanies is
**already complete and booked** (§103.7); this arm only produces the cube list
for a future constructor. At 675/998 sets after 4 433 s and slowing
(25 sets ≈ 1 700 s, ~34 k cubes per window): **expect ~6 h more and ~450 k
cubes.** Nothing depends on it. Kill it freely if the box is wanted; the
booked numbers do not change.

## WHAT THE NEXT AGENT MUST NOT REDO

* **Do not quote MISSING=147 or §16b REMAINING=4 371 again.** Both were measured
  under 2 701 confinement licences of which not one had been probed. §103.5/§103.7.
* **Do not compare two §16b numbers across a change in the withdrawn set** —
  `satisfiable` moves with the assumption set. §92.4's convention is retired.
* **Do not re-run the §40.5a discriminators here.** Null, with an independent
  corroboration (`alias_canonicals_covered` is N/N in all 401 failures). §104.2.
* **Do not re-probe the N-C classes with a private bank.** One bank per
  ENDPOINT: `declared` is in no checkpoint key, and the shared bank served
  99.84 % of the N-C gate's probes. §103.2.
* **Do not lower the probe batch to fix a timeout.** regate5 died on contention,
  not on the cost model. §102.5.

## THE ONE THING THAT WOULD MOVE THE NUMBER

Base MANUFACTURE for `(as_api_response_2_row_guid == '')` in `auth_json`:
present in **all 401** failing gaps, realisable alone in 31.6 % of the corpus,
never co-occurring with the cubes' pins, and **309 of the 401 are short by
exactly one gate**. The index carries its necessity condition verbatim (§104.3).
Two-phase construction, never built.

---

# P35 ADDENDUM (2026-09-15 04:3x) — THE CLOSABILITY ANSWER. SEE §105-§107.

## VERDICT: `OVERALL_COMPLETE=True` IS **NOT REACHABLE** HERE. SHIP INCOMPLETE.

```
  525 constructible gaps, classified over all 48 943 profiles:
      124  construct fine
        2  genuine base-SELECTION miss          <- the true size of "the constructor misses it"
      399  FORECLOSED demand, NO base can exist <- 281 ord-2, 90 ord-4, 16 ord-1, 12 ord-3
  Base MANUFACTURE is IMPOSSIBLE, not hard (§106.1). Do not build it.
  §94.1's "71 % have a compatible base" is retired: it never tested gate-walking.
```

## THE ONE LEVER THAT PAYS — §16f WIDTH. NOT SHIPPED, AND IT SHOULD BE CONSIDERED.

```
  W=3 budget  20 000  REMAINING 3868   (as shipped)
  W=3 budget 200 000  REMAINING 3868   <- budget was NEVER binding; attribution clean
  W=5 budget 200 000  REMAINING 2927   <- -24.3 % for +3 min. THE KNEE.
  W=7 budget 200 000  REMAINING 2867   <- +2.1 % for 2.4x wall. Not worth it.
```
Sound at any width: width is a COMPUTE bound on a set-cover search and
exhausting it leaves the member IN the leaf (the conservative direction).
**Every §16f/OR-refined number in rounds 8-10 and in §103.7 is quoted at W=3 and
is therefore loose by ~24 % or more.**

## WHY THE LADDER STILL CANNOT PRUNE THE REST — A `src/` LIMIT, NOT A TUNING ONE

§16f conditions only on the leaf's **walk PREFIX**, not on the cube's
assignment. Ordinal inversion proves it: ordinal 2 is 281 of 399 blocks but gets
2 (C,d) classes at W=3 / 10 at W=7, while ordinal 4 is 90 blocks and gets 449.
Fix is the owner's (`src/` frozen at `5ae1b13c`, untouched): let `C` range over
already-ASSIGNED literals. **Falsifier: the 281 ordinal-2 blocks must leave the
residue at W=3.** Evidence to check against: `_p35_manufacture_joint.json`,
`_p35_manufacture_classes.json`, `_p35_classA_fullgate.json`.

## IN FLIGHT (both healthy, both deliberately kept)

```
  p31emitP35.scope     W=3 post-restore §16f — the coordinator's load-bearing arm
                       ~212 k cubes and growing, 2h23m CPU, 5.0 G. KNOWN LOOSE (W=3).
  p31emitP35RW5.scope  W=5 post-restore §16f — the number that should be booked
                       still in its prod arm, 3.3 G.
```
The PAIR is the differential that measures the width effect on the real
post-restore universe rather than the control one. Neither is needed for the
§107 verdict, which does not depend on them.

## CLOSURE STAGES WERE **NOT** RUN — DELIBERATELY

The coordinator's condition was "if the ladder leaves a reachable path, take it
through to closure". It does not (§107.5). Running extraction/subsumption to
certify a COMPLETE claim that cannot be earned would be the wrong artefact.
§107.6 lists exactly what a shipped INCOMPLETE policy must disclose; that is a
decision for the coordinator, not a discovery task.
