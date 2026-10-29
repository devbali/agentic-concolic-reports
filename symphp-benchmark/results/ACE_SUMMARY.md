# ACE on the SymPHP benchmark: summary (2026-10-29)

ACE (the Agentic Concolic Engine, branch `php-runtime/real-apps`) with the fixed driver
(`drive.py`), no crawler and no agent loop. Every number is from the concrete judge: ACE's requests
replayed on the UNINSTRUMENTED app under PHP 7.4 against a clone of the app's own database; a
known vuln counts as found when a replay faults (SQL statement error, shell syntax error, or a
structural XSS marker) AND passes the vuln's sink line. Details per app: `IMPLEMENTATION_LOG.md`
(M0-M5).

**Arms.** `cold`: the bare URL of every entry script. `auth`: the app's own login request (RUNLOG
credentials), then the same. ACE finds every other input itself (key discovery, branch flipping);
no crawl seeds (the user ruled them out).

**found / reachable / total.** `reachable` = known vulns whose tainted input is inside ACE's input
model (a GET/POST/COOKIE string value). Outside it: parameter NAMES (incl. routes chosen by a key
name), array-valued parameters, uploaded file names, REQUEST_URI, stored settings, DB rows,
encrypted cookies, entries with no sink line.

| app (known-vulns file) | arms | found / reachable / total | ACE findings judge-confirmed | coverage trace / Xdebug | notes |
|---|---|---|---|---|---|
| Witcher-Test | cold, all flags off | **7 / 7 / 7** | 7/7 | 98.82% / - | unchanged since M0 (`m5_regress_cold`) |
| WebChess 1.1.0 | cold + auth | **9 / 10 / 10** | 59/60 | 52.43% / 50.91% | identical to M2 (`m5r_*`); WC-9: budget/search order |
| HSM 2019 | cold + auth | **29 / 29 / 29** | 98/101 | 29.13% / 29.33% | identical to M4 (`m5r_*`) |
| phpMyAdmin 4.7.0 | cold + auth | **0 / 2 / 10** | 0 findings | 7.63% / 7.03% | 6 need an existing db/table NAME (DB value); budget spent in the shared bootstrap |
| WeBid 1.2.1 | cold + auth (+ admin re-run with eval instrumentation) | **10 / 11 / 11** | 44/48 and 39/42 | 39.08% / 39.08% (m5 arms) | WB-11: `intval` concretized; WB-8..10 need `--eval-instrument` |
| OpenEMR 5.0.2 | cold + auth | **3 / 17 / 28** | 15/19 | 5.87% / 5.87% | budget (30 s/script), module routing, a JS-string reflection |
| OpenEMR 6.0.0 | cold + auth (auth time-boxed: 487/1218 scripts) | **0 / 13 / 19** | 6/7 | 3.48% / 3.48% | 5 of the 13 in scripts the time box never reached |
| OpenCart 2.3.0.2 | cold + auth | **0 / 0 / 1** | 0 findings | 1.65% / 1.65% | routing blocks key discovery (`Request` copies `$_GET`); vuln is an array parameter |
| OpenCart 3.0.3.8 | cold + auth | **0 / 0 / 1** | 0 findings | 1.73% / 1.73% | same |
| phpBB 3.1.10 | cold | **0 / 0 / 1** | 0 findings | 0.44% / 2.62% | request object disables the superglobals; vuln is a parameter NAME |
| WordPress 4.7 | cold + auth | **0 / 2 / 3** | 0 findings | 19.56% / 19.56% | `$wpdb->prepare` (vsprintf) and `preg_replace` concretize the statement |
| WordPress 5.1 | cold + auth | **0 / 1 / 2** | 0 findings | 20.26% / 20.26% | same |
| Drupal 8.0.0 | cold | **0 / 0 / 3** | 0 findings | 3.79% / 3.79% | **blocked**: PHP 8 fatal at bootstrap (error-handler arity during `PDOStatement` inheritance) |
| Drupal 9.0.0 | cold | **0 / 0 / 2** | 0 findings | 2.87% / 2.87% | **blocked**: `PDOStatement::fetch` vs `StatementInterface::fetch` (PHP 8) |
| MediaWiki 1.27.7 | cold | **0 / 0 / 0** | 0 findings | 5.47% / 5.42% | coverage only |
| **total** | | **58 / 92 / 127** | | | |

Coverage is the union of the judge replays' executed lines over the executable lines PHP-Parser
finds in the app (`exec_lines.php`; for OpenEMR `.php` and `.inc`, for Drupal also `.module` etc.,
`vendor/` included everywhere). For the M5 apps the fault replays themselves ran under the Xdebug
coverage prepend (`judge_cgi: xdebug`: the trace build lacks PDO, openssl and curl), so their two
columns are one measurement. Drupal's coverage is the 7.4 judge rendering ACE's bare requests:
ACE itself could not run Drupal.

## What limits ACE on these apps (from the per-app misses)
1. **Key discovery needs a direct superglobal read.** OpenCart (`Request::clean` copies `$_GET`),
   phpBB (`$request->variable()` over a copy, superglobals disabled), OpenEMR's `controller.php`
   (route = first key NAME) never read a parameter directly, so ACE declares none.
2. **Unmodelled string builtins concretize the input** (E4), which is sound for exploration but
   hides injections: `vsprintf` in `$wpdb->prepare`, `preg_replace` over SQL clauses (WordPress),
   `intval` before a range check (WeBid WB-11), `preg_match` route matching (WordPress REST).
3. **DB values ACE cannot guess**: phpMyAdmin's database/table names.
4. **Budget**: per-script wall-clock budgets on a heavily loaded host (OpenEMR: 30 s, 481 of
   1238 scripts hit it; phpMyAdmin: 83 of 86 spent it in the shared bootstrap).
5. **PHP 8 runtime vs PHP 7 apps**: handled by opt-in E2 rewrites where possible (about a dozen kinds now);
   Drupal 8/9's class hierarchy over `PDOStatement` is not.
6. **The structural XSS criterion** (decision (f)) does not cover reflections inside a JavaScript
   string (OpenEMR `patient_match_dialog.php`).

## Not comparable to the paper's numbers
The paper's SymPHP pipeline starts from a Witcher crawl plus fuzzing; ACE here starts from bare
URLs and the login only. The known-vuln lists are our reconstruction (`known_vulns/README.md`:
127 entries for these 15 apps vs the paper's 90).
