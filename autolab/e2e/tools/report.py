#!/usr/bin/env python3
"""report.py — render the numeric sections of REPORT.md from INVENTORY.json.

Every number in the written report comes from here, so no figure in the prose
is hand-typed and none can drift from the artifacts.

Usage: report.py <INVENTORY.json> <INVENTORY_RANKED.json> [<label>]
"""
from __future__ import annotations
import collections, json, sys


def main():
    inv = json.load(open(sys.argv[1]))
    rank = json.load(open(sys.argv[2]))
    label = sys.argv[3] if len(sys.argv) > 3 else "run"
    n = len(inv)
    att = [s for s in inv.values() if s["attempted"]]
    out = []
    P = out.append

    P(f"## Counts — {label}\n")
    P(f"* endpoints scaffolded: **{n}**; attempted: **{len(att)}**; "
      f"not attempted: **{n - len(att)}**")
    P("")
    P("### Per-stage outcome, counted per endpoint\n")
    P("| stage | ok | failed | no result |")
    P("|---|---:|---:|---:|")
    for st in ("dump_ir", "run_complete", "build_policy", "normalize",
               "policy_text", "render_sql"):
        c = collections.Counter(s["stages"][st].get("verdict") for s in inv.values())
        P(f"| `{st}` | {c.get('ok',0)} | {c.get('failed',0)} | {c.get(None,0)} |")
    P("")

    P("### Exploration depth\n")
    ex = collections.Counter(s["stages"]["run"].get("worklist_exhausted") for s in inv.values())
    P(f"* worklist exhausted: **{ex.get(True,0)}**; truncated at MAX_RUNS: "
      f"**{ex.get(False,0)}**; no run: {ex.get(None,0)}")
    runs = [s["stages"]["run"].get("runs_executed") or 0 for s in att]
    dumps = [s["stages"]["run"].get("dumps_written") or 0 for s in att]
    if runs:
        P(f"* runs executed per endpoint: min {min(runs)}, median "
          f"{sorted(runs)[len(runs)//2]}, max {max(runs)}, total {sum(runs)}")
        P(f"* dumps written per endpoint: min {min(dumps)}, median "
          f"{sorted(dumps)[len(dumps)//2]}, max {max(dumps)}, total {sum(dumps)}")
    P("")

    P("### Path conditions and reach\n")
    pc = collections.Counter(s.get("path_conditions_max") for s in inv.values())
    P("* path conditions in the richest dump: `"
      + ", ".join(f"{k}:{v}" for k, v in sorted(pc.items(), key=lambda kv: (kv[0] is None, kv[0])))
      + "`")
    rb = collections.Counter(s.get("reach_best") for s in inv.values())
    P("* declared target functions reached (best dump): `"
      + ", ".join(f"{k}:{v}" for k, v in sorted(rb.items(), key=lambda kv: (kv[0] is None, kv[0])))
      + "`")
    ru = collections.Counter(len(s.get("reach_union") or ()) for s in inv.values())
    P("* reached across ALL of an endpoint's dumps (union): `"
      + ", ".join(f"{k}:{v}" for k, v in sorted(ru.items())) + "`")
    allt = collections.Counter()
    for s in inv.values():
        for t in s.get("reach_union") or ():
            allt[t] += 1
    P(f"* distinct target functions ever called corpus-wide: **{len(allt)}**")
    for t, c in allt.most_common():
        P(f"    * `{t}` — {c} endpoints")
    P("")

    P("### Where execution stopped — real sites, from the live exception\n")
    P("| endpoints | exception | missing method | receiver | raising frame |")
    P("|---:|---|---|---|---|")
    sites = collections.Counter()
    for s in inv.values():
        if not s["attempted"]:
            sites[("(NOT ATTEMPTED — no run in this sweep)", "", "", "")] += 1
            continue
        d = s.get("dominant_stop")
        if not d or not d.get("type"):
            sites[("(ran to completion — no unrescued exception)", "", "", "")] += 1
            continue
        sites[(d["type"], d.get("missing_name") or "", d.get("receiver_class") or "",
               d.get("raising_file_line") or "")] += 1
    for (ty, nm, rc, fr), c in sites.most_common():
        P(f"| {c} | `{ty}` | `{nm}` | `{rc}` | `{fr}` |")
    P("")

    P("### The ranked issue list — the worklist\n")
    P("| endpoints | blocking | issue |")
    P("|---:|:---:|---|")
    for a in rank["ranked_issues"]:
        P(f"| {a['endpoints_affected']} | {'yes' if a['blocking'] else 'no'} | "
          f"`{a['code']}` |")
    P("")

    P("### SQL render\n")
    v = collections.Counter(s["stages"]["render_sql"].get("views") for s in inv.values())
    P("* views rendered per endpoint: `"
      + ", ".join(f"{k}:{c}" for k, c in sorted(v.items(), key=lambda kv: (kv[0] is None, kv[0]))) + "`")
    lost = [s["stages"]["render_sql"].get("atoms_lost_to_note_envelope") for s in inv.values()]
    lost_n = [x for x in lost if isinstance(x, int)]
    if lost_n:
        P(f"* atoms that would render if the note envelope were unwrapped "
          f"(findings S-6): **{sum(lost_n)}** across "
          f"{sum(1 for x in lost_n if x)} endpoints")
    P("")

    P("### Gates\n")
    g = collections.Counter()
    for s in inv.values():
        gs = s["stages"]["run_complete"].get("gate_states") or {}
        for k, val in gs.items():
            g[(k, val)] += 1
    for (k, val), c in sorted(g.items()):
        P(f"* `{k}`: {val} on {c} endpoints")
    cc = collections.Counter(s["stages"]["run_complete"].get("coverage_complete") for s in inv.values())
    tc = collections.Counter(s["stages"]["run_complete"].get("tree_complete") for s in inv.values())
    co = collections.Counter(s["stages"]["run_complete"].get("complete") for s in inv.values())
    P(f"* `coverage_complete`: {dict(cc)}")
    P(f"* `tree_complete`: {dict(tc)}")
    P(f"* overall `complete`: {dict(co)}")
    print("\n".join(out))


if __name__ == "__main__":
    main()
