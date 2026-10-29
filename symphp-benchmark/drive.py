#!/usr/bin/env python3
"""ACE on one benchmark app: explore every entry script, then ask the sink oracle.

usage: drive.py <app> [--arm cold|witcher|auth] [--only SCRIPT] [--max-rounds N] [--budget SECONDS]
                [--label NAME] [--php7compat] [--exit-as-halt] [--concretize] [--switch-cmp]

An app with a `db` block in apps.json (a real app) runs in APP MODE: the copy is
instrumented with harness_app.php's targets and the chosen options, every
request runs in its own PHP 8.2 process (harness_app.php) inside the network
namespace of ACE's own clone database (`ace-<app>-db`, appdb.py), and that
database is restored from its snapshot before each entry script (decision (a)).
Results go to results/<app>/<label>/ (default label: the arm), so a new run
never overwrites an old one.

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
import functools
import json
import os
import pathlib
import re
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

import appdb                                                           # noqa: E402
import judge                                                           # noqa: E402
import sinks                                                           # noqa: E402

APPS = json.loads((HERE / "apps.json").read_text())
GLOBALS = ("GET", "POST", "COOKIE")
FAMILIES = {**{n: sinks.SQL for n in ("mysqli_query", "mysqli_real_query", "mysqli_multi_query", "mysql_query",
                                      # E7 (--db-classes): object-style sinks, harness_db.php
                                      "PDO::prepare", "PDO::query", "PDO::exec", "mysqli::query",
                                      "mysqli::real_query", "mysqli::multi_query", "mysqli::prepare")},
            **{n: sinks.SHELL for n in ("system", "exec", "shell_exec", "passthru", "popen", "proc_open")}}
PHP = ["docker", "run", "--rm", "-i", *appdb.LOG_OPTS, "-u", f"{os.getuid()}:{os.getgid()}",
       "-v", f"{ROOT}:{ROOT}", "-w", str(HERE), "php:8.2-cli", "php"]
#: PHP 8.2 plus mysqli, for app mode (php:8.2-cli has no mysqli). Built on first use.
APP_IMAGE = "ace-php82-mysqli:2"
APP_DOCKERFILE = "FROM php:8.2-cli\nRUN docker-php-ext-install mysqli pdo_mysql >/dev/null\n"
MODE = {"app": None}          # set by main(): the app name when running in app mode


def app_image() -> str:
    if subprocess.run(["docker", "image", "inspect", APP_IMAGE], capture_output=True).returncode != 0:
        subprocess.run(["docker", "build", "-q", "-t", APP_IMAGE, "-"], input=APP_DOCKERFILE, text=True, check=True)
    return APP_IMAGE


def app_runner(app: str) -> str:
    """`ace-<app>-php`: a long-lived PHP 8.2 container in ACE's clone DB's network namespace."""
    db = appdb.ensure(app, "ace")
    name = f"ace-{app}-{appdb.ACE_INSTANCE['suffix']}-php" if appdb.ACE_INSTANCE["suffix"] else f"ace-{app}-php"
    src = (HERE / APPS[app]["src"]).resolve()
    # An app whose config names its OWN absolute path (WeBid's `$main_path`) includes every file
    # from there, i.e. from the uninstrumented source. With `ace_build_at_src`, ACE's runner
    # mounts the instrumented COPY at that path (read-only), so those includes load the copy.
    # The container is labelled with the copy it mounts and recreated when that changes.
    mount = str(MODE.get("build") or src) if APPS[app].get("ace_build_at_src") else str(src)
    st = subprocess.run(["docker", "inspect", "-f", '{{.State.Running}} {{index .Config.Labels "ace.mount"}}', name],
                        capture_output=True, text=True)
    running, _, label = st.stdout.strip().partition(" ")
    if st.returncode == 0 and running == "true" and (label in ("", "<no value>", mount) if mount == str(src) else label == mount):
        return name
    if st.returncode == 0:
        subprocess.run(["docker", "rm", "-f", name], capture_output=True)
    subprocess.run(["docker", "run", "-d", "--name", name, *appdb.LOG_OPTS, "--network", f"container:{db}",
                    "--label", f"ace.mount={mount}",
                    "-u", f"{os.getuid()}:{os.getgid()}", "-v", f"{ROOT}:{ROOT}", "-v", f"{mount}:{src}:ro",
                    "-w", str(HERE), app_image(), "sleep", "infinity"], check=True, capture_output=True)
    return name


def harness_path(app_dir: pathlib.Path) -> str:
    """The path the harness runs the app from: the copy, or (`ace_build_at_src`) the app's own
    source path, where the runner mounts the copy -- so every file has ONE path in the run."""
    app = MODE["app"]
    if app and APPS[app].get("ace_build_at_src"):
        return str((HERE / APPS[app]["src"]).resolve())
    return str(app_dir)


def php(requests: list[dict]) -> list[dict]:
    app = MODE["app"]
    if app:
        cmd = ["docker", "exec", "-i", app_runner(app), "php", "-d", "display_errors=0", "harness_app.php", "--batch"]
    else:
        cmd = [*PHP, "harness.php"]
    try:
        p = subprocess.run(cmd, input=json.dumps(requests), capture_output=True, text=True, timeout=3600)
        if p.returncode == 0:
            return json.loads(p.stdout)
        why = f"batch exited {p.returncode}: {p.stderr[-500:]}"
    except (subprocess.TimeoutExpired, json.JSONDecodeError) as e:
        why = f"batch failed: {type(e).__name__}"
    if not app:
        raise SystemExit(f"harness failed: {why}")
    # App mode: a crashed batch (the app exhausting memory, ...) is a harness error for each of
    # its requests, recorded in the script's summary; exploration of the next script goes on.
    return [{"harness_error": why} for _ in requests]


def instrument(app: str, label: str | None = None, options: tuple[str, ...] = ()) -> pathlib.Path:
    """Instrument a COPY of the app. Options change only that copy (build/<app>[-<label>])."""
    build = HERE / "build" / (app if not MODE["app"] else f"{app}-{label}")
    src = (HERE / APPS[app]["src"]).resolve()
    if MODE["app"]:
        cmd = ["docker", "run", "--rm", "-i", *appdb.LOG_OPTS, "-u", f"{os.getuid()}:{os.getgid()}",
               "-v", f"{ROOT}:{ROOT}", "-v", f"{src}:{src}:ro", "-w", str(HERE), app_image(), "php", "-d", "memory_limit=4G",
               "instrument_app.php", str(src), str(build), "--app-targets", *options,
               *([f"--ext={','.join(APPS[app]['php_exts'])}"] if APPS[app].get("php_exts") else [])]
    else:
        cmd = [*PHP, "instrument_app.php", str(src), str(build)]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(f"instrumentation failed:\n{p.stderr[-3000:]}")
    (HERE / "build" / f"{build.name}.instrument.json").write_text(p.stdout)
    return build


# -- requests ---------------------------------------------------------------
#
# A request is {global: {key: value-or-None}}. `None` is ABSENT.

def canon(req: dict) -> str:
    return json.dumps({g: dict(sorted(req.get(g, {}).items())) for g in GLOBALS}, sort_keys=True)


#: The authenticated arm's credential default (decision DEFAULT, M2): a newly declared key whose
#: name matches `login.credential_keys` starts with the login password instead of absent, as a
#: logged-in crawler fills a password field. Empty in every other arm.
KEY_DEFAULTS: dict = {}


def _default(g: str, k: str):
    rx = KEY_DEFAULTS.get("regex")
    return KEY_DEFAULTS["value"] if rx and g == "POST" and re.search(rx, k) else None


def with_keys(req: dict, keys: dict[str, set]) -> dict:
    """`req` with every known key declared; ones it does not set are absent (or a credential default)."""
    return {g: {k: req.get(g, {}).get(k, _default(g, k)) for k in sorted(keys[g] | set(req.get(g, {})))}
            for g in GLOBALS}


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


def negations(dump: dict, names: dict[str, tuple], base: dict, deadline: float | None = None):
    """One request per branch this run took, flipped against its prefix."""
    run = Run.from_dict(dump)
    symbols = run.symbols()
    pcs = run.path_conditions
    observed = [pc.expr if pc.taken else ("not", pc.expr) for pc in pcs]
    for i, pc in enumerate(pcs):
        if deadline is not None and time.monotonic() >= deadline:
            return
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


def explore(app_dir: pathlib.Path, script: str, seeds: list[dict], max_rounds: int,
            budget_s: float | None = None, extra: dict | None = None) -> dict:
    keys = {g: set() for g in GLOBALS}
    for s in seeds:
        for g in GLOBALS:
            keys[g] |= set(s.get(g, {}))
    queue = [with_keys(s, keys) for s in seeds]
    seen, traces, kept, errors, names = set(), set(), [], [], {}
    rounds = 0
    deadline = time.monotonic() + budget_s if budget_s else None
    extra = extra or {}
    php7 = {"const7": {}, "count7": 0, "cmp7": 0, "arith7": 0}
    while queue and rounds < max_rounds and (deadline is None or time.monotonic() < deadline):
        fresh = []
        for req in queue:
            req = with_keys(req, keys)
            if canon(req) not in seen:
                seen.add(canon(req))
                fresh.append(req)
        queue = []
        if not fresh:
            if kept and (deadline is None or time.monotonic() < deadline):
                cov, _ = coverage(kept, names)
                for m in cov.missing:
                    if not m.untracked and m.concrete_values:
                        queue.append(_from_model(m.concrete_values, names, kept[-1]["request"]))
                queue = [q for q in queue if canon(with_keys(q, keys)) not in seen]
            if not queue:
                break
            continue
        rounds += 1
        if deadline is not None:
            # Bounded batches, so the wall-clock budget is checked often.
            fresh, overflow = fresh[:40], fresh[40:]
            for r in overflow:
                seen.discard(canon(r))
                queue.append(r)
        batch = [{"app": harness_path(app_dir), "script": script, "label": f"r{rounds:02}_{i:03}", "inputs": r,
                  **({k: (v(r) if callable(v) else v) for k, v in extra.items()})}
                 for i, r in enumerate(fresh)]
        for req, res in zip(fresh, php(batch)):
            if "harness_error" in res:
                errors.append(f"harness: {res['harness_error']}: {res.get('stderr', '')[-300:]}")
                continue
            for k, v in (res.get("php7") or {}).items():
                if isinstance(v, (dict, list)):
                    bucket = php7.setdefault(k, {})
                    for c, n in (v if isinstance(v, dict) else {}).items():
                        bucket[c] = bucket.get(c, 0) + n
                else:
                    php7[k] = php7.get(k, 0) + v
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
                if not MODE["app"]:
                    continue
                # App mode KEEPS an errored run: every event before the error
                # (a sink reached, a branch taken) really happened, and a sink
                # is often reached just before the app trips over its result.
            sig = trace(dump)
            if sig in traces:
                continue
            traces.add(sig)
            dump["request"] = req
            kept.append(dump)
            if deadline is not None and time.monotonic() >= deadline:
                continue                         # budget spent: keep the trace, expand no further
            queue.extend(negations(dump, names, req, deadline))
    return {"kept": kept, "errors": errors, "keys": {g: sorted(k) for g, k in keys.items()},
            "requests": len(seen), "rounds": rounds, "names": names, "budget_hit": bool(queue), "php7": php7}


def server_vars(app: str, src: pathlib.Path, script: str, req: dict) -> dict:
    """$_SERVER for one request: the judge's own CGI environment for it (H1)."""
    env, _ = judge.cgi_env(app, {"script": script, **{g: {k: v for k, v in req.get(g, {}).items() if v is not None}
                                                       for g in GLOBALS}}, src)
    return {k: v for k, v in env.items() if k not in ("PATH", "SCRIPT_FILENAME", "DOCUMENT_ROOT")}


