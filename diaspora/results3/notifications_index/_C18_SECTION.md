

## §31. C18 — THE TWO RULINGS MADE, WITH FALSIFIERS: RE-MINT IDENTITY AND THE OUT-OF-RANGE DISPATCH (2026-09-13)

Owner direction (Bali, 2026-09-13): *"make the fair assumptions that the
evidence supports, with a falsifier, and carry the endpoint through. Do not
park anything as 'owner ruling' that a declaration with a stated falsifier can
honestly cover."*

§30 left 84 gap-sets in four classes and two of them parked on an owner:
28 §13.3 multi-gate-unreachable, 24 re-mint/upstream aliasing, 1 identity
compare, 31 open. This round rules on the first two, refuses the third on the
evidence, and re-measures the fourth.

### §31.1 What was measured before anything was declared

Three whole-corpus instruments, all read-only, all re-derivable:

```
_c18_identity_census.py   130 822 dumps, canonicalised with THIS batch's
                          ALIASES (so the names counted are the CHECKER's
                          spellings), 4 workers, 2 m 52 s, peak 96 MB
_c18_profile_diff.py      the same corpus, split by whether all eight
                          SYM_NOTE_TYPE_PROFILE literals came back not_taken
_c18_a0_table.py          the 32 A = 0 gate prefixes x their 576 driven C16A
                          cubes, per gate literal
```

### §31.2 RULING 1 — RE-MINT-IDENTITY. The 24 aliasing leaves, closed.

**The mechanism, from the harness source.** `targets.rb:1071-1090`, the
`records`/`load_target` mock's loaded-target early return:

```ruby
tgt = a0.target
next(IterableSymbolicList.new(tgt.length, name: "#{abase0}_rows",
       note: "preloaded association ##{a0.reflection.name}: answered from the
              loaded target, no statement ..."))
```

`tgt` IS the list the upstream `CollectionProxy#records` materialise mock
produced. The two canonical names the checker keeps apart are two readings of
one value.

**The census — the whole corpus, not a sample.**

```
  29 canonical (re-mint, upstream) pairs
  139 585 paired observations       EQUAL 139 585      DIFFERENT 0
  re-mints minted with NO upstream in the run                    0
  runs pairing ONE re-mint with TWO upstream names               0
```

The last line is load-bearing: photos keeps SIX statement names (three owner
chains x {the real read, its empty-scope `AND (1=0)` variant}), so a re-mint
has two possible partners — but never both in one run, so declaring both
equalities never equates the two upstream names with each other.

**The active falsification (§79 / RENDER_IDENTITY model), because a census is
a passive observation.** `_c18_fals_construct.py` picked 64 bases across six
request variants that mint both names, with a per-association-family quota so
photos and aspect_memberships are exercised as hard as services, and replayed
each base with EVERY upstream length key it feeds a re-mint overwritten to v,
v over the mock's whole domain {0,1,2,3,4}. `_c13_drive.sh C18F 60`, 320 runs,
DRIVE_PAR=2, 10 m 47 s.

```
  replays 320   errors 0   runs with no pair minted 0
  the upstream length WAS realised, at three distinct values per family:
      seed 0 -> upstream 0 (167)   seed 1 -> 1 (167)   seed 2/3/4 -> 3 (501)
  paired observations 835   EQUAL 835   DIFFERENT 0
  19 of the 25 declared pairs exercised (the photos statement names the
  chosen bases did not all mint are the shortfall, stated not hidden)
  VERDICT  C18-FALSIFICATION PASS
```

**The declaration.** `coverage_assumptions.py`, tier `RE-MINT-IDENTITY`, 25
`SymbolicConstraintAssumption`s `SYM_LEN_<remint> == SYM_LEN_<upstream>` —
every alias/ordinal the corpus names BOTH of whose sides occur in a tracked
expression. The other four pairs (aspects / services / aspect_memberships x2
off the principal, 92 398 observations, 0 different) are equally true and
deliberately NOT emitted: their re-mint side is never a recorded decision
here, so no demand can name them, and an extra constraint over a variable the
declarations might not carry makes `solver.py` return unsat for EVERY query —
M-SNAP's stated failure mode, which looks exactly like completeness.

