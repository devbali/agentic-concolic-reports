#!/usr/bin/env python3
"""Which line of the coverage pass costs the memory? (§12.9)

The pass was SIGKILLed at MemoryMax=10G right after its `[assumptions]` line on
the 96 148-profile corpus. That is `CoverageChecker._analyze_coevaluation`'s
first loop, which keys the profile table with
`frozenset((e, frozenset(o)) for e, o in outcomes.items())`
(src/concolic_engine/coverage.py:717).

This probe loads through the batch's OWN load path (so the runs are exactly
what the pass sees) and then runs that loop TWICE -- once with the engine's key
and once with a 16-byte digest of the same information -- reporting RSS after
each. It builds no universe and writes no summary.

usage: DUMP_LIST=<snapshot> python3 -u _mem_probe.py
"""
import gc, hashlib, os, sys
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _exact_enum as EE          # its load_runs IS the pass's load path
                                 # (verified identical, campaign §10.2)


def rss():
    with open("/proc/self/status") as f:
        for l in f:
            if l.startswith("VmRSS:"):
                return int(l.split()[1]) / 1048576
    return -1


runs = EE.load_runs()
print(f"loaded {len(runs)} runs; RSS {rss():.2f} GB", flush=True)
base = rss()

for label in ("frozenset (engine, coverage.py:717)", "blake2b-16 digest"):
    gc.collect()
    before = rss()
    profiles = {}
    for run in runs:
        outcomes = {}
        for pc in run.path_conditions:
            outcomes.setdefault(pc.expr, set()).add(bool(pc.taken))
        if not outcomes:
            continue
        if label.startswith("frozenset"):
            key = frozenset((e, frozenset(o)) for e, o in outcomes.items())
        else:
            key = hashlib.blake2b(
                ";".join(f"{e}:{'1' if True in outcomes[e] else ''}"
                         f"{'0' if False in outcomes[e] else ''}"
                         for e in sorted(outcomes)).encode(),
                digest_size=16).digest()
        profiles.setdefault(key, outcomes)
    print(f"{label:40s} distinct={len(profiles):7d}  "
          f"RSS {rss():.2f} GB  (+{rss()-before:.2f} GB over the loaded runs)",
          flush=True)
    del profiles
    gc.collect()
    print(f"    after free: RSS {rss():.2f} GB", flush=True)
