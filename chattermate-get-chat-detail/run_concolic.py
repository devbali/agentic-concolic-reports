#!/usr/bin/env python3
"""
Standalone concolic runner for ChatterMate get_chat_detail endpoint.

=== Workflow ===

Phase 1 — EXPLORE
  Runs the entrypoint with a seed set of concrete values (no assumptions).
  Shows the path tree and flags potential explosion points.

Phase 2 — ASSUME
  Add minimal assumptions to keep the run count under a practical limit.
  (Edit this file, add to the `assumptions` block at the bottom.)

Phase 3 — GENERATE + EXECUTE
  Generate self-contained inline Python scripts in runs/ (one per run),
  then execute each one.  Each script is independently executable::

      python3 runs/run_jwt_unscoped_found.py

  Every dump JSON includes its own generating script in the "script" field.

Phase 4 — VERIFY
  Collect all dump JSONs and pass them to the CoverageChecker with
  assumptions to confirm 100% branch coverage.

Usage:
    # Full workflow:
    python3 run_concolic.py

    # Execute a single run independently:
    python3 runs/run_jwt_unscoped_found.py

    # Re-verify without re-executing:
    python3 run_concolic.py --verify-only

Output:
    runs/                      — one standalone .py script per run
    dump_<label>.json          — RunDump JSON (embeds its own script)
    coverage_summary.json      — coverage check result
"""

import dataclasses
import json
import os
import sys

sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, "/home/dev/project/py_examples/chattermate/chattermate.chat/backend")

from py_runtime import CallInterceptor, SymbolicVar
from concolic_engine.run import Run
from concolic_engine.coverage import CoverageChecker
from concolic_engine.assumptions import (
    AssumptionSet,
    PathSource,
    IndependenceAssumption,
    UntrackedPathAssumption,
)

REPORT_DIR = os.path.dirname(os.path.abspath(__file__))
RUNS_DIR = os.path.join(REPORT_DIR, "runs")
os.makedirs(RUNS_DIR, exist_ok=True)

interceptor = CallInterceptor()


# ---------------------------------------------------------------------------
# Target declarations (shared across all runs)
# ---------------------------------------------------------------------------

@interceptor.target(lambda a, n: 0)
def check_session_access(
    session_id: str,
    has_user_id: bool,
    has_user_groups: bool,
    include_unassigned: bool,
) -> bool:
    """Target for chat_repo.check_session_access()."""


@interceptor.target(lambda a, n: 1 if a.get("found") else 0)
def get_chat_detail(
    session_id: str, org_id: str, can_view_all: bool, found: bool
) -> dict:
    """Target for chat_repo.get_chat_detail()."""


@interceptor.target
def source_get_chat_detail(
    session_id: str,
    auth_type: str,
    can_view_all: bool,
    can_view_assigned: bool,
    can_view_unassigned: bool,
    session_found: bool,
) -> str:
    """Entrypoint model — replicates get_chat_detail's access-control logic."""
    if auth_type == "shopify_session" or auth_type == "shopify":
        result = get_chat_detail(session_id, "o1", True, session_found)
        if not result:
            return "shopify_404"
        return "shopify_found"
    if not can_view_all:
        has_access = check_session_access(
            session_id,
            has_user_id=can_view_assigned,
            has_user_groups=can_view_assigned,
            include_unassigned=can_view_unassigned,
        )
        if not has_access:
            return "jwt_403_not_found"
    result = get_chat_detail(session_id, "o1", can_view_all, session_found)
    if not result:
        return "jwt_404"
    return "jwt_found"


# ---------------------------------------------------------------------------
# Run definitions
# ---------------------------------------------------------------------------

