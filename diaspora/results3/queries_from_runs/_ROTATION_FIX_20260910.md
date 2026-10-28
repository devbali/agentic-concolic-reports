# `_repair_rotation` — extraction-stage unsoundness, fixed (2026-09-10)

Scope: `src/queries_from_runs/transform.py` `_Build._repair_rotation` and its
new helpers, the transform tests, and the R1 RED check in the two extractors
that carry it. **Python only.** No JRuby, no driving, no blockaid (every
extraction ran `SKIP_SUBSUME=1`), `JAVA_TOOL_OPTIONS` unset, every job under
`systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=1G`; peak
RSS never exceeded **82 MB**. `src/concolic_engine`, `src/ruby_runtime` and
every `concolic_targets.rb` untouched; the runtime note render (Rule T, the
shared boundary) untouched. Reference policies not read, still quarantined.

---

## 1. HEADLINE

| | before | after |
|---|---|---|
| people_stream views | 1 248 | **107** |
| people_stream unparseable notes | 0 | **0** |
| people_stream R1 rotation residue | **1 246 of 1 248** views wrong | **0** |
| people_stream `type-mismatched-join` flags | 5 088 | **0** |
| views changed by the fix | — | **9 360 of 9 884** raw (672 of 755 runs) |
| closed endpoints changed | — | **NONE — all four, plus posts_show, byte-identical** |
| `src/queries_from_runs` tests | 38 | **43 passed** |

The bad views were not merely imprecise. The endpoint's headline statement was

```sql
-- BEFORE (shipped-shaped, WRONG)
SELECT `posts`.* FROM `posts`, `people`
 WHERE `posts`.`author_id` = 'Reshare'          -- an int column = a post TYPE
   AND `posts`.`created_at` < `people`.`id`     -- a datetime column < an id
   AND `posts`.`type` IN ('2026-09-09 09:12:17 +0000', 'StatusMessage')
   AND `people`.`closed_account` = FALSE;
-- AFTER (uniquely determined un-rotation)
SELECT `posts`.* FROM `posts`, `people`
 WHERE `posts`.`author_id` = `people`.`id`
   AND `posts`.`created_at` < _NOW
   AND `posts`.`type` IN ('StatusMessage', 'Reshare')
   AND `people`.`closed_account` = FALSE;
```

`author_id = 'Reshare'` is not a narrow predicate that happens to be wrong: the
author restriction — the whole point of a person's stream — was **detached from
the principal**. That is an over-permission in shipped SQL, the E5 class.

---

## 2. CHARACTERISATION — what the runtime actually renders

All 755 dumps, every SELECT note on a `symbolic_call` event: **9 884 notes,
2 176 of them rotation-triggering** (a non-integer trailing `LIMIT`/`OFFSET`
token), in exactly **8 distinct shapes / 3 families**.

| n | family | slot sequence as rendered | LIMIT |
|---|---|---|---|
| 1 152 | posts stream (no `public`) | `author_id`=15, `created_at`<**BIND**, `type` IN (`<TS>`, `'StatusMessage'`) | `'Reshare'` |
| 144 | posts stream (with `public`) | `author_id`=15, `public`=**BIND**, `created_at`<`true`, `type` IN (`<TS>`, `'StatusMessage'`) | `'Reshare'` |
| 448 | post comments | `commentable_id`=3, `commentable_type`=**BIND** | `'Post'` |
| 432 | (the first family, third bind) | as above with `SYM_PERSON_via_user_id` | `'Reshare'` |

The bind families that land in a rotated slot are
`SYM_RESULT_ActiveRecord__FinderMethods_first_1_id`,
`SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id`,
`SYM_PERSON_via_user_id` and
`SYM_RESULT_ActiveRecord__Relation_records_{1,4}_row_id`.

**The rotation is a right-shift by one per trailing LIMIT/OFFSET token** — the
LIMIT value is rendered into the FIRST WHERE slot and every other value moves
one place right. Note two things the old repair missed:

* the **symbolic bind occupies a slot**. The old repair collected only slots
  whose RHS parsed to a literal, so the bind slot was skipped, the slot list
  was one short, and every value landed one place off;
* every **element of an `IN` list is its own slot** (`exp.In` is not an
  `exp.Binary` in sqlglot, so the old `where.find_all(exp.Binary)` never saw
  them). In the largest family that alone loses two slots.

On the biggest family the old repair therefore had `slots = ['15']` and
`values = ['15', 'Reshare']`, and emitted `author_id = 'Reshare'`.

---

## 3. THE RULE

> **A rotation is applied only when it is UNIQUELY DETERMINED by the types of
> the slots and the values; otherwise nothing is rotated and the note is
> flagged.**

