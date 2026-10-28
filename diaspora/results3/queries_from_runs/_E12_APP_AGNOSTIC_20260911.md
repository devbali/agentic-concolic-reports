# E12 — the REST of `src/queries_from_runs` made app-agnostic (2026-09-11)

Standing rule: **nothing in `src/` may be diaspora-specific; app-specific
inputs are PROVIDED BY THE DRIVER SIDE as an explicit input, never discovered
or embedded by `src/`.** Tonight's earlier work did that for `subsume/`
(`_SUBSUME_APP_AGNOSTIC_20260911.md`). This does it for everything else:
`schema.py`, `transform.py`, `pcs.py`, `diff.py`, `dump.py`, `__init__.py`,
`audits/*.py`, `plan.md`, `README.md`.

**Why this one is harder than `subsume`.** These values decide
RECONSTRUCTION — the SQL text of every shipped policy — not a subsumption
verdict. So the bar is the one `_X1_PERSON_ID_FIX_20260910.md` and
`_ROTATION_FIX_20260910.md` were held to: re-render old vs new over all six
corpora and show nothing moves.

**Result: nothing moves.** Every resolved value is identical to the constant
it replaced (§3.1, a direct old-vs-new comparison of all 18), and the
six-corpus differential is **0 RUNS DIFFERING / 0 VIEWS DIFFERING everywhere**
(§3.3). No closed endpoint's rendering changes; there is **no shipped-policy
finding to escalate**. The principal-resolution conventions of X1 (mint-site
veto ahead of an unchanged shape regex) are unchanged in behaviour — they are
now *stated by the config* instead of hardcoded, and a new test pins that the
veto still fires (§4).

Scope: `src/queries_from_runs/*` (not `subsume/`, done earlier; not
`blockaid/`, vendored), `reports/diaspora/queries_config/`, and a one-line
config hand-off in 24 driver-side callers. `src/concolic_engine`,
`src/ruby_runtime` and every `targets.rb` untouched; dumps read READ-ONLY,
policies not read at all. **Endpoint directories are NOT fully untouched** —
twelve `*audits*.sh` chains inside them got a one-line config export, because
two audits they run now require it; see §8. Reference policies not read,
still QUARANTINED. `src/` has its own git with pre-existing uncommitted
changes; this work is on top — nothing reverted, nothing committed.

Python only. No JRuby, no driving, no coverage pass — with one exception,
an accidental 2-minute blockaid start that was killed and produced nothing
(§8, recorded rather than glossed). Every heavy job caged
`systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=1G
choom -n 1000`; observed RSS of a differential arm **43 MB** against the 1 GB cap.

---

## 1. Inventory — what was app-specific, and where it went

E12's own table, with the disposition of each row.

