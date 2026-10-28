# What is STILL lost after the D1-D8 fixes

Measured, not estimated: every family below is a bucket of the executed
statement-set differential in `_verification/`, counted over 46 models x 12
operations on both target stacks. A gap that is named and counted is a result;
a check tuned until it goes green is not.

Numbers in this file are the AFTER state (`out/fixed_core.json`,
`out/fixed_override.json`). The BEFORE state is in `out/baseline_*.json`.

## The headline, both stacks, 337 cases that issue at least one real statement

| | clean | LOST writes | LOST reads | FABRICATED writes | FABRICATED reads |
|---|---|---|---|---|---|
| core BEFORE | 2 | 323 | 206 | 0 | 95 |
| core AFTER | **207** | **82** | 206 | 35 | 21 |
| override BEFORE | 83 | 222 | 206 | 205 | 11 |
| override AFTER | **207** | **82** | 206 | 26 | 11 |

The two stacks now agree exactly, which is the point: the endpoint layer's
renderer moved into the core, so the 77 core-only write endpoints get what
the one overridden endpoint had.

**The 82 remaining lost writes are not 82 missing statements.** Taking the
fabricated side apart against them (`compare.py` + table+verb matching):

| | core | override |
|---|---|---|
| lost write that HAS a note of the right table and verb, wrong column set | 28 | 20 |
| lost write with no note of that table and verb at all | 54 | 62 |
| noted write with no real counterpart at all | 7 | 6 |

Before the fix the same breakdown was 0 / 323 / 0 (core) and 158 / 64 / 47
(override). So on the core stack the change is: 323 statements that appeared
nowhere become 54 that appear nowhere, 28 that appear with the wrong column
set, and 241 that are exactly right.

The 54 are G2 and G3 below. The 28 are G4, G4b and G5. The 7 are G8.

---

## G1 — Statements issued by validations and callbacks inside a mocked body

**The largest remaining family, and it is not reducible by better rendering.**

A mock replaces a method's whole body. `save` runs `valid?`, which runs the
model's validations, which query — `validates_uniqueness_of` issues
`SELECT 1 AS one FROM … LIMIT 1`, `validates_presence_of :person` loads the
person, a `before_save` may load anything. None of it happens under the mock,
so none of it reaches a note.

Measured example (`Contact#update`, real):

```
SELECT  "users".* FROM "users" WHERE "users"."id" = ? LIMIT ?
SELECT  "people".* FROM "people" WHERE "people"."id" = ? LIMIT ?
SELECT  1 AS one FROM "contacts" WHERE "contacts"."person_id" = ?
        AND "contacts"."id" != ? AND "contacts"."user_id" = ? LIMIT ?
```

Rendering these generally would mean re-implementing each model's validation
set inside the target library — the statements depend on which validators are
declared, on their `scope:`/`conditions:` options, and on the record's state.
That is not a note-rendering fix; it is a second implementation of
ActiveRecord's validation layer, and it would be wrong the first time the app
changed a validation.

**The honest alternatives, neither taken here:**

* let the real body run and mock only at the connection boundary — a
  `src_new` change, and out of scope by instruction;
* declare the validators themselves as targets, so each one's query becomes
  its own access. This is tractable for the two or three validator classes
  diaspora actually uses (`UniquenessValidator` already has a prepend in the
  aspect_memberships layer for its binds) and is the recommended next step.

## G2 — The `destroy` cascade

A real `destroy` runs `dependent:` callbacks before deleting the row. Measured,
`Contact#destroy`:

```
SELECT "aspect_memberships".* FROM "aspect_memberships" WHERE "contact_id" = ?
SELECT "notifications".*      FROM "notifications"      WHERE … target_type = ? …
DELETE FROM "contacts" WHERE "contacts"."id" = ?
```

The note now carries the third line (that is the D6/D7 repair) and not the
first two. Diaspora declares 28 `dependent:` associations directly plus 8 more
injected by concerns into every `Post`, `Comment` and `Photo`; `Person` alone
cascades into 13 tables, and some cascades are plain `before_destroy`
callbacks (`contact.rb:25`, `mention.rb:15`, `post.rb:38`) that no reflection
describes.

**Why it is not fixed here.** Rendering it requires either

* fabricating a `symbolic_instance` per dependent row so each child's own
  `destroy` target fires — which mints a record's worth of symbolic variables
  per association, fans out badly on `Person`, and invents rows no query
  returned; or
* emitting several statements from one note — which the IR forbids:
  "a different note is a different access" (`concolic/model/note.py`), so
  folding a cascade into one note declares three accesses to be one.

Both change the execution tree and the access identity, which is a decision
for the owner, not for a defect fix. The design is written down above so it
can be taken up deliberately.

