#!/usr/bin/env python3
"""Build the assumption gate's corpus index over a batch and print a BYTE
fingerprint of everything it built, plus how many dumps it actually parsed.

    idx_probe.py <batch_dir> [<checkpoint path>|-] [tag]

The fingerprint is over BASENAMES, so two directories holding the same corpus
fingerprint the same; it is a streaming blake2b over a canonical rendering of
_INDEX / _TRACE_INDEX / _ALIAS_INDEX -- the three structures `corpus_index`
builds and everything downstream reads.
"""
import hashlib
import json
import os
import resource
import sys
import time

sys.path.insert(0, "/home/dev/project/src")
from end_to_end_completion_checker.assumption import assumption_checker as AC  # noqa: E402

argv = sys.argv[1:]


def _opt(name):
    if name in argv:
        i = argv.index(name)
        v = argv[i + 1]
        del argv[i:i + 2]
        return v
    return None


declared_path = _opt("--declared")
canon = _opt("--canon")
batch = os.path.realpath(argv[0])
ckpt = argv[1] if len(argv) > 1 else "-"
tag = argv[2] if len(argv) > 2 else ""

# exactly what `main()` does with a manifest's "canonicalize" + declared set
declared = []
if declared_path:
    declared = json.load(open(declared_path))
    if isinstance(declared, dict):
        declared = declared.get("assumptions", [])
    AC._DECLARED_DIGEST = AC._ckpt.digest(declared)
if canon:
    import importlib
    from concolic_engine.assumptions import AliasAssumption
    mod_name, fn_name = canon.split(":")
    sys.path.insert(0, batch)
    mod = importlib.import_module(mod_name)
    AC._CANON_FN = getattr(mod, fn_name)
    AC._ALIASES = [AliasAssumption(result_pattern=a.get("result_pattern", ""),
                                   key=a.get("key", "statement"),
                                   k=int(a.get("k", 1)))
                   for a in declared
                   if a.get("type") in ("AliasAssumption", "DecisionAliasAssumption")] \
        or list(getattr(mod, "ALIASES", []) or [])
if ckpt and ckpt != "-":
    os.environ[AC.INDEX_CKPT_ENV] = ckpt
else:
    os.environ.pop(AC.INDEX_CKPT_ENV, None)

loads = {"n": 0}
_real = AC._load_dump_uncached


def counted(p):
    loads["n"] += 1
    return _real(p)


AC._load_dump_uncached = counted

t0 = time.time()
AC.corpus_index(batch)
elapsed = time.time() - t0


def fingerprint(b):
    h = hashlib.blake2b(digest_size=16)
    for p, seeds, scen, exprs in AC._INDEX[b]:
        h.update(json.dumps([os.path.basename(p), sorted(seeds.items()),
                             scen, sorted(exprs)],
                            sort_keys=True, default=str).encode())
        h.update(b"\x00")
    h.update(b"|TRACE|")
    tr = AC._TRACE_INDEX.get(b) or {}
    for p in sorted(tr):
        d, shapes, pcs = tr[p]
        h.update(json.dumps([os.path.basename(p), d, sorted(shapes),
                             sorted([e, bool(t)] for e, t in pcs)],
                            sort_keys=True, default=str).encode())
        h.update(b"\x00")
    h.update(b"|ALIAS|")
    al = AC._ALIAS_INDEX.get(b) or {}
    for p in sorted(al):
        h.update(json.dumps([os.path.basename(p), sorted(map(list, al[p]))],
                            sort_keys=True, default=str).encode())
        h.update(b"\x00")
    return h.hexdigest()


rows = 0
if ckpt and ckpt != "-" and os.path.exists(ckpt):
    with open(ckpt) as fh:
        rows = sum(1 for i, line in enumerate(fh) if i and line.strip())
print(json.dumps({
    "tag": tag, "batch": batch, "dumps": len(AC._INDEX[batch]),
    "parsed": loads["n"], "elapsed_s": round(elapsed, 1),
    "rate_per_s": round(len(AC._INDEX[batch]) / max(elapsed, 1e-9), 1),
    "fingerprint": fingerprint(batch),
    "ckpt_records": rows,
    "ckpt_bytes": os.path.getsize(ckpt) if (ckpt != "-" and os.path.exists(ckpt)) else 0,
    "stale_rotated": os.path.exists(ckpt + ".stale") if ckpt != "-" else False,
    "peak_rss_mb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0, 1),
}, sort_keys=True))
