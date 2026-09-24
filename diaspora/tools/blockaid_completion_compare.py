#!/usr/bin/env python3
"""Run blockaid coverage mode BOTH WAYS between the handwritten reference
policy and the extracted policies, per endpoint, to see completion.

Way 1 (extraction soundness): views = handwritten reference, queries = extracted
  -> covered[i] means extracted query i is answerable from the reference views.
Way 2 (extraction completeness): views = extracted, queries = handwritten
  -> covered[i] means handwritten view i is answerable from the extracted views.

Usage:
  python3 blockaid_completion_compare.py [--endpoint EP] [--out DIR]
"""
import json, subprocess, sys, os, time, argparse, collections

ROOT = "/home/dev/project"
HANDWRITTEN = f"{ROOT}/ruby_examples/dse-apps/policies/handwritten/diaspora/policies.sql"
EXTRACTED_DIR = f"{ROOT}/ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint"
# App-specific input for the subsume harness: src/queries_from_runs is
# app-agnostic and requires an app config; the diaspora side supplies it.
os.environ.setdefault("QFR_APP_CONFIG",
                      "/home/dev/project/reports/diaspora/queries_config/app.json")
CHECKER = f"{ROOT}/src/queries_from_runs/subsume/check_subsumed.sh"
DEFAULT_OUT = f"{ROOT}/reports/diaspora/results3/blockaid_completion"

ENDPOINTS = {
    "comments_index": "comments-index.sql",
    "conversations_index": "conversations-index.sql",
    "notifications_index": "notifications-index.sql",
    "posts_show": "posts-show.sql",
    "people_show": "people-show.sql",
    "people_stream": "people-stream.sql",
}

def parse_policy(path):
    stmts = []
    for line in open(path):
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        stmts.append(s.rstrip(";").strip())
    return [s for s in stmts if s.upper().startswith("SELECT")]

def run_checker(queries, views, timeout_s=600):
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

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", default=None, help="one endpoint or all")
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    hw = parse_policy(HANDWRITTEN)
    print(f"handwritten reference: {len(hw)} views", flush=True)

    eps = [args.endpoint] if args.endpoint else list(ENDPOINTS)
    summary = {}
    for ep in eps:
        fname = ENDPOINTS[ep]
        path = os.path.join(EXTRACTED_DIR, fname)
        if not os.path.exists(path):
            print(f"!! {ep}: no file {fname}", flush=True)
            continue
        ex = parse_policy(path)
        print(f"\n=== {ep}: {len(ex)} extracted queries ===", flush=True)

        # Way 1: handwritten views cover extracted queries
        t0 = time.time()
        r1 = run_checker(ex, hw)
        dt1 = time.time() - t0
        cov1 = r1["covered"]
        n_yes1 = sum(1 for c in cov1 if c is True)
        n_no1 = sum(1 for c in cov1 if c is False)
        n_err1 = sum(1 for c in cov1 if c is None)
        print(f"  WAY1 (ref views -> extracted queries): {n_yes1} covered / "
              f"{n_no1} NOT covered / {n_err1} errors  ({dt1:.0f}s)", flush=True)

        # Way 2: extracted views cover handwritten queries
        t0 = time.time()
        r2 = run_checker(hw, ex)
        dt2 = time.time() - t0
        cov2 = r2["covered"]
        n_yes2 = sum(1 for c in cov2 if c is True)
        n_no2 = sum(1 for c in cov2 if c is False)
        n_err2 = sum(1 for c in cov2 if c is None)
        print(f"  WAY2 (extracted views -> ref queries): {n_yes2} covered / "
              f"{n_no2} NOT covered / {n_err2} errors  ({dt2:.0f}s)", flush=True)

        summary[ep] = {
            "n_extracted": len(ex), "n_reference": len(hw),
            "way1": {"covered": n_yes1, "not_covered": n_no1, "errors": n_err1,
                     "detail": r1},
            "way2": {"covered": n_yes2, "not_covered": n_no2, "errors": n_err2,
                     "detail": r2},
        }
        with open(os.path.join(args.out, f"{ep}.json"), "w") as f:
            json.dump(summary[ep], f, indent=2)

    with open(os.path.join(args.out, "_summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    print(f"\nResults in {args.out}/", flush=True)

if __name__ == "__main__":
    main()