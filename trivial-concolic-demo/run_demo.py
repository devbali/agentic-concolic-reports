#!/usr/bin/env python3
"""
Trivial concolic demo runner.

Implements the simplest possible concolic cycle:
  1. Define a trivial entrypoint with one branch
  2. Run with initial concrete values
  3. Check coverage
  4. If not complete, use Z3-suggested values for the missing branch
  5. Repeat until complete

Usage: python3 run_demo.py
Output: Saves RunDump JSON files to the report directory.

Framework pattern used:
  from py_runtime import CallInterceptor, SymbolicInt, SymbolicString
  from concolic_engine.run import Run
  from concolic_engine.coverage import CoverageChecker
"""

import json
import os
import sys

sys.path.insert(0, "/home/dev/project/src")

from py_runtime import CallInterceptor
from concolic_engine.run import Run
from concolic_engine.coverage import CoverageChecker

REPORT_DIR = "/home/dev/project/reports/trivial-concolic-demo"


# --- Target function ---

interceptor = CallInterceptor()


@interceptor.target
def is_positive(x: int) -> bool:
    """Return True if x > 0, False otherwise."""
    return x > 0


# --- Entrypoint ---

def entrypoint(x: int) -> str:
    """Check if x is positive or non-positive."""
    if is_positive(x):
        return 'positive'
    return 'non-positive'


# --- Helpers ---

def save_run_dump(run_dump: dict, filename: str) -> None:
    path = os.path.join(REPORT_DIR, filename)
    with open(path, "w") as f:
        json.dump(run_dump, f, indent=2)
    print(f"  [save] {filename} ({len(json.dumps(run_dump))} bytes)")


def dump_events(run_dump: dict) -> None:
    for ev in run_dump["events"]:
        if ev["type"] == "path_condition":
            print(f"    PC: {ev['expr']}  taken={ev['taken']}")
        elif ev["type"] == "call":
            print(f"    CALL: {ev['target']}({ev['args']})")
        elif ev["type"] == "symbolic_call":
            print(f"    SYM_CALL: {ev['target']} -> {ev['result_name']} = {ev['result_value']}")


# --- Concolic cycle ---

def run_concolic_cycle() -> None:
    print("=" * 60)
    print("TRIVIAL CONCOLIC DEMO")
    print("=" * 60)
    print()

    values_to_try = [5]
    all_run_dumps = []
    iteration = 0
    complete = False

    while not complete and values_to_try:
        val = values_to_try.pop(0)
        iteration += 1
        label = f"iter{iteration}_x={val}"

        print(f"--- Iteration {iteration}: x = {val} ---")

        # Execute with symbolic wrapping
        run_dump = interceptor.run(entrypoint, {"x": val}, label=label)
        all_run_dumps.append(run_dump)

        # Save raw RunDump
        save_run_dump(run_dump, f"dump_{label}.json")

        # Print result and events
        print(f"  Result: '{entrypoint(val)}'")
        print(f"  Events ({len(run_dump['events'])}):")
        dump_events(run_dump)
        print()

        # Coverage check
        print(f"--- Coverage Check (after iteration {iteration}) ---")
        runs = [Run.from_dict(d) for d in all_run_dumps]
        for r in runs:
            print(f"  {r.short_summary()}")

        result = CoverageChecker(runs).check_coverage()
        print()
        print(result.summary())
        print()

        complete = result.complete

        if not complete:
            print("--- Missing branches: computing next values via Z3 ---")
            for m in result.missing:
                print(f"  Missing '{m.missing_branch}' at '{m.node_constraint}'")
                print(f"  SMT suggests: {m.concrete_values}")
                if m.concrete_values:
                    next_val = m.concrete_values.get("x", 0)
                    if next_val not in values_to_try:
                        values_to_try.append(next_val)
            print(f"\n  Next values to try: {values_to_try}\n")
        else:
            print("*** ALL BRANCHES COVERED ***\n")

    # Save coverage summary
    summary = {
        "iterations": iteration,
        "complete": complete,
        "total_runs": result.total_runs,
        "total_nodes": result.total_nodes,
        "missing_count": len(result.missing),
        "missing": [
            {
                "node_constraint": m.node_constraint,
                "missing_branch": m.missing_branch,
                "concrete_values": m.concrete_values,
                "source_location": m.source_location,
            }
            for m in result.missing
        ],
    }
    summary_path = os.path.join(REPORT_DIR, "coverage_summary.json")
    with open(summary_path, "w") as f:
        json.dump(summary, f, indent=2)
    print(f"  [save] coverage_summary.json")

    print("\nDone.")


if __name__ == "__main__":
    run_concolic_cycle()