**Not an `AliasAssumption`, for RENDER_IDENTITY's reason.**
`_alias_core` keys on a STATEMENT note and the re-mint's note is the prose
"preloaded association #<assoc>: answered from the loaded target, no
statement" — by construction not a statement, since the whole point of the
early return is that no query is issued. The alias map comes back empty.

**Falsifier.** Any run recording a re-minted association length and its
upstream materialize length with different values. `_c18_identity_census.py`
IS that test over any dump list (~3 min); the C18F drive is its constructed
form. A Rule T change making the loaded-target return independently seedable
refutes the tier and withdraws it. `NO_REMINT_IDENTITY=1` withdraws it
without an edit.

**Gate.** As the brief predicted, the shipped derived test is NOT-TESTABLE on
this shape: `assumption_checker.test_declared` derives the single violating
value for a `VAR op INT` constraint, and `VAR == VAR` is not that form. The
active falsification above is run in its place and recorded, exactly as §79
did for RENDER_IDENTITY.

### §31.3 RULING 2 — GATE-CONJ-INFEASIBLE. The 28 A = 0 leaves, closed.

**The table the brief asked for, and it is uniform.** All 32 A = 0 gate
prefixes of the C16 enumerator, their 576 constructed cubes and 576 driven
C16A runs (`_c18_a0_table.py`, `_c18_a0_table.json`):

```
  prefixes                                              32
  driven cubes / driven runs                       576 / 576
  prefixes REALISED by any driven run                    0
  prefixes whose ONLY unsatisfied gate literal is
      ..._row_target_mentions_container_not_found    32 / 32
  that literal's verdict over its runs        NEVER-EVALUATED, 576 / 576
  consistency                                        100 %
  every OTHER gate literal of every prefix              HONOURED
```

It is not the same *pair* every time in the sense the brief anticipated (a
`g1=o1 forces g2!=o2`): it is the same *coupling* every time, between an
8-literal dispatch conjunction and one member.

**The mechanism, identified in the harness source.**
`build_notification_representative` (`targets.rb:872-901`) mints
`SYM_NOTE_TYPE_PROFILE` from a seed and compares it against every index of the
EIGHT-entry `NOTE_TYPE_PROFILES` table (`:209-241`), recording all eight
decisions unconditionally; an index outside 0..7 records all eight as
not_taken and leaves `profile = NOTE_TYPE_PROFILES.first  # defensive default
(idx out of range)`, so the run renders a `Notifications::Liked` with
`target_type: "Post"`. The `mentions_container` chain exists only on a
`Mention` target — indices 4 and 5 — and its container pin (`:1517-1529`) is
guarded by `if klass.name == "Mention"` and derives itself from
`@active_note_profile`. An out-of-range index therefore renders a Post-target
notification and never reads `target.mentions_container`.

**The ground-truth differential** (`_c18_profile_diff.py`, whole corpus):

```
                                OUT-OF-RANGE      IN-RANGE
   runs                                9 270       120 641
   mentions_container decided              0        41 042
   target_not_found   decided          9 014       116 828
   person_not_found   decided          8 282       112 456
   Core.find_by_1_not_found decided     1 349         2 452
```

The out-of-range state is reachable and is NOT declared away — 9 270 runs of
this corpus are in it (dispatch values 8, 424245, 424249, reached deliberately
by the C14/C16 constructors) and they decide every OTHER gate of these
prefixes. Exactly one member never co-occurs with it, in 9 270 of 9 270 runs,
for the reason the source gives.

**The declaration.** Tier `GATE-CONJ-INFEASIBLE`, four constraints — one per
`to_ary notifications` statement variant:

```
  Or(SYM_NOTE_TYPE_PROFILE == 0, ..., == 7,
     <variant>_row_target_mentions_container_not_found == True)
```

i.e. `Not( out-of-range AND the mention container was FOUND )`.

**The asymmetry, stated rather than hidden.** Only the FOUND direction is
declared. The full truth is "out of range implies the decision is never
MINTED", and over a free Z3 Bool excluding BOTH outcomes collapses to
`Not(out-of-range)` — which is FALSE, refuted by 9 270 runs. A free Bool
cannot express "this decision does not exist in that run", so the constraint
is written for the direction the residue demands and the other side is left
free and reported here.

