#!/usr/bin/env python3
"""C25 step 1 — the MINIMAL conditioning set C, with NO width cap and no budget.

For each of the four blocking sets' WITNESS leaves (read from the C24R2 pass
checkpoint), and for each literal `d` of the leaf, search EXHAUSTIVELY for the
minimum-cardinality subset C of the leaf's other literals with

    A(C) > 0   (some run of the corpus matches every literal of C)
    B(C, d) = 0 (no run matching C evaluates d at all)

twice:
  * PREFIX   — C drawn only from literals fixed EARLIER in the walk (this is
               what §16f may actually use: `C subset-of acc`);
  * ANY      — C drawn from every other literal of the leaf (an upper bound on
               what any prefix-restricted rule could reach).

"Matches" is §16b/§16e's per-literal reading: a run matches (e, o) iff it
recorded e with outcome o at least once, so a run recording BOTH ways matches
either literal.  A and B can therefore only be OVERSTATED and a B = 0 verdict
stays conservative.

  usage: DUMP_LIST=.. CKPT=.. OUT=.. [WORKERS=2] python3 -u _c25_mincond.py
"""
import itertools, json, os, pickle, re, sys, time
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for            # noqa: E402
import coverage_report as CR                                     # noqa: E402
from coverage_assumptions import ALIASES                         # noqa: E402

CKPT = os.environ.get("CKPT", os.path.join(HERE, "_cov_c24_C24R2.ckpt.jsonl"))
LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_c24_R2.txt"))
OUT = os.environ.get("OUT", os.path.join(HERE, "_c25_mincond.json"))
BITS = os.environ.get("BITS", os.path.join(HERE, "_c25_mincond_bits.pkl"))
WORKERS = int(os.environ.get("WORKERS", "2"))

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s

# ---------------------------------------------------------------- the leaves
f = open(CKPT); f.readline()
leaves = []
for line in f:
    r = json.loads(line); v = r.get("v") or {}
    for combo in (v.get("combos") or []):
        leaves.append({"k": r["k"], "lits": [(e, bool(o)) for e, o in combo],
                       "subconj": v.get("subconj") or [],
                       "conj": v.get("conj") or []})
f.close()
print(f"witness leaves: {len(leaves)}", flush=True)
EXPRS = sorted({e for lf in leaves for e, _ in lf["lits"]})
EIDX = {e: i for i, e in enumerate(EXPRS)}
print(f"expr universe: {len(EXPRS)}", flush=True)
for e in EXPRS:
    print(f"   e{EIDX[e]:02d} {e}", flush=True)

FILES = [l.strip() for l in open(LIST) if l.strip()]
N = len(FILES)
print(f"corpus: {N} dumps from {os.path.basename(LIST)}", flush=True)

# ------------------------------------------------------------------ the scan
CHUNK = 8 * 500          # byte-aligned


def scan(args):
    lo, hi = args
    n = hi - lo; nb = (n + 7) // 8
    T = [bytearray(nb) for _ in EXPRS]; F = [bytearray(nb) for _ in EXPRS]
    for i in range(lo, hi):
        p = FILES[i]
        try:
            d = json.load(open(p))
        except Exception:
            continue
        ev = d.get("events") or ()
        alias_map_for([(e.get("result_name"), e.get("note"))
                       for e in ev if e.get("type") == "symbolic_call"], ALIASES)
        CR.canonicalize_ordinals(d)
        li = i - lo; by, b = li >> 3, 1 << (li & 7)
        for e in d.get("events") or ():
            if e.get("type") != "path_condition":
                continue
            j = EIDX.get(fixlen(str(e.get("expr", ""))))
            if j is None:
                continue
            (T if e.get("taken") else F)[j][by] |= b
        del d
    return lo, n, [bytes(x) for x in T], [bytes(x) for x in F]


if os.path.exists(BITS) and os.environ.get("REUSE_BITS") == "1":
    st = pickle.load(open(BITS, "rb"))
    assert st["exprs"] == EXPRS and st["n"] == N, "bits do not match this universe"
    TB, FB = st["T"], st["F"]
    print("reused bitsets", flush=True)
