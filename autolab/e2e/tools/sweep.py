#!/usr/bin/env python3
"""sweep.py — the e2e (issue-inventory) sweep over every scaffolded endpoint.

Derived from shakedown/tools/sweep.py.  Differences, each deliberate:

  * MAX_RUNS is no longer 2.  MEASURED REASON: in the shakedown, 125 of 161
    endpoints stopped with `worklist_exhausted: false` and a non-empty
    worklist — they were cut off by MAX_RUNS, not by the time budget and not
    by having nothing left to explore.  DSE itself cost 390.8 s across all
    161 endpoints (max 9.8 s each) against ~180 s of JRuby+Rails boot per
    endpoint, so depth is nearly free and shallowness was a harness choice,
    not a constraint.
  * the pipeline always has its stderr captured, not only on a non-zero rc:
    the solver prints `Failed to eval var decl …` to stderr and returns 0.
  * PROCESS GROUP CLEANUP.  `subprocess.run(timeout=…)` kills only the direct
    child; a `systemd-run --scope` wrapper's JVM survives it.  Each stage is
    started in its OWN process group (`start_new_session`) and on timeout the
    whole group is SIGTERM'd then SIGKILL'd.
  * DISK BUDGET.  Deeper exploration writes more dumps.  The sweep refuses to
    start a new endpoint when free space on the results filesystem is under
    `--min-free-gb`, and records each endpoint's own dump bytes.
"""
from __future__ import annotations

import argparse
import itertools
import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = "/home/dev/project"
EP = f"{ROOT}/reports/autolab/entrypoints"
SCAFFOLD = f"{EP}/scaffold"
BASE = f"{ROOT}/reports/autolab/e2e"
RUNS = f"{BASE}/runs"
LOGS = f"{BASE}/logs"
RESULTS = f"{BASE}/results"
MANIFEST = f"{BASE}/manifest.jsonl"
PY = f"{ROOT}/venvs/queries_from_runs/bin/python3"

_lock = threading.Lock()


_unit_seq = itertools.count()


def cage(cmd, env_extra, memmax="4G", unit=None):
    """One transient scope per process, with a KNOWN UNIT NAME.

    MEASURED, INCLUDING A CORRECTION.  A first test appeared to show that a
    process-group kill left 2 descendants alive; that measurement was WRONG —
    the check was `pgrep -f 'sleep 300'` run inside `bash -c`, whose own
    command line contains the pattern, so it counted itself.  Re-measured
    properly (`scratchpad/pgtest3.py`, which marks the processes with
    `exec -a` and counts survivors by reading /proc rather than by pgrep),
    a cage'd parent + grandchild killed on timeout leaves **0 survivors with
    the process-group kill alone**: `start_new_session=True` puts the whole
    tree in one process group and neither systemd-run nor JRuby calls
    setsid.

    The unit name is kept anyway, for two reasons that do not depend on that:
    it makes an in-flight endpoint visible as
    `autolab-e2e-run-<pid>-<n>.scope` in `systemctl --user list-units`, and
    it reaps the scope even if some future stage does call setsid, which a
    process-group kill would then miss."""
    pre = ["systemd-run", "--user", "--scope", "-q", "--collect",
           "-p", f"MemoryMax={memmax}", "-p", "MemorySwapMax=0"]
    if unit:
        pre += [f"--unit={unit}"]
    for k, v in env_extra.items():
        pre += [f"--setenv={k}={v}"]
    return pre + list(cmd)


def new_unit(tag):
    return f"autolab-e2e-{tag}-{os.getpid()}-{next(_unit_seq)}"


