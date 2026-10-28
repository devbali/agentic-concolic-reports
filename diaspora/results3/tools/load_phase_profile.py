#!/usr/bin/env python3
"""Split the coverage pass's LOAD phase into its two costs, with RSS.

The question the brief asks is whether the ~10 min, 136k-dump load is worth
parallelising.  It is per-dump JSON parsing, which is embarrassingly parallel --
but the load does two different things, and only ONE of them is per-dump:

  PARSE  json.load + Run.from_dict + apply_len_bounds   -- per dump, parallel
  SHARE  share_run_objects                              -- a process-global
         flyweight cache (_EV_CACHE/_SV_CACHE, keyed on json.dumps(to_dict()))
         that dedupes events and symbolic_vars ACROSS runs. That is what keeps
         a 96k-run corpus at 2.4 GB instead of tens of GB, and it is inherently
         single-process: two workers cannot share one cache, and Runs shipped
         back through pickle arrive as distinct objects that must be re-keyed
         in the parent anyway.

This measures both halves and the resident memory each buys, so the answer is
a number and not an opinion.

Usage: load_phase_profile.py <batch dir> [max dumps]
"""
import glob
import json
import os
import resource
import sys
import time

sys.path.insert(0, "/home/dev/project/src")
from concolic_engine import Run  # noqa: E402

HERE = sys.argv[1]
LIMIT = int(sys.argv[2]) if len(sys.argv) > 2 else 0

_EV_CACHE: dict = {}
_SV_CACHE: dict = {}


def share(run):
    run.events = [
        _EV_CACHE.setdefault(
            (type(ev).__name__, json.dumps(ev.to_dict(), sort_keys=True, default=str)), ev)
        for ev in run.events]
    run.symbolic_vars = [
        _SV_CACHE.setdefault(json.dumps(sv.to_dict(), sort_keys=True, default=str), sv)
        for sv in run.symbolic_vars]
    run.concrete_values = {
        sys.intern(k): (sys.intern(v) if isinstance(v, str) else v)
        for k, v in run.concrete_values.items()}
    run.script = None
    return run


def rss_mb():
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024


dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
if LIMIT:
    dumps = dumps[:LIMIT]
print(f"corpus: {len(dumps)} dumps from {HERE}", flush=True)

t_parse = t_share = 0.0
runs = []
t_all0 = time.time()
for p in dumps:
    t0 = time.time()
    try:
        raw = json.load(open(p))
        r = Run.from_dict(raw)
    except Exception:
        continue
    t1 = time.time()
    r = share(r)
    t2 = time.time()
    t_parse += t1 - t0
    t_share += t2 - t1
    runs.append(r)
    del raw
t_all = time.time() - t_all0

print(f"loaded {len(runs)} runs in {t_all:.1f}s")
print(f"  PARSE (json.load + Run.from_dict) : {t_parse:7.1f}s  "
      f"{100*t_parse/max(t_all,1e-9):5.1f}%   <- the parallelisable half")
print(f"  SHARE (flyweight dedupe, global)  : {t_share:7.1f}s  "
      f"{100*t_share/max(t_all,1e-9):5.1f}%   <- single-process by construction")
print(f"  peak RSS with sharing             : {rss_mb()} MB")
print(f"  distinct events kept              : {len(_EV_CACHE)}")
print(f"  distinct symbolic_vars kept       : {len(_SV_CACHE)}")
tot_ev = sum(len(r.events) for r in runs)
print(f"  event slots across runs           : {tot_ev} "
      f"({tot_ev / max(len(_EV_CACHE), 1):.1f}x sharing factor)")