**Falsifier.** Any run in which all eight dispatch literals are not_taken and
`..._row_target_mentions_container_not_found` is recorded not_taken.
`_c18_profile_diff.py` is that test. A Rule T widening of `NOTE_TYPE_PROFILES`
or any change that reads `mentions_container` off a non-Mention target
refutes it. `NO_GATE_CONJ=1` withdraws it without an edit.

**Active falsification, not only a census.** The 9 270 out-of-range runs are
not an accident of the corpus: 576 of them were CONSTRUCTED for exactly this
prefix by `_c14_construct.py`/`_c16_construct` (the seed writes
`SYM_NOTE_TYPE_PROFILE: 8`) and driven as C16A. The deliberate attempt to
realise the conjunction was made 576 times, the out-of-range dispatch WAS
realised every time (all eight literals recorded not_taken), and the container
decision appeared in none of them. That is the same shape of evidence §79
asks for, already spent.

**Gate.** `Or(...)` is not `VAR op INT` either, so
`assumption_checker.test_declared` returns NOT-TESTABLE here as well, and a
NOT-TESTABLE is not a licence (§24.4). The 576 constructed runs above are what
carries the claim; the full gate was not re-run because its `corpus_index`
leg (~40 min over 300 k dumps) would contend with the posts_show gate the cage
is holding, and it could only repeat the NOT-TESTABLE.

### §31.4 NOT RULED — `find_by_1_person_id == devise_user_first_1_person_id`

The brief asked: if the finder is called with the signed-in user's person id,
declare the identity. **It is not, and the corpus says so plainly.**

```
  runs minting BOTH person ids                     11 569
     values EQUAL                                   5 012
     values DIFFERENT                               6 557
  runs minting only one of the two                 87 837
  the COMPARE itself, over 129 521 indexed runs
     taken 2 577      not_taken 8 881
```

The decision is `PersonPresenter#own_profile?` /
`current_user.person == person` — "is this contact's person the signed-in
user's own person?" — a genuine free application state with both outcomes
observed thousands of times. An identity declaration would be refuted by 6 557
runs and is NOT made.

**What the leaf actually needs is a seed, and the constructor did not write
one.** The single gap-set (`37e4460e...`, width 13) demands the compare TRUE
with twelve other literals; 19 corpus runs match those twelve and all 19 record
the compare FALSE, and the C16A replay contradicted it. The C16 seed
(`_c16_seeds_html_typed.json#324`) writes
`devise_user_first_1_person_id = 0` and **no** `find_by_1_person_id` — a
var-var equality literal needs BOTH sides seeded to the same value and
`_c13_construct.synth` seeds only one. The dimension IS seedable: corpus dumps
carry `SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_id` in their
`concolic_seeds`. So this is a CONSTRUCTOR gap, not Rule T — the last Rule T
marking on this endpoint is dropped.

### §31.5 The 31 OPEN leaves, re-measured per key — and why §16e cannot reach them

**Per-key drive analysis** (`_c18_leafdrive.py`, class `open`, over the C16A +
C17A replays):

```
  31 leaves, 47 replays, 31 of 31 UNEVALUATED, 0 keys CONTRADICTED
  every leaf has EXACTLY ONE never-evaluated member (four have three):

    x16  (devise_user_first_1_person_profile_not_found == True)  = False
    x 7  (FinderMethods_exists__5_exists == True)                = False
    x 3  (FinderMethods_exists__5_exists == True)                = True
    x 1  (FinderMethods_exists__8_exists == True)                = False
    x 4  the three ..._row_target_statusmessage / _target_author
         members of one to_ary variant each
```

Nothing is contradicted. Each of the 31 is one decision short of its cube.

**A SECOND round was constructed and driven** rather than reported —
`_c18_gaps.json` (the 32 constructible cubes), `_c14_construct.py` with
`BASES_PER_GROUP=4`, plus 12 hand-overlaid seeds for the identity cube taken
from bases that RECORD the compare taken. `_c13_drive.sh C18R 30`, 44 runs,
6 min 18 s.

```
  C18R  per gap (32):  REALISED 0   UNEVALUATED 31   CONTRADICTED 1
        44 replays; dump errors {'-': 27, gon: 16, other: 1}
        the identity cube's demanded compare moved CONTRADICTED -> HONOURED
        (the overlay works); it now contradicts on the SPLIT SELF-COMPARE
        (find_by_1_person_id == ..._person_id__prior) demanded False, which
        seeding both ids equal necessarily makes True — the two are coupled
        through gon_helper.rb:6's "is this contact already stored?"
        the other 31 keep exactly the same single never-evaluated member
```

