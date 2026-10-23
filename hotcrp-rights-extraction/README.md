# HotCRP with `rights()` computing

All 40 permission entrypoints, driven with `Contact::rights()` **computing**
rather than pre-empted.

| | sibling corpus | here |
|---|---|---|
| atoms | 40 | 40 |
| **rendered as SQL** | **6** | **39** |
| refused | 34 (33 × `ciflags`) | 1 (`bits`, a method argument) |
| **complete coverage** | 40 | **40** |

Every row is now a win, and the last one took a fix to the engine's
arithmetic rather than more seeds — see
[Why](#why-completeness-was-not-seed-limited-and-what-fixed-it).

```sh
python3 extract.py          # solver-driven -> dumps, policy.json, policy.sql
```

**The measurement, in full.** 40 entrypoints, 22 743 path conditions,
37–92 distinct traces each. No errored runs, no truncated demand set, no
solver timeout, no dropped constraint, no budget hit; `tree_complete` on
every entrypoint and no provisional foreclosure. Those are the ways this
number could have been bought rather than earned, and `summary.json` carries
each one per entrypoint.

## What changed

Letting `rights()` compute replaces `ciflags` — a flag word that exists only
in process — with conditions over the rows it is computed *from*. `ciflags`
appears in 36 of the sibling's 40 atoms and in **none** of these.

```
PaperContactInfo::is_author     conflictType >= 32            (CONFLICT_AUTHOR)
Contact::can_view_decision      conflictType <= 1 AND roles&15 AND roles&4
                                                              (unconflicted chair)
```

37–92 distinct traces per entrypoint, no errored runs.

## How it differs, in one line each

- **`rights()` is not pre-empted.** The sibling sets `_last_rights`,
  `_last_rights_paper` and `_last_rights_version` by reflection so `rights()`
  takes its cache-hit branch. This one leaves them alone.
- **The ROW is seeded, not the flags.** `_contact_info[uid]` is given a
  `PaperContactInfo` whose `conflictType` / `reviewType` / `rflags` are
  symbolic — which is what `load_into` would have produced — and
  `_rights_version` is matched so `optional_contact_info` returns it. So
  `load_into` is skipped but `rights()` still computes.
- **`roles` is seeded, not `isPC`.** `ContactInfo.roles` is a column; `isPC`
  and `privChair` are masks HotCRP takes off it. Seeding the booleans made the
  extracted condition name `isPC`, which no table has. Taking the masks in the
  harness — the same thing `Contact`'s constructor does — records the
  comparison against `roles` instead.
- **No database, and no query mock either.** `Conf` is built with
  `$connect = false`; no query target is declared at all, so anything reaching
  the database layer would raise rather than being quietly answered.

## The extracted policy

With the join declared, the atom renders. This is the whole policy for
`Contact::can_view_paper`, derived by executing HotCRP:

```sql
SELECT `ContactInfo`.`contactId`, `ContactInfo`.`roles`,
       `Paper`.`outcome`, `Paper`.`timeSubmitted`,
       `PaperConflict`.`conflictType`
FROM `ContactInfo`
  JOIN `PaperConflict` ON `ContactInfo`.`contactId` = `PaperConflict`.`contactId`
  JOIN `Paper`         ON `Paper`.`paperId`        = `PaperConflict`.`paperId`
WHERE `ContactInfo`.`contactId` = _MY_UID AND (
     (`conflictType` <=  1 AND roles&15 <> 0 AND roles&4 <> 0)
  OR (`conflictType` >   1 AND `outcome` = 0 AND roles&15 <> 0 AND roles&4 <> 0)
  OR (`conflictType` >= 32 AND `outcome` = 0 AND roles&15  = 0 AND roles&4  = 0)
  OR (`conflictType` >= 32 AND `outcome` = 0 AND roles&15 <> 0 AND roles&4  = 0 AND …)
  OR (`conflictType` <  32 AND `outcome` = 0 AND `timeSubmitted` > 0
                           AND roles&15 <> 0 AND roles&4  = 0 AND …));
```

Five disjuncts, one per way HotCRP lets someone see a paper, and they read as
the policy anyone who knows the application would state:

| disjunct | who |
|---|---|
| `conflictType <= 1`, `roles & 4` | an unconflicted **chair** (`ROLE_CHAIR = 4`) |
| `conflictType > 1`, `roles & 4` | a **conflicted chair** — still allowed |
| `conflictType >= 32`, not PC | an **author** (`CONFLICT_AUTHOR = 32`) |
| `conflictType >= 32`, PC | an author who is also on the PC |
| `conflictType < 32`, `timeSubmitted > 0` | a **PC member**, unconflicted, paper submitted |

`roles & 15` is `ROLE_PCLIKE`; `roles & 4` is `ROLE_CHAIR`.

**One blemish, stated rather than tidied away.** Two disjuncts carry
`((roles & 79) & 32768) = 0`, which is trivially true — 79 has no bit at
0x8000 — so normalization did not fold it. It is harmless and it is not
simplified, and a reader should know which of those two it is.

## Why completeness was not seed-limited, and what fixed it

The fixed grid was first replaced with the standard concolic loop — run,
negate each path condition against its prefix, solve, feed the model back as
a seed. It roughly doubled the traces per entrypoint (22 → 46) and **changed
nothing**: still 0 of 40 complete. The reason was not the corpus.

### The defect: two theories of `&` in one report

The shared solver treats the bitwise operators as UNINTERPRETED FUNCTIONS.
For *proposing* a seed that is the safe direction — a model the program
disagrees with is re-driven and re-measured, so a weak theory costs a wasted
run. **For measuring coverage it is the unsafe direction**, and that is the
half nobody had looked at: a weaker theory also admits DEMANDS the program
can never satisfy, and nothing re-measures a demand away.

So the checker asked for a run where

```
BitAnd(roles, 4)  != 0     -- a chair
BitAnd(roles, 15) == 0     -- not pc-like
```

which is satisfiable only because the solver cannot see that `ROLE_CHAIR = 4`
is one of the bits of `ROLE_PCLIKE = 15`. **38 of the 40 missing branches
were that single pair.** Another demanded `Not(BitAnd(-1, b) == b)`, and
tree completeness was separately blocked by `((roles & 79) & 32768) != 0` —
`79 & 32768 == 0`, so the branch is dead in HotCRP and no seed reaches it.

The asymmetry is the whole bug: `lower()` in this file has ALWAYS lowered
masks exactly (`Int2BV`/`BV2Int`), because a seed has to replay in real PHP.
The coverage query did not. Same corpus, same operator, two meanings.

### The fix: declare the width, once, around the coverage query

`concolic/solver.py` grew `machine_integers(width, signed, cite)` — opt-in,
default OFF, because a corpus spanning runtimes has no single width to
declare and a shared coverage claim must not depend on one. This corpus is
one language, so it has one, and `php_int_width()` ASKS the interpreter that
produced the dumps rather than hard-coding 64: a 32-bit build would answer
differently, and a wrong width prunes demands that are really reachable.

The declaration also BOUNDS the variables. `Int2BV` is total — handed an
`Int` too wide it truncates silently — which showed up as
`Not(BitAnd(-1, r) == r)` coming back SAT with `r = -(2**64) + 4`, a value no
PHP integer can spell. Under a declared width those models are excluded.

Three things followed:

| | before | after |
|---|---|---|
| the impossible mask pair | demanded | UNSAT |
| `tree_complete` | False (dead branch) | **True, with no assumption** |
| remaining demand | phantom | **genuinely reachable** |

### What the honest demand turned out to be

With the phantoms gone, each entrypoint had exactly one real demand left:
chair, unconflicted, with a review, AND `outcome != 0`. Driving the
checker's own witness showed why no seed could close it — the run takes
*every* conjunct except the last, because an unconflicted chair returns
before `outcome` is ever read.

That is foreclosure, and it is not pairwise: neither `roles & 4` nor
`conflictType <= 1` alone removes `outcome` from the path, only the two
together. `foreclosure_subconjunctions=True` infers exactly that, from the
corpus — `outcome != 0` foreclosed under (chair ∧ unconflicted), width 3,
**non-provisional**, which it can only be while `tree_complete` holds. The
lowering is what established that precondition.

It is an inference with a falsifier, not a declaration: any run that matches
the prefix and *does* evaluate the member removes it on the next pass.

### Two edges that now close the loop

- **Coverage witnesses re-enter the seed queue.** Prefix negation flips one
  decision against the path before it, so a demand needing several decisions
  to line up at once is not a seed it can propose; `MissingCoverage.
  concrete_values` is exactly that assignment. Usable only under the
  declaration, since the uninterpreted default produced unrepresentable
  integers.
- **A dropped constraint fails the entrypoint.** `check_satisfiability` logs
  a warning and returns UNSAT for an expression it cannot parse, and an unsat
  demand reads as "nothing missing" — false completeness arriving via a log
  line nobody reads. The log line is collected; a non-empty one forces
  `complete=False` and is reported as `dropped_constraints`.

## Soundness: what "39 rendered, 40 complete" means

**Complete is now a claim, and here is exactly what it claims.** Every
tracked decision was observed with every satisfiable outcome
(`tree_complete`), and every satisfiable assignment over every observed
co-evaluation set was observed too, with the bitwise operators carrying
PHP's own arithmetic. So the disjunction is the whole policy *over the
symbols the harness makes symbolic*.

**What it does not claim**, and these are the live blind spots:

- **The seeded surface is the boundary.** `conflictType`, `reviewType`,
  `rflags`, `roles`, `timeSubmitted`, `timeWithdrawn`, `outcome` are
  symbolic; everything else about the paper, the conference settings and the
  requester is concrete. A branch on an unseeded field is not missing
  coverage, it is outside the universe being measured.
- **The foreclosures are inferred, not proven.** `outcome != 0` is foreclosed
  under (chair ∧ unconflicted) because no run in this corpus matched that
  prefix and evaluated it. That is a universal over the corpus with a
  falsifier, not a theorem about HotCRP — a run that matches and evaluates it
  retracts the foreclosure and re-opens the demand.
- **The width is a declaration.** `php -r 'echo PHP_INT_SIZE'` on the
  interpreter that produced these dumps. On a 32-bit build the masks mean
  something else and this corpus would have to be re-measured.

They are also **not minimal**: `is_author`'s real predicate is
`conflictType >= 32`, but it renders as several disjuncts differing only in
role, because each `rights()` path produced its own conjunction.

**And one conjunct is trivially true.** 22 of the views carry
`((roles & 79) & 32768) = 0` — 79 has no bit at 0x8000. The solver now knows
this (it is what unblocked `tree_complete`), but `normalize` does not fold
mask arithmetic, so it survives into the SQL. Harmless, unsimplified, and
a reader should know which of those two it is.

## Other limits

- **`PaperContactInfo::scope_allows` is refused**, on `bits` — a method
  argument, not data. That refusal is correct and will not go away.
- **`load_into` is skipped, so there is still no SQL query event.** The rows
  are seeded at the boundary rather than parsed out of an intercepted
  statement. Mocking the query needs a target that can return an opaque
  result handle, and `Runtime::call` only returns a `Value`. That is the gap
  OTE would need, and it is separate from this one.
- **The `(int)` cast fix is a prerequisite** and is currently uncommitted
  (see `runtimes/php_runtime/tests/t_cast.php`). Without it, parsing rows
  through `(int) $x[2]` silently yields `1`.
- **The join is declared, not inferred**, and cited to `schema.sql`; with the
  joins removed the same atoms are refused again.
