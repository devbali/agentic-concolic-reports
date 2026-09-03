#!/usr/bin/env python3
"""Generate flip + pair-gap seed dicts from the current corpus (gen3
saturation loop). Usage: _gen_saturation_seeds.py <out.json>"""
import glob
import itertools
import json
import re
import sys


def seeds_for(expr, side):
    m = re.match(r"\((\S+) == StringVal\('([^']*)'\)\)$", expr)
    if m:
        return {m.group(1): (m.group(2) if side else "all")}
    m = re.match(r"\((\S+) != StringVal\('([^']*)'\)\)$", expr)
    if m:
        return {m.group(1): (("x" if m.group(2) == "" else "zzz") if side else m.group(2))}
    m = re.match(r"\((\S+) == ''\)$", expr)
    if m:
        return {m.group(1): ("" if side else "x")}
    m = re.match(r"\((\S+) == (SYM_\S+)\)$", expr)
    if m:
        return {m.group(1): 1, m.group(2): 1} if side else {m.group(1): 1, m.group(2): 0}
    m = re.match(r"\((\S+) (==|>|<|<=|>=) (-?\d+)\)$", expr)
    if m:
        v = int(m.group(3))
        op = m.group(2)
        val = {"==": v if side else v + 1,
               ">": v + 1 if side else v,
               "<": v - 1 if side else v + 1,
               "<=": v if side else v + 1,
               ">=": v if side else v - 1}[op]
        return {m.group(1): val}
    m = re.match(r"\((\S+) == True\)$", expr)
    if m:
        return {m.group(1): bool(side)}
    m = re.match(r"\((\S+) == False\)$", expr)
    if m:
        return {m.group(1): (not side)}
    return None


def main():
    runs = []
    for p in glob.glob("dump_*.json"):
        d = json.load(open(p))
        pcs = {}
        for ev in d["events"]:
            if ev.get("type") == "path_condition":
                pcs.setdefault(ev["expr"], ev["taken"])
        runs.append(pcs)
    exprs = sorted(set(e for r in runs for e in r))

    tof = {}
    for r in runs:
        t = None
        for k in range(8):
            if r.get(f"(SYM_NOTE_TYPE_PROFILE == {k})") is True:
                t = k
        for e in r:
            tof.setdefault(e, set()).add(t)

    out = []
    for e in exprs:
        sides = {r[e] for r in runs if e in r}
        if len(sides) > 1:
            continue
        s = seeds_for(e, not list(sides)[0])
        if s is None:
            continue
        types = set()
        for r in runs:
            if e in r:
                for k in range(8):
                    if r.get(f"(SYM_NOTE_TYPE_PROFILE == {k})") is True:
                        types.add(k)
        for t in (types or {0}):
            d = dict(s)
            d["SYM_NOTE_TYPE_PROFILE"] = t
            out.append(d)

    for a, b in itertools.combinations(exprs, 2):
        for sa in (True, False):
            for sb in (True, False):
                if not any(r.get(a) == sa for r in runs):
                    continue
                if not any(r.get(b) == sb for r in runs):
                    continue
                if any(r.get(a) == sa and r.get(b) == sb for r in runs):
                    continue
                s1, s2 = seeds_for(a, sa), seeds_for(b, sb)
                if s1 is None or s2 is None:
                    continue
                merged = dict(s1)
                if any(k in merged and merged[k] != v for k, v in s2.items()):
                    continue
                merged.update(s2)
                # seed inside every type context BOTH exprs share (the
                # first loop version pinned sorted[0] only, so pairs whose
                # common context is a higher type never got seeded — found
                # as ~45 uncovered pairs anchored at each TYPE==k True).
                common = {t for t in tof.get(a, set()) if t is not None} & \
                         {t for t in tof.get(b, set()) if t is not None}
                if "SYM_NOTE_TYPE_PROFILE" in merged or not common:
                    out.append(merged)
                else:
                    for t in sorted(common):
                        d2 = dict(merged)
                        d2["SYM_NOTE_TYPE_PROFILE"] = t
                        out.append(d2)

    seen, ded = set(), []
    for d in out:
        k = json.dumps(d, sort_keys=True)
        if k not in seen:
            seen.add(k)
            ded.append(d)
    json.dump(ded, open(sys.argv[1], "w"))
    print(f"{len(ded)} seeds")


if __name__ == "__main__":
    main()
