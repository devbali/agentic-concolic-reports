#!/usr/bin/env python3
"""Context-preserving pair seeds (gen3 saturation, phase 2).

For each uncovered same-context pair (a@sa, b@sb): find a dump whose run
OBSERVED b@sb, take that run's full applied seed dict (its whole context —
type, flags, everything), overlay the minimal seed forcing a@sa, and emit.
This closes pairs whose second expr only EXISTS under a coordinated context
that value-pair seeding cannot reconstruct. Falls back to the symmetric
direction. Usage: _gen_context_seeds.py <out.json>
"""
import glob
import itertools
import json
import sys

from _gen_saturation_seeds import seeds_for


def main():
    dumps = []
    for p in glob.glob("dump_*.json"):
        d = json.load(open(p))
        pcs = {}
        for ev in d["events"]:
            if ev.get("type") == "path_condition":
                pcs.setdefault(ev["expr"], ev["taken"])
        dumps.append((pcs, d.get("concolic_seeds") or {}))
    exprs = sorted(set(e for pcs, _ in dumps for e in pcs))

    tof = {}
    for pcs, _ in dumps:
        t = None
        for k in range(8):
            if pcs.get(f"(SYM_NOTE_TYPE_PROFILE == {k})") is True:
                t = k
        for e in pcs:
            tof.setdefault(e, set()).add(t)

    out = []
    for a, b in itertools.combinations(exprs, 2):
        if tof.get(a, set()).isdisjoint(tof.get(b, set())):
            continue
        for sa in (True, False):
            for sb in (True, False):
                if not any(pcs.get(a) == sa for pcs, _ in dumps):
                    continue
                if not any(pcs.get(b) == sb for pcs, _ in dumps):
                    continue
                if any(pcs.get(a) == sa and pcs.get(b) == sb for pcs, _ in dumps):
                    continue
                for base_expr, base_side, overlay_expr, overlay_side in (
                    (b, sb, a, sa), (a, sa, b, sb),
                ):
                    ov = seeds_for(overlay_expr, overlay_side)
                    if ov is None:
                        continue
                    base = next((cs for pcs, cs in dumps
                                 if pcs.get(base_expr) == base_side and cs), None)
                    if base is None:
                        continue
                    merged = dict(base)
                    merged.update(ov)
                    out.append(merged)
                    break

    seen, ded = set(), []
    for d in out:
        k = json.dumps(d, sort_keys=True)
        if k not in seen:
            seen.add(k)
            ded.append(d)
    json.dump(ded, open(sys.argv[1], "w"))
    print(f"{len(ded)} context seeds")


if __name__ == "__main__":
    main()
