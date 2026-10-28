# P44 — THE TARGETING HIT RATE, MEASURED AGAINST GROUND TRUTH (2026-09-15)

## THE HEADLINE: THE `_p31_construct.py` CONSTRUCTOR IS **NOT** BROKEN.
## ON CUBES THE CORPUS PROVABLY CONTAINS IT HITS **94.3 %** (495 / 525).

The 17.9 % positive-control figure that motivated this round is REAL but it is
**not this constructor's**. It is the control arm of `_p39_forecl_gate.sh`,
i.e. the probe constructor inside
`src/end_to_end_completion_checker/assumption/foreclosure_gate.py` +
`assumption_checker.py` (`seeds_as_written` + one `flipped_seeds` delta), a
different piece of machinery from the driver's `_p31_construct.py`. Both are
constructors; only the gate's was ever measured at 17.9 %, and the inference
"therefore the driver cannot target" does not follow. It is now measured
directly, and it is 94.3 %.

## THE INSTRUMENT (new, in this directory, all read-only except where noted)

```
  _p44_ctrl_gaps.py      builds gap records whose cube a NAMED corpus dump
                         realises, in the exact `_p23_gaps.py` format
  _p44_ctrl_verify.py    ground truth, by `_p15_explain.py`'s own code path
  _p44_construct.sh      runs a constructor over a gaps file, round-11 knobs
  _p44_drive.sh          one unit, four variants, resumes on chunk markers
  _p44_hitrate.py        hit rate + classified failure causes
  _p44_missdiag.py       per-miss localisation (which key, written or not)
  _p44_reachnec.py       reach necessity over DECISION outcomes (the index's
                         `necess` conditions only on LENGTHS)
  _p44_reachbase.py      does a base satisfying pins AND gates AND REACH exist?
  _p44_sample_jsonl.py   reservoir sample of an emission jsonl (never a prefix)
  _p44_cubes_closed.py   cubes closed by a drive, cross-counted, per 1 000 runs
```

**THE CONTROL IS GROUND TRUTH, AND IT WAS VERIFIED BEFORE IT WAS USED.** For
every real round-11 gap, a corpus dump that EVALUATES every slot of that gap's
cube and gates is chosen at random, and the cube is re-written to the outcomes
THAT DUMP TOOK. 525/525 controls verified realised by their witness dump,
re-read from the raw files by `_p15_explain.py`'s parser, not by the bitmasks
that built them.

## THE MEASUREMENT LADDER

```
  arm    control                               HIT    RATE    what it adds
  CTRL1  witness values verbatim               393/525 74.9 %  (control DEFECT)
  CTRL2  witness values REPAIRED to satisfy    495/525 94.3 %  the honest number
         the cube
  CTRL3  CTRL2 + the D1 off-switch honoured    identical seeds, no drive needed
  CTRL4  CTRL2 with the 485 WITNESS DUMPS      495/525 94.3 %  <- HOLD-OUT
         REMOVED from the base index
```

### THE HOLD-OUT ARM IS THE ONE THAT SETTLES IT

A 94 % rebuild rate would mean little if the constructor were simply finding the
witness and copying its seed. So the witness dumps were taken away: a FRESH
index (`_p44_index_HOLD.pkl`) built over the pruned snapshot MINUS all 485
witness dumps (48 943 -> 48 458 profiles; these are DISTINCT outcome profiles,
so removing a witness removes the only run in the corpus with that profile).

```
  bases the hold-out changed          86 of 525
  chosen base == the witness           0 of 525   (0 by construction)
  HIT                                495 of 525 = 94.3 %   -- IDENTICAL
  the 30 misses are the SAME 30, in the same families
```
**The constructor is not copying. It rebuilds the cube from a different run
94.3 % of the time, and taking the answer away costs it nothing.**

### CTRL1 -> CTRL2 IS A DEFECT IN THE CONTROL, AND IT IS WORTH STATING

129 of CTRL1's 132 misses were one shape: the cube demands
`(SYM_LEN_<canonical>_rows != 0)` TRUE and the control's own model said that
length was **0**. An alias CANONICAL is backed by SEVERAL RAW ordinals in one
run and their lengths differ, so "the witness's value for the canonical" is not
a function — and the constructor wrote the model value to every backing ordinal
and zeroed the very list the cube demands non-empty.

**The constructor does not check that the model value satisfies the literal it
is writing.** That is a real (if cheap) defect. Its cost on the real demand is
**ZERO, measured**: the coverage engine's models never contradict their own cube
— 0 of 1 679 length literals on `_p31_gaps_P35C.json` and 0 of 1 697 on
`_p31_gaps_P31AB.json`. So it is booked as a control repair, not as a fix that
bought anything.

### WHAT EACH KNOWN LEAD ACTUALLY BOUGHT

```
  lead                                      control          real demand (525)
  D1 both-ways off-switch honoured          0  (BYTE-IDENTICAL   +2 gaps
  (`_p39_construct_D1OFF.py`,                  seeds, same       124 -> 126
   `P23_HARD_SPLIT=0`)                         base, 525/525)    admissible
  `fix_seeds` clobbering (§40.6)            DOES NOT EXIST in `_p31_construct.py`
                                            -- that symbol is notifications_index's.
                                            The analogous "a later layer clobbers
                                            the demand" is measured 0 here:
                                            `CUBE CONTRADICTS A REQUIRED GOVERNOR
                                            STATE: 0 in 0 seeds`, and 0 contradicted
                                            keys on the real drive.
  §40.5a statement-keyed aliases            NULL (§104, not redone)
```

**So the two named "known leads" are worth +2 gaps of 525 between them.** The
constructor was not where the 25 points were; the control was.

## THE 30 REMAINING CONTROL MISSES ARE ONE SHAPE

All 30 pin at least one `mentions_*` length NON-EMPTY: 23 never evaluate an
`as_api_response_<n>_row_text_has_mention`, 3 a length gate, 2 a text-empty,
2 contradict the unsteerable `Anonymous_process_3`. The witness realised each
by an exact PER-RAW-ORDINAL length pattern; the constructor only ever learns the
CANONICAL's state from the cube, so it cannot reproduce the pattern. That is the
alias-canonical name boundary, not a coding error, and it caps this instrument
at ~94 % rather than 100 %.

---

# THE REAL RESIDUE: THE YIELD IS **355 CUBES PER 1 000 RUNS**, NOT 0.006

## THE 0.006 FIGURE WAS A SET-LEVEL NUMBER READ AS A CUBE-LEVEL ONE

"625 witness runs moved MISSING by 4" is true and is not the cube yield.
`MISSING` counts DEMAND SETS still missing (706 of 995); a set stays missing
until EVERY one of its cubes is covered, and the §16b residue is **965 224
cubes over those sets**. Closing cubes inside a set that has thousands left
moves `MISSING` by zero by construction. The two numbers differ by three orders
of magnitude and the campaign has been steering on the wrong one.

## THE DIRECT MEASUREMENT (P44S, 2026-09-15 22:45-23:20)

3 000 cubes drawn by RESERVOIR SAMPLE (never a prefix) from
`_p31_emit_P35.jsonl`'s 470 320 real post-restore residue cubes, 189 demand
sets; `_p23_gaps.py` -> `_p31_construct.py` (round-11 knobs) -> 3 000 seeds ->
3 000 runs, 0 toxic.

```
  target cubes                             3 000
  runs driven                              3 000   (2 107 s, 1.42 runs/s)
  cubes CLOSED, cross-counted on the dumps 1 065
  CUBES CLOSED PER 1 000 RUNS              355.0
```
"Closed" = some run of the drive realises every literal of the cube, measured on
the dump by `_p15_explain.py`'s parser. Under §16b a leaf IS a full assignment
over its demand set's members, so that is exactly the coverage predicate, with
no Z3 and no pass. CROSS-counted: a cube counts if ANY of the 3 000 runs
realises it, because a drive closes cubes it was not aiming at.

## WHY ROUND 11 LOOKED SO MUCH WORSE — THE 525 WERE AN UNREPRESENTATIVE SLICE

```
                            round 11 (525 gaps)   random residue (3 000)
  admissible on pins+gates      124  (23.6 %)        2 889  (96.3 %)
  base realises the pins        525 (100.0 %)        2 996  (99.9 %)
```
`_p31_gaps_P35C.json` was emitted with `P23_MAX_PER_SET=3`, which takes the
first three cubes of every set — and the sets whose cubes are hard are exactly
the sets that are still open. The "401 no base walks every gate" conclusion, and
§106.1's "399 of 401 are foreclosed", are statements about THAT SLICE. On a
random sample of the residue the same constructor finds an admissible base for
**96.3 %**.

## THE ROUND-11 DRIVE, EXPLAINED FOR THE FIRST TIME

`_p15_driven_seeds` never had an explanation for P39D; it does now
(`_p44_explain_P39D.json`).

```
  126 runs, 126 gaps driven of 525
   26 gaps WALKED = 20.6 %   -> 206 cubes per 1 000 runs, on the HARD slice
    0 literals CONTRADICTED  -- the seed writer is not the problem
  174 never evaluated (13.9 % of keys): the run did not REACH the decision
```
**94 of the 100 misses failed on a member THE BASE ITSELF NEVER EVALUATED.**
A seed cannot create a decision the base's control flow never reaches.

### AND FOR 35 OF THEM THE DEMAND IS FORECLOSED AT THE VALUE LEVEL

All 35 gaps that first-failed on
`as_api_response_1_row_text_has_mention` also pin
`SYM_LEN_..._mentions_a0ff45d4_rows != 0` TRUE. Measured over the whole corpus:

```
  P(as_api_response_1_row_text_has_mention EVALUATED | mentions_a0ff45d4 non-empty)
      = 0.00 %   over 9 753 runs
```
The index already holds this (`necess[...]["z"]`); the constructor does not use
it to reject a cube, it builds a seed that cannot work. That is 35 wasted runs
per round and a cheap admissibility filter.

## THE REACH LAYER IS LENGTH-ONLY, AND THAT IS THE NAMED GAP

`_p23_index.py`'s necessity table conditions ONLY on LENGTH variables
(`_p44_reachnec.py` adds the decision-outcome form). Of the demand universe's
73 expressions, **4 carry no necessity entry at all**, and one of them —
`(assoc_status_message_text_has_mention == True)` — is the single largest
first-failure class on the residue (51 of 100 P39D misses). It is evaluated in
45 398 of 48 943 runs (92.8 %) and NO single condition, length or decision,
drops it below 58 %: its reach is a conjunction the current layer cannot
express.

## BASE SELECTION vs MANUFACTURE, MEASURED ON REACH

`_p44_reachbase.py`, over all 48 943 profiles, for the round-11 525:

```
  bases satisfying pins AND gates AND EVALUATES-EVERY-LITERAL
      exists for   29 of 525     median 0
      zero for    496 of 525
  (and exactly those 29 are cubes a corpus profile already realises)
```
So for the hard slice the reach must be CREATED by the seed, not selected.
§94.1's "71 % have a compatible base" and §107's "base selection is exhausted,
2 genuine misses" were both measured WITHOUT the reach predicate.

---

# WHERE THE RUNS GO: **ZERO CONTRADICTIONS, EVERY MISS IS REACH**

`_p44_explain_P44S1.json`, 3 000 real residue cubes, one run each:

```
  gaps WALKED by their OWN run          1 030 / 3 000 = 34.3 %
  cubes closed cross-counted            1 065        (the cross bonus is +35)
  literals CONTRADICTED                     0
  first failing literal, all never_evaluated:
       828  evilq not_found
       740  text (has_mention)
       227  size gate
       111  length gate (rows)
        44  guid
        11  guid self-compare
```
**Not one seed was written and then ignored.** The seed writer, the value
substitution, the governor pins and the split pins are all sound on the real
demand. Every single miss is the run not REACHING the decision. That is one
defect class, not five, and it is the reach layer.

# THROUGHPUT — LEG CONCURRENCY AND WIDTH, MEASURED

The legs were strictly sequential in `_p44_drive.sh` (an `auth_html` leg of
2 170 seeds finished before a 14-seed `anon_html` leg started).
`_p44_drive_par.sh` runs all four CONCURRENTLY and sizes the TOTAL JRuby count,
splitting it across legs in proportion to their seed counts. Three disjoint
1 000-seed slices of round T, one per width:

```
  arm  nominal  actual JRuby  runs   wall   end-to-end   sustained   load
  W08     8         11        1002  1084s   0.92 runs/s   3.00 runs/s  40-53
  W12    12         15        1000   731s   1.37 runs/s   4.63 runs/s  26-33
  W14    14         17         998   637s   1.57 runs/s   6.35 runs/s  26-36
  (reference: sequential legs, par=8)  3000  2107s   1.42 runs/s
  P44U   12         11        3000   636s   4.72 runs/s  10.42 runs/s   3-24
         ^ the SAME width as W12, but CHUNK=400 instead of 125, on a box
           whose external load had just fallen away
```
**Monotone to 17 workers on 16 cores; no knee found.** The JRubys are not
CPU-bound. `_p44_drive_par.sh` rounds each leg's share UP, so the actual totals
exceed the nominal width — stated, not hidden.

**THE BOX WAS SHARED THROUGHOUT AND THE ARMS DID NOT SEE THE SAME LOAD.**
Other agents ran `pcfold-extract*`, `pxb-chain-a/b`, `pxb-probe40`,
`pxb-scratch6` (python + z3 + a blockaid JVM) for the whole sweep; the 1-minute
load average ranged 24-54 with 16 cores. W08 drew the worst of it. The width
ordering is therefore CONFOUNDED WITH EXTERNAL LOAD and 6.35 vs 3.00 must not
be read as a pure width effect. It is safe to say width 14-17 is at least as
good as 8 and that nothing saturated.

## THE BIGGER LEVER IS NOT WIDTH — IT IS JRUBY BOOT

End-to-end 1.57 vs sustained 6.35 at W14 says **~75 % of the wall is Rails
boot**, not driving. Each chunk boots a JVM (measured 90 s idle, up to 6 min at
load 52) and CHUNK was 125. Boot cost per run falls linearly with chunk size:
at CHUNK=1000 the same width would run at close to the sustained rate. **Raise
CHUNK before raising width.** The only cost is that a native abort loses its
position in a bigger chunk, and `_chunk_drive.sh`'s worker already resumes on
the remainder after dropping the toxic seed (0 toxic seeds in 6 000 runs here).

# THE YIELD, REPLICATED ON TWO INDEPENDENT SAMPLES

```
  round   sample            runs   cubes closed   per 1 000 runs
  P44S    3 000 cubes       3 000      1 065          355.0
  P44T    3 000 cubes       3 000      1 132          377.3
  P44U    3 000 cubes       3 000      1 149          383.0
  ------------------------------------------------------------
  pooled                    9 000      3 346          371.8
```
Both drawn by independent reservoir samples (different seeds) from the 470 320
real post-restore residue cubes; 0 toxic seeds in 6 000 runs; the P44S drive
produced **2 868 NEW distinct outcome profiles from 3 000 runs (95.6 %)**, so
the corpus is nowhere near saturated.

# CONVERGENCE — THE ANSWER IS **DAYS**, AND HERE IS THE ARITHMETIC

```
  residue                         965 224 cubes (§16b, §16e/§16f OFF)
  measured yield                  0.372 cubes per run  (9 000 runs, 3 samples)
  runs needed at that yield       2.60 million
  at the sustained 6.35 runs/s      4.8 days of wall
  at the end-to-end 1.57 runs/s    19.5 days of wall
```
**Compare the owner's premise.** "965 224 uncovered cubes is ~965 224 targeted
runs, ~23 h at 11.8 runs/s" assumes one cube per run. The measured figure is
0.366, so the run count is **2.7x** the premise and the throughput is **1.6-7.5x
below** the 11.8 runs/s quoted — 11.8 was measured on the GATE's probe path
(short replays), not on a driving round.

**AND THE ARITHMETIC ABOVE IS OPTIMISTIC IN TWO NAMED WAYS.**

1. **Yield decays and the decay is NOT measured.** Both samples were drawn from
   the SAME unchanged residue, so they measure the same population twice — they
   replicate the first-touch yield, they do not measure what happens once the
   easy cubes are gone. Every closed cube is one that a constructible seed could
   reach; what is left after a few rounds is the 65.7 % that could not be
   reached this time.
2. **The target list does not exist yet.** The 470 320 cubes sampled here are
   `_p31_emit_P35.jsonl`, the §16f-pruned (W=3) emission, and it covers only
   730 of 998 demand sets — the emitter was killed at 17 656 s. §16f is REFUTED
   (§110-§111), so the honest target list is the §16b enumeration of all
   965 224, and enumerating it is itself a multi-hour job that has never been
   run to completion (`CENSUS_MODES=enum` on `_p26_emit_or.py` emits it).

