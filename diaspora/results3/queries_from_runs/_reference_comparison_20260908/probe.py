#!/usr/bin/env python3
"""Usability probe: views = policy file, queries = []. Prints view_errors grouped by cause."""
import json, os, subprocess, sys, re, collections
# App-specific input for the subsume harness: src/queries_from_runs is
# app-agnostic and requires an app config; the diaspora side supplies it.
os.environ.setdefault("QFR_APP_CONFIG",
                      "/home/dev/project/reports/diaspora/queries_config/app.json")
CHECKER = "/home/dev/project/src/queries_from_runs/subsume/check_subsumed.sh"
def load(path):
    out = []
    for line in open(path):
        s = line.split("--")[0].strip().rstrip(";").strip() if not line.lstrip().startswith("--") else ""
        if s.upper().startswith("SELECT"): out.append(s)
    return out
def cause(msg):
    m = msg
    if "unrecognized" in m or "Unknown const" in m or "unknown const" in m.lower(): return "unresolved placeholder const"
    if "LIMIT/OFFSET" in m: return "LIMIT/OFFSET"
    if "aggregate/function in select list" in m: return "aggregate in select list"
    if "solver-type probe" in m: return "solver-type probe"
    if "unsupported as subsumer" in m: return "unsupported as subsumer (shape)"
    if "unsupported as checked" in m: return "unsupported as checked (shape)"
    if "parse" in m.lower(): return "parse error"
    return m[:60]
path = sys.argv[1]
views = load(path)
env = {k: v for k, v in os.environ.items() if k != "JAVA_TOOL_OPTIONS"}
env.update(SUBSUME_TIMEOUT_MS="5000", SUBSUME_SOLVER_THREADS="1")
p = subprocess.run([CHECKER], input=json.dumps({"views": views, "queries": []}), capture_output=True, text=True, env=env)
r = json.loads(p.stdout)
ve = r.get("view_errors", {})
print(f"{path}: {len(views)} views, usable {len(views)-len(ve)}, quarantined {len(ve)}")
c = collections.Counter(cause(v) for v in ve.values())
for k, n in c.most_common(): print(f"   {n:3d}  {k}")
json.dump({"n_views": len(views), "view_errors": ve, "views": views}, open(sys.argv[2], "w"), indent=1)
for k, v in sorted(ve.items(), key=lambda kv: int(kv[0])): print(f"   view#{int(k)+1}: {v[:140]}")
