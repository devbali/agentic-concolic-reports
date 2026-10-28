#!/usr/bin/env python3
"""ARE NOTE-LEVEL AUDITS PROFILE-INVARIANT? (coordinator question, 2026-09-11)

The coverage pass may run on the PRUNED list (one dump per distinct outcome
profile) because its verdict depends only on the profile. `statement_note_lint`
reads NOTES, not outcomes, so the same argument has to be made separately: can
two dumps with the SAME outcome profile carry DIFFERENT notes?

This measures it directly. Profile key = the engine's own equivalence,
`frozenset((expr, frozenset(outcomes)))` over CANONICALISED exprs — the same
relation `_prune_corpus.py` prunes by. Note key = the sorted set of
(target, note) over every symbolic_call.

If any profile holds two distinct note sets, the lint is NOT profile-invariant
and must not be run on the pruned list.
"""
import hashlib, json, os, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
import coverage_report as CR  # noqa: E402

files = [l.strip() for l in open(os.environ["DUMP_LIST"]) if l.strip()]
files = [f if os.path.isabs(f) else os.path.join(HERE, f) for f in files]
N = int(os.environ.get("SAMPLE", "20000"))
files = files[:N]
print(f"scanning {len(files)} dumps", flush=True)

def dig(x):
    return hashlib.blake2b(x.encode(), digest_size=16).digest()

prof = defaultdict(set)          # profile digest -> {note-set digest}
example = {}
n = 0
for p in files:
    try:
        d = json.load(open(p))
    except Exception:
        continue
    if hasattr(CR, "canonicalize_ordinals"):
        CR.canonicalize_ordinals(d)
    out = defaultdict(set)
    notes = set()
    for e in d.get("events") or ():
        t = e.get("type")
        if t == "path_condition":
            out[str(e.get("expr", ""))].add(bool(e.get("taken")))
        elif t == "symbolic_call":
            notes.add((str(e.get("target") or ""), str(e.get("note") or "")))
    pk = dig(";".join(f"{k}:{'1' if True in v else ''}{'0' if False in v else ''}"
                      for k in sorted(out) for v in [out[k]]))
    nk = dig("\n".join(sorted(f"{a}||{b}" for a, b in notes)))
    prof[pk].add(nk)
    example.setdefault(pk, []).append((os.path.basename(p), nk))
    n += 1
    del d
    if n % 5000 == 0:
        print(f"  [{n}/{len(files)}] profiles={len(prof)}", flush=True)

multi = {k: v for k, v in prof.items() if len(v) > 1}
print(f"\n=== NOTE-SET vs OUTCOME-PROFILE ===")
print(f"dumps scanned              : {n}")
print(f"distinct outcome profiles  : {len(prof)}")
print(f"profiles with >1 NOTE SET  : {len(multi)}")
print(f"=> PROFILE-INVARIANT       : {len(multi) == 0}")
if multi:
    worst = sorted(multi.items(), key=lambda kv: -len(kv[1]))[:5]
    print("\nprofiles carrying the most distinct note sets:")
    for pk, nks in worst:
        names = [nm for nm, _ in example[pk]][:4]
        print(f"  {len(nks)} distinct note sets over {len(example[pk])} dumps: {names}")
json.dump({"dumps": n, "profiles": len(prof), "multi": len(multi),
           "invariant": len(multi) == 0}, open(os.path.join(HERE, "_note_invariance.json"), "w"))
print("\nwrote _note_invariance.json")
