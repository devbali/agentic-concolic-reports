#!/usr/bin/env python3
"""C29 — build the two blocking cubes from bases chosen by their ENABLING
GATES, not by the cube.

WHY THIS IS A DIFFERENT BUILD FROM C24/C27/C28's. Every earlier round chose
bases that RECORD the cube's own members and overlaid the rest. Both cubes
demand `SYM_LEN_..._CollectionProxy_records_photos_aa895602_rows`, and
`aa895602` is not "the photos read" — it is the photos read issued on an
UNPERSISTED owner (`AND (1=0)`; Rails merges `none!` into a new_record owner's
association scope, concolic_targets.rb:669-676). Measured on the corpus of
record: with `..._row_target_persisted == True` (6 292 runs) that statement is
evaluated in **0**; with it False (2 366 runs) in **1 175**. The cube does not
carry `row_target_persisted` as a member, so no builder ever wrote it, and the
photos statement the cube names was simply absent from almost every base.

The second gate is `..._row_target_text_nil == True` (a 100 %-vs-0 % separator
in the matched-context differential, `_c29_enable.out`): with the status
message's text nil the render falls through to the photos branch.

So: bases are runs that ALREADY walk {target unpersisted, dispatch arm 2|3,
photos_aa895602 evaluated}; the cube's per-row members are carried by the base
(the C22/C24 rule — overlaying a row-level value changes which partial renders
and the downstream decision then never happens); the non-per-row members and
the two gates are written.

C30 (2026-09-15): COPY of `_c29_build.py` (§29.9's rule: copy, never edit a
script an earlier round is judged by), retargeted at the ONE cube C30OFF1 still
reports blocking on set0. FOUR differences, each stated:

  1. THE SCAN IS THIS ROUND'S. `_c29_scan.pkl` was built on 136 184 runs with
     C29's dispatch-only FILTER; this reads `_c30_scan_R1.pkl` (136 280 runs,
     FILTER=".", 441 exprs) via the SCAN env var, so the base pool sees the
     C30R1 dumps as well.
  2. THE PHOTOS LENGTH IS 4, NOT 1. C29's ON arm wrote
     `SYM_LEN_..._photos_aa895602_rows = 1`, which realises `Not(> 1)` — that
     is the SIBLING leaf, and it is the one C29 closed. The leaf still blocking
     is the same cube with `photos_aa895602_rows > 1`, so the demand is 4
     (the mock's length domain is 0 -> 0, 1 -> 1, 2|3|4 -> 3, §31.2).
  3. `ROWS` IS A PER-ROW WANT. The blocking cube carries
     `(SYM_LEN_..._3aa8587a_rows > 1)` TRUE, which C29's ON arm did not, so the
     base must already record it (it is prefix-coupled; overlaying it is
     forbidden).
  4. THE ARM IS 2 ONLY. C29's pool accepted dispatch arm 2 OR 3 because it
     built both cubes; only the arm-2 cube is still blocking.

WHY THIS BUILD AND NOT `_c30_construct.py`. Measured on C30R2's own 64 runs:
`_c30_construct.py` classes `photos_aa895602` as a HARD member and therefore
writes NO seed for it — the base is required to carry it. The base did carry
it, on the `..._row_target_mentions_container_commentable_photos_row_rows`
chain; the two ENABLING GATES then moved the run onto the
`..._row_target_photos_row_rows` chain, which the base seeds to 1, so the
length came back 1 and the demand was unrealised in 10 of 10 runs that
evaluated it (`evaluated=10, realised=0` — the §40.5a signature one level
deeper, on the SEED KEY rather than on the variable). This build WRITES the
photos length through the base's own alias map, which is what C29's realising
runs did.

  usage: [SCAN=_c30_scan_R1.pkl] [PHLEN=4] K=8 PREF=_c30_s0_seeds_ \
         MANIFEST=_c30_s0_manifest.json python3 -u _c30_build_set0.py
"""
import collections, json, os, pickle, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for, renamer    # noqa: E402
from coverage_assumptions import ALIASES                          # noqa: E402
from _c17_seedkey_fix import fix_seeds                            # noqa: E402
from _c29_dispatch import ON, OFF, P, V, DV, PH                   # noqa: E402

S = pickle.load(open(os.environ.get("SCAN", os.path.join(HERE, "_c30_scan_R1.pkl")), "rb"))
N, T, F, META, FILES = S["n"], S["T"], S["F"], S["meta"], S["files"]
ALL = (1 << N) - 1
VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
PREF = os.environ.get("PREF", "_c30_s0_seeds_")
MANIFEST = os.environ.get("MANIFEST", "_c30_s0_manifest.json")
PHLEN = int(os.environ.get("PHLEN", "4"))
K = int(os.environ.get("K", "8"))
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s

tb = lambda e: T.get(e, 0); fb = lambda e: F.get(e, 0)
eb = lambda e: tb(e) | fb(e); pc = lambda x: x.bit_count()
mask = lambda lit: tb(lit[0]) if lit[1] else fb(lit[0])
PERS = f"({V}_row_target_persisted == True)"
TXTNIL = f"({V}_row_target_text_nil == True)"
GUID = f"({V}_row_target_guid == '')"
PH1 = f"({PH} > 1)"
TGT = f"({V}_row_target_not_found == True)"
ACT = f"(SYM_LEN_{V}_row_actors_row_rows > 1)"
TAP = f"({V}_row_target_author_profile_not_found == True)"
ROWS = f"(SYM_LEN_{V}_rows > 1)"