**WHY they are stuck, measured** (`_c18_minimal_cond.py`). For every open leaf
and its never-evaluated member, the MINIMAL subset of the leaf's own literals
under which the member is foreclosed (A > 0, B = 0) was searched to width 3:

```
  members with a foreclosing subset of width <= 3        39
     of them conditioned ONLY on GATE literals            0
     conditioned on at least one NON-GATE member         39
  members with no such subset (A > 0 all the way)       192
```

**Not one of them conditions on gates alone.** §16e forecloses under GATE
conjunctions by design (gates define the leaf; the falsifier's member list is
`surv - P`), so it structurally cannot reach any of these. Example, the
16-leaf family, A = 108-128 and B = 0 in each:

```
  member   (devise_user_first_1_person_profile_not_found == True) = False
  minimal conditioning
     True   (SYM_LEN_..._to_ary_notifications_<v>_rows > 1)
     True   (SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)
```

i.e. with more than one notification row AND the contact finder returning
nothing, the principal's profile decision is never minted — plausibly because
`gon_load_contact(note.contact)` never presents a contact, so
`ContactPresenter#full_hash_with_person` never reads it. **This is REPORTED,
not declared.** Declaring it would be doing by hand what §16e deliberately
restricts to gate prefixes, and the mechanism above is inferred from the call
graph rather than read end to end. It is a §16f question — *should foreclosure
condition on non-gate members?* — with its evidence attached
(`_c18_minimal_cond.json`), and it is the whole of what stands between this
endpoint and its remaining 31 sets.

**The `exists__5` / `exists__8` family (11 leaves) has a second, separate
cause.** Those names are `ActiveRecord::FinderMethods#exists?` call ORDINALS
(`Post.exists?(guid:)` from a `diaspora://` link in a rendered text or bio,
`targets.rb:1280-1347`), and the endpoint's `AliasAssumption`s cover only
`Relation_records` / `Relation_to_ary` / `CollectionProxy_records` — not this
family. The ordinal moves with the path prefix, so "the same decision" is
several canonical names. That is a P0/P1-shaped alias question for a family
whose gate test (which probes by intervening on `len(<ordinal>_rows)`) has no
length dimension to probe, so it is reported, not declared.

### §31.6 THE PASS — 84 -> 60, and every closed set is the RE-MINT class

`_c18_pass.sh _snapshot_c16_R2.txt C18R1` — the SAME 130 822-run corpus the
C17R2 verdict was measured on, so the only thing that moved is the two
declarations. (`_c16_pass.sh` was copied to `_c18_pass.sh` first; §29.9's
rule. The C18F/C18R runs are deliberately NOT in this corpus — they are folded
in by the R2 pass below, where their effect can be told apart from the
declarations'.)

```
COMPLETE=False;NODES=441;MISSING=40;BLOCKING=36;PCS=8335525
GENUINE=True;TRUNCATED=True;SOLVER_LOST=0;UNEVALUABLE=[]
CONJ_FORECLOSURES=89;CONJ_GROUPS=89;CONJ_PROVISIONAL=False;UNMATCHED_CONJ=8;FORECLOSURES=5278
dump_errors={'ActionView::Template::Error': 45917, 'I18n::InvalidLocale': 1}
coverage phase 1 129 s   wall 39 m 03 s   peak RSS 5 409 MB
VERDICT C18-C18R1: OK (line present)      C18-PASS-DONE C18R1
[assumptions] ... M-SNAP=8 RE-MINT-IDENTITY=25 GATE-CONJ-INFEASIBLE=4 ...
```

```
                        C17R2        C18R1
  MISSING                  68           40
  BLOCKING                 64           36
  UNMATCHED_CONJ           12            8
  distinct witness leaves  64           36
```

`_c16_gapdelta.py _cov_c16_C17R2.ckpt.jsonl -> _cov_c18_C18R1.ckpt.jsonl`

```
  demand universe: shared 1630, only-before 0, only-after 0
  CLOSED 24   NEWLY GAPPED 0   STILL GAPPED 60
  of the still-gapped: witness leaf UNCHANGED 32, REPLACED 28
```

**Per class:**

| class at C17R2 | sets | after C18R1 | why |
|---|---|---|---|
| re-mint / upstream aliasing | 24 | **0 — CLOSED** | `RE-MINT-IDENTITY` makes `upstream > 1 AND re-mint == 0` UNSAT |
| §13.3 A = 0 multi-gate | 28 | 28, **new witness leaf** | `GATE-CONJ-INFEASIBLE` killed the FOUND-side leaf; the sibling leaf pins the same gate NOT-FOUND |
| Rule T identity compare | 1 | 1 | not an identity; a constructor gap (§31.4) |
| open (A > 0, assignment never produced) | 31 | 31 | §31.5 |

Nothing was newly gapped and no observed profile lost its demand — checked
before the pass with the engine's own solver (`_c18_solver_check.py`: the 28
A = 0 and 24 re-mint leaves go SAT -> unsat, the 31 open and the 1 identity
leaf stay SAT, all 37 constraints parse and are jointly satisfiable, and 0 of
400 sampled OBSERVED run cubes are made unsat).

