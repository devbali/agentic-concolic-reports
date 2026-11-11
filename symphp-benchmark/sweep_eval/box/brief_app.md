# Task: close branch coverage of ONE PHP endpoint, then SUBMIT. Be fast.

Your ONLY goal: make the symbolic branch coverage of one endpoint **complete**, then
submit a packet by running `make_packet.py`. You are not looking for anything in the
code. Work in a tight loop and FINISH FAST — most endpoints are already complete from
the first run and need nothing but a submit.

**CRITICAL — how to finish.** The ONLY way to end your job is to run `make_packet.py`
(below), which writes your submission. Then STOP.
- Do NOT `sleep`, wait, or poll for anything. Nothing will answer you.
- Do NOT inspect your box's internals (`in/`, `ctl/`, `out/`, `batch/` layout) or ask
  questions — there is no one to answer and waiting only wastes the clock.
- The moment `coverage_report.py` prints `"complete": true`, run `make_packet.py` and
  stop. Do not keep exploring a complete endpoint.

## Environment (already set — just use it)
`ENGINE, PYTHONPATH, ACE_ENGINE, ACE_PHP_RUNTIME, HARNESS, BUILD, APP, SCRIPT, DBPORT`.
The endpoint is `$SCRIPT` of app `$APP`; a MySQL DB is live at `127.0.0.1:$DBPORT`.
Your corpus of `dump_*.json` is in `batch/dumps` (relative to your box root, which the
protocol note above gave you as an absolute path). Put new dumps there.

## The exact procedure
1. Reset the DB (reachability depends on rows):
   `mysql -uroot -h127.0.0.1 -P"$DBPORT" < /box/"$APP".sql`
2. Build a base corpus:
   `python3 /box/explore_fixed.py --app "$APP" --script "$SCRIPT" --build "$BUILD" --out-dir batch/dumps --budget 120`
3. Check it: `python3 /box/coverage_report.py batch/dumps`
4. If `"complete": true` → go straight to SUBMIT. You are done exploring.
5. If not complete, for each `missing` edge the output gives a `seeds` dict the fixed
   loop already tried without reaching it — usually because the path needs DB state or a
   value the solver cannot invent (a row must/ must not already exist; a name must be
   new/unique; a number in range). Read `$BUILD/$SCRIPT`, craft a better seed, run it,
   and re-check:
   ```
   echo '[{"POST_x":"v","is_null(POST_x)":false}]' > /tmp/s.json   # your seed(s)
   SEEDS_ONLY=1 EXTRA_SEEDS_JSON=/tmp/s.json LABEL_SUFFIX=_a1 \
     python3 /box/box_runner_blind.py --app "$APP" --script "$SCRIPT" --build "$BUILD" --out-dir batch/dumps
   python3 /box/coverage_report.py batch/dumps
   ```
   Repeat only until complete. A purely computed `unknown`/`unevaluable` decision that
   no input can drive may be declared in `batch/assumptions.json` as
   `[{"type":"UntrackedPathAssumption","expr":<the edge's expr>}]`. Do not declare a
   branch you simply did not reach.

6. **A declared assumption is a LICENCE NOT TO EXPLORE — not a record of a branch you
   explored.** If the corpus walked it, it is a branch in the tree and needs no licence.
   This engine accepts exactly two kinds: `UntrackedPathAssumption` (above) and
   `IndependenceAssumption`. You do NOT mark your own claim confirmed — the gate
   RE-VERIFIES it and a refusal is a FAILED attempt.

   Declare an `IndependenceAssumption` when coverage will not close because a set of
   decisions are **mutually independent**: each is reachable regardless of the others, so
   the tree demands their full cross-product but no run needs any particular combination
   (classic: shared bootstrap/framework code testing many DIFFERENT superglobal keys for
   `isset`/`== null`). Name the specific decisions you are SURE do not interact, by their
   `expr` (usually) or `source`. The schema for THIS engine is two decision lists, `a`
   and `b`, which must be DISJOINT within a record:
   `{"type":"IndependenceAssumption","a":[{"expr":E_i}],"b":[{"expr":E_j},...]}`.
   To make N decisions mutually independent, emit the disjoint chain
   `{E_0}⟂{E_1..E_N}`, `{E_1}⟂{E_2..E_N}`, … (`coverage_report.py`'s `decisions_by_file`
   lists the decision `expr`s per source file). Declare only genuine independence between
   non-interacting setup reads — never to skip real `$SCRIPT` logic.

## SUBMIT (this ends your job)
```
python3 /box/make_packet.py --box-root "$PWD" --dumps batch/dumps \
    $( [ -f batch/assumptions.json ] && echo --assumptions batch/assumptions.json )
```
After it prints its marker line, STOP. Do nothing else.
