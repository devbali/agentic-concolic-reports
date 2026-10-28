#!/usr/bin/env python3
"""Isolate which CAND-B assumption clears what: test each addition alone."""
import glob
import json
import os
import re
import sys

HERE = '/home/dev/project/reports/diaspora/results3/people_show'
sys.path.insert(0, HERE)
sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.coverage import CoverageChecker
from concolic_engine.run import Run
from concolic_engine.assumptions import OneSideUntrackedPathAssumption
import coverage_assumptions as ca

_LEN_RE = re.compile(r"len\(([^()]+)\)")


def fix_len_names(dump):
    return json.loads(_LEN_RE.sub(r"SYM_LEN_\1", json.dumps(dump)))


runs = []
for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
    try:
        raw = json.load(open(p))
        run = Run.from_dict(fix_len_names(raw))
    except Exception:
        continue
    runs.append(run)

CONT_F2 = "Contains(StringVal('@'), SYM_RESULT_ActiveRecord__FinderMethods_first_2_diaspora_handle)"
IDX_F2 = "IndexOf(SYM_RESULT_ActiveRecord__FinderMethods_first_2_diaspora_handle, StringVal('@')) == 2"
NE_AUTH = "(assoc_author_guid != StringVal(''))"
NE_F2G = "(SYM_RESULT_ActiveRecord__FinderMethods_first_2_guid != StringVal(''))"
NE_F1G = "(SYM_RESULT_ActiveRecord__FinderMethods_first_1_guid != StringVal(''))"
NE_VUG = "(SYM_PERSON_via_user_guid != StringVal(''))"


def run_checker(assumptions, tag, detail=False):
    checker = CoverageChecker(runs=runs, assumptions=assumptions)
    result = checker.check_coverage()
    blocking = [m for m in result.missing if not m.untracked]
    row_re = re.compile(r"Relation_records_(\d+)_rows")
    fam48 = sum(1 for m in result.missing
                if len(set(int(g.group(1)) for g in row_re.finditer(m.node_constraint))) >= 4)
    fam16 = sum(1 for m in result.missing
                if set(int(g.group(1)) for g in row_re.finditer(m.node_constraint)) == {4, 5})
    print("%s: MISSING=%d BLOCKING=%d TRUNCATED=%s ASSUMPTIONS=%d fam48=%d fam16=%d"
          % (tag, len(result.missing), len(blocking), result.truncated,
             result.assumptions_used, fam48, fam16))
    if detail and result.missing:
        print("  first few:")
        for m in result.missing[:5]:
            print("    %s" % m.node_constraint[:160])
    return result


def base_with(exprs_taken, exprs_nottaken):
    """Add OneSide(tracked=taken) for exprs_taken; OneSide(not_taken) for exprs_nottaken."""
    s = ca.build()
    for e in exprs_taken:
        s.assumptions.append(OneSideUntrackedPathAssumption(
            expr=e, tracked_side="taken",
            description="first_2 handle false side unreachable by construction",
            agent_notes=ca.HANDLE_UNTRACKED,
        ))
    for e in exprs_nottaken:
        s.assumptions.append(OneSideUntrackedPathAssumption(
            expr=e, tracked_side="not_taken",
            description="'!=''' true side never witnessed over the drained corpus",
            agent_notes="0/7673 witnesses; F-count == ==''-T count exactly across all guid vars",
        ))
    return s


run_checker(base_with([], []), "BASE")
run_checker(base_with([CONT_F2, IDX_F2], []), "first2-handle-only")
run_checker(base_with([], [NE_AUTH, NE_F2G]), "guid-ne-only")
run_checker(base_with([], [NE_AUTH]), "auth-ne-only")
run_checker(base_with([], [NE_F2G]), "f2g-ne-only")
run_checker(base_with([], [NE_F1G, NE_VUG]), "other-guid-ne")  # NOT the right ones
run_checker(base_with([CONT_F2, IDX_F2], [NE_AUTH, NE_F2G]), "all-4")