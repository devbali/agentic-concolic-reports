#!/usr/bin/env python3
"""Bounded true-demand probe for people_show coverage (moderate caps).

Honors the 'never unbounded clique enumeration' directive: hard self-timeout
of 180s (moderate caps: max_missing_per_clique=100, max_cliques=2000). If it
exceeds the budget it prints TOO_SLOW and exits 3 — no unbounded run.
"""
import glob
import json
import os
import signal
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)

from concolic_engine.run import Run                      # noqa: E402
from concolic_engine.coverage import CoverageChecker     # noqa: E402
import coverage_report as cr                             # noqa: E402
import coverage_assumptions as ca                        # noqa: E402

BUDGET = 180.0
CAP_CLIQUES = 2000
CAP_PER_CLIQUE = 100


def main() -> int:
    def bail(signum, frame):  # pragma: no cover - alarm handler
        print("TOO_SLOW budget=%.0fs cap_cliques=%d cap_per_clique=%d"
              % (BUDGET, CAP_CLIQUES, CAP_PER_CLIQUE), flush=True)
        sys.exit(3)

    signal.signal(signal.SIGALRM, bail)
    signal.alarm(int(BUDGET) + 1)

    dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
    runs = []
    for p in dumps:
        try:
            raw = json.load(open(p))
            runs.append(Run.from_dict(cr.fix_len_names(raw)))
        except Exception:
            pass
    print("loaded %d runs" % len(runs), flush=True)

    assumptions = ca.build()
    t0 = time.time()
    result = CoverageChecker(
        runs,
        assumptions=assumptions,
        max_missing_per_clique=CAP_PER_CLIQUE,
        max_cliques=CAP_CLIQUES,
    ).check_coverage()
    elapsed = time.time() - t0
    signal.alarm(0)

    missing = result.missing
    blocking = [m for m in missing if not getattr(m, "untracked", False)]
    print("TRUE-DEMAND cap_cliques=%d cap_per_clique=%d elapsed=%.1fs"
          % (CAP_CLIQUES, CAP_PER_CLIQUE, elapsed), flush=True)
    print("MISSING=%d BLOCKING=%d (bounded default was 64)" % (len(missing), len(blocking)), flush=True)
    print("assumptions_used=%s" % getattr(result, "assumptions_used", "?"), flush=True)

    # Break down the demand composition
    from collections import Counter
    cats = Counter()
    for m in missing:
        c = getattr(m, "node_constraint", str(m))
        if "public_details == True" in c:
            cats["PD-T involved"] += 1
        if "via_user" in c:
            cats["via_user (branch B)"] += 1
        if "FinderMethods_first_1" in c:
            cats["first_1 (branch A)"] += 1
        if "SubString" in c and "== ''" in c:
            cats["blank-family"] += 1
        if "Contains(StringVal('.')" in c:
            cats["dot-family"] += 1
        if "records_1" in c or "records_2" in c or "records_3" in c:
            cats["record-length"] += 1
    print("composition:", dict(cats), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())