| file:line (pre-change) | what it was | now |
|---|---|---|
| `schema.py:1-3` | docstring "Diaspora schema knowledge", names `diaspora-schema.rb` | generic; the config names the schema |
| `schema.py:28` | `DEFAULT_SCHEMA_RB = ruby_examples/dse-apps/schemas/diaspora-schema.rb` | `schema.rails_schema_rb`; `load_schema(path=None)` resolves it |
| `schema.py:31` | `DEFAULT_FK_TXT = blockaid/…/DiasporaTest/fk.txt` | `schema.foreign_keys`, defaulting to `subsume.foreign_keys` |
| `schema.py:83-86` | `person_ref_columns` seeded `("people","id")`, fallbacks `person_id`/`author_id` | `identity_ref_columns`, seeded from `principal.identity.{table,id_column}`, fallbacks from `identity.ref_fallback_columns` (old name kept as an alias) |
| `transform.py:78-79` | `MY_UID = "_MY_UID"`, `NOW = "_NOW"` | `principal.uid_const` / `now_const` → `RunTransformer.uid_const` / `.now_const`. The module names survive as **deprecated aliases of the contract defaults** so driver-side importers (`_blockaid_fold.py`) keep working |
| `transform.py:80-81` | `PINNED_PERSON_ID = 1`, `PINNED_USER_GUID = "abc123"` (not in E12's list; same class) | `principal.identity.pinned_id` / `pinned_owner_guid` |
| `transform.py:51,57,58` | `_USER_ID_RE`, `_PERSON_ID_RE`, `_PERSON_BIND_RE` | `principal.binds.{uid,identity_id,identity_prefix}` |
| `transform.py:71-72` | `_NON_PRINCIPAL_PERSON_NAME_RE` (`SYM_PERSON_via_user`), `_NON_PRINCIPAL_PERSON_NOTE_RE` (`User#person`) | `principal.binds.non_principal_identity_{name,note}` |
| `transform.py:76` | `_PARAM_BIND_RE` | `principal.binds.request_param` |
| `transform.py:83` | `_IRREGULAR_PLURALS = {"person": "people"}` | `inflections.irregular_plurals` |
| `transform.py:738-745` | `ensure_myperson`: `FROM people … WHERE owner_id = _MY_UID` | `identity.table` + `principal_columns[identity.table]` + `uid_const`; returns `None` (join refused) when the config declares no identity |
| `transform.py:901-913` | pinned-value rewrites hardcoding `people`/`owner_id`/`guid`/`1`/`abc123` | all five from `principal.identity` |
| `transform.py:382-383` | `schema_path`/`fk_path` defaults from `schema_mod` | `RunTransformer(app_config=…)`; both overridable, neither defaulted |
| `pcs.py:13,50,84,110` | `SYM_USER_<tag>_id` → `_MY_UID` | `parse_pc(..., uid_pattern=…)` / `collect_atoms(..., uid_pattern=…)`, passed by `transform.py` from `principal.binds.uid`; `MyUid` is rendered by the caller as `uid_const` |
| `diff.py:4,21-23,516-519` | `--reference`/`--ours`/`--out` defaulting into `reports/diaspora/…` and the reference dir | no defaults; `cli.reference_dir`/`ours_dir`/`diff_out`, else **exit 2** naming the flags |
| `dump.py:5,16-17,254` | `--results` defaulting to `reports/diaspora/results` | no default; `cli.results_dir`/`queries_out`, else **exit 2** |
| `__init__.py:6-9` | docstring naming the diaspora reference dir | generic + a pointer to the contract |
| `audits/pc_visibility_audit.py:12` | `--gate diaspora_handle,type` example | `--gate <handle-column>,type` |
| `audits/skipped_pcs_audit.py:18` | `reports/diaspora/results3/_experiment/variant_d` example | `reports/<app>/.../variant_d` |
| `audits/bind_resolution_audit.py:41-50` | imported the removed regexes in a bare `try/except` | `principal.binds`, config error named in its RED (§5) |
| `audits/identity_symbolicity_audit.py:29,40` | `users.id` + `user_id,owner_id,recipient_id` as THE principal | `principal.principal_table` + `principal_columns`, or `--principal-cols` (§5) |
| `plan.md:6,8,29`, `README.md` (11 hits) | prose naming diaspora paths | rewritten |

`grep -ri diaspora src/queries_from_runs --include='*.py'` now returns **one
line**: the rule test's own pattern (§4).

## 2. The contract additions

`src/queries_from_runs/app_config.py`'s module docstring is the spec. New
blocks, all optional, all defaulting to "this app has no such thing" rather
than to any app's value:

```
schema.foreign_keys                     FK listing for reconstruction (null => subsume.foreign_keys)

principal.identity.table                the principal's IDENTITY ROW table
principal.identity.id_column            its primary key
principal.identity.guid_column          an alternate unique key, or null
principal.identity.ref_fallback_columns columns ASSUMED to reference it when no FK listing is readable
principal.identity.pinned_id            the concrete id the driver pins the principal's identity row to
principal.identity.pinned_owner_guid    the concrete guid it pins
                                        (owner column = principal_columns[identity.table]; not duplicated)

principal.binds.uid                     regex: the principal-uid symbol
principal.binds.request_param           regex: a symbolic request param
principal.binds.identity_id             regex: an identity-row id symbol
principal.binds.identity_prefix         regex: the identity symbol family
principal.binds.non_principal_identity_name   VETO regex on the symbol's name
principal.binds.non_principal_identity_note   VETO regex on its mint note

inflections.irregular_plurals           {"singular": "plural", ...}

cli.results_dir / queries_out           dump.py --results / --out
cli.reference_dir / ours_dir / diff_out diff.py --reference / --ours / --out
```

**Defaults, and why they are not app knowledge.** Exactly four values default:
`uid_const` `_MY_UID`, `now_const` `_NOW`, `binds.uid`
`^SYM_USER_[A-Za-z0-9]+_id$`, `binds.request_param`
`^(?:__BIND__)?_?SYM_PARAM_`. These are conventions of *this pipeline* (the
constant names its output format uses and the symbol names its harness mints)
and every one is overridable — APP_B in the test suite overrides all four and
the suite proves the overrides are honoured. Everything that names a table,
column, model, plural or pinned value has **no default at all**: an app whose
config omits `principal.identity` gets no identity resolution — identity-shaped
binds stay honest placeholders, `ensure_myperson()` returns `None` and no join
is emitted. Silence produces a *weaker* claim, never a wrong one.

**No fallback knows where diaspora lives.** `RunTransformer(run)` with no
config and no `QFR_APP_CONFIG` raises `ConfigError` naming `--app-config`;
`dump.py`/`diff.py` exit 2 with the same message plus the missing flags:

```
no app config given: pass --app-config PATH or set QFR_APP_CONFIG=PATH.
The config is app-specific input owned by the driver side (for the concolic
experiments: reports/<app>/queries_config/app.json); src/queries_from_runs
never guesses it.
Contract: src/queries_from_runs/app_config.py
Missing: --results, --out
```

**The diaspora instance** is `reports/diaspora/queries_config/app.json`, which
gained `principal.identity`, `principal.binds`, `inflections` and `cli`.
`cli.reference_dir` is **null on purpose** — the reference policies are
quarantined, so `diff.py` cannot be run against them by default any more.
A new `validate_app_json.py` checks everything `schema.rb` can confirm
(50 tables, 6 principal columns, 40 FK lines, every bind regex, every `cli`
path): **OK**. It cannot check the pinned values or the symbol shapes —
those are properties of `targets.rb`, and the README says so.

### Driver-side hand-off (additive first, as required)

Every existing caller keeps working because it now supplies the path itself,
one line, `os.environ.setdefault("QFR_APP_CONFIG", …/queries_config/app.json)`:

- the six extractors `results3/queries_from_runs/_extract_*_streaming.py` —
  inserted **immediately after `sys.path.insert(0, "…/src")`**, i.e. ahead of
  the `_blockaid_fold` import, which reads the schema at module level;
- `results3/queries_from_runs/_blockaid_fold.py` (belt and braces: it is
  importable on its own);
- `results3/_experiment/variant_{d,e}/run_extraction.py` and
  `variant_d/test_assoc_fold.py`;
- `results3/_experiment/variant_b/_run_{extraction,diff}.sh` — these invoke
  the `dump.py`/`diff.py` CLIs **inside `systemd-run`, which does not inherit
  the caller's env** (the trap that bit `SUBSUME_TIMEOUT_MS` on 2026-08-20 and
  `QFR_APP_CONFIG` on `capped_checker.sh` this morning), so they get
  `--app-config <path>` as an explicit FLAG rather than a variable. They pass
  every directory explicitly already, so nothing else about them changes.