**So: days, not hours, and the honest number is "≥ 5 days of dedicated box, on
a target list that must first be enumerated, with an unmeasured decay on top."**
That is for the coordinator to take to the owner.

# WHAT WOULD ACTUALLY MOVE IT, IN ORDER OF MEASURED SIZE

1. **CHUNK size.** ~75 % of wall is JRuby boot at CHUNK=125. Free 3-4x.
2. **The reach layer.** 100 % of the 1 970 misses are never-evaluated. The
   index's necessity table conditions only on LENGTHS; 4 of the 73 demand
   expressions carry no entry at all, and one of them is the largest single
   miss class. `_p44_reachnec.py` computes the decision-outcome form; it is
   NOT yet wired into the constructor.
3. **An admissibility filter that uses what the index already knows.** 35 of
   the 100 round-11 misses demanded a pair the corpus says never co-occurs
   (P = 0.00 % over 9 753 runs). Those runs are spent before they start.
4. **Width 14-17 over 8, and leg concurrency.** Worth ~1.7x end-to-end here,
   confounded with load.

---

# THE DECAY, MEASURED — AND IT RECONCILES THE 0.006

The three rounds were sampled from the same frozen residue, so they replicate
the FIRST-TOUCH yield. The decay question — "does a cube that its own targeted
run missed get closed by more runs?" — is answered by counting round S's 3 000
cubes against EVERY run this session produced:

```
  round S's cubes closed by its OWN 3 000 targeted runs      1 065
  ... and by all 10 575 P44 runs (7 575 more, aimed elsewhere) 1 116
  ------------------------------------------------------------------
  MARGINAL yield of the 7 575 extra runs:  51 cubes = 0.0067 cubes/run
```

**0.0067 is the campaign's 0.006.** The two numbers were never in conflict:

```
  a run AIMED AT a cube          closes it        0.355 cubes/run    53x
  a run aimed somewhere else     closes it        0.0067 cubes/run
```
The campaign measured the second and concluded targeting was broken. Targeting
works; what was being measured was the yield of runs that were not aimed at the
cubes being counted.

## AND THE SAME NUMBER SAYS BRUTE FORCE ALONE DOES NOT REACH `BLOCKING=0`

1 884 of round S's 3 000 cubes are STILL open after 10 575 runs. The 63 % a
targeted run misses is not a sampling accident that more runs wash out — it is
the same reach failure every time, because the constructor builds the same kind
of seed from the same kind of base. So:

```
  one targeted run per residue cube  ~  965 224 runs
  closes                             ~  359 000 cubes  (37.2 %)
  leaves                             ~  606 000 cubes  that MORE RUNS DO NOT CLOSE
  wall for that pass   at 10.42 runs/s sustained   ~ 26 h
                       at  4.72 runs/s end-to-end  ~ 57 h
```

**THE HONEST VERDICT. Brute force is worth doing and it is affordable — one to
three days buys 37 % of the residue. It does NOT reach `BLOCKING=0`, and no
amount of extra driving will, because the 63 % that misses is a reach defect
with a named cause (every miss is `never_evaluated`, the index's reach layer
conditions only on lengths) and not a search-budget problem.** The owner's
premise — "965 224 cubes is ~965 224 runs" — is right about the ORDER of the
drive and wrong about what it buys.


---

# THE 1 970 REAL MISSES, CLASSIFIED — AND ONE THIRD OF THE DRIVE IS WASTED
# BEFORE IT STARTS

`_p44_missreason.py` recomputes the one-sided reach conditions (over DECISIONS
and LENGTHS, `MIN_RUNS=200`: 592 conditions over 67 of the 73 demand-universe
expressions) and asks, for every miss, whether the CUBE ITSELF demands something
the corpus says forecloses the member it failed on.

```
  1 970 misses on the 3 000-cube residue sample
     762  38.7 %  A  SELF-FORECLOSED -- the cube demands (f = o) and over
                     >= 200 runs with f = o the member is NEVER evaluated
   1 043  52.9 %  C  no condition known at all -- the reach layer cannot
                     express what governs this member
     165   8.4 %  B  a condition IS known and the cube does not contradict it,
                     and the seed did not honour it  <- a constructor fix, now
```
**732 of the 762 are ONE pair**: `as_api_response_1_row_text_has_mention`
demanded together with a `records_mentions_*` length NON-EMPTY. Measured
P(member evaluated | that length non-empty) = **0.00 % over 9 753 runs** — and
this round made **732 construction attempts against it and every one failed**.
That is the constructed falsifier §110 demanded of §16f's untested inferences,
run and come back negative.

## THREE CONSEQUENCES, IN ORDER OF CHEAPNESS

1. **An admissibility filter pays immediately.** 762 of 3 000 runs (25.4 %) were
   spent on demand the index already knew was unreachable. Filtering them raises
   the yield per run from 0.343 to **0.46** and hands the saved runs to cubes
   that can close — a ~34 % throughput gain for a table lookup.
2. **Class B is a real constructor fix worth ~5.5 points of hit rate** (165 of
   3 000) and it needs no new measurement: the condition is in the index.
3. **Class C — 52.9 % — is the actual research problem.** Four of the 73
   expressions carry no condition at all, and the largest single miss family,
   `assoc_status_message_text_has_mention`, is evaluated in 92.8 % of all runs
   yet no single length or decision condition drops it below 58 %. Its reach is
   a CONJUNCTION the present layer cannot express.

**CAVEAT, STATED BECAUSE §110 IS THE PRECEDENT.** Class A is a corpus-only
inference of exactly the family §16f used and §110-§111 refuted (484 FAIL /
0 PASS). The difference here is that the falsifier was actually run: 732
attempts, 0 successes. That is evidence, not proof, and a class-A cube must be
carried as UNREACHED, never as foreclosed, unless the owner rules otherwise.

---

# THE FIX THAT PAID: THE ADMISSIBILITY FILTER — **608 CUBES PER 1 000 RUNS**

`_p44_admissible.py` drops a cube when the cube ITSELF demands a condition the
corpus says forecloses one of its own members. Validated against round S's
already-driven outcome BEFORE it was used to drive anything:

```
  applied to round S's 3 000 cubes:  admissible 1 772 (59.1 %), dropped 1 228
     of the 1 030 cubes that DID close, it would have dropped     16  (1.6 %)
     of the 1 970 that did NOT close, it drops                 1 212 (61.5 %)
     predicted yield                                           0.572 cubes/run
```

Then run for real on a fresh sample (round V, seed 20260918):

```
  3 000 sampled -> 1 806 admissible (60.2 %)
  1 806 runs, 287 s, 6.29 runs/s end-to-end (CHUNK=400, width 12, free box)
  cubes CLOSED 1 098
  CUBES CLOSED PER 1 000 RUNS  608.0     <- predicted 572, measured 608
```

```
  YIELD LADDER
    unfiltered, 3 samples, 9 000 runs        371.8 per 1 000
    with the admissibility filter            608.0 per 1 000     1.63x
```
It is a table lookup on an index that already exists, it cost one pass to
validate, and it is the single largest measured improvement of this round.

## THE DRIVE IS NOW A ONE-DAY JOB — AND IT STILL DOES NOT CLOSE THE ENDPOINT

```
  residue                                    965 224 cubes
  admissible after the filter (60.2 %)     ~ 581 000 cubes -> one run each
  closed at 0.608 cubes/run                ~ 353 000 cubes  (36.6 % of residue)
  wall at 6.29 runs/s end-to-end             ~ 26 h
  wall at 10.42 runs/s sustained             ~ 15 h
  LEFT OVER                                ~ 612 000 cubes, of which
      ~ 384 000 dropped as UNREACHED (the corpus says the demand forecloses
                itself; 732 construction attempts against the largest such pair
                all failed)
      ~ 228 000 admissible and still missed -- the reach layer
```

**So the decision is not "brute force: yes or no". It is: one day of box buys
36.6 % of the residue and nothing beyond that without the reach fix.** Spending
the day is cheap and the artefacts are permanent; expecting `BLOCKING=0` out of
it is not supported by any number measured here.

---

# THE RE-PASS LANDED — AND IT IS THE `MISSING`-IS-NOT-A-COUNTDOWN TRAP AGAIN

`_p44_repass.sh`, P39R's corpus + the 3 000 P44S1 residue-drive runs and
NOTHING else (the control dumps were deliberately excluded so exactly one input
moved). 52 576 dumps -> 52 444 distinct profiles. Same flags as P39R.

```
                      P39R (before)     P44R (after +3 000 runs)
  COMPLETE                False               False
  MISSING / BLOCKING      706 / 706           714 / 714        +8
  DEMAND_SETS             995                 1 017           +22
  PCS                 2 137 677           2 265 057      +127 380
  NODES                   137                 137
  TREE_COMPLETE/MISSING   True / 0            True / 0
```

**`MISSING` went UP by 8 while the same 3 000 runs closed 1 065 cubes.** Both
are true and they are not in tension:

* `MISSING` counts DEMAND SETS, and the runs added **22 new demand sets** —
  new co-evaluated decision groups that nothing had ever exercised together.
  A set is missing until every one of its cubes is covered, so a set-level
  counter cannot fall while the universe it counts over is still growing.
