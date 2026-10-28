# X1 — `SYM_PERSON_via_user_id` is **not** the principal. Rule made explicit,
# nothing rebound. (2026-09-10)

Scope: `src/queries_from_runs/transform.py` (`_bind_value` + the new
`RunTransformer.is_principal_person`), its tests, `src/queries_from_runs/README.md`,
and a DECLARE check in `results3/queries_from_runs/_extract_people_stream_streaming.py`.
**Python only.** No JRuby, no driving, no blockaid (`SKIP_SUBSUME=1` throughout),
`JAVA_TOOL_OPTIONS` unset, every job under
`systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=1G`;
peak RSS **84 MB** (the six-corpus differential; the people_stream extraction
ran in the same scope and never came near the cap).
`src/concolic_engine`, `src/ruby_runtime`, every `concolic_targets.rb`/`targets.rb`
and every notifications_index file untouched (its dumps read read-only).
Reference policies not read, still quarantined. `src/` has its own git with
pre-existing uncommitted changes; this work is on top, nothing reverted,
nothing committed.

---

## 0. HEADLINE — the defect report was inverted

X1 said `SYM_PERSON_via_user_id` **is** the current user's person and should
have become the `people.owner_id = _MY_UID` join, and that `_PERSON_ID_RE`'s
`[A-Za-z0-9]+` wrongly rejects it.

**It is not the current user's person.** It is the person of an *arbitrary*
`User` row — on people_stream always the row
`User.find_by_username(params[:username])` returned, i.e. **the VIEWED
person** — and it is minted in **anonymous** runs too, where there is no
principal at all. Binding it to `people.owner_id = _MY_UID` would have
replaced

```sql
-- what the app really issues (the whole point of a person's stream)
SELECT `posts`.* FROM `posts`
 WHERE `posts`.`author_id` = <the person named in the URL>
```

with a **self-only** predicate. That is a *strictly narrower* shipped
statement than the app enforces — a policy that under-claims what the
endpoint reveals, i.e. a false safety claim. The old regex rejected the name
for the right outcome but the wrong reason (an underscore), so the fix here
is to make the refusal a **rule** and to make the resulting placeholder
**enumerable**, not to widen anything.

| | before | after |
|---|---|---|
| people_stream views | 107 | **107 (byte-identical .sql)** |
| people_stream unparseable notes | 0 | **0** |
| people_stream `bind-rotation-UNRESOLVED` residue | 0 | **0** |
| unresolved `_SYM_` placeholder families | 3 | **3 (unchanged — see §6)** |
| views changed, any of the six corpora | — | **0** |
| new flag `non-principal-person-bind` | — | 2 640 raw / **35 of 107** views |
| `src/queries_from_runs` tests | 43 | **47 passed** |

---

## 1. CHARACTERISATION — every `SYM_PERSON_*` name in all six corpora

**Exhaustive, not sampled.** Every `dump_*.json` in all six corpora
(320 746 files) was grepped for `SYM_PERSON_[A-Za-z0-9_]+`.

| corpus | dumps | distinct `SYM_PERSON_*` names | accepted by `_PERSON_ID_RE` | rejected |
|---|---:|---|---|---|
| comments_index | 26 528 | **0** | — | — |
| conversations_index | 18 623 | **0** | — | — |
| people_show | 12 997 | **0** | — | — |
| notifications_index | 165 486 | **0** | — | — |
| posts_show | 96 357 | 1 — `SYM_PERSON_PO_id` (1 196 482 occ.) | 1 | 0 |
| people_stream | 755 | 18 | 1 — `SYM_PERSON_PS_id` (7 392 occ.) | 17 — `SYM_PERSON_via_user_*` |

people_stream's 17 rejected names are one Person object's column set:
`via_user_` + `id` (11 251 occ.), `closed_account`, `guid`, `guid_v`,
`diaspora_handle`, `diaspora_handle_v`, `serialized_public_key(_v)`,
`owner_id`, `pod_id`, `fetch_status`, `created_at(_v,_year)`,
`updated_at(_v,_year)`. Only `_id` ever reaches a bind slot.

So the *only* name X1 is about, corpus-wide, is `SYM_PERSON_via_user_id`.

### What `via_user` IS — established at the mint site, not assumed

The runtime has **exactly two Person mint sites**:

| | mint | note in the dump | who |
|---|---|---|---|
| A | `PeopleStreamTargets.symbolic_user(tag)` → `symbolic_instance(Person, "SYM_PERSON_#{tag}", …)`, attached to the built user with `user.define_singleton_method(:person)` | `"Person (current user's person)"` | **the principal** |
| B | `UserSymPersonAssociation#person` → `symbolic_instance(Person, "SYM_PERSON_via_user", …)`, `User.prepend`-ed onto the **User class** | `"User#person (has_one)"` | **not the principal** |

(`results3/people_stream/targets.rb` §4 `apply_user_overrides!` line 397 and
§8 / line 481; `results3/people_show/targets.rb` line 848 is the same module.
Both files read-only.)

B never fires for the signed-in user: a **singleton method beats a prepended
module** in Ruby's lookup, so `current_user.person` always resolves to A. B
fires for every *other* `User` instance — and on people_stream there is
exactly one such instance, the one the shared `finder_mock` returns for
`User.find_by_username(...)`.

Four independent pieces of evidence, all measured:

1. **Provenance, 211/211.** For every people_stream dump that mints
   `SYM_PERSON_via_user` (211 of 755), the `symbolic_call` immediately
   preceding its first appearance is
   `ActiveRecord::Core::ClassMethods.find_by`, note
   `"User query (class-level finder), args=args=nil"`, called from
   `dynamic_matchers.rb:66` `find_by_username`. **211 of 211, no exceptions.**
2. **Anonymous runs mint it.** 64 of those 211 dumps are `anon_all` / `anon_json`
   — scenarios with **no current user at all**. A symbol that exists when
   there is no principal cannot be the principal's person.
3. **Its `owner_id` is a free symbol.** The dump declares
   `SYM_PERSON_via_user_owner_id` as an independent `Int` var with no
   constraint tying it to the current user. If this were the principal's
   person, `owner_id = _MY_UID` would be a *fact*; here it is an unknown.
4. **The app source says so.** `Person.find_from_guid_or_username`
   (`app/models/person.rb:196`) is
   `elsif params[:username].present? && u = User.find_by_username(params[:username]) then u.person`
   — the person *named in the URL*. `Stream::Person#posts`
   (`lib/stream/person.rb:18`) is
   `user.present? ? user.posts_from(@person) : @person.posts.where(public: true)`,
   and both are mocked to `Post.where(author_id: @person.id)`. So
   `posts.author_id = $$(SYM_PERSON_via_user_id)` reads **"the posts of the
   person whose username is in the URL"** — exactly right, and exactly not
   the principal.

### The other two placeholder families (context, not fixed here)

`SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id` is the **User row**
`u` from the same call. It stays a placeholder for an unrelated reason: that
producer's note is `"User query (class-level finder), args=args=nil"` — **not
SQL**, so `RunTransformer` registers no producer and there is no table to join
to. `SYM_RESULT_ActiveRecord__FinderMethods_find_by_2_author_id` (1 view) is
the same shape. Neither is a `SYM_PERSON_*` name and neither is in X1's scope.

---

## 2. THE RULE

> **A `SYM_PERSON_*` bind becomes the principal join `people.owner_id = _MY_UID`
> only when it is the PRINCIPAL-PERSON MINT. Mint site decides, not name shape.**

`RunTransformer.is_principal_person(bind)`:

1. not a `SYM_PERSON_*` name → **not principal** (unchanged; other resolvers apply);
2. name matches `^SYM_PERSON_via_user(?:_|$)` → **never principal** (mint B, by
   name — anonymous and short runs need not declare the var);
3. the run declares a symbolic var of this name whose `note` matches
   `^\s*User#person\b` → **never principal** (mint B, by the note the runtime
   already writes into the dump — this catches a future `via_user` tag that
   happens to be spelled without an underscore);
4. otherwise `^SYM_PERSON_[A-Za-z0-9]+_id$` decides, exactly as before — the
   `symbolic_user(tag)` shape, one alphanumeric run tag (`PS`, `PO`, `CI`,
   `NI`, `CONV`).

Rules 2 and 3 are **independent vetoes**, either sufficient. Rule 3 is a veto
only, never evidence *for* principal-hood: the principal person's columns
usually never reach `symbolic_vars` at all (measured: `SYM_PERSON_PS_id` and
`SYM_PERSON_PO_id` appear only inside `$$()` binds in SELECT notes, never as a
declared var), so a missing note must mean "no information", not "not the
principal".

A `SYM_PERSON_*` bind that survives all four stays an unresolved `_<name>`
placeholder — **the same SQL the old code emitted** — and is now additionally
flagged **`non-principal-person-bind`** so it is enumerable and cannot ship
silently.

