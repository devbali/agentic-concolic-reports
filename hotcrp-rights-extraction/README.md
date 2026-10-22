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

## What still refuses, and why it is now a small gap

```
-- EXCLUDED ATOMS — 1 of 1
--   atom 1: outcome — Paper rows are not owned by a contact; scoping a view
--           over Paper.outcome needs a join to PaperConflict or PaperReview,
--           which is not a declared fact
```

Not "this symbol is not stored" any more — every symbol in the condition *is*
a column. The blocker is that the condition spans `Paper` and
`PaperConflict`, and `Paper` has no principal: a paper is not owned by a
contact, so a view over it can only be scoped by a **join**, and which column
joins them is not yet a declared fact in
[`app_config.py`](../../agentic_concolic_engine/domains/php_hotcrp_sql/app_config.py).

`Paper.paperId = PaperConflict.paperId` is a schema fact and citable. Teaching
the domain one declared join is the next step, and it is a much smaller one
than "the policy is not relational", which is where this started.

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
- **The `(int)` cast fix is a prerequisite** and is currently uncommitted
  (see `runtimes/php_runtime/tests/t_cast.php`). Without it, parsing rows
  through `(int) $x[2]` silently yields `1`.
