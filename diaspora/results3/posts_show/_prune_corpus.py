#!/usr/bin/env python3
"""Minimal corpus whose §16b verdict equals the full corpus's.

WHY. Under DISCIPLINE §16b the checker reads exactly ONE thing off a run: the
map `expr -> {outcomes it took}` over the canonical expressions (its
"outcome profile"). The demand universe is built from those profiles
(`maximal_sets` over them), foreclosure is inferred from them
(`infer_foreclosures`), covering cubes and blocking clauses are built from
them, and `tree_missing` is the union of the sides they contain. Two runs with
the SAME profile are therefore interchangeable for every number the pass
reports — the engine already collapses them (`profiles.setdefault(...)`).

So the minimal covering subset is ONE DUMP PER DISTINCT OUTCOME PROFILE. That
is not a greedy approximation of set cover; it is exact for the verdict, and
it includes partial walks automatically (a partial walk has its own profile,
and the closed-prefix blocking rule reads that profile like any other).

It is NOT a substitute for the corpus: the extraction, the note audits and the
concrete checks read the dump FILES. Nothing is deleted — this writes a
SNAPSHOT LIST, and the next pass is pointed at it with DUMP_LIST.

usage: DUMP_LIST=<full snapshot> _prune_corpus.py --out <pruned.txt>
       [--shards N --shard i --part <f.json>]   (two-phase for parallelism)
"""
import glob, hashlib, json, os, sys
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals, fix_len_names  # noqa: E402


def opt(name, dflt=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else dflt


def profiles_of(paths):
    """path -> profile digest, in input order."""
    out = []
    for p in paths:
        try:
            d = json.load(open(p))
            canonicalize_ordinals(d)
            fix_len_names(d)
        except Exception:
            out.append((p, None, 0))
            continue
        acc = {}
        n = 0
        for e in d.get("events") or ():
            if e.get("type") == "path_condition":
                n += 1
                acc.setdefault(e["expr"], set()).add(bool(e.get("taken")))
        key = ";".join(f"{k}:{''.join('1' if v else '0' for v in sorted(acc[k]))}"
                       for k in sorted(acc))
        out.append((p, hashlib.blake2b(key.encode(), digest_size=16).hexdigest(), n))
        del d
    return out


_list = os.environ.get("DUMP_LIST")
if _list:
    dumps = sorted(l.strip() for l in open(_list) if l.strip())
    dumps = [d if os.path.isabs(d) else os.path.join(HERE, d) for d in dumps]
else:
    dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))

NS, SH = int(opt("--shards", "1")), int(opt("--shard", "0"))
part = opt("--part")
if part:
    res = profiles_of(dumps[SH::NS])
    json.dump(res, open(part, "w"))
    print(f"shard {SH}/{NS}: {len(res)} dumps profiled")
    sys.exit(0)

# single-process, or the MERGE step over --part files
parts = sorted(glob.glob(opt("--parts", "/nonexistent")))
rows = []
if parts:
    for f in parts:
        rows.extend(tuple(r) for r in json.load(open(f)))
else:
    rows = profiles_of(dumps)

# Keep the FIRST dump of each profile in the full snapshot's own order, so the
# pruned list is a deterministic function of the snapshot.
order = {p: i for i, p in enumerate(dumps)}
rows.sort(key=lambda r: order.get(r[0], 1 << 40))
keep = OrderedDict()
unparseable = 0
for p, dig, _n in rows:
    if dig is None:
        unparseable += 1
        continue
    keep.setdefault(dig, p)
out = opt("--out", os.path.join(HERE, "_snapshot_pruned.txt"))
with open(out, "w") as fh:
    fh.write("\n".join(sorted(keep.values())) + "\n")
print(f"corpus {len(dumps)} dumps -> {len(keep)} distinct outcome profiles "
      f"({unparseable} unparseable dropped); wrote {out}")
