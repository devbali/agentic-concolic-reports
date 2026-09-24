#!/usr/bin/env python3
"""Rewrite NEW-policy queries_for_runs files: replace _SYM_RESULT_* binds
with _MY_UID into a temp dir, then probe usability via check_subsumed.sh."""
import re, os, json, subprocess, sys

ROOT = "/home/dev/project"
SRC = ROOT + "/reports/diaspora/results3/queries_from_runs"
DST = SRC + "/_rewritten"
os.makedirs(DST, exist_ok=True)
# App-specific input for the subsume harness: src/queries_from_runs is
# app-agnostic and requires an app config; the diaspora side supplies it.
os.environ.setdefault("QFR_APP_CONFIG",
                      "/home/dev/project/reports/diaspora/queries_config/app.json")
CHECKER = ROOT + "/src/queries_from_runs/subsume/check_subsumed.sh"
EPS = ["comments_index", "conversations_index"]

def probe(views, tmo=20000):
    env = dict(os.environ, SUBSUME_TIMEOUT_MS=str(tmo), SUBSUME_SOLVER_THREADS="1")
    p = subprocess.run(["bash", CHECKER], input=json.dumps({"queries": [], "views": views}),
                       capture_output=True, text=True, timeout=300, env=env)
    if p.returncode != 0:
        return None, "rc=" + str(p.returncode)
    return json.loads(p.stdout), None

for ep in EPS:
    src = os.path.join(SRC, ep + ".sql")
    dst = os.path.join(DST, ep + ".sql")
    txt = open(src).read()
    before = txt.count("_SYM_RESULT_")
    txt2 = re.sub(r"_SYM_RESULT_[A-Za-z0-9_]+", "_MY_UID", txt)
    open(dst, "w").write(txt2)
    # parse statements like the harness does
    stmts = []
    for line in txt2.splitlines():
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        stmts.append(s.rstrip(";").strip())
    sel = [s for s in stmts if s.upper().startswith("SELECT")]
    out, err = probe(sel)
    n = len(sel)
    if out is None:
        print(ep + ": probe failed " + str(err))
        continue
    verrs = out.get("view_errors", {})
    ok = n - len(verrs)
    kinds = {}
    for k, v in verrs.items():
        msg = str(v)
        key = msg.split(":")[0][:60]
        kinds[key] = kinds.get(key, 0) + 1
    print(ep + ": rewritten " + str(before) + " binds -> " + str(n) + " SELECTs, usable " + str(ok) + "/" + str(n))
    for k, c in sorted(kinds.items(), key=lambda x: -x[1]):
        print("   reject " + str(c) + "x " + k)