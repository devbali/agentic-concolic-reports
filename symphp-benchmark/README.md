# ACE on SymPHP's benchmark — the Witcher-Test pilot

SymPHP (Li et al., *Holistic Concolic Execution for Dynamic Web Applications via
Symbolic Interpreter Analysis*, S&P 2024) is evaluated in §5 on 17 PHP
applications. It measures two things: line coverage, from replaying the generated
inputs, and how many of 101 known command-injection, SQL-injection and reflected-XSS
bugs it finds. A bug counts as found when an input makes a SQL or shell sink fail
to parse, a criterion inherited from Witcher's "fault escalation". The 101-bug list
is not published.

This directory runs ACE on that benchmark. It starts with the one application whose
ground truth is fully public: **Witcher-Test** (Table 2 row 6: 8 files, 246 LoC, 7
bugs). SymPHP is run alongside it on the same machine, and a single concrete judge
scores both tools.

## Result

| tool | starting inputs | bugs found (judge) | line coverage | budget | time used |
|---|---|---|---|---|---|
| **ACE** | none (bare URL) | **7/7** | **98.82%** (84/85) | none set | 19.5 s |
| **ACE** | Witcher unit-test seeds | **7/7** | **98.82%** (84/85) | none set | 10.9 s |
| SymPHP | none (bare URL) | 0/7 | 40.00% (34/85) | 600 s/URL | 170 s (8 S2E runs) |
| SymPHP | Witcher unit-test seeds | 1/7 | 72.94% (62/85) | 600 s/URL | 198 s (9 S2E runs) |
| *paper, SymPHP* | *Witcher crawl (4 h cap) + fuzzing (10 min/URL)* | *7/7* | *100%* | *10 min/URL* | — |
| *paper, Witcher alone* | — | *7/7* | *100%* | — | — |

**SymPHP was not cut short.** Each URL got the paper's 10-minute budget, split
across its seeds as §5.1 prescribes (`~/symphp-eval/witcher-test/plan.txt`).
Every run ended on its own after 20–24 s, because S2E exhausted its states.
`runs/*/run.json` records `wall_s` against `budget_s`, and the debug logs show 2
forks across all 17 runs. More time would not have changed these rows.

**The SymPHP rows do not reproduce the paper's pipeline.** In the paper,
SymPHP's inputs come from a Witcher crawl followed by Witcher fuzzing. Here they
are the seed requests shipped with Witcher's own unit test, which take no time to
produce and are deliberately incomplete. Witcher's fuzzer was not run, so these
rows measure SymPHP given weaker inputs than the paper gave it. The two paper rows
are quoted from Table 2, not reproduced.

- **ACE's single uncovered line** is `config.php:10`, the "Failed to connect" echo.
  Its guard is `mysqli_connect_errno()`, a shim result that no request can control.
  It is excluded by the run's only assumption (see [How ACE runs](#how-ace-runs)).
- **SymPHP's one hit** (`test-2.php`) is reached by the seed request itself, which
  already carries `nv1`…`nv3`. Symbolic exploration added no bugs. It forked
  exactly twice in total, both times at `test-select-3.php:16`. There it solved
  `sel1 = "s-val1a"` correctly, then stopped, because `sel2` and `sel3` are absent
  from the seed.
- **The paper's 7/7 for SymPHP on this app equals Witcher's 7/7.** In the paper's
  pipeline SymPHP is driven by Witcher's fuzzed inputs, and those inputs already
  trigger all seven bugs on their own (Table 2: Witcher 7, SymPHP 7). This
  experiment did not run Witcher's fuzzer, so the paper rows are quoted rather than
  reproduced.

### Why the gap is structural, not tuning

SymPHP marks as symbolic only the bytes of GET and POST values **already present**
in the request. Its source (`~/symphp-eval/src/symphp/php-src/Zend/zend_hash.c`,
under `ENABLE_SYMPHP`) checks `TRACK_VARS_GET` and `TRACK_VARS_POST` and nothing
else. Each of the six bugs SymPHP missed needs a key the seed request does not
carry:

| script | missing key(s) |
|---|---|
| `test-5-cmd` | POST `nv5` |
| `test-findvar-1` | POST `ao3` |
| `test-equal-1` | GET `nv1` |
| `test-get-5-crosspol` | GET `nv1`/`nv2`/`nv82`/`nv92`, depending on the seed |
| `test-select-3` | GET `sel2`, `sel3` |
| `test-cookie-5` | COOKIE `nv5` (COOKIEs are never symbolic) |

A missing key gives SymPHP nothing to make symbolic, so no time budget changes
those six.

ACE models a missing key as an absent `str?` input:
- `isset()` becomes a recorded decision that the solver can flip.
- A key the script reads that the request did not carry is *discovered* at run
  time.

Nothing in this setup reads the application's source to find keys.

## The judge

`judge.py` replays a request against the **uninstrumented** app. It uses PHP 7.4
`php-cgi-trace`, the same build your SymPHP replays use, and a MySQL 8 container
(`ace-judge-mysql`, 127.0.0.1:3307), so the host MySQL is never touched.

A request **faults** when either of these happens during the replay:
- MySQL records a statement error (`performance_schema`, `MYSQL_ERRNO <> 0`).
- dash prints a syntax error on stderr.

A known bug counts as found when one of the tool's requests to its script faults
**and** the trace passes the sink line. Coverage is the union of the traces, divided
by the executable lines PHP-Parser finds (`exec_lines.php`).

Controls, measured:
- A request lacking `sel3`, and a bare request, do not fault.
- `fixtures/oracle/guarded.php` never faults. It is the same sink behind a guard
  that only allows a harmless value.

