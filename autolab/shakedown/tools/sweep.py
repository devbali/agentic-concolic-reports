#!/usr/bin/env python3
"""sweep.py — drive every scaffolded auto-lab endpoint through the shakedown.

Two stages per endpoint, each in its OWN OS process:

  1. the RUN.  `tools/diaspora-concolic-mod <scaffold>/run_dse.rb` (RAILS_ENV=concolic_mod) under
     `systemd-run --user --scope -p MemoryMax=…`, with `DUMP_OUT` pointed at
     `shakedown/runs/<id>/` so nothing is written into the generated
     `scaffold/` tree.  ONE PROCESS PER ENDPOINT, never reused: `install!`
     is not idempotent (README §"Three constraints", constraint 1).
  2. the PIPELINE.  `pipeline.py`, also its own process, so a z3 or JRuby-free
     crash costs one endpoint.

At most MAX_PAR (default 3) endpoints in flight.  The box is shared and
carries multi-day jobs; this does not fan out wider.

Checkpointing: one JSON line per finished endpoint, appended to
`shakedown/manifest.jsonl` under a lock.  A re-run skips every id already
in that file, so an interruption costs one endpoint.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = "/home/dev/project"
EP = f"{ROOT}/reports/autolab/entrypoints"
SCAFFOLD = f"{EP}/scaffold"
SHAKE = f"{ROOT}/reports/autolab/shakedown"
RUNS = f"{SHAKE}/runs"
LOGS = f"{SHAKE}/logs"
RESULTS = f"{SHAKE}/results"
MANIFEST = f"{SHAKE}/manifest.jsonl"
PY = f"{ROOT}/venvs/queries_from_runs/bin/python3"

_lock = threading.Lock()


def cage(cmd, env_extra, memmax="4G"):
    """One transient scope per process, so a runaway endpoint is OOM-killed
    inside its own cgroup instead of taking the box down."""
    pre = ["systemd-run", "--user", "--scope", "-q",
           "-p", f"MemoryMax={memmax}", "-p", "MemorySwapMax=0"]
    for k, v in env_extra.items():
        pre += [f"--setenv={k}={v}"]
    return pre + list(cmd)


def one(eid: str, max_runs: int, time_budget: int,
        run_timeout: int, pipe_timeout: int) -> dict:
    rec = {"endpoint": eid, "started_at": time.strftime("%FT%T")}
    t0 = time.time()
    outdir = f"{RUNS}/{eid}"
    os.makedirs(outdir, exist_ok=True)
    runner = f"{SCAFFOLD}/{eid}/run_dse.rb"
    log = f"{LOGS}/{eid}.log"

    # ---- stage 1: the run -------------------------------------------------
    cmd = cage([f"{SHAKE}/tools/diaspora-concolic-mod", runner],
               {"DUMP_OUT": outdir, "MAX_RUNS": str(max_runs),
                "TIME_BUDGET": str(time_budget)})
    try:
        with open(log, "wb") as fh:
            p = subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT,
                               timeout=run_timeout)
        rec["run_rc"] = p.returncode
        rec["run_timeout"] = False
    except subprocess.TimeoutExpired:
        rec["run_rc"] = None
        rec["run_timeout"] = True
    rec["run_seconds"] = round(time.time() - t0, 1)

    # ---- stage 2: the pipeline -------------------------------------------
    outjson = f"{RESULTS}/{eid}.json"
    t1 = time.time()
    try:
        q = subprocess.run(cage([PY, f"{SHAKE}/tools/pipeline.py",
                                 eid, outdir, outjson], {}, memmax="6G"),
                           capture_output=True, text=True, timeout=pipe_timeout)
        rec["pipeline_rc"] = q.returncode
        rec["pipeline_timeout"] = False
        if q.returncode != 0:
            rec["pipeline_stderr"] = (q.stderr or "")[-1500:]
    except subprocess.TimeoutExpired:
        rec["pipeline_rc"] = None
        rec["pipeline_timeout"] = True
    rec["pipeline_seconds"] = round(time.time() - t1, 1)

    if os.path.exists(outjson):
        try:
            r = json.load(open(outjson))
            rec["verdict"] = r.get("verdict")
            rec["stages"] = r.get("stages")
            rec["dumps"] = r.get("dumps_on_disk")
            rec["reach_best"] = r.get("reach_best")
            rec["declared_target_functions"] = r.get("declared_target_functions")
            rec["reads_profiles"] = r.get("reads_profiles")
            rec["profiles_select_star"] = r.get("profiles_select_star")
            rec["profiles_columns"] = r.get("profiles_columns")
            rec["profiles_wide_shapes"] = r.get("profiles_wide_shapes")
            rec["profiles_narrow_shapes"] = r.get("profiles_narrow_shapes")
            rec["path_conditions_max"] = r.get("path_conditions_max")
            rec["n_failures"] = len(r.get("failures") or ())
            rec["failure_kinds"] = [f"{f.get('stage')}:{f.get('type')}"
                                    for f in (r.get("failures") or ())]
        except Exception as e:
            rec["verdict"] = "harness_error"
            rec["harness_error"] = f"result json unreadable: {e}"
    else:
        rec["verdict"] = ("harness_error" if rec.get("pipeline_timeout")
                          else "harness_error")
        rec["harness_error"] = "pipeline produced no result json"

    rec["elapsed"] = round(time.time() - t0, 1)
    rec["finished_at"] = time.strftime("%FT%T")
    with _lock:
        with open(MANIFEST, "a") as fh:
            fh.write(json.dumps(rec) + "\n")
            fh.flush()
            os.fsync(fh.fileno())
    print(f"{eid:48s} {rec['verdict']:14s} dumps={rec.get('dumps')} "
          f"reach={rec.get('reach_best')}/{rec.get('declared_target_functions')} "
          f"prof={rec.get('reads_profiles')} {rec['elapsed']}s", flush=True)
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--par", type=int, default=3)
    ap.add_argument("--max-runs", type=int, default=2)
    ap.add_argument("--time-budget", type=int, default=120)
    ap.add_argument("--run-timeout", type=int, default=480)
    ap.add_argument("--pipe-timeout", type=int, default=420)
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()

    for d in (RUNS, LOGS, RESULTS):
        os.makedirs(d, exist_ok=True)

    ids = sorted(d for d in os.listdir(SCAFFOLD)
                 if os.path.isdir(os.path.join(SCAFFOLD, d)))
    done = set()
    if os.path.exists(MANIFEST):
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
          f"par={a.par}", flush=True)

    with ThreadPoolExecutor(max_workers=a.par) as ex:
        list(ex.map(lambda i: one(i, a.max_runs, a.time_budget,
                                  a.run_timeout, a.pipe_timeout), todo))
    print("sweep finished", flush=True)


if __name__ == "__main__":
    sys.exit(main())
