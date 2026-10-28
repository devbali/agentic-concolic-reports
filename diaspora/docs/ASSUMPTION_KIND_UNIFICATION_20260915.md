# Design note — independence and confinement license the same thing

**Status: OWNER RULING, 2026-09-15 — DO NOT MERGE. The two kinds STAY
SEPARATE.** Raised by the owner, examined in depth (sub-agent analysis below),
briefly ruled a merge, then **reversed to KEEP SEPARATE on 2026-09-15**. The
required follow-up — documenting the SCOPE difference wherever these kinds are
described — is recorded in §0 and is DONE in `DISCIPLINE.md` §16c; the two
`src/` docstrings are QUEUED (see §0.3).

---

## §0. OWNER RULING — keep separate, and document the scope difference

**Are `IndependenceAssumption` and confinement the same claim? YES** — same
licence: this pair needs no cross product. **Are they the same KIND? NO, and
they stay separate.** The merge was considered and rejected.

**Why separate wins.** The two differ in SCOPE — *where the claim is valid* —
and that difference is not cosmetic:

| | declared independence | confinement (§16c) |
|---|---|---|
| who makes it | a person, by hand | the checker, derived |
| evidence | the author's rationale | measured footprints + standing disqualifier |
| **SCOPE** | **GLOBAL — every evaluation set holding the pair** | **WITHIN ONE LEAF ONLY** |
| refuted by | flip-both probe (X11-blind) | flip A / B / both, criteria (i)-(viii) |
| continuously falsified? | no — probed once at the gate | yes — counterexample search every pass |

A footprint is measured over matched contexts (runs with the SAME tree shape),
so it is evidence about ONE LEAF and says nothing about any other. A merged
type would have to carry that as a `scope` field with no safe default, since a
wrong value is silent in both directions: a derived pair applied globally
removes edges from sets the measurement never spoke about (demand shrinks,
MISSING drops, `complete` flips true, no error); a declared claim narrowed to
one leaf silently changes what its author asserted. **Two kinds encode that
distinction in the type system for free. One kind turns it into a field that
can be defaulted wrong.**

The gate paths cannot merge either: criterion (iv) is a KIND discriminator, and
27 041 of notifications_index's declarations plus 1 115 of posts_show's FAIL it
while being TRUE. See the analysis below.

### §0.1 What was ruled

1. **No type merge.** `IndependenceAssumption` and `ConfinementAssumption`
   remain distinct kinds.
2. **No gate merge.** Do not import confinement's footprint criteria — (i),
   (ii), (iv), (v), (viii) — into the declared path.
3. **Document the scope difference wherever either kind is described.**

### §0.2 Done

- `DISCIPLINE.md` §16c now opens with a SCOPE block: the comparison table, why
  confinement is leaf-local and can never be applied globally, the silent
  hazard in both directions, and why (iv) must not cross over.

### §0.3 Queued — the two `src/` docstrings

Deferred deliberately: `coverage.py` is being edited by the live posts_show
campaign (the §16f conditioning change) and `assumptions.py` is in
`_phase_keys`, so a byte change there invalidates the index/derive checkpoints
(~15 min rebuild). Neither touches the probe bank. Do both when the campaigns
quiesce:

- `src/concolic_engine/assumptions.py` — `IndependenceAssumption`: state that
  its scope is GLOBAL (every evaluation set holding the pair), that this is the
  difference from §16c confinement, and that confinement's leaf-local criteria
  do not apply to it.
- `src/concolic_engine/coverage.py` — confinement block: state that the
  relation is valid WITHIN A LEAF ONLY because footprints are measured over
  matched contexts, and that applying it globally is unsound and silent.

### §0.4 Still worth building, independent of all the above

The **standing disqualifier search** extended to declared pairs, report-only —
the counterexample scan that runs at load on every pass. It needs no footprint,
so it applies to declared claims as-is, and it is the one benefit in this note
that is both real and currently absent. Falsifier: `missing` and `complete`
byte-identical on all five corpora, new field non-empty on at least one.

---

## §0.5 The original merge sketch (SUPERSEDED — kept for the argument)

### The shape

**One type, one licence, provenance-dispatched evidence.**

```
NoCrossProductAssumption(pair, provenance, evidence, scope, grade)
    provenance : DECLARED | DERIVED_FOOTPRINT      # REQUIRED, no default
    scope      : GLOBAL_PAIRWISE | WITHIN_LEAF     # REQUIRED, no default
    evidence   : author rationale | footprints + disqualifier search
    grade      : gate verdict + X12 base counts
```

**In plain words, because these two field names are not self-explaining:**

- **`provenance` = WHO MADE THE CLAIM.** A person wrote it by hand, or the
  checker derived it from measurements. Nothing more.
- **`scope` = WHERE THE CLAIM IS VALID.** Everywhere that pair of decisions
  appears, or only inside one leaf of the tree.

These are not new concepts. They are the two facts the CLASS NAME carries
today: "it is an `IndependenceAssumption`" silently means *hand-written,
applies everywhere*; "it is a `ConfinementAssumption`" silently means *derived
from footprints, valid only within a leaf*. Merge the classes and that
information has nowhere to live unless it becomes explicit data. That is the
entire reason these fields exist.

Scope is the dangerous one. A footprint is measured by comparing runs with the
SAME tree shape — i.e. inside one leaf. Such a measurement says nothing about
any other leaf. Apply it globally and the pair removes edges from evaluation
sets the measurement never spoke about: demand shrinks, MISSING drops,
`complete` flips true, and nothing errors. A wrong default here is silent and
optimistic, which is this project's recurring failure shape.

Three rules, each forced by evidence in the analysis below:

1. **The licence path is shared.** Both provenances resolve to the same
   thing in `coverage.py`: no cross product for this pair. This is the merge.

