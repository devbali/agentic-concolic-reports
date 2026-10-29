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

## M5: the remaining apps, cold and auth arms only (2026-10-29)

**Scope change (from the user, mid-task): no crawler.** A concrete crawler (`crawl.py`: links and
forms from the real app on the 7.4 judge, logged out and in) had been started. On the instruction
that ACE must find its inputs itself, it was deleted before it ran or was committed. Every app
below is run with the **cold** arm (bare URL) and the **auth** arm (the app's own login request,
from its RUNLOG credentials), nothing else. Where reaching a sink needs a value only a crawl (or
the DB) would supply, the miss says so.

### Engine changes (`php-runtime/real-apps`; each off by default or a bug fix, each with tests)

| commit | change | flag |
|---|---|---|
| `30d9978` | **E7** `newClassMap` instrumentor option: `new PDO`/`new mysqli` (FQ, global, or `use`-imported) -> a harness subclass; `Runtime::$locationSkipFiles` so the stand-in's events are located at the app's call | option (off) |
| `dfbe9fa` | **bug fix:** `$x instanceof Alias` in a named namespace was rewritten to the unresolved string `'Alias'` (always false; OpenEMR's Symfony kernel threw). Now `Alias::class`; unchanged outside named namespaces | fix |
| `073ccf6` | `Runtime::$templateSplit`: under realAppBuiltins a 2-arg `explode` becomes `\__explode`; with the flag, `explode($sep, Template)` keeps the template's input parts (ADOdb's bind emulation splits every statement at `?`) | runtime flag (off) |
| `27caf7f` | **E2** `token_get_all7`: PHP 8's single name tokens split into 7.x T_STRING/T_NS_SEPARATOR runs (Doctrine annotations found no `use` imports: "@Table was never imported") | php7Compat |
| `66cec72` | **E2** `sig7`: a method overriding an INTERNAL class's method (Doctrine DBAL's `PDOConnection::query()`, `PDOStatement::fetchAll(...)`) gets a PHP 8-compatible signature (params untyped and optional, missing parent positions and a trailing variadic added) | php7Compat |
| `9031f76` | **two printing bug fixes:** (1) `"${name}"` / `"$a[key]"` interpolations were printed as `${name}` / `$a[key]` in code, i.e. the CONSTANTS `name`/`key` (PHP 8 Error; under php7Compat `__const7` had masked it, which inflated the earlier `const7` counts); (2) a multi-line `.` chain was reprinted on one line and moved every later line of the file (OpenEMR's EventAuditLogger.php by 36 lines); `__concat` now gets a third, ignored single-quoted argument holding the lost newlines | fix |
| `b60ea61` | realAppBuiltins: `hash_equals(concrete, symbolic)` is a recorded `===` (a CSRF token check the solver can now pass), not an E4 concretization | realAppBuiltins (off) |
| `ca7ad62` | **E2** `autoload7`: a declared `function __autoload` (compile-time fatal on PHP 8, even in a dead `if`) is renamed `__ace_autoload7` (WordPress 4.7 compat.php, WeBid's PHPMailerAutoload.php) | php7Compat |
| `568cf56` | `evalInstrument` option + `Runtime::$evalInstrument`: `eval(E)` -> `eval(\__ace_eval_src(E))`, instrumented at run time with the copy's targets and options (WeBid compiles its admin templates and evals them) | option + runtime flag (off) |
| `1c94b87` | realAppBuiltins: `serialize`/`json_encode`/`var_export`/`print_r`/`http_build_query` get their array argument concretized all the way down (`\__arg_deep`; WordPress `md5(serialize($query_vars))`) | realAppBuiltins (off) |
| `9e57246` | realAppBuiltins: a routed one-argument type predicate on a Template answers as for a string (`is_object` false, `gettype` 'string'; WordPress `map_deep`) | realAppBuiltins (off) |
| `84cf951` | **E2** `count7` inside namespaces too (`phpbb\session::sizeof(null)`) | php7Compat |
| `6d3e764` | realAppBuiltins: `sodium_memzero($v)` -> `\__memzero` (by reference; a symbolic password is nulled; OpenEMR 6 login) | realAppBuiltins (off) |

E2 fixtures (`fixtures/php7compat/{tokens,overrides,autoload,counting_ns}.php`) are each run uninstrumented on
php:7.4-cli and instrumented on 8.2; the outputs match.

### Harness changes (`report/symphp-benchmark`)
- `harness_db.php` (new, E7): `AcePDO extends PDO`, `AceMysqli extends mysqli`. `prepare/query/exec`
  (PDO) and `query/real_query/multi_query/prepare` (mysqli) are concrete targets `PDO::prepare`, ...:
  the note is published, the parent method runs on this run's text, an exception (PDO
  ERRMODE_EXCEPTION) is recorded in the summary and rethrown after the event. `drive.py
  --db-classes`; `FAMILIES` knows the 7 new sink names.
- `harness_php7.php` (new): PHP 7.4 functions PHP 8 removed (`get_magic_quotes_gpc`,
  `get_magic_quotes_runtime`, `each`, `create_function`), defined only when `php7Compare` is on.
- `drive.py`:
  - `--instance N` + `--shard i/n` + `--reuse-build` + `--skip-done`: parallel shards of one arm,
    each with its OWN ACE clone (`ace-<app>-<N>-db`, runner `ace-<app>-<N>-php`) that it resets per
    script (decision (a) unchanged).
  - `ace_build_at_src` (apps.json): for an app whose config names its own absolute path (WeBid's
    `$main_path`, OpenCart's `DIR_*`), ACE's runner mounts the instrumented copy at the source path
    and runs the app from there, so every include loads the copy. The copy is ACE's own, so it is
    mounted writable (OpenCart writes its logs there; the real source is not mounted at all). Without it WeBid ran
    almost entirely uninstrumented (found by a run with no SQL events at all).
  - `--site-by-statement`: one finding per (site, statement shape) instead of per site: WeBid's
    and OpenEMR's every query goes through ONE wrapper line (`DatabasePDO.php:76`,
    `adodb-mysqli.inc.php:773`).
  - `--template-split`, `--eval-instrument`; `php_exts` (apps.json, OpenEMR: `php,inc`) is passed
    to the instrumentor and to `exec_lines.php` (OpenEMR's `library/*.inc` were uninstrumented).
  - a crashed batch (an app exhausting memory) is a harness error for its requests, not the end of
    the run; a failed login is recorded for that script.
  - login: `pin_token` (below), nested `success_key`, `success_db_sql`.
- `judge.py`:
  - `judge_cgi: "xdebug"` (apps.json): the trace build `php-cgi-trace` has no PDO (WeBid, Drupal),
    no openssl (OpenEMR: `interface/globals.php` dies) and no curl (OpenCart's admin dashboard).
    Those apps' fault replays (and logins) run on `ace-judge-php74`'s php-cgi (7.4.33), with the
    coverage-only Xdebug prepend supplying `lines`. **Deviation:** the prepend is used on fault
    replays for these apps (it changes no app behaviour); their trace and Xdebug coverage are the
    same measurement.
  - `statement/com/Prepare` errors (server-side PREPARE, NULL SQL_TEXT) now count as SQL faults.
    Before, every PDO app with emulated prepares off could never fault.
  - `db.fault_exclude_errnos` (WeBid: 1055): an errno the app raises on bare requests with no input
    at all (`index.php`, ONLY_FULL_GROUP_BY in the installed sql_mode) is not a fault.
  - `login.pin_token` {key, value}: right after its own login each side sets the session's form/CSRF
    token (or the key it is derived from) to a fixed value of the same kind, in the session file
    (judge), the serialized seed (ACE), or the DB (`db_sql`, OpenCart 3). A POST carrying the token
    is then valid on both sides. Session STATE only. (WeBid `csrftoken`, OpenEMR `csrf_private_key`,
    OpenCart `token`/`user_token`.)
  - `--reset marked`: restore the snapshot before each request marked `reset` (score.py marks every
    ORACLE WITNESS); trace requests run in order on the state their predecessors left, logging in
    once per area, again after a restore or a logout-looking script. **Deviation from decision (a)**
    (per-request reset): WeBid's 24k and OpenEMR's tens of thousands of trace requests at 1-7 s per
    restore were infeasible. Every finding is still judged on the snapshot state.
  - `--instance`: parallel judge clones (`judge-<app>-<N>-db`); `score.py --judge-shards K` replays
    K contiguous slices in parallel and concatenates them in order.
  - Streaming: for a `judge_cgi xdebug` app each slice is written as compact JSON lines, one per
    request, as it is judged (covered lines per file), and a rerun resumes after the last complete
    line (the first resumed request is restored to the snapshot). A request that runs past 120 s is
    recorded as a no-fault result instead of ending the slice.
- `appdb.py`: instances; clone start-up waits up to 15 min (a loaded host).
- `apps.json`: `webid`, `openemr502`, `opencart2302`, `opencart3038`, `wordpress47`, `wordpress51`,
  `phpbb3110`, `drupal80`, `drupal90`, `mediawiki127`. Snapshots are read-only `mysqldump
  --single-transaction` of each installed database (`webid-mysql57`, `emr502-mysql57` root/root,
  `oc2302-mysql57`, `oc3038-mysql57`, and the `phpbb3110`, `wordpress47/51`, `drupal80/90`, `mw127`
  databases of `ace-judge-mysql`); none was written.

**Load.** The cold and auth arms of several apps, and later up to 15 judge slices, ran
concurrently on the 8-core / 32 GB host (load average 10-30; one stretch of IO thrashing at 70
before the judge was made to stream, see "Incidents"). Every `--budget` is wall-clock, so
per-script exploration under load is less than the same budget on an idle host.

### Per app

#### phpMyAdmin 4.7.0 (`phpmyadmin`), cold and auth, no crawl
- **Arms:** `m5_cold` (budget 30 s/script) and `m5_auth` (90 s/script; root with an empty password,
  the two-step cookie login of M2), all 86 entry scripts. Flags: `--php7compat --exit-as-halt
  --concretize --array-mode --real-app-builtins --sanitizers --xss`. **Note:** `m5_cold` was
  instrumented before, and `m5_auth` after, the instanceof/interpolation/line fixes (`dfbe9fa`,
  `9031f76`), which both touch phpMyAdmin's namespaced code; the two arms ran different copies.
- **Wall time:** 2517 s (cold) + 7477 s (auth) of exploration, sequential, ~2.8 h. Budget hit by 83
  of 86 scripts in both arms.
- **Explored:** cold 6145 traces / 6231 requests; auth 5939 / 6390. **Every script spends its budget
  in the shared bootstrap** (`libraries/common.inc.php`): the same 18 GET/POST keys are discovered
  for every script (`lang`, `set_theme`, `collation_connection`, `server`, `db`, `table`,
  `sql_query`, `token`, ...), 5277 of 5939 auth traces end at an `exit` there, and script-specific
  parameters (`username` for `server_privileges.php`, `where_clause` for `tbl_get_field.php`) are
  rarely or never reached.
- **Run errors (80 scripts per arm):** two PHP 8 TypeErrors where 7.4 only warned:
  `key(): Argument #1 must be of type array, string given` and `mysqli_real_connect(): Argument #4
  ($password) must be of type ?string, array given`. Neither builtin is in E2's `call7` list; adding
  them would keep those traces alive. Harness errors: none.
- **ACE findings: 0.** The judge saw 328 faulting requests among ACE's trace requests (1064 on
  `SHOW TABLE STATUS FROM ` / `SHOW TABLES FROM ` with an empty `db`, `SHOW ALL SLAVES STATUS`), none
  on a known sink line, and none of them was flagged by the oracle (sqlglot accepts these SHOW
  forms).
- **Score** (`score.py phpmyadmin ace:m5_cold+m5_auth --coverage xdebug --reset marked
  --judge-shards 3`): **0 found / 2 reachable-in-model / 10 total.**
  - Reachable in the model: PMA470-3, PMA470-4 (`server_privileges.php`, GET `username`/`hostname`,
    admin, confirmed-in-code). **Missed: budget/search order** (the bootstrap above) plus the
    `key()` TypeError cutting traces short.
  - Need a database or table NAME that exists (decision (c), DB values; a crawl would have supplied
    `db=pma47&table=items`, the user ruled crawls out): PMA470-1 (`db_central_columns.php`), -6, -7
    (`tbl_zoom_select.php`), -8 (`tbl_get_field.php`), -9 (`transformation_wrapper.php`, also a DB
    row), -10 (`tbl_create.php`). ACE does discover `db` and `table`, but `selectDb()` only succeeds
    on a real name, and that name is DB content no branch in the code compares against.
  - Outside the input model: PMA470-2 (the value is inside the encrypted `pmaUser` cookie / pmadb),
    PMA470-5 (the injected value is the current MySQL user name, read from the DB).
  - By confidence: confirmed-in-code 0/8, likely 0/2.
- **Coverage:** trace 7.63% (12343/161802), Xdebug 7.03%; per arm cold 1.52%, auth 7.57%.
- **E2 (static, auth copy):** const7 1605, call7 722, count7 583, switch 345, curly_offset 131,
  nested_ternary 1, sig7 2, token_get_all7 7. Runtime fallback counters are unreliable for
  phpMyAdmin (it unsets the `$GLOBALS` counters, M2 note); they read 0.

#### WeBid 1.2.1 (`webid`, the `src/` tree under `apps/webid-1.2.2/`)
- **Arms and labels** (flags: `--php7compat --exit-as-halt --concretize --array-mode
  --real-app-builtins --sanitizers --xss --db-classes --site-by-statement`; budget 60 s/script; two
  shards per arm, each on its own ACE clone):
  - `m5_cold`, `m5_auth`: all 178 entry scripts (68 top-level + 110 `admin/`). Auth logs in per
    script with the recipe for its path: `admin/` -> admin/Admin12345, else seller1/Passw0rd!
    (RUNLOG section 4); the session `csrftoken` is pinned on both sides.
  - `m5b_cold`, `m5b_auth`: the 2 + 4 scripts that hit the PHP 8 `__autoload` compile fatal
    (PHPMailerAutoload.php, sending mail), re-run after E2 `autoload7` (incl. `admin/excludeuser.php`).
  - `m5c_auth`: the 110 `admin/` scripts again, with `--eval-instrument`. WeBid compiles admin
    templates and runs them with `eval()` (`includes/template/Template.php:163`), so in `m5_auth`
    every admin page's output was uninstrumented (E4 "string conversion ... eval()'d code").
- **Wall time:** m5_cold 1221 s, m5_auth 5390 s, m5b 368 s, m5c 4772 s of per-script exploration
  (sums over scripts; shards ran in parallel on a loaded host). Budget hit: 6 / 58 / 6 / 55 scripts.
- **Explored:** m5_cold 6058 traces / 6576 requests; m5_auth 24174 / 31510; m5c 15464 / 20040.
- **Harness errors:** none (0 crashed batches, 0 failed logins in the final runs). Run errors
  (the app's own, on PHP 8 or under symbolic values), in 22 of 178 auth scripts, e.g. `Iteration over
  symbolic values is not modelled` (5), `in_array()` on a string (3), the `__autoload` fatal (3,
  re-run as m5b), `Illegal offset type` (2), `fputs(false)` (2), `Cannot redeclare build_keyword_sql()`
  (send_email/feedback include a file twice under ACE's include path), `imagecreate()` undefined (the
  ACE image has no gd; captcha only).
- **ACE findings:** m5 union 48 sites, **44 judge-confirmed** (16 SQL injectable at
  `DatabasePDO.php:76/:53`, the `yourauctions*` `ORDER BY` and `admin/searchauctions.php`; 32 XSS
  candidates, 28 confirmed structurally). m5c: 42, **39 confirmed**. The 7 unconfirmed are XSS
  candidates whose marker is HTML-escaped or not re-emitted on the 7.4 replay
  (`adminpages.tpl.php:49` via `admin/analytics.php`/`spam.php`, `confirm.php`'s `id`/`hash`,
  `admin/userbanners.php` `keywords`).
- **Score** (`score.py webid ace:m5_cold+m5b_cold+m5_auth+m5b_auth --coverage xdebug --reset marked
  --judge-shards 4`, and `ace:m5c_auth` likewise):
  - m5 union **7/11**: WB-1..5 (SQLi, user, confirmed-in-code), WB-6, WB-7 (reflected XSS, none);
    cold alone 2/11 (WB-6, WB-7), auth 7/11.
  - m5c **3/11**: WB-8, WB-9, WB-10 (admin XSS through eval'd templates).
  - **All arms together: 10/11 found / 11 reachable-in-model / 11 total**, all `confirmed-in-code`;
    CVEs 3/3 (CVE-2018-1000867, -1000868 by m5; CVE-2019-11592 by m5c).
  - **WB-11 missed** (`admin/edituser.php:251`, `offset`): the page first does
    `$userid = intval($_REQUEST['userid'])` and exits unless `$userid > 0`. Under E4 `intval` of a
    symbolic string is CONCRETIZED, so that branch is on a concrete value and no request with a
    positive `userid` is ever proposed (147 traces, all halted at the redirect). A modelled
    string-to-int conversion would reach it; this is an engine limitation, not a budget one.
- **Coverage:** m5 union trace 39.08% (9036/23119) = Xdebug (fault replays under Xdebug); per arm
  m5_cold 20.87%, m5_auth 36.75%. m5c alone 25.88%. (The two scores are separate judge runs; the
  slim replays keep only scored lines, so their union coverage is not computed.)
- **Judge:** 29464 requests in 4 shards for m5 (about 45 min per slice; one slice re-run after the
  AIO failure below, and the merge re-run after the out-of-memory fix); 14968 for m5c. 987 faulting requests (m5): SQL 1064 on the `ORDER BY`
  injections and app bugs such as `admin/newadminuser.php`'s 1136 (column count).
- **E2 rewrites (static):** const7 425, call7 184, count7 295, switch 78, curly_offset 3,
  nested_ternary 2, autoload7 1 (m5b/m5c), new_class 2 (E7), explode 77 (m5b/m5c), eval 3 (m5c).
  **Fired at runtime:** cmp7 1929, count7 353, arith7 174 (m5_auth); call7 `implode` 194 (m5b);
  const7 0.
- **New flags/deviations used here:** E7 `--db-classes`, `--site-by-statement`, `ace_build_at_src`,
  `judge_cgi xdebug`, PREPARE faults, `fault_exclude_errnos [1055]`, `pin_token csrftoken`,
  `--reset marked`, `--eval-instrument` (m5c), `autoload7`.

#### OpenEMR 5.0.2 (`openemr502`)
- **Arms:** cold (budget 10 s/script) and auth (30 s/script; admin/pass, the app's own
  `main_screen.php?auth=login` POST), all 1238 `.php` files at the top level and under `interface/`
  and `library/`; 3 shards per arm. Flags `--php7compat --exit-as-halt --concretize --array-mode
  --real-app-builtins --sanitizers --xss --site-by-statement --template-split`; `php_exts php,inc`.
- **What it took to run on PHP 8 (engine):** `instanceof` name resolution (Symfony kernel),
  `token_get_all7` (Doctrine annotations), `sig7` (Doctrine DBAL's `PDOConnection::query()`), the
  `${name}` interpolation fix (`EventAuditLogger.php` used `"audit_events_${event}"`), the multi-line
  concat line fix, `hash_equals` modelling (the CSRF check), `templateSplit` (ADOdb's `?` binding
  splits every statement); harness: `.inc` files instrumented (`library/*.inc`, e.g. patient.inc),
  `judge_cgi xdebug` (no openssl in php-cgi-trace), `pin_token csrf_private_key` (the CSRF token is
  an HMAC of a random session key), `cookies_from_login` (session.use_strict_mode replaces the fixed
  session id), `--reset marked` (10 MB snapshot, 7 s per restore).
- **Wall time:** cold 2417 s, auth 16949 s of per-script exploration (3 shards each, ~3.5 h
  elapsed for auth on the loaded host). Budget hit: cold 4, auth 481 of 1238.
- **Explored:** cold 6584 traces / 6635 requests (logged out, every page stops at the login check;
  with `site=A` it dies on a missing `sites/A/config.php`, the app's own behaviour); auth 38028 /
  44682. Keys are discovered as intended, e.g. `patient_select.php`: `searchFields`, `findBy`,
  `patient`, `fstart`, `csrf_token_form`, ...
- **Harness errors:** 2 (cold) and 11 (auth) crashed batches (`sql_patch.php`, `standard_tables_
  manage.php`: the app exhausting the process); 7 auth scripts whose login fell in the harness
  breakage window were re-run. Run errors are mostly the app's own: files that are only included
  (`Interface "AmcFilterIF" not found` 76, `CqmFilterIF` 72, `AbstractAmcReport` 38, Zend MVC classes
  23, `xlt()` undefined 19).
- **ACE findings:** 19 sites (11 malformed-at-reach in billing payments through ADOdb, 8 XSS
  candidates: `eye_base.php:372` providerID, `patient_match_dialog.php:55` key,
  `add_template.php:59` list_id, `left_nav.php:1225/1230`, `dataloads_ajax.php:135/169`,
  `a_issue.php:1361`).
- **Score** (`score.py openemr502 ace:m5_cold+m5_auth --coverage xdebug --reset marked
  --judge-shards 6`, 42848 requests, 435 faulting): **3 found / 17 reachable-in-model / 28 total.**
  Cold 0, auth 3: **OE502-6** (SQLi, `library/custom_template/ajax_code.php` `multi`), **OE502-7**
  (SQLi, `eye_base.php` `providerID`), **OE502-23** (XSS, `eye_base.php:372` `providerID`). By
  confidence: confirmed-in-code 2/21, likely 1/6, unverified 0/1. Findings **15/19 judge-confirmed**.
- **Coverage:** 5.87% (33531/571131, all `.php`/`.inc` incl. `vendor/`) = Xdebug; cold 1.29%,
  auth 5.87%.
- **Outside the input model (11):** array-valued parameters (OE502-1 `form_sel_layouts[]`/
  `form_sel_lists[]`, -2 and -3 `form_code[]`, -5 `schedule_facility[]`, -9 `provider_id[]`; ACE's
  inputs are `str?`), a stored clinical rule (-8), a parameter NAME `mf_<name>` (-10), REQUEST_URI
  (-24), -28 (unverified, no sink line), and -12, -13: the injected `sort` is a value, but
  `controller.php` picks its controller from the NAME of the first query key
  (`Controller::act`: `array_keys($_GET)`, `?prescription&list`), so the route itself is a
  parameter name.
- **Why the 14 in-model misses were missed:**
  - Budget (30 s, 481 scripts hit it) before the parameter was even discovered or its branch taken:
    -4 (`searchFields`; a 120 s test run did discover it), -14/-27 (`graphs.php` `name`/`title`),
    -15 (CAMOS `content`), -21 (`messages.php` needs `go=setup` first), -26 (`target`).
  - Module routing not reached within the budget: -11, -18 (`calendar/index.php` needs
    `module=PostCalendar&type=admin&func=categoriesUpdate|categoriesConfirm`, read through
    `pnVarCleanFromInput`; `module`/`func`/`type` were not among the discovered keys, and all 94
    traces end at an `exit` earlier in the page).
  - Discovered but no output event of it within the budget: -19 (`form_status`), -20
    (`pricelevel`), -22 (`list_id` in `share_template.php`; the same parameter IS flagged in
    `add_template.php:59`), -25 (CAMOS `hidden_*`).
  - -16 (`eye_mag/view.php` `pid`/`id`): ACE's runs die at `Call to undefined function
    redirector()` before the echo.
  - -17 (`patient_match_dialog.php:55` `key`): **flagged by ACE, not confirmed.** The value lands
    inside a JavaScript string (`var ename = '<?php echo addslashes(...) ?>'`); the structural XSS
    marker (`"'><acexss..>`, decision (f)) stays script text for html5lib. Breaking out needs
    `</script>`, which the marker does not contain.
- The 4 unconfirmed findings: -17 above, `add_template.php:59` (`list_id`, the same JS-string
  shape) and `dataloads_ajax.php:135/169` (`aas`, not re-emitted on the 7.4 replay).
- **E2 (static):** const7 2689, call7 1251, count7 1182, switch 1617, curly_offset 2883, sig7 41,
  token_get_all7 7, explode 868. **Fired at runtime (auth):** arith7 3948, cmp7 779, count7 85,
  call7 `implode` 4.

#### OpenEMR 6.0.0 (`openemr600`), auth arm time-boxed
- Same configuration as 5.0.2 (port 3371, `openemr600`); 1218 scripts. One more engine change was
  needed for its login: `sodium_memzero` of the symbolic password (`\__memzero`).
- **Cold:** all 1218 scripts (10 s), 6511 traces / 6550 requests, 3367 s.
- **Auth (time box):** stopped at 10:45 UTC after **487 of 1218 scripts** (15 s budget, 2 shards,
  6169 s of exploration): the top-level scripts and `interface/` up to about `interface/forms/...`
  in each shard's alphabetical slice. 12616 traces / 13085 requests; 7 sink sites.
- **Score** (`score.py openemr600 ace:m5_cold+m5_auth ... --judge-shards 4`, 18233 requests, 197
  faulting): **0 found / 13 reachable-in-model / 19 total** (confirmed-in-code 0/14, likely 0/5);
  findings **6/7 judge-confirmed** (6 malformed-at-reach SQL, all off the known sink lines; the
  unconfirmed one is `patient_match_dialog.php:55`, the JS-string case of OE502-17 = OE600-8).
  - Not explored at all because of the time box: OE600-6, -13, -16, -17, -19 (5 of the 13).
  - Outside the model (6): OE600-1 and -18 (array-valued), -2 (parameter NAME), -14 (REQUEST_URI),
    -4 and -5 (`controller.php` routes on a parameter NAME, as in 5.0.2).
  - The rest: the same reasons as their 5.0.2 counterparts (budget at 15 s; PostCalendar and
    `controller.php` routing; the JS-string reflection).
- **Coverage:** 3.48% (19549/561736) = Xdebug; cold 1.02%, auth (partial) 3.39%.
- **E2 (static):** const7 2496, call7 1180, count7 6550, switch 1523, curly_offset 1, sig7 11,
  token_get_all7 5, memzero 5, autoload7 1. **Fired at runtime (auth):** arith7 1381, cmp7 1028,
  count7 43, call7 `implode` 4.

#### OpenCart 2.3.0.2 (`opencart2302`)
- **Arms:** cold (`index.php`, `admin/index.php`), auth (`admin/index.php`, admin/admin; the session
  `token` pinned). Budget 300 s/script; wall 5 s (cold) and 3 s (auth): exploration ran dry.
  Flags: `--php7compat --exit-as-halt --concretize --array-mode --real-app-builtins --sanitizers
  --xss --db-classes --site-by-statement`.
- **Harness work needed:** `ace_build_at_src` (absolute `DIR_*` in config.php), `ace_real_session`
  (its `Session\Native extends SessionHandler`, whose `create_sid()` needs an ACTIVE PHP session),
  a WRITABLE mounted copy (its logger `fopen`s `storage/logs`; on PHP 8 `fclose(false)` is a
  TypeError), `judge_cgi xdebug` (no curl in php-cgi-trace). 0 harness errors in the final runs.
- **Explored:** 10 + 6 traces. **Keys discovered: none in GET/POST** (cookies `PHPSESSID`,
  `default` only). **Routing blocks it:** OpenCart never reads `$_GET`/`$_POST` directly. The
  `Request` constructor COPIES them (`$this->get = $this->clean($_GET)`, a `foreach`), and the
  router reads `$this->request->get['route']` from the copy. Array mode discovers a key only on a
  direct superglobal read (`\__sg_key`), so `route` (and every controller's parameter) is never
  declared. Without `route` the front controller always dispatches `common/home`
  (admin: `common/login` / `common/dashboard`), whose branches are all on DB state.
- **Findings:** none. **Score: 0/1 (0 reachable-in-model).** OC2302-1 (`backup[]`, admin
  `tool/backup`) is outside the input model: an ARRAY-valued POST parameter (ACE's inputs are
  `str?`), and its route is unreachable for the reason above.
- **Coverage:** 1.65% trace = 1.65% Xdebug (1469/88916; the fault replays ran under Xdebug).
- **E2 (static):** const7 3270, call7 402, count7 66, switch 54, sig7 10, curly_offset 1, explode
  175, new_class 2. **Runtime fallbacks:** none fired.

#### OpenCart 3.0.3.8 (`opencart3038`)
- Same arms, budget and flags. Sessions live in the DB (`oc_session`, JSON), so the login is checked
  with `success_db_sql` and `user_token` is pinned with an UPDATE on each side's clone.
- **Explored:** 10 + 4 traces; **no GET/POST key discovered** (same `Request::clean` copy).
- **Score: 0/1 (0 reachable-in-model)**: OC3038-1 is the same array-valued `backup[]` admin route.
- **Coverage:** 1.73% (2402/138564), Xdebug the same. E2 static: const7 2845, call7 447, count7 490,
  switch 146, curly_offset 6; runtime fallbacks none.

#### phpBB 3.1.10 (`phpbb3110`)
- **Arm:** cold only, all 16 top-level front scripts, budget 120 s. (No auth arm: phpBB's login
  needs a form key derived from the session and `creation_time`; with no key discoverable, an auth
  arm would explore nothing more.)
- **Engine work needed:** E2 `count7` inside namespaces (`phpbb\session::sizeof(null)`).
- **Explored:** 16 traces, one per script; **no key discovered**. **Blocked by the request
  abstraction:** `\phpbb\request\request` copies the superglobals and then DISABLES them
  (`disable_super_globals()` replaces `$_GET`... with objects that refuse access); every parameter
  is read through `$request->variable()` from the copy, so no direct read exists to discover.
- **Score: 0/1 (0 reachable-in-model):** PHPBB3110-1 is injected through a POST parameter NAME
  (`login_link_*`), outside the input model by design (decision (d)).
- **Coverage:** trace 0.44% (392/89207), Xdebug 2.62% (the trace build and Xdebug disagree here:
  the trace build records far fewer lines for phpBB's bootstrap).
- E2 static: const7 3275, call7 898, count7 1288, switch 377, sig7 2, token_get_all7 2; runtime
  fallbacks count7 42, call7 `array_key_exists` 42.

#### Drupal 8.0.0 / 9.0.0 (`drupal80`, `drupal90`): **blocked (PHP 8 class hierarchy)**
- **Arm:** cold, `index.php` (routing is by request PATH, which the input model does not cover).
- Both stop at bootstrap, before any request is handled, on ACE's PHP 8.2 runtime:
  - **9.0.0:** `Statement extends \PDOStatement implements StatementInterface`; PHP 8's typed
    `PDOStatement::fetch(int $mode = PDO::FETCH_DEFAULT, ...)` no longer satisfies
    `StatementInterface::fetch($mode = NULL, ...)`: fatal on class declaration (Drupal supports PHP
    8 only from 9.1).
  - **8.0.0:** declaring the same `Statement` raises a deprecation during inheritance, which PHP 8
    passes to `_drupal_error_handler` with 4 arguments; the handler requires 5 (`$context`, removed
    in PHP 8): `ArgumentCountError`, fatal.
  - What it would take: an E2 rewrite that synthesizes 7.x-compatible overrides for inherited
    internal methods and makes a 5-parameter error handler's last parameter optional. Time-boxed
    out; both are semantic rewrites of the ACE copy that the user has not approved.
- Fixes on the way that ARE in: preloading the runtime's classes before the app (Drupal prepends a
  composer autoloader that compares class names via `\__cmp`, which needed `Concolic\Z3` from
  inside the autoloader); a writable copy (`sites/default` read-only); `judge_cgi xdebug` (PDO).
- **Score:** 8.0.0 **0/3**, 9.0.0 **0/2**, all outside the input model (REQUEST_URI reflected as a
  form action; a request-derived exception message; a stored admin setting reaching `mail()`).
- **Coverage** comes from the judge replaying ACE's 2 bare requests on the real 7.4 Drupal, which
  renders the front page: 8.0.0 3.79% (12096/318751), 9.0.0 2.87% (12553/437556), Xdebug the same.

#### MediaWiki 1.27.7 (`mediawiki127`, 0 known vulns: coverage only)
- **Arm:** cold, `index.php`, `api.php`, `load.php`, budget 300 s. (No auth arm: there is nothing to
  score, and the time went to the apps with known vulns.)
- **Harness work needed:** `ace_session_id_before_start`: MediaWiki validates `session_id()` when it
  is non-empty, and the M1 stand-in answered `'acesession'` before any session was started (PHP
  answers `''`): `InvalidArgumentException: Invalid session ID` on every index/api request.
  Opt-in per app; the older apps keep the old stand-in. Dumps with binary blobs: `appdb` now
  restores snapshots as bytes.
- **Explored:** index.php 97 traces / 99 requests, api.php 88 / 92 (both hit the budget),
  load.php 4. Keys discovered (GET, and the same in POST): `action`, `debug`, `forceHTTPS`, `lang`,
  `modules`, `only`, `skin`, and the session cookies (`mw127_session`, `mw127UserID`,
  `mw127Token`), i.e. what `WebRequest` reads directly from the superglobals during setup.
  `title` and the action modules' parameters are not reached within the budget: `index.php`
  without a title renders the main page, and every trace spends its time in setup branches.
- **Findings:** none. **Score 0/0.** **Coverage:** 5.47% trace (12091/221088), Xdebug 5.42%.
- E2 static: const7 9426, call7 3061, count7 1790, switch 406, curly_offset 22, sig7 3,
  token_get_all7 4.

#### WordPress 4.7 (`wordpress47`) and 5.1 (`wordpress51`)
- **Arms:** cold and auth, all 97 entry scripts (the 15 top-level `.php` and `wp-admin/*.php`),
  budget 60 s/script; flags `--php7compat --exit-as-halt --concretize --array-mode
  --real-app-builtins --sanitizers --xss --site-by-statement`. Auth: `wp-login.php` with
  admin/admin123 (RUNLOG) and the test cookie; WordPress keeps no PHP session, so ACE and the
  judge each use the auth cookies of their OWN login; a marker cookie `ace_auth=1` (ignored by
  WordPress) tells the judge which requests to log in for. 4.7 ran on one process per arm, 5.1 on
  two shards per arm.
- **Engine/harness work needed** (all found on 4.7): `harness_php7.php` (`get_magic_quotes_gpc()`
  is gone in PHP 8, and `wp_magic_quotes()` calls it on every request), E2 `autoload7`
  (`compat.php` declares `__autoload`), `__arg_deep` (WordPress hashes
  `md5(serialize($this->query_vars))` with request values inside), Template-aware type
  predicates (`map_deep()` asked `is_object()` of a templated string and called
  `get_object_vars()` on it).
- **Explored (4.7):** cold 8946 traces / 9208 requests, auth 8046 / 8595; budget hit by 75 and 76
  of 95 scripts; 8443 and 7106 traces halted (WordPress ends most admin requests with `exit`/
  `wp_die`). **(5.1):** cold 6669 / 6700, auth 6922 / 7221.
- **Key discovery works:** WordPress reads the superglobals directly. On `index.php` alone ACE
  declares 53 query keys (`p`, `s`, `cat`, `page_id`, `rest_route`, `preview`, `feed`, ...), and
  on `wp-admin/upload.php` `mode`, `s`, `post_id`, `action`, `taxonomy`, ...
- **Run errors:** 7-8 scripts per arm, all the app's own: files meant only to be included
  (`Call to undefined function __()/get_option()/apply_filters()`, `ABSPATHwp-includes/load.php`).
  Harness errors: none after the re-run of the 30 scripts caught by a 2-minute harness breakage
  (see "Incidents").
- **ACE findings: 0** in both versions and both arms. WordPress builds every statement with
  `$wpdb->prepare()` (`vsprintf` over escaped arguments) and rewrites clauses with `preg_replace`;
  both are unmodelled builtins whose symbolic argument is CONCRETIZED (E4), so the statement that
  reaches `mysqli_query` carries no `$$(ref)` and the oracle has nothing to inject into. Output
  goes through `esc_html`/`esc_attr` (`_wp_specialchars`, `wp_check_invalid_utf8`, `strtr`), also
  concretized, so no XSS candidate survives either.
- **Known vulns:**
  - WP47-1 / WP51-1 (SQLi, `s` in the media-library list mode / REST `search`; in the input model):
    **missed.** The search term goes through `$wpdb->prepare`/`esc_like` and then
    `_filter_query_attachment_filenames()`'s `preg_replace` over the WHERE clause, both concretized,
    so the oracle never sees the input in the statement; and exploration values (`''`, `'A'`) never
    contain the `'` that breaks the regex rewrite. 5.1's unauthenticated path additionally needs
    `rest_route=/wp/v2/media`, a value matched by `preg_match` against the registered routes
    (concretized, so not solvable).
  - WP47-2 / WP51-2 (XSS through an uploaded file NAME, `$_FILES`): outside the input model.
  - WP47-3 (XSS through `customized` JSON in the customizer preview, admin, likely): in the model as
    a string, but the value is `json_decode`d (concretized) and rendered by a theme setting; missed.
- **Score** (`score.py wordpressNN ace:m5_cold+m5_auth --coverage xdebug --reset marked
  --judge-shards 3`; fault replays under the Xdebug prepend, streamed):
  - **4.7: 0 found / 2 reachable-in-model / 3 total** (confirmed-in-code 0/2, likely 0/1);
    15859 requests, 0 faulting. Coverage 19.56% (20951/107100) = Xdebug; cold 8.78%, auth 19.55%.
  - **5.1: 0 found / 1 reachable-in-model / 2 total** (confirmed-in-code 0/2); 12981 requests,
    0 faulting. Coverage 20.26% (23427/115658) = Xdebug; cold 9.00%, auth 20.24%.
- **E2 (static, 4.7 / 5.1):** const7 4154 / 4312, call7 2142 / 2525, count7 483 / 527, switch
  410 / 430, curly_offset 149 / 153, autoload7 1 / 1, token_get_all7 1 / 1. **Fired at runtime:**
  cmp7 12569 (4.7 cold) / 2633 (4.7 auth) / 3135 / 1025; const7 `DB_*` x132 and `ABSPATH` x1 (4.7:
  scripts run without `wp-config.php` loaded); count7 8.

### Incidents during M5 (all recovered; recorded so the numbers can be read correctly)
- **Kernel AIO limit.** With a dozen MySQL clones up, new ones failed `InnoDB: io_setup() failed
  with EAGAIN` (`fs.aio-max-nr` 65536 reached; the host setting was not changed). Two drive runs
  and one judge shard died waiting for their DB. Fixed by starting every NEW clone with
  `--innodb-use-native-aio=0` and stopping idle containers; the failed containers were recreated.
- **A crashed batch ended a shard** (OpenEMR `sql_patch.php`, `standard_tables_manage.php`: the
  app exhausting the PHP process). `drive.py` now records such a batch as harness errors and goes
  on; the dead shards were resumed with `--skip-done`.
- **A 2-minute harness breakage (~07:24 UTC).** A first version of the runtime-class preload in
  `harness_app.php` also loaded the instrumentor (which needs PhpParser), so every request in that
  window crashed. The scripts it hit (17 WordPress 4.7 cold, 13 auth, 7 OpenEMR 5.0.2 auth, 1
  OpenEMR 6 test) were found from their summaries (`no result (crashed)` / `login failed`), deleted
  and re-run under the same labels.
- **Scoring ran out of memory** on WeBid's 29k replays (3.5 GB of per-request line lists). Scoring
  now streams the replay slices, accumulates coverage on the way, and keeps a SLIM replay with only
  the lines it scores; judge slices are gzipped.
- **`score.py` checked XSS findings against SQL faults** (a pre-M5 bug: every XSS finding was
  "unconfirmed"). Fixed; WeBid's findings went from 16/48 to 44/48 confirmed on the same replay.
  HSM's M4 figure (98/101) was computed with the bug; its re-score below uses the fix.
- **Disk.** Free space fell to 16-17 GB (the floor is 15 GB). Finished instrumented copies were
  deleted, finished apps' dumps gzipped (`score.py` reads both), and judge output compressed.

### No-regression checks (end of M5)
- **PHP runtime suite:** `php tests/run.php` (php:8.2-cli) **174 tests, 726 assertions, 0 failed**
  (was 161/683). New: E7, instanceof, templateSplit, hash_equals, eval instrumentation,
  `__arg_deep`, Template type predicates, memzero, interpolation and line-keeping printing tests,
  and the php7compat fixtures `tokens`, `overrides`, `autoload`, `counting_ns` (7.4 output == 8.2
  instrumented output).
- **Python `concolic/model/tests`:** **422 passed, 3 skipped** (unchanged).
- **Witcher-Test, every flag off:** `drive.py witcher-test --arm cold --label m5_regress_cold` +
  score: **7/7, 98.82% (84/85), 39 requests, 11 faulting, findings 7/7 judge-confirmed**: identical
  to every earlier milestone.
- **WebChess** (`m5r_cold` + `m5r_auth`, the M1/M2 flags, budget 600 s, fresh clone instance `r`):
  **9/10** (cold 6, auth 9; WC-9 missed, as before), findings **59/60 judge-confirmed**, coverage
  trace **52.43%** (1004/1915), Xdebug **50.91%**, 3173 requests: identical to M2.
  **A pre-M5 harness regression found here:** the first re-run gave `chess.php` ONE trace instead of
  M2's 1782. `chess.php` starts its session only `if (!isset($_SESSION))`, and the harness defines
  `$_SESSION = []` before the app runs, so the logged-in seed (restored by the `session_start`
  stand-in since the phpMyAdmin work of M2) never arrived and every request stopped at "Session
  timed out". WebChess's M2 run predates that change; nothing re-ran WebChess afterwards. Fixed
  behind the per-app flag `ace_session_unset_before_start` (as in PHP, `$_SESSION` does not exist
  until `session_start`); on for WebChess only, so the other apps' scored runs are unaffected
  (phpMyAdmin's ErrorHandler and WordPress's load.php test `isset($_SESSION)` in other places).
  `chess.php` and `sessioncheck.php` were re-run with it in both arms, and `mainmenu.php` (the one
  budget-bound script) was re-run once the host was idle.
- **HSM** (`m5r_cold` + `m5r_auth`, the M4 flags): **29/29**, findings **98/101 judge-confirmed**,
  coverage **29.13%** (990/3399), Xdebug **29.33%**: identical to M4.

### State at hand-off (M5)
- Headline (judge-replayed on uninstrumented PHP 7.4, see `results/ACE_SUMMARY.md`): WebChess 9/10
  and HSM 29/29 (re-scored, unchanged), Witcher-Test 7/7, WeBid 10/11,
  OpenEMR 5.0.2 3/28, phpMyAdmin 0/10, OpenEMR 6.0.0 0/19 (auth time-boxed), OpenCart 0/1 and 0/1,
  phpBB 0/1, WordPress 0/3 and 0/2, Drupal 0/3 and 0/2 (blocked on PHP 8), MediaWiki 0/0.
- Containers: every `ace-*` / `judge-*` container of this milestone is STOPPED, not removed (the
  ones that failed on the AIO limit were recreated). Installed app databases were only read.
- Raw dumps of scored runs are gzipped in place (untracked); `score.py` reads both forms. The
  slim replays (`results/<app>/replay_*.json`) and the `.jsonl` judge slices stay untracked.
- **DEFAULTs and deviations to confirm (new in M5):**
  - E7 `newClassMap` + `harness_db.php` (object-style PDO/mysqli sinks);
  - E2 extensions `token_get_all7`, `sig7`, `autoload7`, `count7` in namespaces; `harness_php7.php`
    polyfills;
  - realAppBuiltins extensions: `hash_equals` as equality, `__arg_deep`, Template type
    predicates, `__memzero`; `templateSplit`; `evalInstrument`;
  - two printing bug fixes and the instanceof fix (they change instrumented output for every app,
    e.g. phpMyAdmin's cold and auth arms ran on different copies);
  - harness: `ace_build_at_src` with a WRITABLE copy, `ace_real_session`,
    `ace_session_id_before_start`, `ace_session_unset_before_start` (WebChess), runtime-class
    preload, `--site-by-statement`, shards/instances;
  - judge: `judge_cgi xdebug` for every M5 app (fault replays under the coverage prepend), PREPARE
    faults, `fault_exclude_errnos` (WeBid 1055), `pin_token`, `--reset marked` (witnesses on a fresh
    snapshot, other requests in order without reset), `--instance`/`--judge-shards`, streamed
    replays, timeouts recorded as no-fault results;
  - scoring: XSS findings confirmed by XSS faults (bug fix), array-valued and route-by-name
    parameters counted as outside the input model.