### The asymmetry, stated

Refusing to resolve costs precision; resolving wrongly costs **soundness in
the direction that hides a leak**. `posts.author_id = <my person>.id` is
strictly narrower than `posts.author_id = <any named person>.id`: a consumer
reading the policy would conclude the endpoint only ever reveals the viewer's
own posts. So when the mint site is not *known* to be the principal, the
resolver declines. That is the same asymmetry `_repair_rotation` uses —
unknown widens the candidate set, never narrows it.

### Where the rule still cannot decide (stated, not hidden)

`SYM_PERSON_via_user` is minted under **one fixed name for every `User` row it
is called on**, with nothing in the dump linking it to the producing query. On
this corpus that is harmless (there is exactly one such row per run, and its
producer — `User.find_by` — has no SQL note to join to anyway), but the name is
**genuinely ambiguous in principle**: two `.person` reads on two different
users would collide on one symbol. Resolving it properly means renaming the
mint at the runtime (`SYM_PERSON_via_<result_name>`), which is
`concolic_targets.rb` / `targets.rb` territory — **Rule T, the shared
boundary** — and was deliberately not done. Until then the bind stays a
placeholder and the 35 views carrying it are DECLARED OPEN, not shipped as
access control.

---

## 3. THE FIX

`src/queries_from_runs/transform.py`, minimal and confined:

* two new module-level constants next to `_PERSON_ID_RE` —
  `_PERSON_BIND_RE` (`^SYM_PERSON_`), `_NON_PRINCIPAL_PERSON_NAME_RE`
  (`^SYM_PERSON_via_user(?:_|$)`), `_NON_PRINCIPAL_PERSON_NOTE_RE`
  (`^\s*User#person\b`), with the mint-site documentation above them;
* `RunTransformer.var_notes` — `{var name: note}` from the run's declared
  `symbolic_vars`, built once per run (the field was already carried through
  `concolic_engine.run.SymbolicVar.note`; nothing new is dumped);
* `RunTransformer.is_principal_person` — the rule;
* `_Build._bind_value` — `_PERSON_ID_RE.match(bind)` becomes
  `self.rt.is_principal_person(bind)`, plus one new branch that sends every
  other `SYM_PERSON_*` to the placeholder path **with the flag** (the old code
  reached the identical placeholder path by falling through the producer loop,
  silently).

`_bind_column_type` is deliberately **untouched**: it still answers `integer`
for `SYM_PERSON_via_user_id`, via its `bind.endswith("_id")` tail rather than
via `_PERSON_ID_RE` — the same answer as before, so `_repair_rotation`'s
type-based un-rotation is bit-for-bit unaffected.

Also updated for accuracy: the module docstring and
`src/queries_from_runs/README.md` rule 1.

Not `src/`: `results3/queries_from_runs/_extract_people_stream_streaming.py`
gained an **X1 DECLARE check** next to the R1 check — a non-empty
`non-principal-person-bind` prints the views and says they must be declared
open, not shipped. (Only people_stream's extractor: it is the only corpus
where the flag can fire.)

**Not done, deliberately:** the runtime mint name (Rule T), and any attempt to
resolve `via_user` onto a fresh unconstrained `people` alias — that would
change shipped SQL on a not-yet-closed endpoint on the strength of a
heuristic, and belongs to the drive, not to an extractor fix.

---

## 4. TESTS — 47 passed (was 43)

`src/queries_from_runs/test_queries_from_runs.py`, four added:

| test | what it pins |
|---|---|
| `test_sym_person_via_user_does_not_resolve_to_the_principal` | the real people_stream note (post-un-rotation): `_SYM_PERSON_via_user_id` stays a placeholder, **no `_MY_UID`, no `people` join**, flag set |
| `test_sym_person_via_user_is_vetoed_without_a_declared_var_too` | the name-only veto — a run that declares no var still refuses |
| `test_non_principal_mint_note_vetoes_a_principal_SHAPED_name` | the rule is the **mint site**, not the underscore: `SYM_PERSON_viauser_id` — a name `_PERSON_ID_RE` **accepts** — with a `User#person` mint note must still not resolve |
| `test_principal_person_bind_still_resolves_to_the_my_person_join` | the control: `SYM_PERSON_PS_id` → `people.owner_id = _MY_UID`, **with and without** a declared mint note, no placeholder, no flag |

