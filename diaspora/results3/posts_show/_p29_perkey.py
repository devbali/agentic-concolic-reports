#!/usr/bin/env python3
"""P29 steps 1-3 — the FULL per-key record of round 6 (P26F), not just the
first failing literal: every literal of every driven gap, its verdict, and
(for a contradicted/never-evaluated one) what the dump did instead.

Reuses _p15_explain.py's join and literal parser verbatim (copied, not
imported — §80.14's rule about import-time main()).
"""
import glob, hashlib, json, os, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer
from coverage_assumptions import ALIASES

TAG = os.environ.get("P15_TAG", "P26F")
SET = os.environ.get("P15_SET", "P26F")
GAPS = os.environ.get("P15_GAPS", HERE + "/_p26_gaps_P26F.json")
MAN = os.environ.get("P15_MANIFEST", HERE + "/_p15_manifest_P26F.json")
OUT = os.environ.get("P29_OUT", HERE + "/_p29_perkey_P26F.json")

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s


def literals(nc):
    out, depth, cur = [], 0, []
    i, n = 0, len(nc or "")
    while i < n:
        c = nc[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        if depth == 0 and nc.startswith(" AND ", i):
            out.append("".join(cur)); cur = []; i += 5; continue
        cur.append(c); i += 1
    if cur:
        out.append("".join(cur))
    res = []
    for t in out:
        t = t.strip()
        if not t:
            continue
        pol = True
        while t.startswith("Not(") and t.endswith(")"):
            t = t[4:-1].strip(); pol = not pol
        res.append((t, pol))
    return res


_FAM = [(r"as_api_response_\d+_row_guid", "guid"),
        (r"^\(SYM_LEN_.*_rows != 0\)$", "length gate (rows)"),
        (r"^\(SYM_LEN_.*_ids != 0\)$", "length gate (ids)"),
        (r"_text_empty == True", "text (empty)"),
        (r"_text_has_mention == True", "text (has_mention)"),
        (r"find_by_\d+_not_found", "find_by not_found"),
        (r"findpublic_.*_not_found", "findpublic not_found"),
        (r"findpublic_.*_public == True", "public gate"),
        (r"_not_found == True", "evilq not_found"),
        (r"CollectionProxy_size_\d+_size", "size gate"),
        (r"Anonymous_process_\d+ == ''", "text (rendered)"),
        (r"assoc_profile_nsfw", "nsfw gate"),
        (r"Length\(SYM_PARAM_id\)", "param id length"),
        (r"_row_status_message_guid !=", "guid self-compare"),
        (r"_row_pending", "pending gate"),
        (r"_row_public", "public row gate")]


def family(e):
    for pat, name in _FAM:
        if re.search(pat, e):
            return name
    return "other"


def sdig(d):
    return hashlib.blake2b(json.dumps(d, sort_keys=True, separators=(",", ":")).encode(),
                           digest_size=16).hexdigest()


def main():
    gaps = {g["id"]: g for g in json.load(open(GAPS))}
    man = [m for m in json.load(open(MAN)) if m["seed_set"] == SET]
    by_dig = defaultdict(list); sbf = {}
    for m in man:
        f = m["seed_file"]
        if f not in sbf:
            sbf[f] = json.load(open(os.path.join(HERE, f)))
        by_dig[sdig(sbf[f][m["seed_index"]])].append((m["gap"], sbf[f][m["seed_index"]]))
    del sbf
    lits = {gid: literals(g["node_constraint"]) for gid, g in gaps.items()}
    files = sorted(glob.glob(os.path.join(HERE, f"dump_*{TAG}*.json")))
    print("dumps", len(files), "gaps", len(gaps), flush=True)
    rec = {}
    for p in files:
        try:
            d = json.load(open(p))
        except Exception:
            continue
        cs = d.get("concolic_seeds") or {}
        hit = by_dig.get(sdig(cs))
        if not hit:
            continue
        ev = d.get("events") or ()
        amap = alias_map_for([(e.get("result_name"), e.get("note"))
                              for e in ev if e.get("type") == "symbolic_call"], ALIASES)
        rn = renamer(amap)
        taken = defaultdict(set)
        for e in ev:
            if e.get("type") == "path_condition":
                taken[fixlen(rn(str(e.get("expr", ""))))].add(bool(e.get("taken")))
        minted = set()
        for e in ev:
            if e.get("type") == "symbolic_call":
                r = e.get("result_name")
                if r:
                    minted.add(amap.get(r, r))
        seedkeys = set(fixlen(rn(k)) for k in cs)
        for gid, sd in hit:
            if gid in rec and rec[gid]["walked"]:
                continue
            rows = []
            for expr, pol in lits[gid]:
                t = taken.get(expr)
                v = ("never_evaluated" if t is None
                     else "honoured" if pol in t else "contradicted")
                rows.append({"e": expr, "p": pol, "v": v,
                             "took": sorted(t) if t else None,
                             "fam": family(expr)})
            rec[gid] = {"dump": os.path.basename(p),
                        "walked": all(r["v"] == "honoured" for r in rows),
                        "lits": rows,
                        "minted": sorted(minted),
                        "seedkeys": sorted(seedkeys),
                        "taken": {k: sorted(v) for k, v in taken.items()}}
        del d
    json.dump(rec, open(OUT, "w"))
    print("wrote", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1e6))
    print("gaps recorded", len(rec), "walked",
          sum(1 for r in rec.values() if r["walked"]))
    print("P29-PERKEY-DONE")


main()
