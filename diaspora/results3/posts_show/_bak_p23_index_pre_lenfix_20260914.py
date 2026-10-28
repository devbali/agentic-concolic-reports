#!/usr/bin/env python3
"""P18 — corpus index, SUPERSET of `_p15_index.py`, plus the two things round
P18 needs and P15 never measured (§80):

  (1) LENGTH STATE per dump. For every `SYM_LEN_<list>_rows` checker name, a
      pair of bitmasks: the lists this run EVALUATED AS EMPTY and the lists it
      evaluated as NON-EMPTY. From these the NECESSITY TABLE below is derived.

  (2) THE API BINDING per dump. `SYM_RESULT_ActsAsApi__Collection_as_api_response_<n>`
      is ORDINAL-keyed, not statement-keyed (the `AliasAssumption` covers only
      the AR record readers), so WHICH collection ordinal n projects is a
      property of the RUN, not of the name. Measured: it is the `records`/
      `to_ary` call immediately preceding that api call in the run's own event
      stream. `bind[i] = {ordinal: canonical}` records it, and it is what makes
      a row-read member's governing length COMPUTABLE for a given base.

Derived and written into the same pickle:

  necess[e] = {"nz": [L...], "z": [L...]}   — for demand-universe expression e,
      the length variables that MUST be non-empty (resp. empty) for e to be
      evaluated at all. Read off the corpus exactly as §16b reads a
      foreclosure: `e` was never once evaluated in a run where L had the other
      state, over at least MIN_RUNS runs that had that state. It is the same
      epistemics one value-level down, and it is computed HERE, at the driver —
      nothing in `src/` is touched.

  bindstat[(n, field, canonical)] = {(gov_nonempty, field_read): count}
      the per-binding version of the same question for the api row reads, whose
      governor is a DISJUNCTION over bindings and therefore invisible to the
      per-variable necessity test.
"""
import json, os, pickle, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer   # noqa: E402
from coverage_assumptions import ALIASES                          # noqa: E402

_LEN_RE = re.compile(r"len\(([^()]+)\)")
VARIANTS = ("auth_html", "anon_html", "auth_json", "anon_json")
OUT = os.environ.get("P18_INDEX", os.path.join(HERE, "_p23_index.pkl"))
LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_pruned_P17.txt"))
PARTS = os.environ.get("PARTS_IN", os.path.join(HERE, "_parts_OD0911.json"))
MIN_RUNS = int(os.environ.get("P18_MIN_RUNS", "200"))

_API_CALL = re.compile(r"^SYM_RESULT_ActsAsApi__Collection_as_api_response_(\d+)$")
_API_ROW = re.compile(r"SYM_RESULT_ActsAsApi__Collection_as_api_response_(\d+)_row_([a-z_]+)")
_REC = re.compile(r"^SYM_RESULT_ActiveRecord__(?:Relation|Associations__CollectionProxy)_"
                  r"(?:records|to_ary)")


def fixlen(s):
    return _LEN_RE.sub(r"SYM_LEN_\1", s) if s else s


