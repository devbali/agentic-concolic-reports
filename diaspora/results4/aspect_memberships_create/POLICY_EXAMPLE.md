# `policy_example.txt` — the policy IR from this corpus

**Date:** 2026-09-24
**Corpus:** all 10 dumps in this directory tree, regenerated clean on
2026-09-24 —
`./dump_auth_json_dse0001..0006.json` (main set,
`MAX_RUNS=6 TIME_BUDGET=600 scripts/diaspora-concolic ./run_dse.rb`; 6 runs,
6 distinct paths, 0 run errors) and
`./write_path/dump_auth_json_dse0001..0004.json` (the seeded replay from
REPORT.md §2: the same runner with
`DUMP_OUT=./write_path EXTRA_SEEDS_JSON=./write_path_seeds.json SEEDS_ONLY=1`;
4 runs, 4 distinct paths, worklist drained).
**Runtime:** `src_new/runtimes/ruby_runtime`, with the 2026-09-24
`call_interceptor.rb` fixes in place (identity-based call/record pairing;
per-call scoping of the pending-note channel). Each dump carries 89
declarations: 48 `target_function`, 41 `shim`.
**Certificate:** none — no coverage/completion pass was run, so
`outcome=UNDECIDED` throughout. No completeness claim is made here.

> **Updated 2026-09-24, second pass.** `src_new` then made provenance
> required and the four `write_path/` dumps stopped building. They build
> again, and the ten still merge into one policy of the same 84 atoms — over
> **14** signatures now, not 15, because
> `ActiveRecord::Associations::SingularAssociation#writer` is no longer a
> declared target. Everything from "What it is" to "What changed since
> REPORT.md" describes the earlier build and is kept as written; the delta,
> the measurement behind it and the generic interceptor addition it points
> at are in *"2026-09-24, second pass: the provenance rule, and the
> interceptor gap"* below.

## What it is

`dumps_to_policy/README.md`'s "The one call", run for real:

```
Run.from_dict → build_policy(entrypoint="aspect_memberships_create")
              → normalize_detailed  (§6: merge, subsume, simplify)
              → print_policy
```