Unchanged and still passing: `test_pinned_person_id_becomes_my_person_join`,
`test_pinned_person_id_on_people_table_uses_owner_id`,
`test_unquoted_datetime_literal_parses_and_becomes_now` (the pre-existing
`SYM_PERSON_PH_id` → my-person-join assertion), and the whole rotation set.

**Ground-truth differential on the tests themselves** (DISCIPLINE: a check
must distinguish, not merely pass). The pre-X1 resolver was restored into a
scratch copy of the package and the same file run against it:

```
3 failed, 44 passed        # pre-X1
47 passed                  # post-X1
```

The three that fail pre-fix are exactly the three new negative tests; the
control (`..._still_resolves_to_the_my_person_join`) passes on both, which is
what makes "the accepted forms are unchanged" a measurement rather than a
claim. The load-bearing failure is the third:

```
E  assert '_SYM_PERSON_viauser_id' in
   'SELECT `posts`.* FROM `posts`, `people`
     WHERE `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID'
```

— i.e. **pre-fix, a `User#person` mint whose tag lacks an underscore silently
becomes the principal join.** That is the latent unsoundness the shape-only
regex was one character away from committing on the real corpus.

---

## 5. SIX-CORPUS DIFFERENTIAL — nothing changes anywhere

Same method as the rotation fix: old-vs-new resolver **in one process**, per
run, emitted-view (SQL text) lists compared. Both arms run under the same
`assoc_fold` + StringVal patches the extractors use — the swap is applied to
`assoc_fold._orig_bind_value`, the delegate `_patched_bind_value` tail-calls,
so the assoc fold itself is held constant and only the person rule moves.
`scratchpad/x1/six_corpus_diff.py` + `old_person.py`; 3 000 seeded random
dumps per corpus (`random.seed(20260910)`, random, never a sorted prefix),
people_stream in full.

**(a) Exhaustive, by construction.** The new resolver can only differ from the
old for a bind matching `^SYM_PERSON_`, and then only for a name that either
starts `SYM_PERSON_via_user` or carries a `User#person` mint note. The §1
grep over **all 320 746 dump files of all six corpora** (not sampled) settles
it corpus-wide:

* comments_index, conversations_index, people_show, notifications_index —
  **no `SYM_PERSON_*` name occurs at all**, so `_bind_value` cannot reach the
  changed branch: byte-identical output, proved, not sampled;
* posts_show — the only name is `SYM_PERSON_PO_id`, which both resolvers
  accept as the principal (no `via_user`, no `User#person` note anywhere in
  the corpus): identical;
* people_stream — `SYM_PERSON_PS_id` accepted by both; the 17
  `SYM_PERSON_via_user_*` names rejected by both, previously via the generic
  fall-through, now via the rule. **Same SQL, plus a flag.**

**(b) Empirical, sampled.**

```
comments_index         pop=  26528 sampled=  3000 runs=  3000 views=  47015  RUNS DIFFERING=     0  VIEWS DIFFERING=      0  new-flag views=0
conversations_index    pop=  18623 sampled=  3000 runs=  3000 views=  64871  RUNS DIFFERING=     0  VIEWS DIFFERING=      0  new-flag views=0
people_show            pop=  12997 sampled=  3000 runs=  3000 views=  78197  RUNS DIFFERING=     0  VIEWS DIFFERING=      0  new-flag views=0
notifications_index    pop= 173745 sampled=  3000 runs=  3000 views=  50837  RUNS DIFFERING=     0  VIEWS DIFFERING=      0  new-flag views=0
people_stream          pop=    755 sampled=   755 runs=   755 views=   9884  RUNS DIFFERING=     0  VIEWS DIFFERING=      0  new-flag views=2640
posts_show             pop=  96357 sampled=  3000 runs=  3000 views= 123498  RUNS DIFFERING=     0  VIEWS DIFFERING=      0  new-flag views=0
peak RSS 84 MB
```

(notifications_index's population reads 173 745 here vs the 165 486 counted
for §1's grep a few hours earlier — its owner is still adding dumps. The
sample is a seeded random draw from whatever was on disk at read time; §1's
exhaustive argument is what carries the claim, and it holds for any dump that
contains no `SYM_PERSON_*` name at all. Read-only throughout; nothing in that
directory was written.)

**No corpus's rendering changes — closed endpoints included.** Nothing to
re-extract anywhere; no shipped policy carried a person-bind error, so there
is **no shipped-policy finding to escalate to any endpoint owner**.
notifications_index's dumps were read read-only and its files were not
touched.

---

## 6. PEOPLE_STREAM — after-numbers

