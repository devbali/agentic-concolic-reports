#!/usr/bin/env python3
"""Score one tool's requests on one app with the concrete judge.

usage: score.py <app> <tool-label> <requests.json> [--coverage xdebug]
       score.py <app> ace:<arm>[+<arm>...]      (collects results/<app>/<arm>/*/dump_*.json;
                                                 `ace:cold+auth` scores the UNION of the arms)

A known vulnerability is DETECTED when at least one of the tool's requests
faults during concrete replay (judge.py) with the vuln's fault kind AND the
replay's trace passes the SINK LINE, `sink_file:sink_line`. Matching on the
sink's own file (not on the entry script) is what credits a sink that lives in
an included file. The known-vuln list comes from `known_vulns_file` in
apps.json (`known_vulns/<app>.json`, read only), else from apps.json's own
`known_vulns` (Witcher-Test: there the script IS the sink file).

Reported per sink (each list entry) and per CVE (an entry's `cve` list; a CVE
counts once any of its entries is detected). Line coverage is the union of the
replays' traces over the executable lines PHP-Parser finds.
Writes results/<app>/score_<label>.json and prints one row.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
APPS = json.loads((HERE / "apps.json").read_text())
FAULT_KIND = {"sqli": "sql", "cmdi": "shell", "xss": "xss"}


def known_vulns(app: str) -> list[dict]:
    spec = APPS[app]
    if spec.get("known_vulns_file"):
        doc = json.loads((HERE / spec["known_vulns_file"]).read_text())
        return [{**v, "sink_file": v.get("sink_file") or v["script"], "sink_line": int(v["sink_line"])}
                for v in doc["vulns"]]
    return [{**v, "sink_file": v["script"], "sink_line": int(v["line"])} for v in spec.get("known_vulns", [])]


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


def ace_findings(app: str, arm: str) -> list[dict]:
    """Every sink site ACE's oracle flagged, with its witness request."""
    out = []
    for summary in sorted((HERE / "results" / app / arm).glob("*/summary.json")):
        row = json.loads(summary.read_text())
        for s in row["sink_sites"]:
            req = {"script": row["script"], **{g: {k: v for k, v in s["request"].get(g, {}).items() if v is not None}
                                               for g in ("GET", "POST", "COOKIE")}}
            out.append({"arm": arm, "site": s["site"], "sink": s["sink"], "kind": s["kind"], "request": req,
                        "carries_input": "$$(" in json.dumps(s.get("instance", "")) or bool(sum(map(len, s["request"].values())))})
    return out