Concretely:

1. **Slot sequence** = every position the runner rendered a value into, in
   render order: each comparison's RHS, **every element of an `IN` list**, both
   `BETWEEN` bounds, then the `LIMIT` and `OFFSET` tokens. **Symbolic binds
   (`$$(...)`) count as slots.** (`_conjuncts` + `flatten()` gives render order;
   sqlglot's `find_all` is breadth-first and does not.)
2. **Every slot has a column type** — from `schema.rb` for a WHERE slot,
   `integer` for LIMIT/OFFSET.
3. **Every value has a type.** A literal's comes from its render. **A bind's
   comes from the column its NAME carries**: `SYM_RESULT_<producer>_<col>` (or
   `..._row_<col>`) is the `<col>` of the row `<producer>` returned, and
   `<producer>`'s primary table gives that column a type — so
   `SYM_RESULT_ActiveRecord__Relation_records_4_row_id` is a `posts.id`, an
   integer, and cannot be the value of `comments.commentable_type`.
   `SYM_USER_*_id` / `SYM_PERSON_*_id` and any `*_id` are integers;
   `SYM_PARAM_*` and unresolvable producers are **unknown**.
4. **A rotation `r` is admissible iff every value lands in a slot whose type
   family accepts it.** Families: int / num / bool / dt / str. Unknown column
   or unknown bind type accepts anything.
5. **Exactly one admissible `r` → apply it**, flag `bind-rotation-repaired`.
   **Zero, or more than one → do not guess**: leave the note exactly as the
   runner rendered it and flag **`bind-rotation-UNRESOLVED`**, plus one
   `unresolved bind-rotation: <sql>` line in `errors` so the residue is
   enumerable.

Two deliberate asymmetries:

* **Unknown types widen the candidate set, never narrow it.** Missing schema
  knowledge can only make a rotation *ambiguous* (flagged), never *wrong*.
* **A bare `0`/`1` literal is accepted by a boolean column** (Rails' sqlite and
  mysql adapters render booleans that way, and `clean_conjunct` already
  normalises it), but an **integer-typed BIND is not** — for a bind we know the
  source column exactly, and `people.id` is not a boolean. That asymmetry is
  what refutes `r = 0` on the `public = $$(..._id)` family.

Measured on the corpus: **all 8 rotated shapes have exactly one admissible
rotation, `r = 1`**, and it is the semantically correct one in every case
(`author_id` = the person bind, `public` = TRUE, `created_at` < the timestamp,
`type IN ('StatusMessage','Reshare')`, `commentable_id` = the post bind,
`commentable_type` = `'Post'`, LIMIT = 15 / 3).

### Where the rule could still fail to decide (stated, not hidden)

The rule decides here because each family contains a value whose type is
incompatible with every slot but one. It would go **ambiguous** on a note whose
slot-type pattern is cyclically symmetric — e.g. all-unknown columns, or a
`(str, int, str, int)` column pattern with a `(str, int, str, int)` value
pattern. It would go **refuted** (zero admissible) if the runner ever rotated by
something other than a whole number of slots, or if a genuinely string column
held a timestamp-shaped literal. Both outcomes are flagged, not guessed, and
`test_bind_rotation_ambiguous_is_flagged_not_guessed` /
`test_bind_rotation_refuted_is_flagged_not_guessed` pin them. **Neither occurs
on any of the six corpora.**

---

## 4. THE FIX

`src/queries_from_runs/transform.py`, minimal and confined:

* new module-level helpers next to `_lit_value`: `_TYPE_FAMILY`, `_family`,
  `_is_bind_node`, `_RotValue` (a literal or a bind, with `fits(ctype)`),
  `_token_rot_value`, `_collect_rot_slots`;
* new `_Build` methods `_bind_column_type` (name → producer → table → column →
  type; **no side effects** — unlike `_bind_value` it never inlines a
  producer), `_rot_value_of`, `_slot_column_type`;
* `_repair_rotation` rewritten around them. **Its entry guard is byte-identical
  to the old one** (`if not limit_toks or all(_tok_is_int(t) ...): return`;
  `if where is None: return`), which is what makes §5's differential argument
  exhaustive.

Also updated, for accuracy rather than behaviour: the module docstring and
`src/queries_from_runs/README.md` step 5.

Not `src/`: the R1 RED check in
`results3/queries_from_runs/_extract_people_stream_streaming.py` and
`_extract_posts_show_streaming.py` was **rearmed onto the new flag** —
`bind-rotation-UNRESOLVED` is RED, `bind-rotation-repaired` is now INFO
("a uniquely determined un-rotation was applied"), because after the fix the
old flag means the opposite of what it meant when the check was written.

**Not done, deliberately:** the runtime note render. It is the shared boundary
(Rule T) and a change there restarts every endpoint.

---

## 5. SIX-CORPUS DIFFERENTIAL — only people_stream changes

**(a) Exhaustive, by construction.** The repair is entered only when the note's
trailing `LIMIT`/`OFFSET` token is non-integer, and that guard is unchanged by
the fix. Every `LIMIT ...` tail in every dump file of all six corpora was
scanned (`grep`, not sampled — 318 512 files):

| corpus | dumps | LIMIT tails found | **non-integer (rotation-triggering)** |
|---|---:|---|---:|
| comments_index | 26 528 | `LIMIT <N>` 1 715 441 | **0** |
| conversations_index | 18 623 | `LIMIT <N>` 2 925 757, `LIMIT <N> OFFSET <N>` 277 912 | **0** |
| people_show | 12 997 | `LIMIT <N>` 2 308 201 | **0** |
| notifications_index | 163 252 | `LIMIT <N>` 16 249 921, `LIMIT <N> OFFSET <N>` 2 023 874 | **0** |
| posts_show | 96 357 | `LIMIT <N>` 187 450 | **0** |
| **people_stream** | 755 | `LIMIT <N>` 1 056 | **`LIMIT 'Reshare'` 39 744, `LIMIT 'Post'` 5 824** |

(The people_stream counts are raw textual occurrences over the whole dump —
`call` and `symbolic_call` events carry the same note — against the 2 176
`symbolic_call` SELECT notes the transformer actually consumes.)

**(b) Empirical, sampled.** Every note re-rendered through the OLD and the NEW
`_repair_rotation` **in one process**, per run, emitted-view lists compared
(`scratchpad/rot/six_corpus_diff.py`, 3 000 random seeded dumps per corpus —
random, never a sorted prefix; people_stream in full):

```
comments_index         pop=  26528 sampled= 3000 views=  47015  RUNS DIFFERING=  0  VIEWS DIFFERING=     0
conversations_index    pop=  18623 sampled= 3000 views=  64871  RUNS DIFFERING=  0  VIEWS DIFFERING=     0
people_show            pop=  12997 sampled= 3000 views=  78197  RUNS DIFFERING=  0  VIEWS DIFFERING=     0
notifications_index    pop= 163288 sampled= 3000 views=  49908  RUNS DIFFERING=  0  VIEWS DIFFERING=     0
people_stream          pop=    755 sampled=  755 views=   9884  RUNS DIFFERING=672  VIEWS DIFFERING=  9360
posts_show             pop=  96357 sampled= 3000 views= 123498  RUNS DIFFERING=  0  VIEWS DIFFERING=     0
peak RSS 82 MB
```

**No closed endpoint's rendering changes.** No shipped policy carries a
rotation error; nothing needs re-extraction anywhere but people_stream.
people_stream's 9 360 changed views are exactly its `bind-rotation-repaired`
flag count, i.e. every rotated note and nothing else.

---

## 6. PEOPLE_STREAM — before / after

Full 755-dump extraction, `SKIP_SUBSUME=1`, 1 GB cap, **41 MB peak RSS**,
written to the scratchpad (this is a DRY RUN — `people_stream.sql` is not
shipped; the endpoint is not closed and subsumption has not run).

| | before (old repair) | **after** |
|---|---|---|
| dumps / runs loaded | 755 / 755 | 755 / 755 |
| raw → distinct → final views | 9 884 → 1 248 → **1 248** | 9 884 → 107 → **107** |
| **unparseable notes (E11)** | **0** | **0** |
| **R1 rotation residue** | **1 246 views RED** | **0 — R1 is silent** |
| `bind-rotation-repaired` | 9 360 (all wrong) | 9 360 (all uniquely determined) |
| `bind-rotation-UNRESOLVED` | n/a | **0** |
| `type-mismatched-join` | 5 088 | **0** |
| `unscoped` | 260 | 260 |
| subsumption-eligible | 1 of 1 248 | **36 of 107** |
| placeholder occurrences | 1 490 | 142 |

**Views changed: 105 of 107** (only the 2 views that never carried a rotated
note are identical to a before-view). **Residue: none — no ambiguous or refuted
rotation remains on this corpus.**

The 1 248 → 107 collapse is not lost information, it is the defect's own
signature: the rotation pushed a **per-run wall-clock timestamp** into
`posts.type`, a *string* column, where the datetime → `_NOW` rewrite could not
normalise it, so every run minted fresh "distinct" views. Un-rotated, the
timestamp lands on `created_at` and folds to `_NOW`, and 1 141 pseudo-views
collapse into their real 107.

---

## 7. TESTS

`src/queries_from_runs/test_queries_from_runs.py`: **43 passed** (was 38).
Five added:

| test | what it pins |
|---|---|
| `test_bind_rotation_repair` (pre-existing, unchanged) | literal-only rotation — **behaviour is unchanged**, `r` still uniquely determined |
| `test_bind_rotation_repair_with_symbolic_bind_in_a_rotated_slot` | the bug, on the real 5-slot people_stream note |
| `test_bind_rotation_repair_bind_and_boolean_slot` | the 6-slot shape (bind, boolean, datetime, IN list, LIMIT) |
| `test_bind_rotation_ambiguous_is_flagged_not_guessed` | >1 admissible rotation → `bind-rotation-UNRESOLVED`, note left as rendered, error recorded |
| `test_bind_rotation_refuted_is_flagged_not_guessed` | 0 admissible rotations → same |
| `test_unrotated_note_with_bind_is_untouched` | the posts_show-style control: integer LIMIT + a bind → no flag, bind resolves normally |

**Ground-truth differential on the tests themselves** (DISCIPLINE: a check must
distinguish, not merely pass): run against the pre-fix `_repair_rotation`,
**4 of the new tests FAIL** and the two that must not change (literal-only
rotation, unrotated control) PASS.

---

## 8. WHAT THIS FIX DID *NOT* FIX — one finding, one open issue

**X1 — unresolved binds shipped as placeholders (people_stream).** Three bind
families are emitted as bare `_SYM_...` placeholder columns:

```
_SYM_PERSON_via_user_id                                       70 views
_SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id     70 views
_SYM_RESULT_ActiveRecord__FinderMethods_find_by_2_author_id    2 views
```

`SYM_PERSON_via_user_id` **is the current user's person** and should have become
the `people.owner_id = _MY_UID` join: `_PERSON_ID_RE` in `transform.py` is
`^SYM_PERSON_[A-Za-z0-9]+_id$`, and the underscore in the `via_user` tag makes
it miss. This is **pre-existing and independent of the rotation fix** — both
families were placeholders before it too (1 490 occurrences then, 142 now) —
but the fix *moved them onto `posts.author_id`*, where they are load-bearing:

```sql
SELECT `posts`.* FROM `posts`
 WHERE `posts`.`author_id` = _SYM_PERSON_via_user_id
   AND `posts`.`created_at` < _NOW
   AND `posts`.`type` IN ('StatusMessage', 'Reshare');
```

**That view must not ship as access control while the placeholder is unbound.**
Recorded in `people_stream/POLICY_HEADER.txt` as DECLARED OPEN X1. Fixing
`_PERSON_ID_RE` is a `src/` change with a six-corpus blast radius and was **not**
made here.

**The runtime render bug itself remains.** The extractor now repairs it
soundly; the note the runtime writes is still rotated. That is Rule T territory.

---

## 9. POLICY HEADERS

`people_stream/POLICY_HEADER.txt` and `posts_show/POLICY_HEADER.txt` created,
modelled on `comments_index/` and `people_show/`. Both are **marked TEMPLATE**
and carry explicit `TODO(drive)` markers for everything the drive must measure
(engine verdict, the Argument-5 declaration or the driven branch, adversary
round, full-corpus extraction, subsumption tally, walls). people_stream's is
filled in with the §16b preflight numbers, wall W1, the bind-rotation
explanation, and X1; posts_show's records that it is the **control** — it has no
bind-rotated notes at all — and that its extraction numbers are still a
DUMP_SAMPLE=8000 dry run, a lower bound. The `NO POLICY_HEADER.txt` placeholder
warning no longer fires for people_stream.

---

## 10. FILES

```
src/queries_from_runs/transform.py                 _repair_rotation rewritten + helpers
src/queries_from_runs/README.md                    step 5 describes the rule
src/queries_from_runs/test_queries_from_runs.py    +5 tests (43 passed)
results3/queries_from_runs/_extract_people_stream_streaming.py   R1 rearmed on the new flag
results3/queries_from_runs/_extract_posts_show_streaming.py      R1 rearmed on the new flag
results3/people_stream/POLICY_HEADER.txt           NEW (template)
results3/posts_show/POLICY_HEADER.txt              NEW (template)
results3/queries_from_runs/_ROTATION_FIX_20260910.md  this file
```

`src/` has its own git with many pre-existing uncommitted changes; this work is
**on top of them, nothing reverted, nothing committed**.
