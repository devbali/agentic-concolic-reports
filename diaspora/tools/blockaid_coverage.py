#!/usr/bin/env python3
"""Is each query covered by this policy?  (blockaid coverage mode)

    blockaid_coverage.py <policy.sql> <queries.sql> [--timeout-ms N] [--threads N]

Both files are plain .sql — one statement per line, `--` comments ignored.
Prints one line per query and exits 1 if any query is not proven covered.

  COVERED     UNSAT proof: answerable from the policy
  NOT COVERED SAT: z3 built two DBs agreeing on every view, differing here
  UNKNOWN     timeout or error -- NEVER read this as "not covered"

Views blockaid cannot use (parse failure, solver-type probe, LIMIT/aggregate/
GROUP BY) are dropped by the checker and listed at the end: a NOT COVERED is
only meaningful once you have looked at that list.
"""
import json, os, subprocess, sys

# App-specific input for the subsume harness: src/queries_from_runs is
# app-agnostic and requires an app config; the diaspora side supplies it.
os.environ.setdefault("QFR_APP_CONFIG",
                      "/home/dev/project/reports/diaspora/queries_config/app.json")
CHECKER = "/home/dev/project/src/queries_from_runs/subsume/check_subsumed.sh"

def load(path):
    out = []
    for line in open(path):
        s = line.split("--")[0].strip().rstrip(";").strip()
        if s.upper().startswith("SELECT"):
            out.append(s)
    return out

a = sys.argv[1:]
def opt(name, default):
    return a[a.index(name) + 1] if name in a else default
timeout, threads = opt("--timeout-ms", "60000"), opt("--threads", "3")
policy, queries = [x for x in a if not x.startswith("--")][:2]

views, qs = load(policy), load(queries)
env = {**os.environ, "SUBSUME_TIMEOUT_MS": timeout, "SUBSUME_SOLVER_THREADS": threads}
env.pop("JAVA_TOOL_OPTIONS", None)          # a leaked value breaks the JVM run
r = json.loads(subprocess.run(
    [CHECKER], input=json.dumps({"views": views, "queries": qs}),
    capture_output=True, text=True, env=env, check=True).stdout)

bad = 0
for i, q in enumerate(qs):
    c = r["covered"][i]
    label = {True: "COVERED    ", False: "NOT COVERED", None: "UNKNOWN    "}[c]
    bad += c is not True
    print(f"{label}  {q[:110]}")
    if c is None and str(i) in r.get("errors", {}):
        print(f"               reason: {r['errors'][str(i)]}")

ve = r.get("view_errors", {})
print(f"\n{len(qs) - bad}/{len(qs)} covered by {len(views) - len(ve)}/{len(views)} usable views")
for k, v in ve.items():
    print(f"  unusable view {k}: {v[:100]}")
sys.exit(1 if bad else 0)
