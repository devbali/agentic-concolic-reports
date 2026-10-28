#!/usr/bin/env python3
"""Investigate the 404 render path (no mutations)."""
import re

FILES = [
    "/home/dev/project/ruby_examples/dse-apps/apps/diaspora/app/controllers/application_controller.rb",
    "/home/dev/project/ruby_examples/dse-apps/apps/diaspora/app/controllers/people_controller.rb",
    "/home/dev/project/reports/diaspora/results3/people_show/run_dse.rb",
    "/home/dev/project/reports/diaspora/results3/people_show/_replay_missing.rb",
]
PATS = ["404", "not_found", "RecordNotFound", "AccountClosed", "render ", "rescue_with_handler"]

for f in FILES:
    print(f"########## {f}")
    try:
        with open(f) as fh:
            text = fh.read()
    except Exception as e:  # noqa: BLE001
        print(f"  !! {e}")
        continue
    for i, line in enumerate(text.splitlines(), 1):
        if any(p in line for p in PATS):
            print(f"  {i:4d}| {line[:160]}")
