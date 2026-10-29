# Implementation log: HARNESS_PLAN.md

One entry per milestone. Engine branch: `php-runtime/real-apps` (off `php-runtime/sink-templates`)
in `agentic_concolic_engine`. Harness branch: `report/symphp-benchmark` in this repo.

## M0: judge fixes, the 5.7 statement-history check, score.py (2026-10-29)

**Changed**
- `appdb.py` (new): per-app clone MySQL servers `ace-<app>-db` / `judge-<app>-db`, loaded from a
  snapshot (`build/snapshots/<app>.sql`, made with a read-only `mysqldump --single-transaction`
  from the installed `<app>-mysql57`). `restore` (= the reset), `statement_errors(schema)`,
  `clear_history`, and a per-server `flock` (`build/locks/<server>.lock`). Every container is
  started with `--log-opt max-size=20m --log-opt max-file=2`.
- `judge.py`:
  - A `db` app (apps.json `db` block) gets its own judge server. **Deviation from the plan's
    "port comes from config":** WebChess's own `config.php` hardcodes `127.0.0.1:3341`, which on
    the host is the INSTALLED `webchess-mysql57`. A `mysqli.default_port` flag cannot redirect
    it. So the clone listens on the app's port inside its own network namespace, and php-cgi
    runs in a long-lived runner container (`judge-<app>-php`, image `ace-judge-php74`,
    `--network container:judge-<app>-db`) where the app source is mounted **read-only**.
    php-cgi-trace (a host binary) runs there under the host's loader/libraries, mounted
    read-only (`/hostlib/ld-linux-x86-64.so.2 --library-path /hostlib ...`).
  - Errors are filtered to `CURRENT_SCHEMA = <app db>` (Witcher-Test: `schema: testdb`).
  - One replay at a time per server (lock file).
  - `--reset request|batch|none`; the default for a `db` app is `request` (snapshot and the
    session directory restored before each replay). Witcher-Test keeps the old setup
    (host php-cgi, `ace-judge-mysql:3307`, no reset).
  - `--coverage xdebug` adds `xdebug_lines` from a second pass (one reset, all requests in
    order). The `lines` field is unchanged.
  - Each replay also records the CGI response headers (for M4's content-type check).
- `judge_cov_prepend.php` (new), see (g) below.
- `score.py`: reads `known_vulns_file` (apps.json -> `known_vulns/<app>.json`, read only) and
  matches on `sink_file:sink_line`. Per-sink and per-CVE counts. `ace:<a>+<b>` scores the union of
  arms. `--coverage xdebug`.
- `apps.json`: `webchess` entry (all 30 `.php` files as entry scripts, `db` block, ini);
  `schema: testdb` on witcher-test and oracle-fixtures.

**(g) Xdebug.** Tried without a prepend first: Xdebug 3.1.6's `xdebug.mode=coverage` only
enables the collector. No ini setting starts it (`start_with_request` covers
debug/trace/profile only), and trace mode records function calls, not lines. **Method used:**
a coverage-only `auto_prepend_file` (`judge_cov_prepend.php`), outside every docroot and used
only on the Xdebug coverage pass, never on fault replays. It calls
`xdebug_start_code_coverage()` and writes the executed lines from a shutdown function.

**5.7 statement history: works.** On `judge-webchess-db` (5.7.44, started with
`--performance-schema-consumer-events-statements-history-long=ON`, consumers re-enabled at
runtime), an erroneous statement in `webchess` shows up with `MYSQL_ERRNO=1064`. One in another
schema is excluded by the `CURRENT_SCHEMA` filter.

**Ran**
- `judge.py replay webchess` on 3 hand requests: `mainmenu.php ToDo=HideMessage messageID=1'`
  faults (`UPDATE communication SET ack = 1 WHERE commID = 1'`, errno 1064); `index.php` and
  `viewmessage.php messageID=1` do not. Xdebug lines are reported for all three. 3 replays with
  per-request reset take 1.9 s.
- Witcher-Test regression: `score.py witcher-test m0:rejudge_ace_cold
  results/witcher-test/requests_ace_cold.json` (the committed ACE requests, new label) gives
  **7/7, 98.82% (84/85), 11/39 faulting**, identical to `score_ace_cold.json`.

**Not touched:** `webchess-mysql57` (one read-only `mysqldump`), the host MySQL, `wfull-*`,
and the existing databases in `ace-judge-mysql` (`judge.py setup witcher-test` was not re-run).

## M1: E1-E4 and H1-H3, WebChess logged out (2026-10-29)

**Engine** (`php-runtime/real-apps`; every option off by default, each with tests):
- **E1** `Runtime::target($n, 'concrete', ...)`: the supplier runs the real call and returns
  `{value, summary}`. `call()` records a `concrete_call` event (encoded args, sealed note, summary,
  location) and returns the value unwrapped. There is no symbol and no `call`/`symbolic_call`
  event. **Deviation:** concrete targets are left out of the dump's `declarations` table, because
  `concolic/model/declarations.py` keeps `KINDS` closed (`target_function`, `shim`).
- **E2** instrumentor option `php7Compat` plus `Runtime::$php7Compare`:
  - parse as 7.4;
  - `__const7`, `__count7`, the switch rewrite (below);
  - concrete loose comparison with 7.x number-vs-non-numeric-string rules.
  - **Extended beyond the plan**, because WebChess needed it in its first run:
    - arithmetic on a string with no leading number gives 0 plus a warning, as on 7.x
      (`__arith`);
    - `call7`: a fixed list of internal functions (mysqli result functions, a few array
      functions, `implode`) returns NULL plus a warning on a wrong-typed argument where PHP 8
      throws `TypeError`. `mysqli_num_rows(false)` after a broken query is the WebChess case.
  - Each rewrite is counted per file (`instrument_app.php` -> `rewrites_by_file`). Each runtime
    fallback is counted per request (`php7` in harness results, `php7_runtime` per script).
  - Tests: `fixtures/php7compat/*.php` (8 fixtures). Each is run uninstrumented on php:7.4-cli
    (`tests/php7compat_regen.sh` -> `*.out74`), then instrumented on 8.2 by
    `t_php7compat.php`; the outputs must match. A negative control shows that 5 of them differ
    without the option.
- **E3** `exitAsHalt`: `exit`/`die` -> `\__exit()`, which throws `ExitSignal extends HaltError`.
  Every catch gets `\__ace_rethrow_exit($e);` first; a var-less catch gets `$__ace_exit`. The
  printer puts an inserted statement on its own line, which would shift every later line, so
  `Instrument::source` joins the guard onto the `{` line. A test pins line numbers for 5 catch
  shapes. `run()`/`finish()` record `halted.exit = true`. As the plan documents, `finally`
  blocks run on this exit.
- **E4** `Runtime::$concretizeUnmodelled`:
  - covers `Value::__toString`, `Template::__toString` and the `__fn` defaults (as in the plan);
  - **extended** to `(int)` casts of strings, comparisons the IR refuses (mixed sorts, numeric
    strings), arithmetic on non-ints, `is_numeric`, and templates in decisions;
  - each records a `concretized` event (`what`, `symbols`, location).
- **Not in the plan, needed:**
  - `switchCmp` (implied by `php7Compat`): `switch (E) { case C: }` becomes
    `switch (true) { case \__cmp($__ace_swN = E, '==', C): }`. The subject is evaluated once,
    in the first non-default case, and no line moves. Without it, a switch on a symbolic value
    (WebChess `switch ($postTodo)`, the whole ToDo dispatcher) gives PHP's own `==` a Value and
    cannot be explored.
  - `Runtime::begin()/finish()`: `run()` is now exactly these two around the handler, so a
    harness can `include` the app at file scope.
- Python: `AnnotationEvent` / `ConcreteCallEvent` in `concolic/model/run.py`. They are read in
  order and round-tripped, and ignored by the solver and the coverage checker
  (`test_annotation_events.py`).
- Suites: PHP **149 tests, 629 assertions, 0 failed** (php:8.2-cli; was 134/564). Python
  `concolic/model/tests`: **422 passed, 3 skipped**.

**Harness** (`report/symphp-benchmark`):
- `harness_app.php` (new; `harness.php` is kept for Witcher-Test, with only a guard added so
  its classes can be reused):
  - one PHP process per request;
  - the app is included at file scope between `begin`/`finish`;
  - the app's own `mysqli_connect` reaches `ace-<app>-db` through the network-namespace trick;
  - `mysqli_query`/`real_query`/`multi_query` are concrete targets: the note is published, then
    the query runs on the template's text. `mysqli_report(OFF)` as on 7.4, and an empty query's
    `ValueError` gives `false` as on 7.4;
  - `$_SESSION` is a seeded array; `session_*`, `header`, `setcookie` are recording stand-ins;
  - `$_SERVER` is the judge's `cgi_env` for the same request;
  - a fatal error or a real exit still writes the dump (shutdown hook).
- `instrument_app.php`: `--app-targets --php7compat --exit-as-halt --switch-cmp`. It writes
  only the copy in `build/<app>-<label>/` and reports per-file and total rewrite counts.
  Default output is unchanged.
- `drive.py`:
  - app mode for an app with a `db` block: image `ace-php82-mysqli:1` (php:8.2-cli plus mysqli,
    built from an inline Dockerfile), runner `ace-<app>-php`;
  - the DB is restored per script (decision (a));
  - `--label`, so results go to `results/<app>/<label>/`; `--budget` (wall clock per script);
    `--php7compat`, `--exit-as-halt`, `--concretize`;
  - **app mode keeps errored dumps**, since the sink events before an error are real; Witcher
    mode still drops them;
  - each summary reports concretizations, PHP 7 runtime counts and halted traces;
  - `run.json` records the options and the instrumentation report.
- `sinks.py` reads `concrete_call` events too, and records the DB's errno.
- `score.py` reports the findings that the judge confirms (each oracle witness replayed: does it
  fault?).
- Python for the driver: `build/venv` (z3-solver, sqlglot 30.25.0, pytest, html5lib). The host
  python has neither z3 nor sqlglot.

**Ran**
- Witcher-Test regression with every new flag off: `drive.py witcher-test --arm cold --label
  m1_regress_cold` and `score.py witcher-test ace:m1_regress_cold` give **7/7, 98.82% (84/85),
  39 requests, 11 faulting**, identical to the committed `score_ace_cold.json`.
- WebChess: `drive.py webchess --arm cold --label m1_cold --budget 600 --php7compat
  --exit-as-halt --concretize` covers 30 scripts, 146 traces and 262 requests in about 70 s; no
  script hit the budget. Then `score.py webchess ace:m1_cold --coverage xdebug`.
  - **Detected 6/10** (WC-1, 2, 5, 6, 7, 10; both CVEs). This matches the plan's M1 estimate.
    The 4 misses (WC-3, 4, 8, 9) are all `auth: user` (M2).
  - **ACE findings: 20/20 judge-confirmed** on the uninstrumented 7.4 replay, schema-filtered.
  - Coverage: trace **32.38% (620/1915)**; Xdebug **33.58%**.
  - Most M1 hits are *malformed-at-reach*: an action whose parameter is absent builds
    `... WHERE gameID = `. That is the Witcher/SymPHP fault criterion. The oracle's
    *injectable* witnesses (payload requests) are among the 20 too.
  - Harness errors: none. The only run errors are `Call to undefined function gettext()` in
    `footer.php` and `mailmsg*.php` (6 scripts). That is the app's own fatal, reproduced on the
    7.4 judge: those files are meant to be included after `lang.php`.
  - Known-list line convention: some entries give the query-building line (`mainmenu.php:315`),
    while ACE reports the `mysqli_query` call (`:316`). Scoring uses the judge trace, so this
    does not matter.

**E2 rewrite counts, WebChess** (static, `results/webchess/m1_cold/run.json`):
`const7` 249, `call7` 115, `switch` 14, `count7` 1 (`exit` 32 is E3). Runtime fallbacks over the
whole run: `const7` 4 (all `APP_NAME`, in `footer.php`/`mailmsgtest.php`, which never include
`config.php`); `call7` 32 (`mysqli_num_rows` 30, `mysqli_fetch_array` 2, all after a failed
query); `cmp7`/`arith7`/`count7` 0. So of the 249 constant rewrites, only `APP_NAME` ever took
the PHP 7 path; the rest (`$CFG_TABLE[games]`) resolve to constants that `config.php` defines.
E4 concretizations: `is_numeric` 96, string conversion 32 (`chessdb.php:292`), comparison 6.
