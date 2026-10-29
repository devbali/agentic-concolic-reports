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