def detected(v: dict, results: list[dict]) -> list[dict]:
    kind = FAULT_KIND[v["type"]]
    site = f"{v['sink_file']}:{v['sink_line']}"
    return [r for r in results if site in r["lines"] and any(f["kind"] == kind for f in r["faults"])]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("app")
    ap.add_argument("label")
    ap.add_argument("requests", nargs="?")
    ap.add_argument("--coverage", choices=("trace", "xdebug"), default="trace")
    ap.add_argument("--judge-shards", type=int, default=1, help="replay with K parallel judge instances")
    ap.add_argument("--reset", choices=("request", "batch", "marked", "none"),
                    help="judge.py's reset policy (default: request for a db app)")
    a = ap.parse_args()
    app, label = a.app, a.label
    arms_of: dict[str, set] = {}
    if label.startswith("ace:"):
        reqs = []
        for arm in label[4:].split("+"):
            for r in ace_requests(app, arm):
                arms_of.setdefault(json.dumps(r, sort_keys=True), set()).add(arm)
                reqs.append(r)
        reqs = list({json.dumps(r, sort_keys=True): r for r in reqs}.values())
    else:
        reqs = json.loads(pathlib.Path(a.requests).read_text())
    work = HERE / "results" / app
    work.mkdir(parents=True, exist_ok=True)
    tag = label.replace(":", "_").replace("+", "_")
    (work / f"requests_{tag}.json").write_text(json.dumps(reqs, indent=1) + "\n")
    replay = work / f"replay_{tag}.json"
    sent = work / f"requests_{tag}.json"
    if a.reset == "marked" and label.startswith("ace:"):
        # Every oracle witness is replayed on a freshly restored snapshot (judge.py --reset marked).
        witness = {json.dumps(f["request"], sort_keys=True) for arm in label[4:].split("+") for f in ace_findings(app, arm)}
        sent = work / f"requests_{tag}.marked.json"
        sent.write_text(json.dumps([{**r, "reset": True} if json.dumps(r, sort_keys=True) in witness else r
                                    for r in reqs], indent=1) + "\n")
    extra = ["--coverage", a.coverage, *(["--reset", a.reset] if a.reset else [])]
    if a.judge_shards > 1:
        # K judge instances (own clone DB, runner, statement history), each replaying one
        # CONTIGUOUS slice of the list in order; results are concatenated back in order.
        allreqs = json.loads(sent.read_text())
        k = a.judge_shards
        size = -(-len(allreqs) // k)
        procs, parts = [], []
        for i in range(k):
            part = sent.with_suffix(f".j{i}.json")
            part.write_text(json.dumps(allreqs[i * size:(i + 1) * size]))
            out = replay.with_suffix(f".j{i}.json")
            parts.append(out)
            try:
                if out.exists() and [r["request"] for r in json.loads(out.read_text())] == \
                        [{k: v for k, v in r.items() if k != "reset"} for r in allreqs[i * size:(i + 1) * size]]:
                    continue                     # this slice was already replayed (a resumed score)
            except (json.JSONDecodeError, KeyError):
                pass
            procs.append(subprocess.Popen([sys.executable, str(HERE / "judge.py"), "replay", app, str(part),
                                           "--out", str(out), "--instance", f"j{i}", *extra]))
        if any(p.wait() != 0 for p in procs):
            raise SystemExit("a judge shard failed")
        results = [r for out in parts for r in json.loads(out.read_text())]
        replay.write_text(json.dumps(results, indent=1) + "\n")
        for f in [*parts, *(sent.with_suffix(f".j{i}.json") for i in range(k))]:
            f.unlink(missing_ok=True)
    else:
        subprocess.run([sys.executable, str(HERE / "judge.py"), "replay", app, str(sent), "--out", str(replay),
                        *extra], check=True)
    results = json.loads(replay.read_text())

    exec_cache = work / "exec_lines.json"
    if not exec_cache.exists():
        exec_cache.write_text(subprocess.run([sys.executable, str(HERE / "judge.py"), "exec-lines", app],
                                             capture_output=True, text=True, check=True).stdout)
    executable = {f"{f}:{n}" for f, ns in json.loads(exec_cache.read_text()).items() for n in ns}
    covered = {l for r in results for l in r["lines"]} & executable

    vulns = []
    for v in known_vulns(app):
        hits = detected(v, results)
        vulns.append({"id": v["id"], "cve": v.get("cve", []), "type": v["type"],
                      "sink": f"{v['sink_file']}:{v['sink_line']}", "auth": v.get("auth"),
                      "detected": bool(hits), "witness": hits[0]["request"] if hits else None})
    cves: dict[str, bool] = {}
    for v in vulns:
        for c in v["cve"]:
            cves[c] = cves.get(c, False) or v["detected"]
    findings = []
    if label.startswith("ace:"):
        by_req = {json.dumps(r["request"], sort_keys=True): r for r in results}
        for f in (f for arm in label[4:].split("+") for f in ace_findings(app, arm)):
            r = by_req.get(json.dumps(f["request"], sort_keys=True))
            kind = "shell" if f["sink"] in ("system", "exec", "shell_exec", "passthru", "popen", "proc_open") else "sql"
            f["judge_fault"] = bool(r and any(x["kind"] == kind for x in r["faults"]))
            f["judge_reached_site"] = bool(r and f["site"] in r["lines"])
            findings.append(f)
    row = {"app": app, "tool": label, "requests": len(results),
           "findings": len(findings), "findings_judge_confirmed": sum(f["judge_fault"] for f in findings),
           "findings_unconfirmed": [{k: f[k] for k in ("site", "kind", "request")} for f in findings if not f["judge_fault"]],
           "faulting_requests": sum(1 for r in results if r["faults"]),
           "detected": sum(v["detected"] for v in vulns), "known": len(vulns),
           "cves_detected": sum(cves.values()), "cves_known": len(cves), "cves": cves,
           "coverage_pct": round(100 * len(covered) / len(executable), 2) if executable else None,
           "covered_lines": len(covered), "executable_lines": len(executable), "vulns": vulns}
    if a.coverage == "xdebug":
        xcov = {l for r in results for l in r.get("xdebug_lines", [])} & executable
        row |= {"xdebug_coverage_pct": round(100 * len(xcov) / len(executable), 2) if executable else None,
                "xdebug_covered_lines": len(xcov), "xdebug_method": "auto_prepend_file (coverage-only, outside docroot)"
                + ("; the fault replays themselves ran under it (judge_cgi xdebug), so trace == xdebug"
                   if APPS[app].get("judge_cgi") == "xdebug" else "")}
    if len(label[4:].split("+")) > 1 and label.startswith("ace:"):
        # Decision (e): each arm separately, from the SAME replay (each request is judged once).
        row["arms"] = {}
        for arm in label[4:].split("+"):
            mine = [r for r in results if arm in arms_of.get(json.dumps(r["request"], sort_keys=True), ())]
            cov = {l for r in mine for l in r["lines"]} & executable
            row["arms"][arm] = {"requests": len(mine), "detected": sum(bool(detected(v, mine)) for v in known_vulns(app)),
                                "detected_ids": [v["id"] for v in known_vulns(app) if detected(v, mine)],
                                "coverage_pct": round(100 * len(cov) / len(executable), 2) if executable else None}
    (work / f"score_{tag}.json").write_text(json.dumps(row, indent=1) + "\n")
    print(f"{label:16} detected {row['detected']}/{row['known']}  coverage {row['coverage_pct']}% "
          f"({row['covered_lines']}/{row['executable_lines']})  requests {row['requests']}"
          + (f"  findings {row['findings_judge_confirmed']}/{row['findings']} judge-confirmed" if findings else "")
          + (f"  xdebug {row['xdebug_coverage_pct']}%" if a.coverage == "xdebug" else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
