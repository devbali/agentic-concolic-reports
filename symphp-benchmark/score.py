#!/usr/bin/env python3
"""Score one tool's requests on one app with the concrete judge.

usage: score.py <app> <tool-label> <requests.json>
       score.py <app> ace:<arm>            (collects results/<app>/<arm>/*/dump_*.json)

A known vulnerability is DETECTED when at least one of the tool's requests to
its script faults during concrete replay (judge.py) at that sink -- the
paper's criterion, applied by a judge neither tool controls. Line coverage is
the union of the replays' traces over the executable lines PHP-Parser finds.
Writes results/<app>/score_<label>.json and prints one row.
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
APPS = json.loads((HERE / "apps.json").read_text())


def ace_requests(app: str, arm: str) -> list[dict]:
    """Everything ACE emits: one request per explored trace, plus the sink
    oracle's witness for each site it flagged (for an `injectable` site that
    witness is a payload request no exploration run carried)."""
    out = []
    for summary in sorted((HERE / "results" / app / arm).glob("*/summary.json")):
        row = json.loads(summary.read_text())
        reqs = [json.loads(d.read_text())["request"] for d in sorted(summary.parent.glob("dump_*.json"))]
        reqs += [s["request"] for s in row["sink_sites"]]
        for req in reqs:
            out.append({"script": row["script"], **{g: {k: v for k, v in req.get(g, {}).items() if v is not None}
                                                     for g in ("GET", "POST", "COOKIE")}})
    return list({json.dumps(r, sort_keys=True): r for r in out}.values())


def main() -> int:
    app, label = sys.argv[1], sys.argv[2]
    if label.startswith("ace:"):
        reqs = ace_requests(app, label[4:])
    else:
        reqs = json.loads(pathlib.Path(sys.argv[3]).read_text())
    work = HERE / "results" / app
    work.mkdir(parents=True, exist_ok=True)
    tag = label.replace(":", "_")
    (work / f"requests_{tag}.json").write_text(json.dumps(reqs, indent=1) + "\n")
    replay = work / f"replay_{tag}.json"
    subprocess.run([sys.executable, str(HERE / "judge.py"), "replay", app,
                    str(work / f"requests_{tag}.json"), "--out", str(replay)], check=True)
    results = json.loads(replay.read_text())

    exec_cache = work / "exec_lines.json"
    if not exec_cache.exists():
        exec_cache.write_text(subprocess.run([sys.executable, str(HERE / "judge.py"), "exec-lines", app],
                                             capture_output=True, text=True, check=True).stdout)
    executable = {f"{f}:{n}" for f, ns in json.loads(exec_cache.read_text()).items() for n in ns}
    covered = {l for r in results for l in r["lines"]} & executable

    vulns = []
    for v in APPS[app]["known_vulns"]:
        hits = [r for r in results if r["request"]["script"] == v["script"]
                and any(f["kind"] == ("shell" if v["type"] == "cmdi" else "sql") for f in r["faults"])
                and f"{v['script']}:{v['line']}" in r["lines"]]
        vulns.append({**v, "detected": bool(hits), "witness": hits[0]["request"] if hits else None})
    row = {"app": app, "tool": label, "requests": len(results),
           "faulting_requests": sum(1 for r in results if r["faults"]),
           "detected": sum(v["detected"] for v in vulns), "known": len(vulns),
           "coverage_pct": round(100 * len(covered) / len(executable), 2) if executable else None,
           "covered_lines": len(covered), "executable_lines": len(executable), "vulns": vulns}
    (work / f"score_{tag}.json").write_text(json.dumps(row, indent=1) + "\n")
    print(f"{label:16} detected {row['detected']}/{row['known']}  coverage {row['coverage_pct']}% "
          f"({row['covered_lines']}/{row['executable_lines']})  requests {row['requests']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
