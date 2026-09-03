#!/usr/bin/env python3
"""WAY2 per-query candidate subsets using REWRITTEN new views.
For each OLD query: run coverage against the rewritten NEW views whose tables
are a superset of the query's tables (cap 12, ranked by column overlap),
120s timeout, 3 threads.  Covered-by-subset => covered-by-full-policy.
NOT-against-subset is inconclusive (full policy is stronger)."""
import re, os, json, subprocess, sys, time

ROOT = "/home/dev/project"
NEW_DIR = ROOT + "/reports/diaspora/results3/queries_from_runs/_rewritten"
OLD_DIR = ROOT + "/ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint"
OUT = ROOT + "/reports/diaspora/results3/blockaid_new_vs_old"
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

def tables(q):
    m = re.search(r"\bFROM\s+(.*?)(?:\bWHERE\b|$)", q, re.S)
    if not m:
        return set()
    f = re.sub(r"\s+AS\s+`[a-z0-9_]+`", "", m.group(1))
    return set(re.findall(r"`([a-z_][a-z0-9_]*)`", f))

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
    oldq = parse(os.path.join(OLD_DIR, of))
    print("=== " + ep + " rewritten views=" + str(len(vws)) + " OLD=" + str(len(oldq)) + " ===", flush=True)
    probe = run([], vws, 20000, 1, cto=300)
    verrs = probe.get("view_errors", {})
    usable = [(i, q) for i, q in enumerate(vws) if str(i) not in verrs]
    v = [(i, tables(q)) for i, q in usable]
    union = set().union(*(t for _, t in v)) if v else set()
    print("usable: " + str(len(usable)) + "/" + str(len(vws)), flush=True)
    res = {}
    n_cov = n_not = n_tmo = n_skip = 0
    for oi, oq in enumerate(oldq):
        ot = tables(oq)
        miss = ot - union
        if miss:
            res[str(oi)] = {"verdict": None, "skip": "tables-missing: " + str(sorted(miss))}
            print("OLD#" + str(oi) + " SKIP missing tables " + str(sorted(miss)), flush=True)
            n_skip += 1
            continue
        cands = [i for i, t in v if ot <= t]
        if not cands:
            res[str(oi)] = {"verdict": None, "skip": "no-superset"}
            print("OLD#" + str(oi) + " SKIP no-superset", flush=True)
            n_skip += 1
            continue
        qcols = set(re.findall(r"`(\w+)`\.`(\w+)`", oq))
        def score(i):
            txt = dict((i, q) for i, q in usable)[i]
            return sum(1 for (t, c) in qcols if ("`" + t + "`.`" + c + "`") in txt)
        cands.sort(key=score, reverse=True)
        cands = cands[:12]
        t0 = time.time()
        r = run([oq], [dict((i, q) for i, q in usable)[i] for i in cands], tmo, thr)
        dt = time.time() - t0
        vd = r["covered"][0] if r.get("covered") else None
        err = r.get("errors", {}).get("0")
        if vd is True:
            n_cov += 1
        elif vd is False:
            n_not += 1
        else:
            n_tmo += 1
        print("OLD#" + str(oi) + " verdict=" + str(vd) + " cands=" + str(len(cands)) + " (" + str(int(dt)) + "s) " + oq[:70], flush=True)
        res[str(oi)] = {"verdict": vd, "candidate_indexes": cands, "error": err, "query": oq}
    print("SUMMARY: covered=" + str(n_cov) + " NOT(subset-only)=" + str(n_not) + " timeout=" + str(n_tmo) + " skip=" + str(n_skip), flush=True)
    with open(os.path.join(OUT, ep + "_way2_rewritten_subsets.json"), "w") as f:
        json.dump(res, f, indent=2, default=str)
    print("saved " + ep + "_way2_rewritten_subsets.json", flush=True)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "comments_index", int(sys.argv[2]) if len(sys.argv) > 2 else 120000, int(sys.argv[3]) if len(sys.argv) > 3 else 3)