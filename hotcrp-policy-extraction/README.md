# HotCRP access-control policy extraction

The last stage of the pipeline, run: the policy IR from
[`../hotcrp-typed-policies/`](../hotcrp-typed-policies/) rendered through the
[`php_hotcrp_sql`](../../agentic_concolic_engine/domains/php_hotcrp_sql/README.md)
domain.

```sh
python3 extract.py            # views/, review_items.json, summary.json
python3 extract.py --print
```

## Result

40 entrypoints, 40 atoms: **6 rendered as SQL, 34 refused.**

```sql
-- PaperContactInfo::is_author
SELECT `conflictType`, `contactId` FROM `PaperConflict`
  WHERE `contactId` = _MY_UID AND (`conflictType` >= 32);

-- PaperContactInfo::conflicted
SELECT `conflictType`, `contactId` FROM `PaperConflict`
  WHERE `contactId` = _MY_UID AND (`conflictType` > 1);

-- PaperContactInfo::unconflicted
SELECT `conflictType`, `contactId` FROM `PaperConflict`
  WHERE `contactId` = _MY_UID AND (`conflictType` <= 1);

-- PaperContactInfo::is_reviewer
SELECT `contactId`, `reviewType` FROM `PaperReview`
  WHERE `contactId` = _MY_UID AND (`reviewType` > 0);

-- PaperContactInfo::review_submitted
SELECT `contactId`, `rflags` FROM `PaperReview`
  WHERE `contactId` = _MY_UID AND ((`rflags` & 4096) <> 0);

-- PaperContactInfo::self_assigned
SELECT `contactId`, `rflags` FROM `PaperReview`
  WHERE `contactId` = _MY_UID AND ((`rflags` & 131072) <> 0);
```

### They are right

Each was recovered by executing the real method, never by reading it. Checked
afterwards against the source:

| extracted | `apps/hotcrp/src/paperinfo.php` | constant |
|---|---|---|
| `conflictType >= 32` | `$this->conflictType >= CONFLICT_AUTHOR` | `CONFLICT_AUTHOR = 32` |
| `conflictType > 1` | `… > CONFLICT_MAXUNCONFLICTED` | `= 1` |
| `conflictType <= 1` | `… <= CONFLICT_MAXUNCONFLICTED` | `= 1` |
| `reviewType > 0` | `$this->reviewType > 0` | — |
| `rflags & 4096` | `$this->rflags & ReviewInfo::RF_SUBMITTED` | `0x1000` |
| `rflags & 131072` | `$this->rflags & ReviewInfo::RF_SELF_ASSIGNED` | `0x20000` |

Six for six, constants included.

## The 34 refusals

`ciflags` 33, `bits` 1. Every one is written out with its reason
(`views/*.sql`, `review_items.json` — 68 blocking items, 0 advisory):

```
-- Contact::can_view_paper
-- 0 of 1 atoms rendered
-- EXCLUDED ATOMS — 1 of 1
--   atom 1: ciflags — computed in PHP by Contact::rights() from conflict and
--           review rows; absent from schema.sql …
```

**This is the shape of HotCRP's access control, not a shortfall of the tool.**
It loads conflict and review rows, computes a `ciflags` bitmask in PHP, and
tests that word. The six predicates that *are* relational are exactly the six
that read a column directly. Everything above them tests the derived flag.

## What would raise 6/40, and the defect in the way

`ciflags` is computed **from** `PaperConflict` and `PaperReview` rows, so in
principle it is expressible over them. The route is to stop seeding it and let
`Contact::rights()` compute it from a mocked query — then the policy atoms
would name the row columns rather than the flag.

Two things block that today.

**1. The harness pre-empts `rights()`.** `../hotcrp-typed-policies/harness.php`
sets `_last_rights`, `_last_rights_paper` and `_last_rights_version` by
reflection, which puts `rights()` on its cache-hit branch so it never calls
`contact_info()` → `load_into()` → the query. The comment says so outright:
*"This establishes the actual rights() cache-hit branch; no DB supplier."*
That is a deliberate, documented choice and it is why 95/95 paths carry no SQL.

**2. `(int)` on a symbolic value silently yields `1`.** This is a runtime
defect, and it is the reason undoing (1) would not work yet.
`PaperContactInfo::load_into` parses rows with `(int) $x[2]`, and:

```php
$x = $v["conflictType"];       // a symbolic Value
$i = (int) $x;                 // PHP Warning: could not be converted to int
                               // $i === 1
```

Not an exception — a **warning and the integer 1**. So every row field would
be concretised to 1 on the way in, and every branch below would read as
covered while never having depended on the input. That is precisely the silent
concretisation the design forbids, and the instrumentor rewrites `(bool)`
(`InstrumentVisitor` handles `Cast\Bool_`) but no other cast.

Fixing it is a bounded runtime change in the same shape as the `(bool)` case —
rewrite `(int)`/`(float)`/`(string)` casts through the runtime so they are
modelled or loud. It is **not done here** because `Runtime.php` and
`InstrumentVisitor.php` both have uncommitted work in the tree, and editing a
file another session is mid-change on is how two correct changes become one
broken one.

## Files

| | |
|---|---|
| `extract.py` | the run: policy IR → domain → artifacts |
| `views/<entrypoint>.sql` | one per entrypoint, SELECTs and refusals both |
| `review_items.json` | 68 blocking claims, one per refused atom |
| `summary.json` | counts, refusals by symbol, per-entrypoint detail |
