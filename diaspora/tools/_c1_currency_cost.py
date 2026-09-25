#!/usr/bin/env python3
"""C1 — the CURRENCY fix, and what it costs (2026-09-13).

`docs/CONFINEMENT_PRECISION_20260913.md` §2: notifications_index,
comments_index and conversations_index `coverage_report.py::fix_len_names`
pops `note`/`args` off every event (a 2026-08-27 memory optimisation), so
`concolic_engine.assumptions.call_shape` degenerates to the bare target name
and the engine's footprint currency is not the one the assumption gate's
`access_trace` is tested in. This tool measures, on the endpoint's OWN
loader:

  today   the shipped `fix_len_names` (note/args popped)
  keep    the same, minus the two `pop`s -- posts_show's currency
  digest  note replaced by its call_shape NORMAL FORM (binds and string
          literals already wildcarded) and every arg value by a shared
          sentinel of the same type -- the cheapest thing that can still
          reproduce call_shape exactly

Two things are reported per mode: PEAK RSS of the load (the reason the pops
exist) and the number of DISTINCT SHAPES the loaded Run objects yield, which
is the number that has to equal the gate's. `--shapes-only` streams (flat
memory) so the full corpus can be counted without holding it.

Read-only: imports the endpoint's coverage_report as a module (its work is
behind `if __name__ == "__main__"`) and writes only where --out points.
"""
import argparse
import gc
import importlib.util
import json
import os
import random
import re
import resource
import sys
import time

sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import call_shape, shape_str          # noqa: E402
from concolic_engine.run import Run                                    # noqa: E402
import concolic_engine.assumptions as _A                               # noqa: E402

# call_shape's own normal form, applied at load. Idempotent: `?` contains no
# `$$(`, and "'?'" maps to "'?'", so call_shape(target, NORM(note), .) ==
# call_shape(target, note, .) for every note.
def norm_note(note):
    if not note:
        return note
    return re.sub(r"'[^']*'", "'?'", _A._BIND_RE.sub("?", note))


# One shared value per type name, so `type(v).__name__` -- all call_shape
# reads of an arg -- is preserved while the value itself costs nothing.
_SENTINEL = {"int": 0, "str": "", "bool": False, "float": 0.0,
             "list": [], "dict": {}, "tuple": ()}


def norm_args(args):
    if not isinstance(args, dict):
        return args
    return {k: _SENTINEL.get(type(v).__name__, v)
            for k, v in args.items() if v is not None}


def rss_mb():
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024


def cur_rss_mb():
    with open("/proc/self/statm") as fh:
        return int(fh.read().split()[1]) * os.sysconf("SC_PAGE_SIZE") // (1 << 20)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", required=True)
    ap.add_argument("--snapshot", required=True)
    ap.add_argument("--mode", required=True, choices=("today", "keep", "digest"))
    ap.add_argument("--n", type=int, default=0, help="0 = the whole snapshot")
    ap.add_argument("--seed", type=int, default=20260913)
    ap.add_argument("--shapes-only", action="store_true")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    spec = importlib.util.spec_from_file_location(
        "_cr_under_test", os.path.join(a.batch, "coverage_report.py"))
    cr = importlib.util.module_from_spec(spec)
    sys.modules["_cr_under_test"] = cr
    spec.loader.exec_module(cr)                      # main() is behind __main__

    shipped = cr.fix_len_names

    def fix(dump):
        dump = shipped(dump)                         # the endpoint's own rename
        if a.mode == "today":
            return dump
        raw_evs = dump.get("_c1_raw_events") or ()
        for ev, src in zip(dump.get("events") or (), raw_evs):
            if src.get("note") is not None:
                ev["note"] = (norm_note(src["note"]) if a.mode == "digest"
                              else src["note"])
            if src.get("args") is not None:
                ev["args"] = (norm_args(src["args"]) if a.mode == "digest"
                              else src["args"])
        dump.pop("_c1_raw_events", None)
        return dump

    paths = [l.strip() for l in open(a.snapshot) if l.strip()]
    if a.n and a.n < len(paths):
        random.Random(a.seed).shuffle(paths)
        paths = sorted(paths[: a.n])

    t0 = time.time()
    shapes = {}
    runs = []
    nerr = 0
    canon = getattr(cr, "canonicalize_ordinals", None)
    for p in paths:
        try:
            raw = json.load(open(p))
        except Exception:
            nerr += 1
            continue
        try:
            if canon is not None:
                canon(raw)
            if a.mode != "today":
                # keep the untouched note/args alongside; fix() puts them back
                raw["_c1_raw_events"] = [
                    {"note": e.get("note"), "args": e.get("args")}
                    for e in raw.get("events") or ()]
            run = Run.from_dict(fix(raw))
            run = cr.apply_len_bounds(run)
            run = cr.share_run_objects(run)
        except Exception:
            nerr += 1
            continue
        if a.shapes_only:
            for ev in run.symbolic_call_events:
                if ev.result_name:
                    sh = call_shape(ev.target_name, ev.note, ev.args)
                    shapes.setdefault(sh, 0)
                    shapes[sh] += 1
        else:
            runs.append(run)
        del raw
    if not a.shapes_only:
        for run in runs:
            for ev in run.symbolic_call_events:
                if ev.result_name:
                    sh = call_shape(ev.target_name, ev.note, ev.args)
                    shapes.setdefault(sh, 0)
                    shapes[sh] += 1
    gc.collect()
    res = {"batch": a.batch, "mode": a.mode, "dumps": len(paths), "errors": nerr,
           "runs": len(runs), "distinct_shapes": len(shapes),
           "peak_rss_mb": rss_mb(), "rss_after_load_mb": cur_rss_mb(),
           "elapsed_s": round(time.time() - t0, 1),
           "shapes_only": bool(a.shapes_only),
           "shape_list": sorted(shape_str(s) for s in shapes)}
    print(json.dumps({k: v for k, v in res.items() if k != "shape_list"}))
    if a.out:
        json.dump(res, open(a.out, "w"))


if __name__ == "__main__":
    main()
