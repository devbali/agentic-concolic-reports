#!/usr/bin/env python3
"""Append the cycle-6 section + a metric table derived from the FINAL
coverage_summary.json to AGENT_RUN.md. Numbers are read, never typed."""
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
draft = sys.argv[1]
d = json.load(open(os.path.join(HERE, "coverage_summary.json")))
c = d.get("completion") or {}
a = c.get("assumptions") or {}
vc = a.get("verdict_counts") or {}
sv = c.get("shim_verdict_counts") or {}
audits = c.get("audits") or []
rows = []
rows.append(f"| coverage_complete | `{d.get('coverage_complete')}` |")
rows.append(f"| missing branches | {d.get('missing_branches')} "
            f"(blocking {sum(1 for m in d.get('missing', []) if not m.get('untracked'))}) |")
rows.append(f"| tree nodes | {d.get('tree_nodes')} |")
rows.append(f"| runs | {d.get('total_runs')} |")
rows.append(f"| path conditions | {d.get('total_path_conditions')} |")
rows.append(f"| truncated / solver_lost | {d.get('truncated')} / {d.get('solver_lost')} |")
rows.append(f"| assumptions declared | {a.get('declared')} |")
rows.append("| assumptions PASS / FAIL / NOT-TESTABLE | "
            + " / ".join(str(vc.get(k, 0)) for k in ("PASS", "FAIL", "NOT-TESTABLE")) + " |")
rows.append("| shims | " + ", ".join(f"{k} {v}" for k, v in sorted(sv.items())) + " |")
rows.append(f"| note check | {'green' if (c.get('note_check') or {}).get('green') else 'RED'} |")
for au in audits:
    rows.append(f"| audit {au['name']} | {'green' if au.get('green') else 'RED'} (exit {au.get('exit')}) |")
rows.append(f"| dump_errors | {d.get('dump_errors')} |")
rows.append(f"| **complete** | **`{d.get('complete')}`** |")
rows.append("| completion.blocking | " + (("`" + "`, `".join(str(b)[:70] for b in c.get("blocking", [])) + "`") if c.get("blocking") else "`[]`") + " |")
table = ("\n### METRIC TABLE (cycle 6, final report)\n\n| metric | value |\n|---|---|\n"
         + "\n".join(rows) + "\n")
with open(os.path.join(HERE, "AGENT_RUN.md"), "a") as fh:
    fh.write(open(draft).read())
    fh.write(table)
print(table)
