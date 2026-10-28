#!/usr/bin/env python3
"""Probe: what SymbolicConstraintAssumption z3_exprs does build() emit,
and do they name the SAME guard vars that appear in coverage_summary's
missing[] node_constraint strings?"""
import json
import os
import sys

HERE = "/home/dev/project/reports/diaspora/results3/people_show"
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

import coverage_assumptions

as_ = coverage_assumptions.build()
print("total assumptions:", len(as_.assumptions))

cons = [a for a in as_.assumptions if type(a).__name__ == "SymbolicConstraintAssumption"]
print("SymbolicConstraintAssumption count:", len(cons))
for c in cons:
    print("  z3_expr:", c.z3_expr)

# load missing[] node_constraint guard-var mentions
data = json.load(open(os.path.join(HERE, "coverage_summary.json")))
missing = data["missing"]
guard_tokens = set()
for it in missing:
    nc = it.get("node_constraint", "")
    for tok in [
        "FinderMethods_first_1_not_found",
        "FinderMethods_first_1_closed_account",
        "FinderMethods_first_2_not_found",
        "FinderMethods_first_2_closed_account",
        "ClassMethods_find_by_1_not_found",
        "ClassMethods_find_by_1_closed_account",
        "ClassMethods_find_by_2_not_found",
        "ClassMethods_find_by_2_closed_account",
        "PERSON_via_user_closed_account",
    ]:
        if tok in nc:
            guard_tokens.add(tok)
print("\nguard tokens appearing in missing[] node_constraints:")
for t in sorted(guard_tokens):
    print("  ", t)