RUN_DEFS: list[tuple[str, dict, str]] = [
    # JWT, unscoped (can_view_all=True)
    ("jwt_unscoped_found", {
        "session_id": "jwt_unscoped_found",
        "auth_type": "jwt",
        "can_view_all": True,
        "can_view_assigned": True,
        "can_view_unassigned": True,
        "session_found": True,
    }, "jwt_found"),
    ("jwt_unscoped_not_found", {
        "session_id": "jwt_unscoped_not_found",
        "auth_type": "jwt",
        "can_view_all": True,
        "can_view_assigned": True,
        "can_view_unassigned": True,
        "session_found": False,
    }, "jwt_404"),
    # JWT, scoped, assigned
    ("jwt_scoped_assigned_found", {
        "session_id": "jwt_scoped_assigned_found",
        "auth_type": "jwt",
        "can_view_all": False,
        "can_view_assigned": True,
        "can_view_unassigned": False,
        "session_found": True,
    }, "jwt_found"),
    # JWT, scoped, unassigned
    ("jwt_scoped_unassigned_found", {
        "session_id": "jwt_scoped_unassigned_found",
        "auth_type": "jwt",
        "can_view_all": False,
        "can_view_assigned": False,
        "can_view_unassigned": True,
        "session_found": True,
    }, "jwt_found"),
    # JWT, scoped, denied
    ("jwt_scoped_denied", {
        "session_id": "jwt_scoped_denied",
        "auth_type": "jwt",
        "can_view_all": False,
        "can_view_assigned": False,
        "can_view_unassigned": False,
        "session_found": False,
    }, "jwt_403_not_found"),
    # Shopify (shopify_session)
    ("shopify_session_found", {
        "session_id": "shopify_session_found",
        "auth_type": "shopify_session",
        "can_view_all": True,
        "can_view_assigned": True,
        "can_view_unassigned": True,
        "session_found": True,
    }, "shopify_found"),
    ("shopify_session_not_found", {
        "session_id": "shopify_session_not_found",
        "auth_type": "shopify_session",
        "can_view_all": True,
        "can_view_assigned": True,
        "can_view_unassigned": True,
        "session_found": False,
    }, "shopify_404"),
    # Shopify (shopify)
    ("shopify_type_found", {
        "session_id": "shopify_type_found",
        "auth_type": "shopify",
        "can_view_all": True,
        "can_view_assigned": True,
        "can_view_unassigned": True,
        "session_found": True,
    }, "shopify_found"),
    ("shopify_type_not_found", {
        "session_id": "shopify_type_not_found",
        "auth_type": "shopify",
        "can_view_all": True,
        "can_view_assigned": True,
        "can_view_unassigned": True,
        "session_found": False,
    }, "shopify_404"),
]


# ---------------------------------------------------------------------------
# Script template (for generating standalone run scripts)
# ---------------------------------------------------------------------------

SRC_PATH = "/home/dev/project/src"
PYEX_PATH = "/home/dev/project/py_examples/chattermate/chattermate.chat/backend"

_RUN_SCRIPT_TEMPLATE = """\
#!{interp}
\"\"\"
Standalone concolic run for label: {label}

Generated by run_concolic.py — execute directly:
    python3 runs/run_{label}.py

The RunDump JSON includes this script source in the "script" field.
\"\"\"
import json
import os
import sys

sys.path.insert(0, {src_path!r})
sys.path.insert(0, {pyex_path!r})

from py_runtime import CallInterceptor, SymbolicVar
from concolic_engine.run import Run

interceptor = CallInterceptor()


@interceptor.target(lambda a, n: 0)
def check_session_access(
    session_id: str, has_user_id: bool,
    has_user_groups: bool, include_unassigned: bool,
) -> bool:
    \"\"\"Target for chat_repo.check_session_access().\"\"\"


@interceptor.target(lambda a, n: 1 if a.get("found") else 0)
def get_chat_detail(
    session_id: str, org_id: str,
    can_view_all: bool, found: bool,
) -> dict:
    \"\"\"Target for chat_repo.get_chat_detail().\"\"\"


@interceptor.target
def source_get_chat_detail(
    session_id: str,
    auth_type: str,
    can_view_all: bool,
    can_view_assigned: bool,
    can_view_unassigned: bool,
    session_found: bool,
) -> str:
    if auth_type == "shopify_session" or auth_type == "shopify":
        result = get_chat_detail(session_id, "o1", True, session_found)
        if not result:
            return "shopify_404"
        return "shopify_found"
    if not can_view_all:
        has_access = check_session_access(
            session_id,
            has_user_id=can_view_assigned,
            has_user_groups=can_view_assigned,
            include_unassigned=can_view_unassigned,
        )
        if not has_access:
            return "jwt_403_not_found"
    result = get_chat_detail(session_id, "o1", can_view_all, session_found)
    if not result:
        return "jwt_404"
    return "jwt_found"


# --- Run ---
SymbolicVar.clear_path_conditions()
from py_runtime.symbolic_func import reset_symbolic_state
reset_symbolic_state()

kwargs = {kwargs_python}

# Embed this script's own source as the dump "script" field
_this_source = open(__file__).read()

dump = interceptor.run(
    source_get_chat_detail,
    kwargs,
    label={label_json!r},
    script=_this_source,
)

report_dir = {report_dir!r}
dump_path = os.path.join(report_dir, {dump_filename!r})
with open(dump_path, "w") as f:
    json.dump(dump, f, indent=2)
print(f"Written: {{dump_path}}")
"""


