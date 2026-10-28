#!/usr/bin/env python3
"""Summarise res_<ep>_<tier>_way<n>.json: usable/quarantined-by-cause views, true/false/null queries, per-query list."""
import json, sys, collections, re, os
S = os.path.dirname(os.path.abspath(__file__))
def cause(msg):
    m = msg
    if "unrecognized constant" in m: return "unresolved placeholder const (" + re.search(r"unrecognized constant: (\S+)", m).group(1)[:40] + ")"
    if "LIMIT/OFFSET" in m: return "LIMIT/OFFSET"
    if "aggregate/function in select list" in m: return "aggregate in select list"
    if "relation alias" in m: return "relation alias (shape)"
    if "unhandled join type: LEFT" in m: return "LEFT join (shape)"
    if "fully-specified column names" in m: return "unqualified/identifier-as-literal (shape)"
    if "column not found" in m: return "column not found (identifier-as-literal)"
    if "Sorts CS!BOOL and CS!STRING" in m: return "solver-type probe: bool vs string literal 't'"
    if "solver-type probe" in m: return "solver-type probe: " + m[:80]
    if "timeout/inconclusive" in m: return "timeout/inconclusive"
    if "unsupported as subsumer" in m: return "unsupported as subsumer (shape)"
    if "unsupported as checked" in m: return "unsupported as checked (shape)"
    return m[:70]
for tag in sys.argv[1:]:
    r = json.load(open(f"{S}/res_{tag}.json"))
    c = r["covered"]; ve = r.get("view_errors", {}); qe = r.get("errors", {})
    print(f"===== {tag}  rc={r['rc']} {r['secs']}s timeout={r['timeout_ms']}ms threads={r['threads']}")
    print(f"views: {r['n_views']} total, {r['n_views']-len(ve)} usable, {len(ve)} quarantined")
    for k, n in collections.Counter(cause(v) for v in ve.values()).most_common(): print(f"    {n:3d} {k}")
    print(f"queries: {r['n_queries']} total: true={sum(1 for x in c if x is True)} false={sum(1 for x in c if x is False)} null={sum(1 for x in c if x is None)}")
    for k, n in collections.Counter(cause(v) for v in qe.values() if not isinstance(v, dict)).most_common(): print(f"    null cause {n:3d} {k}")
    for i, q in enumerate(r["queries"]):
        lab = {True: "TRUE ", False: "FALSE", None: "null "}[c[i]]
        extra = "" if c[i] is not None else "  <" + cause(qe.get(str(i), "?")) + ">"
        print(f"  q#{i+1:<3} {lab}{extra}  {q[:150]}")
    print()
