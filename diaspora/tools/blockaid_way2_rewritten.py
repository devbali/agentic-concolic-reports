#!/usr/bin/env python3
"""WAY2 full-set with REWRITTEN new views (_SYM_RESULT_* -> _MY_UID), 120s."""
import re, os, json, subprocess, sys, time

ROOT = "/home/dev/project"
NEW_DIR = ROOT + "/reports/diaspora/results3/queries_from_runs/_rewritten"
OLD_DIR = ROOT + "/ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint"
OUT = ROOT + "/reports/diaspora/results3/blockaid_new_vs_old"
# App-specific input for the subsume harness: src/queries_from_runs is
# app-agnostic and requires an app config; the diaspora side supplies it.
os.environ.setdefault("QFR_APP_CONFIG",
                      "/home/dev/project/reports/diaspora/queries_config/app.json")
CHECKER = ROOT + "/src/queries_from_runs/subsume/check_subsumed.sh"
EPS = {
    "comments_index": ("comments_index.sql", "comments-index.sql"),
    "conversations_index": ("conversations_index.sql", "conversations-index.sql"),
}

def parse(path):
    out = []
    for line in open(path):
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        out.append(s.rstrip(";").strip())
    return [s for s in out if s.upper().startswith("SELECT")]

def run(queries, views, tmo, thr, cto=900):
    env = dict(os.environ, SUBSUME_TIMEOUT_MS=str(tmo), SUBSUME_SOLVER_THREADS=str(thr))
    p = subprocess.run(["bash", CHECKER], input=json.dumps({"queries": queries, "views": views}),
                       capture_output=True, text=True, timeout=cto, env=env)
    if p.returncode != 0:
        return {"covered": [None] * len(queries), "errors": {"global": "rc=" + str(p.returncode)}}
    try:
        return json.loads(p.stdout)
    except Exception:
        return {"covered": [None] * len(queries), "errors": {"global": "bad-json"}}

def main(ep, tmo=120000, thr=3):
    nf, of = EPS[ep]
    vws = parse(os.path.join(NEW_DIR, nf))
    oq = parse(os.path.join(OLD_DIR, of))
    print("=== " + ep + " REWRITTEN views=" + str(len(vws)) + " OLD=" + str(len(oq)) + " tmo=" + str(tmo) + " ===", flush=True)
    probe = run([], vws, 20000, 1, cto=300)
    verrs = probe.get("view_errors", {})
    usable = [q for i, q in enumerate(vws) if str(i) not in verrs]
    print("usable views: " + str(len(usable)) + "/" + str(len(vws)), flush=True)
    t0 = time.time()
    r = run(oq, usable, tmo, thr)
    dt = time.time() - t0
    cov = r.get("covered", [])
    errs = r.get("errors", {})
    kinds = {}
    for k, v in errs.items():
        msg = str(v)
        key = msg.split(":")[0][:50]
        kinds[key] = kinds.get(key, 0) + 1
    n_cov = sum(1 for c in cov if c is True)
    n_not = sum(1 for c in cov if c is False)
    n_tmo = sum(1 for c in cov if c is None)
    print("WAY2 rewritten full-set: " + str(n_cov) + " covered / " + str(n_not) + " NOT / " + str(n_tmo) + " errors (" + str(int(dt)) + "s)", flush=True)
    print("error kinds: " + str(kinds), flush=True)
    for i, c in enumerate(cov):
        if c is True:
            print("OLD#" + str(i) + " COVERED: " + oq[i][:80], flush=True)
        elif c is False:
            print("OLD#" + str(i) + " NOT: " + oq[i][:80], flush=True)
    out = {"covered": cov, "errors": errs, "n_new_usable": len(usable), "n_old": len(oq), "timeout_ms": tmo}
    with open(os.path.join(OUT, ep + "_way2_rewritten.json"), "w") as f:
        json.dump(out, f, indent=2, default=str)
    print("saved " + ep + "_way2_rewritten.json", flush=True)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "comments_index", int(sys.argv[2]) if len(sys.argv) > 2 else 120000, int(sys.argv[3]) if len(sys.argv) > 3 else 3)