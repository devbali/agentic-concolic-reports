#!/usr/bin/env python3
"""P29 — is the CONTRADICTED length gate a corpus impossibility or a
RAW-ORDINAL TARGETING defect in the constructor?

For every contradicted `(SYM_LEN_<canonical>_rows != 0)` literal of round 6:
  * find the RAW ordinal at which <canonical> was actually minted in the dump
  * read the seed the constructor wrote at THAT raw ordinal's `len(...)` key
  * classify:
      SEED-AT-RIGHT-ORDINAL-WRONG-VALUE  seed there == demanded, run disagreed
      SEED-AT-RIGHT-ORDINAL-CONTRADICTS  seed there != demanded  (constructor
                                         pinned this ordinal to the wrong value
                                         -> ORDINAL MISTARGETING)
      NO-SEED-AT-THAT-ORDINAL            constructor never wrote that key
      MULTI-ORDINAL                      canonical minted at >1 raw ordinal
"""
import json, os, re, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for
from coverage_assumptions import ALIASES

per = json.load(open(HERE + "/_p29_perkey_P26F.json"))
LENV = re.compile(r"^\(SYM_LEN_(.+)_rows != 0\)$")

cls = collections.Counter()
byvar = collections.defaultdict(collections.Counter)
examples = collections.defaultdict(list)
cache = {}
for gid, r in per.items():
    bad = [l for l in r["lits"] if l["v"] == "contradicted"
           and l["fam"] == "length gate (rows)"]
    if not bad:
        continue
    p = HERE + "/" + r["dump"]
    if p not in cache:
        d = json.load(open(p))
        ev = d["events"]
        amap = alias_map_for([(e.get("result_name"), e.get("note"))
                              for e in ev if e.get("type") == "symbolic_call"], ALIASES)
        rev = collections.defaultdict(list)
        for raw, canon in amap.items():
            rev[canon].append(raw)
        cache[p] = (rev, d.get("concolic_seeds") or {})
    rev, seeds = cache[p]
    for l in bad:
        m = LENV.match(l["e"])
        if not m:
            continue
        canon = m.group(1)
        raws = rev.get(canon, [])
        short = canon.replace("SYM_RESULT_ActiveRecord__Relation_records_", "R_") \
                     .replace("SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_", "CP_")
        demanded = l["p"]                     # True means "!=0 must hold"
        if not raws:
            c = "CANONICAL-NOT-MINTED"
        else:
            vals = {}
            for raw in raws:
                k = "len(%s_rows)" % raw
                vals[raw] = seeds.get(k, "<absent>")
            seeded_nonzero = [v for v in vals.values() if v not in ("<absent>",) and int(v) != 0]
            seeded_zero = [v for v in vals.values() if v not in ("<absent>",) and int(v) == 0]
            absent = [v for v in vals.values() if v == "<absent>"]
            want_nonzero = demanded
            if absent and not seeded_nonzero and not seeded_zero:
                c = "NO-SEED-AT-THAT-ORDINAL"
            elif want_nonzero and seeded_nonzero:
                c = "SEED-AGREES-run-still-disagreed"
            elif (not want_nonzero) and seeded_zero and not seeded_nonzero:
                c = "SEED-AGREES-run-still-disagreed"
            else:
                c = "SEED-MISTARGETED (constructor pinned this raw ordinal the other way)"
            c += "  [%d raw ord]" % len(raws)
        cls[c] += 1
        byvar[short][c] += 1
        if len(examples[c]) < 4:
            examples[c].append((gid, r["dump"], short, demanded,
                                {k: seeds.get("len(%s_rows)" % k, "<absent>") for k in raws}))

print("CONTRADICTED length-gate literals of round 6:", sum(cls.values()))
for k, n in cls.most_common():
    print("  %-70s %5d" % (k, n))
print()
print("BY VARIABLE")
for v, c in sorted(byvar.items(), key=lambda kv: -sum(kv[1].values())):
    print("  %-32s %s" % (v, dict(c)))
print()
for c, ex in examples.items():
    print("EXAMPLES", c)
    for e in ex:
        print("   ", e)
