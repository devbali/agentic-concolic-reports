#!/usr/bin/env python3
"""Thin CLI wrapper — the completion checker now LIVES in the concolic
engine (src/concolic_engine/completion.py), as a peer of CoverageChecker,
so its verdict is a section of the engine's final coverage_summary.json.
This wrapper only preserves the old invocation path.

    PYTHONPATH=src python3 completion_checker.py <completion_config.json>
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from concolic_engine.completion import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())
