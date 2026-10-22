# HotCRP with `rights()` computing

All 40 permission entrypoints, driven with `Contact::rights()` **computing**
rather than pre-empted.

| | sibling corpus | here |
|---|---|---|
| atoms | 40 | 40 |
| **rendered as SQL** | **6** | **39** |
| refused | 34 (33 × `ciflags`) | 1 (`bits`, a method argument) |
| **complete coverage** | 40 | **0** — see [Why](#why-completeness-is-not-seed-limited) |

The first three rows are the win. **The last one is the catch, and it is not
a footnote** — see [Soundness](#soundness-what-39-rendered-does-and-does-not-mean).

```sh
python3 extract.py          # 96 seeds -> dumps, policy.json, policy.sql
```

## What changed

Letting `rights()` compute replaces `ciflags` — a flag word that exists only
in process — with conditions over the rows it is computed *from*. `ciflags`
appears in 36 of the sibling's 40 atoms and in **none** of these.

```
PaperContactInfo::is_author     conflictType >= 32            (CONFLICT_AUTHOR)
Contact::can_view_decision      conflictType <= 1 AND roles&15 AND roles&4
                                                              (unconflicted chair)
```

288 seeds per entrypoint, 17–44 distinct traces each, no errored runs.

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

## Why completeness is not seed-limited

The fixed grid was replaced with the standard concolic loop — run, negate each
path condition against its prefix, solve, feed the model back as a seed — the
same expansion `../hotcrp-typed-policies/run_concolic.py` uses, batched one
PHP process per round so a HotCRP boot is not paid per seed. It roughly
doubled the traces per entrypoint (22 → 46).

**Coverage still reports 0 of 40 complete, and more seeds will not fix it.**

Of the 40 missing branches, **39 are unsatisfiable in PHP**. The engine
deliberately treats masks as uninterpreted functions — right for a shared
coverage claim, which must not depend on one language's integer width — and
the cost is that it demands combinations arithmetic forbids:

| demanded | why it cannot happen |
|---|---|
| `roles & 4 != 0` **and** `roles & 15 == 0` (38 of them) | `ROLE_CHAIR = 4` is *inside* `ROLE_PCLIKE = 15` |
| `Not(bits & -1 == bits)` | `-1` is all ones, so `x & -1 == x` always |

Tree completeness is blocked separately, by a branch that is genuinely **dead
in HotCRP**: `((roles & 79) & 32768) != 0` is never taken, and never can be,
since `79 & 32768 == 0`. It is the same trivially-true conjunct visible in the
rendered SQL.

Declaring those three as assumptions — two `SymbolicConstraintAssumption`s for
the mask arithmetic and a `OneSideUntrackedPathAssumption` for the dead branch
— does bite: `tree_missing` drops to 0 and the reported combination changes.
But a new combination surfaces in its place, and the entrypoints still report
one missing each.

That is the finding, and it is about the engine's model rather than the
corpus: **each pruned artifact reveals another, because what is missing is
mask semantics, not seeds.** Two honest ways forward, neither of which is
"explore harder":

1. **A report-local mask lowering.** The sibling already does exactly this for
   seed generation (`lower()` maps `&` onto `Int2BV`/`BV2Int`), precisely
   because a seed must replay in real PHP. The coverage query could use the
   same lowering for this corpus, leaving the shared solver's UF treatment
   untouched.
2. **Assumptions per mask fact**, as above — sound, since each is arithmetic
   rather than judgement, but there is one per mask pair and they accumulate.

## Soundness: what "39 rendered" means

Sound as observed, not proven complete. Every disjunct is a path some run
really took, so nothing is invented — but a disjunction is the whole policy
only if every path was explored, and an incomplete one is **narrower** than
the application, which is the unsafe direction. Do not enforce these; read
them as a description of what the explored paths permit.

They are also **not minimal**: `is_author`'s real predicate is
`conflictType >= 32`, but it renders as three disjuncts differing only in
role, because each `rights()` path produced its own conjunction.

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
