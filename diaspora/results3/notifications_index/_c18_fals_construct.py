#!/usr/bin/env python3
"""C18 — ACTIVE FALSIFICATION of the RE-MINT-IDENTITY declaration (§79 model).

The corpus census (`_c18_identity_census.py`) is a passive observation: over
130 822 runs the re-minted association length and its upstream materialize
length were recorded EQUAL 139 585 times and different 0 times.  That is
evidence, not a test — the corpus might simply never have varied the upstream.

This constructs runs that DO vary it.  For each base that mints at least one
(re-mint, upstream) pair, the base's own seed dict is replayed with EVERY
upstream `len(...CollectionProxy_records_<N>_rows)` key it feeds a re-mint
overwritten to v, for v across the mock's whole domain {0, 1, 2, 3, 4} (the
snap folds 2/3/4 onto the high point, which is the domain, not a defect).

  usage: [N_BASES=..] [VALUES=0,1,2,3,4] python3 -u _c18_fals_construct.py

writes _c18f_seeds_<variant>.json + _c18f_manifest.json  (drive: _c13_drive.sh)
"""
import json, os, random, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)

LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_c16_R2.txt"))
NB = int(os.environ.get("N_BASES", "80"))
VALUES = [int(x) for x in os.environ.get("VALUES", "0,1,2,3,4").split(",")]
PREF = "_c18f_seeds_"
MANIFEST = "_c18f_manifest.json"
VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
VRE = re.compile(r"^dump_(" + "|".join(VARIANTS) + r")_")
REMINT = re.compile(r"^preloaded association #([a-z_]+):")
BIND = re.compile(r"\$\$\(([A-Za-z0-9_]+)\)")
CPRAW = "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_"
TABLE = {"followed_tags": "tags"}


def pairs_of(d):
    """RAW (ordinal-named) (remint key, upstream key) pairs of one dump."""
    svs = {sv.get("name"): sv for sv in (d.get("symbolic_vars") or ()) if sv.get("name")}
    cps = [(n, sv) for n, sv in svs.items() if n.startswith(CPRAW)]
    out = []
    for n, sv in svs.items():
        m = REMINT.match(sv.get("note") or "")
        if not (m and n.startswith("len(")):
            continue
        assoc = m.group(1); base = n[4:-1]; tail = f"_{assoc}_row_rows"
        if not base.endswith(tail):
            continue
        owner = base[:-len(tail)]
        for n2, sv2 in cps:
            if any(b.startswith(owner) for b in BIND.findall(sv2.get("note") or "")):
                # the raw upstream name carries no table, so the owner bind is
                # the whole test; keep every candidate and let the drive show
                # which one moves.
                out.append((n, n2, sv.get("value"), sv2.get("value"), assoc))
    return out


def main():
    files = [l.strip() for l in open(LIST) if l.strip()]
    random.seed(18); random.shuffle(files)
    cand = defaultdict(list)          # variant -> [(fp, pairs, seeds)]
    scanned = 0
    LIMIT = int(os.environ.get("SCAN", "12000"))
    for fp in files[:LIMIT]:
        m = VRE.match(os.path.basename(fp))
        if not m:
            continue
        v = m.group(1)
        try:
            d = json.load(open(fp))
        except Exception:
            continue
        scanned += 1
        if d.get("error"):
            continue
        ps = pairs_of(d)
        if not ps:
            continue
        seeds = {k: x for k, x in (d.get("concolic_seeds") or {}).items()
                 if not k.startswith("__")}
        if not seeds:
            continue
        cand[v].append((fp, ps, seeds))
    # QUOTA per association family, so the rarer chains (photos,
    # aspect_memberships) are exercised as hard as `services`.
    QUOTA = int(os.environ.get("QUOTA", "16"))
    got = Counter(); byvar = defaultdict(list); chosen = set()
    order = ["aspect_memberships", "photos", "followed_tags", "aspects", "services"]
    for assoc in order:
        pos = {v: 0 for v in VARIANTS}
        while got[assoc] < QUOTA:
            moved = False
            for v in VARIANTS:                      # ROUND-ROBIN over variants
                lst = cand[v]
                while pos[v] < len(lst):
                    fp, ps, seeds = lst[pos[v]]; pos[v] += 1
                    if fp in chosen or assoc not in {p[4] for p in ps}:
                        continue
                    chosen.add(fp); byvar[v].append((fp, ps, seeds))
                    for a in {p[4] for p in ps}:
                        got[a] += 1
                    moved = True
                    break
                if got[assoc] >= QUOTA:
                    break
            if not moved:
                break
    print("bases per assoc after quota fill:", dict(got))
    per_variant, manifest = defaultdict(list), []
    stat = Counter()
    for v in VARIANTS:
        for fp, ps, base_seeds in byvar[v]:
            ups = sorted({p[1] for p in ps})
            for val in VALUES:
                s = dict(base_seeds)
                for k in ups:
                    s[k] = val
                gid = f"f{len(manifest):05d}"
                s["__c13gap__"] = gid
                per_variant[v].append(s)
                manifest.append({
                    "gap": gid, "cube": gid, "set": 0, "group": 0,
                    "width": len(ups), "set_capped": False, "variant": v,
                    "reachable": True, "seed_set": "A",
                    "seed_file": PREF + v + ".json",
                    "seed_index": len(per_variant[v]) - 1,
                    "base": os.path.basename(fp), "base_rank": 0,
                    "value": val, "upstream_keys": ups,
                    "pairs": [{"remint": p[0], "upstream": p[1],
                               "base_remint_val": p[2], "base_up_val": p[3],
                               "assoc": p[4]} for p in ps],
                })
                stat[f"{v}:{val}"] += 1
    for v in VARIANTS:
        json.dump(per_variant.get(v, []), open(os.path.join(HERE, f"{PREF}{v}.json"), "w"))
    json.dump(manifest, open(os.path.join(HERE, MANIFEST), "w"))
    print(f"bases scanned {scanned}; bases used "
          f"{ {v: len(byvar[v]) for v in VARIANTS} }")
    print(f"seeds: {len(manifest)}  over values {VALUES}")
    for k in sorted(stat):
        print(f"   {stat[k]:5d}  {k}")
    print("C18-FALS-CONSTRUCT-DONE")


if __name__ == "__main__":
    main()