else:
    ranges = [(lo, min(lo + CHUNK, N)) for lo in range(0, N, CHUNK)]
    TBa = [bytearray((N + 7) // 8) for _ in EXPRS]
    FBa = [bytearray((N + 7) // 8) for _ in EXPRS]
    t0 = time.time(); done = 0
    with Pool(WORKERS) as pool:
        for lo, n, Tc, Fc in pool.imap_unordered(scan, ranges, chunksize=1):
            off = lo >> 3; nb = (n + 7) // 8
            for j in range(len(EXPRS)):
                tc, fc = Tc[j], Fc[j]
                for k in range(nb):
                    if tc[k]:
                        TBa[j][off + k] |= tc[k]
                    if fc[k]:
                        FBa[j][off + k] |= fc[k]
            done += n
            if done % 20000 < CHUNK:
                print(f"  {done}/{N}  {time.time()-t0:.0f}s", flush=True)
    ti = lambda x: int.from_bytes(bytes(x), "little")
    TB = [ti(x) for x in TBa]; FB = [ti(x) for x in FBa]
    print(f"scan done in {time.time()-t0:.0f}s", flush=True)
    pickle.dump({"exprs": EXPRS, "n": N, "T": TB, "F": FB}, open(BITS, "wb"), 4)

EB = [TB[j] | FB[j] for j in range(len(EXPRS))]
ALL = (1 << N) - 1
for e in EXPRS:
    j = EIDX[e]
    print(f"   e{j:02d} eval={EB[j].bit_count():7d} T={TB[j].bit_count():7d} "
          f"F={FB[j].bit_count():7d}  {e}", flush=True)

mask = lambda lit: (TB if lit[1] else FB)[EIDX[lit[0]]]


def minimal(cands, d):
    """exhaustive, minimum-cardinality C over `cands` with A>0 and B(C,d)=0."""
    jd = EIDX[d]
    if not (ALL & EB[jd]):
        return ([], N, 0)                    # never evaluated anywhere
    for r in range(0, len(cands) + 1):
        for sub in itertools.combinations(cands, r):
            m = ALL
            for lit in sub:
                m &= mask(lit)
                if not m:
                    break
            if not m:
                continue
            a = m.bit_count()
            b = (m & EB[jd]).bit_count()
            if a and b == 0:
                return (list(sub), a, b)
    return None


out = []
for li, lf in enumerate(leaves):
    lits = lf["lits"]
    print(f"\n=== LEAF {li}  key {lf['k']}  width {len(lits)} ===", flush=True)
    rec = {"leaf": li, "key": lf["k"], "width": len(lits),
           "lits": [[e, o] for e, o in lits], "members": []}
    for pos, (e, o) in enumerate(lits):
        jd = EIDX[e]
        prefix = lits[:pos]
        others = [x for x in lits if x[0] != e]
        # A/B under the FULL prefix and the FULL rest
        def ab(sub):
            m = ALL
            for lit in sub:
                m &= mask(lit)
            return m.bit_count(), (m & EB[jd]).bit_count()
        apre, bpre = ab(prefix)
        aoth, both = ab(others)
        mp = minimal(prefix, e)
        mo = minimal(others, e)
        r = {"pos": pos, "expr": e, "outcome": o,
             "evaluated_in_corpus": EB[jd].bit_count(),
             "A_full_prefix": apre, "B_full_prefix": bpre,
             "A_full_others": aoth, "B_full_others": both,
             "min_prefix": None if mp is None else
                           {"C": [[x, y] for x, y in mp[0]], "size": len(mp[0]), "A": mp[1]},
             "min_any": None if mo is None else
                        {"C": [[x, y] for x, y in mo[0]], "size": len(mo[0]), "A": mo[1]}}
        rec["members"].append(r)
        tag = "NEVER-EVAL-anywhere" if r["evaluated_in_corpus"] == 0 else ""
        print(f"  pos{pos:2d} {'T' if o else 'F'} eval={r['evaluated_in_corpus']:7d} "
              f"A(pre)={apre:7d} B(pre)={bpre:7d} A(oth)={aoth:7d} B(oth)={both:7d} "
              f"minPREFIX={'-' if mp is None else len(mp[0])} "
              f"minANY={'-' if mo is None else len(mo[0])} {tag}", flush=True)
        print(f"        {e}", flush=True)
        if mp is not None and mp[0]:
            print(f"        minPREFIX |C|={len(mp[0])} A={mp[1]}", flush=True)
            for x, y in mp[0]:
                print(f"            {'T' if y else 'F'}  {x}", flush=True)
        if mo is not None and mo[0]:
            print(f"        minANY    |C|={len(mo[0])} A={mo[1]}", flush=True)
            for x, y in mo[0]:
                print(f"            {'T' if y else 'F'}  {x}", flush=True)
    out.append(rec)

json.dump(out, open(OUT, "w"), indent=1)
print("\nC25-MINCOND-DONE", flush=True)
