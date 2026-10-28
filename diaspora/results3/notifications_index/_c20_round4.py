#!/usr/bin/env python3
"""C20 round 4 — the last three gap-sets, with the base chosen PER TARGET LEAF.

Rounds 2 and 3 chose one base per SET and overlaid the whole cube. That fails
on these three because the members are COUPLED THROUGH THE CALL PREFIX: seeding
`len(notifications_rows) = 1` moves the `exists?` call ordinals, so a base that
records `exists__5` stops recording it once the overlay shortens the list.

`_c20_ord5_pc.txt` measures the way out: of the 2 246 runs that record
`(exists__5 == True)`, **302 already do it with `len(notifications_rows) > 1`
FALSE** — the one-row context CAN mint ordinal 5. So the base must already
satisfy the two prefix-coupled members (the row length and the exists literal)
and the overlay may then write only the REST.

usage: python3 _c20_round4.py <cov.json> <candidate_list> [K]
"""
import json, os, re, sys, itertools, collections
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for, renamer   # noqa: E402
from coverage_assumptions import ALIASES                          # noqa: E402
from _c20_scan2 import parse                                      # noqa: E402

VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
_CANON_RE = re.compile(r"SYM_RESULT_[A-Za-z0-9_]*?_(?:notifications|aspect_memberships|"
                       r"photos|tags|aspects|services|mentions)_[0-9a-f]{8}")
_EQT = re.compile(r"^\((\w+) == (True|False)\)$")
_GTI = re.compile(r"^\((\w+) > (-?\d+)\)$")
SETS = None


def split_lits(nc):
    out = []
    for part in nc.split(" AND "):
        p, w = part.strip(), True
        if p.startswith("Not(") and p.endswith(")"):
            w, p = False, p[4:-1]
        out.append((p, w))
    return out


def _init(sets):
    global SETS
    SETS = sets


def work(path):
    try:
        evs, pcs, seeds, _v = parse(path)
    except Exception:
        return None
    amap = alias_map_for(evs, ALIASES)
    mint = set(amap.values())
    rn = renamer(amap)
    seen = {}
    for expr, taken, _s in pcs:
        seen.setdefault(fixlen(rn(expr)), set()).add(bool(taken))
    rows = []
    for si, (members, canons, hard) in enumerate(SETS):
        if not canons <= mint:
            continue
        if not all(h in seen for h in hard):
            continue
        obs = tuple((("B" if len(seen[e]) > 1 else ("T" if True in seen[e] else "F"))
                     if e in seen else "U") for e in members)
        rows.append((si, obs))
    if not rows:
        return None
    return (path, len(seeds), rows)


def main():
    cov, lst = sys.argv[1], sys.argv[2]
    K = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    miss = [m for m in json.load(open(cov))["missing"] if not m["untracked"]]
    sets, meta = [], []
    for m in miss:
        lits = split_lits(m["node_constraint"])
        members = [e for e, _w in lits]
        canons = set()
        for e in members:
            canons |= set(_CANON_RE.findall(e))
        # the PREFIX-COUPLED members the base must already carry
        hard = [e for e in members
                if "_exists__" in e or (e.endswith("_rows > 1)") and "row_actors" not in e
                                        and "mentions" not in e and "aspect_member" not in e)]
        sets.append((members, canons, hard))
        meta.append({"members": members, "witness": [w for _e, w in lits], "hard": hard})
        print(f"  set: width {len(members)} hard {len(hard)}")
    files = [l.strip() for l in open(lst) if l.strip()]
    print(f"candidates {len(files)}")
    pool_rows = collections.defaultdict(list)
    with Pool(int(os.environ.get("JOBS", "3")), initializer=_init, initargs=(sets,)) as pool:
        for r in pool.imap_unordered(work, files, chunksize=32):
            if r:
                path, ns, rows = r
                for si, obs in rows:
                    pool_rows[si].append((path, ns, obs))
    per_variant, manifest = collections.defaultdict(list), []
    for si, (members, canons, hard) in enumerate(sets):
        w = len(members)
        space = set(itertools.product(*[[True, False]] * w))
        covered = set()
        for _p, _n, obs in pool_rows[si]:
            if "U" in obs:
                continue
            covered |= set(itertools.product(*[[True, False] if c == "B" else [c == "T"]
                                               for c in obs]))
        todo = sorted(space - covered)
        print(f"  set{si}: bases {len(pool_rows[si])}  covered-here {len(covered)}  todo {len(todo)}")
        hidx = [members.index(h) for h in hard]
        for asg in todo:
            # bases whose OWN recording already matches every hard member
            cand = []
            for p, ns, obs in pool_rows[si]:
                ok = all(obs[j] in ("B", "T" if asg[j] else "F") for j in hidx)
                if not ok:
                    continue
                nm = sum(1 for j in range(w) if obs[j] in ("B", "T" if asg[j] else "F"))
                cand.append((nm, ns, p))
            cand.sort(reverse=True)
            for _nm, _ns, p in cand[:K]:
                d = json.load(open(p))
                amap = alias_map_for([(e.get("result_name"), e.get("note"))
                                      for e in d.get("events") or ()
                                      if e.get("type") == "symbolic_call"], ALIASES)
                rnm = renamer(amap)
                rev = collections.defaultdict(list)
                for o, c in (amap or {}).items():
                    rev[c].append(o)
                rev_sorted = sorted(rev, key=len, reverse=True)
                s = dict(d.get("concolic_seeds") or {})
                variant = next((v for v in VARIANTS
                                if os.path.basename(p).startswith("dump_" + v)), None)
                del d
                if variant is None:
                    continue

                def seedkeys(k):
                    dn = f"len({k[8:]})" if k.startswith("SYM_LEN_") else k
                    outs = [dn]
                    for c in rev_sorted:
                        if re.search(re.escape(c) + r"(?![0-9])", dn):
                            outs = [re.sub(re.escape(c) + r"(?![0-9])",
                                           o.replace("\\", "\\\\"), dn) for o in rev[c]]
                            break
                    return [o for o in outs if fixlen(rnm(o)) == k]

                # write ONLY the members that are not prefix-coupled; the hard
                # ones are what the base was selected for and touching them is
                # what moved the ordinal in rounds 2 and 3.
                for j, (e, want) in enumerate(zip(members, asg)):
                    if j in hidx:
                        continue
                    m = _EQT.match(e)
                    if m:
                        val = (m.group(2) == "True") if want else (m.group(2) != "True")
                        for sk in seedkeys(m.group(1)):
                            s[sk] = val
                        continue
                    m = _GTI.match(e)
                    if m:
                        rhs = int(m.group(2))
                        for sk in seedkeys(m.group(1)):
                            s[sk] = rhs + 1 if want else max(0, rhs)
                per_variant[variant].append(s)
                manifest.append({"set": si, "assignment": [bool(x) for x in asg],
                                 "base": os.path.basename(p), "variant": variant})
    for v in VARIANTS:
        json.dump(per_variant.get(v, []),
                  open(os.path.join(HERE, f"_c20_r4_seeds_{v}.json"), "w"))
    json.dump({"meta": meta, "manifest": manifest},
              open(os.path.join(HERE, "_c20_r4_manifest.json"), "w"), indent=1)
    print("per variant:", {v: len(per_variant.get(v, [])) for v in VARIANTS})
    print(f"C20-R4-BUILT {sum(len(x) for x in per_variant.values())} seeds")


if __name__ == "__main__":
    main()
