#!/usr/bin/env python3
"""Size the UNEVALUATED class: is it CONJUNCTION foreclosure?

A constructed seed fixed every gate and every member, the gates were honoured,
and yet some member was never reached. That is neither a driving failure nor
impossibility — the candidate explanation is a foreclosure that depends on more
than one gate AT ONCE, which §16b's pairwise inference cannot see.

For each UNEVALUATED combination this reports the member(s) never reached and
the gate conjunction they were demanded under; groups by (member, conjunction);
and applies §16b's own "never" test to each group over the WHOLE corpus:

    a (member d, gate conjunction P) is a CONJUNCTION FORECLOSURE iff
    some run matches P, and NO run that matches P evaluates d.

`matches P` = the run evaluated every gate of P with P's outcome (the same
convention the leaf-group covering test uses). A group where runs match P and
some of them DO evaluate d is not a foreclosure at all — it goes back to the
drive, with that run as the base.

usage: PLAN=_construct_CT4_plan.json REPORT=_construct_report.json \
       REM=_remaining_s3post.jsonl REM_NOW=_remaining_s4post.jsonl \
       DUMP_LIST=<pruned> python3 -u _conj_forecl.py 'dump_*CT4*.json'
"""
import glob, json, os, re, sys, time
from collections import defaultdict, Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals  # noqa: E402

_UNLEN = re.compile(r"len\(([^()]+)\)")
PAT = sys.argv[1] if len(sys.argv) > 1 else "dump_*CT4*.json"
PLAN = os.environ.get("PLAN", "_construct_CT4_plan.json")
REPORT = os.environ.get("REPORT", "_construct_report.json")
REM = os.environ.get("REM", "_remaining_s3post.jsonl")
REM_NOW = os.environ.get("REM_NOW", "_remaining_s4post.jsonl")


def pcs_of(d):
    canonicalize_ordinals(d)
    out = defaultdict(set)
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            ex = e["expr"]; tk = bool(e.get("taken"))
            out[ex].add(tk)
            ex2 = _UNLEN.sub(r"SYM_LEN_\1", ex)
            if ex2 != ex:
                out[ex2].add(tk)
    return out


# -- 1. recover combo index -> gate conjunction, exactly as the constructor did
rows = [json.loads(l) for l in open(os.path.join(HERE, REM))]
combos = defaultdict(list)
for r in rows:
    combos[tuple(sorted((r.get("pre") or {}).items()))].append(r)
pre_of = {}
for ci, (pre, rs) in enumerate(sorted(combos.items(), key=lambda kv: -len(kv[1])), 1):
    pre_of[ci] = dict(pre)
plan = json.load(open(os.path.join(HERE, PLAN)))
demanded = {}
for p in plan:
    if p.get("status") == "CONSTRUCTED":
        demanded.setdefault(p["combo"], {}).update(p["demanded"])
rep = json.load(open(os.path.join(HERE, REPORT)))
unev = [int(c) for c, v in rep["per_combo"].items() if v == "UNEVALUATED"]
print(f"UNEVALUATED combinations to explain: {len(unev)} of {len(rep['per_combo'])}")

# -- 2. what the replay actually walked, per combination
files = sorted(glob.glob(os.path.join(HERE, PAT)))
print(f"replay dumps: {len(files)}")
seen_expr = defaultdict(set)          # combo -> exprs evaluated by ANY of its runs
gate_ok = defaultdict(lambda: defaultdict(int))
runs_of = Counter()
for fp in files:
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    c = (d.get("concolic_seeds") or {}).get("__ctcombo__")
    if c is None or c not in demanded:
        continue
    runs_of[c] += 1
    p = pcs_of(d)
    seen_expr[c] |= set(p)
    for g, w in pre_of.get(c, {}).items():
        if g in p and w in p[g]:
            gate_ok[c][g] += 1
    del d

pairs = defaultdict(list)             # (member, conjunction) -> [combos]
gates_honoured = []
for c in unev:
    pre = pre_of.get(c, {})
    miss = [e for e in demanded[c] if e not in seen_expr[c]]
    if not miss:
        continue
    hon = sum(1 for g in pre if gate_ok[c].get(g)) 
    gates_honoured.append((hon, len(pre)))
    key = tuple(sorted(pre.items()))
    for m in miss:
        pairs[(m, key)].append(c)
print(f"distinct (unevaluated member, gate conjunction) pairs: {len(pairs)}")
if gates_honoured:
    full = sum(1 for h, n in gates_honoured if h == n)
    print(f"combinations whose gates were ALL honoured in some run: "
          f"{full} of {len(gates_honoured)}")
