#!/usr/bin/env python3
"""P28 (read-only) — port of notifications' `_c17_seedkey_probe.py` to
posts_show: is every `len(X)` seed key the runner WRITES actually the key the
runtime READS, or is some dimension re-minted under a second name and the seed
therefore INERT?

Ground-truth differential on the corpus itself (DISCIPLINE: a check is a
differential, not an instance test): for every `len(X)` in a base's
`concolic_seeds`, compare the seed against the value the runtime minted under
that same name.

Difference from the C17 original, and why: C17 hard-codes notifications'
snapping (`snap013`/`snap014`) into the honour test. posts_show's `rows_mock`
may snap differently, and assuming the wrong snap would report a HONOURED key
as INERT. So this version does NOT assume a snap — it DERIVES the seed->minted
relation from the data and calls a key honoured iff the mapping is a
FUNCTION of the seed that every other key with that seed also obeys. Any
genuinely ignored seed shows up as a seed value mapping to several minted
values (a non-function), which no snapping can explain away.

usage: SAMPLE=600 [DUMP_LIST=...] python3 -u _p28_seedkey_probe.py
"""
import json, os, random, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_pruned_P26E2.txt"))
N = int(os.environ.get("SAMPLE", "600"))
REMINT = "preloaded association #"

files = [l.strip() for l in open(LIST) if l.strip()]
random.seed(28)
# stratify over the four scenarios so no variant's mocks are missed
byvar = defaultdict(list)
for f in files:
    b = os.path.basename(f)
    for v in ("auth_html", "anon_html", "auth_json", "anon_json"):
        if v in b:
            byvar[v].append(f); break
    else:
        byvar["other"].append(f)
sample = []
per = max(1, N // max(1, len(byvar)))
for v, fs in byvar.items():
    sample += random.sample(fs, min(per, len(fs)))
print(f"sample {len(sample)} dumps from {os.path.basename(LIST)} "
      f"({ {v: len(fs) for v, fs in byvar.items()} } available)\n", flush=True)

cls = Counter()
pairs = defaultdict(Counter)        # class -> Counter[(seed, minted)]
fam_pairs = defaultdict(Counter)    # family -> Counter[(seed, minted)]
notes_seen = Counter()
scanned = 0

for fp in sample:
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    scanned += 1
    seeds = d.get("concolic_seeds") or {}
    svs = {}
    for sv in d.get("symbolic_vars") or ():
        n = sv.get("name")
        if n:
            svs[n] = (sv.get("value"), sv.get("note") or "")
            nt = sv.get("note") or ""
            if nt.startswith(REMINT):
                notes_seen[nt.split(":")[0]] += 1
    for k, sval in seeds.items():
        if not (k.startswith("len(") and k.endswith(")")):
            continue
        if k not in svs:
            cls["NOT-MINTED (key written, variable never created on this run)"] += 1
            continue
        val, note = svs[k]
        c = ("REMINT (loaded-target early return)" if note.startswith(REMINT)
             else "SEED-CONSULTING MINT")
        cls[c] += 1
        try:
            sv_i, val_i = int(sval), int(val)
        except Exception:
            continue
        pairs[c][(sv_i, val_i)] += 1
        fam_pairs[re.sub(r"_\d+_", "_N_", k[4:-1])][(sv_i, val_i)] += 1

def verdict(counter):
    """A seed->minted relation is a FUNCTION (seed under control, possibly
    snapped) or NOT (seed ignored on some runs)."""
    bysee = defaultdict(set)
    for (s, v), n in counter.items():
        bysee[s].add(v)
    multi = {s: sorted(vs) for s, vs in bysee.items() if len(vs) > 1}
    tot = sum(counter.values())
    amb = sum(n for (s, v), n in counter.items() if s in multi)
    return tot, amb, multi, {s: sorted(vs)[0] for s, vs in bysee.items()}

print("len(X) seed keys, by what the runtime did with the name:")
for k, v in cls.most_common():
    print(f"  {v:8d}  {k}")
print(f"\nREMINT notes observed in the corpus: {len(notes_seen)}")
for k, v in notes_seen.most_common(10):
    print(f"  {v:8d}  {k}")

print("\nseed -> minted relation, per mint class:")
for c in sorted(pairs):
    tot, amb, multi, fn = verdict(pairs[c])
    print(f"  {c}")
    print(f"    observations {tot}, ambiguous (same seed -> several minted) {amb} "
          f"= {100.0*amb/max(1,tot):.1f} %  -> {'NOT A FUNCTION: seed IGNORED somewhere' if multi else 'A FUNCTION of the seed: the seed CONTROLS the mint'}")
    print(f"    mapping seed->minted: {dict(sorted(fn.items())[:12])}")
    if multi:
        print(f"    ambiguous seeds: {dict(sorted(multi.items())[:8])}")

print("\nper-family (ordinals folded), any family whose relation is NOT a function:")
bad = 0
for f in sorted(fam_pairs):
    tot, amb, multi, fn = verdict(fam_pairs[f])
    if multi:
        bad += 1
        print(f"    AMBIGUOUS {amb:5d}/{tot:5d}  {f[:90]}  {dict(sorted(multi.items())[:4])}")
print(f"  families with an ambiguous relation: {bad} of {len(fam_pairs)}")
print(f"\nscanned {scanned} dumps")
print("P28-SEEDKEY-PROBE-DONE")
