#!/usr/bin/env python3
"""repipe.py — re-run ONLY the python pipeline stage over dumps already on
disk, and rewrite the manifest lines from the fresh results.

The Ruby run is the expensive half (~90 s of JRuby/Rails boot); the pipeline
is seconds.  When the pipeline itself changes mid-sweep — as it did here,
after `path_conditions` was added — this re-derives every endpoint's result
from the SAME dumps rather than re-driving the app, so the reported numbers
all come from one version of the instrument.

Writes `manifest.jsonl` afresh (the old one is kept as `manifest.jsonl.bak`),
preserving each endpoint's run-stage fields (`run_rc`, `run_seconds`, …)
from the previous manifest.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

SHAKE = "/home/dev/project/reports/autolab/shakedown"
PY = "/home/dev/project/venvs/queries_from_runs/bin/python3"
MANIFEST = f"{SHAKE}/manifest.jsonl"

RUN_FIELDS = ("started_at", "run_rc", "run_timeout", "run_seconds",
              "finished_at")


def main():
    prev = {}
    for line in open(MANIFEST):
        line = line.strip()
        if line:
            r = json.loads(line)
            prev[r["endpoint"]] = r
    ids = sorted(prev)
    par = int(sys.argv[1]) if len(sys.argv) > 1 else 4

    def one(eid):
        outdir = f"{SHAKE}/runs/{eid}"
        outjson = f"{SHAKE}/results/{eid}.json"
        try:
            q = subprocess.run([PY, f"{SHAKE}/tools/pipeline.py", eid,
                                outdir, outjson],
                               capture_output=True, text=True, timeout=600)
            rc, err = q.returncode, (q.stderr or "")[-1500:]
        except subprocess.TimeoutExpired:
            rc, err = None, "pipeline timeout"
        rec = {k: prev[eid].get(k) for k in RUN_FIELDS}
        rec["endpoint"] = eid
        rec["pipeline_rc"] = rc
        if rc != 0:
            rec["pipeline_stderr"] = err
        if os.path.exists(outjson):
            r = json.load(open(outjson))
            rec.update({
                "verdict": r.get("verdict"), "stages": r.get("stages"),
                "dumps": r.get("dumps_on_disk"),
                "reach_best": r.get("reach_best"),
                "declared_target_functions": r.get("declared_target_functions"),
                "path_conditions_max": r.get("path_conditions_max"),
                "reads_profiles": r.get("reads_profiles"),
                "profiles_select_star": r.get("profiles_select_star"),
                "profiles_columns": r.get("profiles_columns"),
                "n_failures": len(r.get("failures") or ()),
                "failure_kinds": [f"{f.get('stage')}:{f.get('type')}"
                                  for f in (r.get("failures") or ())],
            })
        else:
            rec["verdict"] = "harness_error"
            rec["harness_error"] = "pipeline produced no result json"
        print(f"{eid:48s} {rec['verdict']}", flush=True)
        return rec

    with ThreadPoolExecutor(max_workers=par) as ex:
        recs = list(ex.map(one, ids))

    shutil.copy(MANIFEST, MANIFEST + ".bak")
    with open(MANIFEST, "w") as fh:
        for r in recs:
            fh.write(json.dumps(r) + "\n")
    print(f"rewrote {len(recs)} manifest lines")


if __name__ == "__main__":
    sys.exit(main())