def M(sub):
    m = ALL
    for lit in sub:
        m &= mask(lit)
    return m


def bits(m):
    out = []
    b = m.to_bytes((N + 7) // 8, "little")
    for bi, byte in enumerate(b):
        if byte:
            for k in range(8):
                if byte & (1 << k):
                    out.append(bi * 8 + k)
    return out


CUBE = os.environ.get("CUBE", "s0")
# The ONE cube `_cov_C30_C30OFF1.json` still reports blocking, verbatim:
#   Not(P==0..1), (P==2), Not(P==3..7),
#   Not(devise_user_first_1_person_not_found), (..._person_profile_not_found),
#   (LEN 3aa8587a_rows > 1), Not(3aa8587a_row_target_not_found),
#   (LEN 3aa8587a_row_actors_row_rows > 1),
#   Not(3aa8587a_row_target_author_profile_not_found),
#   (LEN photos_aa895602_rows > 1)
cube, arm, want_rows = ON, 2, True
per_row_wanted = [(TGT, False), (ACT, True), (TAP, False), (ROWS, True)]
write = [(P, "int", 2),
         (f"{DV}_person_not_found", "bool", False),
         (f"{DV}_person_profile_not_found", "bool", True),
         (f"SYM_LEN_{PH[8:] if PH.startswith('SYM_LEN_') else PH}", "len", PHLEN)]
# the two ENABLING GATES, written explicitly even though the base carries them
GATES = [(f"{V}_row_target_persisted", "bool", False),
         (f"{V}_row_target_text_nil", "bool", True)]

PHVAR = PH  # "SYM_LEN_SYM_RESULT_..._photos_aa895602_rows"
write = [w for w in write if not w[0].startswith("SYM_LEN_SYM_LEN_")]
write = [((PHVAR if w[1] == "len" else w[0]), w[1], w[2]) for w in write]


def base_pool():
    """runs that already walk the enabling chain and carry the per-row members"""
    lits = [(PERS, False), (PH1, None)]
    m = M([(PERS, False)]) & eb(PH1)
    m &= tb(f"({P} == {arm})")
    strict = m
    for e, o in per_row_wanted:
        strict &= mask((e, o))
    return m, strict


def build(pool_bits, label, tagged):
    per_variant = collections.defaultdict(list)
    manifest = []
    for i in pool_bits:
        p = FILES[i]
        variant = next((v for v in VARIANTS
                        if os.path.basename(p).startswith("dump_" + v)), None)
        if variant is None:
            continue
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

        def seedkeys(k):
            dn = f"len({k[8:]})" if k.startswith("SYM_LEN_") else k
            outs = [dn]
            for c in rev_sorted:
                if re.search(re.escape(c) + r"(?![0-9])", dn):
                    outs = [re.sub(re.escape(c) + r"(?![0-9])",
                                   o.replace("\\", "\\\\"), dn) for o in rev[c]]
                    break
            return [o for o in outs if fixlen(rnm(o)) == k]

        wrote, unres = [], []
        for var, kind, val in GATES + write:
            ks = seedkeys(var)
            if not ks:
                unres.append(var)
                continue
            for sk in ks:
                s[sk] = val
                wrote.append([sk, val])
        # C17's `fix_seeds` moves a RE-MINTED length demand to the upstream
        # key the runtime reads -- and the base's own re-mint seed can land on
        # the very key this build just wrote (measured on C29B: the base's
        # `len(..._row_target_photos_row_rows) = 0` was moved onto
        # `len(..._CollectionProxy_records_2_rows)` and clobbered the demanded
        # 4, so `photos > 1` came back FALSE in 44 of 44 runs). The DEMAND wins:
        # re-apply this build's own writes after the move.
        s, moved = fix_seeds(s, d)
        for var, kind, val in GATES + write:
            for sk in seedkeys(var):
                s[sk] = val
        del d
        per_variant[variant].append(s)
        manifest.append({"cube": CUBE, "base": os.path.basename(p),
                         "variant": variant, "wrote": wrote,
                         "unresolved": unres,
                         "remint_moved": [[a, b] for a, b, _v in moved]})
    return per_variant, manifest


if __name__ == "__main__":
    loose, strict = base_pool()
    print(f"corpus {N}")
    print(f"base pool  LOOSE  (target unpersisted, arm 2|3, photos_aa895602 "
          f"evaluated): {pc(loose)}")
    print(f"base pool  STRICT (+ the per-row members already recorded as the "
          f"cube wants): {pc(strict)}")
    for e, o in per_row_wanted:
        print(f"    of the loose pool, {pc(loose & mask((e, o))):5d} record "
              f"{'T' if o else 'F'}  {e[:88]}")
    pool = strict if pc(strict) else loose
    which = "STRICT" if pc(strict) else "LOOSE"
    sel = bits(pool)
    print(f"building CUBE={CUBE} from the {which} pool, {len(sel)} bases")
    pv, man = build(sel, CUBE, CUBE)
    for v in VARIANTS:
        json.dump(pv.get(v, []), open(os.path.join(HERE, f"{PREF}{v}.json"), "w"))
    json.dump({"cube": CUBE, "pool": which, "bases": len(sel),
               "manifest": man}, open(os.path.join(HERE, MANIFEST), "w"), indent=1)
    print("per variant:", {v: len(pv.get(v, [])) for v in VARIANTS})
    unres = collections.Counter()
    for m in man:
        for u in m["unresolved"]:
            unres[u] += 1
    print("unresolved seed keys:", unres.most_common())
    print(f"C30-BUILT {sum(len(x) for x in pv.values())} seeds")