mem_counts = Counter(m for (m, _k) in pairs)
print(f"distinct unevaluated MEMBERS: {len(mem_counts)}")
for m, n in mem_counts.most_common(8):
    print(f"   {n:4d} conjunctions   {m[-100:]}")

# -- 3. §16b's own "never" test, over the WHOLE corpus, per pair
need = set()
for (m, key) in pairs:
    need.add(m)
    for g, _w in key:
        need.add(g)
print(f"\nindexing the corpus for {len(need)} expressions "
      f"(the members + every gate of every conjunction)")
DL = os.environ.get("DUMP_LIST")
dumps = [l.strip() for l in open(DL)] if DL else sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
pol = {}                                   # (expr, outcome) -> bitmask
ev = {}                                    # expr -> bitmask
t0 = time.time()
for i, fp in enumerate(dumps):
    if i and i % 25000 == 0:
        print(f"   [{i}/{len(dumps)}] {time.time()-t0:.0f}s", flush=True)
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    b = 1 << i
    p = pcs_of(d)
    for e in need & set(p):
        ev[e] = ev.get(e, 0) | b
        for o in p[e]:
            pol[(e, o)] = pol.get((e, o), 0) | b
    del d
print(f"   indexed {len(dumps)} dumps in {time.time()-t0:.0f}s")

forecl, notforecl, nomatch = [], [], []
for (m, key), cs in pairs.items():
    match = None
    for g, w in key:
        mm = pol.get((g, bool(w)), 0)
        match = mm if match is None else (match & mm)
        if not match:
            break
    n_match = bin(match).count("1") if match else 0
    if not n_match:
        nomatch.append((m, key, cs))
        continue
    both = match & ev.get(m, 0)
    n_both = bin(both).count("1")
    (forecl if n_both == 0 else notforecl).append((m, key, cs, n_match, n_both))

print("\n=== §16b's 'never' test, applied to the CONJUNCTION ===")
print(f"  CONJUNCTION FORECLOSURE  (runs match the gates, none evaluates the "
      f"member): {len(forecl)}")
print(f"  REACHABLE                (some matching run DOES evaluate it -> back "
      f"to the drive): {len(notforecl)}")
print(f"  NO RUN MATCHES the conjunction at all (undecidable by this test): "
      f"{len(nomatch)}")
if notforecl:
    print("\n  the REACHABLE ones, biggest first (matching runs / of which evaluate the member):")
    for m, key, cs, nm, nb in sorted(notforecl, key=lambda t: -t[4])[:8]:
        print(f"    {nb:6d}/{nm:6d}  combos={len(cs)}  {m[-88:]}")

# -- 4. how many of the CURRENT remaining cubes do the foreclosures explain?
now = [json.loads(l) for l in open(os.path.join(HERE, REM_NOW))]
fset = set()
for m, key, cs, nm, nb in forecl:
    fset.add((m, key))
expl = 0
for r in now:
    pre = tuple(sorted((r.get("pre") or {}).items()))
    asg = r.get("asg") or {}
    if any((m, pre) in fset for m in asg):
        expl += 1
print(f"\n=== COVERAGE OF THE CURRENT RESIDUE ===")
print(f"  remaining cubes now: {len(now)}")
print(f"  explained by a corpus-consistent CONJUNCTION FORECLOSURE: {expl}"
      f"  ({100.0*expl/max(1,len(now)):.1f} %)")
def _ser(lst, withn=True):
    out = []
    for t in lst:
        if withn:
            m, key, cs, nm, nb = t
            out.append({"member": m, "pre": [list(x) for x in key],
                        "combos": cs, "matching_runs": nm, "of_which_evaluate": nb})
        else:
            m, key, cs = t
            out.append({"member": m, "pre": [list(x) for x in key], "combos": cs})
    return out


json.dump({"foreclosure": _ser(forecl), "reachable": _ser(notforecl),
           "no_match": _ser(nomatch, False)},
          open(os.path.join(HERE, "_conj_pairs.json"), "w"), indent=1)
print("wrote _conj_pairs.json")
json.dump({"unevaluated_combos": len(unev), "pairs": len(pairs),
           "conjunction_foreclosures": len(forecl), "reachable": len(notforecl),
           "no_match": len(nomatch), "remaining_now": len(now),
           "remaining_explained": expl,
           "members": mem_counts.most_common(40)},
          open(os.path.join(HERE, "_conj_forecl.json"), "w"), indent=1)
print("\nwrote _conj_forecl.json")