def main():
    t0 = time.time()
    parts = json.load(open(PARTS))["parts"]
    exprs = sorted({m for p in parts for m in p["members"]})
    eidx = {e: i for i, e in enumerate(exprs)}
    print(f"expr universe: {len(exprs)}", flush=True)

    files = [l.strip() for l in open(LIST) if l.strip()]
    files = [f if os.path.isabs(f) else os.path.join(HERE, f) for f in files]
    print(f"dumps: {len(files)}  from {os.path.basename(LIST)}", flush=True)

    dumps, canon_idx, len_idx = [], {}, {}
    seedable = Counter()
    domain = defaultdict(Counter)
    raw = {}
    binds = []
    bindstat = defaultdict(Counter)
    bindstat_raw = defaultdict(Counter)
    len0_counts = Counter(); len1_counts = Counter()
    # P23 (2026-09-12) — THE MINTING TABLE for RAW ORDINAL lengths.
    # §80.13 D1: 76 of the 102 one-sided splits sat on a base that DOES take the
    # length expression both ways, and the seed still lost the second reading,
    # "because an empty list's length decision is only recorded when that list
    # is REACHED". The split writes 0 to the other ordinals; whether those
    # ordinals exist at all on the driven path is governed by the same kind of
    # length precondition the necessity table already measures for expressions
    # — one level down, on the RAW positional name (`records_5`), which is what
    # the split machinery actually writes. `mintnec[rawkey]` is read off the
    # corpus exactly as `necess` is: over at least MIN_RUNS runs in which the
    # aliased length L was empty (resp. non-empty), the raw ordinal was NEVER
    # minted -> L is a measured precondition of that ordinal existing.
    rawlen_idx = {}
    rawmint = []                    # index-aligned with `dumps`
    mprofiles = Counter()
    rl0 = defaultdict(Counter)      # rawlen index -> Counter over len index (L empty)
    rl1 = defaultdict(Counter)
    rlm_counts = Counter()
    co0 = defaultdict(Counter)     # expr index -> Counter over length index (evaluated & L empty)
    co1 = defaultdict(Counter)
    eval_counts = Counter()
    profiles = Counter()
    for n, p in enumerate(files):
        if n and n % 4000 == 0:
            print(f"  {n}/{len(files)}  {time.time()-t0:.0f}s", flush=True)
        try:
            d = json.load(open(p))
        except Exception:
            continue
        ev = d.get("events") or ()
        amap = alias_map_for([(e.get("result_name"), e.get("note"))
                              for e in ev if e.get("type") == "symbolic_call"], ALIASES)
        rn = renamer(amap)
        cm = 0
        for c in set((amap or {}).values()):
            j = canon_idx.setdefault(c, len(canon_idx))
            cm |= 1 << j
        # ---------------- symbolic vars, observed domain, LENGTH STATE
        sv, sv0 = {}, {}
        for s in d.get("symbolic_vars") or ():
            nm, val = s.get("name"), s.get("value")
            if nm is None or isinstance(val, (dict, list)):
                continue
            sv0[str(nm)] = val
            nm = fixlen(rn(str(nm)))
            sv[nm] = val
            r = repr(val)
            domain[nm][r] += 1
            raw.setdefault((nm, r), val)
        rlm = 0
        for k in sv0:
            if k.startswith("len(") and k.endswith("_rows)"):
                j = rawlen_idx.setdefault(k, len(rawlen_idx))
                rlm |= 1 << j
        l0 = l1 = 0
        for k, v in sv.items():
            if not (k.startswith("SYM_LEN_") and k.endswith("_rows")):
                continue
            j = len_idx.setdefault(k, len(len_idx))
            if v:
                l1 |= 1 << j
            else:
                l0 |= 1 << j
        # ---------------- path conditions
        em = tm = fm = 0
        apif = defaultdict(set)
        for e in ev:
            if e.get("type") != "path_condition":
                continue
            ex = fixlen(rn(str(e.get("expr", ""))))
            i = eidx.get(ex)
            if i is not None:
                em |= 1 << i
                if e.get("taken"):
                    tm |= 1 << i
                else:
                    fm |= 1 << i        # BOTH-WAYS is tm & fm — a run can take one
                                        # expression both ways when several ordinals
                                        # back one alias canonical, and that is the
                                        # only shape in which a cube that empties a
                                        # canonical can still read a row of it.
            for m in _API_ROW.finditer(ex):
                apif[int(m.group(1))].add(m.group(2))
        # ---------------- THE API BINDING
        bind, bindraw = {}, {}
        last = lastraw = None
        for e in ev:
            if e.get("type") != "symbolic_call":
                continue
            rawnm = str(e.get("result_name") or "")
            nm = rn(rawnm)
            m = _API_CALL.match(nm)
            if m:
                bind[int(m.group(1))] = last
                # THE RAW ORDINAL, not only its canonical. A canonical is backed
                # by SEVERAL ordinals in the same run (mentions_66022a8b: 3 928 of
                # 8 000 sampled runs), so "make the canonical non-empty" is not a
                # seedable instruction — "make THIS ordinal non-empty and the
                # others empty" is, and it is the only way a cube that demands the
                # canonical empty can still reach the row it also demands read.
                bindraw[int(m.group(1))] = lastraw
            elif _REC.match(nm):
                last, lastraw = nm, rawnm
        for o, g in bind.items():
            L = bool(sv.get(f"SYM_LEN_{g}_rows")) if g else None
            # THE RAW ORDINAL'S OWN LENGTH. The alias canonical collapses two or
            # more `records` statements whose lengths differ in the same run, so
            # `SYM_LEN_<canonical>_rows` is not a function of the one list the
            # api call projects and the canonical-keyed test returns EITHER
            # where the truth is exact. Measured on the raw ordinal over 18 899
            # api calls: a `guid` is read in 9 191 of the calls whose own
            # preceding collection is non-empty and in 0 of the 4 613 whose
            # collection is empty.
            ro = bindraw.get(o)
            LR = bool(sv0.get(f"len({ro}_rows)")) if ro else None
            for fld in ("guid", "text_has_mention", "text_empty"):
                bindstat[(o, fld, g)][(L, fld in apif.get(o, ()))] += 1
                bindstat_raw[(o, fld)][(LR, fld in apif.get(o, ()))] += 1
        # ---------------- co-occurrence for the necessity table.
        # Aggregated over DISTINCT (em, l0, l1) triples and expanded once at the
        # end: the per-dump double loop is 137 x 30 and would dominate the scan.
        profiles[(em, l0, l1)] += 1
        mprofiles[(rlm, l0, l1)] += 1
        rawmint.append(rlm)
        for sk in d.get("concolic_seeds") or ():
            seedable[fixlen(rn(str(sk)))] += 1
        base = os.path.basename(p)
        v = next((x for x in VARIANTS if base.startswith("dump_" + x)), "auth_html")
        dumps.append((p, v, em, tm, len(d.get("concolic_seeds") or {}), cm, l0, l1, fm))
        binds.append((bind, bindraw))
        del d

    for (em, l0, l1), cnt in profiles.items():
        bits0, bits1 = [], []
        x = l0
        while x:
            b = x & -x; bits0.append(b.bit_length() - 1); x ^= b
        x = l1
        while x:
            b = x & -x; bits1.append(b.bit_length() - 1); x ^= b
        for j in bits0:
            len0_counts[j] += cnt
        for j in bits1:
            len1_counts[j] += cnt
        m = em
        while m:
            b = m & -m; i = b.bit_length() - 1; m ^= b
            eval_counts[i] += cnt
            c0, c1 = co0[i], co1[i]
            for j in bits0:
                c0[j] += cnt
            for j in bits1:
                c1[j] += cnt
    print(f"distinct (eval, len-state) profiles: {len(profiles)}", flush=True)
    for (rlm, l0, l1), cnt in mprofiles.items():
        bits0, bits1 = [], []
        x = l0
        while x:
            b = x & -x; bits0.append(b.bit_length() - 1); x ^= b
        x = l1
        while x:
            b = x & -x; bits1.append(b.bit_length() - 1); x ^= b
        m = rlm
        while m:
            b = m & -m; i = b.bit_length() - 1; m ^= b
            rlm_counts[i] += cnt
            c0, c1 = rl0[i], rl1[i]
            for j in bits0:
                c0[j] += cnt
            for j in bits1:
                c1[j] += cnt
    print(f"distinct (raw-mint, len-state) profiles: {len(mprofiles)}", flush=True)

    lens = [k for k, _ in sorted(len_idx.items(), key=lambda kv: kv[1])]
    print(f"indexed {len(dumps)} dumps in {time.time()-t0:.0f}s; "
          f"{len(domain)} vars in domain; {len(seedable)} seedable; "
          f"{len(canon_idx)} alias canonicals; {len(lens)} length variables", flush=True)

    # ------------------------------------------------- THE NECESSITY TABLE
    necess = {}
    for i, e in enumerate(exprs):
        if eval_counts[i] < MIN_RUNS:
            continue
        nz, z = [], []
        for j, L in enumerate(lens):
            if len0_counts[j] >= MIN_RUNS and co0[i].get(j, 0) == 0:
                nz.append(L)
            if len1_counts[j] >= MIN_RUNS and co1[i].get(j, 0) == 0:
                z.append(L)
        if nz or z:
            necess[e] = {"nz": nz, "z": z}
    print(f"NECESSITY TABLE: {len(necess)} of {len(exprs)} demand-universe expressions "
          f"carry at least one measured length precondition (MIN_RUNS={MIN_RUNS})")
    nnz = sum(len(v['nz']) for v in necess.values()); nz_ = sum(len(v['z']) for v in necess.values())
    print(f"   must-be-NONEMPTY conditions: {nnz}    must-be-EMPTY conditions: {nz_}")

    rawlens = [k for k, _ in sorted(rawlen_idx.items(), key=lambda kv: kv[1])]
    mintnec = {}
    for i, rk in enumerate(rawlens):
        if rlm_counts[i] < MIN_RUNS:
            continue
        nz, z = [], []
        for j, L in enumerate(lens):
            if len0_counts[j] >= MIN_RUNS and rl0[i].get(j, 0) == 0:
                nz.append(L)
            if len1_counts[j] >= MIN_RUNS and rl1[i].get(j, 0) == 0:
                z.append(L)
        # The same both-sides filter `_p18_construct` applies to `necess`: a
        # length appearing on BOTH sides is a mutually-exclusive statement, not
        # a precondition. Applied HERE so the table is already clean.
        both = set(nz) & set(z)
        nz = [x for x in nz if x not in both]; z = [x for x in z if x not in both]
        if nz or z:
            mintnec[rk] = {"nz": nz, "z": z}
    print(f"MINTING TABLE: {len(mintnec)} of {len(rawlens)} raw ordinal lengths carry "
          f"at least one measured precondition (MIN_RUNS={MIN_RUNS})")
    for rk in sorted(mintnec)[:12]:
        v = mintnec[rk]
        print(f"   {rk[:70]:<72} minted {rlm_counts[rawlen_idx[rk]]:6d}  "
              f"needs NZ {[x[len('SYM_LEN_SYM_RESULT_ActiveRecord__'):][:26] for x in v['nz']][:3]}"
              f" Z {[x[len('SYM_LEN_SYM_RESULT_ActiveRecord__'):][:26] for x in v['z']][:2]}")

    print("\nRAW-ORDINAL REQUIREMENT (the api call's own preceding collection):")
    for k in sorted(bindstat_raw):
        c = bindstat_raw[k]
        print(f"   ord {k[0]} {k[1]:<18} read|empty={c[(False,True)]:6d} read|full={c[(True,True)]:6d}"
              f" skip|empty={c[(False,False)]:6d} skip|full={c[(True,False)]:6d}")
    print("\nAPI BINDING STATISTICS (ordinal, field, governing collection):")
    for k in sorted(bindstat, key=lambda x: (x[0], x[1], str(x[2]))):
        c = bindstat[k]
        if not (c[(True, True)] + c[(False, True)]):
            continue
        print(f"   ord {k[0]} {k[1]:<17} {str(k[2])[len('SYM_RESULT_ActiveRecord__'):][:46]:<48}"
              f" read|empty={c[(False,True)]:6d} read|full={c[(True,True)]:6d}"
              f" skip|empty={c[(False,False)]:6d} skip|full={c[(True,False)]:6d}")

    with open(OUT, "wb") as fh:
        pickle.dump({"exprs": exprs, "dumps": dumps, "seedable": dict(seedable),
                     "canon": [c for c, _ in sorted(canon_idx.items(), key=lambda kv: kv[1])],
                     "lens": lens, "binds": binds,   # (canonical map, raw-ordinal map)
                     "bindstat": {f"{k[0]}\x00{k[1]}\x00{k[2]}": dict(v)
                                  for k, v in bindstat.items()},
                     "bindstat_raw": {f"{k[0]}\x00{k[1]}": dict(v)
                                      for k, v in bindstat_raw.items()},
                     "necess": necess,
                     "rawlens": rawlens, "rawmint": rawmint,
                     "rawmint_counts": {rawlens[i]: c for i, c in rlm_counts.items()},
                     "mintnec": mintnec,
                     "domain": {k: dict(v) for k, v in domain.items()},
                     "raw": {f"{k[0]}\x00{k[1]}": v for k, v in raw.items()}}, fh, 4)
    print(f"P23-INDEX-DONE {OUT} ({os.path.getsize(OUT)/1e6:.1f} MB) {time.time()-t0:.0f}s", flush=True)


main()
