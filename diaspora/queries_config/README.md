# queries_config — diaspora's instance of the app-config contract

`src/queries_from_runs` is generic code. The app-specific input it needs —
the schema/DDL, the key and dependency fixtures, the principal and identity
conventions, the symbol names this app's `targets.rb` mints, the inflections,
the CLI directory defaults — lives **here**, on the driver side, and is passed
in by path. Contract: `src/queries_from_runs/app_config.py`.

Since 2026-09-11 (E12) this config drives **reconstruction**, not just the
subsumption harness: these values decide the SQL text of every shipped
policy. Treat an edit to `principal`, `schema` or `inflections` as a change to
the extractor — it needs the same corpus differential any transform.py change
needs — the harness is
`reports/diaspora/tools/extraction_differential/` and the write-up is
`results3/queries_from_runs/_E12_APP_AGNOSTIC_20260911.md` §3.3.

```
app.json               the config (see the contract for every key)
resources/
  diaspora-ddl.sql     DERIVED from the app's schema.rb  (make_resources.sh)
  pk.txt               DERIVED from the app's schema.rb  (make_resources.sh)
  fk.txt               hand-maintained (schema.rb carries no FK constraints)
  deps.sql             hand-maintained (app invariants as query containments)
  const-decls.txt      hand-maintained (`_MY_UID:int;`)
make_resources.sh      regenerates the two DERIVED files
validate_app_json.py   checks app.json against the app's schema.rb
check_subsumed.sh      wrapper: exports QFR_APP_CONFIG, execs the generic checker
```

## What the blocks mean

| block | decides |
|---|---|
| `schema.rails_schema_rb` | column types, which name suffixes are real columns |
| `schema.foreign_keys` (null ⇒ `subsume.foreign_keys`) | which columns reference the identity row |
| `principal.uid_const` / `now_const` | the constants rendered into every view (`_MY_UID`, `_NOW`) |
| `principal.principal_columns` | per-table principal column — `<table>.<col> = _MY_UID` selects the PRINCIPAL's rows of `<table>`. `people → owner_id` is the identity join's owner side; the whole map is also what `transform.principal_provenance` follows a value's recorded producing statement back to (2026-09-15), so an entry that does not mean "the principal's rows" would make the fold emit a predicate narrower than the app enforces |
| `principal.identity` | the identity table (`people`), its id/guid columns, the FK fallbacks, and the driver's PINNED values (`person.id = 1`, guid `abc123`) |
| `principal.binds` | which symbol names mean the principal (`SYM_USER_*_id`), the identity (`SYM_PERSON_*_id`), a NON-principal identity mint (`SYM_PERSON_via_user*`, note `User#person`), a request param (`SYM_PARAM_*`) |
| `inflections.irregular_plurals` | `person → people`, so a `person_id` request param matches `people.id` |
| `cli` | `dump.py`/`diff.py` directory defaults. `reference_dir` is **null on purpose**: the reference policies are QUARANTINED. |

The `principal.binds` values are the contract between this config and
`results3/<endpoint>/targets.rb`: they are the names that file mints. Rule T
applies — changing a mint name is a shared-boundary change, and the config
must move with it.

`fk.txt`, `deps.sql` and `const-decls.txt` are adapted from blockaid's own
`src/test/resources/DiasporaTest/` fixtures (fk/deps/const-decls verbatim); they
have no machine-readable source in the app, so they are not regenerated.

## Use

```sh
reports/diaspora/queries_config/check_subsumed.sh input.json
# or, for anything that calls the generic harness directly:
export QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json
```

The extractors (`results3/queries_from_runs/_extract_*_streaming.py`), the
`tools/blockaid_*.py` drivers and `results3/_experiment/variant_d/capped_checker.sh`
set `QFR_APP_CONFIG` themselves, so existing invocations keep working unchanged.

## Regenerating / validating

```sh
reports/diaspora/queries_config/make_resources.sh      # ddl + pk from schema.rb
reports/diaspora/queries_config/validate_app_json.py   # app.json vs schema.rb
```

`make_resources.sh` output is byte-identical to the pre-2026-09-11 checked-in
files for the current `ruby_examples/dse-apps/schemas/diaspora-schema.rb`
(50 tables). `validate_app_json.py` checks everything in `app.json` that
schema.rb can confirm: every principal/identity table and column exists, the
identity table has an owner column, every FK line names real columns, every
bind pattern compiles, every `cli` path exists. It cannot check the pinned
values or the symbol-name shapes — those are properties of `targets.rb`.

## Running src's tests against this app

```sh
QFR_APP_CONFIG=$PWD/reports/diaspora/queries_config/app.json \
QFR_TEST_RUNNER_RB=$PWD/reports/diaspora/results/comments/run_dse.rb \
QFR_TEST_DUMP_DIR=$PWD/reports/diaspora/results/comments/comments_index \
PYTHONPATH=src venvs/queries_from_runs/bin/python3 -m pytest \
  src/queries_from_runs/test_queries_from_runs.py -q
```

The suite itself is app-free (two synthetic apps); these three variables turn
on the integration tests that want a real runner and a real corpus.