(`tools/blockaid_*.py`, `tools/rewrite_probe.py`, the reference-comparison
driver/probe and `capped_checker.sh` were already done by the subsume
refactor and need nothing further.) Every file was rewritten atomically
(`os.replace`) because other agents run them concurrently. `variant_d`'s own
test suite still passes (4/4), and `_blockaid_fold` still imports and still
sees `transform.MY_UID == "_MY_UID"`.

---

## 3. Proof of no behaviour change

Three independent arguments, weakest to strongest in coverage: the resolved
values are the same constants; the inputs are the same bytes; and the rendered
views are the same text over 18 000 sampled runs.

### 3.1 Every resolved value equals the constant it replaced

Old package (snapshot, its `_HERE` repointed at the real tree so its defaults
resolve exactly as they did in place) vs new package under the diaspora
config, in two processes, all 18 values compared:

```
SAME  uid_const            '_MY_UID'
SAME  now_const            '_NOW'
SAME  pinned_id            1
SAME  pinned_guid          'abc123'
SAME  uid_re               '^SYM_USER_[A-Za-z0-9]+_id$'
SAME  identity_id_re       '^SYM_PERSON_[A-Za-z0-9]+_id$'
SAME  identity_prefix_re   '^SYM_PERSON_'
SAME  np_name_re           '^SYM_PERSON_via_user(?:_|$)'
SAME  np_note_re           '^\s*User#person\b'
SAME  param_re             '^(?:__BIND__)?_?SYM_PARAM_'
SAME  pcs_uid_re           '^SYM_USER_[A-Za-z0-9]+_id$'
SAME  plurals              {'person': 'people'}
SAME  schema_rb            '…/ruby_examples/dse-apps/schemas/diaspora-schema.rb'
SAME  schema_tables        50 entries
SAME  schema_dump          50 entries   (every table's full column:type map)
SAME  fks                  40 entries
SAME  person_refs          15 entries
DIFF  fk_txt               old '…/src/queries_from_runs/blockaid/src/test/resources/DiasporaTest/fk.txt'
                           new '…/reports/diaspora/queries_config/resources/fk.txt'
```

