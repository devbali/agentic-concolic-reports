# `dump_examples/write_path/` — the seeded replay, regenerated 2026-09-24

All **four** `write_path/` dumps, as JSON and in §10.3 text form
(`concolic/model/syntax.py`). These are the runs that actually issue the
endpoint's DML; the main set (`../`, six dumps) is read-only up to the
409/404 terminals.

Regenerated with:

```
DUMP_OUT=<batchdir>/write_path \
EXTRA_SEEDS_JSON=<batchdir>/write_path_seeds.json \
SEEDS_ONLY=1 MAX_RUNS=6 TIME_BUDGET=600 \
scripts/diaspora-concolic <batchdir>/run_dse.rb
```

`run errors: {}`, 4 runs, 4 distinct paths, worklist drained, 5.1 s.
(`DUMP_OUT` is not optional: without it the seeded replay overwrites the
main set's identically-named dumps in the parent directory.)

## Which dump carries which statement

| file | events / calls | DML it carries |
|---|---|---|
| `dump_auth_json_dse0001.json` | 46 / 17 | `INSERT INTO "contacts" ("user_id", "person_id", "sharing", "receiving")`, then `UPDATE "notifications" SET "unread" = false`. The **contact-missing** arm: the join row is not written by this path. |
| `dump_auth_json_dse0002.json` | 46 / 17 | Same two statements, reached on a different path (a distinct flip earlier in the run). |
| **`dump_auth_json_dse0003.json`** | **60 / 22** | **`INSERT INTO "aspect_memberships" ("aspect_id", "contact_id") VALUES ($$(SYM_RESULT_ActiveRecord__FinderMethods_first_1_id), $$(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_id))`** — the endpoint's defining statement — then `UPDATE "contacts" SET "receiving" = true` and the notifications `UPDATE`. The **existing-contact** arm. |
| **`dump_auth_json_dse0004.json`** | **60 / 22** | The same three statements on the sibling path. |

So the `aspect_memberships` INSERT lives in **dse0003 and dse0004**, and both
of its columns are bound to real symbols: `aspect_id` to the id of the aspect
the endpoint looked up (`c3` in `../policy_example.txt`, itself bound to
`$$(SYM_PARAM_aspect_id)`), `contact_id` to the contact's. Both entrypoint
parameters therefore reach SQL as genuine `$$(…)` binds.

(The table in `../README.md` previously credited `write_path/dse0001` with
the join-row INSERT. Measured against the dumps, it does not carry one; that
row has been corrected.)

## What changed in this regeneration

Only one thing, and it is a **removal**:
`ActiveRecord::Associations::SingularAssociation#writer` **is no longer a
declared target**. A structural diff of old-vs-new dumps shows the two
events it produced per run (`call` + `symbolic_call`) gone and *nothing else
altered* — same paths, same path conditions, same SQL, same binds; 48→46
events on dse0001, 62→60 on dse0003, 18→17 symbolic results.

Why: the mock was an identity — it writes the belongs_to foreign key (D4;
without it the INSERT loses `aspect_id`) and returns **its own argument**.
Under `src_new`'s now-required provenance (`concolic/model/provenance.py`
R2) the interceptor minted a fresh `obj<?>` result symbol for a value
another event had produced, and no symbol could ever declare itself an
attribute of it, so `build_policy` refused all four dumps. The foreign-key
write now happens in a prepended module (`../targets.rb`'s
`AmSingularAssociationWriterFk`), i.e. as ordinary application code, so the
effect is identical and the un-declarable symbol is gone. Full reasoning:
`../targets.rb` §7 and `../POLICY_EXAMPLE.md`, "The interceptor gap".

The `target … #writer = shim` line still appears in each dump's declaration
list: the shared wall W1 in `../concolic_targets.rb` still declares it. The
declaration is inert — a prepended module sits ahead of the class in the
ancestor chain, so the `declare_target` wrapper is never entered — and it is
left untouched on purpose.

## Round-trip

Each `.run.txt` was produced by `print_run(to_text_domain(run))` and checked
with `parse_run(print_run(to_text_domain(r))) == to_text_domain(r)`: **OK for
all four** (356, 356, 441, 441 lines).
