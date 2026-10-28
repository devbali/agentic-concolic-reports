# `src/queries_from_runs/subsume` made app-agnostic (2026-09-11)

Standing rule: **nothing in `src/` may be diaspora-specific.** `subsume/` was.
It now takes the app as INPUT — an *app config* produced and passed in by the
driver side — and carries no schema, no table names, no fixture data.

Scope: `src/queries_from_runs/{app_config.py,subsume.py,README.md,
test_queries_from_runs.py}`, `src/queries_from_runs/subsume/*`, the new
`reports/diaspora/queries_config/`, and a one-line config hand-off in the
17 diaspora-side callers. `src/concolic_engine`, `src/ruby_runtime`, every
`concolic_targets.rb`/`targets.rb` and every endpoint directory untouched
(installed `.sql` read only, for the differential). Reference policies not
read, still quarantined. `src/` has its own git with pre-existing uncommitted
changes; this work is on top — nothing reverted, nothing committed.

---

## 1. Inventory — what was diaspora-specific in `subsume/`

| file:line (pre-change) | what it was | now |
|---|---|---|
| `gen_ddl.py:2,4` | docstring: "the diaspora schema", `diaspora-schema.rb` | generic; the config names the schema |
| `gen_ddl.py:15` | `SCHEMA_RB = /home/dev/project/ruby_examples/dse-apps/schemas/diaspora-schema.rb` | `schema.rails_schema_rb` |
| `gen_ddl.py:16` | `OUT = resources/diaspora-ddl.sql` | `subsume.ddl` |
| `gen_ddl.py:55` | DDL header naming `diaspora-schema.rb` | derived from the config's schema basename (byte-identical for diaspora) |
| `check_subsumed.sh:2` | "for the diaspora schema" | generic |
| `check_subsumed.sh:6` | `_MY_UID` / `_NOW` named as *the* principal binds | "the principal/now constants declared by the config's const-decls file" |
| `check_subsumed.sh:18` | blockaid jar path fixed to the vendored build | `subsume.blockaid_jar`, vendored build as fallback |
| `check_subsumed.sh:19,21` | z3 dir / `JAVA_HOME` fixed | `subsume.z3_dir` / `subsume.java_home`, same fallbacks |
| `SubsumeChecker.java:77` | class doc: "for the diaspora schema" | generic |
| `SubsumeChecker.java:94` | `SUBSUME_RESOURCE_DIR` default `/home/dev/project/src/queries_from_runs/subsume/resources` | **required**, no default; set from the config |
| `SubsumeChecker.java:127` | comment "the diaspora schema" | "the app schema" |
| `SubsumeChecker.java:130` | H2 URL `jdbc:h2:mem:diaspora_subsume` | `subsume.h2_db_name` |
| `SubsumeChecker.java:132` | `Paths.get(RESOURCE_DIR, "diaspora-ddl.sql")` | `SUBSUME_DDL_FILE` |
| `SubsumeChecker.java:152,156,168,170` | Calcite schema literal `'diaspora'` (×3 + error text) | `subsume.sql_schema_name` |
| `SubsumeChecker.java:187-190` | `pk.txt`/`fk.txt`/`deps.sql`/`const-decls.txt` basenames | `SUBSUME_{PK,FK,DEPS,CONST_DECLS}_FILE` |
| `SubsumeChecker.java:509` | comment example `` `posts`.`guid` = `posts0`.`id` `` | "a string column compared to an int column" |
| `resources/diaspora-ddl.sql` (491 lines) | diaspora DDL, 50 tables | **moved** to `reports/diaspora/queries_config/resources/` |
| `resources/pk.txt` (50) | diaspora tables, `id` pk | **moved** |
| `resources/fk.txt` (42) | diaspora FKs (`people.owner_id:users.id`, `share_visibilities.user_id:users.id`, …) | **moved** |
| `resources/deps.sql` (16) | diaspora invariants (`posts.type='Reshare'`, `aspect_memberships`, `share_visibilities.shareable_type='Post'`, …) | **moved** |
| `resources/const-decls.txt` (1) | `_MY_UID:int;` | **moved** |
| `README.md` | 53 diaspora hits: table names, schema path, blockaid `DiasporaTest` provenance | rewritten app-agnostically; two pointer lines + a labelled "run against the diaspora config" sanity section remain |

`src/queries_from_runs/subsume/resources/` **no longer exists**; a test asserts
that (`test_subsume_harness_carries_no_app_data`, which also greps every
`.py`/`.sh`/`.java` under `subsume/` for the app name).

## 2. The config boundary

