#!/usr/bin/env python3
import json, os, subprocess, sys, time
S = "/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad"
ROOT = "/home/dev/project"
# App-specific input for the subsume harness: src/queries_from_runs is
# app-agnostic and requires an app config; the diaspora side supplies it.
os.environ.setdefault("QFR_APP_CONFIG",
                      "/home/dev/project/reports/diaspora/queries_config/app.json")
CHECKER = ROOT + "/src/queries_from_runs/subsume/check_subsumed.sh"
E = ROOT + "/reports/diaspora/results3/queries_from_runs"
R = ROOT + "/ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint"
EPS = {"conversations_index": "conversations-index", "comments_index": "comments-index", "people_show": "people-show"}
TMO, THR = sys.argv[1], sys.argv[2]
def load(path):
    out = []
    for line in open(path):
        if line.lstrip().startswith("--"): continue
        s = line.strip().rstrip(";").strip()
        if s.upper().startswith("SELECT"): out.append(s)
    return out
def run(views, queries, tag):
    env = {k: v for k, v in os.environ.items() if k != "JAVA_TOOL_OPTIONS"}
    env.update(SUBSUME_TIMEOUT_MS=TMO, SUBSUME_SOLVER_THREADS=THR, HOME=os.environ["HOME"])
    t0 = time.time()
    p = subprocess.run(["systemd-run", "--user", "--pipe", "--wait", "--quiet", "-p", "MemoryMax=6300M", "--setenv=HOME=" + env["HOME"],
                        "--setenv=SUBSUME_TIMEOUT_MS=" + TMO, "--setenv=SUBSUME_SOLVER_THREADS=" + THR, "env", "-u", "JAVA_TOOL_OPTIONS", CHECKER],
                       input=json.dumps({"views": views, "queries": queries}), capture_output=True, text=True, env=env)
    dt = time.time() - t0
    try:
        r = json.loads(p.stdout)
    except Exception:
        r = {"covered": [None] * len(queries), "errors": {"global": "rc=%d no-json" % p.returncode}, "view_errors": {}}
    r.update(rc=p.returncode, secs=round(dt, 1), n_views=len(views), n_queries=len(queries), views=views, queries=queries, timeout_ms=TMO, threads=THR, stderr_tail=p.stderr[-3000:])
    json.dump(r, open(f"{S}/res_{tag}.json", "w"), indent=1)
    c = r["covered"]
    print(f"{tag}: rc={p.returncode} {dt:.0f}s views {len(views)-len(r.get('view_errors', {}))}/{len(views)} usable; queries true={sum(1 for x in c if x is True)} false={sum(1 for x in c if x is False)} null={sum(1 for x in c if x is None)}", flush=True)
order = sys.argv[3:] or ["raw", "tierC"]
LABEL = os.environ.get("TIER_LABEL")  # e.g. "final": the regenerated extraction, read from the same .sql path as "raw"
ONLY = os.environ.get("ONLY_EP")
for ep, ref in EPS.items():
    if ONLY and ep != ONLY: continue
    refq = load(f"{R}/{ref}.sql")
    for tier in order:
        ours = load(f"{E}/{ep}.sql") if tier == "raw" else load(f"{S}/tierC_{ep}.sql")
        lab = LABEL if (LABEL and tier == "raw") else tier
        run(refq, ours, f"{ep}_{lab}_way1")
        run(ours, refq, f"{ep}_{lab}_way2")
print("ALL DONE", flush=True)