2. **The test path DISPATCHES on provenance. This is not a compromise — it is
   what the evidence requires.** Confinement's criterion (iv) ("flipping A
   leaves B evaluated") is a KIND discriminator, not a licence check: it asks
   *confinement or foreclosure?*, not *is this claim true?*. It FAILs by
   construction on mutually-exclusive dispatch claims, which are 27,041 of
   notifications_index's declarations and 1,115 of posts_show's — all true.
   Importing (iv) into the declared path would withdraw them and re-open four
   closed endpoints.

   ```
   shared   : (iii), the corpus 2x2, and the standing disqualifier search
   DERIVED  : (i)(ii)(iv)(v)(viii)      # footprint-based
   DECLARED : flip-both + X11's symmetric fix
   ```

   Confinement's evidence is better *for the pairs confinement can measure*.
   Declared claims are dominated by pairs it CANNOT measure — a footprint needs
   matched contexts (same tree shape), and these are exactly the pairs whose
   flip changes which decisions are evaluated. That is also why X11 was fixed
   in one path and not the other: the paths cover different populations.

3. **Retire the source-pattern keying rather than reconcile it.** All 38,486
   `IndependenceAssumption` rows across `results3/` are expr-keyed; not one
   carries a source. The pattern layer is dead in practice, and keeping it
   would leave a matcher that can expand one declaration to 12x12 pairs.

### What transfers from confinement to declared claims

The **standing disqualifier search** — a counterexample scan run at load on
every pass, contradicting claims as evidence accumulates instead of probing
once at gate time. It needs no footprint, so it applies to declared claims
immediately. This is Stage 3 below and is the first thing to build.

### Silent-failure risks, both directions

- `scope=WITHIN_LEAF` defaulted onto a DECLARED claim silently NARROWS what
  the author declared.
- `scope=GLOBAL_PAIRWISE` defaulted onto a DERIVED pair silently BROADENS it:
  footprints are valid only inside a leaf, and the pair would remove edges from
  evaluation sets the measurement never spoke about — fewer cubes, lower
  MISSING, `complete` flips true, **no error**.

Hence: both fields REQUIRED, no defaults, plus a property test that the two
scopes produce different demands.

### Order of work, and the falsifier at each step

Build in the analysis's stage order (Stage 3 -> type merge -> gate dispatcher);
its per-stage falsifiers are adopted as written. Two facts set the sequencing:

- The **type** merge costs ZERO probe replays (`ProbeCache`'s engine key
  hashes `assumption_checker.py` only; `assumptions.py` is not in it).
- The **gate** dispatcher destroys the probe bank on any byte change. It is
  campaign-gated: not while an endpoint is mid-gate.

**Overall falsifier, unchanged:** byte-identical verdicts on every closed
endpoint. This refactors provenance, not licence; any verdict that moves means
the semantics changed and the implementation is wrong. Nesting re-pinned by the
existing property tests on random corpora.

**Standing prediction to check, not to rescue:** if (iv) is ever applied to
declared claims, the closed-endpoint differential WILL fail. That failure is
the falsifier for the claim that (iv) is general. Do not relax the differential
to make it pass.

---

## The observation

`IndependenceAssumption` and confinement (`ConfinementAssumption`, §16c) are
two assumption kinds that grant the **same licence**: a pair of decisions needs
no cross product. Confinement's own docstring in `coverage.py` states it
directly — "A confined pair needs no cross product". Same pairwise shape, same
effect on the demand, both applied inside a demand set.

They are not two ideas. They are one idea with two provenances.

## What actually differs

The difference is epistemic, not semantic. Four things, all real, none of them
about *what is licensed*:

1. **Confinement has a mechanised proof; independence has an assertion.**
   Confinement: suppose a shape `Z` required both outcomes, `A=x ∧ B=y ⇒ Z`.
   Then in any matched context with `B=y`, flipping `A` toggles `Z`, so
   `Z ∈ footprint(A)`; symmetrically `Z ∈ footprint(B)`; disjointness refutes
   `Z`'s existence. Independence rests on the author's reasoning about access
   patterns — which is why `assumptions.py:198` calls it, in caps, the most
   dangerous assumption in the system.

2. **Confinement is continuously falsified; independence is tested once.**
   A counterexample search runs at load on EVERY pass: for every confined
   decision and every shape in its footprint, one run anywhere in the corpus
   with the decision on its non-enabling side and the shape present
   DISQUALIFIES it (`confinement_disqualified`, run and shape named).
   Independence is probed at the gate and otherwise trusted.

3. **Confinement knows where it is valid; independence does not.**
   Footprints are measured over matched contexts — pairs of runs with the SAME
   tree shape — so the claim holds only WITHIN a leaf, and the implementation
   enforces that by splitting demand sets into gates ∪ cliques. Independence
   removes the pairwise edge wherever both expressions appear.

4. **Confinement checks its preconditions and refuses itself.**
   Tree incomplete ⇒ footprints PROVISIONAL and the combination claim declined.
   No matched contexts ⇒ undecidable, stays fully demanded. No trace layer ⇒
   projection is the identity. It also carries a proven nesting
   (`weak ⊆ strict ⊆ §16b ⊆ §16`) pinned by property tests on random corpora.
   Independence has none of this.

**Accurate one-line description: confinement is independence, derived instead
of asserted, bounded to a leaf, proven nested, and continuously falsified.**

## Foreclosure is NOT in this family