Each tool is scored on everything it emits:
- **SymPHP:** the seed request plus every S2E test case (`symphp_requests.py`).
- **ACE:** one request per explored trace plus each oracle witness (`score.py`).

## How ACE runs

`drive.py <app> --arm cold|witcher`, per entry script:

1. **Run.** `harness.php` executes the instrumented script under the typed PHP
   runtime.
   - `$_GET`, `$_POST` and `$_COOKIE` are recording `ArrayAccess` objects, and every
     declared key is a `str?` input.
   - SQL and shell builtins are `target_function`s. Each publishes its statement as
     a note, with `$$(ref)` marking each symbolic part.
   - Connection builtins are `shim`s.
2. **Expand.** New traces are expanded by prefix negation through the engine's own
   lowering (`concolic.solver.solve_and_evaluate`). When that runs dry, the queue
   is refilled from `CoverageChecker`'s witnesses.
3. **Stop.** Exploration ends when neither source proposes an unseen trace.
4. **Assume.** The run makes one mechanical class of assumption: a branch whose
   every symbol is a shim result gets an `UntrackedPathAssumption`. Each one is
   written into the summary; on Witcher-Test it is exactly one, `config.php:8`.
5. **Oracle.** `sinks.py` checks each sink call.
   - **Malformed-at-reach:** the statement, filled with this run's values, does not
     parse. All of Witcher-Test's bugs are this kind.
   - **Injectable:** for an input the statement carries, Z3 finds a value that
     satisfies every path condition before the sink and contains a breaking
     payload, and the result does not parse.

   Parsing is sqlglot (MySQL dialect) for SQL and `sh -n` for shell. Neither
   verdict counts until the judge replays it.

```sh
# once: the judge's database
docker run -d --name ace-judge-mysql -p 127.0.0.1:3307:3306 \
  -e MYSQL_ALLOW_EMPTY_PASSWORD=yes mysql:8.0 --default-authentication-plugin=mysql_native_password
python3 judge.py setup witcher-test

# ACE (needs a python with z3-solver + sqlglot; PHP 8.2 comes from docker)
python drive.py witcher-test --arm cold
python drive.py witcher-test --arm witcher
python3 score.py witcher-test ace:cold
python3 score.py witcher-test ace:witcher

# SymPHP (S2E, ~/symphp-eval/witcher-test): 10 min per URL, split across its seeds,
# as in the paper's §5.1
cd ~/symphp-eval/witcher-test && xargs -P 3 -L 1 sh -c './run.sh $0 $1' < plan.txt
cd - && python3 symphp_requests.py results/witcher-test/symphp_witcher.json ~/symphp-eval/witcher-test/runs/witcher-*
python3 score.py witcher-test symphp:witcher results/witcher-test/symphp_witcher.json
```

## What changed in the engine to do this

Two runtime changes, both in `agentic_concolic_engine/runtimes/php_runtime/`, both
with tests:

1. **`Concolic\Template` (opt-in via `Runtime::$templates`).**
   - *Why:* `concat` refuses a symbolic operand because the dump IR has no
     concatenation term. That refusal is right for a *decision*, but it makes
     injection impossible to see, since an injection is exactly a parameter
     concatenated into SQL.
   - *What it does:* under the flag, a concatenation keeps its parts. The result
     can only be echoed or passed to a target, where it renders as a note with
     refs. Every decision on it raises: comparison, truthiness, `empty`, and any
     string conversion.
   - *Compatibility:* the flag is off by default, so every existing corpus is
     unchanged. `tests/t_template.php` covers it, including the off-by-default
     negative control.
2. **Instrumentor line drift (a bug fix).**
   - *The bug:* rewriting `echo` replaced the statement node and dropped its
     leading comment. The printer then omitted that line, so every later line in
     the file, and every dump location from it, was off by one. Witcher-Test showed
     it: the sink at `test-2.php:20` was reported at line 19.
   - *Fixed in:* `InstrumentVisitor`, by carrying the comments over.
     `t_instrument.php::test_rewritten_echo_keeps_its_comment_and_every_line_number`
     fails 3 assertions without the fix.
   - *Impact elsewhere:* any HotCRP file with a comment directly above an `echo`
     was affected the same way.

PHP runtime suite after both changes: `php tests/run.php` → 134 tests, 564
assertions, 0 failed (PHP 8.2, docker). The Python suites that shell out to `php`
(`concolic/runtime/tests`, `runtimes/tests/test_php_ts_typed_parity.py`) were
**not** run: the host has no `php` ≥ 8.1 on `PATH`.

## Scope, and what does not carry over yet

This is one application, and a synthetic one. Witcher-Test tests *reaching* a
broken sink; it has no sanitizers, database reads, sessions or `exit`. The real
apps in Table 2 need things this harness does not yet do, each of which will raise
rather than pass silently:

- **Database results.** `mysqli_query` returns "succeeded" and nothing can be
  fetched. SymPHP runs the concretized query against a real DB. ACE needs either
  that or symbolic rows, and that is a design decision.
- **Sanitizers** (`mysqli_real_escape_string`, `htmlspecialchars`, `intval`, …) are
  not modelled. A template reaching one raises at `__toString`.
- **Reflected XSS.** `echo` of a template is printed but not judged. There is no
  XSS oracle yet; in the paper it accounts for the 12 false positives.
- **Requests.** `exit`/`die` would end the batch process. Iterating or `count()`ing
  a superglobal raises. App code runs in function scope, so `global $x` across
  includes is not modelled.
- **The ACE agent loop (`sweep/`) was not used.** This is the engine plus a fixed
  driver; no agent wrote a config or judged a claim.
