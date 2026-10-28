#!/usr/bin/env python3
"""ACE on one benchmark app: explore every entry script, then ask the sink oracle.

usage: drive.py <app> [--arm cold|witcher] [--only SCRIPT] [--max-rounds N]

Per entry script, starting from the arm's seed request:

1. Run the request through `harness.php` (the ACE PHP runtime, instrumented
   app). A superglobal key the script read and the request did not declare
   comes back as DISCOVERED and is declared -- absent -- from then on, so its
   `isset()` becomes a recorded decision.
2. Expand each new trace by prefix negation, solved by the engine's own
   lowering (`concolic.solver.solve_and_evaluate`).
3. When that runs dry, refill from `CoverageChecker`'s witnesses -- the
   assignment reaching a combination no run took.
4. Stop when neither proposes a request that produces an unseen trace.

Then `sinks.findings` over the kept dumps, and the coverage verdict with ONE
mechanical class of assumption declared: a branch whose every symbol is a
shim's result (e.g. `mysqli_connect_errno() != 0`) is untracked, because no
request can drive it. Each such assumption is written into the summary.

`cold` starts from the bare URL -- no parameters at all. `witcher` starts from
the requests Witcher's crawler recorded (the benchmark's own
`request_data.json`), which is the input SymPHP is given in the paper.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.parse

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "agentic_concolic_engine"))

from concolic.assumptions.assumption_set import AssumptionSet          # noqa: E402
from concolic.assumptions.untracked import UntrackedPathAssumption     # noqa: E402
from concolic.coverage import CoverageChecker                          # noqa: E402
from concolic.model.run import Run                                     # noqa: E402
from concolic.solver import solve_and_evaluate                         # noqa: E402

import sinks                                                           # noqa: E402

APPS = json.loads((HERE / "apps.json").read_text())
GLOBALS = ("GET", "POST", "COOKIE")
FAMILIES = {**{n: sinks.SQL for n in ("mysqli_query", "mysqli_real_query", "mysqli_multi_query", "mysql_query")},
            **{n: sinks.SHELL for n in ("system", "exec", "shell_exec", "passthru", "popen", "proc_open")}}
PHP = ["docker", "run", "--rm", "-i", "-u", f"{os.getuid()}:{os.getgid()}",
       "-v", f"{ROOT}:{ROOT}", "-w", str(HERE), "php:8.2-cli", "php"]


def php(requests: list[dict]) -> list[dict]:
    p = subprocess.run([*PHP, "harness.php"], input=json.dumps(requests),
                       capture_output=True, text=True, timeout=1800)
    if p.returncode != 0:
        raise SystemExit(f"harness failed:\n{p.stderr[-3000:]}")
    return json.loads(p.stdout)


def instrument(app: str) -> pathlib.Path:
    build = HERE / "build" / app
    src = (HERE / APPS[app]["src"]).resolve()
    p = subprocess.run([*PHP, "instrument_app.php", str(src), str(build)], capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(f"instrumentation failed:\n{p.stderr[-3000:]}")
    (HERE / "build" / f"{app}.instrument.json").write_text(p.stdout)
    return build


# -- requests ---------------------------------------------------------------
#
# A request is {global: {key: value-or-None}}. `None` is ABSENT.

def canon(req: dict) -> str:
    return json.dumps({g: dict(sorted(req.get(g, {}).items())) for g in GLOBALS}, sort_keys=True)


def with_keys(req: dict, keys: dict[str, set]) -> dict:
    """`req` with every known key declared; ones it does not set are absent."""
    return {g: {k: req.get(g, {}).get(k) for k in sorted(keys[g] | set(req.get(g, {})))} for g in GLOBALS}


def witcher_seeds(app: str) -> dict[str, list[dict]]:
    """request_data.json -> {script: [request]}. Duplicate JSON keys are kept."""
    spec = APPS[app].get("witcher_requests")
    if not spec:
        return {}
    pairs = json.loads((HERE / spec).read_text(), object_pairs_hook=lambda kv: kv)
    found = dict(pairs).get("requestsFound", [])
    out: dict[str, list[dict]] = {}
    for name, entry in found:
        e = dict(entry)
        # The SCRIPT comes from the entry's name, not `_url`: in Witcher-Test
        # they disagree once (`test-5-cmd.php`'s request points at a
        # `test-5.php` that does not exist), and the name is the URL the
        # crawler filed the request under. A body is sent whenever one was
        # recorded, whatever `_method` says -- several entries record both.
        script = urllib.parse.urlsplit(name.split(" ", 1)[1].strip()).path.lstrip("/")
        url = urllib.parse.urlsplit(e.get("_url", ""))
        req = {"GET": dict(urllib.parse.parse_qsl(url.query, keep_blank_values=True)),
               "POST": dict(urllib.parse.parse_qsl(e.get("_postData") or "", keep_blank_values=True)),
               "COOKIE": dict(urllib.parse.parse_qsl(e.get("_cookieData", ""), keep_blank_values=True))}
        out.setdefault(script, []).append(req)
    return out


# -- expansion ----------------------------------------------------------------

def trace(dump: dict) -> tuple:
    return tuple((json.dumps(e["expr"], sort_keys=True), e["taken"])
                 for e in dump["events"] if e["type"] == "path_condition")


def _from_model(model: dict, names: dict[str, tuple], base: dict) -> dict:
    req = json.loads(canon(base))
    for name, (g, key) in names.items():
        if model.get(f"is_null({name})") is True:
            req[g][key] = None
        elif name in model and isinstance(model[name], str):
            req[g][key] = model[name]
        elif model.get(f"is_null({name})") is False and req[g].get(key) is None:
            req[g][key] = ""
    return req


def negations(dump: dict, names: dict[str, tuple], base: dict):
    """One request per branch this run took, flipped against its prefix."""
    run = Run.from_dict(dump)
    symbols = run.symbols()
    pcs = run.path_conditions
    observed = [pc.expr if pc.taken else ("not", pc.expr) for pc in pcs]
    for i, pc in enumerate(pcs):
        flipped = ("not", pc.expr) if pc.taken else pc.expr
        res = solve_and_evaluate([*observed[:i], flipped], symbols,
                                 eval_conditions=[pc.expr for pc in pcs])
        if res.status == "sat":
            yield _from_model(res.model, names, base)


def shim_only(expr: dict, inputs: set[str]) -> bool:
    syms = set()

    def walk(n):
        if isinstance(n, dict):
            if "sym" in n:
                syms.add(n["sym"])
            for a in n.get("args", []):
                walk(a)
    walk(expr)
    return bool(syms) and not (syms & inputs)


def coverage(kept: list[dict], names: dict) -> tuple:
    inputs = set(names)
    declared = {}
    for d in kept:
        for e in d["events"]:
            if e["type"] == "path_condition" and shim_only(e["expr"], inputs):
                key = json.dumps(e["expr"], sort_keys=True, separators=(",", ":"))
                declared[key] = f"{e.get('file', '').rsplit('/', 1)[-1]}:{e.get('lineno')}"
    runs = [Run.from_dict(d) for d in kept]
    # The checker matches an assumption's expr against the PC's identity
    # string; use the spelling the runs themselves carry.
    identities = {pc.expr for r in runs for pc in r.path_conditions}
    aset = AssumptionSet()
    for key, where in declared.items():
        match = next((i for i in identities if json.loads(i) == json.loads(key)), key)
        aset.add(UntrackedPathAssumption(expr=match, description=f"shim result only, at {where}: no request can drive it"))
    checker = CoverageChecker(runs, assumptions=aset, foreclosure_conjunctions=True,
                              foreclosure_subconjunctions=True)
    return checker.check_coverage(), [a.description for a in aset.assumptions]


def explore(app_dir: pathlib.Path, script: str, seeds: list[dict], max_rounds: int) -> dict:
    keys = {g: set() for g in GLOBALS}
    for s in seeds:
        for g in GLOBALS:
            keys[g] |= set(s.get(g, {}))
    queue = [with_keys(s, keys) for s in seeds]
    seen, traces, kept, errors, names = set(), set(), [], [], {}
    rounds = 0
    while queue and rounds < max_rounds:
        fresh = []
        for req in queue:
            req = with_keys(req, keys)
            if canon(req) not in seen:
                seen.add(canon(req))
                fresh.append(req)
        queue = []
        if not fresh:
            if kept:
                cov, _ = coverage(kept, names)
                for m in cov.missing:
                    if not m.untracked and m.concrete_values:
                        queue.append(_from_model(m.concrete_values, names, kept[-1]["request"]))
                queue = [q for q in queue if canon(with_keys(q, keys)) not in seen]
            if not queue:
                break
            continue
        rounds += 1
        batch = [{"app": str(app_dir), "script": script, "label": f"r{rounds:02}_{i:03}", "inputs": r}
                 for i, r in enumerate(fresh)]
        for req, res in zip(fresh, php(batch)):
            for g, ks in (res.get("discovered") or {}).items():
                new = set(ks) - keys[g]
                if new:
                    keys[g] |= new
                    queue.append(req)            # the same request, now declaring the new keys
            for n, spec in res["inputs"].items():
                names[n] = (spec["global"], spec["key"])
            dump = res["dump"]
            if dump.get("error"):
                errors.append(f"{dump['error']['type']}: {dump['error']['message'][:200]}")
                continue
            sig = trace(dump)
            if sig in traces:
                continue
            traces.add(sig)
            dump["request"] = req
            kept.append(dump)
            queue.extend(negations(dump, names, req))
    return {"kept": kept, "errors": errors, "keys": {g: sorted(k) for g, k in keys.items()},
            "requests": len(seen), "rounds": rounds, "names": names, "budget_hit": bool(queue)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("app")
    ap.add_argument("--arm", choices=("cold", "witcher"), default="cold")
    ap.add_argument("--only")
    ap.add_argument("--max-rounds", type=int, default=50)
    a = ap.parse_args()

    app_dir = instrument(a.app)
    spec = APPS[a.app]
    seeds_by_script = witcher_seeds(a.app) if a.arm == "witcher" else {}
    out = HERE / "results" / a.app / a.arm
    rows = []
    for script in spec["scripts"]:
        if a.only and a.only != script:
            continue
        seeds = seeds_by_script.get(script) or [{}]
        t0 = time.monotonic()
        r = explore(app_dir, script, seeds, a.max_rounds)
        wall = round(time.monotonic() - t0, 1)
        d = out / script.replace("/", "__")
        d.mkdir(parents=True, exist_ok=True)
        for stale in d.glob("dump_*.json"):
            stale.unlink()
        found = []
        for dump in r["kept"]:
            (d / f"dump_{dump['label']}.json").write_text(json.dumps(dump, indent=1))
            for f in sinks.findings(dump, FAMILIES):
                f["request"] = {g: {k: f["witness"].get(n) for n, (gg, k) in r["names"].items() if gg == g
                                    and f["witness"].get(n) is not None} for g in GLOBALS}
                found.append(f)
        cov, assumed = coverage(r["kept"], r["names"]) if r["kept"] else (None, [])
        # One finding per sink site: the first witness that reached it.
        sites = {}
        for f in found:
            sites.setdefault((f["file"].rsplit("/", 1)[-1], f["lineno"], f["sink"]), f)
        row = {"script": script, "wall_s": wall, "requests": r["requests"], "rounds": r["rounds"], "traces": len(r["kept"]),
               "errored": len(r["errors"]), "first_error": r["errors"][0] if r["errors"] else None,
               "keys_discovered": r["keys"], "budget_hit": r["budget_hit"],
               "coverage_complete": bool(cov and cov.complete), "missing": len(cov.missing) if cov else None,
               "assumptions": assumed,
               "sink_sites": [{"site": f"{k[0]}:{k[1]}", "sink": k[2], "kind": f["kind"],
                               "instance": f["instance"], "request": f["request"]} for k, f in sites.items()]}
        (d / "summary.json").write_text(json.dumps(row, indent=1) + "\n")
        rows.append(row)
        print(f"{script:28} {row['traces']:3} traces {row['requests']:3} requests  "
              f"{'complete' if row['coverage_complete'] else str(row['missing']) + ' missing':12} "
              f"sinks={len(row['sink_sites'])} errored={row['errored']}")
    if not a.only:
        (out / "summary.json").write_text(json.dumps(rows, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
