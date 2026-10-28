#!/usr/bin/env python3
"""Test: does the solver treat the 6c guard pins as genuinely conflicting
with a guard-True demand? Uses the real dump corpus to collect the merged
declarations, then asks check_satisfiability for:
  [pin, demand]  where pin=(G == False), demand=(G == True)
under those declarations."""
import glob
import json
import os
import sys

HERE = "/home/dev/project/reports/diaspora/results3/people_show"
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.run import Run
from concolic_engine.solver import check_satisfiability

GUARDS = [
    "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found",
    "SYM_RESULT_ActiveRecord__FinderMethods_first_2_closed_account",
    "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_2_not_found",
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found",
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account",
    "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found",
    "SYM_PERSON_via_user_closed_account",
]

runs = []
decls_seen = set()
decls = []
for p in sorted(glob.glob(os.path.join(HERE, "dump_*.json"))):
    try:
        raw = json.load(open(p))
    except Exception:
        continue
    if raw.get("error"):
        continue
    try:
        r = Run.from_dict(raw)
    except Exception:
        continue
    runs.append(r)
    for d in r.z3_declarations():
        name = d.split("=", 1)[0].strip()
        if name not in decls_seen:
            decls_seen.add(name)
            decls.append(d)

print("runs:", len(runs), "decls:", len(decls))

for g in GUARDS:
    dem = f"({g} == True)"
    pin = f"({g} == False)"
    res = check_satisfiability([pin, dem], decls, 30000)
    print("%-92s demand(X==True) AND pin(X==False) -> satisfiable=%s"
          % (g, getattr(res, "satisfiable", "?")))