The single DIFF is a **path**, and the two files are byte-identical:

```
4090b76ea3fa42d9a2b9a41453d425c9bdf9716df2862557cd85b93e00a92350  blockaid/…/DiasporaTest/fk.txt
4090b76ea3fa42d9a2b9a41453d425c9bdf9716df2862557cd85b93e00a92350  queries_config/resources/fk.txt
```

— so the parsed `fks` (40) and the derived `person_refs` (15) are identical,
which is what any code path actually sees. `schema.rb` is the same FILE on
both sides (`cd1c8378…`), not a copy.

`validate_app_json.py` independently re-derives the config's claims from
`schema.rb`: 50 tables, 6 principal columns, 40 FK lines, every bind regex,
every `cli` path — **OK**.

### 3.2 The tests are ground-truth differentials, not instance tests

Per DISCIPLINE: a check only counts if it FAILS on the defect it claims to
catch. Each moved item was re-hardcoded to its diaspora value in a scratch
copy of the NEW package and the test that claims to pin it was run:

| mutation (the app knowledge put back) | result |
|---|---|
| M1 `uid_const = "_MY_UID"` | **2 failed**, 2 passed |
| M2 `now_const = "_NOW"` | **1 failed** |
| M3 `pinned_id = 1`, `pinned_guid = "abc123"` | **3 failed**, 2 passed |
| M4 identity table/owner `people`/`owner_id` | **2 failed**, 1 passed |
| M5 uid bind regex `^SYM_USER_…` | **2 failed** |
| M6 plurals `{"person": "people"}` | **1 failed** |
| M7 identity refs seeded `("people","id")` + `person_id`/`author_id` | **2 failed**, 1 passed |
| M8 param regex `^…SYM_PARAM_` | **1 failed** |
| M9 identity regexes `^SYM_PERSON_…` | **3 failed** |
| M10 schema path → the app's `schema.rb` | **2 failed** |
| M11 `pcs` ignores `uid_pattern` | **1 failed** |

Every re-hardcoding is caught, and the battery was re-run against the FINAL
tree (after the audit fixes) with the same results. (The "passed" columns are the APP_A-shaped
controls: a mutation that puts APP_A's value back is invisible under APP_A by
construction — which is exactly why the second app exists.)

### 3.3 Six-corpus rendering differential — old vs new

**Method** (the same as the rotation fix and X1, with one addition). Two
processes rather than one, because the change spans module boundaries: the
OLD arm runs a verbatim snapshot of the pre-change package as
`queries_from_runs` (`PYTHONPATH=<snapshot>:src`), the NEW arm the real one.
Both install the DEPLOYED pipeline — `variant_d/assoc_fold.install()` +
`AssocFoldingTransformer`, i.e. exactly what the extractors run, so the fold
is held constant and only the config plumbing moves — and both use
`discover_param_pool` over the same paths. Per run, the emitted view list is
sorted and hashed; the deduped global view set is written out in full.
`RUNS DIFFERING` = runs whose (hash, count) differs; `VIEWS DIFFERING` = the
symmetric difference of the two global view sets.