def rel_file(path: str | None, app_dir: pathlib.Path) -> str:
    """A dump location relative to the instrumented tree (= the app's own relative path). Under
    `ace_build_at_src` a file can also be named by the app's own source path."""
    path = path or ""
    for root in (str(app_dir) + "/", str((HERE / APPS[MODE["app"]]["src"]).resolve()) + "/" if MODE["app"] else None):
        if root and path.startswith(root):
            return path[len(root):]
    return path.rsplit("/", 1)[-1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("app")
    ap.add_argument("--arm", choices=("cold", "witcher", "auth"), default="cold")
    ap.add_argument("--only", action="append", help="entry script (repeatable)")
    ap.add_argument("--max-rounds", type=int, default=50)
    ap.add_argument("--budget", type=float, help="wall-clock seconds per entry script (H5)")
    ap.add_argument("--label", help="results/<app>/<label>/ (default: the arm)")
    ap.add_argument("--php7compat", action="store_true", help="E2 (DEFAULT-off; app mode)")
    ap.add_argument("--exit-as-halt", action="store_true", help="E3 (app mode)")
    ap.add_argument("--switch-cmp", action="store_true", help="switch via __cmp (app mode)")
    ap.add_argument("--concretize", action="store_true", help="E4 (app mode)")
    ap.add_argument("--array-mode", action="store_true", help="decision (b): real-array superglobals (app mode)")
    ap.add_argument("--real-app-builtins", action="store_true", help="route type predicates through __fn (app mode)")
    ap.add_argument("--sanitizers", action="store_true", help="E5: sanitizers as tagged template parts (app mode)")
    ap.add_argument("--xss", action="store_true", help="E6 output events + the XSS oracle (app mode)")
    ap.add_argument("--instance", default="", help="use ACE clone ace-<app>-<N>-db / runner ace-<app>-<N>-php")
    ap.add_argument("--shard", help="i/n: explore only scripts[i::n] (parallel shards, each with its own --instance)")
    ap.add_argument("--skip-done", action="store_true", help="skip scripts that already have a summary.json under the label")
    ap.add_argument("--reuse-build", action="store_true", help="reuse build/<app>-<label> if it exists (shards)")
    ap.add_argument("--eval-instrument", action="store_true", help="instrument eval'd code at run time (WeBid templates)")
    ap.add_argument("--template-split", action="store_true", help="explode() on a SQL template keeps its parts (ADOdb)")
    ap.add_argument("--db-classes", action="store_true", help="E7: object-style PDO/mysqli sinks (app mode)")
    ap.add_argument("--site-by-statement", action="store_true",
                    help="one finding per (site, statement shape), not per site: for apps whose every query "
                         "goes through ONE wrapper line (WeBid's DatabasePDO.php:76)")
    a = ap.parse_args()

    spec = APPS[a.app]
    label = a.label or a.arm
    app_mode = bool(spec.get("db"))
    MODE["app"] = a.app if app_mode else None
    options = tuple(f for f, on in (("--php7compat", a.php7compat), ("--exit-as-halt", a.exit_as_halt),
                                    ("--switch-cmp", a.switch_cmp), ("--superglobal-reads", a.array_mode),
                                    ("--real-app-builtins", a.real_app_builtins),
                                    ("--db-classes", a.db_classes), ("--eval-instrument", a.eval_instrument)) if on)
    appdb.ACE_INSTANCE["suffix"] = a.instance
    MODE["app"] = a.app if app_mode else None
    built = HERE / "build" / f"{a.app}-{label}"
    if a.reuse_build and app_mode and built.is_dir() and (HERE / "build" / f"{built.name}.instrument.json").exists():
        app_dir = built
    else:
        app_dir = instrument(a.app, label, options)
    MODE["build"] = app_dir
    src = (HERE / spec["src"]).resolve()
    extra: dict = {}
    if app_mode:
        flags = {"php7Compare": a.php7compat, "concretize": a.concretize, "arrayMode": a.array_mode, "sanitizers": a.sanitizers,
                 "outputEvents": a.xss, "templateSplit": a.template_split,
                 # the instrumentor options eval'd code is instrumented with (= the copy's)
                 "evalInstrument": ({k: True for k, on in (("php7Compat", a.php7compat), ("exitAsHalt", a.exit_as_halt),
                                     ("switchCmp", a.switch_cmp), ("superglobalReads", a.array_mode),
                                     ("realAppBuiltins", a.real_app_builtins), ("evalInstrument", True)) if on}
                                    | ({"newClassMap": {"pdo": "\\AcePDO", "mysqli": "\\AceMysqli"}} if a.db_classes else {})
                                    if a.eval_instrument else None)}
        extra = {"flags": flags, "session": {}, "session_ser": ""}
    seeds_by_script = witcher_seeds(a.app) if a.arm == "witcher" else {}
    if a.arm == "auth":
        seeds_by_script = {s: [auth_seed(a.app)] for s in spec["scripts"]}
        login = spec["login"]
        if login.get("credential_keys"):
            KEY_DEFAULTS.update(regex=login["credential_keys"])
    out = HERE / "results" / a.app / label
    out.mkdir(parents=True, exist_ok=True)
    (out / "run.json").write_text(json.dumps({"arm": a.arm, "options": options, "concretize": a.concretize,
                                              "sanitizers": a.sanitizers, "array_mode": a.array_mode,
                                              "site_by_statement": a.site_by_statement,
                                              "budget_s": a.budget, "max_rounds": a.max_rounds,
                                              "instrument": json.loads((HERE / "build" / f"{app_dir.name}.instrument.json").read_text())
                                              if app_mode else None}, indent=1) + "\n")
    rows = []
    scripts = spec["scripts"]
    if a.shard:
        i, n = map(int, a.shard.split("/"))
        scripts = scripts[i::n]
    for script in scripts:
        if a.only and script not in a.only:
            continue
        if a.skip_done and (out / script.replace("/", "__") / "summary.json").exists():
            continue
        seeds = seeds_by_script.get(script) or [{}]
        if app_mode:
            appdb.ensure(a.app, "ace")                  # a no-op once the clone is up
            appdb.restore(a.app, "ace")                 # decision (a): reset per script
            extra["server"] = functools.partial(server_vars, a.app, src, script)
            if a.arm == "auth":
                extra["script"] = script
                try:
                    login_session(a.app, app_dir, extra)   # sets extra["session_ser"] (and auth cookies)
                except SystemExit as e:
                    # A failed login is recorded for this script; the next script logs in afresh.
                    dd = out / script.replace("/", "__")
                    dd.mkdir(parents=True, exist_ok=True)
                    (dd / "summary.json").write_text(json.dumps({"script": script, "wall_s": 0, "requests": 0, "rounds": 0,
                        "traces": 0, "errored": 1, "first_error": f"login failed: {str(e)[:300]}", "keys_discovered": {},
                        "budget_hit": False, "coverage_complete": False, "missing": None, "assumptions": [],
                        "sink_sites": [], "errors_distinct": [f"login failed: {str(e)[:150]}"]}, indent=1) + "\n")
                    print(f"{script:28} login failed", flush=True)
                    continue
                seeds = [{"COOKIE": {**auth_seed(a.app)["COOKIE"], **extra.pop("auth_cookies", {})}}]
        t0 = time.monotonic()
        r = explore(app_dir, script, seeds, a.max_rounds, a.budget, extra)
        wall = round(time.monotonic() - t0, 1)
        d = out / script.replace("/", "__")
        d.mkdir(parents=True, exist_ok=True)
        for stale in d.glob("dump_*.json"):
            stale.unlink()
        found = []
        concretized, halted = {}, 0
        for dump in r["kept"]:
            (d / f"dump_{dump['label']}.json").write_text(json.dumps(dump, indent=1))
            halted += bool(dump.get("halted"))
            for e in dump["events"]:
                if e["type"] == "concretized":
                    k = f"{e['what']} @ {rel_file(e.get('file'), app_dir)}:{e.get('lineno')}"
                    concretized[k] = concretized.get(k, 0) + 1
            for f in sinks.findings(dump, FAMILIES) + (sinks.xss_findings(dump) if a.xss else []):
                f["request"] = {g: {k: f["witness"].get(n) for n, (gg, k) in r["names"].items() if gg == g
                                    and f["witness"].get(n) is not None} for g in GLOBALS}
                found.append(f)
        cov, assumed = coverage(r["kept"], r["names"]) if r["kept"] else (None, [])
        # One finding per sink site: the first witness that reached it.
        sites = {}
        for f in found:
            shape = (re.sub(r"\$\$\(p\d+\)", "$$", str(f.get("statement"))),) if a.site_by_statement else ()
            sites.setdefault((rel_file(f["file"], app_dir) if app_mode else f["file"].rsplit("/", 1)[-1],
                              f["lineno"], f["sink"], *shape), f)
        row = {"script": script, "wall_s": wall, "requests": r["requests"], "rounds": r["rounds"], "traces": len(r["kept"]),
               "errored": len(r["errors"]), "first_error": r["errors"][0] if r["errors"] else None,
               "keys_discovered": r["keys"], "budget_hit": r["budget_hit"],
               "coverage_complete": bool(cov and cov.complete), "missing": len(cov.missing) if cov else None,
               "assumptions": assumed,
               "sink_sites": [{"site": f"{k[0]}:{k[1]}", "sink": k[2], "kind": f["kind"],
                               "instance": f["instance"], "request": f["request"],
                               **({"db_errno": f["db_errno"]} if f.get("db_errno") is not None else {})}
                              for k, f in sites.items()]}
        if app_mode:
            row |= {"errors_distinct": sorted(set(e[:160] for e in r["errors"]))[:20], "halted_traces": halted,
                    "concretized": concretized, "php7_runtime": r["php7"]}
        (d / "summary.json").write_text(json.dumps(row, indent=1) + "\n")
        rows.append(row)
        print(f"{script:28} {row['traces']:3} traces {row['requests']:3} requests  "
              f"{'complete' if row['coverage_complete'] else str(row['missing']) + ' missing':12} "
              f"sinks={len(row['sink_sites'])} errored={row['errored']} {wall}s", flush=True)
    if not a.only and not a.shard:
        (out / "summary.json").write_text(json.dumps(rows, indent=1) + "\n")
    return 0


def login_session(app: str, app_dir: pathlib.Path, extra: dict) -> dict:
    """M2: run the app's OWN login request (apps.json `login.request`) through the harness, on the
    freshly restored DB, and return the `$_SESSION` it leaves -- the authenticated arm's seed."""
    recipe = judge.login_recipe(app, extra["script"])
    src = (HERE / APPS[app]["src"]).resolve()

    def run(req, session_ser):
        return php([{"app": harness_path(app_dir), "script": req["script"], "label": "login",
                     "inputs": {g: req.get(g, {}) for g in GLOBALS}, "flags": extra.get("flags", {}),
                     "session": {}, "session_ser": session_ser, "server": server_vars(app, src, req["script"], req)}])[0]
    req, ser = recipe["request"], ""
    if recipe.get("pre"):
        # Two-step login (phpMyAdmin): the form token comes from the first page's output.
        res = run(recipe["pre"], "")
        ser = res.get("session_after_ser") or ""
        m = re.search(recipe["token"]["regex"], res.get("output") or "")
        if m:
            req = {**req, "POST": {**req.get("POST", {}), recipe["token"]["into"]: m.group(1)}}
    res = run(req, ser)
    session = res.get("session_after") or {}
    extra["session_ser"] = res.get("session_after_ser") or ""
    judge.pin_session_db(app, "ace")
    if extra["session_ser"] and APPS[app]["login"].get("pin_token"):
        import base64
        raw = base64.b64decode(extra["session_ser"]).decode("latin-1")
        extra["session_ser"] = base64.b64encode(judge.pin_session_token(app, raw).encode("latin-1")).decode()
    cookies = {}
    for name, args in res.get("standins") or []:
        if name in ("setcookie", "setrawcookie") and args and len(args) > 1 and args[1] not in (None, "", False):
            cookies[args[0]] = str(args[1])
    if "success_db_sql" in recipe:
        # A DB-stored session (OpenCart 3): the login took when the query finds a row.
        got = appdb.sql(appdb.container(app, "ace"), recipe["success_db_sql"], APPS[app]["db"]["database"]).strip()
        ok = got not in ("", "0")
    elif "success_cookie" in recipe:
        ok = recipe["success_cookie"] in cookies
    else:
        ok = str(_find_key(session, recipe["success_key"]) or "") not in ("", "-1")
    if not ok:
        raise SystemExit(f"{app}: login recipe {recipe['prefix']!r} did not log in (session keys {list(session)[:12]}, "
                         f"cookies {list(cookies)}, error {(res.get('dump') or {}).get('error')})")
    KEY_DEFAULTS["value"] = recipe.get("password")
    extra["auth_cookies"] = cookies if APPS[app]["login"].get("cookies_from_login") else {}
    return session


def _find_key(obj, key: str):
    """`key` at the top of the session, or (OpenCart: $_SESSION[<id>][...]) at any depth."""
    if isinstance(obj, dict):
        if obj.get(key) not in (None, ""):
            return obj[key]
        for v in obj.values():
            found = _find_key(v, key)
            if found not in (None, ""):
                return found
    return None


def auth_seed(app: str) -> dict:
    """The authenticated arm's seed request: just the login cookie (the judge logs in on it)."""
    return {"COOKIE": dict(APPS[app]["login"]["cookie"])}


if __name__ == "__main__":
    raise SystemExit(main())
