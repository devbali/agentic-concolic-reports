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

## M2: authenticated seeds, then HSM and phpMyAdmin (2026-10-29)

**Changed**
- `apps.json` `login`, per app: `cookie` (a fixed session id, `acesession`), `recipes` chosen by
  script-path prefix (HSM has admin, doctor and patient areas, which share session keys),
  `credential_keys`, and per-recipe `password`, `success_key|success_cookie`, optional
  two-step `pre` + `token` (phpMyAdmin's form token), and `cookies_from_login`.
- `drive.py --arm auth`, per script after the DB reset:
  - runs the app's OWN login request(s) through the harness and seeds `$_SESSION` from the
    session they leave. The session is PHP-serialized and base64-encoded; the `session_start`
    stand-in restores it after the app's autoloader exists;
  - the seed request carries the session cookie, plus, for phpMyAdmin, the auth cookies the
    login's `setcookie` stand-in recorded.
  - **DEFAULT (to confirm):** a newly discovered POST key whose name matches
    `credential_keys` (`pass|pwd`) starts with the login password instead of absent, as a
    logged-in crawler fills a password field. WebChess WC-9's old-password check
    (`password_verify`) cannot be solved symbolically.
- `judge.py`: a request that carries the login cookie is replayed after the judge runs the same
  login itself (after the per-request reset). With `cookies_from_login`, it uses the cookies
  from ITS OWN login response (phpMyAdmin's encrypted pmaUser/pmaAuth are tied to the session).
  `score.py ace:a+b` reports each arm separately from ONE union replay (decision (e)).
- **Array mode (decision (b), DEFAULT, opt-in `--array-mode`)**: engine
  `InstrumentVisitor` option `superglobalReads` plus `Concolic\Superglobals`.
  - Superglobals are real arrays of the present inputs.
  - Each direct read becomes `$_GET[\__sg_key('GET', $_GET, k)]`, which records discovery, or
    puts a declared-absent key's null Value in place so `isset`/`??` still record presence.
    The expression stays a variable, so by-reference passing works.
  - **Deviations:** a declared-absent key, once read directly, appears in later iteration of
    that superglobal; keys reached only by iteration are not discovered.
  - Needed by phpMyAdmin (`$_REQUEST = array_merge($_GET, $_POST)`, `foreach ($_COOKIE ...)`,
    `count($_REQUEST)`). The plan expected it only for phpBB/WordPress/Drupal/Opencart.
- Engine, found on HSM/phpMyAdmin:
  - **bug fix:** `<?php echo $x?>` (closed by the tag) lost its `?>`, so the following HTML
    parsed as PHP (6 HSM files). That shape now keeps its echo and wraps each expression in
    `__echo_str`;
  - E2 `curly_offset`: `$s{0}` -> `$s[0]` (fixture against 7.4);
  - E4 for subscripts of a symbolic scalar;
  - opt-in `realAppBuiltins`: routes type predicates and `hash_equals` through `__fn`
    (unrouted, `is_scalar($value)` answers about the wrapper object); concretizes symbolic
    array keys (`__key`); wraps the by-value arguments of internal functions in `__arg`
    (by-reference positions come from reflection at instrumentation time);
  - harness state moved into a static class, because phpMyAdmin unsets all unknown globals.
- `appdb.py`: `mysqld_args` (HSM `--lower-case-table-names=1`), `init_sql` (HSM's `hms`
  user), `schema_filter: false` (phpMyAdmin's clone server is its alone, so every error
  counts). `exec_lines.php` skips unreadable files (HSM's dangling `doctor/.#search.php`).

**Ran and results**
- **WebChess** auth: `drive.py webchess --arm auth --label m2_auth --budget 600 --php7compat
  --exit-as-halt --concretize`; score `score.py webchess ace:m1_cold+m2_auth --coverage
  xdebug`:
  - **cold 6/10, auth 9/10, union 9/10**;
  - findings **59/60 judge-confirmed**;
  - coverage trace **52.43%** (1004/1915), Xdebug **50.91%**.
  - **WC-9 missed, reason: budget/search order.** In `mainmenu.php` authenticated, 655 of 725
    traces went to `ToDo=UpdatePrefs` (combinatorial preference flags) before the 600 s
    budget ended. `UpdatePersonalInfo` was reached twice and never expanded to its UPDATE
    (:384). With the credential default the old-password check passes, so this is a scheduling
    miss, not a modelling one.
  - The unconfirmed finding is `mainmenu.php:447` (UpdatePrefs, `userLevel='`). The judge saw
    no fault there.
- **HSM** (procedural mysqli; no app edits; `lower_case_table_names=1` as in its RUNLOG):
  `--label m2_cold` / `m2_auth`, same flags; 73 entry scripts, about 2.5 min per arm, **0 run
  errors**. Score `ace:m2_cold+m2_auth`:
  - **24/29 (cold 24, auth 24)**: every SQLi except HSM-12/17, plus none of the 3 XSS (M4);
  - findings **88/91 judge-confirmed**;
  - coverage trace 29.13%, Xdebug 29.33%.
  - Cold equals auth because HSM's `check_login()` only sends a `Location` header and does not
    exit, so logged-out requests run the protected code (on the 7.4 judge too).
  - HSM-12/17 (`search.php:90`, `like '%$sdata%' || ... like '%$sdata%'`): the oracle's lone
    `'` payload balances when the input appears twice in quotes. Fixed in M4 by unbalanced
    payloads (see M4).
  - Unconfirmed: `admin/registration.php:11` twice, `admin/change-password.php:15` once.
- **phpMyAdmin: harness works, not scored (time box).**
  - Done: a clone `ace-/judge-phpmyadmin-db` (MySQL 8 on 3307 in its namespace, snapshot =
    read-only `mysqldump` of `pma47` from `ace-judge-mysql`); 2822/2822 files instrumented,
    0 failures; the two-step cookie login works on both sides (the judge confirms PMA470-8 by
    hand: `tbl_get_field.php?db=pma47&table=items&where_clause=1'` faults); authenticated
    exploration runs (`results/phpmyadmin/m2_try_auth/tbl_get_field.php`: 258 traces, it
    discovers `db`/`table`).
  - **Why no score:** reaching the sinks needs `db`/`table` to name an existing database and
    table (`selectDb($db)` must succeed). That is a DB value (decision (c)), and the plan
    counts on crawl seeds to supply it. There is no crawler in this harness. Seeding them from
    the known-vuln list would be cheating. A full run would also take about 3 h at 120 s per
    script.
  - **Remaining:** a crawl-seed generator (links/forms from explored pages' output), then
    `drive.py phpmyadmin --arm auth --array-mode --real-app-builtins ...`.

**E2 rewrite counts** (static, from each run's `run.json` / instrument report):

| app | files | const7 | call7 | count7 | switch | curly_offset | nested_ternary |
|---|---|---|---|---|---|---|---|
| WebChess | 30 | 249 | 115 | 1 | 14 | 0 | 0 |
| HSM | 85 | 24 | 75 | 9 | 33 | 0 | 0 |
| phpMyAdmin | 2822 | 1605 | 722 | 583 | 345 | 131 | 1 |

Runtime PHP-7 fallbacks:
- WebChess auth: `const7` APP_NAME ×4; `call7` `mysqli_fetch_array` 11366, `mysqli_fetch_row`
  3797, `mysqli_num_rows` 33 (all on a failed query's `false`; mostly chess.php's malformed
  `gameID` queries); cmp7/arith7/count7 0.
- HSM: `call7` `mysqli_fetch_array` 6, otherwise 0.
- phpMyAdmin: counters unreliable (the app unsets the `$GLOBALS` counters).

Other options: `exit` (E3) WebChess 32, HSM 6, phpMyAdmin 318; `catch` HSM 4, phpMyAdmin 572.
phpMyAdmin with `realAppBuiltins`: `internal_arg` 11774, `array_key` 12574, `builtin_routed`
229; array mode: `sg_read` 2323.

## M3: E5 sanitizers (2026-10-29)

- Engine (`Runtime::$sanitizers`, off by default; needs `templates`):
  - `addslashes`, `mysqli_real_escape_string` (subject = 2nd argument),
    `htmlspecialchars`/`htmlentities` (with the flags passed), `escapeshellarg`/`escapeshellcmd`,
    `trim`, `strtolower`/`strtoupper` on a symbolic string give
    `Template([Sanitized(value, chain)])`;
  - on a Template, each literal part is transformed and each symbolic part's chain extended;
    `trim`/`escapeshellarg` of a multi-part template fall back to E4;
  - refs are sealed as `{name, apply: [[fn, args], ...]}`;
  - `BUILTINS` grows by the 6 sanitizer names. A symbolic argument there raises (or E4)
    instead of reaching `__toString`: same outcome, different path, when the flag is off.
  - Tests: off-by-default refusal, chain, flags, subject position, template parts.
- Harness:
  - `sinks.py` applies the chain to every candidate payload (Python twins of the 9 functions);
  - `test_sanitizers.py` checks them against PHP on 307 random ASCII strings × 12 cases (2
    passed). It found 3 real differences, now fixed: `escapeshellcmd` does not escape `,`;
    its quote pairing is left to right with a pending quote character; `double_encode=false`
    keeps only HTML 4.01 entity names;
  - `--sanitizers` in drive.py.
- Ran:
  - `drive.py webchess --arm cold --label m3_cold ... --sanitizers`: the same sites and traces
    as M1 (WebChess's escapes are all on authenticated paths).
  - `--arm auth --label m3_auth --only sendmessage.php`: the two `mysqli_real_escape_string`
    calls are no longer concretized, and the INSERT's note carries
    `{"name":"POST_txtTitle","apply":[["mysqli_real_escape_string",[]]]}`. On that trace the
    oracle reports nothing (escaped and quoted); the site is still found injectable through
    the unescaped `from`/`to` (WC-8).

## M4: E6 and XSS confirmation (2026-10-29)

- Engine: `Runtime::$outputEvents` (off by default). `__echo`/`__echo_str` record an `output`
  event for a symbolic Value or Template: its sealed note (refs and chains) and the byte offset
  in the response (bytes buffered above `outputBaseLevel`). Test included. Suite **161 tests,
  683 assertions, 0 failed**.
- `sinks.xss_findings`, for each output event and each carried input:
  - the payload is a unique marker `"'><acexss<hash>>`;
  - the ref's sanitizer chain is applied, and the site is dropped if `<` does not survive;
  - otherwise Z3 is asked for a value that satisfies every prior path condition and contains
    the marker, giving an `xss-candidate` with that witness.
- `judge.py` (decision (f), structural only): the request must carry an `acexss` marker; the
  response must be HTML and not an attachment; html5lib must parse the marker as an element or
  attribute NAME. A control request with the marker as plain text does not fault.
- `sinks.PAYLOADS` gains `'(` and `"(`, appended after the existing four, so earlier verdicts
  are unchanged. A lone quote balances when an input appears twice inside quotes (HSM-12/17).
- Witcher-Test after every engine change of M2-M4: `drive.py witcher-test --arm cold --label
  m4_regress_cold` + score gives **7/7, 98.82%, 39 requests, findings 7/7 judge-confirmed**.
- HSM: `--label m4_cold` / `m4_auth` with `--sanitizers --xss`. All three XSS sites
  (`doctor/search.php:74`, `admin/patient-search.php:74`,
  `admin/betweendates-detailsreports.php:61`) and both search SQLi (`:90`) are now flagged.
  Score: see the next entry.

### M4 HSM score
`score.py hsm ace:m4_cold+m4_auth --coverage xdebug`:
- **29/29 (cold 29, auth 29)**: 26 SQLi + 3 structurally confirmed reflected XSS;
- findings **98/101 judge-confirmed**; coverage trace 29.13% (990/3399), Xdebug 29.33%;
- the 3 unconfirmed are the same as in M2 (`admin/registration.php:11` ×2,
  `admin/change-password.php:15`): the oracle's statement does not break on the 7.4 replay.

## State at hand-off
- Headline scores, all judge-replayed on uninstrumented PHP 7.4 with schema-filtered faults:
  - WebChess **9/10**: M1 cold 6, M2 auth 9, union 9. WC-9 is a budget/search-order miss.
  - HSM **29/29** (M4 union).
  - phpMyAdmin not scored: no crawl seeds (see M2).
  - Witcher-Test still 7/7 with all flags off.
- Containers started and left running, all log-capped:
  - `ace-` and `judge-{webchess,hsm,phpmyadmin}-db`;
  - `ace-` and `judge-{webchess,hsm,phpmyadmin}-php`.
- Image built: `ace-php82-mysqli:1`.
- Python environment: `build/venv`.
- DEFAULTs and deviations to confirm:
  - E2 php7Compat, including its extensions: `call7`, `curly_offset`, `arith7`, and
    `switchCmp`;
  - E4 extensions: casts, comparisons, arithmetic, `is_numeric`, subscripts;
  - `realAppBuiltins`;
  - array mode (b);
  - the credential default in the auth arm;
  - concrete targets left out of `declarations`;
  - app mode keeps errored dumps;
  - the judge's network-namespace runner (instead of a port flag);
  - Xdebug via a coverage-only prepend;
  - read-only dumps from `webchess-mysql57` and from `ace-judge-mysql` (`pma47` only);
    HSM's snapshot is its pristine dump file.