**The addition:** other agents add dumps to these corpora while this runs (X1
hit exactly that, and it happened again here — people_stream went from 9 894
dumps at census time to 13 677 by the time its arms ran), so the OLD arm
FREEZES its sample into a list file and the NEW arm replays that list
verbatim. Both arms therefore see the same files, whatever else lands
meanwhile; the `pop=` column below is each corpus's population at the moment
its OLD arm drew, not a stable count. 3 000 seeded random dumps per corpus
(`seed=20260911`, random — never a sorted prefix). Read-only throughout;
nothing in any corpus directory was written. `SKIP_SUBSUME` is moot — this
harness never calls the checker. Each arm caged at `MemoryMax=1G`; peak RSS
**43 MB**, ~2 minutes per arm.

**X1's veto, measured rather than assumed.** people_stream is the only corpus
that mints a non-principal identity symbol, and both arms flag it the same
number of times — `non-principal-person-bind: 966` of 3 000 sampled runs on
each side, `unscoped: 3000` on each side. The rule that used to live in two
module-level regexes now lives in `principal.binds`, and it fires on exactly
the same binds.

**Result — every corpus, zero difference.**

| corpus | population | sampled | runs | views emitted | distinct views | RUNS DIFFERING | VIEWS DIFFERING | flag counts |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `comments_index` | 26 528 | 3 000 | 3 000 | 46 671 | 61 | **0** | **0** | identical |
| `conversations_index` | 18 623 | 3 000 | 3 000 | 65 646 | 91 | **0** | **0** | identical |
| `people_show` | 12 997 | 3 000 | 3 000 | 78 821 | 70 | **0** | **0** | identical |
| `notifications_index` | 270 884 | 3 000 | 3 000 | 58 128 | 686 | **0** | **0** | identical |
| `people_stream` | 13 677 | 3 000 | 3 000 | 71 760 | 181 | **0** | **0** | identical |
| `posts_show` | 129 607 | 3 000 | 3 000 | 112 721 | 124 | **0** | **0** | identical |

Totals: **18 000 runs**, **433 747 emitted views**, **0 differing runs, 0 differing
views, 0 transform exceptions on either arm**, and every per-flag count
identical corpus by corpus. Raw harness output:

```
comments_index         pop=  26528 sampled=  3000 runs=  3000 views=  46671 distinct=   61  RUNS DIFFERING=     0  VIEWS DIFFERING=     0  exc old/new=0/0
conversations_index    pop=  18623 sampled=  3000 runs=  3000 views=  65646 distinct=   91  RUNS DIFFERING=     0  VIEWS DIFFERING=     0  exc old/new=0/0
people_show            pop=  12997 sampled=  3000 runs=  3000 views=  78821 distinct=   70  RUNS DIFFERING=     0  VIEWS DIFFERING=     0  exc old/new=0/0
notifications_index    pop= 270884 sampled=  3000 runs=  3000 views=  58128 distinct=  686  RUNS DIFFERING=     0  VIEWS DIFFERING=     0  exc old/new=0/0
people_stream          pop=  13677 sampled=  3000 runs=  3000 views=  71760 distinct=  181  RUNS DIFFERING=     0  VIEWS DIFFERING=     0  exc old/new=0/0
posts_show             pop= 129607 sampled=  3000 runs=  3000 views= 112721 distinct=  124  RUNS DIFFERING=     0  VIEWS DIFFERING=     0  exc old/new=0/0
```

**No closed endpoint's rendering changes, so there is no shipped-policy
finding to escalate and nothing to re-extract anywhere.**

**The harness is kept**, because every future change that can move
reconstruction output needs exactly this evidence:
`reports/diaspora/tools/extraction_differential/` (`diffarm.py`,
`compare.py`, `run_diff.sh`, README with the two-`PYTHONPATH` recipe and the
frozen-sample rule).

---

## 4. Tests

`src/queries_from_runs/test_queries_from_runs.py` — **81 tests** (59 before,
22 new): **78 passed / 3 skipped** with no config at all, **81 passed / 0
skipped** with the app config and the two integration variables (below).
Before this work there were 59, and every one of them needed diaspora's
`schema.rb` on disk to mean anything.

