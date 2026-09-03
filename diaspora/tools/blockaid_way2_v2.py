#!/usr/bin/env python3
"""WAY2 completeness audit v2: NEW views -> OLD queries, coverage mode, long
timeout, memory-disciplined threads.  Evaluate only.

Usage: python3 blockaid_way2_v2.py [--endpoint EP] [--timeout-ms 60000]
"""
import json, subprocess, sys, os, time, argparse
from collections import Counter

ROOT = "/home/dev/project"
NEW_DIR = f"{ROOT}/reports/diaspora/results3/queries_from_runs"
OLD_DIR = f"{ROOT}/ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint"
CHECKER = f"{ROOT}/src/queries_from_runs/subsume/check_subsumed.sh"
DEFAULT_OUT = f"{ROOT}/reports/diaspora/results3/blockaid_new_vs_old"

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

def run_checker(queries, views, timeout_ms, threads, call_timeout_s=1800):
    env = dict(os.environ, SUBSUME_TIMEOUT_MS=str(timeout_ms),
               SUBSUME_SOLVER_THREADS=str(threads))
    inp = json.dumps({"queries": queries, "views": views})
    p = subprocess.run(["bash", CHECKER], input=inp, capture_output=True,
                       text=True, timeout=call_timeout_s, env=env)
    if p.returncode != 0:
        return {"covered": [None]*len(queries),
                "errors": {"global": f"rc={p.returncode}: {p.stderr[-2000:]}"}}
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        return {"covered": [None]*len(queries),
                "errors": {"global": f"bad json: {p.stdout[:2000]}"}}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", default=None)
    ap.add_argument("--timeout-ms", type=int, default=60000)
    ap.add_argument("--threads", type=int, default=3)
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()
    eps = [args.endpoint] if args.endpoint else list(ENDPOINTS)
    os.makedirs(args.out, exist_ok=True)
    for ep in eps:
        new_f, old_f = ENDPOINTS[ep]
        newq = parse_policy(os.path.join(NEW_DIR, new_f))
        oldq = parse_policy(os.path.join(OLD_DIR, old_f))
        print(f"\n=== {ep}: NEW={len(newq)} OLD={len(oldq)} timeout={args.timeout_ms}ms threads={args.threads} ===", flush=True)
        # probe views (empty queries -> view_errors only)
        probe = run_checker([], newq, 10000, 1, call_timeout_s=300)
        view_errs = probe.get("view_errors", {})
        usable = [q for i, q in enumerate(newq) if str(i) not in view_errs]
        kinds = Counter(v.split(":")[0] for v in view_errs.values())
        print(f"  usable NEW views: {len(usable)}/{len(newq)}"
              + (f"  rejected: {dict(kinds)}" if kinds else ""), flush=True)
        # full-set coverage: old queries vs usable new views
        t0 = time.time()
        res = run_checker(oldq, usable, args.timeout_ms, args.threads)
        dt = time.time() - t0
        cov = res["covered"]
        errs = res.get("errors", {})
        n_yes = sum(1 for c in cov if c is True)
        n_no = sum(1 for c in cov if c is False)
        n_err = sum(1 for c in cov if c is None)
        print(f"  WAY2 full-set: {n_yes} covered / {n_no} NOT / {n_err} errors ({dt:.0f}s)", flush=True)
        ekinds = Counter(v.split(":")[0] for v in errs.values())
        print(f"  error kinds: {dict(ekinds)}", flush=True)
        for i, c in enumerate(cov):
            if c is False:
                print(f"   OLD#{i} NOT COVERED: {oldq[i][:120]}", flush=True)
        # per-view discrimination for undecided + not-covered queries
        if n_err or n_no:
            print("  per-view discrimination...", flush=True)
            decided = {}
            for vi, v in enumerate(usable):
                res2 = run_checker(oldq, [v], args.timeout_ms, args.threads, call_timeout_s=1200)
                cov2 = res2["covered"]
                for i, c in enumerate(cov2):
                    if c is True:
                        decided.setdefault(i, []).append(vi)
                print(f"    view {vi}/{len(usable)} done", flush=True)
            for i in range(len(oldq)):
                if i in decided:
                    print(f"   OLD#{i} COVERED by views {decided[i]}: {oldq[i][:90]}...", flush=True)
                elif cov[i] is False:
                    print(f"   OLD#{i} NOT COVERED (confirmed): {oldq[i][:90]}...", flush=True)
                else:
                    print(f"   OLD#{i} UNDECIDED: {oldq[i][:90]}...", flush=True)
        result = {"n_new": len(newq), "n_old": len(oldq), "usable_new_views": usable,
                  "view_errors": view_errs, "way2_full": {"covered": cov, "errors": errs}}
        with open(os.path.join(args.out, f"{ep}_way2_v2.json"), "w") as f:
            json.dump(result, f, indent=2)
        print(f"  saved {ep}_way2_v2.json", flush=True)

if __name__ == "__main__":
    main()