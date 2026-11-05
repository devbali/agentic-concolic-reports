"""Which engine the harness drives, and the three engine calls drive.py makes.

The harness runs against EITHER engine branch, chosen by what is checked out
(or by `ACE_ENGINE=<path to an engine checkout>`):

* v1 -- `php-runtime/real-apps` (every result up to M5): `concolic.model.*`,
  `concolic.solver.solve_and_evaluate`, `concolic.coverage.CoverageChecker`,
  the PHP runtime's `Concolic\\Template` notes. drive.py keeps its own code
  for these, unchanged.
* v2 -- `php-runtime/real-apps-v2` (main's native `concat`): `dump_ir.*`,
  `concolic.solver.solve`, `concolic.coverage.check`, and the statement's own
  TERM on the sink call. Told apart by `dump_ir/run.py`, which only v2 has.

Only the v2 implementations live here; `V2` is what drive.py branches on.
"""

from __future__ import annotations

import json
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ENGINE = pathlib.Path(os.environ.get("ACE_ENGINE") or ROOT / "agentic_concolic_engine").resolve()
V2 = (ENGINE / "dump_ir" / "run.py").exists()
#: The PHP runtime the PHP harnesses load (they read ACE_PHP_RUNTIME).
PHP_RUNTIME = ENGINE / "runtimes" / "php_runtime"
if str(ENGINE) not in sys.path:
    sys.path.insert(0, str(ENGINE))

if V2:
    from concolic.assumptions import AssumptionSet, Decision, UntrackedPathAssumption   # noqa: E402
    from concolic import coverage as _coverage                                         # noqa: E402
    from concolic.solver import solve                                                  # noqa: E402
    from dump_ir import expr as _expr                                                  # noqa: E402
    from dump_ir.run import Run                                                        # noqa: E402
else:
    from concolic.model.run import Run                                                 # noqa: E402,F401


def negations(dump: dict, timeout_ms: int = 5000):
    """v2: for each branch this run took, a model of the prefix with that branch flipped (or None)."""
    run = Run.from_dict(dump)
    symbols = run.symbols()
    pcs = run.path_conditions
    observed = [(pc.expr, bool(pc.taken)) for pc in pcs]
    for i, pc in enumerate(pcs):
        res = solve([*observed[:i], (pc.expr, not pc.taken)], symbols, timeout_ms=timeout_ms)
        yield res.model if res.status == "sat" else None


def coverage(kept: list[dict], names: dict):
    """v2: the completion check, with drive.py's one mechanical class of UNTRACKED decision, listed:
    every symbol is a shim's result (`mysqli_connect_errno() != 0`), so no request can drive it."""
    inputs = set(names)
    runs = [Run.from_dict(d) for d in kept]
    declared: dict[str, str] = {}
    for run in runs:
        for pc in run.path_conditions:
            node = _expr.from_identity(pc.expr)
            syms = set(_expr.symbols(node)) if node is not None else set()
            where = f"{(pc.source.file if hasattr(pc.source, 'file') else '').rsplit('/', 1)[-1]}:" \
                    f"{getattr(pc.source, 'lineno', '?')}"
            if syms and not (syms & inputs):
                declared.setdefault(pc.expr, f"shim result only, at {where}: no request can drive it")
    aset = AssumptionSet()
    for expr, why in declared.items():
        aset.add(UntrackedPathAssumption(decision=Decision(expr=expr), description=why))
    return _coverage.check(runs, assumptions=aset), [a.description for a in aset.assumptions]


def missing_models(cov) -> list[dict]:
    """v2: the model reaching each missing edge."""
    return [m.seeds for m in cov.missing if m.seeds]