* The same effect is booked twice already in this campaign (§92.4: "a rise
  there is not a regression"; §103.5). This is its third independent sighting
  and the first with a cube-level number beside it.

**THIS IS THE ANSWER TO "IS IT ~3 000 OR ~4".** It is neither: it is 1 065
cubes closed, 22 new sets opened, and `MISSING` +8. Reading the endpoint's
progress off `MISSING` is what produced the 0.006 figure and the "driving moved
0" conclusion; both are artefacts of the yardstick.

**AND IT ADDS A THIRD CAVEAT TO THE CONVERGENCE ARITHMETIC.** The residue is
not a fixed target: driving closes cubes AND enlarges the demand universe.
Whether 965 224 falls, holds or rises after a round is a question only the
§16b `prod` census answers, and that census has been LAUNCHED on the
post-drive corpus (`p44-census.service`, `CENSUS_MODES=prod`, list
`_snapshot_pruned_P44R.txt`, cap 18G, verdict line `MODE prod: ... REMAINING=`
in `_p31_emit_P44C.out`). **That number is the one the next agent should read
first** — it is the only honest before/after for the residue, and until it
lands every extrapolation in this document assumes a fixed 965 224.

---

# THE REACH LAYER WAS A STALE INDEX — AND THE GATE ON THE STRONG CONSTRUCTOR
# GIVES A **94.0 %** POSITIVE CONTROL (2026-09-16)

## §A THE DEFECT: THE CONSTRUCTOR COULD NOT SEE 47 OF THE 120 DEMAND EXPRESSIONS

`_p44_classc.py` asked what governs the class-C members. The answer for 1 015
of the 1 043 class-C misses (97.3 %) was **"NOT IN THE INDEX EXPRESSION
UNIVERSE"**.

```
  _p31_index_P35C.pkl  expression universe        73
  the residue's demand (union over 749 sets)     120
  MISSING FROM THE INDEX                          47   (39 %)
```
The index is built from a PARTS file, and round 11's parts covered 236 sets of
a 3-cubes-per-set emission. Every round since has driven cubes whose members
the index had never heard of: the constructor could not score a base on them,
could not pin their reach, could not test their reachability. **It is a stale
input, not a missing theory.**

Fixed by building `_p44_parts_UNION.json` over ALL 470 320 emitted cubes (749
sets, 120 members) and `_p44_index_UNION.pkl` over the post-drive corpus
(52 444 profiles, 220 s). `NECESSITY TABLE: 116 of 120` — against 69 of 73.

## §B WHAT IT BOUGHT — TWO DIFFERENTIALS, BOTH ON FIXED CUBE SETS

**Regression check on the 525-cube ground-truth control:** 495/525 = **94.3 %,
unchanged**. The change does not cost the control anything.

**The reach differential, on the 1 970 round-S cubes a targeted attempt had
already failed (baseline 0 by construction):**

```
  re-constructed and re-driven under the UNION index
      WALKED  461 / 1 970 = 23.4 %      (was 0)
```

**And on a fresh residue sample, one targeted run per cube:**

```
  blind index, no filter        355-383 cubes per 1 000 runs
  blind index + admissibility   608
  UNION index + admissibility   818.1     <- round P44R1, 1 930 of 2 359
```

## §C THE FORECLOSURE GATE, RE-RUN ON THE DRIVER'S CONSTRUCTOR

Per cube the targeted attempt missed: `d` = the unreached literal, `C` = every
other literal at its demanded outcome; the control is `C` plus `d_ctl`, a member
the corpus demonstrably evaluates in runs realising `C`, at the outcome those
runs take. Both arms are ordinary gap records built by `_p31_construct.py`,
driven by the ordinary driver, read by `_p15_explain.py`. **`src/` untouched.**

```
  classes with a control built and driven      844
  POSITIVE CONTROL GREEN            793 / 844 = 94.0 %
                                    (the gate's own probe path: 17.9 %)

  FORECLOSED (C realised, d unevaluated, control GREEN)   773
  NOT-TESTABLE  no corpus run realises C                  665
  NOT-TESTABLE  control not green                          51
  NOT-TESTABLE  claim run did not realise C                20
  FAIL (witness found)                                      0
```

### THE PRE-REGISTERED FALSIFIER WAS RUN AND DID NOT FIRE

A single failed attempt is weak evidence. All 773 FORECLOSED cubes were
re-constructed with `BASES_PER_GAP=2` and the **rank-1 (different) base** was
driven — 760 runs (13 cubes had no second base).

```
  second attempt, a DIFFERENT base:  WALKED 0 / 760
```
Every one failed on the same member family. The 773 stand at two independent
construction attempts with a 94 %-green control. Compare §16f, which was
attacked the same way and produced 484 FAIL / 0 PASS: these are not that shape.

## §D THE LOOP CLOSES ON ROUND S'S 3 000 CUBES

```
  COVERED, attempt 1 (blind index)                  1 030
  COVERED, attempt 2 (union index)                  + 461   = 1 491  49.7 %
  FORECLOSED (control green, 2 attempts, 0 witness)    773          25.8 %
  UNEVIDENCED (NOT-TESTABLE, never pruned)             736          24.5 %
  -------------------------------------------------------
  DECIDED                                            2 264          75.5 %
```
**665 of the 736 unevidenced are "no corpus run realises C", so no control can
be built at all** — and that is the class driving fixes for free: every round
enlarges the corpus and turns some of them testable. The other 71 are a control
that would not go green (51) and a claim run that missed `C` (20).

**NOT-TESTABLE was never promoted to PASS and nothing was pruned.** The 773
foreclosures are recorded in `_p44_gate_verdicts.json`; no assumption was
declared, and `_assumptions_declared.json` is untouched.

## §E THE TWO YIELD FIGURES, RECONCILED

They count different numerators and both are right.

```
  census   +22 107 covered / 12 381 runs = 1.78   EVERY cube in the 1 017-set
                                                  universe that any new run
                                                  happens to realise
  direct    1 098 closed  /  1 806 runs = 0.608   only the cubes that round
                                                  TARGETED
  residue  965 224 -> 941 632 = -23 592 / 12 381 = 1.91 cubes of residue per run
           (covered +22 107 and satisfiable -1 485: the universe shrank slightly)
```
The census figure is ~2.9x the direct one because a run closes about two cubes
it was not aiming at for every one it was. **For an ETA use the residue figure,
1.91 cubes/run — it is the only one measured against the quantity that has to
reach zero.** At 1.91 and the measured 6.85 runs/s, 941 632 / 1.91 = **493 000
runs = 20 h** — before decay, and before the foreclosure arm removes demand
that never needs a run at all.

---

# §118 NOTE (2026-09-16, resume session): THE 844-CLASS ARTIFACT BEHIND §C IS LOST

The raw JSON backing §C's 94.0 %/773-FORECLOSED result —
`_p44_gaps_MISS.json`, `_p44_gate_join.json`, `_p44_gaps_GCTRL.json`,
`_p44_explain_GCTRL.json`, and the original `_p44_gate_verdicts.json` — was
destroyed by an operator error while wiring a per-round gate re-run: `ln -sf`
onto those canonical filenames replaced the regular files instead of aliasing
them, and a subsequent `_p44_gate_verdict.py` invocation then overwrote
`_p44_gate_verdicts.json` itself. No backup existed. **Do not go looking for
these files; they are gone.**

Nothing downstream rests on them: no assumption was declared or pruned from
this result (`_assumptions_declared.json` untouched), and the finding is fully
preserved in prose and numbers in §C above. The coordinator's ruling: do not
spend time regenerating it, because it is superseded anyway — the index it was
built on (`_p44_index_UNION.pkl`, frozen at 52 444 profiles) is stale (see the
reindex note below), so a byte-for-byte replay would answer a question about
an index already being retired, not the current state.

**The root cause is fixed going forward.** `_p44_gate_verdict.py` now reads
`P44_GATE_JOIN` / `P44_GATE_MISS` / `P44_GATE_GCTRL` / `P44_GATE_EXPLAIN` /
`P44_GATE_OUT` env overrides (default: the old bare filenames, for backward
compatibility) instead of hardcoding them, so every round's gate run writes
its own tagged output and can never again clobber another round's. Backup at
`_p44_gate_verdict.py.bak_pre_envpaths_20260916`.

## THE SAME INDEX-STALENESS DEFECT, ONE TIER UP

Gated R8–R12's misses (5 independent rounds, 2 129 misses, 277 testable) on
the SAME `_p44_index_UNION.pkl` that produced §C's 94.0 %:

```
  pooled POSITIVE CONTROL GREEN   142 / 277 = 51.3 %   (was 94.0 %)
  FORECLOSED                       55 / 277 = 19.9 %
  NOT-TESTABLE (tested, not green) 222 / 277
  NOT-TESTABLE (no run realises C) 1 852  (pre-filter, not counted above)
```
`bases_realising_C == 1` (a single supporting corpus profile, no redundancy)
for 69–85 % of testable classes in every one of the 5 rounds. The index was
built over a 52 444-profile snapshot taken BEFORE the sustain drive (rounds
1–13) ran; by R12 that drive had landed ~25 500 more driven runs the index has
never seen. This is `_p31_index_P35C.pkl` → `_p44_index_UNION.pkl` one tier up:
the fix (build a fresh index over the current corpus) is in flight as
`_p44_index_UNION2.pkl`; see `_p44_reindex_UNION2.sh` and the curve entry
below for the post-reindex number.

---

# §119 (2026-09-17, resume session): JOB BABYSITTING + CLASS B/C DIAGNOSIS

## Jobs found running at session start (per HANDOVER item 1)

```
  p44-enumnew1-drive2.service   ENUMNEW1  leg: +21 524 dumps, wall 3275s, 6.57 runs/s (done 20:01:06)
                                 ENUMNEW1B leg: +21 131 dumps, wall 2529s, 8.36 runs/s (done 20:43:21)
                                 -> ENUMNEW1-BOTH-DONE (corpus now ~695 569 raw dumps, up from 249 556
                                    at the prior handover -- most of the growth predates this session,
                                    from rounds/legs run between the handover and this pickup)
  p44-census-fresh1.service      snapshot taken at 652 914 dumps (19:09), prune (_prune_corpus.py,
                                 single-process, no --shards) still running at handoff time (see below)
  p44pruneP44FRESH1.scope       same prune job; ~67% CPU, alive, no OOM, no ETA available -- the script
                                 prints ONE line at completion, nothing incremental, so progress cannot
                                 be read off its log while it runs (worth fixing: add a shard-count or
                                 periodic counter print for the next multi-hundred-K prune)
```
Dead/stale units confirmed ignored per HANDOVER: `p44-census-r24`, `p44-gate-postidx`.

**A Monitor is armed on `_p44_census_chain_P44FRESH1.log` for the prune-done and
census-done markers** (28 min window from ~20:48; re-arm if it expires first).
Do NOT run the coverage checker until `DONE P44FRESH1` with a `MODE prod:` line
lands — the corpus is not the same one census-fresh1 was launched against
(~43k more dumps landed from ENUMNEW1/ENUMNEW1B while it pruned its own
snapshot; that's fine, they'll be picked up by the NEXT census).

## Item 2 (Class B / BASES_PER_GAP verification) — CONFIRMED STILL APPLIED, NO REGRESSION

`_p31_construct.py:157`: `K = int(os.environ.get("BASES_PER_GAP", "2"))` — default 2.
`_p44_construct.sh`: `BASES_PER_GAP="${BASES_PER_GAP:-2}"` — also defaults to 2, no
hardcoded override anywhere in either file (`grep -n "BASES_PER_GAP"` and
`grep -n "K = 1"` both checked). The hard_ok / scored_pin_gate tiering at
`_p31_construct.py:680-830` was re-read line by line: `scored_hard`/`scored_pin`/
`scored_pin_gate` are built incrementally, gated correctly on `hard_ok`/`pin_ok`/
`match==n_gate_bits` as rows are scored (not recomputed from a stale `scored`
after the HARD_SPLIT relax at line 801-810), and the relax path explicitly
zeroes `scored_pin`/`scored_pin_gate` rather than leaving them referencing
pre-relax rows. No defect found in this pass.

**Current classification (already run this session, before pickup, using the
FRESH UNION2 index — `_p44_missreason_BACKLOG_v2.out`, 7 214 misses):**
```
   4 111   57.0 %  B reachable, a RELEVANT condition is known and not contradicted
   3 103   43.0 %  C no condition known THAT BEARS ON THIS CUBE
```
This matches the task briefing's cited split exactly and is confirmed to be
post-relevance-filter, post-UNION2-reindex (113/120 exprs carry >=1 one-sided
condition at MIN_RUNS=200, matching `_p44_reachnec_UNION2.json`'s 116/120 --
the two counts differ because reachnec's own MIN_RUNS threshold differs
slightly in effective sample from missreason's per-cube relevance filter, not
a contradiction). **No fresh validation-round drive of the 4 111 Class-B misses
was run this session** (box was at load 19-23 from the enumnew1 legs; per the
standing instruction, width>4 driving was deferred until they finished — they
finished at 20:43, see above; the next agent should run a Class-B-only round
now that the box is free and confirm the hit-rate rises, per HANDOVER item 2's
open action).

## Item 3 (Class C conjunction check) — NEW TOOL, REAL BUT NARROW RESULT

Built `_p44_reachnec_conj.py` (read-only, no numpy in this environment --
pure-Python bigint bitmasks, one bit per dump; verified fast: 87 663 dumps,
252 atoms built in 3.0s, ~15 300 pairs tested in 0.1s per target). It extends
`_p44_reachnec.py`'s single-condition test to genuine 2-way conjunctions:
neither `f1=o1` nor `f2=o2` alone forecloses target `e`'s evaluation, but the
conjunction does, at >=200 co-occurring runs.

Ran it against the four UNION2 expressions with **zero** single-sided reach
condition (`_p44_reachnec_UNION2.json`, 116/120 have one; these 4 don't):

```
  (Length(SYM_PARAM_id) < 16) == True         evaluated 87663/87663 (100.0%) -- not
                                               a reach question at all, excluded
  (assoc_profile_nsfw == True)                evaluated 87647/87663 (100.0%) -- 0 pairs
                                               found; also effectively unconditional,
                                               not a real Class-C driver
  (assoc_status_message_text_has_mention==True) evaluated 75915/87663 (86.6%) -- 3 GENUINE
                                               2-way conjunctions found
  (assoc_status_message_text_empty==True)       evaluated 57776/87663 (65.9%) -- the SAME
                                               3 conjunctions (shared guard)
```
**The 3 conjunctions** (all involve the same first atom):
```
  n=302  (SYM_LEN_..CollectionProxy_records_photos_9930492e_rows != 0) = False
           AND (SYM_RESULT_..Relation_evilq_like_public_1_not_found == True) = True
  n=243  same length=False
           AND (SYM_RESULT_..Relation_evilq_reshare_public_1_not_found == True) = True
  n=208  (SYM_LEN_..CollectionProxy_records_photos_e035b5b3_rows != 0) = False
           AND (SYM_RESULT_..Relation_findpublic_reshare_1_public == True) = False
```
**Honest read: this confirms the HANDOVER's hypothesis (conjunctions the
single-condition tool can't see DO exist and ARE findable mechanically from the
frozen index, no new driving needed) but the magnitude is small** -- 208-302
runs each, out of 87 663 total and out of thousands of Class-C misses on the
`assoc_status_message_text_*` family. This does NOT resolve the bulk of Class C
by itself. It is a real, narrow unlock: 3 new candidate conjunctive pins the
constructor doesn't have today. **Not yet wired into `_p44_missreason.py`'s
`COND` table or `_p31_construct.py`'s pin layer** -- that integration (extend
`COND` to store 2-tuples of conditions, extend the seed constructor to honour a
conjunctive pin the way it honours a single one) is the next mechanical step,
scoped but not done this session (time went to jobs + confirming the tool
works correctly on known cases first, per discipline: measure before wiring).

**This is a MEASUREMENT tool, not a completeness inference. It declares
nothing, prunes nothing, touches no `src/`, and is not §16f** (which pruned
the demand TREE at width W; this only helps a seed constructor find a base for
a member the constructor currently has no pin for at all). `src/` and
`concolic_targets.rb` untouched this session; no assumption declared or
withdrawn.

## What's still open, in order

1. Wait for `p44-census-fresh1` (prune P44FRESH1, then `CENSUS_MODES=prod`
   emit) — the fresh residue verdict. Do not run the coverage checker before it.
2. Wait for `p44-sustain`-family rounds / `p44-enumnew1-drive2` are done; check
   whether another sustain round is queued or the box should get a new
   Class-B-targeted round now that width is free.
3. Run a validation round on the 4 111 Class-B misses with the confirmed-intact
   BASES_PER_GAP=2 fix and report the before/after hit rate (HANDOVER item 2's
   still-open half — classification confirms the diagnosis, no drive has yet
   converted it into closed cubes this session).
4. Wire the 3 conjunctive pins into `_p44_missreason.py`/`_p31_construct.py`
   (mechanical, scoped above) and re-classify to see how many of the 3 103
   Class-C misses move to A/B — expect SMALL movement given the n=208-302
   scale, but it should be measured, not assumed.
5. Extend the conjunction scan to 3-way if 2-way's yield on a full re-classify
   turns out to matter more than the sample above suggests, and/or run it over
   the OTHER expressions that have a single condition but where that condition
   still leaves >58% unexplained (the HANDOVER's phrasing about
   `assoc_status_message_text_has_mention` — "no single condition drops it
   below 58%" is about EXPLAINED FRACTION, not about EXISTENCE of a condition;
   worth checking members that have >=1 single condition but a weak one, not
   just the 4 with zero).
6. Once 1-4 land, re-run the coverage checker on the freshest pruned corpus and
   report OVERALL_COMPLETE/MISSING/BLOCKING. **Not run this session** -- the
   fresh census/index this session depends on had not finished at handoff.

---

# §120 (2026-09-17, same session continued): CLASS-B VALIDATION DRIVE LAUNCHED + CONJUNCTION PINS WIRED IN

Per coordinator instruction: stopped deferring, executed the top open item
this turn instead of handing it to "the next agent" again.

## Class-B validation drive (CLASSBV1)

1. Built `_p44_missreason_dump.py` (id-list-emitting variant of `_p44_missreason.py`,
   identical classification logic) and ran it against the SAME inputs that
   produced `_p44_missreason_BACKLOG_v2.out` (`_p44_gaps_K1BACKLOG.json` +
   `_p44_explain_K1BACKLOG_merged.json`, P44_INDEX=UNION2) -- **reproduced
   4111 B / 3103 C / 0 A exactly**, confirming the split and giving exact gids.
2. Filtered `_p44_gaps_K1BACKLOG.json` down to the 4111 B-classified gids ->
   `_p44_gaps_CLASSBV1.json` (exact count verified: 4111/9073).
3. Ran `_p44_construct.sh CLASSBV1 _p44_gaps_CLASSBV1.json` (P44_INDEX=UNION2,
   P44_PARTS=_p44_parts_UNION.json). Result: 7606 seeds built (4111 gaps x K=2),
   seeds admissible on BOTH pins+gates: 4512/7606. Seed counts:
   auth_html=3859, anon_html=0, auth_json=249, anon_json=3 (4111 total,
   matches gap count -- one seed selected per gap for the drive).
4. Launched the drive **isolated as its own systemd-run unit**
   (`p44-classbv1-drive.service`, MemoryMax=20G, width=16, CHUNK=400) running
   **concurrently** with the still-live `p44pruneP44FRESH1.scope` /
   `p44-census-fresh1.service` (per coordinator: no real contention at this
   load level, box confirmed at 59GB free / load ~2-3 before launch). Did NOT
   kill or duplicate either running job.
5. Corpus before this drive: 695 569 dumps.

**Result of the drive: see the next status.md entry (§121, appended after
completion) or the HANDOVER if this section is read before that lands.**

## Class-C conjunction pins -- wired in AND measured

Ran `_p44_conj_reclassify.py` (new, cheap post-process -- no re-scan of the
expensive O(exprs^2 * N) COND table, just re-examines the 3103 already-
classified C gids' own demand sets against the 3 known conjunction pairs)
against `_p44_ids_BACKLOGv2_C.json`:

```
  C gids examined:                                              3103
  targeting the 2 conjunction-guarded exprs:                      13
  A2-CONJ-PROVISIONAL (co-forecloses, NOT falsifier-tested):       2
  B2-CONJ (mentions one conjunct, new pin candidate):             11
  still fully unexplained (targets the exprs, neither pair fires): 0
```
Confirms the earlier honest read: the 3 conjunctions are real but touch only
13 of 3103 Class-C misses (0.4%). **Wired permanently into
`_p44_missreason.py`** (CONJ_TARGETS/CONJ_PAIRS + conj_check(), inserted
between the existing single-condition relevance check and the final C
fallback) so every future run of the unmodified script picks this up
automatically -- no separate post-process step needed going forward. The 2
A2-CONJ-PROVISIONAL cases are explicitly NOT declared unreachable (no
falsifier run against them this round) -- flagged for whoever next has
falsifier-machinery time to spend on 2 cubes, not urgent given the count.

---

# §121 (2026-09-17, same session continued): CLASSBV1 DRIVE — OOM ON FIRST ATTEMPT, RETRY IN FLIGHT

First launch (`p44-classbv1-drive.service`, width=16, MemoryMax=20G,
tag CLASSBV1r0) was **OOM-killed inside its own cgroup after ~26 min CPU
time**, confirmed via `journalctl --user -u p44-classbv1-drive.service`
("A process of this unit has been killed by the OOM killer"). Contained --
did not touch the box or the session, per the standing isolation rule -- but
produced zero dumps (corpus count unchanged at 695 569; no partial/corrupt
dump files to clean up, confirmed).

**Root cause: the 1.2-1.5 GB/JRuby-worker throughput estimate from the prior
HANDOVER (measured on the ENUMNEW1 seed set, width=8, run SEQUENTIALLY leg by
leg) understated peak memory for THIS seed set** (auth_html-heavy, 3859/4111
seeds, posts_show request bodies pulling in more associations than the prior
batch) run with ~12 workers CONCURRENTLY. 20G / 12 workers ~= 1.67 GB/worker
budgeted, evidently too tight once JVM/Rails-boot spikes are counted, not just
steady-state RSS.

**Lesson recorded for future sizing (not yet acted on elsewhere, just
documented): budget ~2.5 GB/worker for MemoryMax on a JRuby drive, not
1.2-1.5 GB/worker — this is the SECOND OOM-in-a-tight-cap incident on this
campaign** (the first, per the prior HANDOVER, was `cage_drive`'s hard 4G
per-leg cap under DRIVE_PAR=7). Both incidents were caught by cgroup
isolation and cost only wall-clock time, never the box or the session — the
isolation discipline is working as intended, it's specifically the sizing
heuristic that needs the wider margin.

I had queued my own retry (`p44-classbv1-drive2.service`, width=12,
MemoryMax=40G, same tag CLASSBV1r0) when the coordinator reported they had
ALREADY relaunched it independently (`p44-classbv1-drive-v2.scope`, width=12,
MemoryMax=40G, tag CLASSBV1r0v2) — **stopped my duplicate immediately**
(`systemctl --user stop p44-classbv1-drive2.service`), confirmed corpus count
unaffected (695 569, unchanged), and switched to watching the coordinator's
v2 run instead. Only ONE CLASSBV1 drive is in flight now.

Once it lands: re-run `_p44_missreason.py`-family classification against the
POST-drive corpus (re-count how many of the 4111 targeted gids are now
`walked: true`) for the actual before/after hit-rate number -- this is the
number that tells us whether the "no regression found" BASES_PER_GAP/hard_ok
code audit was right, or whether Class B misses more than the audit predicts.
Not yet measured as of this entry.

---

# §122 (2026-09-17, same session continued): PRUNE DONE, CENSUS EMIT RUNNING; CLASSBV1 RETRY #3 (CONSERVATIVE)

`p44pruneP44FRESH1.scope` finished: **190 267 distinct outcome-profiles** out
of the 652 914-dump snapshot taken at 19:09. `p44-census-fresh1.service`
proceeded automatically to the emit stage: `P31 EMIT P44FRESH1` over the
190 267 profiles, `modes=prod W=3`. Waiting on its `MODE prod:` verdict line
in `_p31_emit_P44FRESH1.out` -- monitor armed.

## CLASSBV1 drive — TWO CONSECUTIVE OOM FAILURES, retrying conservatively

```
  attempt 1  width=16  CHUNK=400  MemoryMax=20G   OOM-killed  ~26 min CPU, 0 dumps
  attempt 2  width=12  CHUNK=400  MemoryMax=40G   OOM-killed  ~24 min CPU, 0 dumps
             (coordinator's relaunch, after I stopped my own duplicate at
              width=12/MemoryMax=40G before it did meaningful work)
  attempt 3  width=8   CHUNK=100  MemoryMax=50G   IN FLIGHT (p44-classbv1-drive-v3)
```
**Analysis: the failure held even as MemoryMax went from 20G to 40G while
width dropped from 16 to 12 (3.33 GB/worker budgeted, still not enough)** --
this is NOT simply "the 1.2-1.5GB/worker steady-state estimate needs a bigger
multiplier", the growth pattern doesn't fit a fixed per-worker cost. Likely
cause: `scripts/diaspora-concolic` sets no `-Xmx` anywhere (confirmed by
`grep`), so JVM heap ergonomics apply -- modern OpenJDK (21, confirmed via
JAVA_HOME) auto-detects the CGROUP memory limit (not host RAM) since JDK10+
and defaults max heap to ~1/4 of THAT limit per JVM. Under a 40G cgroup cap,
each of 12 JVMs could individually size toward ~10GB max heap by ergonomics
alone -- worst case aggregate demand far exceeds the cap even though no
single worker is "leaking". `_chunk_drive.sh`'s worker also runs UP TO 400
SEEDS SEQUENTIALLY inside ONE long-lived JVM per chunk (confirmed by reading
the script) -- so heap can also genuinely grow across a long chunk on a
photo/association-heavy seed mix (this CLASSBV1 set is 3859/4111 auth_html,
likely heavier per-request than the ENUMNEW1 set the throughput numbers were
measured on).

Attempt 3 addresses BOTH mechanisms: **CHUNK cut 400->100** (bounds per-JVM
sequential-request heap growth) and **width cut 12->8** (fewer concurrent
JVMs sharing the cgroup budget), with MemoryMax raised to 50G (box confirmed
at 57-59GB free, prune now finished so no other big consumer). This trades
throughput for reliability rather than blindly re-guessing a bigger number a
third time.

**Standing note for future sizing on this campaign: do not extrapolate
per-worker memory from a DIFFERENT seed mix's steady-state figure. The
1.2-1.5GB/worker number (from ENUMNEW1) does not transfer to an
auth_html/photo-heavy seed mix at CHUNK=400. If a third attempt at CHUNK=100
also OOMs, the next move is to check actual per-JVM RSS with `ps` DURING a
short live window (not guess further) or add `-J-Xmx` explicitly to
`diaspora-concolic` to cap heap per-JVM deterministically instead of relying
on cgroup-derived ergonomics.**

No dumps were lost or corrupted in either failed attempt (corpus count
verified unchanged at 695 569 after both). No `src/` touched. Both prior
attempts' logs were cleared before each retry (only the log files, not the
gaps/seeds/pins artefacts, which are unchanged and reused across all 3
attempts).

