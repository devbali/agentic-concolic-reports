#!/usr/bin/env python3
"""smoke_report.py — collect what actually happened when runners were launched.

Reads every `scaffold/<id>/exploration_summary.json` that exists, plus the
matching `smoke_logs/<id>.log`, and writes `smoke_results.json`.

This is the file that turns "scaffolded" into "verified to launch". It judges
nothing about coverage; it answers, per endpoint:

  did_not_launch      no summary — the runner never got as far as writing one
  launched_no_paths   summary written, but zero distinct paths (see `notes`)
  launched_partial    paths recorded, but at least one harness failure
  launched_productive paths recorded, no harness failure

Usage:
  /home/dev/project/venvs/queries_from_runs/bin/python3 smoke_report.py
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
EP = HERE.parent
SCAFFOLD = EP / "scaffold"
LOGS = EP / "smoke_logs"
OUT = EP / "smoke_results.json"
MANIFEST = EP / "manifest.json"

HARNESS_RE = re.compile(r"HARNESS FAILURE (\S+): (.*)")


def main() -> int:
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {"endpoints": []}
    meta = {e["id"]: e for e in manifest["endpoints"]}

    rows = []
    for d in sorted(SCAFFOLD.iterdir()):
        if not d.is_dir():
            continue
        summary_p = d / "exploration_summary.json"
        log_p = LOGS / f"{d.name}.log"
        if not summary_p.exists() and not log_p.exists():
            continue  # never attempted — not a result, just untried

        summary = {}
        if summary_p.exists():
            try:
                summary = json.loads(summary_p.read_text())
            except json.JSONDecodeError:
                summary = {}

        harness = []
        if log_p.exists():
            for line in log_p.read_text(errors="replace").splitlines():
                m = HARNESS_RE.search(line)
                if m:
                    harness.append({"error": m.group(1), "message": m.group(2)[:200]})

        paths = int(summary.get("distinct_paths", 0) or 0)
        runs = int(summary.get("runs_executed", 0) or 0)

        if not summary:
            verdict = "did_not_launch"
        elif paths >= 1 and not harness:
            verdict = "launched_productive"
        elif paths >= 1:
            verdict = "launched_partial"
        else:
            verdict = "launched_no_paths"

        e = meta.get(d.name, {})
        rows.append(
            {
                "id": d.name,
                "verdict": verdict,
                "runs_executed": runs,
                "distinct_paths": paths,
                "dumps_on_disk": len(list(d.glob("dump_*.json"))),
                "unflippable_shapes": len(summary.get("unflippable_pcs", {}) or {}),
                "terminals": summary.get("terminals", {}),
                "run_errors": summary.get("run_errors", {}),
                "harness_failures": harness,
                "targets_tier": summary.get("targets_tier"),
                "variant": summary.get("variant"),
                "worklist_exhausted": summary.get("worklist_exhausted"),
                "elapsed_seconds": summary.get("elapsed_seconds"),
                "priority_tier": (e.get("priority") or {}).get("tier"),
                "cost_score": (e.get("cost") or {}).get("score"),
                "log": f"smoke_logs/{d.name}.log" if log_p.exists() else None,
            }
        )

    counts: dict[str, int] = {}
    for r in rows:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1

    OUT.write_text(
        json.dumps(
            {
                "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "generator": "reports/autolab/entrypoints/tools/smoke_report.py",
                "note": (
                    "A launch result, not a coverage result. 'launched_productive' "
                    "means the generated runner booted, dispatched the action and "
                    "recorded path conditions — nothing about whether the "
                    "exploration is complete or the mocks are right."
                ),
                "attempted": len(rows),
                "total_scaffolded": sum(1 for d in SCAFFOLD.iterdir() if d.is_dir()),
                "counts": counts,
                "results": rows,
            },
            indent=2,
        )
        + "\n"
    )

    print(f"wrote {OUT}")
    print(f"  attempted: {len(rows)}")
    for k, v in sorted(counts.items()):
        print(f"  {k}: {v}")
    for r in rows:
        print(
            f"    {r['id']:<44} {r['verdict']:<20} runs={r['runs_executed']:<3} "
            f"paths={r['distinct_paths']:<3} dumps={r['dumps_on_disk']:<3} "
            f"targets={r['targets_tier']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
