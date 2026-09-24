#!/usr/bin/env python3
"""Compare NEW extracted policies (reports/diaspora/results3/queries_from_runs/)
against OLD extracted policies (ruby_examples/dse-apps/policies/extracted/
diaspora/per-endpoint/) using blockaid coverage mode, BOTH WAYS.

WAY1: views = OLD extracted, queries = NEW extracted
      -> covered[i] = new query i is answerable from the old extracted policy.
WAY2: views = NEW extracted, queries = OLD extracted
      -> covered[i] = old query i is answerable from the new extracted policy.

Evaluate only. No input normalization, no harness changes; parse failures and
timeouts are reported as errors.

Usage: python3 blockaid_new_vs_old.py [--endpoint EP] [--out DIR]
"""
import json, subprocess, sys, os, time, argparse

ROOT = "/home/dev/project"
NEW_DIR = f"{ROOT}/reports/diaspora/results3/queries_from_runs"
OLD_DIR = f"{ROOT}/ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint"
# App-specific input for the subsume harness: src/queries_from_runs is
# app-agnostic and requires an app config; the diaspora side supplies it.
os.environ.setdefault("QFR_APP_CONFIG",
                      "/home/dev/project/reports/diaspora/queries_config/app.json")
CHECKER = f"{ROOT}/src/queries_from_runs/subsume/check_subsumed.sh"
DEFAULT_OUT = f"{ROOT}/reports/diaspora/results3/blockaid_new_vs_old"

ENDPOINTS = {
    "comments_index":      ("comments_index.sql",      "comments-index.sql"),
    "conversations_index": ("conversations_index.sql", "conversations-index.sql"),
    "notifications_index": ("notifications_index.sql", "notifications-index.sql"),
}

def parse_policy(path):
    stmts = []
    for line in open(path):
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        stmts.append(s.rstrip(";").strip())
    return [s for s in stmts if s.upper().startswith("SELECT")]

def run_checker(queries, views, timeout_s=1800):
    inp = json.dumps({"queries": queries, "views": views})
    p = subprocess.run(["bash", CHECKER], input=inp, capture_output=True,
                       text=True, timeout=timeout_s)
    if p.returncode != 0:
        return {"covered": [None]*len(queries),
                "errors": {"global": f"rc={p.returncode}: {p.stderr[-2000:]}"}}
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        return {"covered": [None]*len(queries),
                "errors": {"global": f"bad json: {p.stdout[:2000]}"}}

def summarize(ep, direction, n_q, n_v, res, dt):
    cov = res["covered"]
    n_yes = sum(1 for c in cov if c is True)
    n_no = sum(1 for c in cov if c is False)
    n_err = sum(1 for c in cov if c is None)
    print(f"  {direction}: views={n_v} queries={n_q} -> {n_yes} covered / "
          f"{n_no} NOT covered / {n_err} errors  ({dt:.0f}s)", flush=True)
    return {"covered": n_yes, "not_covered": n_no, "errors": n_err,
            "detail": res}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", default=None)
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    eps = [args.endpoint] if args.endpoint else list(ENDPOINTS)
    summary = {}
    for ep in eps:
        new_f, old_f = ENDPOINTS[ep]
        new_path = os.path.join(NEW_DIR, new_f)
        old_path = os.path.join(OLD_DIR, old_f)
        if not os.path.exists(new_path):
            print(f"!! {ep}: no new file {new_path}", flush=True); continue
        if not os.path.exists(old_path):
            print(f"!! {ep}: no old file {old_path}", flush=True); continue
        newq = parse_policy(new_path)
        oldq = parse_policy(old_path)
        print(f"\n=== {ep}: NEW={len(newq)} OLD={len(oldq)} ===", flush=True)

        t0 = time.time()
        r1 = run_checker(newq, oldq)
        t1 = time.time() - t0
        s1 = summarize(ep, "WAY1 (old views -> new queries)", len(newq), len(oldq), r1, t1)

        t0 = time.time()
        r2 = run_checker(oldq, newq)
        t2 = time.time() - t0
        s2 = summarize(ep, "WAY2 (new views -> old queries)", len(oldq), len(newq), r2, t2)

        summary[ep] = {"n_new": len(newq), "n_old": len(oldq),
                       "way1": s1, "way2": s2}
        with open(os.path.join(args.out, f"{ep}.json"), "w") as f:
            json.dump(summary[ep], f, indent=2)

    with open(os.path.join(args.out, "_summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    print(f"\nResults in {args.out}/", flush=True)

if __name__ == "__main__":
    main()