§16b/§16e/§16f/§16g are a genuinely different claim and should stay a separate
kind. Independence and confinement deny an *interaction* — both outcomes still
occur, they just need not be paired. Foreclosure denies that an outcome
*exists* in a context: given `C`, `d` never occurs. It removes specific
combinations rather than a product, its evidence is corpus co-occurrence
(`A(C)>0, B(C,d)=0`) rather than footprint disjointness, and its refutation is
a WITNESS (build a run exhibiting `C ∧ d`), not a perturbation (flip A, watch
B's footprint).

That difference in refutation is why the gate work authorised on 2026-09-15
makes foreclosure a construction-attempt test with a mandatory positive
control, rather than reusing the flip probe.

## Why the split exists

Historical, not principled. Independence came first and was hand-written.
Confinement was added (2026-09-11) when it became clear that nobody can
hand-write thousands of pairwise claims. The derivation made licences cheap to
CREATE while testing them stayed expensive — roughly 100k probes for
posts_show's 2,701 — and that cost asymmetry is exactly where an unearned
completion number hid: `MISSING=147` rested on 2,701 licences of which not one
had ever been probed, and became `MISSING=710` once the gate tested them.

## If it were designed today

ONE assumption kind — "no cross product for this pair" — carrying a
provenance/evidence field rather than two kinds that happen to license the same
thing:

```
NoCrossProductAssumption(pair, provenance, evidence, scope, grade)
    provenance : DECLARED | DERIVED_FOOTPRINT | (future derivations)
    evidence   : the author's rationale | measured footprints + disqualifier search
    scope      : GLOBAL_PAIRWISE | WITHIN_LEAF
    grade      : from the gate — bases_probed/realising/passing/failing (X12)
```

The benefits are not cosmetic:

- **One gate path.** `_test_confinement` and the independence flip-both probe
  are near-duplicates today; X10 (flip-both never ran on canonicalising
  endpoints) and X11 (gate blind to removal) were defects in ONE of the two
  paths, found separately, at separate cost. One path fails once.
- **Declared claims inherit the standing disqualifier search.** Point 2 above
  is currently a confinement-only safety net. There is no reason a hand-written
  independence claim should not also be disqualified the moment the corpus
  contradicts it.
- **`scope` becomes explicit rather than implied by kind.** Today "within a
  leaf" is a property of being confinement; it should be a property of the
  claim.
- **One nesting proof** instead of a nesting proof for confinement and nothing
  for independence.

## Why not now

**Superseded in part by §0 (owner ruling) and corrected by the analysis below —
the merge IS happening; only its scheduling is deferred. Reason 1 as originally
written is WRONG and is kept only so the correction is legible.**

1. ~~Both live endpoints are mid-campaign against the current kinds; posts_show's
   probe bank (102,178 records) is keyed on the gate's engine/phase/cfg digest
   and this refactor invalidates it.~~
   **CORRECTED:** `ProbeCache`'s engine key hashes `assumption_checker.py`
   ONLY — verified by recomputing `source_hash` at the frozen md5 and matching
   the live 4.32 GB bank header. `assumptions.py` is in `_phase_keys`, not the
   probe cache. So the TYPE merge costs zero probe replays; only the GATE
   dispatcher destroys the bank. The two costs were never coupled. Campaign
   scheduling still applies to the gate stage.
2. It is a `src/` change of real size, and `src/` changes here have a history of
   being subtly wrong in the licensing direction (see the name-boundary sanitiser
   near-miss in NAME_BOUNDARY_PLAN_20260914.md §8).
3. It buys no completion on any open endpoint. It buys correctness insurance for
   the NEXT one.

## If it is taken up

Falsifier, stated in advance: **the unified kind must produce a byte-identical
verdict on every closed endpoint** (people_stream, notifications, comments,
conversations) — it is a refactor of provenance, not of licence, so any endpoint
whose verdict moves means the semantics changed and the implementation is wrong.
Nesting must be re-pinned by the existing property tests on random corpora.
Default OFF and gate-testable like every other rung.

Do not carry `scope=WITHIN_LEAF` over to declared claims by default — a
hand-written independence claim has never been scoped to a leaf and silently
narrowing it would CHANGE what existing declarations mean.

## Related

- `docs/DISCIPLINE.md` §16c (confinement), §16b/§16e/§16f/§16g (foreclosure)
- `docs/CONFINEMENT_PRECISION_20260913.md` (C1/C2/C3 precision knobs)
- `src/concolic_engine/assumptions.py:198` (`IndependenceAssumption`, safety warning)
- `src/concolic_engine/coverage.py` (confinement: claim, falsifier, nesting, gate)
- X10 / X11 / X12 gate defects — three defects in the two near-duplicate gate paths

---

## How the merge would actually be done (sub-agent analysis, 2026-09-15)

Read: `assumptions.py` (810 ll.), `coverage.py` confinement block + projection,
`assumption_checker.py` (frozen, md5 `5ae1b13c`), DISCIPLINE §16/§16b/§16c and
X10/X11/X12, and the five live declaration corpora in `results3/`. Measurements
below are read off the files, not estimated; where I infer, I say so.

**Three corrections to the note before the plan, because two of them change the
plan.** (a) "This refactor invalidates posts_show's probe bank" is HALF WRONG —
measured in §4: the type half costs zero replays, the gate half costs all of
them. (b) The note's difference #4 ("confinement checks its preconditions,
independence has none of this") overstates: tree completeness already blocks
`complete` for every claim at `coverage.py:3293` (`complete = … and not
tree_missing`), so independence's combination claim is refused on an incomplete
tree exactly as confinement's is. The genuinely confinement-only preconditions
are matched contexts and the trace layer. Differences #2 and #3 stand as
written. (c) The note's central argument for the refactor — "X10, X11 and X12
were defects in ONE of the two paths, found separately, at separate cost" —
does not survive contact with the code; §7 takes it apart.

### 1. The unified type — and the keying crux

**The crux is not hard, it is dead.** The two keying schemes are irreconcilable
*in the type system* and already identical *in the corpus*.

Irreconcilable in type: `IndependenceAssumption` is matched by `_matches`
(`assumptions.py:139-167`) against a `(source, expr)` pair supplied at
`coverage.py:2405-2409` for every ordered pair of active exprs. A declaration
with `expr_a` set and `source_a` blank matches that expr exactly; one with
`source_a` set and `expr_a` blank matches **every** expr at that
`(file, lineno, function)`. The module's own measurement
(`assumptions.py:49-51`) is that 129 of 146 distinct branch expressions (88 %)
share a source with at least one other, and all twelve finder decisions of an
entrypoint sit at `concolic_targets.rb:331`. So a source-only declaration is a
claim over the **cross product of two sets** of decisions, up to 12 × 12. That
is a pattern language. Confinement has no pattern layer at all: `confined_pairs`
is `Tuple[Tuple[str, str], ...]` of canonical expr strings
(`coverage.py:561`) and `footprint` is `Mapping[str, int]`
(`coverage.py:1716`) — ground pairs, one per entry. A pattern language does not
unify with a ground term; you can only expand the pattern, and expansion is the
single most dangerous edit in this whole refactor (§5, risk 4).

Identical in corpus: I counted every declaration in
`results3/*/_assumptions_declared.json`.

| endpoint | Independence | both exprs set | non-blank `source_a`/`source_b` |
|---|---|---|---|
| comments_index | 4 182 | 4 182 | **0** |
| conversations_index | 6 123 | 6 123 | **0** |
| notifications_index | 27 041 | 27 041 | **0** |
| people_stream | 25 | 25 | **0** |
| posts_show | 1 115 | 1 115 | **0** |
| **total** | **38 486** | **38 486** | **0** |

Same for the other declared kinds: all 9 `UntrackedPathAssumption` and all 14
`OneSideUntrackedPathAssumption` rows across the corpus are expr-keyed with a
blank source. **`PathSource`-based matching is exercised by nothing except
three unit tests** (`src/test_assumptions.py::test_untracked_by_expression_at_a_shared_source`,
`::test_independence_by_expression_at_a_shared_source`,
`::test_expr_and_source_together_and_blank_is_inert`).

So: **do not reconcile the two keying schemes — retire one.** The unified kind
keys on a ground expr pair; `PathSource` is demoted to provenance metadata for
display and locate (which is what `_source_to_dict`, `coverage.py:928`, already
uses it for) and is not consulted by the matcher. `_matches`/`_source_key` stay
alive for `UntrackedPathAssumption`/`OneSideUntrackedPathAssumption`, which are
not in this family.

```python
@dataclasses.dataclass(frozen=True)
class NoCrossProductAssumption(Assumption):
    expr_a: str = ""                       # REQUIRED — __post_init__ raises if blank
    expr_b: str = ""                       # REQUIRED
    provenance: str = ""                   # REQUIRED: "DECLARED" | "DERIVED_FOOTPRINT"
    scope: str = ""                        # REQUIRED: "GLOBAL_PAIRWISE" | "WITHIN_LEAF"
    rationale: str = ""                    # evidence, DECLARED shape
    footprint_a: t.Tuple[str, ...] = ()    # evidence, DERIVED shape (shape_str)
    footprint_b: t.Tuple[str, ...] = ()
    enabling_a: t.Tuple[t.Tuple[str, str], ...] = ()
    enabling_b: t.Tuple[t.Tuple[str, str], ...] = ()
    # source_a / source_b: metadata only, NOT matched
    source_a: PathSource = dataclasses.field(default_factory=PathSource)
    source_b: PathSource = dataclasses.field(default_factory=PathSource)
```

Three deliberate choices:

- **No defaults on `provenance` and `scope`.** A default is exactly the channel
  by which a derived pair acquires a declared pair's weak test, or a leaf-scoped
  claim acquires global reach (§5, risks 1 and 3). Blank must raise in
  `__post_init__`, the way `OneSideUntrackedPathAssumption` already raises on a
  bad `tracked_side` (`assumptions.py:378-382`) and `AliasAssumption` on a bad
  `key` (`assumptions.py:562-567`). That is the house style and it is the right
  one here.
- **`grade` is NOT a field.** The note's sketch lists it. It must not be.
  `bases_probed/realising/passing/failing` are produced by the gate into the
  verdict row (`assumption_checker.py:2476-2479`), and the only feedback channel
  into the engine today is negative and one-directional (`withdrawn_pairs` →
  `restrict_confinement(withdrawn=…)`, `coverage.py:1721`). Put a grade on the
  frozen dataclass and someone will eventually read it as a licence, at which
  point a grade earned on an older corpus licenses a pair the current corpus
  disqualifies, silently.
- **`evidence` is two typed fields, not one polymorphic one.** `rationale` is
  prose the gate cannot test; `footprint_*`/`enabling_*` are what
  `_test_confinement` consumes (`assumption_checker.py:2084-2087`,
  `2118-2121`). Collapsing them into one `evidence: Any` makes "which test am I
  entitled to run" a runtime type check, which is risk 3 again.

`scope` is not a label — it selects a **different code path**, and this is worth
stating flatly because it is the reason the merge is shallower than it looks.
`GLOBAL_PAIRWISE` removes the edge in the `adj` graph at
`coverage.py:2403-2414`, *before* tree completeness and *before* foreclosure,
and the result is induced on every evaluation set. `WITHIN_LEAF` goes through
`restrict_confinement` (`coverage.py:1713-1810`) which runs *after*
`restrict_foreclosures`, closes each clique under "a part holding `d` holds
every gate that forecloses `d`", and is judged by §16b on its own pruned tree.
They have different nesting proofs. A `scope` field that dispatches between the
two existing projections is honest; a single projection parameterised by scope
is not, because the proof that `WITHIN_LEAF ⊆ §16b` does not transfer.

### 2. The two gate paths — and why they are not near-duplicates

First, the arithmetic. Confinement's composition
(`_confinement_composition`, `assumption_checker.py:2154-2287`) applies eight
criteria. The independence path (`_independence_once`, `2558-2608`) applies
**one predicate**:

```
covered = base ∪ trace(flip-A) ∪ trace(flip-B)      # :2598
novel   = trace(flip-both) − covered                # :2599  FAIL iff novel ≠ ∅
```

That predicate is **strictly implied by criterion (iii)**. (iii) asserts
`trace(both) == (base − removed_A − removed_B) ∪ added_A ∪ added_B`; call the
right-hand side `predicted`. `predicted ⊆ covered` always, so `novel ≠ ∅`
implies `trace(both) ⊄ predicted` implies (iii) fails. The converse is false —
(iii) also fails when the double flip *loses* a shape the singles kept, which
`novel` cannot see. That is X11, in one line of algebra.

So the two paths are not near-duplicates. **The independence test is a proper
one-directional weakening of one of confinement's eight criteria.** Merging the
code does not merge the claims.

Footprint dependence, criterion by criterion:

| criterion | needs a footprint? | what it is really testing |
|---|---|---|
| (i) ΔA ⊆ fp(A) | **yes** | the measurement was complete |
| (ii) ΔB ⊆ fp(B) | **yes** | same |
| (iii) additive composition | **no** | *no shape needs both outcomes* — the licence itself |
| (iv) partner stays evaluated | **no** | *this is confinement and not foreclosure* — a KIND test |
| (v) strict one-sidedness | **yes** | the enabling side is the decision's to control |
| (vi) exhaustive profile flip | **yes** | (v) made complete over the corpus |
| (vii) constructed adversarial route | **yes** (+ producers) | (v) against a route no run walked |
| (viii) shared-shape 2×2 | **yes** (`shared = fpa ∩ fpb`) | OR-sharing is not interaction |

Plus one instrument neither path currently uses on declarations and which needs
**no footprint at all**: `infer_pair_tables` (`coverage.py:1871-1898`) +
`classify_cells` (`coverage.py:1822-1868`). Per co-evaluated pair it builds the
2×2 of shape presence over outcome profiles and returns `OR`/`A-only`/`B-only`/
`ALWAYS`/`NEVER` (benign) vs `AND`/`NON-MONOTONE` (interaction, refutes). Inputs
are outcomes and traces only. **This is the answer to "what can a DECLARED claim
with no measured footprint be tested against": (iii), (iv), and the corpus 2×2.**

**Does a declared claim acquire a measured footprint at gate time? It can, and
it must not.** `infer_footprints` is a pure function of the corpus and the gate
already holds the corpus index, so synthesising `fp(A)`/`fp(B)` for a declared
pair is mechanically trivial. But then (i)/(v)/(vi)/(vii) test "A's *measured*
footprint is disjoint from B's" — which is the **derived** claim, strictly
stronger than and different from what the author wrote. A FAIL would be recorded
as the author's claim refuted when what was refuted is a claim the author never
made. Declared claims get (iii), (iv is discussed next), and the 2×2. No
synthesised footprints.

**And (iv) is not general.** This is the finding that decides the whole gate
question. (iv) FAILs when flipping A leaves B unevaluated — and the live
declared corpus is *dominated by exactly that shape*:

- comments_index / conversations_index: 978 + 1 972 rows carry the detail
  *"mutually exclusive: both recorded, never co-evaluated in any run"* — the
  co-evaluation-inert genre (`assumptions.py:206-213`). Correctly inert today,
  inert under any unified kind.
- posts_show's 1 115: *"not_found vs public — attribute PC only fires in
  finder_mock's 'found' branch"*. Flip A to `not_found` and B is gone from the
  path. That is **(iv) FAIL by construction**, on a claim that is *true*: the
  pair genuinely needs no cross product.
- notifications_index's 27 041: *"dispatch-independence: the STI-dispatch seed
  … flipping the type only adds/removes a whole …"* — add/remove, i.e. the same
  shape.

(iv) answers "which KIND of relation is this — confinement or foreclosure?", not
"is this licence sound?". It belongs to confinement because a footprint is only
measurable in a *matched context* (same tree shape), so a decision whose flip
changes which decisions are evaluated is out of the measurement's domain
(`coverage.py:260-275`). A *declared* "no cross product" claim of the
mutual-exclusion family legitimately violates it. Importing (iv) into the
declared path would withdraw licences en masse and re-open four closed
endpoints — safe in the licensing direction, catastrophic in cost, and *wrong on
the merits*.

**Therefore the merged test is a merged DISPATCHER, not a merged TEST:**

```
_test_no_cross_product(cfg, a, cache, out, footprint=None):
    bases = pick_bases_with(batch, [ea, eb])        # shared (X12), already exists
    per base:
        (iii) additive composition            # ALL claims  — replaces `novel`
        corpus 2x2 via classify_cells         # ALL claims  — standing falsifier
        if footprint is not None:
            (i)(ii)(iv)(v)(viii)              # DERIVED only
    if footprint is not None and held:
        (vi) _exhaustive_flip, (vii) _constructed_route   # DERIVED only, once
    _combine_bases(...)                       # shared (X12), already exists
```

Honest accounting of what that buys: the shared parts (`pick_bases_with`,
`_combine_bases`, `_combined_flip`, `flipped_seeds`, `_reading_changed`,
`access_trace`, `shape_str`) are **already shared**. What the dispatcher
actually merges is ~25 lines of base-loop boilerplate plus the criterion table.
That is the true size of the "one gate path" benefit.

### 3. Migration

**Declared rows: 38 486, all mechanically liftable.** Every one is
`(expr_a, expr_b)`-keyed with blank sources (§1 table), so the lift is
`type → "NoCrossProductAssumption"`, `provenance → "DECLARED"`,
`scope → "GLOBAL_PAIRWISE"`, `agent_notes → rationale`. Nothing needs judgement.

**Construction sites: 23, all in the write-freely zone.**
`results3/{comments_index,conversations_index}/coverage_assumptions.py` (4 each),
`people_stream` (1), `notifications_index` (8), `posts_show` (6). No `src/`
constructor outside tests. `src/` references to the name:
`concolic_engine/assumptions.py` (4), `coverage.py` (2), `__init__.py` (2),
`assumption_checker.py` (2, both frozen), and eight test files
(`test_assumptions.py` 9, `test_assumption_checker.py` 6, `test_coevaluation.py`
5, `test_symbolic.py` 3, `test_multibase_gate.py` 3, `test_confinement_e2e.py`
2, `test_confinement_gate.py` 2, `test_path_explosion.py` 1,
`test_assumption_checker_index.py` 1).

**Inferred rows need no lift at all** — posts_show's 2 315
`ConfinementAssumption`, notifications_index's 89 + 52 foreclosure rows are
regenerated from `CoverageResult` by `confinement_to_dict`
(`coverage.py:882-915`) on every pass. Only the declared file migrates.

**The shim must live in the SERIALISER, not only in the class.**
`assumptions_to_dict` emits `item["type"] = type(a).__name__`
(`coverage.py:752`) and `test_declared` dispatches on that string
(`assumption_checker.py:2488`, `2547`). An unrecognised type falls through to
`"no derived test for type {typ}"` → NOT-TESTABLE (`assumption_checker.py:2746`),
and §24.4 withdraws a NOT-TESTABLE. So a bare class rename with the gate frozen
would silently withdraw **all 38 486 declarations** — conservative in the
licensing direction, but it would void every closed endpoint. The shim is a
`GATE_TYPE_NAME` map consulted by `assumptions_to_dict`, emitting the legacy
string while the gate is frozen.

**Shim lifetime: exactly as long as `assumption_checker.py` is frozen.** Retire
it in the same commit that unfreezes the gate, never before and never later —
a shim that outlives the freeze is how a `provenance`-less row reaches the new
dispatcher (§5, risk 3). Keep `IndependenceAssumption` itself as a thin
subclass so `isinstance` at `assumptions.py:697` and every existing test keep
working; that costs nothing and is removable independently.

### 4. The probe bank — measured, and the note is half wrong

`ProbeCache`'s header (`assumption_checker.py:1202-1207`) is exactly five keys:

```
engine       = _ckpt.source_hash(sys.modules[__name__])       # THIS MODULE ONLY
phase        = "assumption_checker:ProbeCache"
cfg          = _ckpt.digest(cfg)                               # the manifest JSON
canonicalize = _canon_key()                                    # hook identity + ALIASES tuples
keep         = str(bool(keep))
```

`source_hash` (`concolic_engine/checkpoint.py:80-98`) hashes raw file bytes.
So the bank is invalidated by **any byte change to `assumption_checker.py`,
including a comment**, and by **nothing else in `src/`**.

Verified against the live bank:

```
results3/posts_show/_p32_regate_probes.ckpt.jsonl   4 320 703 151 bytes, 2026-09-15 00:54
  header engine = c220d0b7df24a6cb72ee278397bc4321
  recomputed source_hash(assumption_checker.py) at md5 5ae1b13c
                = c220d0b7df24a6cb72ee278397bc4321      ← identical
  source_hash(assumption_checker.py, concolic_engine/assumptions.py)
                = e698d5c6276127472928544b1e4b4242      ← NOT what the bank uses
```

The second line is the one that matters. `_phase_keys`
(`assumption_checker.py:228-236`) *does* include `concolic_engine.assumptions`
in its engine hash **and** `_DECLARED_DIGEST`, so the corpus-index and
`profile_representatives` checkpoints invalidate on a type rename. The
ProbeCache does not.

**Conclusion, against the note's "Why not now" #1:**

| change | probe bank (4.3 GB, ~102 k records) | index/derive checkpoints |
|---|---|---|
| unified TYPE in `assumptions.py` + serialiser shim in `coverage.py` | **preserved** | invalidated |
| any edit to `assumption_checker.py` (the gate merge) | **destroyed** | invalidated |

The index checkpoint is cheap to lose — `corpus_index` is incremental with
per-row self-validating stamps (`_row_stamp`, `assumption_checker.py:239-259`;
`_phase_keys(..., corpus=False)`), so a rebuild costs dump reads, no runner
launches. `profile_representatives` is `corpus=True` and rebuilds whole, but it
is a derivation over already-loaded dumps, still no runner launches. **The type
half of this refactor is free of replay cost.** The gate half is not, and there
is no phasing that avoids it.

One tempting mitigation I recommend **against**: narrowing the ProbeCache engine
key to hash only the probe-execution surface (`run_probe`, `ProbeCache`,
`_flip_core`, `flipped_seeds`, `_combined_flip`) instead of the whole module.
That reintroduces precisely the hazard the 2026-09-14 canonicalize fix closed
(`assumption_checker.py:1177-1200`): a key that does not cover everything
deciding what a record *means* silently reuses a stale bank. Pay the bank once,
in one commit, when no campaign is live.

### 5. What could go silently wrong, in the licensing direction — ranked

1. **`scope` on DERIVED pairs defaulting to `GLOBAL_PAIRWISE`.** The note warns
   about the opposite direction (WITHIN_LEAF onto declared claims, which
   *narrows*). This is the dangerous mirror and the note does not name it. A
   footprint is measured over matched contexts — pairs of runs with the *same
   tree shape* — so the disjointness claim holds only inside a leaf
   (`coverage.py:260-275`). Give a derived pair global scope — by a field
   default, by a dict round-trip through `confinement_to_dict` that omits
   `scope`, by a census tool constructing the kind positionally — and the edge
   is removed at `coverage.py:2403-2414` from *every* evaluation set, including
   ones the measurement never spoke about. Effect: fewer demanded cubes, lower
   MISSING, `complete` flips to true, **no error anywhere**. This is the
   name-boundary-sanitiser shape exactly. Mitigation: `scope` required, no
   default, `__post_init__` raises; plus a property test that GLOBAL and
   WITHIN_LEAF demands are *not* equal on random corpora, so a later "these are
   the same, let's simplify" cannot land silently.
2. **`grade` as a field on the assumption.** §1. An output becoming an input;
   a PASS earned on corpus *N* licensing a pair on corpus *N+1* that the
   standing disqualifier would refuse. Today's feedback is negative-only
   (`withdrawn_pairs`). Keep the dataclass free of gate output.
3. **A lost `provenance` selecting the weak test.** If the merged dispatcher
   treats absent `provenance` as `DECLARED`, a `ConfinementAssumption` row whose
   provenance is dropped anywhere in the
   `assumptions_to_dict → attach_to_summary → _assumptions_declared.json →
   --declared` chain silently gets the `novel`-only test instead of (i)-(viii).
   Derived pairs would then PASS on the one probe DISCIPLINE §16c explicitly
   says cannot see them. Mitigation: absent provenance is ERROR, never a
   default. (Note the contrast with today's behaviour, which *is* safe: an
   unknown type → NOT-TESTABLE → withdrawn, `assumption_checker.py:2746`. The
   merge is what creates the unsafe fallback; today there isn't one.)
4. **Expanding the retired `PathSource` pattern layer during the lift.** Zero
   source-keyed declarations exist (§1), so retiring the layer is free — but
   the tempting "helpful" migration is to *expand* a source-only declaration
   into every expr at that source. At 12 finder decisions per mock source that
   turns one declaration into 66 pairwise edge removals. Mitigation: the
   unified kind refuses construction without both exprs; a source-only legacy
   row migrates to *nothing* and is reported, not expanded.
5. **Losing the self-pair guard.** `are_independent` (`assumptions.py:689-694`)
   short-circuits `expr_a == expr_b` to `False` — two occurrences of one
   decision are never independent. Note the `elif`: when both exprs are given
   and differ, the source-equality guard is skipped, which is correct for
   mock-boundary PCs. If the unified kind takes identity from the source key
   instead, two distinct exprs at one mock source collapse into "same decision"
   and are refused — safe. The unsafe mirror is dropping the expr guard
   altogether, which lets a decision be declared independent of itself; the
   clique code at `coverage.py:2417-2426` would read the missing self-edge as a
   licence. Cheap to pin: `test_assumptions.py:517` already asserts it.
6. **Routing declared claims through `force_confined`.** `coverage.py:1722`
   and `:2017` expose a ready seam that treats a pair as confined "whatever the
   footprints say", documented as a what-if for census tools. It is the
   cheapest imaginable way to give declared claims leaf scope, and it is a trap:
   the forced branch `continue`s before the `fa is None` check
   (`coverage.py:1767-1770`), so the pair skips the disqualifier and the
   footprint test entirely, lands in `confined_pairs`, and is re-emitted by
   `confinement_to_dict` as a `ConfinementAssumption` with `footprint_a: []`.
   At the gate that is not `None`, so it passes the undecidable check at
   `assumption_checker.py:2085` and then FAILs (i) on the first changed shape
   — i.e. a declaration is reported as a refuted confinement. Safe direction,
   wrong label, and the label is what a campaign acts on. Don't use the seam.

### 6. Staged plan, one falsifier per stage

**Stage 0 — baseline pin (no code).** Digest today's
`results3/{comments_index,conversations_index,people_stream}/_assumption_results.json`
and each endpoint's `coverage_summary.json` `missing`/`complete`. *Falsifier:*
none; this is the reference every later stage diffs against.

**Stage 1 — the type, behaviour-frozen.** `NoCrossProductAssumption` in
`assumptions.py`; `IndependenceAssumption` becomes a subclass; `GATE_TYPE_NAME`
shim in `assumptions_to_dict` (`coverage.py:752`) still emitting
`"IndependenceAssumption"`. *Falsifier:* `src/test_assumptions.py` (15 tests),
`src/test_coevaluation.py`, `src/test_symbolic.py`, `src/test_path_explosion.py`
pass unchanged, **and** re-serialising all five
`results3/*/_assumptions_declared.json` through the new classes is byte-identical
to the files on disk. Pure Python, no runner, no Z3, no probe replay, probe bank
untouched (§4).

**Stage 2 — `scope` made explicit, both values routed to today's paths.**
*Falsifier:* the existing nesting property tests on random corpora —
`src/test_confinement.py::test_demand_is_nested_in_16b_on_random_corpora`,
`::test_strict_is_nested_in_weak_on_random_corpora`,
`::test_gate_confinement_is_nested_in_the_earlier_rule_on_random_corpora`,
`::test_or_sharing_is_nested_in_strict_on_random_corpora`,
`src/test_confinement_span.py::test_the_licensed_set_and_the_demand_nest_on_random_corpora`,
`src/test_conjunction_foreclosure.py::test_demand_is_nested_16e_16b_16` and
`::test_missing_is_nested_on_random_corpora` — plus **one new property**:
GLOBAL-scoped and WITHIN_LEAF-scoped demand differ on some random corpus. If
that new test cannot be made to fail, the two scopes are interchangeable and
risk 1 is not real; I expect it to fail easily (the gate-closure step at
`coverage.py:1800-1810` has no counterpart in the step-5 path), but it is
untested inference until someone writes it.

**Stage 3 — the standing disqualifier extended to declared pairs, REPORT-ONLY.**
The counterexample search that produces `confinement_disqualified`
(`coverage.py:557`) runs at load over the corpus and needs no footprint for the
2×2 form (`infer_pair_tables` + `classify_cells`). Emit a new
`CoverageResult` field naming declared pairs the corpus contradicts; change no
demand. *Falsifier:* `missing` and `complete` byte-identical on all five
corpora, with the new field non-empty on at least one — a field that is empty
everywhere has proven nothing. **This stage needs no type merge and no gate
change, and it is the single benefit in the note's list that is both real and
currently absent.**

**Stage 4 — the gate dispatcher (bank-destroying, campaign-gated).**
`_test_no_cross_product` per §2, criteria partitioned by provenance.
*Falsifier:* `src/test_confinement_gate.py` (25), `src/test_confinement_active.py`
(7), `src/test_multibase_gate.py`, `src/test_confinement_e2e.py` (4),
`src/test_assumption_checker.py` all pass, **and** every row of the three closed
endpoints' `_assumption_results.json` reproduces its verdict under the merged
dispatcher. Note the standing prediction: **if (iv) is applied to declared
claims this differential FAILs**, and that failure is the falsifier for the
claim that (iv) is general. Do not rescue it by relaxing the differential.

**Stage 5 — X11's filed symmetric fix (a separate change, not this refactor).**
Give the declared path (iii) in place of `novel`. *Falsifier is inverted:* the
change **must** FAIL at least one of the ~6 600 replay-earned closed-endpoint
PASSes (comments_index 2 670, conversations_index 3 905, people_stream 25 —
the remainder of each endpoint's total being the 978 + 1 972 co-evaluation-inert
rows that no replay touched). Each new FAIL is hand-verified as a real
removal-shaped dependence before it is booked. A Stage 5 that changes nothing
has not been shown to work; it has been shown not to run.

Note what Stages 4 and 5 do to the note's stated overall falsifier: **"byte-identical
verdicts on every closed endpoint" is satisfiable only by the stages that buy
nothing.** The stage with the most value (5) is defined by *not* being
byte-identical. The note's falsifier is right for the *refactor* and wrong for
the *repair*, and the two must not be shipped together.

### 7. Recommendation

**Testing the note's own argument against the code.** The note says X10, X11 and
X12 "were defects in ONE of the two paths, found separately, at separate cost.
One path fails once."

- **X10 — refutes the argument.** The fix is one shared helper,
  `_combined_flip` (`assumption_checker.py:1623-1648`), whose docstring says
  *"Shared by the Independence and the Confinement tests"*, and DISCIPLINE:1499
  records *"the X10 combined-flip lines are now one shared helper,
  `_combined_flip`, used unchanged by the independence test."* Found once,
  fixed once, in code the two paths already shared. Not a duplication cost.
- **X11 — refutes the argument, harder.** DISCIPLINE:1519: *"The existing
  independence flip test is untouched; X11's symmetric fix stays a filed
  proposal."* X11 was fixed in one path and is **still open in the other, today**.
  Unification would not have found it twice; it would have forced a decision
  about whether (iv) applies to declared claims — and §2 shows it does not.
  X11 is evidence that the two paths test *different claims*, which is an
  argument against the merge, not for it.
- **X12 — argues for something already done.** The fix touched *four* sites
  (`_test_confinement`, `_independence_once`, `_untracked_once`,
  `_symbolic_constraint_once`, plus the two foreclosure tests), one of which
  (untracked) is not in this family at all. The shared part was extracted into
  `pick_bases_with` + `_combine_bases`. That argues for shared **base-selection
  plumbing**, which now exists, not for a unified assumption **type**.

**One of three supports the note's argument; one refutes it; one argues for a
refactor already completed. The stated case for the merge does not hold.**

**Is it worth doing? Mostly no, in the form the note sketches.**

- **Do Stage 3** (standing disqualifier for declared claims, report-only). It is
  the real benefit, it is small, it needs neither the type merge nor the gate
  change, it costs no probe replays, and its falsifier is clean.
- **Do Stage 5** (X11's symmetric fix), on its own schedule, with its own
  inverted falsifier, and expect it to withdraw licences. ~6 600 PASSes on four
  closed endpoints currently rest on a probe DISCIPLINE itself calls the wrong
  instrument. That is a standing correctness exposure and it has nothing to do
  with whether the types are merged.
- **Stages 1-2** (the type merge) are cheap and safe — free of probe-replay
  cost (§4), a clean lift (§3), the keying crux dissolves on measurement (§1).
  But they buy *conceptual hygiene*, and the note's own honest framing ("it buys
  no completion on any open endpoint") is right. Do them when something else
  needs the file touched; do not schedule them on their own.
- **Do not do Stage 4 as the note specifies.** A genuinely unified gate *test*
  is unsound: (iv) is a kind discriminator, not a licence check, and applying it
  to the declared corpus would withdraw ~1 100 posts_show and ~27 000
  notifications_index claims that are correct.

**Cheapest version capturing most of the value: Stage 3 alone.**

**"One gate path" WITHOUT unifying the types: yes, and it is strictly easier.**
`test_declared` dispatches on a *string* (`assumption_checker.py:2488`, `2547`)
and both claim dicts already carry `expr_a`/`expr_b`. One function
`_test_no_cross_product(cfg, a, cache, out, footprint=None)` with the two
existing branches as callers is a ~40-line change in **one file**, touching no
`concolic_engine/` type at all. It still costs the probe bank (any byte change
does), so it is campaign-gated — but if the "one path fails once" benefit is
wanted, that is the version to build, and it is evidence that the type merge and
the gate merge were never actually coupled.