def make_script(label: str, kwargs: dict) -> str:
    """Generate the standalone script for a run.

    Uses Python literal formatting (not JSON) for boolean values so the
    generated script can be run directly with ``python3 runs/run_X.py``.
    """
    def _py_literal(v):
        if isinstance(v, bool):
            return str(v)  # True / False
        return json.dumps(v)

    kwargs_lines = "{\n"
    for k, v in kwargs.items():
        kwargs_lines += f"        {json.dumps(k)}: {_py_literal(v)},\n"
    kwargs_lines += "    }"

    return _RUN_SCRIPT_TEMPLATE.format(
        interp=sys.executable,
        label=label,
        src_path=SRC_PATH,
        pyex_path=PYEX_PATH,
        kwargs_python=kwargs_lines,
        label_json=label,
        report_dir=REPORT_DIR,
        dump_filename=f"dump_{label}.json",
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _reset():
    SymbolicVar.clear_path_conditions()
    from py_runtime.symbolic_func import reset_symbolic_state
    reset_symbolic_state()


def _assumption_to_dict(a):
    d = {"type": type(a).__name__, "description": a.description}
    if hasattr(a, "source_a"):
        d["source_a"] = dataclasses.asdict(a.source_a)
    if hasattr(a, "source_b"):
        d["source_b"] = dataclasses.asdict(a.source_b)
    if hasattr(a, "source"):
        d["source"] = dataclasses.asdict(a.source)
    if hasattr(a, "tracked_side"):
        d["tracked_side"] = a.tracked_side
    if hasattr(a, "z3_expr"):
        d["z3_expr"] = a.z3_expr
    return d


# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------

def phase_explore():
    """Phase 1 — run with seed values, show raw branch tree."""
    print("=" * 70)
    print("PHASE 1 — EXPLORE  (no assumptions)")
    print("=" * 70)
    print()

    for label, kwargs, _expected in RUN_DEFS:
        _reset()
        dump = interceptor.run(source_get_chat_detail, kwargs, label=label)
        run = Run.from_dict(dump)
        pc_count = len(run.path_conditions)
        print(f"  {label:35s}  {pc_count} PCs  {run.call_events}")

    # Coverage check (no assumptions)
    runs = [Run.from_dict(
        interceptor.run(source_get_chat_detail, kw, label=lb)
    ) for lb, kw, _ in RUN_DEFS]
    cc = CoverageChecker(runs, timeout_ms=5000)
    result = cc.check_coverage()
    print(f"\n  Total runs: {result.total_runs}")
    print(f"  Tree nodes: {result.total_nodes}")
    print(f"  Complete:   {result.complete}")
    if result.missing:
        print(f"  Missing branches ({len(result.missing)}):")
        for m in result.missing:
            print(f"    - {m.node_constraint}  ({m.missing_branch})")
    print()


def phase_generate_scripts():
    """Phase 3 — produce standalone run scripts."""
    print("=" * 70)
    print("PHASE 3 — GENERATE  (standalone run scripts)")
    print("=" * 70)
    print()

    for label, kwargs, _expected in RUN_DEFS:
        script = make_script(label, kwargs)
        script_path = os.path.join(RUNS_DIR, f"run_{label}.py")
        with open(script_path, "w") as f:
            f.write(script)
        os.chmod(script_path, 0o755)
        print(f"  [script] runs/run_{label}.py  ({len(script)} chars)")
    print()


def phase_execute():
    """Phase 3 — execute each run via interceptor, saving JSON with script."""
    print("=" * 70)
    print("PHASE 3 — EXECUTE  (runs with embedded scripts)")
    print("=" * 70)
    print()

    dumps = []
    for label, kwargs, _expected in RUN_DEFS:
        _reset()
        script = make_script(label, kwargs)
        dump = interceptor.run(
            source_get_chat_detail, kwargs, label=label, script=script,
        )
        dumps.append(dump)
        dump_path = os.path.join(REPORT_DIR, f"dump_{label}.json")
        with open(dump_path, "w") as f:
            json.dump(dump, f, indent=2)
        print(f"  [dump] dump_{label}.json  ({len(json.dumps(dump))} bytes)")
    print()
    return dumps


def _build_assumptions():
    """Phase 2 — define assumptions."""
    assumptions = AssumptionSet()

    # Independence: Shopify vs JWT scoped-access are in mutually exclusive
    # if/elif/else branches (shopify returns early, JWT is in the else).
    assumptions.add(IndependenceAssumption(
        source_a=PathSource(
            file="app/api/chat.py", lineno=127,
            snippet="auth_type == 'shopify_session' or auth_type == 'shopify'",
        ),
        source_b=PathSource(
            file="app/api/chat.py", lineno=140,
            snippet="if not can_view_all:",
        ),
        description="Shopify vs JWT check is independent of scoped-access checks.",
    ))

    # Untracked: message attribute parsing runs AFTER all access-control
    # decisions (auth, permission, session-found). It's purely data presentation.
    assumptions.add(UntrackedPathAssumption(
        source=PathSource(
            file="app/api/chat.py", lineno=156,
            snippet="if hasattr(chat_detail, 'messages') and chat_detail.messages:",
        ),
        description="Message attribute parsing is data presentation, not access control.",
    ))

    return assumptions


def phase_verify(dumps=None):
    """Phase 4 — run CoverageChecker with assumptions."""
    print("=" * 70)
    print("PHASE 4 — VERIFY  (coverage check with assumptions)")
    print("=" * 70)
    print()

    if dumps is None:
        dumps = []
        for label, _, _ in RUN_DEFS:
            path = os.path.join(REPORT_DIR, f"dump_{label}.json")
            if os.path.exists(path):
                with open(path) as f:
                    dumps.append(json.load(f))
        if not dumps:
            print("  No dump files found. Run phase_execute first.")
            return None

    runs = [Run.from_dict(d) for d in dumps]
    assumptions = _build_assumptions()
    cc = CoverageChecker(runs, timeout_ms=5000, assumptions=assumptions)
    result = cc.check_coverage()

    print(result.summary())
    print()

    for run in runs:
        print(f"  {run.short_summary()}")
    print()

    if result.missing:
        print("Missing branches:")
        for m in result.missing:
            print(f"  - {m.node_constraint} -> missing '{m.missing_branch}'")
            print(f"    Z3 suggests: {m.concrete_values}")
            print(f"    Origin run: {m.origin_run_label}")
        print()

    if result.complete:
        print("*** COVERAGE COMPLETE — ALL ACCESS-CONTROL PATHS EXPLORED ***")
    else:
        print("*** COVERAGE NOT COMPLETE ***")
    print(f"   Total runs: {result.total_runs}")
    print(f"   Tree nodes: {result.total_nodes}")
    print(f"   Assumptions applied: {result.assumptions_used}")
    print(f"   Independence folds: {result.independent_folds}")
    print(f"   Solver time: {result.elapsed_ms:.1f} ms")
    print()

    summary = {
        "total_runs": result.total_runs,
        "total_nodes": result.total_nodes,
        "complete": result.complete,
        "missing_count": len(result.missing),
        "solver_lost": result.solver_lost,
        "elapsed_ms": result.elapsed_ms,
        "assumptions_used": result.assumptions_used,
        "independent_folds": result.independent_folds,
        "assumptions": [_assumption_to_dict(a) for a in assumptions.assumptions],
        "missing": [
            {
                "node_constraint": m.node_constraint,
                "source_location": m.source_location,
                "missing_branch": m.missing_branch,
                "missing_constraint": m.missing_constraint,
                "concrete_values": m.concrete_values,
                "origin_run_label": m.origin_run_label,
            }
            for m in result.missing
        ],
    }
    summary_path = os.path.join(REPORT_DIR, "coverage_summary.json")
    with open(summary_path, "w") as f:
        json.dump(summary, f, indent=2)
    print(f"  [save] coverage_summary.json")
    print()

    return result


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="ChatterMate get_chat_detail concolic report")
    parser.add_argument("--verify-only", action="store_true",
                        help="Skip execution, just verify existing dumps")
    args = parser.parse_args()

    if args.verify_only:
        result = phase_verify()
    else:
        phase_explore()
        phase_generate_scripts()
        dumps = phase_execute()
        result = phase_verify(dumps)

    sys.exit(0 if (result and result.complete) else 1)
