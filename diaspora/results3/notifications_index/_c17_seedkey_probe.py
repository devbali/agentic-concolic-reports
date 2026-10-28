#!/usr/bin/env python3
"""C17 (scratch, read-only) — is a nested row length a SEEDABLE dimension?

Ground-truth differential on the corpus itself: for every `len(X)` key the
runner WROTE into a base's `concolic_seeds`, was the variable the runtime
actually minted under that name equal to the (snapped) seed?  A key that is
written and never read is INERT — the dimension is not under seed control AT
THAT NAME, regardless of whether the name round-trips through the alias map.

usage: SAMPLE=600 python3 -u _c17_seedkey_probe.py
"""
import json, os, random, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_pruned_20260911_143539.txt"))
N = int(os.environ.get("SAMPLE", "600"))

files = [l.strip() for l in open(LIST) if l.strip()]
random.seed(17); files = random.sample(files, min(N, len(files)))

REMINT = "preloaded association #"
BIND = re.compile(r"\$\$\(([A-Za-z0-9_]+)\)")

cls = Counter()
honour = defaultdict(Counter)          # class -> honoured/violated
fam = defaultdict(Counter)             # variable family -> honoured/violated
upstream_ok = Counter()
examples = []

def snap013(v):   # Relation to_a/to_ary/CollectionProxy records
    v = int(v)
    return 0 if v < 0 else (3 if v > 1 else v)
def snap014(v):   # emit_includes_preloads collection
    v = int(v)
    return 0 if v < 0 else (4 if v > 1 else v)

for fp in files:
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    seeds = d.get("concolic_seeds") or {}
    svs = {}
    for sv in d.get("symbolic_vars") or ():
        n = sv.get("name")
        if n:
            svs[n] = (sv.get("value"), sv.get("note") or "")
    for k, sval in seeds.items():
        if not (k.startswith("len(") and k.endswith(")")):
            continue
        if k not in svs:
            cls["NOT-MINTED (key written, variable never created on this run)"] += 1
            continue
        val, note = svs[k]
        c = "REMINT (loaded-target early return)" if note.startswith(REMINT) \
            else "SEED-CONSULTING MINT"
        cls[c] += 1
        ok = (val == snap013(sval)) or (val == snap014(sval))
        honour[c]["HONOURED" if ok else "INERT"] += 1
        base = k[4:-1]
        f = re.sub(r"_\d+_", "_N_", base)
        fam[f]["HONOURED" if ok else "INERT"] += 1
        if c.startswith("REMINT") and not ok and len(examples) < 6:
            # try to find the upstream CollectionProxy var that really decided it
            m = re.match(r"(.*)_([a-z_]+)_row_rows$", base)
            up = None
            if m:
                ownerbase = m.group(1)
                for n2, (v2, nt2) in svs.items():
                    if not n2.startswith("len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_"):
                        continue
                    if any(b.startswith(ownerbase + "_") for b in BIND.findall(nt2)):
                        up = (n2, v2, seeds.get(n2, "<unseeded>"), nt2[:90])
            examples.append((os.path.basename(fp), k, sval, val, up))
        if c.startswith("REMINT"):
            m = re.match(r"(.*)_([a-z_]+)_row_rows$", base)
            if m:
                ownerbase = m.group(1)
                found = None
                for n2, (v2, nt2) in svs.items():
                    if not n2.startswith("len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_"):
                        continue
                    if any(b.startswith(ownerbase + "_") for b in BIND.findall(nt2)):
                        found = (n2, v2)
                if found is None:
                    upstream_ok["NO-UPSTREAM-FOUND"] += 1
                elif found[1] == val:
                    upstream_ok["UPSTREAM-MATCHES-VALUE"] += 1
                else:
                    upstream_ok["UPSTREAM-DIFFERS"] += 1

print(f"sample: {len(files)} dumps\n")
print("len(X) seed keys, by what the runtime did with the name:")
for k, v in cls.most_common():
    print(f"  {v:8d}  {k}")
print("\nhonour rate, minted keys only:")
for c in sorted(honour):
    h, i = honour[c]["HONOURED"], honour[c]["INERT"]
    print(f"  {c}: HONOURED {h}, INERT {i}  ({100.0*h/max(1,h+i):.1f} % honoured)")
print("\nREMINT keys: can the upstream CollectionProxy length be identified from the note bind?")
for k, v in upstream_ok.most_common():
    print(f"  {v:8d}  {k}")
print("\nper-family (ordinals folded), families with any INERT:")
for f in sorted(fam, key=lambda x: -fam[x]["INERT"]):
    if fam[f]["INERT"]:
        print(f"  INERT {fam[f]['INERT']:5d}  HONOURED {fam[f]['HONOURED']:5d}  {f[:100]}")
print("\nexamples of an INERT REMINT and the upstream key that really decided it:")
for e in examples:
    print(f"  {e[0]}\n     key   {e[1]}\n     seed  {e[2]}   ->  minted {e[3]}")
    print(f"     upstream {e[4]}")
print("C17-SEEDKEY-PROBE-DONE")