### §31.6a The 28 did not close, and the reason is the asymmetry the
### declaration ITSELF wrote down — measured, not discovered afterwards

`GATE-CONJ-INFEASIBLE` declares only `Not( out-of-range AND container FOUND )`.
The pass shows exactly the predicted consequence: all 28 sets kept their gap
with a NEW witness leaf that is the same cube with the container gate flipped,

```
  all eight (SYM_NOTE_TYPE_PROFILE == k) not_taken
  AND  ..._row_target_mentions_container_not_found  == True   (NOT FOUND)
```

and the pass's own `unmatched_gate_conjunction_prefixes` went 12 -> 8, all
eight of them that shape. Both outcomes are genuinely unreachable under an
out-of-range dispatch — the decision is never MINTED — but as Z3 constraints
the two directions together are `Not(out-of-range)`, and 9 270 runs of this
corpus refute that, so declaring the second one is not available. Declaring it
anyway would also be the `split_self_compare` bug from the other side: a
demand set whose only observed cubes are out-of-range would report
`covered == 0`.

**What actually stands in the way is one line of §16e**, and the question is
now precise enough to answer in one:

> §16e says *"Gates are never conjunction-foreclosed. They DEFINE `P`."*
> `..._row_target_mentions_container_not_found` is a GATE of these leaf
> groups, so it can never be foreclosed — even though it IS foreclosed under
> a SUB-conjunction of its own gate prefix: over the eight dispatch literals
> alone, **A = 9 270 and B = 0**, measured on this corpus, with the mechanism
> in `targets.rb:872-901` / `:1517-1529`.

That is a §16f question — *may a gate be conjunction-foreclosed under a proper
sub-prefix of its own leaf-group conjunction?* — and it is the whole of the
28. It is an `src/` change and is NOT made here.

### §31.7 Ops

Cage 24 G shared with the posts_show confinement gate (never stopped; it held
11.0-11.7 G throughout). Every launch gated on `free -g >= 4` AND
`(24 G - slice MemoryCurrent) >= cap`, both logged; the pass additionally
gated INSIDE the unit on `pgrep -a python3 | grep -q
"posts_show/coverage_report[.]py"` being empty, per the 2026-09-13 rule.
`_c16_pass.sh` was NOT edited — it was COPIED to `_c18_pass.sh` first (§29.9's
rule), and nothing was edited while running.

```
  notif-c18-census-1      4G   2 m 52 s   peak    96 MB  130 822 dumps
  notif-c18-profdiff-1    -    2 m 40 s              -   130 822 dumps
  notif-c18-falsconstr    -         6 s              -   320 seeds
  notif-c18-driveF        6G  10 m 47 s   DRIVE_PAR=2, JRUBY_CAP=2G, +320 dumps
  notif-c18-solvercheck   -   ~ 6 min               -   3 000 runs, engine solver
  notif-c18-construct-R   -         6 s              -   46 + 12 seeds
  notif-c18-driveR        6G   6 m 18 s   DRIVE_PAR=2, +44 dumps
```

No `src/` edit, no `targets.rb` edit, no shared-boundary edit, no extraction,
no git, nothing under `posts_show/` or `comments_index/`. The only project
file changed is `notifications_index/coverage_assumptions.py`
(backup `_bak_coverage_assumptions_pre_c18_20260913.py`).

### §31.8 Artefacts