## G3 — `destroy_all`'s per-row DELETEs

`Relation#destroy_all` keeps its SELECT note, and that note is TRUE — real
ActiveRecord does issue exactly that SELECT to load the rows. What is missing
is the per-row `DELETE` (and each row's own cascade, i.e. G2). Same reason as
G2: they are separate accesses.

`delete_all` and `update_all` are NOT in this family — they are single
statements and are fixed (D5).

## G4 — Columns written by `before_create` / `before_save` callbacks

A callback that assigns a column before the INSERT is invisible to a mock that
replaces `save`. Measured, `authorization.o_auth_access_tokens.create`:

```
real : INSERT INTO "o_auth_access_tokens" ("authorization_id", "token", "expires_at", "created_at", "updated_at")
note : INSERT INTO "o_auth_access_tokens" ("authorization_id", "created_at", "updated_at")
```

`token` and `expires_at` are set by the model's `before_create`. The verb, the
table, the owner foreign key and the timestamps are right; two
callback-assigned columns are short. This is a strictly smaller gap than the
one it replaced (before D7a there was no note at all), and closing it has the
same shape as G1.

## G4b — A deferred association INSERT cannot name the owner's foreign key

D8 recovers the join-row INSERT itself. Measured after the fix:

```
real : INSERT INTO "aspect_memberships" ("aspect_id", "contact_id", "created_at", "updated_at")
note : INSERT INTO "aspect_memberships" ("aspect_id",                "created_at", "updated_at")
```

`aspect_id` is there and, correctly, as a symbolic reference
(`$$(SYM_RESULT_…_find_4_id)`) rather than a literal. `contact_id` is not,
and cannot be: the owner's own INSERT is mocked, so the owner never receives
a primary key, and there is no value — symbolic or concrete — to point the
foreign key at. Naming the owner's INSERT as the producer of that key would
be the right fix and needs a producer relation the IR does not currently
express between two notes.

## G5 — Counter caches and counter-cache-like callbacks

`Tagging#save` fires `UPDATE "tags" SET "taggings_count" = COALESCE(…) + 1`,
`Comment` and `Like` update their parent's counters, `Reshare` updates the
root's. These are `after_save` callbacks issuing a second statement — same
family as G2/G3 (a second access), same reason for not folding them into one
note.

## G6 — `PostService#mark_user_notifications` statements 2-4

D7b changed the declaration from `SHIM` to `TARGET_FUNCTION` and gave it the
one statement it always issues. Its body issues up to four, and the fourth is
CONDITIONAL (`if mention_ids.any?`). Widening the note to cover them would
collapse a conditional access into an unconditional one, which this library
does not do. The complete fix is to delete the declaration so the real body
runs and each inner call reaches its own target; that needs the
`CastableSymbolicInt` promotion described in the report and changes which
targets fire on `posts_show`, so it is the owner's call.

## G8 — Noted writes with no real counterpart at all

Seven on the core stack, six on the override stack. They are the mirror of
G4/G5 one level down: the mock accounts for a deferred autosave child
(D8) or renders a `proxy_create` INSERT in a case where the REAL run's
equivalent write went to a different table, or did not happen because the
real association never materialised the same child. Each is a concrete note
naming a table and a verb, so none of them is silent; they are counted here
rather than absorbed, and they are the smallest of the four buckets.

## G7 — Validation-blocked write scenarios in the check itself

Not an application gap — a property of the check. Some probe rows fail a
model's validations, so the REAL run issues the validation SELECTs and then no
write, while the mock renders the write it models (the `<name>_<op>_ok`
symbol is seeded true and stays a flippable decision). `compare.py` reports
these in their own `validation_blocked` bucket and never folds them into
LOST or FABRICATED in either direction.

---

## What the check itself cannot see

The differential drives ActiveRecord operations directly, model by model. It
does **not** drive the 162 HTTP entry points end to end, because no real-mode
fixture plan exists for them (`entrypoints/scaffold/*/config.json` has
`fixtures: null`, `real_mode_plan: null`), and authoring one per endpoint is a
larger project than this repair.

What that costs, stated plainly:

* it covers every WRITE MECHANISM the 79 write endpoints use, because those
  endpoints reach the store through exactly the operations in the matrix;
* it does NOT cover an endpoint's own read path, controller filters, or view
  rendering, so a SELECT lost there would not appear in these numbers;
* the existing shakedown dumps are the partial substitute — they are real
  driven runs — but they reach a write on only 2 of 138 endpoints, because
  the shakedown runs at `MAX_RUNS=2` and most runs terminate before the
  action's write. They confirm D5/D6 in the wild and can confirm nothing
  about breadth.