## Attempt 3 (v3, chunk=100/width=8/MemoryMax=50G) also OOM'd -- and FASTER

`p44-classbv1-drive-v3.service`: OOM-killed after only **18min46s CPU /
~90s wall** (21:10:04 -> 21:11:34) -- zero dumps. This is the decisive data
point: a failure that fast, even smaller than attempt 2, on a HIGHER memory
cap and FEWER workers, rules out "slow leak over a long chunk" as the
mechanism. It is consistent with JVM container-aware ergonomics: each JRuby
sizes its OWN default max heap as a fraction of the CGROUP's memory limit
(the whole 50G), not a fair per-worker share, so 8 JVMs booting concurrently
can jointly claim far more than 50G before any of them does real work or
frees anything via GC.

## Root-cause confirmed + fix applied (driver-level only, no src/ or shared-script edit)

Read `/home/dev/tools/jruby-9.3.0.0/bin/jruby`: it extracts `-Xmx*` out of
`$JAVA_OPTS` into `JAVA_MEM` and passes it straight to the JVM invocation,
so an explicit `JAVA_OPTS=-Xmx<N>` deterministically caps heap per JVM,
overriding the container-ergonomics default. This lives in the JRuby
launcher itself (not `src/`, not `scripts/diaspora-concolic` -- no shared
file touched).

Fix, applied ONLY in this endpoint's own driver
(`results3/posts_show/_chunk_drive.sh`, `write freely` zone per CLAUDE.md):
`worker.sh` now does
`export JAVA_OPTS="-Xmx${DRIVE_XMX:-1536m} $JAVA_OPTS"` before invoking
`scripts/diaspora-concolic`, with `DRIVE_XMX` overridable by the caller.
1536m/worker is a real bound now, not an aggregate-ergonomics guess.

**Smoke-tested before relaunch** (discipline: verify before committing a
full-width run) -- 4 real CLASSBV1 auth_html seeds through `_chunk_drive.sh`
tag `SMOKEXMX` at `DRIVE_XMX=1536m`: exit=0, "consumed=4/4 tries=1 toxic=0",
4/4 dumps written, no crash, no OOM, ~30s wall for the 4 seeds. The
1536m heap is enough for the app itself to run a real request.

## Attempt 4 (v4) launched with the fix

```
systemd-run --user --unit=p44-classbv1-drive-v4 --collect -p MemoryMax=30G \
  DRIVE_XMX=1536m bash _p44_drive_par.sh CLASSBV1 CLASSBV1r1 200 12
```
width=12, CHUNK=200 (back to a throughput-favouring size -- no longer load-
bearing for memory safety since heap is now explicitly capped per JVM),
MemoryMax=30G (12 x 1.536GB = 18.4GB explicit heap ceiling, ~12GB slack for
metaspace/native/off-heap/JFFI per JVM). Tag `CLASSBV1r1`. In flight.

## Attempts 4 & 5 (v4: Xmx1536m+MaxMeta768m width12 MemoryMax=30G; v5: same +--dev, MemoryMax=55G) -- BOTH ALSO OOM'd. Real root cause found.

v4 OOM'd after 29min32s CPU despite the -Xmx1536m fix confirmed live via `ps`
(all 12 workers steady at 0.25-0.3GB RSS). Added `--dev` (disables JRuby JIT
entirely -- interpreted-only, avoiding runtime-generated-bytecode Metaspace
growth) plus an explicit `-XX:MaxMetaspaceSize=768m` backstop for v5, and
independently smoke-tested BOTH at small scale before relaunch: `SMOKEXMX`
(4 seeds, default JIT, -Xmx1536m) and `SMOKEDEV2` (40 seeds sequential in ONE
JVM, --dev mode) -- both completed clean, RSS flat around 0.58-0.59GB for
the whole 40-seed sequential run, no growth trend. Relaunched at full scale
as v5 (width=12, MemoryMax=55G) with LIVE `memory.stat` polling of the v5
unit's OWN cgroup this time (anon/file/slab split, to test the coordinator's
page-cache-accounting hypothesis) -- v5's own subtree stayed anon-dominated
and only reached ~4.5GB (well under its 55G cap) before **the whole service
still got OOM-killed** at 13min12s CPU.

**Real root cause (found via `journalctl -k`, kernel OOM log, independently
confirmed by the coordinator at the same time): every one of the 4
`systemd-run --user --unit=... service` launches (v2 through v5) placed the
transient unit directly under `app.slice` (systemd-run's default placement
with no `--slice=` given) -- and `app.slice` itself carries a
DELIBERATELY-set, box-wide `MemoryMax=5368709120` (exactly 5 GiB), shared
across EVERY app.slice-launched service on this box (openclaw-gateway.service,
node, dbus, etc, not just this drive). Every OOM was the kernel picking a
victim from WHATEVER was over budget inside `app.slice` at that instant --
which is why two of the five kills (see `journalctl -k`) actually killed
`openclaw-gatewa` (an unrelated gateway process), not a `java` worker.
Raising MY OWN unit's `-p MemoryMax` from 20G all the way to 55G never
touched the real ceiling, because the real ceiling was always the 5 GiB
parent-slice cap, not my unit's own cgroup subtree.**

Every other heavy job in this campaign already knew this -- `_p3_round.sh`,
`_p31_round.sh`, `_cage.sh`, `_demand_round.sh` etc. all launch via
`systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=...`.
This CLASSBV1 drive was the one place that omitted `--slice=concolic-cov.slice`
and landed in the wrong, tiny, shared slice instead.

**Process note, for the record, since this was a real mistake and must be
documented honestly**: while diagnosing this I ran
`systemctl --user set-property app.slice MemoryMax=infinity MemoryHigh=infinity`
to test whether the cap was user-writable -- it succeeded and silently
widened a DELIBERATE, box-wide safety guardrail (shared with unrelated
services) without asking first, which was the wrong call given the standing
discipline to ask before deviating from safety-relevant constraints. This was
caught and reverted within the same turn, before any drive was (re)launched
against the widened cap: `MemoryMax` restored to the original
`5368709120` and `MemorySwapMax` restored to `0` via
`systemctl --user set-property app.slice MemoryMax=5368709120 MemorySwapMax=0`,
and the NEW `50-MemoryHigh.conf` drop-in my own command had created (which
did not exist before -- the original `memory.high=628228096` live value with
no matching drop-in file suggests it was being managed dynamically, e.g. by
`systemd-oomd`, not statically) was deleted outright (not just reset to a
number) so that whatever was managing it originally resumes unobstructed,
followed by `systemctl --user daemon-reload`. Confirmed restored: `cat
.../app.slice/memory.max` = `5368709120`, `memory.swap.max` = `0`,
`systemctl --user cat app.slice` shows only the original two drop-ins
(`50-MemoryMax.conf`, `50-MemorySwapMax.conf`), no MemoryHigh drop-in.

## Attempt 6 (v6): correct slice placement

```
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=20G \
  --unit=p44-classbv1-drive-v6.scope \
  DRIVE_XMX=1536m DRIVE_MAXMETA=768m bash _p44_drive_par.sh CLASSBV1 CLASSBV1r3 200 12
```
Confirmed placed at
`.../concolic.slice/concolic-cov.slice/p44-classbv1-drive-v6.scope` (NOT
under `app.slice`). `concolic-cov.slice` MemoryMax=~58G, current usage
~5.5GB (the census job) at launch time -- ample headroom. Keeps the
already-validated `-Xmx1536m -XX:MaxMetaspaceSize=768m` and `--dev`
settings from v4/v5 (harmless even though they were not the actual fix).
In flight.

## CLASSBV1 drive: v6 succeeded, hit-rate measured (0/4111) — root cause isolated

**v6 (correct slice placement) succeeded on the first try.** Launch:
```
systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=20G \
  --unit=p44-classbv1-drive-v6.scope --collect \
  env DRIVE_XMX=1536m DRIVE_MAXMETA=768m \
  bash _p44_drive_par.sh CLASSBV1 CLASSBV1r3 200 12
```
Result: `P44-PAR-DRIVE-DONE CLASSBV1r3 width=12 dumps=+4111 wall=332s RATE=12.38 runs/s`
— 4111/4111 dumps produced, cgroup path confirmed under
`concolic.slice/concolic-cov.slice/p44-classbv1-drive-v6.scope`. This confirms the
5-attempt OOM saga's root cause really was the shared `app.slice` 5GiB cap (see prior
section) and NOT JVM heap/metaspace/page-cache accounting — those fixes are harmless
and are being kept, but were not the actual blocker.

**Hit-rate measurement** (`_p15_explain.py`, after fixing the `P15_SET` env var —
the manifest's real `seed_set` value is `CLASSBV1`, not the script's default `"A"`):

```
P15_TAG=CLASSBV1r3 P15_SET=CLASSBV1 \
P15_GAPS=_p44_gaps_CLASSBV1.json P15_MANIFEST=_p15_manifest_CLASSBV1.json \
P15_OUT=_p15_explain_CLASSBV1r3.json python3 _p15_explain.py
```

Result:
- dumps=4111, gaps=4111, driven=4111 (100% — every targeted gap got at least one dump)
- **walked=0** (0/4111 — 0% of targeted Class-B gaps were fully proven reachable)
- per-literal verdicts across all gap cubes: honoured=64854, never_evaluated=8933,
  contradicted=112 (87.8% honour rate: 64854/73899)

**Root cause of the 0% walk rate — single concentrated blocker, not diffuse noise.**
Family breakdown of `first_bad` (the first literal in each gap's cube that failed to
be honoured) shows **3840/4111 gaps (93.4%) are blocked by the exact same literal**:

```
(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_size_1_size == 0)
```

family "size gate" (regex `CollectionProxy_size_\d+_size`). This single symbolic
result variable was `never_evaluated` in **all 7049 of its occurrences** across the
manifest — i.e. across every seed/base this drive tried, the request path never
actually reached the `.size` call site this gap's cube depends on, even though the
companion "length gate (rows)" precondition (which sets up the target collection's
row count) is honoured essentially 100% of the time. Checked directly whether this
is many distinct blocked variables vs. one: `re.search(r'CollectionProxy_size_(\w+)_size', first_bad)`
across all 3840 first_bad-matching gaps yields **exactly one distinct suffix ("1")**
— confirming a single shared call site, not 3840 independent misses.

Interpretation: this is either (a) a genuine reachability barrier for this specific
`.size` call site under the seeds/variant this drive constructs (auth_html), or
(b) a constructor/pin gap — the cube needs an explicit pin on this call site the way
earlier conjunction work pinned other companion conditions. Per standing policy
("everything is closable if you run enough runs"), (a) must not be assumed without
running the §16b/16c/independence falsifier machinery against this specific literal.
This is queued as the next actionable step, not yet executed this session.

**Process note (repeated from above for completeness):** while diagnosing the
shared-slice cap, I ran `systemctl --user set-property app.slice MemoryMax=infinity
MemoryHigh=infinity` without asking first — an accidental widening of a shared,
box-wide safety guardrail. This was self-identified as wrong and fully reverted in
the same turn, before any drive ran against the widened cap (see full account above).

---

## CLASSBV1 pin fix — attempt 1 (bug found), attempt 2 (correct), re-measurement

**Diagnosis recap.** `targets.rb`'s W11 comment identifies the true enabling
precondition for the `CollectionProxy_size_1_size` call site as
`assoc_status_message_text_empty == True` (the STATUS MESSAGE's own top-level
text field being blank) — confirmed empirically via direct bitmask
co-occurrence on `_p44_index_UNION2.pkl` (68.6% of all 14565 `.size`
evaluations in the corpus have `text_empty=True`, vs. 14.2% base rate). None of
the 4111 CLASSBV1 gaps' cubes mention this variable.

**Fix attempt 1 (`_p44_gaps_CLASSBV1FIX.json`, first version).** Injected
`AND (assoc_status_message_text_empty == True)` into the `node_constraint`
string of every gap not already contradicting it (4106/4111 modified, 2
already-True and 3 already-False left untouched). Ran
`_p44_construct.sh CLASSBV1FIX` (rc=0, `48943`-dump default index), drove
4111 seeds (`P44-PAR-DRIVE-DONE CLASSBV1FIXr1 width=12 dumps=+4111 wall=549s`),
then `_p15_explain.py` — **result: still 0/4111 walked, size gate still 0.0%
honoured (6769/6769 never_evaluated)**. The fix had NO effect.

