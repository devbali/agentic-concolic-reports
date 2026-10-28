#!/usr/bin/env python3
"""P29 — the ORDINAL-level joint for the comments family: how many raw ordinals
mint each comments canonical in one run, and what the length decision does at
each. This is the "both ways" question the D1 base filter actually asks."""
import json, os, sys, collections, re
from concurrent.futures import ProcessPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for
from coverage_assumptions import ALIASES
LEN = re.compile(r"^\(len\((SYM_RESULT_[A-Za-z0-9_]+)_rows\) != 0\)$")


def one(p):
    try:
        d = json.load(open(p))
    except Exception:
        return None
    ev = d.get("events") or ()
    amap = alias_map_for([(e.get("result_name"), e.get("note"))
                          for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    rev = collections.defaultdict(list)
    for raw, c in amap.items():
        if "_comments_" in c:
            rev[c].append(raw)
    if not rev:
        return None
    out = {}
    for c, raws in rev.items():
        per = {}
        for e in ev:
            if e.get("type") != "path_condition":
                continue
            m = LEN.match(str(e.get("expr")))
            if m and m.group(1) in raws:
                per.setdefault(m.group(1), set()).add(bool(e.get("taken")))
        out[c] = (sorted(raws), {k: sorted(v) for k, v in per.items()})
    return out


def main():
    lst = HERE + "/_snapshot_pruned_P26F2.txt"
    paths = [l.strip() for l in open(lst) if l.strip()]
    nord = collections.Counter(); ndec = collections.Counter()
    both = collections.Counter(); percanon = collections.Counter()
    multi_ord_outcomes = collections.Counter()
    with ProcessPoolExecutor(max_workers=int(os.environ.get("W", "3"))) as ex:
        for r in ex.map(one, paths, chunksize=200):
            if not r:
                continue
            for c, (raws, per) in r.items():
                s = c.split("_records_")[-1]
                percanon[s] += 1
                nord[(s, len(raws))] += 1
                ndec[(s, len(per))] += 1
                vals = set()
                for v in per.values():
                    vals |= set(v)
                if len(vals) == 2:
                    both[s] += 1
                if len(per) > 1:
                    multi_ord_outcomes[(s, tuple(sorted(tuple(v) for v in per.values())))] += 1
    print("%-16s %8s   raw ordinals minting it per run     length decisions per run   BOTH ways"
          % ("canonical", "runs"))
    for s in sorted(percanon):
        no = {k[1]: v for k, v in nord.items() if k[0] == s}
        nd = {k[1]: v for k, v in ndec.items() if k[0] == s}
        print("%-16s %8d   %-34s %-26s %6d"
              % (s, percanon[s], no, nd, both[s]))
    print("\nruns in which a comments canonical carries >1 length DECISION:")
    if not multi_ord_outcomes:
        print("   NONE")
    for k, n in multi_ord_outcomes.most_common(20):
        print("   ", k, n)
    print("P29-COMMENTS-ORD-DONE")


main()
