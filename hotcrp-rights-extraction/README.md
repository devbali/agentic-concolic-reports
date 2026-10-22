# HotCRP with `rights()` computing

A probe with one question: **does letting `Contact::rights()` actually run turn
the extracted policy relational?**

It does.

```sh
python3 extract.py          # 96 seeds -> dumps, policy.json, policy.sql
```

## The result

| | sibling harness | this one |
|---|---|---|
| `rights()` | pre-empted via `_last_rights` | **computes** |
| symbols in the conditions | `ciflags`, `scope_bits` | `conflictType`, `reviewType`, `rflags`, `roles`, `outcome` |
| `ciflags` appears | in 36 of 40 atoms | **never** |

Seeding one paper and one viewer and asking `can_view_paper`:

```
SYMBOLS: {conflictType: 6, isPC: 4, privChair: 2, reviewType: 1, outcome: 1}
  conflictType <= 1        conflictType >= 32
  conflictType > 1         reviewType == 0
```

Those are `PaperConflict.conflictType` and `PaperReview.reviewType` — real
columns of real tables. The flag word the whole permission layer tests has
been computed *away* into conditions over the rows it was computed *from*,
which is exactly what 33 of the 40 refusals in
[`../hotcrp-policy-extraction/`](../hotcrp-policy-extraction/README.md) were
waiting for.

96 seeds, 22 distinct traces, 226 path conditions, no errored runs.

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

## Honest limits of this probe

- **One entrypoint.** `Contact::can_view_paper` only.
- **A seed GRID, not solver-driven exploration.** 96 combinations chosen to
  span the conflict/review/role space. `../hotcrp-typed-policies/run_concolic.py`
  has the real exploration loop; this answers a narrower question and a grid
  answers it.
- **Coverage is not complete** (10 nodes). This probe was not driven to
  completeness — it was driven until it answered its question.
- **`load_into` is skipped, so there is still no SQL query event.** The rows
  are seeded at the boundary rather than parsed out of an intercepted
  statement. Capturing the statement needs the query boundary mocked, and
  `Runtime::call` can only return a `Value`, never an opaque result handle the
  application walks — see the parent discussion. That is a separate gap from
  this one, and it is the one OTE would need.
- **The join is declared, not inferred.** `Paper.paperId =
  PaperConflict.paperId` and `ContactInfo.contactId = PaperConflict.contactId`
  are cited to `schema.sql`; with them removed the same atom is refused again,
  which `test_an_undeclared_join_is_still_refused` pins.
- **It did not help the 40-atom corpus**, which stays at 6 rendered / 33
  `ciflags` refusals. That is the diagnosis confirming itself: those atoms are
  blocked by the pre-empted `rights()`, not by the mapping, and the fix for
  them is this harness.
- **The `(int)` cast fix is a prerequisite** and is currently uncommitted
  (see `runtimes/php_runtime/tests/t_cast.php`). Without it, parsing rows
  through `(int) $x[2]` silently yields `1`.