**The suite no longer references any app.** Everything runs against TWO
SYNTHETIC APPS built in a temp dir at import:

- **APP_A** — social-app-shaped: `users`/`people`/`posts`/`comments`/
  `contacts`/`photos`/`likes`/`reports`/`participations`, identity table
  `people` owned through `people.owner_id`, pinned `1` / `abc123`, symbols
  `SYM_USER_*_id` / `SYM_PERSON_*_id` / `SYM_PARAM_*`, plural `person→people`.
  The 59 pre-existing tests run against it unchanged in substance (only the
  one column named after the app was renamed `handle`).
- **APP_B** — deliberately different in EVERY app-specific dimension:
  tables `accounts`/`members`/`articles`/`leaves`, principal table `accounts`,
  identity table `members` owned through `members.account_id`, constants
  `_CURRENT_ACCOUNT` / `_REQUEST_TIME`, symbols `SYMV_ACCT_*_pk` /
  `SYMV_MEMBER_*_pk` / `QUERYARG_*`, vetoes `SYMV_MEMBER_borrowed*` and
  `Account#member`, pinned `77` / `zzz-9`, plural `leaf→leaves`.

14 new tests run the same machinery under APP_B: the uid constant and bind
shape, the now constant, the identity join's table/owner column, both
non-principal vetoes, the pinned id and the pinned guid, the guid column, the
inflections, the `pcs` uid pattern, the request-param pattern, the FK-derived
identity columns and their fallbacks, an app with NO identity block, and the
no-config error. Several are negative: APP_A's uid shape is **not** a uid
under APP_B, APP_A's pinned `1` is **just a number** under APP_B, APP_A's
`via_user` veto word means nothing under APP_B.

**X1's rule is pinned, not just preserved.** The four X1 tests
(`test_sym_person_via_user_*`, `test_non_principal_mint_note_vetoes_a_
principal_SHAPED_name`, `test_principal_person_bind_still_resolves_*`) are
unchanged and green under APP_A, and the veto is now ALSO exercised in APP_B's
vocabulary, so "the veto fires" is a property of the rule and not of the
string `via_user`.

Rule tests, all new:

- `test_no_app_name_in_any_module` — no app name in ANY `.py` under
  `queries_from_runs/` (modules, `audits/`, `subsume/`, and this test file).
  One exemption mechanism, a `# app-name-rule` marker comment, used on
  exactly one line: the pattern the rule itself is written with. Nothing else
  is allow-listed; every other occurrence was rewritten.
- `test_no_app_name_in_the_subsume_harness_scripts` — same for `.sh`/`.java`.
- `test_no_app_path_defaults_in_the_package` — no `reports/`- or
  `ruby_examples/`-rooted string literal may appear as a default anywhere in
  the package. This is the one that would have caught E12's CLI-default rows
  the day they were written.
- `test_subsume_harness_carries_no_app_data` — no fixture directory in `src/`.

Two integration tests kept their value but lost their hardcoded paths: they
now take `QFR_TEST_RUNNER_RB` (a runner `.rb`) and `QFR_TEST_DUMP_DIR` (an
endpoint dump dir, with `QFR_APP_CONFIG`), and skip when unset. Their
assertions were re-aimed at the SHAPE of the output (every line a terminated
SELECT, every bind resolved or an explicit placeholder, one run loaded per
dump) rather than at one app's expected SQL. The diaspora side documents the
invocation in `queries_config/README.md`.

Driver-side suites still green: `variant_d/test_assoc_fold.py` **4 passed**,
`src/test_statement_note_lint.py` green.

---

## 5. Two audits that were quietly app-specific

Not on E12's list, found while sweeping `audits/*.py`, and both fixed the
same way (config first, explicit flag second, RED with neither):

- `audits/bind_resolution_audit.py` imported `_USER_ID_RE`, `_PERSON_ID_RE`
  and `_PARAM_BIND_RE` from `transform.py` **inside a bare `try/except`** —
  after this refactor those names no longer exist, so it would have silently
  fallen back to name-level-only classification. It now compiles them from
  `principal.binds` and reports the config error as the cause of its RED.
  (Its schema-unavailable RED already existed and is unchanged.)