**Contract** — `src/queries_from_runs/app_config.py` (module docstring is the
spec; `AppConfig`/`SubsumeConfig`/`PrincipalConfig` dataclasses are the parsed
form). One JSON file carries:

- `schema.rails_schema_rb` — the DDL source;
- `subsume.{resource_dir,ddl,primary_keys,foreign_keys,dependencies,const_decls}`
  — the schema/DDL and the fixture rows the checker's dependency model needs;
- `subsume.{sql_schema_name,h2_db_name}` — the solver-side schema identifiers;
- `subsume.{blockaid_jar,z3_dir,java_home}` — the classpath/toolchain (null ⇒
  the harness's vendored defaults);
- `principal.{uid_const,now_const,principal_table,principal_columns}` — the
  principal bind names and the table→principal-column map;
- `conventions.{view_file_suffix,placeholder_prefix}` — view-key conventions.

Relative paths resolve against the config file's own directory, so a config
directory is self-contained and relocatable.

**How the default is resolved.** It is not. Per the owner's clarification,
`src/` never discovers or embeds an app: `check_subsumed.sh` and `gen_ddl.py`
REQUIRE `--app-config PATH` or `QFR_APP_CONFIG`, and with neither they exit 2
with

```
no app config given: pass --app-config PATH or set QFR_APP_CONFIG=PATH.
The config is app-specific input owned by the driver side (for the concolic
experiments: reports/<app>/queries_config/app.json); src/queries_from_runs
never guesses it.
Contract: src/queries_from_runs/app_config.py
```

`check_subsumed.sh` resolves the config once (`python3 ../app_config.py
--print-sh`) into `SUBSUME_*` exports and the JVM reads only those, so the
Java needs no JSON parsing and no config knowledge; `SUBSUME_RESOURCE_DIR` is
now required there too (it has no default).

**Backwards compatibility comes from the driver side, not from `src/`.** The
diaspora instance is `reports/diaspora/queries_config/`:

```
app.json                the config
resources/              the five fixtures (moved out of src/)
make_resources.sh       regenerates the DERIVED two from the app's schema.rb
check_subsumed.sh       wrapper: exports QFR_APP_CONFIG, execs the generic one
README.md
```

and every existing diaspora-side caller now supplies the path itself — one
added line, `os.environ.setdefault("QFR_APP_CONFIG", ".../queries_config/app.json")`:

- the six extractors `results3/queries_from_runs/_extract_*_streaming.py`
  (inserted right after `import subsume as subsume_mod`, so
  `prune_subsumed`/`DEFAULT_CHECKER` keep working unchanged);
- `tools/blockaid_{completion_compare,coverage,new_vs_old,way2_perview,
  way2_rewritten,way2_rewritten_subsets,way2_single,way2_v2}.py`,
  `tools/rewrite_probe.py`;
- `results3/queries_from_runs/_reference_comparison_20260908/{driver,probe}.py`;
- `results3/_experiment/variant_d/capped_checker.sh` — via
  `--setenv=QFR_APP_CONFIG=…`, because `systemd-run` does not inherit the
  caller's env (the same trap that bit `SUBSUME_TIMEOUT_MS` on 2026-08-20).

All files were rewritten atomically (`os.replace`) because other agents run
them concurrently. **Observed live:** during this work another agent's
invocation of the checker was caught mid-run with
`QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json`
and the full `SUBSUME_*` set resolved — i.e. a third-party call went through
the refactored path unchanged.

**What is derived vs hand-maintained.** `make_resources.sh` regenerates
`resources/diaspora-ddl.sql` and `resources/pk.txt` from
`ruby_examples/dse-apps/schemas/diaspora-schema.rb` (the generic
`gen_ddl.py --with-pk`). `fk.txt`, `deps.sql` and `const-decls.txt` stay
hand-maintained: Rails' `schema.rb` carries no FK constraints and no app
invariants, so they have no machine-readable source — they are the fixtures
adapted from blockaid's own `src/test/resources/DiasporaTest/`.

## 3. Proof of no behaviour change

### Byte-identical generated resources

Pre-refactor `gen_ddl.py` (reconstructed verbatim) reproduces the checked-in
`diaspora-ddl.sql` exactly; the refactored config-driven generator then
produces the same file **byte-for-byte** (50 tables), and `--with-pk`
reproduces `pk.txt` byte-for-byte (50 lines). The DDL header still reads
`-- Auto-generated by gen_ddl.py from diaspora-schema.rb.` because the header
is now derived from the config's schema basename.

### Verdict differential, old harness vs new

The pre-refactor `classes/` (built 2026-08-18) and the pre-move `resources/`
were snapshotted and run side by side with the refactored harness on identical
inputs, both caged
(`systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=3G
choom -n 1000`, `JAVA_TOOL_OPTIONS` unset).

**Sanity set** (the six queries the README documents), pairwise:

| | result |
|---|---|
| old | `{"subsumed":[[0,1],[2,1],[4,5]],"errors":{}}` |
| new | `{"subsumed":[[0,1],[2,1],[4,5]],"errors":{}}` |

identical, and identical to the README's recorded expectation.

**Three closed endpoints — RUN 2026-09-11.** Both arms SEQUENTIALLY (never two
JVMs at once), each under
`systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=3G choom -n 1000 --`,
`JAVA_TOOL_OPTIONS` unset, with `systemctl --user show concolic-cov.slice -p
MemoryCurrent` checked ≤ 4 GiB before every arm (the gate fired once, at
5.06 GiB, and aborted that arm rather than proceeding — it was re-run later).
`results3/posts_show/coverage_report.py` was running throughout at ~3.0 GB.

Old side = the pre-refactor `classes/` (built 2026-08-18) over the pre-move
`resources/`; new side = the refactored harness via
`reports/diaspora/queries_config/check_subsumed.sh`.

### Pairwise — the mode `prune_subsumed` actually uses

First 12 views of each installed policy, `SUBSUME_TIMEOUT_MS=3000`, 2 threads.
`subsumed` pairs and `errors` compared as sets.

| endpoint | views in policy | queries | pairs old / new | errors old / new | identical |
|---|---|---|---|---|---|
| `comments_index` | 61 | 12 | 0 / 0 | 0 / 0 | **yes** |
| `conversations_index` | 58 | 12 | 0 / 0 | 11 / 11 | **yes** |
| `people_show` | 59 | 12 | 0 / 0 | 12 / 12 | **yes** |

(0 pairs is the expected result: an installed policy has already been pruned,
so no surviving view subsumes another.)

### Coverage — full installed policy as the view set

Views = the whole policy; queries = 8 sampled views + 2 synthetic wide-row
negatives (`SELECT posts.*`, `SELECT users.*`); `SUBSUME_TIMEOUT_MS=30000`,
2 threads. `covered` compared element-wise, true/false/null distinct.

| endpoint | old true/false/null | new true/false/null | view_errors old / new | identical |
|---|---|---|---|---|
| `comments_index` | 9 / 1 / 0 | 9 / 1 / 0 | 0 / 0 | **yes** |
| `conversations_index` | 0 / 1 / 9 | 0 / 2 / 8 | 50 / 50 | no — see below |
| `people_show` | 0 / 1 / 9 | 0 / 2 / 8 | 42 / 42 | no — see below |

### The two non-identical cells are solver timing, not the refactor

Both disagreements are **one element**, and in both cases it is a *synthetic
wide-row negative I added to the sample* — never a policy view. The README
already documents these as MBQI-boundary cases ("`SELECT users.*` → false
(64 s of MBQI; `null` + timeout error at the default 15 s)"; wide-row cases
"can need ~60–90 s"). No verdict flipped between `true` and `false`; the change
is `null` (inconclusive) → `false` (a counterexample found), a *refinement*.

Three arms pin this down (people_show, same input each time):

- **ARM A — the OLD harness against itself, 30 s, twice:** both runs gave
  `[…, False, False]` (24 s, 26 s) — i.e. the old harness now returns
  **false:2 / null:8**, the very tally the "new" side produced in the
  differential, while in the differential the same old harness returned
  **false:1 / null:9**. *The old harness disagrees with itself run to run.*
- **ARM B — old vs new at 120 s:** old returned `[…, False, None]` after 123 s;
  new returned `[…, False, False]` in 37 s. The old side did *worse* at 120 s
  than it had at 30 s in ARM A — z3's MBQI search on these quantified formulas
  is not reproducible under load.
- **ARM C — old vs new at 30 s over the REAL policy views only** (queries =
  `views[:8]`, no synthetic negatives), all three endpoints:

  | endpoint | covered (old = new) | view_errors old / new | errors old / new | identical |
  |---|---|---|---|---|
  | `conversations_index` | 8 × `null` | 50 / 50 | 0 / 0 | **yes** |
  | `people_show` | 8 × `null` | 42 / 42 | 0 / 0 | **yes** |
  | `comments_index` | 8 × `true` | 0 / 0 | 0 / 0 | **yes** |

  These resolve in 3–8 s, far inside the timeout, so they are deterministic —
  and they are **verdict-for-verdict identical, including the quarantined-view
  sets** (50 and 42 views land in `view_errors` on both sides, unchanged).

**Conclusion:** every deterministic verdict is identical old vs new — all
pairwise results on all three endpoints, and all coverage results over real
policy content. The only cells that moved are two synthetic negatives sitting
on the MBQI timeout boundary, demonstrably unstable *within a single harness*.
`null` was never folded into `false` anywhere in this comparison.

`prune_subsumed` itself is unchanged apart from its docstring: it is a pure
function of the `(pairs, errors)` the checker returns (`syntactic_subsumed_pairs`
+ `_drop_from_pairs`, no I/O of its own), so identical checker output means
identical pruning. Its behaviour is additionally pinned by the eight existing
`prune_*` unit tests, all still passing.

### Tests

`src/queries_from_runs/test_queries_from_runs.py` — **78 passed, 3 skipped**
without a config; **79 passed, 2 skipped** with `QFR_APP_CONFIG` set. (The file
also grew from another agent's concurrent work during this task; the remaining
skips are its `QFR_TEST_RUNNER_RB` / `QFR_TEST_DUMP_DIR` environment-gated
tests, not mine.) Eleven tests added:

- config loader: requires an explicit path (message names `--app-config` and
  `QFR_APP_CONFIG`); reads the env var; explicit path beats env; relative
  paths resolve against the config's directory; absolute paths pass through;
  missing `subsume` key and missing sub-keys are rejected by name; a missing
  file names the path; `sh_exports` quotes values and omits null entries;
- generic pieces: `gen_ddl.py` driven by a config over a synthetic two-table
  `schema.rb` (type mapping, implicit `id` pk, `t.index` skipped, `--with-pk`
  output), and its no-config exit-2 message;
- the standing rule: no app name in any `.py`/`.sh`/`.java` under `subsume/`,
  and no `subsume/resources/` directory.

`test_blockaid_checker_live` now skips (rather than fails) when no config is
supplied — the harness is app-agnostic, so the app must come from the caller.

Raw results: `scratchpad/differential.{log,json}` (main), `stability.log`
(arms A/B), `armc.{log,json}` (arm C) under
`/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/`;
the drivers are `differential.py`, `stability.py`, `armc.py` beside them.

## 4. Still diaspora-specific in `src/` — inventoried, NOT moved

Recorded as **E12** in `_EXTRACTION_OPEN_ISSUES.md`. Summary: `schema.py`
(`DEFAULT_SCHEMA_RB`, `DEFAULT_FK_TXT` → blockaid's `DiasporaTest/fk.txt`,
`person_ref_columns` seeded with `("people","id")`), `transform.py`
(`MY_UID`/`NOW`, `_USER_ID_RE`/`_PERSON_ID_RE`, `_IRREGULAR_PLURALS`, the
`people.owner_id = _MY_UID` my-person join), `pcs.py` (`SYM_USER_<tag>_id` →
`_MY_UID`), `diff.py`/`dump.py` CLI defaults pointing at
`reports/diaspora/...` and the reference dir, and docstrings in
`__init__.py`/`plan.md`/`audits/`.

**This section is the brief for the follow-up agent picking up E12**, which is
to be held to the same differential discipline used here.

**Why not moved here:** they decide *reconstruction* output, not the
subsumption verdict. Parameterising them changes what views are emitted, so
each would need its own differential over the dump corpora (the standard the
X1 fix was held to — six corpora, 320 746 dumps). The config already
*declares* their replacements (`schema`, `principal`); no `src/` module reads
those blocks yet. **The principal-resolution conventions of
`_X1_PERSON_ID_FIX_20260910.md` are unchanged by this refactor.**

Outside `queries_from_runs`: `src/ruby_runtime/concolic_harness.rb`,
`src/ruby_runtime/completion_checker/*`, `src/end_to_end_completion_checker/*`
and `src/concolic_engine/assumptions.py` also name diaspora (harness paths,
`scripts/diaspora-concolic` invocations, measured-on-diaspora commentary).
Out of scope: `concolic_engine` and `ruby_runtime` were not to be touched.

## 5. Docs updated

- `src/queries_from_runs/README.md` — new "App config" section (contract, the
  required flag, where diaspora's instance lives, the unmoved items).
- `src/queries_from_runs/subsume/README.md` — app-agnostic throughout, with a
  four-step "Pointing at another app".
- `reports/diaspora/queries_config/README.md` — new; what is derived, what is
  hand-maintained, how to run.
- `reports/diaspora/docs/RUNBOOK.md` Phase 6 — one bullet: run the checker via
  the diaspora wrapper or export `QFR_APP_CONFIG`.
- `_EXTRACTION_OPEN_ISSUES.md` — E12.
