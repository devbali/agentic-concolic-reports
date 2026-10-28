# Boundary note gaps — the values the corpus cannot account for (2026-09-15)

**Status: FINDING, not a repair.** Every gap below is a TARGET-BOUNDARY defect
(`targets.rb` / `src/ruby_runtime/call_interceptor.rb`), i.e. **Rule T**
territory — DISCIPLINE §8: a defect in a target declaration voids every
endpoint and forces a from-scratch regeneration. Nothing here was edited.

## Why this is now the blocking item

Until 2026-09-15 an unresolved bind was indistinguishable from a resolver
limitation. It no longer is. `src/queries_from_runs/transform.py` now resolves
a bind by **inlining the query that produced it as a join and recursing on
that query's binds**, and a producing query is ANY recorded query — a
`symbolic_call` note or a `symbolic_vars` note. Measured over 150 dumps of
each of the six corpora after that change:

| corpus | distinct placeholders left | all caused by |
|---|---:|---|
| conversations_index | 2 | request params (`SYM_PARAM_*`) — a legitimate leaf |
| comments_index | 0 | — |
| notifications_index | 0 | — |
| people_show | 3 | **the boundary recorded no statement** |
| people_stream | 3 | **the boundary recorded no statement** |
| posts_show | 11 | **the boundary recorded no statement** |

**Zero remaining resolver-caused placeholders, corpus-wide.** Every surviving
placeholder is a value whose producing query the run never recorded. No change
to `src/queries_from_runs` can recover a statement that was never written
down, so these are the whole of the remaining gap — and they are what blocks
two other things:

1. **100% policy loadability.** An unresolved bind ships as a bare
   `_SYM_RESULT_...` token, which the project's own SQL loader rejects
   (`unrecognized constant`), so the whole statement fails to load and,
   per `subsume.py`'s contract, "participates in no pair and always
   survives" — it stays in the policy meaning nothing to any consumer.
2. **The `principal.binds` regex set in `queries_config/app.json`.** `uid`,
   `identity_id`, `identity_prefix` and the two `non_principal_identity_*`
   vetoes exist because provenance cannot reach those symbols. It cannot
   reach them for exactly the reason below: their mint sites record a
   DESCRIPTION instead of a SELECT. Once they record the statement, the
   general recursion classifies them and the regexes can go. Not before —
   deleting them today would lose resolution, not simplify it
   (`SYM_PERSON_PO_id` alone is 1 196 482 occurrences on posts_show).

## The gaps, by mint site

### B-1 · class-level finder drops its kwargs → no WHERE
*people_show:* `SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id`
(198 occurrences / 150 dumps), `..._find_by_2_id` (18).

```
note: "User query (class-level finder; WHERE unavailable -- interceptor drops
       kwargs for *rest-signature finder methods called with keyword syntax,
       see call_interceptor.rb param binding), args=args=nil LIMIT 1"
```

The note NAMES ITS OWN CAUSE: `call_interceptor.rb`'s parameter binding drops
keyword arguments for `*rest`-signature finder methods, so `User.find_by(
username: ...)` arrives with `args=nil` and the interceptor cannot render a
WHERE. The row is real and came from a real `SELECT "users".* FROM "users"
WHERE ...`; only the predicate is lost.
**Same class as people_show's known Class-S defect** (10 767 degenerate
placeholder notes; no `users` statement in that policy at all).
**Owner:** `src/ruby_runtime/call_interceptor.rb` — SHARED. Rule T.

**FIXED 2026-09-15** (`call_interceptor.rb.bak_pre_b1_20260915`). The binding
loop's only keyword lookup was `kwargs[<parameter name>]`; for a method whose
real signature is a bare `*args` (`ActiveRecord::Core::ClassMethods#find_by`,
activerecord-5.2.4.3 `core.rb:186`) the wrapper's `**kwargs` swallows the
trailing hash, `kwargs[:args]` is `nil`, and the call records `{"args": null}`.
29 lines added after the loop (nothing existing modified): keywords bind to the
`*rest` parameter they were really passed as, ONLY when the method declares no
`:key`/`:keyreq`/`:keyrest`, a named `:rest` exists, and that slot is still
`nil`. Note before/after:

```
- FakeUser query (class-level finder; WHERE unavailable -- interceptor drops
  kwargs ...), args=args=nil LIMIT 1
+ SELECT "users".* FROM "users" WHERE "users"."username" = $$(username) LIMIT 1
```

Exercised on ruby 3.2 AND JRuby 9.3.0.0: 2 defect cases changed, 5 controls
byte-identical (including the double-wrapped `{splat_args,kwargs,block}` shape
that conversations_index's mocks read). `src/test_ruby_runtime.rb` 65/0 before
and after; `test_name_boundary_seed.rb`'s single failure reproduced with the
backup swapped in, so it is pre-existing and unrelated.

**B-1a — the existing app-level workaround is DEAD CODE.** Every
`results3/*/concolic_targets.rb` carries `ConcolicKwargsToPositional`
("bug 2a") for this exact problem. It does not work on either runtime: its own
`define_method(m) do |*args, **kwargs|` re-splats `super(*args)` and the
trailing symbol-keyed hash is re-absorbed by the interceptor wrapper's
`**kwargs`. Verified empirically pre-patch on both runtimes. It should be
removed or corrected — but removing it is NOT additive, so it needs a ruling.

**B-1b — the same drop affects signatures OUTSIDE B-1's guards, and was left
deliberately.** Single-positional signatures called with keyword syntax
(`Person.name {"opts":null}`, `MessageRenderer.title {"opts":null}`,
`url_for {"options":null}`, `exists?(conditions) {"conditions":null}`) and the
double-wrapped `{splat_args,kwargs,block}` family lose their kwargs too.
Fixing those would MOVE EXISTING NOTES, which the additive-only rule forbids,
so they are open and need their own ruling.

### B-2 · the identity association mint records a description
*people_stream:* `SYM_PERSON_via_user_id` (40 / 150 dumps).

```
note: "User#person (has_one)"
```

Mint: `UserSymPersonAssociation#person`, `results3/people_stream/targets.rb`
§8 and `results3/people_show/targets.rb:830`, prepended onto `User`. It stands
for `SELECT "people".* FROM "people" WHERE "people"."owner_id" = <that user's
id>` but records prose. X1 (2026-09-10) established on independent evidence
that this symbol is NOT the principal — the person NAMED IN THE URL — which is
why the `non_principal_identity_name` veto exists. If the mint recorded its
SELECT, the recursion would reach that conclusion by itself and the veto could
be deleted.
Second, separate defect at the same site (X1 §7.1): it mints ONE FIXED NAME
for every `User` row it is called on, so two `.person` reads on two users
would alias onto one symbol. The repair is `SYM_PERSON_via_<result_name>`.
**Owner:** the endpoints' `targets.rb`. Rule T.

**FIXED 2026-09-15** in the only two copies that carry the site —
`results3/people_show/targets.rb` and `results3/people_stream/targets.rb`
(changed-region hash `828389494aca7bb3`, identical on both; the other four
copies have no such site and are byte-identical to their pre-task state).
The mint now records the statement, rendered by the same shared
`ConcolicTargets.render_relation_sql` that already writes the CALL-EVENT note
for this relation, so the two agree byte-for-byte:

```
- "User#person (has_one)"
+ SELECT "people".* FROM "people" WHERE "people"."owner_id" = $$(...) LIMIT 1
```

Guarded by `rescue Exception` — NOT `StandardError`: a symbolic wall raises
`NotImplementedError < ScriptError`, which `StandardError` does not catch and
which would have escaped and crashed `person`. `ConcolicTargets.sql_for`
already uses `rescue Exception` for the same reason. Every failure mode
(NoMethodError / NotImplementedError / "(no arel)") falls back to the old prose
note BYTE-IDENTICALLY — never a new prose string. No query behaviour moved
(`Person.where` is lazy; people_show's fallback still issues no query at all).

The ` LIMIT 1` is APPENDED exactly as `finder_note` appends it under Rule T4 —
Arel does not emit it for `rel.limit(1)` — so the note is byte-identical to
what the ordinary query boundary already writes for this relation.

**Renderer verified on the corpus, not assumed** (26 674 dumps of the two
affected corpora, read-only): people_stream has the successful rendered
`SELECT "people".* FROM "people" WHERE "people"."owner_id" = $$(...) LIMIT 1`
note in 7 695 dumps, people_show in 9 946, and **zero** `render_relation_sql`
failure notes on a Person/people relation in either. B-4's `NoMethodError` is a
different relation shape (the posts_show Reshare query), so B-2 is NOT blocked
on B-4 — on a bare `people.owner_id = ?` equality the renderer is measured to
succeed and to emit precisely this text.

Coverage note: people_show's corpus mints `SYM_PERSON_via_user_*` in **0 of
12 997 dumps** — its `association(:person).reader` path never falls through —
so the people_show edit repairs a LATENT path with no observed occurrences.
Only people_stream (200 of 13 677 dumps) exercises it today.

**It does not change shipped SQL today.** Measured with the real `transform.py`
and the live `app.json`: `_bind_value` reaches `is_identity_bind`
(`identity_prefix: ^SYM_PERSON_`) BEFORE the recursion, so the bind stays the
same flagged placeholder either way. What the repair supplies is the PRODUCER.
With the identity regexes retired, the recursion then resolves it to
`posts.author_id = people.id AND people.owner_id = $$(<the URL user's row>)` —
**X1's conclusion reached by provenance, with no `_MY_UID` anywhere** — where
the old prose note yields nothing but the placeholder.

**Config consequence, for whoever retires the regexes.**
`principal.binds.non_principal_identity_note` (`^\s*User#person\b`) STOPS
MATCHING after this repair: a note cannot both start with `User#person` and
start with `SELECT`. No veto is lost —
`non_principal_identity_name` (`^SYM_PERSON_via_user(?:_|$)`) and
`identity_prefix` both still fire. (A trailing SQL comment to keep both was
tried and REJECTED: it defeats `_split_limit` and leaks `LIMIT 1 /* ... */`
into the emitted statement.)

**The X1 §7.1 RENAME IS STILL OPEN — it is not additive-safe.** Three
independent reasons, any one sufficient: (1) the name appears as a `$$()` bind
inside OTHER statements' notes, so renaming changes the shape of existing
statements in 35 of people_stream's 107 views; (2) it voids a live safety veto
— a renamed symbol matches neither `non_principal_identity_name` nor (post-
repair) the note veto, leaving only the shape rule that X1 §4 showed silently
converts a `User#person` mint into `people.owner_id = _MY_UID`; (3) it
invalidates every corpus on disk (11 251 occurrences on people_stream alone).
The truthful note does narrow it: a future rename becomes provenance-supported
rather than blind.

### B-3 · the serializer returns rows with no link to their query
*people_stream:* `SYM_RESULT_ActsAsApi__Collection_as_api_response_{1,2}_row_id`
(122 + 65). *posts_show:* the same family `_1..4_row_id` (78 + 82 + 69 + 47).

```
note: "ActsAsApi::Collection#as_api_response"
```

Mint: `declare_target(ActsAsApi::Collection, :as_api_response, ...)`,
`results3/posts_show/targets.rb:812`. This is a SERIALIZER, not a query — but
the rows it serialises were fetched by an earlier query, and the interception
keeps no reference to it, so the ids it exposes are unaccountable. The repair
is to carry the source relation's note through the serializer rather than to
invent a statement for it.
**Owner:** `targets.rb`. Rule T.

### B-4 · `render_relation_sql` crashes and the crash is stored as the note
*posts_show:* `..._CollectionProxy_records_2_row_root_guid` (1 574 / 150
dumps — the single largest gap), `..._row_id` (155), `..._row_author_id` (84),
`..._FinderMethods_find_by_{3,6,9}_author_id` (41 + 27 + 22).

```
note: "Reshare query (render_relation_sql failed: NoMethodError
       undefined method `value' for #<Arel::Nod), args="
```

The runtime TRIED to render the statement and threw
`NoMethodError: undefined method 'value' for #<Arel::Nod...>`; the exception
text was then stored in the note field. This is a plain bug in the Arel
renderer for one node shape, and it is the cheapest of these to fix: the
statement exists, the relation is in hand, only the rendering fails.
**Owner:** the shared `render_relation_sql` helper. Rule T.

**FIXED 2026-09-15**, and the root cause is a divergence artefact, not a new
bug. `collect_binds`'s Casted branch did `out << node.value`; arel-9.0.0's
`Arel::Nodes::Casted` exposes **`#val`**, not `#value` (`Quoted` aliases
`value`, `Casted` does not). An STI predicate `type IN ('Reshare')` builds a
Casted via `Attribute#in -> build_quoted`, so EVERY STI relation raised. Casted
is also rendered INLINE by `ToSql#quoted` and never emits a `?`, so it must not
join the bind list at all — the fix skips it without collecting.

**The fix already existed.** It landed 2026-08-19 as "bug-2b" in the five
endpoint copies and never reached the CANONICAL copy or posts_show's. That is
why posts_show showed B-4 and the others did not: it is not a posts_show
defect, it is a copy that missed a month-old repair. See `TODO.md` T-DIV — this
is the concrete evidence that the boundary divergence causes real, silent,
long-lived defects.

Exercised on the REAL environment (JRuby 9.3.0.0, arel 9.0.0),
`u.association(:person).scope`:

```
concrete owner id -> SELECT "people".* FROM "people" WHERE "people"."owner_id" = 7
symbolic owner id -> SELECT "people".* FROM "people" WHERE "people"."owner_id" = $$(SYM_USER_id)
```

Both render, neither raises, byte-identical to `Person.where(owner_id: S)`.
**Success output is unchanged, measured not asserted:** a 12-case differential,
pre-patch vs post-patch canonical over the same relations — 8 byte-identical,
4 crash->statement, **0 MOVED**. This also settles the B-2 dependency: B-2 runs
against the five endpoint copies, which already carried the fix, so it was
never blocked.

### B-5 · NOT a missing note — a NAME defect (premise corrected 2026-09-15)

*posts_show:* `SYM_RESULT_ActiveRecord__Calculations_ids_1_ids` (62 / 150
dumps).

**The original premise here was wrong and is retracted.** `noteless_call_audit`
on posts_show (150 dumps) returns NO `Calculations.ids` finding: all 96 `ids`
call events DO carry a note. The defect is that `posts_show/targets.rb` names
the produced list `<result>_ids`, and `ids` is not a column of any table — so
`transform.py`'s `<producer>_<column>` recursion cannot place the bind
`$$(..._1_ids)` (72 notes / 150 dumps) and it ships as a placeholder.

The shared declaration now names it after the real primary key
(`<result>_id`), which resolves. **posts_show's LOCAL declaration shadows the
shared one**, so the gap stays open on posts_show until that override is
dropped — for the `targets.rb` owner, after that campaign closes.

### Not a boundary gap
*people_show:* `SYM_POSTS_GUID` (12), note `"bio/location diasporalink guid"`.
A runner-declared FREE SYMBOL standing for an arbitrary guid in post text —
there is no query behind it and there should not be. It is a leaf like a
request parameter, and the honest emission for it is the same: broaden the
predicate away, or declare it. It is listed here only so the census adds up.

## Suggested priority

1. **B-4** (`render_relation_sql`) — largest single gap, plainly a bug, no
   design question.
2. **B-1** (interceptor kwargs) — named by its own note, and the same class as
   people_show's standing Class-S defect.
3. **B-3** (serializer provenance) — needs a small design decision (carry the
   source relation through).
4. **B-2** (identity mint) — two defects at one site; fixing it is what lets
   `app.json`'s identity regexes be deleted.
5. **B-5** — run `noteless_call_audit` on posts_show first to size it.

All five are Rule T. **They must not be repaired from an extraction task**: a
boundary change voids every endpoint and forces regeneration, so this file is
the hand-off, not the fix.
