#!/usr/bin/env python3
"""P23 — turn the EXACT ENUMERATOR's streamed remaining cubes into the gap +
parts files `_p23_construct.py` consumes.

Why this exists (§80.12). The checker runs with MAX_MISSING_PER_CLIQUE=1, so a
pass reports ONE witness per demand set and a round can close at most one leaf
per set however well it is constructed — P18 round 5 walked 95 of 290 demanded
leaves and only 5 sets went clean. DISCIPLINE's driver-level batching says take
EVERY remaining cube from the exact enumerator instead. `_p23_enum.py` streams
them in the `missing[]` shape; this script adds the four fields the classifier
used to add (`constrained`, `out_of_domain`, `unknown_vars`, `not_seedable`)
and the demand-set identity.

THE SET IDENTITY IS THE ENUMERATOR'S OWN CLIQUE INDEX, not a match against a
stale `_parts_*.json`. §78.6 measured what a stale parts file costs (43 % of a
batch silently scored `setmask = 0`); here the parts are BUILT from the same
census the cubes came from, so the grouping is exact by construction and the
S1 "one compatible base per set" grouping has something true to group on.

The helpers below are COPIED from `_p15_classify.py`, deliberately: that module
runs `main()` at import and importing it for a helper has twice overwritten
campaign files (§79.7, §80).
"""
import json, os, pickle, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))

JSONL = os.environ.get("P23_JSONL", os.path.join(HERE, "_p23_emit_R1.json.jsonl"))
INDEX = os.environ.get("P18_INDEX", os.path.join(HERE, "_p23_index.pkl"))
GOUT  = os.environ.get("P15_GAPS",  os.path.join(HERE, "_p23_gaps.json"))
POUT  = os.environ.get("P23_PARTS", os.path.join(HERE, "_p23_parts.json"))
MAXPS = int(os.environ.get("P23_MAX_PER_SET", "0"))     # 0 = every emitted cube
MAXTOT = int(os.environ.get("P23_MAX_TOTAL", "0"))

_FAM = [
    (r"as_api_response_\d+_row_guid",            "guid"),
    (r"^SYM_LEN_.*_rows != 0",                   "length gate (rows != 0)"),
    (r"^SYM_LEN_.*_ids != 0",                    "length gate (ids != 0)"),
    (r"_text_empty == True",                     "text (empty)"),
    (r"_text_has_mention == True",               "text (has_mention)"),
    (r"find_by_\d+_not_found",                   "find_by not_found"),
    (r"findpublic_.*_not_found",                 "findpublic not_found"),
    (r"findpublic_.*_public == True",            "public gate"),
    (r"_not_found == True",                      "evilq not_found"),
    (r"CollectionProxy_size_\d+_size",           "size gate"),
    (r"Anonymous_process_\d+ == ''",             "text (rendered)"),
    (r"assoc_profile_nsfw",                      "nsfw gate"),
    (r"Length\(SYM_PARAM_id\)",                  "param id length"),
    (r"_row_status_message_guid !=",             "guid self-compare"),
]
def family(e):
    for pat, name in _FAM:
        if re.search(pat, e):
            return name
    return "other"

_PART_FAM = [(r"_photos_", "photos"), (r"_tags_", "tags"), (r"_comments_", "comments"),
             (r"_likes_", "likes"), (r"_mentions_", "mentions"),
             (r"_participations_", "participations"),
             (r"as_api_response", "api-response"), (r"evilq_", "evilq"),
             (r"findpublic_", "findpublic"), (r"find_by_", "find_by"),
             (r"^\(assoc_", "assoc-root"), (r"SYM_PARAM_id", "param"),
             (r"Anonymous_process", "render")]
def pfam(e):
    for pat, name in _PART_FAM:
        if re.search(pat, e):
            return name
    return "other"

_ID = r"[A-Za-z_][A-Za-z0-9_]*"
_EQ = re.compile(rf"^\(\s*({_ID})\s*==\s*(.+?)\s*\)$")
_NE = re.compile(rf"^\(\s*({_ID})\s*!=\s*(.+?)\s*\)$")
_LN = re.compile(rf"^\(\s*Length\(({_ID})\)\s*<\s*(\d+)\s*\)$")

def constrained_vars(nc):
    out = set()
    for part in (nc or "").split(" AND "):
        part = part.strip()
        m = re.match(r"^Not\((.*)\)$", part, re.S)
        if m:
            part = m.group(1).strip()
        for rx in (_EQ, _NE, _LN):
            m = rx.match(part)
            if not m:
                continue
            if rx is not _LN and m.group(2).strip() == m.group(1):
                break
            out.add(m.group(1))
            break
    return out

