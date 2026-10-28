#!/usr/bin/env python3
"""repipe_only.py — re-run the PYTHON half over the surviving round-2 dumps.

No JVM, no re-drive: the 161 `runs/<id>/` dump sets from the 2026-09-26 sweep
are the input, so this isolates what changed in `src_new` from what the
endpoints do. Used to measure what the S-6 fix (`classify_note` reading the
note payload, src_new 2026-09-28) actually bought.
"""
import os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
BASE = "/home/dev/project/reports/autolab/e2e"
PY = "/home/dev/project/venvs/queries_from_runs/bin/python3"
OUT = sys.argv[1] if len(sys.argv) > 1 else BASE + "/results_s6fix"
os.makedirs(OUT, exist_ok=True)
eids = sorted(d for d in os.listdir(BASE + "/runs")
               if os.path.isdir(os.path.join(BASE, "runs", d)))
def one(e):
    t0 = time.time()
    cage = ["systemd-run", "--user", "--scope", "-q", "--collect",
            "-p", "MemoryMax=6G", "-p", "MemorySwapMax=0"]
    p = subprocess.run(cage + [PY, BASE + "/tools/pipeline.py", e,
                               BASE + "/runs/" + e, OUT + "/" + e + ".json"],
                       capture_output=True, text=True, timeout=900)
    return e, p.returncode, round(time.time() - t0, 1), (p.stderr or "")[-200:]
bad = 0
with ThreadPoolExecutor(max_workers=2) as ex:
    for e, rc, s, err in ex.map(one, eids):
        if rc != 0:
            bad += 1; print("RC!=0", e, rc, err[:150], flush=True)
print(f"done: {len(eids)} endpoints, {bad} non-zero rc", flush=True)