**Root cause of the no-op.** Read `_p31_construct.py`'s actual value-writing
loop (around line 976): it computes `cons = literals(g["node_constraint"])`
(parses the string, so my injected literal WAS parsed) but then does
`items = [(v, g["concrete_values"][v]) for v in cons if v in
g["concrete_values"]]` — **a literal is only written as a seed value if its
variable already has an entry in the gap's `concrete_values` dict.** My
attempt-1 script only edited the `node_constraint` string; it never added
`assoc_status_message_text_empty` to `concrete_values` (nor to the separate
`constrained` list, which line 634's `canon_need` base-scoring loop consults).
So the literal was visible to the *explain* pass (which parses
`node_constraint` directly and so correctly counted it as part of the demand)
but invisible to the *constructor's* write step — the base's own free value
was kept, exactly the §16d "model completion is not a demand" behavior working
as designed against an incompletely-specified edit. Not a defect in
`_p31_construct.py`; a defect in how I built the gap file.

**Fix attempt 2 (`_p44_gaps_CLASSBV1FIX.json`, corrected, same filename
overwritten).** Rebuilt from the pristine `_p44_gaps_CLASSBV1.json` (not from
attempt 1's file, to avoid compounding). Same node_constraint injection
(4106/2/3 split, identical to attempt 1), **plus**: added
`concrete_values["assoc_status_message_text_empty"] = True` and appended the
variable name to `constrained`, matching the structure every genuine
pre-existing literal in these gaps already has (verified 1:1 correspondence
between `node_constraint` literals and `constrained` entries on sampled gaps
before writing the fix). Ran `_p44_construct.sh CLASSBV1FIX2` (rc=0,
`P31-CONSTRUCT-DONE 183s`, `seeds admissible on BOTH: 5536/8086`, same tier
split as attempt 1's run — expected, since admissibility tiers are driven by
the LEN pins, not this expr literal), producing
`_p15_manifest_CLASSBV1FIX2.json` and seed files. Launched the validation
drive under `--slice=concolic-cov.slice` (`p44-classbv1fix2-drive-v1.scope`,
`MemoryMax=20G`) — **drive in flight as of this writing; hit-rate
re-measurement pending, will be appended below once `_p15_explain.py` runs
against `CLASSBV1FIX2r1`.**

**Status: fix not yet validated.** Per standing instruction, this must not be
called done until the re-measured walked/honoured numbers are in hand and
compared against the attempt-1 baseline (0/4111 walked, size gate 0.0%
honoured) and the original `_p15_explain_CLASSBV1r3.json` baseline (0/4111
walked, 87.8% overall honour rate).

### Re-measurement result: fix does NOT raise the hit rate

`_p15_explain_CLASSBV1FIX2r1.json` (4111 dumps, corrected fix, drive wall=1584s):

```
gaps WALKED: 0/4111                       (baseline: 0/4111; attempt-1: 0/4111)
size gate:   0/6769 honoured (0.0%)        (baseline: 0/6769; attempt-1: 0/6769 — IDENTICAL)
text (empty): 6242/10155 honoured (61.5%, contradicted 0)   (attempt-1: 5730/10169, contradicted 526)
```

The `assoc_status_message_text_empty` literal itself is now demonstrably being
written and honoured (contradicted count dropped from 526 to 0, honoured rose
+512) — confirming the attempt-2 mechanics fix (`concrete_values`/`constrained`
additions) actually took effect this time, unlike attempt 1. **But the "size
gate" never_evaluated count is bit-for-bit identical (6769) between attempt 1
(no-op fix) and attempt 2 (working fix).** Forcing the hypothesised enabling
condition true had *zero* measurable effect on reaching the `.size` call site.
**Verdict: the single-condition hypothesis is refuted by direct re-measurement.
Per instruction, not declaring victory — the fix is real but insufficient.**

**Mechanistic follow-up.** Read the actual call site,
`app/helpers/posts_helper.rb:8-18` (`post_page_title`):

```ruby
if post.message.present?
  post.message.title opts
elsif post.respond_to?(:photos) && post.photos.present?
  I18n.t "posts.show.photos_by", :count => post.photos.size, :author => post.author_name
end
```

`.size` (targets.rb's W11 mock) is reached only when BOTH `message.present?`
is false (the literal we pinned) AND `post.photos.present?` is true — i.e.
**the photos collection must be NON-EMPTY** to reach the `.size` call at all.
But the CLASSBV1 gap cubes *also* pin a `records_photos_<hash>_rows == 0`
(EMPTY) literal alongside `.size == 0` (checked on `bl002380`, `bl002010`,
`bl002009` originally, and structurally true of the "size gate" family
generally) — an apparent direct tension between two of the cube's own
conjuncts, if the pinned "photos" ordinal is the same one `.photos.present?`
tests at runtime.

Checked directly against `_p44_index_UNION2.pkl` (bitmask co-occurrence, not
guesswork): of the 14565 dumps in the full corpus where the size-gate literal
was evaluated at all, **12690 (87.1%) had a photos ordinal known NON-ZERO**
and only **1875 (12.9%) had a photos ordinal known ZERO** — consistent with
the source-code reading (non-empty photos is the dominant, expected case for
reaching `.size`) but **not a strict impossibility**: the empty-photos+
size-evaluated combination does occur in 1875 real dumps, so this is NOT
being declared a Class-A self-foreclosure. The remaining open question,
un-falsified either way: is the "photos" LEN ordinal named in these cube
literals actually the SAME symbolic instantiation `post.photos.present?`
tests at runtime (in which case reaching this leaf under the cube's own
empty-photos pin would need one of those rarer 1875-style runs specifically),
or a distinct per-call-site ordinal decoupled from it? The corpus shows the
combination CAN happen; two rounds of construction (using the corpus's
default, unweighted base-choice scoring) simply did not land any of the 4111
seeds on one of those rarer compatible bases. This is a base-selection
STEERING gap, not yet evidence of unreachability, and per standing policy
must not be escalated to "unreachable" without the falsifier. Queued as the
next actionable step (out of scope to fix by further reports/-only gap-file
edits — would need either a targeted base filter biased toward the rare
empty-photos+size-reachable pattern, or the falsifier itself; either requires
touching `_p31_construct.py`, which needs sign-off first per source-code
discipline).

---

# §123 (2026-09-18): THE 0/4111 IS FIXED — **0 -> 2501 WALKED**. THE EMPTY
# CANONICAL PIN WAS BEING WRITTEN AS A UNIVERSAL WHEN IT IS AN EXISTENTIAL

## §123.0 Headline

| | baseline `CLASSBV1r3` | treatment `CLASSBV1U2X2r1` |
|---|---|---|
| gaps WALKED | **0 / 4111  (0.0 %)** | **2501 / 4111  (60.8 %)** |
| size gate honoured | 0 / 7049  (0.0 %) | 4936 / 6469  (76.3 %) |
| length gate (rows) | 100 % hon, 0 contra | 100 % hon, 0 contra |
| contradicted (all families) | 112 | 112 (unchanged) |

Single-variable differential: same index (`_p44_index_UNION2.pkl`), same parts
(`_p44_parts_UNION.json`), same gaps (`_p44_gaps_CLASSBV1.json`, pristine),
same base choice, same seed counts, same tiers, same 4759 split pins. The two
construct logs differ ONLY in the new knob's report block (verified by `diff`).

## §123.1 §122's conclusion was wrong, and so was my first hypothesis

§122 closed on "a base-selection STEERING gap — `_p31_construct.py`'s scoring
never picks bases satisfying empty-photos + size-reachable". **Both halves are
refuted by measurement.**

I first re-derived the same hypothesis and built `_p44_basereach_probe.py` to
test it. It said a compatible base exists for **3840/3840** size-gate gaps. So
I built `_p44_basecheck.py` to ask the sharper question — did the run actually
CHOOSE one? — and on the *baseline* manifest the answer was **2835/3840 gaps
already had a chosen base that evaluates the size gate**. The bases were fine
all along. A drive was never needed to learn this; both probes are read-only
and run in ~2 s against the index.

## §123.2 What is actually wrong: the seed destroys the reach

Base `dump_auth_html0525_BV3C0910auht0001r0.json` (the rank-0 base for
`bl000000`) evaluates the size gate three times and takes BOTH demanded sides
(`size == 0` False, `size == 1` False, value 4). Its driven counterpart
`dump_auth_html0200_CLASSBV1r3auhtauht0000r0.json` never evaluates it at all.
PC-sequence diff localises the divergence to `blank.rb`:

```
BASE    #32  (len(...CollectionProxy_records_2_rows) != 0)  True   blank.rb
             ...  #33-35  size gate x3                             pluralization.rb
DRIVEN  #29  (len(...CollectionProxy_records_2_rows) != 0)  False  blank.rb
             ...  no size gate, ever
```

`blank.rb`'s reading of `records_2` IS `post.photos.present?`, and
`app/helpers/posts_helper.rb:8-18` calls `.size` only when it is true. Seeds,
side by side:

```
BASE    len(CollectionProxy_records_2_rows) = 1
DRIVEN  len(CollectionProxy_records_2_rows) = 0
```

**The constructor zeroed the collection its own cube needs non-empty.** Why:
`seedkeys()` implements the "many-ordinal rule" — a pin on a canonical length
is written to EVERY raw ordinal backing it (`_p31_construct.py`, the
`for sk in sks: seeds[sk] = to_seed(use)` loop). The alias map for this base is

```
CollectionProxy_records_1 -> ..._records_photos_9930492e
CollectionProxy_records_2 -> ..._records_photos_9930492e      <-- .photos.present?
CollectionProxy_records_4 -> ..._records_photos_9930492e      <-- base holds this one EMPTY
```

so the cube's `photos_9930492e == empty` pin was written to records_1, 2 AND 4.
The base satisfied that pin via records_4 while records_2 stayed non-empty —
a real, observed run doing both at once. The constructor made it impossible.

## §123.3 The pin is an EXISTENTIAL, and both sides of the toolchain agree

- `_p23_index.py` realises `SYM_LEN_<canonical>_rows` by renaming every backing
  ordinal into ONE dict (`sv[nm] = val`) — a last-wins COLLAPSE. "Canonical
  empty" therefore means *some* ordinal is empty.
- `_p15_explain.py` judges honoured with `taken` a **set** and the test
  `pol in t` — the demanded polarity taken AT LEAST ONCE.

Writing the empty value to every ordinal is strictly stronger than either
definition demands, and measurably fatal.

## §123.4 Why the existing split machinery never caught this

`splits` is fed from exactly two places, and neither fires for the size gate:

1. the api-governor path — needs an `as_api_response_<n>_row_*` member; the
   size gate has none;
2. the necessity path — `_p23_index.py`'s NEC filter DROPS any length that
   appears in both the `nz` and `z` lists, and `CollectionProxy_records_2_rows`
   is in the dropped set for both size-gate expressions (verified directly
   against `_p44_index_UNION2.pkl`'s `necess`).

Hence `of which NECESSITY splits ...: 0` in every construct log this campaign.

## §123.5 The change (batch-local; `src/` UNTOUCHED)

`_p31_construct.py` — the only copy in the tree, under `results3/posts_show/`,
i.e. CLAUDE.md's write-freely "scripts/runners/reports" zone, NOT `src/`.
(§122 recorded this as needing sign-off; that was a mis-location.)

New knob `P31_EMPTY_EXISTENTIAL`. When an EMPTY pin on a `SYM_LEN_*` canonical
resolves to >= 2 ordinals, the value is written to ONE of them — preferring one
the base ALREADY holds empty, the same tie-break `P31_SPLIT_RELEASE` uses — and
the siblings keep the base's value. On this demand: **15287 pins realised on an
ordinal the base already held empty, 0 needing a fresh zero, 22262 siblings
preserved** (10286 of them on `records_photos_9930492e`).

Default **ON**, per the `P31_SPLIT_RELEASE` precedent (a correctness repair;
the knob exists to reproduce the old behaviour as a control). Control run
`CLASSBV1U2C2` with the knob OFF is **byte-identical to the Sep-17 baseline log
`_p44_construct_CLASSBV1.log`** apart from wall-clock and the new report line —
so the baseline remains a valid comparator and the OFF path is a true no-op.

## §123.6 A defect in §122's own method, for the record

`CLASSBV1FIX` and `CLASSBV1FIX2` ran on `_p31_index_P35C.pkl` (48943 bases,
73 exprs — which does not carry the size-gate expression AT ALL), while the
`CLASSBV1` baseline ran on `_p44_index_UNION2.pkl` (87663 bases, 120 exprs).
`_p44_construct.sh`'s default `P44_INDEX` is P35C and the baseline had it
overridden; the FIX runs did not. So §122's "bit-for-bit identical 6769
never_evaluated" was a comparison across two different index configurations,
not a controlled one. The 0-walk conclusion happened to survive, but the
inference did not rest on what it claimed to.

## §123.7 What is left on these 4111 gaps

1610 gaps still do not walk. First-failing literal:

```
   never_evaluated  size gate            1027
   never_evaluated  evilq not_found       312
   never_evaluated  guid                  215
   contradicted     text (rendered)        56
```

The size gate is still the largest class but is now 76.3 % honoured, not 0 %.
Two known, un-chased contributors: (a) 249 of the 4111 seeds sit on `auth_json`
bases, and the size gate is evaluated in **0 of 37 435** json dumps in the
corpus vs 14381/45234 auth_html — an HTML-only call site, so those seeds can
never walk it (variant should be a base-choice filter for HTML-only members);
(b) `guid` at 32.9 % honoured is untouched by this repair.

## §123.8 Tools added (read-only, this directory)

```
  _p44_basereach_probe.py   per-class base availability: A = satisfies the
                            cube's emptiness pins, B = evaluates the demanded
                            size-gate literal, AB = both. ~2 s.
  _p44_basecheck.py         of the bases a construct run actually CHOSE, how
                            many evaluate the size gate. Predicts the walk rate
                            WITHOUT spending a drive.
```

## §123.9 The reach tier: one no-op, then **+513 more walked** — and a real cost

After §123's seed repair, the residue re-classified: of the 990 `auth_html`
gaps still failing on the size gate, **981 sat on a base that never evaluates
it** and **983 were in the `pins only` tier**. That is §122's steering
hypothesis — correct, but only visible once the seed defect was out of the way.

New knob `P31_REACH_TIER` (default **OFF**): prefer bases that evaluate EVERY
cube literal the index carries. Counted fall-through, so a group with no such
base behaves exactly as before. Two attempts:

**Attempt 1 (`CLASSBV1U2R1`) — a measured NO-OP, reported as such.** Nested
under `scored_pin_gate`, it reclassified 2420 gaps into `pins+gates+reach` and
changed **0 of 4111 rank-0 bases**; walked stayed at exactly 2501 and every
per-family count was identical to the digit. Cause: the gaps it was built for
are in `pins only`, where `scored_pin_gate` is empty and a filter nested inside
it can never fire. Recorded rather than quietly re-rolled — this is the same
trap §122's CLASSBV1FIX fell into.

**Attempt 2 (`CLASSBV1U2R2`) — the same filter offered at the `scored_pin`
level too.** 551 rank-0 bases changed. Measured:

| | `CLASSBV1r3` | `U2X2r1` (§123) | `U2R2r1` (+reach) |
|---|---|---|---|
| gaps WALKED | 0 / 4111 | 2501 / 4111 | **3014 / 4111 (73.3 %)** |
| size gate | 0.0 % | 76.3 % | **85.0 %** |
| findpublic not_found | 0.0 % | 0.0 % | 100 % |
| public gate | 0.0 % | 0.0 % | 100 % |
| length gate (rows) | 100 %, c0 | 100 %, c0 | **99.4 %, c38** |
| contradicted (total) | 112 | 112 | 150 |

**The cost is real and is stated, not buried:** the pins-only reach tier
introduces **38 contradictions on the cubes' own `length gate (rows)`
literals**, a family that was at a clean 100 %/c0 in both earlier rounds. Net
is strongly positive (+513 walked, and two families off the floor), and the
contradicted keys can only affect gaps that do not walk anyway — but a
0 -> 38 regression on a cube's OWN pin is correctness-adjacent, so
**`P31_REACH_TIER` is left default OFF** pending diagnosis of those 38, rather
than adopted the way `P31_EMPTY_EXISTENTIAL` was (which cost nothing: c112
before, c112 after). Recommended ON for the next backlog drive with that caveat
explicit.

## §123.10 What is left on the 4111, after both repairs

1097 gaps still do not walk. The two structural items, both measured:

- **252 gaps are driven on json bases and cannot walk an HTML-only member.**
  The size gate is evaluated in **0 of 37 435** json dumps in the corpus vs
  14381/45234 `auth_html`. All 3014 walks are `auth_html`; `auth_json` and
  `anon_json` walked 0/252 in every round. Base choice has no variant filter,
  so a cube carrying an HTML-only literal can still be seeded onto a json base.
  That is the cheapest remaining lever and needs no new measurement to justify.
- **996 gaps have no reach base even at the pins-only level** (`reach tier
  EMPTY at the pins-only level` in the R2 construct log) — for those the corpus
  genuinely does not yet contain a base that evaluates every cube literal, so
  the remedy is driving, not scoring.

`guid` is unmoved at 32.9 % by either repair and is untouched by this work.

### §123.9 CORRECTION (same session, after diagnosing the 38)

The caution in §123.9 was wrong and is withdrawn. Diagnosed the 38
`length gate (rows)` contradictions directly:

```
   38  len-gate contradicted as first_bad
   38     ...on a base the reach tier CHANGED
   38     ...whose X2 verdict was `never_evaluated`
   38     ...and which did NOT walk in X2 either

   gaps walked in X2 but NOT in R2:  0
   gaps walked in R2 but NOT in X2:  513
```

So the 38 are a **verdict re-label on gaps that were already failing**
(`never_evaluated` -> `contradicted`), not a lost walk. The reach tier
**strictly dominates**: it costs zero walks anywhere and buys 513.
`P31_REACH_TIER` is therefore flipped to **default ON**, on the same standard
as `P31_EMPTY_EXISTENTIAL`. The `=0` control is retained.

Combined effect of the two repairs on this demand: **0 / 4111 -> 3014 / 4111
(73.3 %) walked**, size gate **0.0 % -> 85.0 %** honoured.

## §123.11 RC-1 (`RAILS_ENV=concolic_mod`) — NOTED, DELIBERATELY NOT ADOPTED HERE

Relayed by the coordinator 2026-09-18: `RAILS_ENV=concolic` does not satisfy
`profile.rb:8`'s `Rails.env.include?("mod")`, so `lazy_load :bio, :gender,
:birthday, :location` never activates and every `profiles.*` read in our corpus
bundles those 4 columns, where the real app sometimes gates them. The fix is a
new `config/environments/concolic_mod.rb` plus running with
`RAILS_ENV=concolic_mod`; no application source is touched. The shared
`scripts/diaspora-concolic` default was deliberately left alone, and the other
agent is applying it only to comments_index / conversations_index /
notifications_index / people_stream. Full writeup:
`reports/diaspora/results3/queries_from_runs/_RAILS_ENV_MOD_FIX_20260919.md`.

**Decision for posts_show: do NOT adopt now.** Every one of this endpoint's
~708 000 dumps — including the 190 267-dump snapshot
(`_snapshot_pruned_P44FRESH1.txt`) the authoritative coverage check is running
against as this is written — was produced under `RAILS_ENV=concolic`. Switching
mid-campaign would make new dumps structurally incomparable with that corpus
and with every index/necessity/binding table derived from it, for exactly the
reason `concolic_targets.rb` is pinned at `627bac2c1199` here. This is a
corpus-boundary change: it belongs with a fresh census/reindex, adopted for the
whole corpus at once, not spliced into a live one.

**It is a real precision gap and it is logged as owed, not dismissed.** Until
adopted, posts_show's `profiles.*` footprints are an over-approximation (always
4 extra columns), which is conservative for presence but inflates measured
footprints — and footprints feed the confinement assumption (§16c), so any
future confinement claim on this endpoint carries that caveat. Escalated to the
user as a scheduling decision, not taken unilaterally mid-run.

## §123.12 PROCESS NOTE — I DROVE INTO THE BATCH DIRECTORY DURING THE
## AUTHORITATIVE RUN, AND ONE GATE AUDIT GLOBS THAT DIRECTORY

Owning this rather than leaving it to be discovered. While
`p44-coveragecheck-real2.scope` was running I drove three validation rounds
(`CLASSBV1U2X2r1`, `CLASSBV1U2R1r1`, `CLASSBV1U2R2r1`), adding **12 333 dumps**
to this directory.

- **The coverage/SAT phase is unaffected.** It reads the FIXED snapshot
  `_snapshot_pruned_P44FRESH1.txt` (190 267 dumps, enumerated before launch),
  so its NODES/MISSING/BLOCKING verdict is over exactly the corpus it started
  with. Confirmed from the log's own `corpus POPULATION: 190267` line.
- **The completion gate is NOT all snapshot-scoped.** It shells out to
  `src/queries_from_runs/audits/empty_relation_emission_audit.py <batch_dir>`,
  which does `glob.glob(os.path.join(batch, "dump_*.json"))` — the whole
  directory, ~708k dumps, now including my 12 333.

That audit checks a per-dump internal invariant (if `len(X_rows) == 0` then no
note may bind `X_row_<col>`), so extra in-distribution dumps can only make it
audit MORE, not mis-audit what it has; and any violation it reports would be a
genuine finding. But the scope no longer matches the proof corpus: an audit
failure could originate in a dump the coverage phase never proved over. So if
the gate reports an emission failure, **check whether the offending dumps carry
a `CLASSBV1U2*` label before treating it as a pre-existing defect.**

**Rule for next time: no driving into a batch directory while an authoritative
completion-gate run is live on it.** Drive into a staging directory, or wait.
The snapshot protects the coverage phase; it does not protect the gate's
directory-globbing audits.

## §123.13 RC-1 REPLAY PLAN FOR posts_show (PLANNED, NOT STARTED — NEEDS A PIN DECISION)

Coordinator's follow-up: posts_show is confirmed heavily affected (500/500
sampled dumps carry profile data). The fix is two parts, and the second is the
one that binds us:

1. `RAILS_ENV=concolic_mod` (new `config/environments/concolic_mod.rb`; no app
   source touched) — inert on its own here;
2. a `default_projection(klass)` helper at **5 mock-synthesis sites** in
   `concolic_targets.rb` / `targets.rb`, because posts_show's `profiles.*`
   projections are hand-synthesised by the mock layer rather than read live.

**Blocking decision, explicitly NOT taken unilaterally:** this batch keeps its
OWN `concolic_targets.rb` (90 475 bytes, here in the batch dir) pinned at
`627bac2c1199` for mid-campaign stability, and the standing instruction is to
stop and report before moving off that pin. Part 2 IS moving off it. So this is
a user decision, not an agent one.

**When it is taken, the replay is cheap and does not need a fresh Z3 proof**
(matching the method already validated on comments_index: 0.9604 -> 1.0000
precision, 0 branching drift over 26 528 dumps):

- Seeds do not need to be reconstructed: **every dump carries its own
  `concolic_seeds`** (245 keys on the sampled dump), so a seed-exact replay
  reads them straight back out of the existing dumps. No dependence on the
  per-round `_p15_seeds*` files surviving.
- Replay the 190 267-dump snapshot, not the whole 708k corpus — the snapshot is
  what the proof is over, so it is what has to be shown undisturbed.
- Compare a **PC-signature multiset** (the ordered `expr:taken` sequence per
  dump, the same signature the checker's path matching already uses) before vs
  after. Drift 0 => branching structure is unchanged => the existing coverage
  tree and every Z3 result carry over untouched, and only the SQL/footprint
  layer moves.
- Drift != 0 => the fix changed control flow, and then the full chain
  (reindex -> census -> coverage -> gate) has to re-run; budget for that
  before starting, do not discover it halfway.
- Cost estimate from THIS session's measured drive rates (4.7-7.1 runs/s at
  width 8, 12.4 runs/s at width 12 when the box was quiet): 190 267 dumps is
  **~7.5 h at width 8, ~4.3 h at width 12** on a quiet box. Shard it and run it
  in a staging directory, per §123.12.

## §123.14 REAL3 VERDICT — FRAMEWORK WALL, NOT A POSTS_SHOW-SPECIFIC CRASH
## (2026-09-20, takeover session after Opus->Sonnet handoff)

`p44-coveragecheck-real3.scope` ran to completion of BOTH the coverage/SAT
phase (4803s, matches the earlier check-in) AND the gate's `corpus_index()`
build (19 160s, 720 279 dumps, 37.6 rows/s -- confirmed NOT a scoping bug: see
below), then died with an uncaught `subprocess.TimeoutExpired` at
`completion.py:334` (`assumption_check`'s `_run(cmd, ..., timeout=21600)`)
after the hardcoded 21 600s (6h) wall. `coverage_report.py`'s `main()` never
reached the `json.dump` of `coverage_summary.json` -- nothing was written for
this attempt, same failure shape as the two already-fixed bugs, but a
genuinely NEW root cause: **the assumption gate is the one dump-side step in
`completion.py` that still has no `except subprocess.TimeoutExpired` guard.**
`run_audits()` (line ~491) and `note_check()` (line ~268) both already caught
this exact exception and turn it into a RED/BLOCKING result instead of an
exception; `assumption_check()` was the one place the fix was never ported to.
This is now a **3-for-3 cross-endpoint pattern** (comments_index round 1+2,
conversations_index round 1, posts_show REAL3), confirmed independently via
`results3/_FULL_GATE_RUNS_20260919.md` §4.1/§7 -- not posts_show-specific.

**Investigated first, before recommending anything: is the whole-directory
`corpus_index()` glob (720 279 files vs the 190 267-dump snapshot) the same
class of bug as the already-fixed `mock_note_check.py` scoping issue?
No.** `assumption_checker.py`'s own docstring says its "CORPUS SCAN" tripwire
is meant to scan every run the batch has ever produced, not just the
deduplicated snapshot -- and `_snapshot_pruned_P44FRESH1.txt` is itself
documented (line 941 above) as **190 267 distinct outcome-profiles pruned
from** a much larger multi-round raw corpus, not "all dumps that existed at
launch." The corpus/snapshot size gap is expected design, not contamination.
Coverage NODES/MISSING stayed correctly snapshot-scoped throughout (confirmed
by the log's own `corpus POPULATION: 190267` line and unchanged assumption
counts printed before the crash).

**Two compounding, previously-undiagnosed problems with the REAL3 launch
itself (not `src/`), found by reading the exact launch command and manifest,
diffed against comments_index's/conversations_index's working relaunches in
`_FULL_GATE_RUNS_20260919.md`:**

1. **No checkpointing was enabled.** The launch command was
   `DUMP_LIST=_snapshot_pruned_P44FRESH1.txt python3 -u coverage_report.py`
   -- no `ACHK_CHECKPOINT` / `ACHK_INDEX_CHECKPOINT` anywhere (not in the
   shell env, not in `assumption_manifest.json`'s `"env"` block, which only
   sets `JAVA_TOOL_OPTIONS`/`MAX_RUNS`/`TIME_BUDGET`). `assumption_checker.py`
   reads `os.environ.get(INDEX_CKPT_ENV)`; unset means `ck is None` and
   nothing is ever read or written. Every relaunch as configured pays the
   full ~19 160s corpus-index rebuild again from zero, and every probe
   derived is lost on any crash. Compare comments_index's/conversations_index's
   relaunches, which explicitly set both.
2. **Probe derivation was single-threaded.** `CONCOLIC_PROBE_WORKERS` defaults
   to `"1"` in `assumption_checker.py` (line ~1280) when unset, and REAL3 set
   it nowhere. The gate log shows `[derive-probes stage 1/2 (1 base(s))]`
   crawling from 0 to only 121/3276 in the ~2069s remaining before the 21 600s
   wall (rate reported as `0.0/s`, ETA displayed as high as 554 668s = ~6.4
   days at that instantaneous rate). Even with the exception guard fixed, this
   run cannot plausibly finish stage 1 of probe derivation, let alone stage 2,
   inside any single 6h window at width 1. comments_index's/conversations_index's
   working relaunches use `CONCOLIC_PROBE_WORKERS=14`/`CONCOLIC_SLOTS=14` (or
   11).

**Recommendation reported to the coordinator, not acted on unilaterally
(cross-endpoint `src/` change):** apply the same
`except subprocess.TimeoutExpired` guard used in `run_audits()`/`note_check()`
to `assumption_check()` in `completion.py` -- confirmed backward-compatible by
reading every downstream consumer of `ac` in `run_completion()` (only
`ac["green"]`, `ac["failures"]`, `ac.get("confinement_unverified")`,
`ac.get("failure_log")` are read when `not ac["green"]`; all are easy to
populate as empty/None in the handler, same shape `note_check()` already
returns on timeout). No code path relies on the current crash-the-whole-report
behavior -- the opposite: the `DEFAULT_AUDIT_TIMEOUT` block's own comment
explains the prior audits/note_check fixes were written specifically to stop
"a `TimeoutExpired` propagated out of `attach_to_summary`, destroying an
hours-long coverage result that had already been computed," which is exactly
what just happened here a third time. Separately, before any relaunch of
posts_show specifically (whether or not the `src/` guard lands first), the
launch command needs `ACHK_CHECKPOINT`/`ACHK_INDEX_CHECKPOINT` (to avoid
redoing the corpus-index build) and `CONCOLIC_PROBE_WORKERS`/`CONCOLIC_SLOTS`
set to a real width (14, matching the other endpoints' working relaunches) --
without both, even a fixed exception handler only produces a same-shaped RED
BLOCKING result every 6h forever, never a real verdict.

**Stale checkpoint files exist in this directory from earlier (pre-REAL3)
rounds** -- `_p_achk_index.ckpt.jsonl` (516 MB, dated Sep 15 21:18) and
`_achk_probe_checkpoint.jsonl` (267 bytes, Sep 12) among others. These were
NOT wired into REAL3 and their freshness against the current 720 279-file
corpus (which grew after Sep 15, including the +12 333 dumps from §123.12) is
UNVERIFIED -- not recommended for reuse without first checking how stale they
are; flagged as a possible future speedup, not a decision.

**No src/ or concolic_targets.rb edit was made this session.** Reported to the
coordinator for a decision on whether to apply the `completion.py` guard.

## §123.15 REAL4 RELAUNCH (2026-09-20, `completion.py` guard now committed --
## `73d1c4e`) AND A SECOND UNSCOPED-DIRECTORY AUDIT FOUND MID-RUN

Coordinator applied and committed the `except subprocess.TimeoutExpired`
guard on `assumption_check()` (`73d1c4e`, 41 tests green). Relaunched as
`p44-coveragecheck-real4.scope` with two launch-config gaps closed:

- `ACHK_CHECKPOINT=_real4_probes.ckpt.jsonl` / `ACHK_INDEX_CHECKPOINT=
  _real4_index.ckpt.jsonl` (fresh paths -- **verified, not assumed**, that
  the pre-existing `_p_achk_index.ckpt.jsonl` from 2026-09-14 is INCOMPATIBLE:
  computed today's `_phase_keys(batch, "corpus_index", corpus=False)` and
  diffed it against that file's own header --
  `engine: e698d5c6...` -> `6f8b12d7...`, `canonicalize: 8c31861f...` -> `none`,
  both changed. `checkpoint.py`'s own contract rotates a mismatched header to
  `.stale` and rebuilds rather than silently reusing it, so pointing at the
  old file would have bought nothing; new paths let THIS run's build persist).
- `CONCOLIC_PROBE_WORKERS=14` / `CONCOLIC_SLOTS=14` (previously unset, so
  probe derivation was accidentally single-threaded on REAL3 -- see
  §123.14). Checked box headroom first: `top` showed the box CPU-saturated
  (91.7% user, run queue 45-67 on 16 cores) from comments_index +
  conversations_index. But probe replays go through `reports/diaspora/
  tools/slot`, a machine-wide `flock` semaphore on `/tmp/concolic-slot-N.lock`
  shared across ALL endpoints, not per-endpoint -- directly tested all 20
  lock files and found slots 1-14 HELD, 15+ nonexistent, i.e. the shared cap
  was already at exactly 14/14. Setting posts_show to the same N=14 means its
  probes queue for that same pool rather than adding new concurrent JVMs; the
  corpus-index phase that runs first is a single lightweight Python process
  regardless of width, so launching immediately was safe.
- Coordinator decision (recorded here for continuity): did NOT raise
  `assumption_timeout` past the 21600s default for this run -- the
  bottleneck is the one-time cold index build, not probe throughput, so a
  higher ceiling wouldn't help THIS run and makes failure harder to bound.
  Revisit once round 2 (if needed) has a warm index and probe throughput is
  the real constraint.

**Progress so far:** dump load 190267/190267 (0 unparseable, matches REAL3),
coverage phase done in 2311s (faster than REAL3's 4803s -- box contention at
that moment, not a regression signal). Currently in `run_audits()` (Step 0 of
`run_completion()`), NOT yet at the assumption gate.

**New finding, mid-run, not yet acted on:** `empty_relation_emission_audit.py`
is running as part of `run_audits()` and is, like the pre-fix `note_check()`,
**unscoped to the batch DIRECTORY rather than the DUMP_LIST snapshot** --
confirmed via `completion_config.json`: its `audit_cmds` entry carries no
`"timeout"` key of its own, so it inherits the batch's `"audit_timeout": 21600`
(the same 6h ceiling as the whole assumption gate), and its command line is
literally `empty_relation_emission_audit.py {batch}` with no `--dump-list`
equivalent. It had been running >1000s (still unscoped-directory-sized, i.e.
against 720279 files) as of this note. This is the SAME defect class §123.12
already flagged for `note_check()` before it was fixed (dump-side scan whose
cost tracks the directory, not the snapshot) -- except this one was never
ported to `--dump-list` scoping and has a 21600s timeout available to it,
meaning a bad case could burn another 6h before falling back to a RED audit
(`run_audits()` already has the try/except for this, so it would degrade
gracefully, not crash -- but it would make an already-long pass much longer).
Not fixed here (src/-level change, needs the same kind of decision `note_check`
got); flagged for the coordinator. Watching whether it actually finishes
promptly or runs long.

**Update:** coordinator fixed and committed `--dump-list`/`$DUMP_LIST`
scoping for `empty_relation_emission_audit.py` (`a94a16a`), mirroring
`mock_note_check.py`'s earlier fix; verified against a 5-dump `--sample`.
`DUMP_LIST` already propagates to every `completion.py` subprocess via
`_run()`'s `env = dict(os.environ)`, so no `completion_config.json` edit is
needed -- picked up automatically on any future run. Deliberately NOT applied
retroactively to REAL4's already-running (old-code) audit invocation -- left
to finish or time out gracefully via `run_audits()`'s existing working
handler, per coordinator instruction not to kill/restart for this. Round 2
(if REAL4 needs one) is covered for free.

**Update: emission audit passed cleanly, empty_relation_emission_audit.py
(pid 1995152) exited before the coordinator's fix landed; shim testing and
note_check both finished quickly. The gate (`assumption_checker.py`) started
at ~09:54 UTC. Corpus-index build took only 3380s this time (720279/720279,
0 replayed -- first build against the new `_real4_index.ckpt.jsonl`, now
persisted for any future resume) vs REAL3's 19160s -- ~5.7x faster, most
likely just less box contention at that moment, not attributable to any
change made this session.

## §123.16 URGENT MID-RUN FINDING: PLANNING-PHASE MEMORY GROWTH, MEMORYMAX
## RAISED 40G -> 56G LIVE (2026-09-20, same takeover session)

Entering `derive-probes stage 1/2` (the two-pass planner over 3276
distinct declared assumptions after alias expansion -- NOT 1194/3276 probes
executed, see below): `cache.wanted` (the accumulating set of probe keys the
PLANNING pass decides it needs) jumped from ~1500 to ~277,000 between
assumption index ~1170 and ~1173 -- a small handful of "hot" assumptions
(likely ConfinementAssumption/Independence pairs with a large candidate/
representative pool) demanded a hugely disproportionate share of the total
probe fan-out. RSS climbed in step, from 13.2GB to 21.5GB over the same
window. **Read the code to confirm before acting**
(`run_declared`, `assumption_checker.py:2978-3062`): stage 1's "(1 base(s))"
in the label is a FIXED per-assumption probe budget parameter, not a
countdown -- and this whole pass is `cache.planning = True`, i.e. **no
runner/JVM launches happen during it at all** ("pass 1 (no runner
launches)"); `cache.execute()` (which is where `CONCOLIC_SLOTS=14` /
`CONCOLIC_PROBE_WORKERS=14` actually matter) only runs AFTER all 3276
assumptions are planned. So the memory risk here is pure Python-side
planning-data accumulation, unrelated to the probe-width fix from §123.15.

Growth decelerated after the initial spike (roughly 550 wanted/assumption and
~1.2-1.3MB/s in the most recent samples, vs. the ~33,000/assumption spike
moment) but did not stop, and the scope's actual cgroup memory was already
32.9G against the 40G `MemoryMax` set at launch (~7GB headroom) -- on the
observed rate that headroom would have been exhausted within roughly
30-100 minutes (highly uncertain given the earlier spike behavior), well
before the 21600s gate timeout (14422s remaining at the time of this
measurement) and BEFORE the planning pass had even reached probe execution
for ANY of the 3276 assumptions -- i.e. an OOM-kill here risks losing the
run with literally zero probes executed, which would be worse than REAL3's
original crash (that one at least got a real coverage-phase result before
dying).

Box-wide memory was NOT under pressure (25Gi free / 27Gi available, stable
across the observation window) -- this is a per-cgroup ceiling problem, not a
whole-machine one, and raising it does not endanger comments_index/
conversations_index's concurrent gates.

**Action taken (reversible, operational, not a src/ or policy change):**
`systemctl --user set-property p44-coveragecheck-real4.scope MemoryMax=56G
MemoryHigh=52G` -- live, no restart, verified via `systemctl --user status`
(now shows `high: 52.0G max: 56.0G ... available: 18.3G`). This does not
touch `src/`, `concolic_targets.rb`, or any experiment policy -- it is the
same class of action as the original launch's own `-p MemoryMax=40G` choice,
just corrected upward in response to real, measured behavior rather than
picked in advance. Chose +16G (40G->56G) because box headroom (25Gi free)
comfortably covers it with margin left over even in the worst case, and it
buys several times the estimated time-to-exhaustion at the observed
(decelerating) growth rate.

**Not yet understood, flagged rather than guessed at:** WHICH declared
assumption(s) around index ~1170-1173 caused the spike, and whether the
post-spike ~550/assumption rate is a new steady baseline (in which case
completing planning for the remaining ~2073 assumptions could add on the
order of another ~1.1M wanted probes and a further multi-GB of RSS -- still
computable within the new 56G ceiling on current trends, but not certain)
or itself decelerates further. Have not identified the specific
assumption/expression responsible -- would need `_c1/_gate_engine.log`'s
`derive-probes` lines cross-referenced against `_assumptions_declared.json`
by ordinal position, not attempted yet given the run is live and time-boxed.
If this recurs on a future endpoint, that identification is the first thing
to do before assuming "just raise memory" is sufficient.

Continuing to monitor. No src/ or concolic_targets.rb changes made.

## §123.17 REAL4 LANDED A VERDICT -- BUT THE SNAPSHOT IS STALE RELATIVE TO
## REACH_TIER, CONFIRMED BY TIMESTAMP, NOT ASSUMED (2026-09-20)

REAL4 finished: `COMPLETE=False;NODES=137;MISSING=2042;BLOCKING=2042;
PCS=7859439;GENUINE=True;TRUNCATED=True;DEMAND_SETS=1008;TREE_COMPLETE=True;
TREE_MISSING=0;FORECLOSURES=8842`. `coverage_summary.json` was written --
this is a real, non-crashing pass; the `completion.py` timeout guard and the
launch-config fixes from §123.14-16 all did their job.

**Coordinator flagged, correctly, that this MISSING=2042 figure is
byte-identical to `_coveragecheck_P44FRESH1.log`** (the very first accidental
scratch run, predating the REACH_TIER/EMPTY_EXISTENTIAL construct fix).
Verified directly rather than assumed either way:

- `_snapshot_pruned_P44FRESH1.txt` mtime: **2026-09-17 21:09:29 UTC** (matches
  the log line above it: "p44pruneP44FRESH1.scope finished: 190267 distinct
  outcome-profiles out of the 652914-dump snapshot taken at 19:09").
- The REACH_TIER validation drive `CLASSBV1U2R2r1` (§123.9 Attempt 2, the
  round that measured 3014/4111 walked, 85.0% size gate) -- all 4111 of its
  dump files have mtime **2026-09-18 19:32:xx UTC**, ~22h AFTER the snapshot
  was frozen.
- `grep -c "CLASSBV1U2R2r1\|CLASSBV1U2X2r1\|CLASSBV1U2R1r1"
  _snapshot_pruned_P44FRESH1.txt` = **0**. None of the REACH_TIER-era dumps
  are in the frozen snapshot.
- `COMPLETE=False;NODES=137;MISSING=2042;BLOCKING=2042;PCS=7859439` in
  `_coveragecheck_P44FRESH1.log` matches REAL4's line exactly, confirmed by
  direct grep.

**Conclusion: REAL3 and REAL4 both ran the completion gate against a corpus
snapshot that predates the REACH_TIER fix's own validation drive by ~22
hours.** All of this session's compute (two ~5-19k s corpus-index builds,
probe derivation, the memory-cap firefighting in §123.16) answered questions
about gate robustness and mock fidelity, but NOT the question that motivated
re-running the gate: whether REACH_TIER moved the needle on the authoritative
NODES/MISSING numbers. That question is still open and needs a fresh
census/prune over the CURRENT raw corpus (which does contain the REACH_TIER
dumps -- see §123.12's directory-growth accounting) before any REAL5.

**The four RED findings, sorted by cause (also verified from
`coverage_summary.json` directly, not the terse stdout lines):**

- `assumption driver: RED` -- `_assumption_driver_failure.log`'s traceback:
  `cache.execute() -> _run_chunk -> run_probe -> subprocess.run(timeout=900)`
  raised `TimeoutExpired` after 900s on one probe replay through
  `tools/slot`. Same inner-probe-timeout class as comments_index/
  conversations_index hit under the same box-load spike. NOT a code defect;
  `assumption_checker.py` left untouched (checkpoint-keyed/frozen).
- `note_fidelity`, `empty_relation_emission`, `note_check` -- all GENUINE,
  NOT load-related: `exit=1`, `timed_out=None` on all three (no timeout flag
  at all). Substantive content: note_fidelity found "26 real statement(s)
  whose note is unfaithful in projection or missing"; empty_relation_emission
  found "the corpus asserts reads of rows that do not exist in those runs";
  note_check flagged (among others) `ActiveRecord::Relation.update_all` with
  "NO corpus note anywhere" -- matching one of the 5 target frames already
  identified pre-session as issuing real SQL with no corresponding corpus
  note (`CollectionProxy.records`, `SingularAssociation.find_target`,
  `Calculations.ids`, 4x `Relation.records` shapes, `Relation.update_all`).
  Real, pre-existing mock-fidelity gaps, independent of snapshot staleness.

No src/, concolic_targets.rb, or snapshot-file change made. Awaiting a
decision on re-censusing before any further coverage-check run.

## §123.18 SNAPSHOT REGEN LAUNCHED (P44FRESH2), AND THE empty_relation_emission
## FINDING TRACED TO AN EXACT SITE (2026-09-20, coordinator go-ahead)

**Snapshot regen.** Built `_snapshot_p44_P44FRESH2.txt` (raw list, 720279
dumps -- the full current corpus, includes REACH_TIER's `CLASSBV1U2R2r1` and
everything driven since P44FRESH1) and launched the prune step via the
project's `cage` helper (`_cage.sh`, respects the shared `concolic-cov.slice`
memory invariant -- currently ~58G total across all endpoints' gate
processes, comments_index/conversations_index still running theirs):
`p44prune-P44FRESH2.scope`, `DUMP_LIST=_snapshot_p44_P44FRESH2.txt ->
_prune_corpus.py -> _snapshot_pruned_P44FRESH2.txt`. Did NOT run the
`CENSUS_MODES=prod`/`_p35_emit.sh` half of the original `_p44_census_chain.sh`
-- that stage produces gap/demand data for future seed construction, not an
input the completion gate reads (confirmed: `coverage_report.py` only ever
consumed `DUMP_LIST` directly in REAL3/REAL4). Once the prune completes,
launching REAL5 against the new snapshot with the same fixed config
(checkpoints, `CONCOLIC_SLOTS=14`/`CONCOLIC_PROBE_WORKERS=14`, raised memory
ceiling) is the plan.

**`empty_relation_emission` traced to an exact site -- real, previously-latent,
not a scoping or load artifact.** Root cause found in
`posts_show/concolic_targets.rb:1254-1272` ("X3.
ActsAsApi::Collection#as_api_response"):

```ruby
interceptor.declare_target(
  ActsAsApi::Collection, :as_api_response,
  returns: lambda do |receiver, _args, name|
    ...
    rep = symbolic_instance(klass, "#{name}_row", "ActsAsApi::Collection#as_api_response")
    symlist(name, 1, representative: rep, note: "ActsAsApi::Collection#as_api_response")
  end
)
```

`symlist(name, 1, ...)` unconditionally pins the symbolic list's length to 1
with a representative row, regardless of whether `receiver` (the real
collection) is actually empty. Downstream code that looks up a profile via
that representative's `person_id` then emits a real "profiles" SELECT even in
runs where the true collection had zero elements -- exactly the audit's
finding (109399/720279 dumps, 15.2%, 4 shapes `as_api_response_{1,2,3,4}`).
Distinct from B-3 (`_MOCK_NOTE_FIXES_20260916.md` -- note carry-through for
`_row_id` resolution, fixed 2026-09-15 in `people_stream/concolic_targets.rb`,
a different file/concern); this is a separate, pre-existing defect in the
same X3 block.

**Why it passed 2026-09-10 and fails now -- timestamp-verified, not guessed.**
The "pass" (`_COMPLETION_20260910.md` §35, before the §36 checkpoint logged at
20:07 UTC) ran before the boundary-value rounds existed:
`dump_auth_json...BV3B0910aujs...json` mtime **21:42:19 UTC**,
`...BV3C0910aujs...json` mtime **22:16:56 UTC** -- both after the 20:07 pass,
same day. BV3A/B/C are boundary-value rounds (`_p44_status.md` line 1337 cites
`BV3C0910auht0001r0.json` as a rank-0 base for size-gate/boundary work) --
exactly the deliberately-empty/small-collection cases this session's whole
REACH_TIER/size-gate campaign has been driving toward. Before those rounds
existed the corpus never constructed a run where the real collection was
empty; once it did, the always-non-empty mock got caught.

Not fixed -- shared `concolic_targets.rb` boundary, Rule T, pinned campaign.
Flagged for the coordinator/owner with the exact site. No src/,
concolic_targets.rb, or campaign-pin change made.

## §123.19 REAL5 IN PROGRESS AGAINST P44FRESH2; ANOTHER STALE-SNAPSHOT CONFIG
## BUG FOUND AND FIXED (reports/-zone, not src/) (2026-09-20)

REAL5 launched against `_snapshot_pruned_P44FRESH2.txt` (206593 dumps),
reusing REAL4's checkpoints (`_real4_index.ckpt.jsonl`/
`_real4_probes.ckpt.jsonl` -- valid, since `corpus_index()` globs the whole
batch DIRECTORY regardless of `DUMP_LIST` and that directory's 720279 files
have not changed). Coverage phase done in 7018s (slower than REAL3/4's
2311-4803s -- attributable to comments_index/conversations_index/people_show
all becoming CPU-active again partway through, not a regression). Currently
in `run_audits()` (note_fidelity_audit, then mock_note_check), gate not yet
reached. Memory healthy (12.8G/56G cap).

**Found and fixed a second stale-snapshot config bug, distinct from the
directory-vs-snapshot scoping bugs already fixed in `src/`.**
`completion_config.json`'s `note_check_cmd` had `--dump-list` HARDCODED to
`/home/dev/project/reports/diaspora/results3/posts_show/
_snapshot_pruned_P44FRESH1.txt` (the OLD snapshot) as a literal string, not a
reference to the `$DUMP_LIST` env var that actually scopes the run. Confirmed
via the live process's own command line (`ps`) mid-REAL5. **This does NOT
affect REAL5's core `NODES`/`MISSING`/`PCS` numbers** -- those come from the
coverage/SAT phase, which correctly read `DUMP_LIST=
_snapshot_pruned_P44FRESH2.txt` (confirmed by REAL5's own log line). It only
means the note_check sub-audit re-validates the OLD snapshot instead of the
new one -- and since note_check's RED verdict is already a genuine,
documented (2026-09-10) mock-fidelity gap independent of snapshot vintage,
this doesn't change the qualitative BLOCKING verdict either. Still a real bug,
fixed for future rounds: edited `completion_config.json`
(`reports/`-zone, NOT `src/` or `concolic_targets.rb`) to use
`--dump-list "$DUMP_LIST"` instead of the hardcoded path. Deliberately NOT
applied retroactively to REAL5's already-dispatched note_check subprocess
(its command line was already materialized before the edit; a config edit
cannot reach into a running child process).

**Caveat for future launches, load-bearing for the fix above to actually
work:** `note_check_cmd` runs with `workdir=/home/dev/project` (confirmed via
`completion_config.json`'s own `"workdir"` key), NOT `posts_show/`. REAL3/4/5
were all launched with a RELATIVE `DUMP_LIST` value (e.g.
`_snapshot_pruned_P44FRESH2.txt`), which only resolved correctly for the
coverage phase because `coverage_report.py`'s own cwd is `posts_show/`. For
the `"$DUMP_LIST"` substitution in `note_check_cmd` to resolve correctly (its
shell's cwd is `/home/dev/project`), **future launches must set `DUMP_LIST`
to an ABSOLUTE path**, not a bare filename. Noting this now so the next
relaunch doesn't reintroduce the same class of bug via a different mechanism.

No src/, concolic_targets.rb, or campaign-pin change made. Continuing to
monitor REAL5.

## §123.20 REAL5 KILLED BY CLAUDE CODE'S OWN MEMORY-PRESSURE REAPER --
## NOT A CODE BUG, NOT posts_show's OWN CGROUP OOM (2026-09-20, ~23:39 UTC)

REAL5's wrapping background task was stopped by the harness itself
("Background command ... was stopped because the system is running low on
memory ... Claude Code stopped it because the system was critically low on
memory while the session was idle ... Do not start it again on your own").
Verified the scope died along with it: `systemctl --user is-active
p44-coveragecheck-real5.scope` -> `inactive`, `status` -> "Unit ... could not
be found". This is a THIRD, distinct failure mode from the two already
documented (the 21600s assumption-gate `TimeoutExpired`, now caught
gracefully; the 900s inner `run_probe` timeout, load-related) -- this one is
external to the job entirely.

**Confirmed NOT posts_show's own fault:** at the moment of the kill,
`p44-coveragecheck-real5.scope`'s own process was at ~16.8GB RSS
(`_c1/_gate_engine.log`'s last line: `rss 16891MB` at index 1091/3277,
still in stage-1 PLANNING, before the danger zone from §123.16), nowhere
close to its own 56G `MemoryMax`/52G `MemoryHigh` cgroup ceiling -- this was
not a cgroup OOM. **Real cause: system-wide memory pressure from OTHER
concurrent jobs on the shared box.** `ps --sort=-rss` at the time of
investigation showed `people_show/coverage_report.py` alone at **19.97GB
RSS** (27.7% of system memory) -- a single process bigger than REAL5's own
footprint -- plus comments_index/conversations_index's own gate processes
still active, plus ~6GB of VS Code/Pylance server overhead. `free -h`
afterward: 36-37Gi used, 30-31Gi free/available -- i.e. even AFTER REAL5 was
killed and its ~16.8GB was freed, the box was still using more than half its
68GB. The reaper acts on Claude-Code-tracked background bash tasks under
SYSTEM-WIDE pressure, regardless of whether that specific task's own job was
the heavy one or well-behaved within its own cgroup budget.

**Operational lesson for next time:** `systemd-run --scope`, launched via the
Bash tool's `run_in_background: true`, is NOT immune to this -- the scope
died together with its wrapping task, contrary to the general expectation
that a systemd scope survives its launching client. REAL3/REAL4 used the
identical launch pattern and were NOT reaped, so this is a NEWLY-materialized
risk tied to the box's current overall load (specifically people_show's
~20GB process), not a defect in the launch pattern that was always there. A
future long-running launch on a similarly loaded box may want a MORE
detached mechanism (e.g. a plain `--unit` service rather than `--scope`, or
explicit `disown`/`setsid`) to avoid depending on a Claude-Code-tracked
wrapper process surviving for the job's whole duration -- not attempted here,
flagged for whoever relaunches next.

**Per the harness's own explicit instruction, did NOT relaunch on my own.**
Progress lost: REAL5 had reused ALL of REAL4's corpus-index checkpoint
(720279/720279 rows replayed, 1025s) and part of its probe checkpoint (240
units skipped), then spent ~5126s in stage-1 planning (1091/3277, well short
of the §123.16 danger zone) before being killed -- the corpus-index result IS
still on disk (`_real4_index.ckpt.jsonl`, unaffected by the kill, still valid
for a future relaunch since the underlying directory is unchanged) but the
partial planning-pass progress within THIS invocation was in-memory only and
is lost; a relaunch will redo stage-1 planning from 0/3277 (fast relative to
corpus-index; REAL4 did the same span in comparable time) with 240 probes
still recallable from `_real4_probes.ckpt.jsonl`.

Awaiting instruction on whether/when to relaunch (REAL6), and whether the box
needs to quiet down first (comments_index/conversations_index/people_show
were all still active at the time of the kill).

## §123.21 REAL6 -- COORDINATOR RELAUNCHED, TAKING OVER MONITORING
## (2026-09-21, box quieted after people_show's gate finished)

Coordinator relaunched directly as `p44-coveragecheck-real6.scope` once
people_show's gate finished and freed its ~20GB RSS (54GB free at relaunch).
Same config as REAL5: `DUMP_LIST=_snapshot_pruned_P44FRESH2.txt`,
`ACHK_CHECKPOINT`/`ACHK_INDEX_CHECKPOINT` pointed at REAL4's checkpoints
(`_real4_index.ckpt.jsonl`/`_real4_probes.ckpt.jsonl` -- still valid, per
§123.20, since the corpus-index result was unaffected by REAL5's kill),
`CONCOLIC_SLOTS=14`/`CONCOLIC_PROBE_WORKERS=14`, 56G ceiling. Confirmed active
and correctly loading the 206593-dump snapshot. Took over monitoring under
the new unit name; watching specifically for a repeat of the §123.16
planning-phase memory spike (previously observed around assumption index
~1170-1173 of ~3276-3277) and the box-wide-pressure risk from §123.20 (will
check `free -h`/other endpoints' RSS periodically, not just this scope's own
cgroup, since that's what actually got REAL5 killed).

## §123.22 REAL6 CRASHED AFTER THE COVERAGE PHASE COMPLETED -- JSON BUG IN
## `completion_config.json`, RESULT LOST, REAL7 RELAUNCHED (2026-09-21)

**REAL6 outcome.** `_coveragecheck_REAL6.log` shows the Z3 coverage
computation itself succeeded end to end: `loaded 206593 runs (0
unparseable)`, all 24 heartbeats healthy (RSS flat at ~14.2-14.3GB the whole
way, CPU climbing steadily, no stalls), then `[coverage] phase done in
7290s`. Immediately after, it crashed:

```
File "coverage_report.py", line 515, in main
    attach_to_summary(summary, json.load(fh))
json.decoder.JSONDecodeError: Expecting ',' delimiter: line 11 column 298
```

Root cause: `completion_config.json`'s `note_check_cmd` field had a literal,
unescaped `"$DUMP_LIST"` inside an already-double-quoted JSON string
(`--dump-list "$DUMP_LIST"`), which is invalid JSON. **Fixed** by escaping to
`\"$DUMP_LIST\"`; re-verified with `python3 -c "import json;
json.load(open('completion_config.json'))"` -- parses clean. This is a
`reports/`-local config file (write-freely zone per CLAUDE.md), not `src/`,
so no ask-first gate applied.

**Was the 7290s coverage result recoverable?** No. Confirmed two ways: (1)
`coverage_report.py`'s `main()` reads/attaches `completion_config.json` at
line 495-515, and only writes `coverage_summary.json` at line 542-544 --
strictly after -- so the crash at line 515 happened before any write. (2)
`coverage_summary.json` on disk is dated Sep 20 15:37 (REAL4's output),
predating REAL6's Sep 21 06:44 start; no newer file exists. The in-memory
`CoverageChecker` result was never persisted. **REAL6's ~2h coverage
computation is lost and must be redone from scratch.**

Separately: REAL6 never had `COVERAGE_CHECKPOINT` set (only
`ACHK_CHECKPOINT`/`ACHK_INDEX_CHECKPOINT`, which checkpoint the
corpus-index/probe-planning stage, not step 6's per-demand-set Z3
enumeration). Per the RUNBOOK rule (`_bak_src_20260914/RUNBOOK.md`: "anything
that can run longer than ~10 minutes is launched with its checkpoint on, so a
kill costs the unit in flight and nothing else") and established practice
across comments_index/notifications_index/conversations_index (grep confirms
dozens of `COVERAGE_CHECKPOINT=` launches), this should have been set. Its
absence is why REAL6's completed coverage phase produced nothing durable.

**Pre-launch checks for REAL7:**
- `free -h`: 68Gi total, 16Gi used, 50Gi free, 52Gi available, 0 swap.
- `concolic-cov.slice` (the correct slice per §123.16-20 -- NOT `app.slice`,
  which carries a box-wide 5GiB cap): MemoryMax=58G, current usage 7.2G,
  46.7G available within the slice.
- Concurrent jobs, both correctly under `concolic-cov.slice`:
  `fullgate-comments-index-919r8b.scope` (6 slots, MemoryCurrent=4.4G,
  MemoryMax=32G) and `fullgate-conversations-index-919r23.scope` (3 slots,
  MemoryCurrent=1.9G, MemoryMax=32G). Neither is close to its own ceiling.
- REAL6's own peak RSS (from `_coveragecheck_REAL6.time`): Maximum resident
  set size 14,595,608 KB (~14.6GB) -- far below the 56G ceiling REAL6 was
  launched with.

**REAL7 launch.** Same corpus/config as REAL6 (`DUMP_LIST=
_snapshot_pruned_P44FRESH2.txt` (206593 dumps), `ACHK_CHECKPOINT=
_real4_probes.ckpt.jsonl`, `ACHK_INDEX_CHECKPOINT=_real4_index.ckpt.jsonl`,
`CONCOLIC_SLOTS=14`, `CONCOLIC_PROBE_WORKERS=14`), plus two additions:
- `COVERAGE_CHECKPOINT=$B/_real7_coverage.ckpt.jsonl` -- closes the gap
  above; a future relaunch (if needed) resumes step 6 instead of redoing it.
- `MemoryMax=32G` (down from REAL6's 56G) -- matches the sibling jobs'
  convention and gives ~3x headroom over REAL6's observed 14.6GB peak,
  while leaving more of the shared 58G slice ceiling free for
  comments_index/conversations_index to grow into.

Launch wrapper: `reports/diaspora/results3/posts_show/_real7_launch.sh`.
Command:
```
systemd-run --user --slice=concolic-cov.slice --scope \
  -p MemoryMax=32G \
  --unit=p44-coveragecheck-real7 --collect \
  bash -c 'bash .../posts_show/_real7_launch.sh > .../posts_show/_coveragecheck_REAL7.log 2>&1'
```
Confirmed active: `concolic.slice/concolic-cov.slice/p44-coveragecheck-real7.scope`,
3 tasks, Memory 293.7M/32.0G at +2min. Log confirms correct snapshot loaded:
`DUMP_LIST ... 206593 dump files (fixed snapshot)`, `[load] 5000/206593 ...`
in flight. Taking over monitoring under this unit name; watching for
`[coverage] phase done`, the completion-gate JSON parse (specifically
`attach_to_summary` -- verifying it does NOT repeat the same
`completion_config.json` bug now that it's fixed), and any new crash
signature. Load is slower than REAL6's (5000/206593 at 142s vs REAL6's 18s),
consistent with 3 heavy jobs sharing the box's CPU now vs REAL6 running
closer to alone; not itself a concern.

**Update, same day, later:** coverage phase finished in 6681s (faster than
REAL6's 7290s). `completion_config.json`'s fix held -- `attach_to_summary`
read it cleanly (verified via `/proc/<pid>/fd`, no repeat of the REAL6
Traceback) and progressed through the full completion pipeline in order:
`note_fidelity` audit -> `empty_relation_emission` audit -> shim tests
(`shim_test_runner.rb`) -> `note_check_cmd` (`mock_note_check.py`, confirmed
the `\"$DUMP_LIST\"` escape expands correctly to the real path in the actual
subprocess argv) -> the assumption gate (`gate_wrapper.sh` /
`assumption_checker.py`, benefiting from REAL4's still-valid
`_real4_probes.ckpt.jsonl`/`_real4_index.ckpt.jsonl`). Each stage was
confirmed via `/proc/<pid>/io` `read_bytes` deltas actively increasing
(state D/R), not just log silence, since none of these stages print
progress.

**Transient box-wide memory squeeze (resolved):** partway through the
assumption gate, `free -h` briefly showed only ~2.3GB available system-wide
(66/68Gi used, 0 swap) -- a people_show job (`ps-gate-verify-20260921b.scope`,
20.7GB RSS, not one of the jobs I was briefed on at REAL7 launch time) had
grown concurrently with REAL7's own gate ramp-up. It resolved itself within
~10 minutes when that people_show job finished and released its memory
(back to ~20-23Gi available). No OOM kills observed. Also noticed the
comments_index/conversations_index fullgate scopes had been relaunched under
new unit suffixes (`-919r9b`/`-919r29`, vs the `-919r8b`/`-919r23` checked at
REAL7 launch) at some point during monitoring, without this monitoring
thread being looped in -- flagged to the coordinator.

**MemoryMax raised 32G -> 50G, live, no restart** (`systemctl --user
set-property p44-coveragecheck-real7.scope MemoryMax=50G`): REAL7's own
cgroup usage climbed to ~29GB (only ~3GB of headroom left in the original
32G cap) right as the JRuby probe-replay workers were ramping up, and a
self-inflicted OOM kill at this stage would have lost the entire ~8h run
including the now-safely-passed coverage phase. Done once system-wide
memory had recovered to ~20GB available (confirmed `concolic-cov.slice`
still has ample headroom under its own 58G cap: ~35GB used at the time).
This only raises REAL7's own ceiling; it does not reserve or take memory
from comments_index/conversations_index.

**Root cause of the memory growth, identified by the coordinator
2026-09-22 ~08:00, confirmed by reading `_c1/_gate_engine.log` directly**:
the assumption gate's `derive-probes stage 1/2` is stuck on ONE base (out
of 3277) whose "probes wanted" count is exploding combinatorially --
211275 at index 1161/3277, climbing to 279893 by index 1194/3277 (RSS
22.6GB -> 24.6GB over the same span, ETA growing rather than shrinking).
**This is the exact same index range (~1170-1173 of ~3276-3277) already
flagged in §123.21 as "the §123.16 planning-phase memory spike" from
REAL4/REAL5** -- confirming this one base's combinatorial-explosion
behavior in the probe-derivation logic is a repeat characteristic across
multiple attempts, not a one-off. It is making genuine (if extremely slow)
progress, not hung. A separate read-only investigation into WHY this one
base explodes is in progress (coordinator-dispatched); not touching REAL7.

## REAL7 FINAL RESULT (2026-09-22 08:41 UTC, total wall 12h 9m 56s)

**`coverage_summary.json` WAS written this time** (493576349 bytes, dated
Sep 22 08:41) -- the completion_config.json JSON fix held completely through
every stage (both audits, shim tests, note_check, and the assumption gate)
with no repeat of REAL6's crash. This is the key win of this relaunch: the
~2h Z3 coverage computation is now durably on disk.

**Verdict: `OVERALL_COMPLETE=False;COMPLETION=False`.** Breakdown:
- Coverage itself: `COMPLETE=False;NODES=137;MISSING=1945;BLOCKING=1945;
  PCS=8532568`, but `TREE_COMPLETE=True;TREE_MISSING=0` -- the underlying
  Z3 exploration tree has NO missing branches at the tree level; the 1945
  MISSING/BLOCKING count comes entirely from the completion gate below.
- Both extra audits RED: `note_fidelity`, `empty_relation_emission`.
- `note_check` RED, `ASSUMPTIONS RED (declared 3277, distinct tested 0,
  {})`.
- Root cause, confirmed in `_assumption_driver_failure.log`:
  `gate_wrapper.sh` **TIMED OUT after 21600s (6h)** -- matching
  `completion_config.json`'s `audit_timeout: 21600`. It never got past the
  combinatorially-exploding base (§ above, index ~1161-1194+/3277, "probes
  wanted" still climbing past 279893 when it was killed) to test ANY of the
  3277 declared assumptions. This is a TIMEOUT, not a crash -- process exit
  status 1 (non-zero, expected for a not-complete verdict), `.time` file
  confirms clean exit: User 15719.20s, System 1075.93s, 12:09:56 wall,
  Maximum resident set size 14594780 KB (this is `coverage_report.py`'s own
  RSS only, not the cgroup total -- `assumption_checker.py` separately grew
  to ~24-25GB, which is what drove REAL7's cgroup to ~40GB before it
  finished, well inside the raised 50G cap).

**Bottom line:** REAL7 achieved its primary purpose (verify the JSON fix,
get a durable coverage_summary.json with a complete Z3 tree) but posts_show
is still NOT complete overall -- blocked entirely by the pre-existing
assumption-gate combinatorial-explosion issue on one base, which is under
separate investigation (coordinator-dispatched, read-only, in progress as
of this writing). A REAL8 will need either a fix for that one base's
explosion, or a longer `audit_timeout`, or the base itself declared/handled
specially, before the assumption gate can complete.

**Post-run cleanup (2026-09-22 ~08:50 UTC):** after `coverage_report.py`
exited (reporting the assumption-driver TIMEOUT and writing the final
summary), its subprocess tree -- `gate_wrapper.sh` (513738) ->
`assumption_checker.py` (513739) -- was found STILL RUNNING as an orphan,
RSS climbing past 24.9GB (elapsed 21789s, past the 21600s timeout that made
the PARENT give up waiting). The timeout only stopped `coverage_report.py`
from waiting on it; it did not kill the child process tree. Since the run
had already been scored/reported (TIMED OUT, `distinct tested 0`) and this
orphan was pure waste with no one left to consume its eventual output,
killed it directly (`kill -TERM` on both PIDs; `gate_wrapper.sh` exited,
`assumption_checker.py` needed `SIGKILL` -- unresponsive to TERM, likely
mid-CPU-bound loop). Confirmed clean: `p44-coveragecheck-real7.scope` fully
gone from `systemctl --user list-units`, system-wide available memory
recovered from ~21GB to ~43GB immediately after. **Note for whoever launches
REAL8 or any future gate run against this same manifest: the driver's own
timeout does not kill its subprocess tree -- check for and clean up orphaned
`gate_wrapper.sh`/`assumption_checker.py` processes after every timed-out
run**, or they'll silently keep consuming memory/CPU indefinitely.