Full 755-dump extraction, `SKIP_SUBSUME=1`, 1 GB cap. This is a **DRY RUN** —
written to the scratchpad; `people_stream.sql` is not shipped, the endpoint is
not closed and subsumption has not run.

| | before (post-rotation, pre-X1) | **after** |
|---|---|---|
| dumps / runs loaded | 755 / 755 | 755 / 755 |
| raw → distinct → final views | 9 884 → 107 → 107 | 9 884 → 107 → **107** |
| **unparseable notes (E11)** | 0 | **0** |
| **R1 rotation residue** (`bind-rotation-UNRESOLVED`) | 0 | **0** |
| `bind-rotation-repaired` | 9 360 | 9 360 |
| **views changed** | — | **0 — statements byte-identical** |
| unresolved `_SYM_` placeholder families | 3 | **3** |
| `non-principal-person-bind` | — | 2 640 raw / **35 of 107** views |
| subsumption-eligible | 36 of 107 | 36 of 107 |

**Unresolved `_SYM_` placeholders remaining — the target of 0 is NOT met, and
should not be.** Counted as distinct SELECT statements of the 107:

| placeholder | views | what it is | why it stays |
|---|---:|---|---|
| `_SYM_PERSON_via_user_id` | **35** | the **viewed** person's id (`u.person.id` for `u = User.find_by_username(params[:username])`) | resolving it to the principal join would ship a narrower predicate than the app enforces; resolving it to its real producer needs a RUNTIME rename — one fixed mint name, no link to the producing query (**Rule T**) |
| `_SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id` | **35** | that `users` row's id | its producer's note is `"User query (class-level finder), args=args=nil"` — **not SQL**, so no producer and no table to join to. Separate defect, not X1 |
| `_SYM_RESULT_ActiveRecord__FinderMethods_find_by_2_author_id` | **1** | same shape | same reason |

71 of 107 views carry at least one placeholder. All 71 are DECLARED OPEN in
`people_stream/POLICY_HEADER.txt` X1 and the extractor now prints a DECLARE
block for the 35 person-bind ones. The headline statement still reads:

```sql
SELECT `posts`.* FROM `posts`
 WHERE `posts`.`author_id` = _SYM_PERSON_via_user_id   -- the person named in the URL
   AND `posts`.`created_at` < _NOW
   AND `posts`.`type` IN ('StatusMessage', 'Reshare');
```

— which is **semantically right and syntactically unenforceable**, and that is
the honest state of it.

---

## 7. WHAT WAS *NOT* DONE, DELIBERATELY

1. **The runtime mint name.** `UserSymPersonAssociation#person` mints
   `SYM_PERSON_via_user` for *any* `User` row. Two `.person` reads on two
   different users would alias onto one symbol. Harmless on this corpus (one
   such row per run) but wrong in principle. The repair is
   `SYM_PERSON_via_<result_name>` in `targets.rb` — **Rule T, the shared
   boundary**, which restarts every endpoint.
2. **Resolving `via_user` onto a fresh unconstrained `people` alias.** That
   would be the truthful generalisation under param-broadening
   (`posts.author_id = <any person>.id`) and is strictly *more* permissive, so
   it is sound in the safe direction — but it changes shipped SQL on a
   not-yet-closed endpoint on the strength of a heuristic (the dump does not
   say the symbol is a `Person`; only the mint site does), and it turns a
   flagged placeholder into a trivially-satisfiable join that would need
   subsumption re-run. That is a drive decision, not an extractor fix.
3. **The `find_by_1` producer.** A class-level finder's note is a description,
   not SQL, so the row it returned can never be joined to. Real, separate,
   and not X1.

---

## 8. FILES

```
src/queries_from_runs/transform.py                _bind_value + is_principal_person + var_notes
src/queries_from_runs/README.md                   rule 1 states the mint-site rule
src/queries_from_runs/test_queries_from_runs.py   +4 tests (47 passed, was 43)
results3/queries_from_runs/_extract_people_stream_streaming.py   X1 DECLARE check
results3/people_stream/POLICY_HEADER.txt          X1 entry corrected
results3/queries_from_runs/_EXTRACTION_OPEN_ISSUES.md            X1 section
results3/queries_from_runs/_X1_PERSON_ID_FIX_20260910.md         this file
```

Untouched, as required: `src/concolic_engine`, `src/ruby_runtime`, every
`concolic_targets.rb` / `targets.rb`, every notifications_index file, and the
quarantined reference policies.
