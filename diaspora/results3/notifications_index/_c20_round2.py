#!/usr/bin/env python3
"""C20 round 2 — drive EVERY uncovered leaf of the 9 remaining gap-sets, not
just the checker's one witness.

C20R1 closed 2 sets and REPLACED the witness leaf of 8 more: the driven cubes
were covered and the set simply named its next uncovered leaf. Driving one
witness per set per round is a backlog, so this round enumerates, per set, the
assignments over the set's OWN members that the corpus has not covered, and
constructs each of them.

  members(S)  = the literals of the checker's witness cube (a leaf is a full
                assignment over the leaf's members, so the witness names them)
  covered(S)  = the cubes real runs contribute: a run that evaluated every
                member contributes its assignment, free on any member it
                recorded BOTH ways (coverage.py step 6's blocking clause)
  target(S)   = every assignment not covered

Bases are chosen exactly as `_c20_exists_bases.py` does — the base must MINT
every alias canonical the set names (else the overlaid seed keys are inert)
and, when the set names an `exists__N` ordinal, must RECORD that ordinal.

usage: python3 _c20_round2.py <cov.json> <dump_list> [K_BASES]
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
_EXORD = re.compile(r"SYM_RESULT_ActiveRecord__FinderMethods_exists__(\d+)_exists")
_EQT = re.compile(r"^\((\w+) == (True|False)\)$")
_GTI = re.compile(r"^\((\w+) > (-?\d+)\)$")
_ID = r"[A-Za-z_][A-Za-z0-9_]*"
_SELF = re.compile(rf"^\(({_ID}) == \1__prior\)$")
_CMP2 = re.compile(rf"^\(({_ID}) (==|!=) ({_ID})\)$")
_BOOLRHS = ("True", "False")
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
    """-> (path, nseeds, [(set_index, covered-cube-or-None, ok_base)])"""
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
    out = []
    for si, (members, canons, exlit) in enumerate(SETS):
        # covered: the run evaluated EVERY member
        if all(e in seen for e in members):
            cube = tuple(("B" if len(seen[e]) > 1 else ("T" if True in seen[e] else "F"))
                         for e in members)
        else:
            cube = None
        nm = sum(1 for e in members if e in seen)
        okbase = canons <= mint and (exlit is None or exlit in seen)
        if os.environ.get("REQUIRE_ALL_MEMBERS") and nm < len(members):
            okbase = False        # C20 round 3: the base must CO-EVALUATE the
                                  # whole set, or the overlay is writing seeds
                                  # on decisions the run never reaches
        if cube is None and not okbase:
            continue
        nmatch = sum(1 for e in members if e in seen)
        out.append((si, cube, okbase, nmatch))
    if not out:
        return None
    return (path, len(seeds), out)


def expand(cube):
    """a cube with B (both) entries -> the assignments it covers"""
    slots = [[True, False] if c == "B" else [c == "T"] for c in cube]
    return set(itertools.product(*slots))


def main():
    cov, lst = sys.argv[1], sys.argv[2]
    K = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    miss = [m for m in json.load(open(cov))["missing"] if not m["untracked"]]
    sets, meta = [], []
    for i, m in enumerate(miss):
        lits = split_lits(m["node_constraint"])
        members = [e for e, _w in lits]
        canons = set()
        for e in members:
            canons |= set(_CANON_RE.findall(e))
        exlit = next((e for e in members if "_exists__" in e), None)
        sets.append((members, canons, exlit))
        meta.append({"set": i, "width": len(members), "members": members,
                     "witness": [w for _e, w in lits]})
        print(f"  set{i}: width {len(members)}  canonicals {len(canons)}  "
              f"exists-literal {'yes' if exlit else 'no'}")
    files = open(lst).read().split()
    covered = collections.defaultdict(set)
    bases = collections.defaultdict(list)
    with Pool(int(os.environ.get("JOBS", "3")), initializer=_init, initargs=(sets,)) as pool:
        for n, r in enumerate(pool.imap_unordered(work, files, chunksize=64)):
            if r:
                path, ns, rows = r
                for si, cube, okbase, nmatch in rows:
                    if cube is not None:
                        covered[si] |= expand(cube)
                    if okbase:
                        bases[si].append({"path": path, "nseeds": ns, "match": nmatch})
            if (n + 1) % 20000 == 0:
                print(f"  [{n+1}/{len(files)}]", flush=True)

    per_variant, manifest = collections.defaultdict(list), []
    PREF = os.environ.get("R2_PREF", "_c20_r2_seeds_")
    MANI = os.environ.get("R2_MANIFEST", "_c20_r2_manifest.json")
    for si, (members, canons, exlit) in enumerate(sets):
        w = len(members)
        allasg = set(itertools.product(*[[True, False]] * w)) if w <= 12 else None
        if allasg is None:
            # width 13: target only the checker's witness plus its 1-flip
            # neighbours, which is what a round can actually drive
            wit = tuple(meta[si]["witness"])
            allasg = {wit} | {wit[:j] + (not wit[j],) + wit[j+1:] for j in range(w)}
        todo = sorted(allasg - covered[si])
        meta[si].update(covered=len(covered[si]), space=len(allasg), todo=len(todo))
        print(f"  set{si}: space {len(allasg)}  covered {len(covered[si])}  "
              f"TO DRIVE {len(todo)}  bases {len(bases[si])}")
        rows = sorted(bases[si], key=lambda r: (-r["match"], -r["nseeds"]))[:K * 3]
        for asg in todo:
            for r in rows[:K]:
                p = r["path"]
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

                unres = 0
                protect = []
                for e, want in zip(members, asg):
                    m = _SELF.match(e)
                    if m:
                        for sk in seedkeys(m.group(1)) or []:
                            s.pop(sk, None)
                        protect.append(m.group(1))
                        continue
                    m = _EQT.match(e)
                    if m:
                        val = (m.group(2) == "True") if want else (m.group(2) != "True")
                        ks = seedkeys(m.group(1))
                        unres += 0 if ks else 1
                        for sk in ks:
                            s[sk] = val
                        continue
                    m = _GTI.match(e)
                    if m:
                        rhs = int(m.group(2))
                        ks = seedkeys(m.group(1))
                        unres += 0 if ks else 1
                        for sk in ks:
                            s[sk] = rhs + 1 if want else max(0, rhs)
                        continue
                    m = _CMP2.match(e)
                    if m and m.group(3) not in _BOOLRHS:
                        continue          # var-var: carried by the base (§33.6)
                    unres += 1
                for v in protect:
                    for sk in seedkeys(v) or []:
                        s.pop(sk, None)
                per_variant[variant].append(s)
                manifest.append({"set": si, "assignment": [bool(x) for x in asg],
                                 "base": os.path.basename(p), "variant": variant,
                                 "unresolved": unres})
    for v in VARIANTS:
        json.dump(per_variant.get(v, []),
                  open(os.path.join(HERE, f"{PREF}{v}.json"), "w"))
    json.dump({"meta": meta, "manifest": manifest},
              open(os.path.join(HERE, MANI), "w"), indent=1)
    print("per variant:", {v: len(per_variant.get(v, [])) for v in VARIANTS})
    print(f"C20-R2-BUILT {sum(len(x) for x in per_variant.values())} seeds")


if __name__ == "__main__":
    main()