def cube_exprs(nc):
    """Top-level conjuncts of a printed cube, with the Not() stripped."""
    out, depth, cur = [], 0, []
    toks = (nc or "").split(" AND ")
    for t in toks:
        cur.append(t)
        depth += t.count("(") - t.count(")")
        if depth <= 0:
            piece = " AND ".join(cur); cur = []; depth = 0
            p = piece.strip()
            m = re.match(r"^Not\((.*)\)$", p, re.S)
            out.append(m.group(1).strip() if m else p)
    if cur:
        out.append(" AND ".join(cur).strip())
    return out


def main():
    idx = pickle.load(open(INDEX, "rb"))
    domain = idx["domain"]
    seedable = set(idx.get("seedable") or ())
    print(f"index: {len(domain)} vars in domain, {len(seedable)} seedable, "
          f"{len(idx['dumps'])} dumps")

    by_set = defaultdict(list)
    nread = 0
    with open(JSONL) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                it = json.loads(line)
            except Exception:
                continue                       # a truncated tail from a kill
            nread += 1
            by_set[it["clique"]].append(it)
    print(f"read {nread} streamed cubes over {len(by_set)} demand sets")

    dist = Counter(len(v) for v in by_set.values())
    print("cubes per set (emitted): " +
          ", ".join(f"{k}x{n}" for k, n in sorted(dist.items())[:20]))

    gaps, parts, nsel = [], [], 0
    for si, (ci, items) in enumerate(sorted(by_set.items())):
        members = sorted({e for it in items for e in cube_exprs(it["node_constraint"])})
        parts.append({"i": ci, "width": max(it["width"] for it in items),
                      "members": members, "sat": 0, "covered": 0, "remaining": 0,
                      "leaf_groups": 0, "cubes": len(items), "forecl": 0,
                      "bound": False, "from": "_p23_enum census"})
        sel = items if not MAXPS else items[:MAXPS]
        for it in sel:
            if MAXTOT and nsel >= MAXTOT:
                break
            nsel += 1
            nc = it["node_constraint"]
            model = it.get("concrete_values") or {}
            con = constrained_vars(nc)
            oo = [k for k, val in model.items()
                  if k in con and k in domain and repr(val) not in domain[k]]
            oof = [k for k, val in model.items()
                   if k not in con and k in domain and repr(val) not in domain[k]]
            unknown = [k for k in model if k in con and k not in domain]
            unkf = [k for k in model if k not in con and k not in domain]
            noseed = sorted(v for v in con if v in model and v not in seedable)
            gaps.append({
                "id": f"e{len(gaps):06d}",
                "set": ci,
                "width": it["width"],
                "surviving": it["surviving"],
                "gates": it["gates"],
                "part_family": sorted({pfam(e) for e in members}),
                "families": sorted({family(e) for e in cube_exprs(nc)}),
                "node_constraint": nc,
                "concrete_values": model,
                "assignments": it.get("assignments"),
                "constrained": sorted(con & set(model)),
                "out_of_domain": oo,
                "out_of_domain_free": oof,
                "unknown_vars": unknown,
                "unknown_free": unkf,
                "not_seedable": noseed,
            })
    json.dump(gaps, open(GOUT, "w"))
    json.dump({"parts": parts, "totals": {"sets": len(parts), "cubes": len(gaps)}},
              open(POUT, "w"))
    print(f"wrote {len(gaps)} gaps -> {os.path.basename(GOUT)}")
    print(f"wrote {len(parts)} parts -> {os.path.basename(POUT)}")

    print("\n-- CONSTRUCTIBILITY of the batch, before any base is chosen")
    print(f"   cubes with >=1 CONSTRAINED out-of-domain value : "
          f"{sum(1 for g in gaps if g['out_of_domain'])}")
    print(f"   cubes with >=1 CONSTRAINED never-observed var  : "
          f"{sum(1 for g in gaps if g['unknown_vars'])}")
    print(f"   cubes with an UNSTEERABLE constrained variable : "
          f"{sum(1 for g in gaps if g['not_seedable'])}")
    print(f"   cubes fully constructible from observed values : "
          f"{sum(1 for g in gaps if not g['out_of_domain'] and not g['unknown_vars'])}")
    fs = Counter(f for g in gaps for f in g["families"])
    print("\n-- decision families the demanded outcomes touch (member-slots)")
    for k, n in fs.most_common():
        print(f"   {n:7d}  {k}")
    w = Counter(g["width"] for g in gaps)
    print("\n-- by set WIDTH: " + ", ".join(f"w{k}x{n}" for k, n in sorted(w.items())))
    ns = Counter(v for g in gaps for v in g["not_seedable"])
    for k, n in ns.most_common(6):
        print(f"   unsteerable x{n:<6} {k[:84]}")
    print("P23-GAPS-DONE")


main()
