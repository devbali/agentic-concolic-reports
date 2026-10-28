#!/usr/bin/env python3
"""Mark FUTURE_WORK3_PLAN.md as COMPLETE (result: 64 stays, ordinal-naming
collision, not app gap) without deleting the plan detail."""
PATH = "/home/dev/project/reports/diaspora/results3/people_show/FUTURE_WORK3_PLAN.md"
with open(PATH) as f:
    txt = f.read()
marker = "# Status: PLAN ONLY — NOT IMPLEMENTED. Harness change ⇒ PERMISSION REQUIRED"
new_marker = ("# Status: COMPLETE (2026-09-04, PERMISSION GRANTED). Result: dual-format\n"
              "# scenario proves semantic co-reachability but MISSING STAYS 64 — the 48\n"
              "# cross-format items are a single-run call-ordinal NAMING collision, not an\n"
              "# app gap (see STRUCTURAL_GAPS.md addendum + commit). Runtime naming change\n"
              "# to clear them is OUT OF SCOPE (SOURCE.md). Plan below retained as record.")
assert marker in txt, "marker not found"
with open(PATH, "w") as f:
    f.write(txt.replace(marker, new_marker))
print("updated status marker")