- `audits/identity_symbolicity_audit.py` hardcoded `"users"."id"` and
  `DEFAULT_PRINCIPAL = ["user_id","owner_id","recipient_id"]` — diaspora's
  principal columns, as its default. It now derives them from
  `principal.principal_table` + `principal_columns`, prints the set it is
  auditing, and exits 2 if neither a config nor `--principal-cols` is given.
  **The derived set is identical to the old default** — `users.id` plus
  `{owner_id, recipient_id, user_id}` — so no audit verdict moves.

An audit that invents its own idea of "the principal" passes on the wrong
columns and calls it green; that is why neither one keeps a default.

**One trap this opened and closed.** `identity_symbolicity_audit` is invoked
by twelve batch scripts with a **plain `python3`**, not the venv — it was
stdlib-only. `from queries_from_runs import app_config` runs the package
`__init__`, which imports sqlglot, which plain python3 does not have: the
audit would have gone RED on every one of those scripts. It now loads
`app_config.py` **standalone** by path (it is stdlib-only and has no relative
imports), falling back to that only when the package import fails, and
registers the module in `sys.modules` before executing it so `@dataclass` can
resolve its annotations. Verified in all three modes: plain `python3` with a
config (works), plain `python3` without one (RED, names the flag), venv with
a config (works).

Those twelve scripts
(`results3/{comments_index,conversations_index,notifications_index,people_stream,posts_show}/*audits*.sh`
and the comments_index chains) each got the same one-line
`export QFR_APP_CONFIG="${QFR_APP_CONFIG:-…}"` after their header, so they
keep running unchanged; all twelve pass `bash -n`.

---

## 6. Docs

- `src/queries_from_runs/README.md` — "the app is INPUT" up front; the
  transformation rules restated in config terms; a table of which block drives
  which module; the CLI's new flags and exit-2 behaviour; how the tests run
  with and without an app.
- `src/queries_from_runs/app_config.py` — the module docstring IS the
  contract; new blocks documented inline, with the four framework defaults
  named and justified.
- `src/queries_from_runs/plan.md`, `__init__.py`, `audits/*.py` — prose
  degeneralised.
- `reports/diaspora/queries_config/README.md` — what each block DECIDES (a
  table), the warning that an edit here is an extractor change, the
  `targets.rb` / Rule T coupling, `validate_app_json.py`, and the recipe for
  running `src/`'s tests against this app.
- `reports/diaspora/queries_config/validate_app_json.py` — **new**; the safety
  net that replaces "src/ would have noticed".
- `reports/diaspora/docs/RUNBOOK.md` Phase 6 — the whole package (not just the
  checker) needs the config; an `app.json` edit is an extractor change and
  needs `validate_app_json.py` + the corpus differential; `diff.py` has no
  reference default because the reference is quarantined; and the two audits
  now go RED without a config (every `*audits*.sh` exports it, a new one must
  too).
- `reports/diaspora/tools/extraction_differential/` — **new**; the harness +
  README, so the next reconstruction-affecting change has the evidence path
  ready instead of rebuilding it.
- `src/queries_from_runs/subsume/README.md` — one step added to "Pointing at
  another app": the same `app.json` drives reconstruction, fill it with the
  app's `targets.rb` open.
- `_EXTRACTION_OPEN_ISSUES.md` — **E12 CLOSED** with the disposition table and
  the three things deliberately left open; **E13 opened** as an inventory.
- `reports/diaspora/README.md` — the layout block now lists `queries_config/`
  (the app config) and `tools/extraction_differential/`.

---

## 7. E13 — diaspora named outside `queries_from_runs` (inventory, not fixed)

Full file:line table in `_EXTRACTION_OPEN_ISSUES.md`. The headline:

