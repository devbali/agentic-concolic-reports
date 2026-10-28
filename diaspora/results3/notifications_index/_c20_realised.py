#!/usr/bin/env python3
"""C20 — per-KEY realisation report for a constructed drive.

usage: python3 _c20_realised.py <cov.json> <tag> [manifest.json]
Prints, per gap-set, how many driven runs REALISE the whole cube and, for the
ones that do not, which literal fell short and what was recorded instead
(REALISED / CONTRADICTED / UNEVALUATED, the campaign's three classes).
"""
import json, os, re, sys, glob, collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
import coverage_report as CR                                     # noqa: E402

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s


def split_lits(nc):
    out = []
    for part in nc.split(" AND "):
        p, w = part.strip(), True
        if p.startswith("Not(") and p.endswith(")"):
            w, p = False, p[4:-1]
        out.append((p, w))
    return out


def main():
    cov, tag = sys.argv[1], sys.argv[2]
    manp = sys.argv[3] if len(sys.argv) > 3 else os.path.join(HERE, "_c20_exists_manifest.json")
    miss = json.load(open(cov))["missing"]
    man = json.load(open(manp))
    gaps = {}
    for r in man:
        gaps.setdefault(r["gap"], r["missing_index"])
    files = sorted(glob.glob(os.path.join(HERE, f"dump_*_{tag}*.json")))
    print(f"driven dumps {len(files)}; gap-sets {len(gaps)}")
    # every driven run is checked against EVERY gap-set: a run built for one
    # cube may realise another, and the pass counts them all anyway.
    lits = {g: split_lits(miss[i]["node_constraint"]) for g, i in gaps.items()}
    hit = collections.Counter()
    short = collections.defaultdict(collections.Counter)
    for f in files:
        d = json.load(open(f))
        CR.canonicalize_ordinals(d)
        seen = {}
        for e in d.get("events") or ():
            if e.get("type") != "path_condition":
                continue
            seen.setdefault(fixlen(str(e.get("expr", ""))), set()).add(bool(e.get("taken")))
        for g, ls in lits.items():
            missl = [(e, w, sorted(seen.get(e, [])) or "UNEVALUATED")
                     for e, w in ls if not (e in seen and w in seen[e])]
            if not missl:
                hit[g] += 1
            else:
                for e, w, got in missl:
                    short[g][(e[-64:], w, str(got))] += 1
    print()
    for g in sorted(gaps, key=lambda x: int(x[1:])):
        print(f"{g} (missing[{gaps[g]}], width {len(lits[g])}): REALISED by {hit[g]} run(s)")
        if not hit[g]:
            for (e, w, got), n in short[g].most_common(4):
                cls = "CONTRADICTED" if got != "UNEVALUATED" else "UNEVALUATED"
                print(f"     {n:4d}x {cls:12s} want={w} got={got}  {e}")
    print(f"\nREALISED {sum(1 for g in gaps if hit[g])}/{len(gaps)} gap-sets")
    print(f"C20-REALISED-DONE {tag}")


if __name__ == "__main__":
    main()
