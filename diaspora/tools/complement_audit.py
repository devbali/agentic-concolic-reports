#!/usr/bin/env python3
"""F4, dump-side (Bali directive 2026-08-25: all checks run ON DUMPS).
Report-only, exit 0.

    python3 complement_audit.py <batch_dir>

Run-level PC folding scopes every downstream query of a run by the run's
recorded PCs. A PC expr recorded with BOTH polarities across the corpus
is what becomes complementary `=`/`<>` view variants at extraction. The
merge decision needs exactly this dump-level fact: which producer-note
families appear under BOTH polarities (they execute on both sides of the
branch — folded variants will fragment, and their union is the unscoped
view: sound merge) vs under only ONE polarity (genuinely branch-gated —
the predicate is real and must be KEPT; e.g. the StartedSharing
contact/tags chain).
"""
import glob
import json
import os
import re
import sys
from collections import defaultdict

SELECT_RE = re.compile(r"\s*SELECT", re.I)


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: complement_audit.py <batch_dir>")
    batch = sys.argv[1]
    files = glob.glob(os.path.join(batch, "dump_*.json"))
    if not files:
        sys.exit(f"no dump_*.json under {batch}")

    polarity = defaultdict(set)                  # expr -> {True, False}
    fam_by_side = defaultdict(lambda: defaultdict(set))  # expr -> polarity -> note families

    for f in files:
        d = json.load(open(f))
        events = d.get("events") or []
        run_pcs = {}
        for ev in events:
            if ev.get("type") == "path_condition":
                run_pcs.setdefault(str(ev.get("expr", "")), bool(ev.get("taken")))
        run_fams = set()
        for ev in events:
            if ev.get("type") == "symbolic_call":
                n = str(ev.get("note") or "")
                if SELECT_RE.match(n):
                    run_fams.add(re.sub(r"\s+", " ", n)[:100])
        for sv in d.get("symbolic_vars") or []:
            n = str(sv.get("note") or "")
            if SELECT_RE.match(n):
                run_fams.add(re.sub(r"\s+", " ", n)[:100])
        for expr, taken in run_pcs.items():
            polarity[expr].add(taken)
            fam_by_side[expr][taken] |= run_fams

    both = {e for e, p in polarity.items() if p == {True, False}}
    print(f"== complement_audit (dump-side): {len(files)} dumps, "
          f"{len(polarity)} distinct PC exprs, {len(both)} with BOTH polarities ==\n")

    for expr in sorted(both):
        t_fams = fam_by_side[expr][True]
        f_fams = fam_by_side[expr][False]
        shared = t_fams & f_fams
        gated_t = t_fams - f_fams
        gated_f = f_fams - t_fams
        # only interesting if the expr scopes note families asymmetrically
        if not gated_t and not gated_f and not shared:
            continue
        print(f"-- {expr[:110]} --")
        print(f"   note families on BOTH sides (folded variants MERGEABLE to unscoped): {len(shared)}")
        if gated_t:
            print(f"   ONLY under taken=True (branch-gated — predicate must be KEPT): {len(gated_t)}")
            for fam in sorted(gated_t)[:4]:
                print(f"      {fam}")
        if gated_f:
            print(f"   ONLY under taken=False (branch-gated — predicate must be KEPT): {len(gated_f)}")
            for fam in sorted(gated_f)[:4]:
                print(f"      {fam}")
        print()


if __name__ == "__main__":
    main()
