#!/usr/bin/env python3
"""WAY2 full-set coverage: NEW views -> OLD queries, one shot, no per-view.
Usage: python3 blockaid_way2_single.py <endpoint> <timeout-ms>
"""
import json, subprocess, sys, os, time
from collections import Counter

ROOT = "/home/dev/project"
NEW_DIR = f"{ROOT}/reports/diaspora/results3/queries_from_runs"
OLD_DIR = f"{ROOT}/ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint"
CHECKER = f"{ROOT}/src/queries_from_runs/subsume/check_subsumed.sh"
OUT = f"{ROOT}/reports/diaspora/results3/blockaid_new_vs_old"

ENDPOINTS = {
    "comments_index":      ("comments_index.sql",      "comments-index.sql"),
    "conversations_index": ("conversations_index.sql", "conversations-index.sql"),
}

def parse_policy(path):
    stmts = []
    for line in open(path):
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        stmts.append(s.rstrip(";").strip())
    return [s for s in stmts if s.upper().startswith("SELECT")]

def run_checker(queries, views, timeout_ms, threads, call_timeout_s=3600):
    env = dict(os.environ, SUBSUME_TIMEOUT_MS=str(timeout_ms),
               SUBSUME_SOLVER_THREADS=str(threads))
    p = subprocess.run(["bash", CHECKER],
                       input=json.dumps({"queries": queries, "views": views}),
                       capture_output=True, text=True, timeout=call_timeout_s, env=env)
    if p.returncode != 0:
        return {"covered": [None]*len(queries),
                "errors": {"global": f"rc={p.returncode}: {p.stderr[-2000:]}"}}
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        return {"covered": [None]*len(queries),
                "errors": {"global": f"bad json: {p.stdout[:2000]}"}}

def main():
    ep = sys.argv[1]
    timeout_ms = int(sys.argv[2]) if len(sys.argv) > 2 else 60000
    threads = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    new_f, old_f = ENDPOINTS[ep]
    newq = parse_policy(os.path.join(NEW_DIR, new_f))
    oldq = parse_policy(os.path.join(OLD_DIR, old_f))
    probe = run_checker([], newq, 10000, 1, call_timeout_s=300)
    view_errs = probe.get("view_errors", {})
    usable = [q for i, q in enumerate(newq) if str(i) not in view_errs]
    print(f"{ep}: NEW={len(newq)} usable={len(usable)} OLD={len(oldq)} timeout={timeout_ms}ms threads={threads}", flush=True)
    t0 = time.time()
    res = run_checker(oldq, usable, timeout_ms, threads)
    dt = time.time() - t0
    cov = res["covered"]
    errs = res.get("errors", {})
    n_yes = sum(1 for c in cov if c is True)
    n_no = sum(1 for c in cov if c is False)
    n_err = sum(1 for c in cov if c is None)
    print(f"WAY2 full-set: {n_yes} covered / {n_no} NOT / {n_err} errors ({dt:.0f}s)", flush=True)
    ekinds = Counter(v.split(":")[0] for v in errs.values())
    print(f"error kinds: {dict(ekinds)}", flush=True)
    for i, c in enumerate(cov):
        status = "COVERED" if c is True else ("NOT-COVERED" if c is False else "UNDECIDED")
        print(f"  OLD#{i} {status}: {oldq[i][:130]}", flush=True)
    with open(os.path.join(OUT, f"{ep}_way2_60s.json"), "w") as f:
        json.dump({"n_new": len(newq), "n_old": len(oldq), "usable": usable,
                   "view_errors": view_errs, "timeout_ms": timeout_ms,
                   "covered": cov, "errors": errs, "elapsed_s": dt}, f, indent=2)
    print(f"saved {ep}_way2_60s.json", flush=True)

if __name__ == "__main__":
    main()