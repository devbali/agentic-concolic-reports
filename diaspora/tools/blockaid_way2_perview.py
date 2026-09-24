#!/usr/bin/env python3
"""WAY2 completeness audit: NEW extracted as views, OLD extracted as queries.

Decomposes the view set per-view (subsets): for each usable NEW view v, run
blockaid coverage with views=[v] and queries = all OLD queries.  An old query
is COVERED iff at least one new view proves it answerable.  Also records which
new views are structurally unusable (rejected by probe) and which old queries
remain undecided even per-view (timeout).

Evaluate only.  Usage: python3 blockaid_way2_perview.py [--endpoint EP]
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
TIMEOUT_MS = os.environ.get("SUBSUME_TIMEOUT_MS", "30000")

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

def run_checker(queries, views, timeout_s=900):
    env = dict(os.environ, SUBSUME_TIMEOUT_MS=TIMEOUT_MS)
    inp = json.dumps({"queries": queries, "views": views})
    p = subprocess.run(["bash", CHECKER], input=inp, capture_output=True,
                       text=True, timeout=timeout_s, env=env)
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
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    eps = [args.endpoint] if args.endpoint else list(ENDPOINTS)

    for ep in eps:
        new_f, old_f = ENDPOINTS[ep]
        newq = parse_policy(os.path.join(NEW_DIR, new_f))
        oldq = parse_policy(os.path.join(OLD_DIR, old_f))
        print(f"\n=== {ep}: NEW={len(newq)} OLD={len(oldq)} (timeout={TIMEOUT_MS}ms) ===", flush=True)

        # Probe all NEW views first (one coverage call, no queries -> view_errors only).
        probe = run_checker([], newq)
        view_errs = probe.get("view_errors", {})
        usable = [q for i, q in enumerate(newq) if str(i) not in view_errs]
        print(f"  usable NEW views: {len(usable)}/{len(newq)}", flush=True)
        from collections import Counter
        kinds = Counter(v.split(":")[0] for v in view_errs.values())
        print(f"  unusable view reasons: {dict(kinds)}", flush=True)

        # Per-view coverage: old queries vs each usable new view individually.
        covered_by = {i: [] for i in range(len(oldq))}   # old idx -> new view idxs that cover it
        not_covered = {i: False for i in range(len(oldq))}
        still_undecided = {i: [] for i in range(len(oldq))}
        for vi, v in enumerate(usable):
            res = run_checker(oldq, [v])
            cov = res["covered"]
            errs = res.get("errors", {})
            for i, c in enumerate(cov):
                if c is True:
                    covered_by[i].append(vi)
                elif c is False:
                    not_covered[i] = True
                else:
                    still_undecided[i].append((vi, errs.get(str(i), "?")))
            print(f"  view {vi}/{len(usable)} done ({sum(1 for c in cov if c is True)} covered)", flush=True)

        # Aggregate.
        print(f"\n  === {ep} WAY2 aggregate (new covers old) ===")
        for i in range(len(oldq)):
            if covered_by[i]:
                print(f"   OLD#{i} COVERED by {len(covered_by[i])} view(s): {oldq[i][:90]}...")
            elif not_covered[i]:
                print(f"   OLD#{i} NOT COVERED (proven): {oldq[i][:90]}...")
            else:
                print(f"   OLD#{i} UNDECIDED ({len(still_undecided[i])} views timeout): {oldq[i][:90]}...")

        result = {
            "n_new": len(newq), "n_old": len(oldq),
            "usable_new_views": usable,
            "view_errors": view_errs,
            "covered_by": covered_by,
            "not_covered_proven": [i for i in range(len(oldq)) if not_covered[i] and not covered_by[i]],
            "undecided": still_undecided,
        }
        with open(os.path.join(args.out, f"{ep}_way2_perview.json"), "w") as f:
            json.dump(result, f, indent=2, default=str)
        print(f"  saved {ep}_way2_perview.json", flush=True)

if __name__ == "__main__":
    main()