```
_c18_identity_census.py / .json / _c18_census.log / _c18_census.sh
                                       29 pairs, 139 585 obs, 0 different
_c18_profile_diff.py / _c18_profile_diff_pre.json
                                       OOR 9 270 runs, 0 mentions_container
_c18_a0_table.py / _c18_a0_table.json  32 prefixes x 576 runs, 100 % uniform
_c18_fals_construct.py / _c18f_construct.log / _c18f_seeds_*.json /
_c18f_manifest.json                    320 seeds, 64 bases, 6 variants
_c13_drive.sh C18F -> _c18f_drive_outer.log / _c13_drive_C18F.log
_c18_fals_classify.py / _c18f_classify.json      PASS, 835 equal, 0 different
_c18_solver_check.py                   28 constraints parse; 28 A0 + 24 re-mint
                                       leaves SAT -> unsat; 31 open + 1 identity
                                       still SAT; 0 of 400 observed run cubes killed
_c18_leafdrive.py / _c18_leafdrive_open.json     per-key drive of the open class
_c18_minimal_cond.py / _c18_minimal_cond.json    39/39 foreclosures need a
                                                 NON-GATE member
_c18_gaps.json / _c18r_seeds_*.json / _c18r_manifest.json / _c13_drive_C18R.log
_c18r_classify_C18R.json
_c18_pass.sh (copy of _c16_pass.sh)    _c18_cov_C18R1.log / _c18_cov_C18R1.time
_cov_C18_C18R1.json / _cov_c18_C18R1.ckpt.jsonl
_c18_snapshot.sh / _snapshot_c18_R2.txt (131 186)
_bak_coverage_assumptions_pre_c18_20260913.py
```


### §31.9 WHERE THE ENDPOINT STANDS AFTER C18

```
  C12 (cap 4)  298 sets with a gap
  C13 R1       227   (-71,  1 554 runs)
  C13 R2       227   ( -0,    406 runs)     rate rule fired
  M-SNAP       184   (-43,      0 runs)     a declaration (§26)
  C14 R1       105   (-79, 10 396 runs)
  C14 R2       103   ( -2,  2 555 runs)     rate rule fired
  C15 R2        84   (-19,      0 runs)     §16e in src/ (§28)
  C16 R1        84   ( -0,  1 192 runs)
  C17 R2        84   ( -0,    109 runs)
  C18 R1        60   (-24,      0 runs)     TWO declarations (§31.2, §31.3)

  CURRENT   COMPLETE=False; NODES=441; MISSING=40; BLOCKING=36;
            DEMAND_SETS=1630; tree_missing 0   (_cov_C18_C18R1.json)

  60 gap-sets = 28  A = 0 gate conjunction, out-of-range dispatch x the
                    mentions-container GATE  -> §16f, one line of §16e
              + 31  A > 0, one member never evaluated under the leaf's own
                    other literals; 39/39 of the foreclosures that explain
                    them need a NON-GATE member -> §16f, same line
              +  1  the identity compare: a CONSTRUCTOR gap (a var-var
                    equality needs both sides seeded), no longer Rule T
```

**Rule T is now empty on this endpoint.** §30 dropped the 24 aliasing leaves'
Rule T marking; §31.4 drops the last one. No change to the shared target
boundary is required by anything in this residue.

**All three remaining classes are ONE question**: may a decision be
foreclosed under a conjunction that is not exactly its leaf group's gate
prefix — a proper sub-prefix (the 28), or a conjunction containing non-gate
members (the 31)? Both are measured on the corpus, with A and B per (leaf,
member), in `_c18_a0_table.json`, `_c18_profile_diff.json` and
`_c18_minimal_cond.json`. The remaining 1 needs a constructor that seeds both
sides of a var-var equality.

### §31.10 R2 — the round's own runs folded in

`_c18_pass.sh _snapshot_c18_R2.txt C18R2` (131 186 runs = C18R1's corpus + the
320 C18F falsification runs + the 44 C18R construction runs) was launched at
08:28 and is QUEUED behind a posts_show `coverage_report.py` by the
coordinator's one-pass-at-a-time gate, which fired correctly from inside the
unit. Its purpose is to separate the declarations' effect (C18R1, same corpus)
from the new runs' effect; the C18R classification already says what to expect
from the construction half — 0 of 32 cubes realised.
