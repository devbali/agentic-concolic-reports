#!/usr/bin/env python3
"""C23 (2026-09-14) — read-only roll-up of one _c23_* measurement pass.

  usage: python3 _c23_analyze.py <TAG> [<TAG> ...]

Reads only `_c23_cov_<TAG>.json`, `_c23_cov_<TAG>.ckpt.jsonl`,
`_c23_pairs_<TAG>.json`, `_c23_cov_<TAG>.time` and the frozen
`_c23_declared656_pairs.json`. Writes `_c23_summary.json` and nothing else.
A gap-set is a demand-set checkpoint record carrying a witness (`v.combos`),
exactly as `_c16_gapdelta.py` counts one.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
D656 = {tuple(sorted(p)) for p in
        json.load(open(os.path.join(HERE, "_c23_declared656_pairs.json")))}


def one(tag):
    r = {"tag": tag}
    cov = os.path.join(HERE, f"_c23_cov_{tag}.json")
    if os.path.exists(cov):
        s = json.load(open(cov))
        r.update(complete=s.get("coverage_complete"), nodes=s.get("tree_nodes"),
                 missing=s.get("missing_branches"),
                 demand_sets=s.get("demand_sets"),
                 tree_complete=s.get("tree_complete"),
                 tree_missing=len(s.get("tree_missing") or ()),
                 truncated=s.get("truncated"),
                 solver_lost=s.get("solver_lost"),
                 total_runs=s.get("total_runs"))
    ck = os.path.join(HERE, f"_c23_cov_{tag}.ckpt.jsonl")
    if os.path.exists(ck):
        sets = gaps = 0
        gapkeys, leaves = [], set()
        for i, line in enumerate(open(ck)):
            if i == 0:
                continue
            rec = json.loads(line); v = rec.get("v") or {}
            sets += 1
            if v.get("combos"):
                gaps += 1; gapkeys.append(rec["k"])
                for c in v["combos"]:
                    leaves.add(tuple(sorted((e, bool(o)) for e, o in c)))
        r.update(ckpt_sets=sets, gap_sets=gaps, witness_leaves=len(leaves),
                 gap_keys=gapkeys[:50])
    pr = os.path.join(HERE, f"_c23_pairs_{tag}.json")
    if os.path.exists(pr):
        p = json.load(open(pr))
        cp = {tuple(sorted(x)) for x in p.get("confined_pairs") or ()}
        r.update(confined_pairs=len(cp),
                 or_pairs=len(p.get("or_pairs") or ()),
                 and_pairs_refused=len(p.get("and_pairs") or ()),
                 decided=p.get("decided"), undecidable=p.get("undecidable"),
                 splits=p.get("splits"),
                 shapes=len(p.get("footprint_shapes") or ()),
                 of_the_656_still_licensed=len(cp & D656),
                 licensed_not_in_656=len(cp - D656))
    tm = os.path.join(HERE, f"_c23_cov_{tag}.time")
    if os.path.exists(tm):
        t = open(tm).read()
        m = re.search(r"Maximum resident set size \(kbytes\): (\d+)", t)
        if m:
            r["peak_rss_mb"] = round(int(m.group(1)) / 1024)
        m = re.search(r"Elapsed \(wall clock\) time.*?: ([0-9:.]+)", t)
        if m:
            r["wall"] = m.group(1)
    log = os.path.join(HERE, f"_c23_cov_{tag}.log")
    if os.path.exists(log):
        txt = open(log).read()
        m = re.search(r"^BLOCKING=|^COMPLETE=.*?BLOCKING=(\d+)", txt, re.M)
        m2 = re.search(r"BLOCKING=(\d+)", txt)
        if m2:
            r["blocking"] = int(m2.group(1))
        m3 = re.search(r"loaded \d+ runs.*?peak RSS (\d+) MB", txt)
        if m3:
            r["load_peak_rss_mb"] = int(m3.group(1))
        m4 = re.search(r"\[coverage\] phase done in (\d+)s", txt)
        if m4:
            r["coverage_phase_s"] = int(m4.group(1))
    return r


if __name__ == "__main__":
    out = [one(t) for t in sys.argv[1:]]
    print(json.dumps(out, indent=1))
    dest = os.path.join(HERE, "_c23_summary.json")
    prev = json.load(open(dest)) if os.path.exists(dest) else []
    by = {x["tag"]: x for x in prev}
    for x in out:
        by[x["tag"]] = x
    json.dump(list(by.values()), open(dest, "w"), indent=1)
    print(f"wrote {dest}")
