#!/usr/bin/env python3
"""Run an endpoint's own coverage_report.py with DISCIPLINE §16g FORCED ON,
without editing that endpoint's script.

`coverage_report.py` binds `CoverageChecker` at ITS import time, so patching
`concolic_engine.coverage.CoverageChecker` before running it is enough: the
`from ... import CoverageChecker` inside the report then picks up the
subclass. Nothing under the endpoint directory is touched.

  usage: FORCE_REPORT=<abs path to coverage_report.py> python3 _force_16g.py
"""
import os, runpy, sys

sys.path.insert(0, "/home/dev/project/src")
import concolic_engine.coverage as _cov

_Base = _cov.CoverageChecker


class _Forced(_Base):
    def __init__(self, *a, **kw):
        kw["foreclosure_wellfounded_drops"] = True
        super().__init__(*a, **kw)


_cov.CoverageChecker = _Forced
path = os.environ["FORCE_REPORT"]
print(f"[force-16g] running {path} with foreclosure_wellfounded_drops=True",
      flush=True)
runpy.run_path(path, run_name="__main__")