**All 10 dumps build, and all 10 merge into ONE policy.** 105 atoms before
merging (= the total number of target-function calls across the corpus, which
is §4.1.2's completeness invariant), 84 after `normalize_detailed`, over 15
signatures. (15 as of this pass; **14** after the second pass — see below.)

## This file used to be six separate policies — what was wrong, and what changed

**Until 2026-09-24 this corpus could not be merged into a single policy**, and
the earlier version of this document recorded that as a property of the
corpus. It was not. It was a **defect in `dumps_to_policy/build.py`**, now
fixed (with the project owner's go-ahead — see *Source-code discipline*
below). The refusal looked like this:

```
BuildError: aspect_memberships_create: two dumps declare different types for
the same value (list[opaque] and int) — §5.2: a declaration is a contract,
and unifying two is inventing a third.
```

### The mechanism

The "same value" was a **call variable `cN`**, assigned by
`dumps_to_policy.build._Names` as the *N-th target call within one run*. That
identity is canonical **within** a run and meaningless **across** runs: under
prefix-directed DSE an earlier branch flip changes how many calls precede a
point, so the N-th call of two runs is routinely two different calls of two
different targets. Measured on this corpus:

| | `c3` | `c7` | `c15` |
|---|---|---|---|
| `dse0001` | `FinderMethods#first` | `FinderMethods#find_by` | `Rendering#_set_rendered_content_type` |
| `dse0002` | `SingularAssociation#find_target` | `Querying#find_by_sql` | `Querying#find_by_sql` |
| `dse0004` | `Rendering#_set_rendered_content_type` | — | — |
| `write_path/dse0003` | `FinderMethods#first` | `FinderMethods#find_by` | `SingularAssociation#writer` |

`build_policy` nevertheless merged **every run's §5.4 type observations into
one corpus-wide table keyed by that positional identity**, and raised the
moment two entries at one key carried different declared types. So
`_set_rendered_content_type` returning `[opaque]` and `find_by_sql` returning
`int` — two unrelated calls that merely both sat at index 15 — read as one
value declared two ways. **22 such collisions across these 10 dumps**, which
is why the corpus fell into six groups.

### The fix

The observation keys that are **run-local** are now scoped per run before
merging. The distinction is structural and already in the IR — a term is
run-local exactly when `Term.refs()` is non-empty, i.e. when it reads a `cN`,
which covers `c3`, `c3.author_id`, `len(c3.rows)` and `-c3`. No name is
parsed.

What deliberately **still** agrees corpus-wide, and still raises on a genuine
disagreement:

* **entrypoint inputs** — `$SYM_PARAM_aspect_id` is *which argument of the
  entrypoint this is*, the same symbol in every run and not a position on any
  path. Merging its observations is exactly how a ten-run policy gets one
  `EntrySignature`; two dumps that declare it differently still raise.
* **everything keyed by target name** — a target's declared `kind`, its
  argument types, its declared return type. A target is the same target in
  every run.
* **§5.2's fixed-object attribute sets** (the `types` table), keyed by type
  name.

One consequence worth stating plainly: two dumps declaring a **different
return type for the same target** do *not* raise, and did not before either —
`build_policy` unions them (`unify`, "the IR saw two things and declares
nothing about which"), which is CHANGE 5's documented design and is untouched
here. This corpus exercises it: `ActiveRecord::FinderMethods#exists?` is
declared `bool` by some dumps and `opaque?` by others, and the merged policy
prints the union. The old `BuildError` fired on that case only by accident,
when the positions happened to line up.

### What merging bought

| | six groups (before) | one policy (after) |
|---|---|---|
| atoms before merging | 105 | 105 |
| atoms after `normalize_detailed` | 97 | **84** |
| signature blocks | 6 × partial | **1 × 15 signatures** |
| entry signature | 6, each partial | **1** |

The 97 → 84 drop is §6's merge and subsumption finally being allowed to see
the whole corpus at once; the per-target return types likewise widen to their
corpus-wide union (`FinderMethods#first` is `opaque?` here, `opaque` in what
group 5 alone could see).

### Regression tests

`dumps_to_policy/tests/test_relations.py::PositionalIdentityIsRunLocal` — six
tests: two that reproduce the false conflict (two runs whose `c1` is a
different target with a different declared type; the same through
`c1.<field>`) and fail without the fix, and four negative controls that must
keep raising or keep merging (a genuinely conflicting entrypoint input, the
same *through* a benign positional collision, a differing fixed-object
attribute set, and an entrypoint input whose type only one run declares still
reaching the merged `EntrySignature`).

## What the policy says

The signature block, now one for the whole corpus:

```
  sig ActiveRecord::Associations::SingularAssociation#find_target() -> int target_function
  sig ActiveRecord::Associations::SingularAssociation#writer(splat_args: str) -> int shim
  sig ActiveRecord::Base#save() -> bool target_function
  sig ActiveRecord::Core::ClassMethods#find(ids: str) -> opaque target_function
  sig ActiveRecord::FinderMethods#devise_user_first() -> opaque target_function
  sig ActiveRecord::FinderMethods#exists?() -> opaque? target_function
  sig ActiveRecord::FinderMethods#find_by() -> opaque? target_function
  sig ActiveRecord::FinderMethods#first() -> opaque? target_function
  sig ActiveRecord::Querying#find_by_sql(sql: str, binds: opaque, preparable: bool) -> int target_function
  sig ActiveRecord::Relation#update_all() -> int target_function
  sig Diaspora::Federation::Dispatcher.defer_dispatch(sender: str, object: str) -> opaque? shim
  sig User#blocks() -> int shim
```

(Three more signatures now appear that no single group's block carried:
`ActionController::Metal#status=`, `ActionController::Rendering#_set_rendered_content_type`
and `ActiveRecord::Base#save!` — 15 in total.)

**This is an insert endpoint, and the write is in the IR.** The `write_path/`
atoms carry real DML as access notes, with genuine producer→consumer binds:

```
access c12 = ActiveRecord::Base#save()
  // INSERT INTO "contacts" ("user_id", "person_id", "sharing", "receiving")
  //   VALUES ($$(SYM_RESULT_…devise_user_first_1_id),
  //           $$(SYM_RESULT_…ClassMethods_find_1_id), 'f', true)

access c__ = ActiveRecord::Base#save()
  // INSERT INTO "aspect_memberships" ("aspect_id", "contact_id")
  //   VALUES ($$(SYM_RESULT_…FinderMethods_first_1_id),
  //           $$(SYM_RESULT_…FinderMethods_find_by_1_id))

  // UPDATE "contacts" SET "contacts"."receiving" = true
  //   WHERE "contacts"."id" = $$(…)
  // UPDATE "notifications" SET "notifications"."unread" = false
  //   WHERE "notifications"."type" IN ('Notifications::StartedSharing') AND …
```

Both entrypoint parameters reach SQL as binds (`$$(SYM_PARAM_aspect_id)`,
`$$(SYM_PARAM_person_id)`).

**The write is still not in the main 6-run set**, exactly as REPORT.md §2
predicted: that is defect **D8** (cross-rep id collision forecloses
`record_a == record_b`, so `not_contact_for_self` fires by default), and the
two runtime fixes applied on 2026-09-24 do not touch it. The `write_path/`
seeded replay is what carries the INSERT, and it does.

## What changed since REPORT.md

REPORT.md lists nine defects. Two are now closed in `src_new`:

* **D9 — a raising finder's pending note lands on the next target call.**
  **FIXED.** The channel (`Thread.current[:concolic_pending_note]`) was only
  ever cleared by `CallInterceptor.extract_note`, which a mock that *raises*
  never reaches; `run` did not clear it between runs either. Each target call
  now runs with an empty channel and restores its caller's on the way out, so
  a note can only be read by the call that wrote it. The measured witness was
  in `../comments_index` (`dump_anon_json_dse0020.json` / `…0038.json`, a
  finder event carrying the webfinger wall's description).
* **A tenth defect, not in REPORT.md's list, also closed:** the dump
  assembler paired calls to symbolic-call records **by position**, which is
  wrong whenever a mock calls another declared target — and wrong by one for
  every call after a target that *raised*. This endpoint has raising targets,
  so its dumps were affected even though none of them was refused outright.
  Records now carry the identity of the call that published them.

D1–D8 are unchanged and remain reported-with-batch-local-workarounds only.
The `cN` cross-run collision was a new, eleventh finding — in
`dumps_to_policy`, not the runtime — and it is **now fixed**, as described
above.

## 2026-09-24, second pass: the provenance rule, and the interceptor gap

Everything above describes the build as it stood earlier on 2026-09-24. Later
the same day `src_new` made **provenance required**, and this corpus had to
be regenerated. The counts did not move — 105 atoms unmerged, **84** after
`normalize_detailed` — but the corpus went from "all 10 build" to "the four
`write_path/` dumps are refused" and back again, and the way back is worth
recording because it is a real limit of the IR, not a mock bug.

### What the new rule is

`concolic/model/origin.py` + `concolic/model/provenance.py`: a symbol says
where it came from as a **relation**, not by its spelling —

```
{"name": "<any identifier>", "type": "int",
 "origin": {"kind": "attr", "of": "<parent symbol>", "name": "author_id"}}
```

and R2 makes it bite: a `symbolic_call` whose declared `result_type` is
structured (`obj<…>`, a typed list) **must** have its parts declared as
relations to the symbol minted for that call. The interceptor emits them
itself (`CallInterceptor.declare_result_structure`), by walking the returned
value's own structure — no identifier is read anywhere in that walk.

### How the write path broke

```
BuildError: run 'auth_json_dse0001': events[32]
(ActiveRecord::Associations::SingularAssociation#writer) returns obj<?> as
'SYM_RESULT_ActiveRecord__Associations__SingularAssociation_writer_1', and
NOT ONE symbol in this run declares itself an attribute of it.
```

All four `write_path/` dumps, standalone and combined. The main six were
unaffected: they never write, so they never reach the association writer.

The mock at fault is `./targets.rb` §7, which exists for a measured reason
(defect **D4**): AR attaches the join row's aspect through the *association*
(`has_many_through_association.rb:61`), so `aspect_memberships.aspect_id` is
written **only** by the belongs_to writer deriving it from the record, and
with the shared W1 no-op in force the endpoint's defining INSERT came out as
`INSERT INTO "aspect_memberships" ("contact_id")` — a Class-S mis-shape.

But that mock is an **identity**: it writes the foreign key and then returns
the object it was handed. Nothing is produced. So the walk finds a value
whose attribute symbols already carry an origin — they are attributes of the
symbol the aspect was *built* under, `SYM_RESULT_…FinderMethods_first_1` —
and `declare_result_structure` correctly leaves them alone ("first producer
wins"). What is left is a freshly minted `obj<?>` symbol that nothing in the
run can ever declare a part of, because the parts are not its parts.

**The rule is right and the refusal is correct.** Measured across all four
dumps, that minted symbol occurs exactly twice each — as
`events[N].result_name` and as its own `symbolic_results` entry — and
nowhere else: no path condition, no later argument, no note. Ruby says why
it must be so: `obj.assoc = v` evaluates to `v` whatever the writer returns,
and AR's own caller (`assign_attributes` → `_assign_attribute` →
`public_send("#{k}=", v)`) discards it. The run never looks inside this
return value; the aspect fields it *does* read, it reads off the aspect's
own symbol, where they have real, checked origins.

### The interceptor gap

The honest statement about this call is **"it returned the value that symbol
already names"**, and the IR cannot make it. Checked, not assumed:

* `origin`'s kind set is closed — `attr`, `elem`, `result`, `input`
  (`ORIGIN_KINDS`). `result` names a *producing event*; none of the four says
  *this symbol is that symbol*.
* `declare_target` has no pass-through or alias form. Its only `returns:`
  convention is `[value, sort]` (guarded by `SORT_NAME_SET`), and
  `result_name` is minted by `SymbolicFunc.result_name_for` **before** the
  mock runs, unconditionally. `DumpTerm.term_of` spells a `{"sym": …}`
  reference only for a `SymbolicVar`, so a symbolic *model instance* handed
  back by a mock falls through to its concrete value and the identity is
  lost even from `result_value`.
* Re-declaring the record's attributes under the new result name is not
  available either: `SymbolicFunc.declare_var` raises `TypeConflict` — "an
  origin is a fact about where the value came from, and it has exactly one
  answer".

**Recommended generic fix, NOT applied** (`src_new` is separately owned and
the standing rule is to ask first). Two small, name-free additions that
together let a runtime say "this call returned an existing value":

1. `runtimes/*/term.*` — `term_of` should consult the same
   `symbol_name_of(value)` the interceptor already uses for the structure
   walk (it reads `sym_name` **and** `concolic_name`), not `sym_name` on
   `SymbolicVar` alone. Then a pass-through's `result_value` is recorded as
   `{"sym": "<the existing symbol>"}` — a true fact the dump currently
   throws away, and one that costs nothing where it does not apply.
2. `concolic/model/provenance.py` — R2 should be discharged when the event's
   recorded `result_value` **is** a symbol reference whose own parts are
   declared. That is not a loophole: it is the one case where the result has
   no parts of its own *because it is not a new value*, and (1) makes the
   claim checkable rather than inferred from spelling.

Everything else stays as it is; no new `origin` kind, no change to
`result_name` minting, nothing endpoint-specific.

### What was done instead, and what it cost

`./targets.rb` §7 now **`prepend`s** `AmSingularAssociationWriterFk` instead
of declaring a target. Its `writer(record)` carries the identical
foreign-key body as ordinary application code and deliberately does not call
`super` (the real `replace_keys` is the `SymbolicInt#to_i` wall W1 was built
for). A target declaration is configuration, and this one was declaring an
interception of a method that produces nothing — so removing it removes a
fabricated symbol rather than hiding one.

A structural diff of old-vs-new dumps shows **only a removal**: the writer's
two events per run (`call` + `symbolic_call`) are gone and nothing else
changed — same paths, same path conditions, same SQL, same binds.
48 → 46 events on `write_path/dse0001`, 62 → 60 on `dse0003`, 18 → 17
symbolic results. The regeneration itself reported `run errors: {}`, 4 runs,
4 distinct paths, worklist drained.

It also retires the **re-declaration arg-name defect** (REPORT.md, §7's own
comment): a prepended `writer(record)` is a real method with a real
parameter, so `record` is the Aspect and never `nil` —
`args["record"] || args["splat_args"]` is gone.

The shared wall **W1** in `./concolic_targets.rb` still declares
`SingularAssociation#writer`, and is left untouched on purpose. It is inert:
`declare_target` installs its wrapper with `klass.define_method`, i.e. on the
class, and a prepended module sits ahead of the class in the ancestor chain,
so the wrapper is never entered. The declaration therefore still appears in
each dump's `target … = shim` list and no `#writer` event appears in any of
the ten dumps.

### The corpus after the fix

| | before the provenance rule | now |
|---|---|---|
| dumps that build | 10 | **10** |
| `write_path/` standalone | 4 ok | **4 ok** (51 atoms, 13 signatures) |
| combined policy | 1 | **1** |
| atoms (unmerged → normalized) | 105 → 84 | **105 → 84** |
| signature blocks | 15 signatures | **14** — only `SingularAssociation#writer` dropped |
| `minimal` | full | **full** (`solver_used=True`) |

The endpoint's defining statement survives the fix intact, in
`write_path/dse0003` and `dse0004` and in the printed policy (atom 47):

```
access c15 = ActiveRecord::Base#save!()
  // "INSERT INTO \"aspect_memberships\" (\"aspect_id\", \"contact_id\")
  //   VALUES ($$(SYM_RESULT_ActiveRecord__FinderMethods_first_1_id),
  //           $$(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_id))"
```

with the same atom carrying
`c2 = ActiveRecord::Core::ClassMethods#find($SYM_PARAM_person_id)` and
`c3 = ActiveRecord::FinderMethods#first()  // "… "aspects"."id" =
$$(SYM_PARAM_aspect_id) …"` — so both entrypoint parameters reach the INSERT
as genuine binds, `aspect_id` through `c3`'s id and `contact_id` through the
contact found from `person_id`.

The current signature block (14, replacing the 15 quoted earlier in this
file; the return types also read `opaque` where the earlier quote read `int`,
which is change 5's total `result_type_of` landing, not a loss):

```
  sig ActionController::Metal#status=(arg: int) -> opaque? shim
  sig ActionController::Rendering#_set_rendered_content_type(format: str) -> [opaque] shim
  sig ActiveRecord::Associations::SingularAssociation#find_target() -> opaque target_function
  sig ActiveRecord::Base#save() -> opaque target_function
  sig ActiveRecord::Base#save!() -> opaque target_function
  sig ActiveRecord::Core::ClassMethods#find(ids: str) -> opaque target_function
  sig ActiveRecord::FinderMethods#devise_user_first() -> opaque target_function
  sig ActiveRecord::FinderMethods#exists?() -> opaque? target_function
  sig ActiveRecord::FinderMethods#find_by() -> opaque? target_function
  sig ActiveRecord::FinderMethods#first() -> opaque? target_function
  sig ActiveRecord::Querying#find_by_sql(sql: str, binds: opaque, preparable: bool) -> [opaque] target_function
  sig ActiveRecord::Relation#update_all() -> opaque target_function
  sig Diaspora::Federation::Dispatcher.defer_dispatch(sender: str, object: str) -> opaque? shim
  sig User#blocks() -> opaque shim
```

## Source-code discipline

**Nothing under `src_new/` was changed in the second pass.** The writer
fix is entirely batch-local (`./targets.rb`), and the generic interceptor
addition it points at is written down above and left unapplied for review.

One change was made under `src_new/dumps_to_policy/`, with the project
owner's go-ahead obtained beforehand: `build.py`'s corpus-wide type table now
scopes run-local (`cN`-reading) observation keys per run. Full suite before:
252 passed, 5 subtests. After: **258 passed, 5 subtests** — zero regressions,
+6 new tests. `dumps_to_policy/examples/` regenerates byte-identical
(`tests/regenerate_examples.py --check`), and
`../comments_index/policy_example.txt` rebuilds byte-identical, so neither
fixture was reached by the bug or by the fix.

## Printer gaps worked around in the driver only

Three cosmetic **printer** gaps remain, and are still monkeypatched at
runtime by the build script rather than fixed under `dumps_to_policy/`:

1. `print_policy` cannot print a certificate-free policy (falls back to a
   default `Certificate()` with `atoms=0`, then fails its own
   `check_atoms`) — a blank certificate is attached and its atom count
   re-stated after normalization.
2. `_QNAME` rejects a trailing `=`, so a setter target cannot be printed.
3. `print_term` has no §10.2 spelling for a **list literal**, which this
   corpus needs: a mock recorded an Arel bind array as an argument. Spelled
   locally as `[a, b, c]`. This one is new — `comments_index` does not hit it.

## Reproducing it

The build driver lives in `reports/diaspora/tools/`. It is now the ordinary
single-policy driver, `build_policy_example.py` (the same one
`comments_index` uses), with a `--header` for this file's preamble;
`build_policy_example_grouped.py` is no longer needed for this corpus and is
kept only for a corpus `build_policy` genuinely refuses:

```
cd /home/dev/project/src_new
/home/dev/project/venvs/queries_from_runs/bin/python3 \
  ../reports/diaspora/tools/build_policy_example.py \
  --header ../reports/diaspora/tools/aspect_memberships_create_policy_header.txt \
  aspect_memberships_create \
  ../reports/diaspora/results4/aspect_memberships_create/policy_example.txt \
  ../reports/diaspora/results4/aspect_memberships_create \
  ../reports/diaspora/results4/aspect_memberships_create/write_path
```

## Files

* `policy_example.txt` — the one printed policy described above (84 atoms).
* `dump_examples/` — six representative main-set dumps with a per-file
  README, plus `dump_examples/write_path/`: **all four** write-path dumps
  as JSON and in §10.3 text form (`print_run`; each checked with
  `parse_run(print_run(to_text_domain(r))) == to_text_domain(r)`), with
  their own README naming the dump that carries the INSERT.
* `REPORT.md` — the batch report (defects D1–D9, mock ledger, open items).
* `POLICY_EXAMPLE.md` — this file.


## Regenerated 2026-09-25 (second pass, IR validation)

The corpus under `..` and `../write_path` was regenerated after
`../targets.rb` grew §R (rows declare their fixed type) and §10
(`find_by_sql`'s note renders its binds instead of the prepared-statement
template, closing `REPORT.md` §5 open item 5). Metadata only: main set 6
runs / 6 distinct paths / 0 errors, write path 4 / 4 / 0, every dump's
path-condition count unchanged. The rebuilt policy is 84 atoms / 14
signatures / 1669 lines, and the `?` right-hand side is gone from every
note:

```
access c7 = ActiveRecord::Querying#find_by_sql("SELECT \"blocks\".* … = ?", […], true)
  // ~SELECT "blocks".* FROM "blocks" WHERE "blocks"."user_id" = $$(c1.id)
```

Incidental fix: this file previously documented a `--header` that the
committed `policy_example.txt` had not been built with. It is now built
with it, as documented above. See `REPORT.md` §7.