def run_group(cmd, timeout, unit=None, **kw):
    """Run `cmd`; on timeout reap its systemd scope AND its process group.

    Two mechanisms, in this order, because neither alone is enough:
      1. `systemctl --user stop <unit>` — the scope holds the JVM, and only
         the unit reaches it (measured: a process-group kill alone left 2
         descendants alive);
      2. SIGTERM then SIGKILL to the process group — for a stage that was not
         cage'd, and as a backstop if systemctl is unavailable.
    """
    p = subprocess.Popen(cmd, start_new_session=True, **kw)
    try:
        out, errs = p.communicate(timeout=timeout)
        return p.returncode, out, errs, False
    except subprocess.TimeoutExpired:
        if unit:
            for verb in ("stop", "kill"):
                try:
                    subprocess.run(["systemctl", "--user", verb,
                                    unit + ".scope"], timeout=20,
                                   stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
                except Exception:
                    pass
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(os.getpgid(p.pid), sig)
            except (ProcessLookupError, PermissionError):
                pass
            try:
                out, errs = p.communicate(timeout=20)
                return None, out, errs, True
            except subprocess.TimeoutExpired:
                continue
        return None, None, None, True


def dir_bytes(d):
    n = 0
    for root, _dirs, files in os.walk(d):
        for f in files:
            try:
                n += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return n


def declared_limits(eid):
    """What the endpoint's OWN config.json says its run limits are.

    THE CONFIG IS THE DOCUMENT THE GATES READ.  `concolic.review` quotes it
    verbatim -- a campaign review item for `admin_pods_index` reads "Scenario
    'auth_json' is selected by the environment [MAX_RUNS=6, TIME_BUDGET=600]"
    -- and the campaign digests it (`config_digest`).  All 161 scaffolded
    configs declare `MAX_RUNS=6, TIME_BUDGET=600`; shakedown run 1 and run 2
    both drove `MAX_RUNS=2, TIME_BUDGET=120`.  So that sentence has never
    described a run that actually happened.  Reading the limits from the
    config makes the document and the run the same thing, and an explicit
    override is recorded rather than silently substituted."""
    try:
        cfg = json.load(open(f"{SCAFFOLD}/{eid}/config.json"))
    except Exception:
        return None, None
    for _name, sc in (cfg.get("scenarios") or {}).items():
        mr, tb = sc.get("MAX_RUNS"), sc.get("TIME_BUDGET")
        if mr is not None and tb is not None:
            return int(mr), int(tb)
    return None, None


def one(eid: str, a) -> dict:
    cfg_runs, cfg_budget = declared_limits(eid)
    max_runs = a.max_runs if a.max_runs is not None else (cfg_runs or 6)
    time_budget = a.time_budget if a.time_budget is not None else (cfg_budget or 600)
    rec = {"endpoint": eid, "started_at": time.strftime("%FT%T"),
           "max_runs": max_runs, "time_budget": time_budget,
           "config_max_runs": cfg_runs, "config_time_budget": cfg_budget,
           "limits_overridden": bool(
               (cfg_runs is not None and cfg_runs != max_runs) or
               (cfg_budget is not None and cfg_budget != time_budget))}
    t0 = time.time()
    outdir = f"{RUNS}/{eid}"
    os.makedirs(outdir, exist_ok=True)
    runner = f"{SCAFFOLD}/{eid}/run_dse.rb"
    log = f"{LOGS}/{eid}.log"

    unit = new_unit("run")
    cmd = cage([f"{BASE}/tools/diaspora-concolic-mod", runner],
               {"DUMP_OUT": outdir, "MAX_RUNS": str(max_runs),
                "TIME_BUDGET": str(time_budget)}, unit=unit)
    rec["run_unit"] = unit
    with open(log, "wb") as fh:
        rc, _o, _e, to = run_group(cmd, a.run_timeout, unit=unit,
                                   stdout=fh, stderr=subprocess.STDOUT)
    rec["run_rc"], rec["run_timeout"] = rc, to
    rec["run_seconds"] = round(time.time() - t0, 1)

    outjson = f"{RESULTS}/{eid}.json"
    t1 = time.time()
    punit = new_unit("pipe")
    rc2, out, errs, to2 = run_group(
        cage([PY, f"{BASE}/tools/pipeline.py", eid, outdir, outjson], {},
             memmax="6G", unit=punit),
        a.pipe_timeout, unit=punit,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    rec["pipeline_rc"], rec["pipeline_timeout"] = rc2, to2
    rec["pipeline_stderr"] = ((errs or b"").decode("utf8", "replace"))[-4000:]
    rec["pipeline_stdout"] = ((out or b"").decode("utf8", "replace"))[-2000:]
    rec["pipeline_seconds"] = round(time.time() - t1, 1)
    rec["dump_bytes"] = dir_bytes(outdir)

    if os.path.exists(outjson):
        try:
            r = json.load(open(outjson))
            for k in ("verdict", "stages", "reach_best", "reach_union_n",
                      "declared_target_functions", "reads_profiles",
                      "profiles_select_star", "path_conditions_max",
                      "accepted_dumps", "chosen_dump"):
                rec[k] = r.get(k)
            rec["dumps"] = r.get("dumps_on_disk")
            rec["n_failures"] = len(r.get("failures") or ())
            rec["failure_kinds"] = [f"{f.get('stage')}:{f.get('type')}"
                                    for f in (r.get("failures") or ())]
            rec["completion_complete"] = (r.get("completion") or {}).get("complete")
        except Exception as e:
            rec["verdict"] = "harness_error"
            rec["harness_error"] = f"result json unreadable: {e}"
    else:
        rec["verdict"] = "harness_error"
        rec["harness_error"] = ("pipeline timed out" if to2
                                else f"pipeline produced no result json (rc={rc2})")

    rec["elapsed"] = round(time.time() - t0, 1)
    rec["finished_at"] = time.strftime("%FT%T")
    with _lock:
        with open(MANIFEST, "a") as fh:
            fh.write(json.dumps(rec) + "\n")
            fh.flush()
            os.fsync(fh.fileno())
    print(f"{eid:48s} {str(rec['verdict']):14s} dumps={rec.get('dumps')} "
          f"reach={rec.get('reach_best')}/{rec.get('declared_target_functions')} "
          f"pcs={rec.get('path_conditions_max')} {rec['elapsed']}s", flush=True)
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--par", type=int, default=3)
    # DEFAULT None = take the limits from each endpoint's own config.json.
    # Passing either one overrides it for every endpoint and sets
    # `limits_overridden` in that endpoint's manifest row.
    ap.add_argument("--max-runs", type=int, default=None)
    ap.add_argument("--time-budget", type=int, default=None)
    ap.add_argument("--run-timeout", type=int, default=900)
    ap.add_argument("--pipe-timeout", type=int, default=600)
    ap.add_argument("--min-free-gb", type=float, default=10.0)
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--redo", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()

    for d in (RUNS, LOGS, RESULTS):
        os.makedirs(d, exist_ok=True)

    ids = sorted(d for d in os.listdir(SCAFFOLD)
                 if os.path.isdir(os.path.join(SCAFFOLD, d)))
    done = set()
    if os.path.exists(MANIFEST) and not a.redo:
        for line in open(MANIFEST):
            line = line.strip()
            if line:
                try:
                    done.add(json.loads(line)["endpoint"])
                except Exception:
                    pass
    todo = [i for i in ids if i not in done]
    if a.only:
        todo = [i for i in a.only if i in ids]
    if a.limit:
        todo = todo[:a.limit]
    print(f"scaffolded={len(ids)} already_done={len(done)} todo={len(todo)} "
          f"par={a.par} max_runs={a.max_runs if a.max_runs is not None else 'from config.json'} "
          f"tb={a.time_budget if a.time_budget is not None else 'from config.json'}",
          flush=True)

    stop = {"disk": False}

    def guarded(i):
        if stop["disk"]:
            return {"endpoint": i, "verdict": "skipped_disk"}
        free = shutil.disk_usage(BASE).free / 1e9
        if free < a.min_free_gb:
            stop["disk"] = True
            print(f"!! DISK BUDGET: {free:.1f} GB free < {a.min_free_gb} GB; "
                  f"stopping before {i}", flush=True)
            return {"endpoint": i, "verdict": "skipped_disk"}
        return one(i, a)

    with ThreadPoolExecutor(max_workers=a.par) as ex:
        list(ex.map(guarded, todo))
    print("sweep finished", flush=True)


if __name__ == "__main__":
    sys.exit(main())
