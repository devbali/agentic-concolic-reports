#!/usr/bin/env python3
"""Eval tables from res_*.json: one row per (endpoint, tier, direction)."""
import json, sys, os, collections, re
S = os.path.dirname(os.path.abspath(__file__))
def cause(m):
    if "unrecognized constant" in m: return "placeholder const"
    if "aggregate/function" in m: return "aggregate select"
    if "relation alias" in m: return "relation alias"
    if "LEFT" in m: return "LEFT join"
    if "fully-specified" in m or "column not found" in m: return "identifier-as-literal"
    if "CS!BOOL" in m: return "'t' vs bool"
    if "timeout" in m: return "timeout"
    return m[:30]
rows = []
hdr = "| endpoint | tier | direction | policy (views) | usable | quarantined (cause) | checked (stmts) | accepted (true) | rejected (false) | undecided (null: cause) | accepted / decided |"
print(hdr); print("|" + "---|" * 11)
for tag in sys.argv[1:]:
    p = f"{S}/res_{tag}.json"
    if not os.path.exists(p): continue
    r = json.load(open(p)); ep, tier, way = re.match(r"(.*)_(raw|tierC|final)_(way[12])$", tag).groups()
    c = r["covered"]; ve = r.get("view_errors", {}); qe = r.get("errors", {})
    if "global" in qe:
        print(f"| {ep} | {tier} | {way} | {'reference' if way=='way1' else 'ours'} ({r['n_views']}) | — | — | {'ours' if way=='way1' else 'reference'} ({r['n_queries']}) | — | — | run failed: {qe['global']} (OOM-killed) | — |"); continue
    vq = collections.Counter(cause(v) for v in ve.values())
    nq = collections.Counter(cause(v) for k, v in qe.items())
    t, f, n = sum(1 for x in c if x is True), sum(1 for x in c if x is False), sum(1 for x in c if x is None)
    pol = "reference" if way == "way1" else "ours"
    chk = "ours" if way == "way1" else "reference"
    dec = f"{t}/{t+f} = {100*t/(t+f):.0f}%" if t + f else "n/a (nothing decided)"
    vqs = "; ".join(f"{n_} {k}" for k, n_ in vq.most_common()) or "—"
    nqs = "; ".join(f"{n_} {k}" for k, n_ in nq.most_common()) or "—"
    print(f"| {ep} | {tier} | {way} ({'soundness' if way=='way1' else 'completeness'}) | {pol} ({r['n_views']}) | {r['n_views']-len(ve)} | {len(ve)} ({vqs}) | {chk} ({r['n_queries']}) | {t} | {f} | {n} ({nqs}) | {dec} |")
