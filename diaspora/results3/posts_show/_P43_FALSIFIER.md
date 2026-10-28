# P43 — THE 189 LEAK PAIRS: FALSIFIER, STATED BEFORE ANY MEASUREMENT
2026-09-15, agent owning posts_show. `src/` untouched, boundary untouched.

## THE HYPOTHESIS UNDER TEST
A `LEAK` refutation ("(i) flip-X changed a shape OUTSIDE footprint(X)")
disqualifies the *footprint measurement* that §16c needs, not the
no-cross-product *claim*. If so, a LEAK pair may still be genuinely
independent in the declared (GLOBAL, control-flow-argument) sense, and
declaring the survivors collapses 97.5 % of the residue
(WFAIL 882 556 -> WNOLEAK 22 363).

## FALSIFIERS — STATED NOW, HONOURED WHATEVER THEY SAY

**F1 (primary; the coordinator's, made numeric).** Run the corpus 2x2
(`tools/declared_pair_2x2.py`, `KEEP_NOTES=1`) over all 189. If **more than
25 %** of the 189 carry an INTERACTION cell (AND / NON-MONOTONE shape), the
LEAK-as-mis-measurement theory is WRONG — the leaks are marking real joint
access patterns — and the lever is DEAD. Report the split and STOP. Do not
filter down to whichever pairs happen to survive.

**F2 (yield).** If, after F1 passes and after per-pair leak characterisation,
the declarable survivors leave the re-passed residue above **50 %** of
882 556 (i.e. the lever recovers less than half of what the ladder predicted
for the full 189), the lever has not delivered and is reported as a partial
null, not as a closure.

**F3 (gate, corroborating only).** The flip-both independence probe is
ADDITIVE-ONLY (X11): it FAILs on a novel shape and is blind to dependence
that REMOVES reads. A PASS there is therefore WEAKER evidence than the 2x2.
A **FAIL** there is still decisive against the pair: any survivor that FAILs
the gate is dropped.

## WHAT COUNTS AS EVIDENCE FOR A DECLARATION
Per pair, all three, recorded:
 1. the leak's CAUSE — which shape, which side, and why the footprint was
    mis-measured (third-decision producer / alternate route), NOT merely
    "the footprint leaked";
 2. corpus 2x2 verdict = BENIGN (co-evaluated, four or more cells reachable,
    zero AND/NON-MONOTONE shapes). An INTERACTION cell disqualifies
    regardless of the leak story. OPEN is not evidence FOR;
 3. gate verdict PASS (corroboration), with its base count.

---

# RESULTS (filled in as measured — this file is the pre-registration + record)

## R1. THE LEAK, CHARACTERISED PER PAIR — ONE CAUSE, MEASURED, NOT A STORY

`_p43_leakcause.py` over ALL 237 175 dumps (4 workers), gate currency
(`call_shape`, KEEP_NOTES). `_p43_leakcause.json`, `_p43_leak_char.json`.

The 189 LEAK pairs name exactly **THREE** leaked shapes, all render-path:

```
  0  SingularAssociation.find_target | SELECT "posts".* FROM "posts" WHERE "posts"."guid" = ? |
       = Reshare#root  (belongs_to :root, class_name Post, foreign_key :root_guid,
         primary_key :guid — reshare.rb:8), reached from PostPresenter#root ->
         @post.absolute_root.  Present in 209 086 / 237 175 runs (88.2 %).
  1  Photo.url | Photo#url |              present in 204 774 / 237 175 (86.3 %)
  2  Photo.url | Photo#url | name:str     present in 198 652 / 237 175 (83.8 %)
       = PostPresenter#images -> photos.map(&:url) (post_presenter.rb:143)
```

Which side leaked: **A in 180 pairs, B in 9**. Shapes per pair: 2 in 153,
3 in 30, 1 in 6 — 402 (pair, shape) instances in total.

**Corpus contingency of each leaked shape against each decision.** Of the 124
two-armed decisions in the corpus, each of the three shapes is STRICTLY
ONE-SIDED for exactly **3** of them and appears on **BOTH ARMS of the other
121**. The three strict producers are the same three for all three shapes:

```
  (findpublic_act_1_not_found == True)   T: 0/7 893    F: 62 568/76 625
  (findpublic_act_1_public    == True)   T: 62 568/72 559  F: 0/4 066
  (evilq_act_public_1_not_found == True) T: 0/1 795    F: 38 579/39 404
```

i.e. **whether a post was found at all, and whether it was public** — the
post-existence decisions. Not one of them is a member of any of the 189 pairs.

**THE DECISIVE PER-PAIR NUMBER: for all 189 pairs and all 402 (pair, shape)
instances, the leaked shape appears on BOTH ARMS of BOTH members.** Never
strictly one-sided for either. (`_p43_leak_char.json`; tally
`{('BOTH-ARMS','BOTH-ARMS'): 402}`, no other cell.)

**So the leak is a FOOTPRINT mis-measurement with a named third cause**, and
the cause is the same for every pair: a flip probe rewrites a seed, the mocked
finder then returns a DIFFERENT concrete record, and whether that record is a
Reshare (root lookup) or carries photos (Photo#url) rides on the post-identity
decisions, not on the member being flipped. The replay's ΔA is confounded; the
matched-context footprint was not wrong so much as narrower than the probe.
This is exactly case (b) of the brief's discriminator — "the shape is produced
by a third decision / reachable through another route".

Corroboration from the gate's own ordering: criterion (i) is reached ONLY after
(iv), (v) and (viii) have PASSED, so for all 189 the gate had already found
that neither decision changes the other's outcome or leaves it unevaluated,
that no unshared footprint shape survives its own flip, and that every SHARED
footprint shape is OR-monotone across the four replay cells. Criterion (iii) —
the additive composition law, the direct interaction test — was never reached.
**A LEAK FAIL is a refusal to certify disjointness, not a finding of
interaction.** That much of the brief's theory is confirmed.

## R2. THE CORPUS 2×2 — `tools/declared_pair_2x2.py`, KEEP_NOTES=1

Run over **all 568 withdrawn pairs plus 4 controls**, not only the 189, so the
LEAK class has its own calibration inside the same measurement.

### R2.1 THE INSTRUMENT IS CALIBRATED — it reproduces DISCIPLINE's own table

DISCIPLINE §16c-X11's posts_show control table (six §64 negative controls,
measured on `_snapshot_pruned_p5.txt`) is reproduced exactly on P39R:

```
  W-F  find_by_1_not_found x find_by_2_not_found        INTERACTION (AND: Person.name)   [matches]
  W-C  Length(SYM_PARAM_id)<16 x find_by_1_not_found    INTERACTION (AND: Person.name)   [matches]
  SAME-REP x2 (find_by_3 not_found x text_*)            OPEN, only 2 of 4 cells          [matches]
```

### R2.2 THE FOUR-WAY SPLIT OVER THE 189 — AND THE CLASS CALIBRATION

`_p43_2x2_pilot.json`, list `_snapshot_pruned_P39R.txt` (49 576 dumps ->
47 753 (outcome,trace) profiles, 69 distinct shapes).

```
  LEAK        189   co-evaluated 189 (4 cells each)  BENIGN 128  OPEN 0  INTERACTION  61   32.3 %
  --- calibration, same run, same universe ---
  DOWNSTREAM  233   BENIGN 226                                   INTERACTION   7    3.0 %
  REMOVAL      75   BENIGN  61                                   INTERACTION  14   18.7 %
  UNEVIDENCED  57   BENIGN  53                                   INTERACTION   4    7.0 %
  OTHER        10   BENIGN  10                                   INTERACTION   0    0.0 %
```

No pair in the LEAK class is INERT and none has fewer than four cells: all 189
are genuinely co-evaluated in both polarities of both members.

**The calibration is the finding.** The LEAK class is the WORST of the five —
**ten times** the interaction rate of DOWNSTREAM, the class the gate refuted as
genuine additive dependence. If a LEAK refutation were merely a mis-measured
footprint, the LEAK class should look like OTHER or DOWNSTREAM. It does not.

### R2.3 HOW MUCH OF THE 61 IS INSTRUMENT ARTEFACT — MEASURED, AND REPORTED
### BECAUSE A HOSTILE READER WILL ASK. IT DOES NOT CHANGE THE VERDICT.

`_p43_cellsupport.py` records, per AND instance, the profile count of every 2×2
cell and of the cell the shape appears in.

```
  64 AND instances over the 61 pairs; every classification is `AND`, none NON-MONOTONE
  the 2x2 CELLS are fat:  thinnest cell >= 108 profiles, median 527, max 4 041
  the SHAPE is thin:      present in 1..26 profiles (median 4) of its one cell
  by shape:  Person.name | Person#name |        45
             ActiveRecord::Relation.evilq_act_vis |  |    16
             ActiveRecord::Relation.evilq_act_author |  |  2
             ActiveRecord::Relation.evilq_like_author |  | 1
```

Two caveats, both measured, both stated against my own interest:

1. **`Person.name | Person#name | ` is a shape the SHIPPED boundary cannot
   emit.** `concolic_targets.rb` X6i is `if false && defined?(Person)` —
   disabled on 2026-09-10 under DISCIPLINE D1 — and `targets.rb` W8 replaced it
   with a singleton stub that declares no target and emits no event. In the
   census list exactly **13 dumps of 49 576** carry it, and all 13 are one
   cohort: `dump_{anon,auth}_html00NN_W7ALL.json`, all written 2026-09-10
   20:38. So 45 of the 64 AND instances — and DISCIPLINE's OWN two named
   posts_show residual instances (W-F, W-C) — rest on 13 dumps from one
   superseded boundary configuration.
2. **A chance control.** Under the null "a shape with k occurrences falls where
   cell sizes put it", `p = Σ_cells (n_cell/N)^k`. Of the 64 AND instances,
   **7 are at p < 0.01** (5 at p < 0.001, driven by k = 10..26 occurrences of
   `evilq_act_vis` / `evilq_act_author` with empty notes) and **28 are at
   p ≥ 0.05** — indistinguishable from chance. Only **7 of the 61 pairs** carry
   an AND instance at p < 0.01.

**Why this does NOT rescue the lever.** A low-k AND is UNINFORMATIVE, not
benign: the corpus cannot tell whether the combination is needed. It is not
evidence FOR independence. And excluding the W7ALL cohort is a corpus filter
nobody has authorised, discovered only after it became convenient, which would
have to be applied to every other number in the campaign (footprints,
disqualifications, the residue ladder) to be coherent. The verdict below rests
on the corpus of record — the same universe every other posts_show number is
computed on.

**RAISED, separately and not as an excuse:** the corpus is BOUNDARY-
HETEROGENEOUS. Runs made under superseded target declarations sit in it and can
manufacture one-sided shapes. That reaches §16c footprints and disqualifications
as well as this census, and it reaches the four CLOSED endpoints' declared-pair
measurements in DISCIPLINE §16c-X11. Not investigated further here.

### R2.4 THE FULL CORPUS — SAME VERDICT, AND THE CALIBRATION GETS WORSE

Repeated over ALL **237 175** dumps (49 865 profiles, 70 shapes), with BOTH the
shipped `tools/declared_pair_2x2.py` verbatim and the local emission-widened
copy `_p43_pair2x2_full.py`. **Both print an identical tally**
(BENIGN 401 / INTERACTION 165 / OPEN 2 over the 568).

```
                        pruned P39R (47 753 prof)      full corpus (49 865 prof)
  LEAK        189       BENIGN 128  INTERACTION  61    BENIGN 128  INTERACTION  61   32.3 %
  DOWNSTREAM  233       BENIGN 226  INTERACTION   7    BENIGN 154  INTERACTION  79   33.9 %
  REMOVAL      75       BENIGN  61  INTERACTION  14    BENIGN  60  INTERACTION  15   20.0 %
  UNEVIDENCED  57       BENIGN  53  INTERACTION   4    BENIGN  52  INTERACTION   5    8.8 %
  OTHER        10       BENIGN  10  INTERACTION   0    BENIGN   7  INTERACTION   3   30.0 %
```

Two things to read here, and the second is the one that matters:

* **The LEAK verdict is corpus-stable.** Not merely the same count — the SAME
  61 PAIRS, set-identical across a 4.8x change in corpus size (`|A∩B| = 61`).
  This is not a small-sample effect.
* **DOWNSTREAM moved 7 -> 79 and LANDED ON TOP OF LEAK.** With the full corpus
  the instrument finds interaction in **33.9 %** of the class the confinement
  gate refuted as genuine additive dependence (`flip-X changed Y's outcome`) and
  in **32.3 %** of the LEAK class. Under the orientation-invariant instrument
  **the LEAK class is indistinguishable from the known-dependent class.**

## R3. THE GATE — ADDITIVE-ONLY, AND IT DISAGREES WITH THE 2×2

`_p43_gate.sh`, checker `5ae1b13c` (frozen), 8 bases, shared bank
(109 021 records carried over), canonical index. Wall 1 079 s, rc=1.

```
  RESULT: 189 distinct tested — PASS 146, FAIL 43, ERROR 0, NOT-TESTABLE 0, NOT-COMPARABLE 0
  every PASS went to 8 bases;  the 43 FAILs stop at first FAIL (1..8 bases)
  all 43 FAIL on the same three NOVEL shapes, present in flip-both and in
  neither single flip:
      ActiveRecord::FinderMethods.find_by  Reshare query (render_relation_sql failed…)
      ActiveRecord::FinderMethods.find_by  SELECT "likes".* FROM "likes" WHERE "likes"."target_id" = ?
      ActiveRecord::FinderMethods.find_by  SELECT "poll_participations".* FROM "poll_participations" …
```

**STATED PLAINLY, AS THE BRIEF REQUIRES: this probe is ADDITIVE-ONLY (X11).**
`_independence_once` FAILs only when `trace(flip-both) - (base ∪ trace(flip-A) ∪
trace(flip-B))` is non-empty. It is BLIND to dependence that REMOVES reads. A
PASS here is therefore WEAKER evidence than the 2×2; a FAIL is decisive against
the pair.

### R3.1 THE CROSS-TABULATION — THE TWO INSTRUMENTS DISAGREE ON 45 % OF THE CLASS

Identical on both universes (the 2×2 verdicts are set-identical):

```
                    gate PASS   gate FAIL
  2x2 BENIGN            94         34
  2x2 INTERACTION       52          9
```

* survive BOTH instruments: **94 of 189 (49.7 %)**
* disqualified by at least one: **95 of 189 (50.3 %)**
* **the instruments disagree on 86 of 189 pairs (45.5 %)**: 34 of the 43 gate
  FAILs (79 %) were called BENIGN by the 2×2, and 52 of the 61 2×2 INTERACTIONs
  (85 %) were called PASS by the gate.

Each instrument is blind where the other sees, exactly as X11 predicts. A pair
passing both is not a pair with two confirmations — it is a pair that two
partially-blind instruments both failed to catch, on a class where each catches
20-32 % when it looks.

## R4. THE VERDICT — **F1 FIRED. THE LEVER IS DEAD. NOTHING IS DECLARED.**

F1 as pre-registered: *more than 25 % of the 189 carrying an INTERACTION cell
refutes the LEAK-as-mis-measurement theory; report and STOP, do not filter down
to whichever pairs happen to survive.*

**Measured: 61 of 189 = 32.3 %, on both universes, the same 61 pairs.** Above
the line on the corpus of record and on the full corpus. The coordinator's
qualitative form — "more than a small minority" — is met by a third of the
class on any reading.

Three independent things say the same:

1. **32.3 % INTERACTION**, corpus-stable, set-identical across a 4.8x corpus.
2. **The class calibration.** On the full corpus the LEAK class (32.3 %) sits
   ON TOP OF the DOWNSTREAM class (33.9 %) — the class refuted for genuine
   additive dependence. The LEAK class is not distinguishable from known
   dependence by the instrument the brief names as primary.
3. **The gate, independently, FAILs 43 of 189 (22.8 %)** on combination-only
   `find_by` shapes — Reshare, likes, poll_participations — and it agrees with
   the 2×2 on only 55 % of the class. Only 94 of 189 survive both.

**What is NOT claimed.** The leak characterisation (R1) stands and is confirmed:
a LEAK FAIL refutes the measured FOOTPRINT, not the claim, and the gate's own
ordering proves criteria (iv)/(v)/(viii) had already passed. §114.2 and §16c's
scope ruling were RIGHT about that. What is refuted is the INFERENCE FROM IT —
that the class is therefore declarable. It is not: half of it is refuted by one
instrument or the other, and the half that survives does so on two instruments
that disagree with each other about 45 % of the class.

**Declared: 0 pairs.** Not the 128 2×2-BENIGN, not the 94 that survive both.
Filtering to 94 would be exactly the manoeuvre the falsifier forbids, and the
evidence needed to justify even one of them — a control-flow argument that the
pair cannot jointly reach anything new — is not available from these
measurements, which disagree with each other.

**Residue, unchanged:**
```
  shipped (W564, 564 withdrawn)   REMAINING 965 224   MISSING 706  BLOCKING 706
  WFAIL   (507 withdrawn)         REMAINING 882 556   -- the 57 unevidenced, ceiling, lead 1 dead
  the 97.5 % (WNOLEAK 22 363) IS NOT AVAILABLE. It required the 189.
```
No re-pass was run: with nothing declared the demand structure is unchanged and
a pass would reproduce P39R's `COMPLETE=False MISSING=706 BLOCKING=706`
by construction. `OVERALL_COMPLETE=True` remains NOT REACHABLE (§107).

## R5. WHAT THIS ROUND ADDS THAT IS NOT A NULL

1. **The leak has ONE named cause, measured over the whole corpus** (R1). Three
   render-path shapes; both on both arms of both members in all 402 instances;
   strictly one-sided for only the three post-existence decisions. Anyone
   re-opening this must start from that, not from "the footprint leaked".
2. **The declared-pair 2×2 is now measured on posts_show, all 568 withdrawn
   pairs plus controls, on both universes**, and it reproduces DISCIPLINE
   §16c-X11's published control table. `_p43_2x2_full.json`,
   `_p43_2x2_shipped.json`, `_p43_2x2_pilot.json`.
3. **The two instruments disagree on 45 % of a class.** That is a fact about
   the instruments, not about posts_show, and it bears directly on the
   ~6 600 replay-earned PASSes inside four closed endpoints (§16c-X11).
4. **The corpus is boundary-heterogeneous** and 13 dumps from one superseded
   configuration carry a shape that drives 45 of 64 AND instances here — and
   DISCIPLINE's own two named posts_show residual instances. Raised in R2.3.
5. **A chance control for `classify_cells`** (R2.3): 28 of 64 AND instances are
   indistinguishable from chance. `classify_cells` has no support threshold.
   Filed as an observation, not a proposed change to frozen `src/`.