**Every hit is prose.** 23 occurrences across 12 files, all comments,
docstrings or READMEs — usage recipes naming `scripts/diaspora-concolic`,
pointers into `reports/diaspora/docs|tools|results3`, one docstring example
manifest, and one correctly-attributed measured claim
(`concolic_engine/assumptions.py:39`, "in the diaspora experiment … ~64%").
**No executable path, constant or identifier in `src/ruby_runtime`,
`src/end_to_end_completion_checker` or `src/concolic_engine` names an app**:
the one functional app path in the Ruby stack is in the driver-side
`scripts/diaspora-concolic` (`DIASPORA_APP=…/apps/diaspora`), where it
belongs. So E13 is a documentation job with no behavioural risk, unlike E12.

Distribution: `end_to_end_completion_checker/concrete/CONCRETE_CHECKER.md` 9,
`end_to_end_completion_checker/README.md` 3, `ruby_runtime/concolic_harness.rb`
2, `ruby_runtime/completion_checker/{README.md,concrete_run_probe.rb}` 2 each,
`ruby_runtime/completion_checker/{mock_checker.rb,shim_test_runner.rb}` 1 each,
`end_to_end_completion_checker/assumption/assumption_checker.py` 2,
`end_to_end_completion_checker/mock/mock_note_check.py` 1,
`concolic_engine/assumptions.py` 1.

One judgement recorded for whoever takes it: `assumptions.py:39` should KEEP
its attribution. A number measured on one app must say which app — the rule
is "no app-specific input or behaviour in `src/`", not "no app may ever be
named in a provenance note".

---

## 8. Honest notes

- **A blockaid run was started by accident and killed.** Smoke-testing one
  extractor, I assumed a `SKIP_SUBSUME` knob it does not have; it reached the
  subsumption prune and ran the checker for ~2 minutes before I killed it
  (`pkill`, JVM confirmed gone, no output written, no file in any endpoint
  directory touched — the run wrote only to a scratchpad path). Nothing was
  produced from it and nothing depends on it. The extractor smoke test was
  replaced by the differential harness, which never calls the checker.
- **Two module names survive in `transform.py` as deprecated aliases**,
  `MY_UID` and `NOW`, bound to the contract's default constant names. They
  exist only so a driver-side importer (`_blockaid_fold.py`) does not break
  mid-flight; the value a run actually uses is `RunTransformer.uid_const` /
  `.now_const`. They are not app data (`_MY_UID` is this pipeline's own
  output convention) but they ARE stale if a config overrides the constants,
  which the comment on them says.
- **`audits/README.md` keeps one pointer** to `reports/diaspora/tools/` — the
  same convention `subsume/README.md` already uses: prose may say where the
  example app's driver lives. The rule test covers `.py`, not `.md`.
- **Twelve of the edited files live inside ENDPOINT directories**, which the
  brief told me not to touch beyond reading: the `*audits*.sh` chains in
  `results3/{comments_index,conversations_index,notifications_index,people_stream,posts_show}/`.
  The edit is one behaviour-preserving line each
  (`export QFR_APP_CONFIG="${QFR_APP_CONFIG:-…}"` after the header); without
  it those scripts would go RED on two audits the moment their owner re-ran
  them, which the "every intermediate state must keep them working"
  requirement forbids. No other content in any endpoint directory was
  changed, and no dump, policy, header or result file was written. **Flagged
  for owner review**, not presented as unremarkable.
- **Five `completion_config.json` files were edited and then REVERTED.** I
  added `QFR_APP_CONFIG` to their `env` block defensively, realised they are
  endpoint-owned and that none of their `extra_audit_cmds` actually needs it
  (they run `empty_relation_emission`, `noteless_call`,
  `cardinality_consistency`, `note_fidelity`, `format_coverage` — none imports
  the package), and restored them to their original `indent=2`,
  no-trailing-newline form with the key removed. Net change: none. **For the
  future:** if anyone adds `identity_symbolicity_audit` or
  `bind_resolution_audit` to an `audit_cmds` / `extra_audit_cmds` entry, that
  config's `env` needs `QFR_APP_CONFIG` — `completion.py:_run` merges `env`
  over `os.environ`, so one key is enough. That is an owner action; it is
  recorded here rather than done.
- The differential samples 3 000 dumps per corpus, not the full 465 000. The
  claim that carries the result is §3.1 + §3.2 (identical resolved values over
  identical bytes); §3.3 is the empirical confirmation, at the same sample
  size X1 used.
