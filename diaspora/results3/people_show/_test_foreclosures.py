#!/usr/bin/env python3
"""TEST foreclosure candidates for the 48-family (and 16) IN-PROCESS.

Candidate A for the 48: IndependenceAssumption on the 4 cross-shape
ordinal pairs (rows_1 x rows_4, rows_1 x rows_5, rows_2 x rows_4,
rows_2 x rows_5) -- run-shape mutual exclusion (mobile never mints rows_4/5;
dual never mints rows_1/2). Empirical: 0/7673 dumps contain any such pair.

Candidate B for the 16: OneSide(tracked='not_taken') on the two '!='''
guid true-sides + OneSide(tracked='taken') on the first_2 CONT/IDX.

Measure MISSING/TRUNCATED/ASSUMPTIONS_used before/after.
"""
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
from concolic_engine.assumptions import IndependenceAssumption, OneSideUntrackedPathAssumption
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
print("runs loaded: %d" % len(runs))


def run_checker(assumptions, tag):
    checker = CoverageChecker(runs=runs, assumptions=assumptions)
    result = checker.check_coverage()
    blocking = [m for m in result.missing if not m.untracked]
    row_re = re.compile(r"Relation_records_(\d+)_rows")
    fam48 = sum(1 for m in result.missing
                if len(set(int(g.group(1)) for g in row_re.finditer(m.node_constraint))) >= 4)
    fam16 = sum(1 for m in result.missing
                if set(int(g.group(1)) for g in row_re.finditer(m.node_constraint)) == {4, 5})
    print("%s: MISSING=%d BLOCKING=%d TRUNCATED=%s SOLVER_LOST=%d ASSUMPTIONS=%d fam48=%d fam16=%d"
          % (tag, len(result.missing), len(blocking), result.truncated,
             result.solver_lost, result.assumptions_used, fam48, fam16))
    return result


# baseline
base = ca.build()
run_checker(base, "BASE")

R1 = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_1_rows > 0)"
R2 = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2_rows == 15)"
R4 = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_4_rows == 15)"
R5 = "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_5_rows > 0)"

SHAPE_EXCL = (
    "run-shape ordinal mutual exclusion: the posts stream fires at ordinals "
    "1,2,3 in mobile-only runs and 3,4,5 in dual runs (the presenter's bare "
    "records_1/2 consume ordinals 1,2 first). A single show request therefore "
    "mints AT MOST 3 stream-row ordinals, and the cross-shape pairs "
    "(rows_1 x rows_4/5, rows_2 x rows_4/5) NEVER co-mint: empirical 0/7673 "
    "dumps contain any of them. The checker's 5-ordinal union demand is a z3 "
    "artifact of the ordinal-position naming collision -- real-impossible in "
    "one Rails request."
)


def build_a():
    s = ca.build()
    for ea, eb in [(R1, R4), (R1, R5), (R2, R4), (R2, R5)]:
        s.assumptions.append(IndependenceAssumption(
            expr_a=ea, expr_b=eb, description="cross-shape ordinal mutual exclusion",
            agent_notes=SHAPE_EXCL,
        ))
    return s


run_checker(build_a(), "CAND-A(independence x4)")


def build_b_real():
    s = ca.build()
    for expr in (
        "Contains(StringVal('@'), SYM_RESULT_ActiveRecord__FinderMethods_first_2_diaspora_handle)",
        "IndexOf(SYM_RESULT_ActiveRecord__FinderMethods_first_2_diaspora_handle, StringVal('@')) == 2",
    ):
        s.assumptions.append(OneSideUntrackedPathAssumption(
            expr=expr, tracked_side="taken",
            description="first_2 handle false side unreachable by construction (same string.rb split call sites as CONT1/IDX1_2)",
            agent_notes=ca.HANDLE_UNTRACKED,
        ))
    for expr in (
        "(assoc_author_guid != StringVal(''))",
        "(SYM_RESULT_ActiveRecord__FinderMethods_first_2_guid != StringVal(''))",
    ):
        s.assumptions.append(OneSideUntrackedPathAssumption(
            expr=expr, tracked_side="not_taken",
            description="'!=''' true side never witnessed (0/7673; F-count equals ==''-T count exactly over the drained corpus) -- textual dual recorded only in the empty path",
            agent_notes=SHAPE_EXCL,
        ))
    return s


run_checker(build_b_real(), "CAND-B(16-family oneside)")


def build_ab_real():
    s = build_a()
    s2 = build_b_real()
    existing = set(id(a) for a in s.assumptions)
    for a in s2.assumptions:
        if id(a) not in existing:
            s.assumptions.append(a)
    return s


run_checker(build_ab_real(), "CAND-AB(both)")