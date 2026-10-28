#!/usr/bin/env python3
"""P18 — DIAGNOSE the 340 P17 witnesses: which ROW-READ members they carry,
which LIST LENGTH governs each, what the corpus walks, and what is needed.

Definition of a ROW-READ member (measured, §80):
  * `<LIST>_row_<field>`  where <LIST> is a `records`/`to_ary` result:
        governor = SYM_LEN_<LIST>_rows                       (direct)
  * `SYM_RESULT_ActsAsApi__Collection_as_api_response_<n>_row_<field>`:
        the api call is a projection of the collection it is called ON, and the
        `_row_*` fields are that collection's row. The collection is the
        `records` call IMMEDIATELY PRECEDING the api call in the run's own
        event stream, so the governor is RUN-DEPENDENT and is read per dump.
        governor = SYM_LEN_<that canonical>_rows
Both are stated in CHECKER space (alias canonicalisation + len -> SYM_LEN).
"""
import json, os, re, sys, pickle, random
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer   # noqa: E402
from coverage_assumptions import ALIASES                          # noqa: E402

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
CKPT = os.environ.get("P18_CKPT", os.path.join(HERE, "_cov_p17.ckpt.jsonl"))
LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_pruned_P17.txt"))
SAMPLE = int(os.environ.get("P18_SAMPLE", "0"))          # 0 = all
OUT = os.environ.get("P18_OUT", os.path.join(HERE, "_p18_diag.json"))

_API = re.compile(r"^SYM_RESULT_ActsAsApi__Collection_as_api_response_(\d+)_row_([a-z_]+)$")
_ROW = re.compile(r"^(SYM_RESULT_ActiveRecord__(?:Relation|Associations__CollectionProxy)_"
                  r"(?:records|to_ary)[A-Za-z0-9_]*?)_row_([a-z_]+)$")
_REC = re.compile(r"^SYM_RESULT_ActiveRecord__(?:Relation|Associations__CollectionProxy)_"
                  r"(?:records|to_ary)")
_VAR = re.compile(r"SYM_(?:RESULT|LEN|PARAM)_[A-Za-z0-9_]+")


def cube_vars(nc):
    return set(_VAR.findall(nc or ""))


def direct_governor(v):
    """SYM_LEN_<LIST>_rows for a `<LIST>_row_<field>` member, else None."""
    m = _ROW.match(v)
    if m:
        return f"SYM_LEN_{m.group(1)}_rows"
    return None


def api_ordinal(v):
    m = _API.match(v)
    return (int(m.group(1)), m.group(2)) if m else None


def scan_corpus(files):
    """Per dump: alias-renamed length values, evaluated exprs, and the
    api-ordinal -> governing canonical binding this run realised."""
    lenval = defaultdict(Counter)          # SYM_LEN_x_rows -> value counter
    binding = defaultdict(Counter)         # api ordinal -> governor canonical
    bind_field = defaultdict(Counter)      # (ord, governor, len!=0) -> fields read
    rowfield_ok = defaultdict(Counter)     # (LIST, field) -> (len!=0, read)
    nn = 0
    for p in files:
        try:
            d = json.load(open(p))
        except Exception:
            continue
        nn += 1
        ev = d.get("events") or ()
        amap = alias_map_for([(e.get("result_name"), e.get("note"))
                              for e in ev if e.get("type") == "symbolic_call"], ALIASES)
        rn = renamer(amap)
        sv = {}
        for s in d.get("symbolic_vars") or ():
            sv[fixlen(rn(str(s.get("name"))))] = s.get("value")
        for k, v in sv.items():
            if k.startswith("SYM_LEN_") and k.endswith("_rows"):
                lenval[k][v] += 1
        apif = defaultdict(set); rowf = defaultdict(set)
        for e in ev:
            if e.get("type") != "path_condition":
                continue
            ex = fixlen(rn(str(e.get("expr") or "")))
            for v in _VAR.findall(ex):
                a = api_ordinal(v)
                if a:
                    apif[a[0]].add(a[1])
                m = _ROW.match(v)
                if m:
                    rowf[m.group(1)].add(m.group(2))
        last = None
        for e in ev:
            if e.get("type") != "symbolic_call":
                continue
            nm = rn(str(e.get("result_name") or ""))
            m = re.match(r"^SYM_RESULT_ActsAsApi__Collection_as_api_response_(\d+)$", nm)
            if m:
                n = int(m.group(1))
                binding[n][last] += 1
                L = sv.get(f"SYM_LEN_{last}_rows") if last else None
                for f in ("guid", "text_has_mention", "text_empty"):
                    bind_field[(n, f)][(bool(L), f in apif.get(n, ()))] += 1
            elif _REC.match(nm):
                last = nm
        for lst, fs in rowf.items():
            L = sv.get(f"SYM_LEN_{lst}_rows")
            for f in fs:
                rowfield_ok[f][(bool(L), True)] += 1
        for k in sv:
            if k.startswith("SYM_LEN_") and k.endswith("_rows"):
                lst = k[len("SYM_LEN_"):-len("_rows")]
                if lst not in rowf:
                    rowfield_ok["(any)"][(bool(sv[k]), False)] += 1
        del d
    return lenval, binding, bind_field, rowfield_ok, nn


def main():
    f = open(CKPT); f.readline()
    seen = set(); wit = []
    for line in f:
        r = json.loads(line); v = r["v"]
        for cb, mo in zip(v.get("combos") or [], v.get("models") or []):
            k = tuple((e, bool(o)) for e, o in cb)
            if k in seen:
                continue
            seen.add(k); wit.append({"set": r["k"], "cube": k, "model": mo})
    print(f"witnesses: {len(wit)}")

    files = [l.strip() for l in open(LIST) if l.strip()]
    if SAMPLE:
        random.seed(9); files = random.sample(files, min(SAMPLE, len(files)))
    print(f"scanning {len(files)} dumps ...", flush=True)
    lenval, binding, bind_field, rowfield_ok, nn = scan_corpus(files)
    print(f"scanned {nn}")

    print("\n== API-ORDINAL -> GOVERNING RECORDS LIST (the collection the api call projects)")
    for n in sorted(binding):
        tot = sum(binding[n].values())
        print(f"  as_api_response_{n}  ({tot} calls)")
        for g, c in binding[n].most_common(8):
            print(f"      {c:7d}  {str(g)[len('SYM_RESULT_ActiveRecord__'):]}")
    print("\n== IS A NON-EMPTY GOVERNOR NECESSARY FOR THE FIELD TO BE READ?")
    print("   (govLen!=0, fieldRead) counts, per (ordinal, field)")
    for k in sorted(bind_field, key=lambda x: (x[0], x[1])):
        c = bind_field[k]
        viol = c[(False, True)]
        print(f"   ord {k[0]:>2} {k[1]:<18} read|empty={viol:6d}  read|nonempty={c[(True,True)]:6d}"
              f"  notread|empty={c[(False,False)]:6d}  notread|nonempty={c[(True,False)]:6d}")

    # ---------------- per-witness row-read members and their governors
    rows = []
    fam_needed = Counter(); gov_conflict = Counter(); gov_free = Counter()
    needed_hist = Counter()
    for w in wit:
        nc = " AND ".join(e if o else f"Not({e})" for e, o in w["cube"])
        vs = cube_vars(nc)
        # which lengths does the cube itself FORCE to zero / non-zero?
        zero, nonzero = set(), set()
        for e, o in w["cube"]:
            m = re.match(r"^\((SYM_LEN_[A-Za-z0-9_]+) != 0\)$", e)
            if m:
                (nonzero if o else zero).add(m.group(1))
        ent = {"set": w["set"], "api": [], "row": [], "zero": sorted(zero),
               "nonzero": sorted(nonzero)}
        for v in sorted(vs):
            a = api_ordinal(v)
            if a:
                govs = [g for g, _ in binding[a[0]].most_common() if g]
                gk = [f"SYM_LEN_{g}_rows" for g in govs]
                conf = [g for g in gk if g in zero]
                ent["api"].append({"var": v, "ord": a[0], "field": a[1],
                                   "governors": gk, "forced_zero": conf,
                                   "any_free": len(conf) < len(gk)})
                fam_needed[f"api_{a[1]}"] += 1
                if conf and len(conf) == len(gk):
                    gov_conflict[f"api_{a[1]}"] += 1
                elif conf:
                    gov_free[f"api_{a[1]} (some binding free)"] += 1
                else:
                    gov_free[f"api_{a[1]} (no conflict)"] += 1
                continue
            g = direct_governor(v)
            if g:
                ent["row"].append({"var": v, "governor": g,
                                   "forced_zero": g in zero,
                                   "in_cube": g in vs})
                fam_needed[f"row_{_ROW.match(v).group(2)}"] += 1
                if g in zero:
                    gov_conflict[f"row_{_ROW.match(v).group(2)}"] += 1
                else:
                    gov_free[f"row_{_ROW.match(v).group(2)}"] += 1
        needed_hist[(len(ent["api"]), len(ent["row"]))] += 1
        rows.append(ent)

    print("\n== ROW-READ MEMBERS ACROSS THE 340 WITNESSES")
    for k, c in fam_needed.most_common():
        print(f"   {c:6d}  {k}")
    print("\n== GOVERNOR STATUS (does the SAME cube force the governing list empty?)")
    print("   -- every binding forced empty (structurally infeasible on that binding):")
    for k, c in gov_conflict.most_common():
        print(f"      {c:6d}  {k}")
    print("   -- at least one binding is free (constructible by base choice + a length pin):")
    for k, c in gov_free.most_common():
        print(f"      {c:6d}  {k}")
    nA = sum(1 for r in rows if r["api"]); nR = sum(1 for r in rows if r["row"])
    print(f"\n   witnesses with >=1 api row-read member : {nA}")
    print(f"   witnesses with >=1 records row-read    : {nR}")
    print(f"   witnesses with neither                 : "
          f"{sum(1 for r in rows if not r['api'] and not r['row'])}")

    print("\n== OBSERVED DOMAIN OF EVERY GOVERNING LENGTH (what the corpus walks)")
    govs = sorted({g for r in rows for a in r["api"] for g in a["governors"]}
                  | {x["governor"] for r in rows for x in r["row"]})
    for g in govs:
        c = lenval.get(g) or Counter()
        tot = sum(c.values()); nz = sum(v for k, v in c.items() if k)
        print(f"   {g[len('SYM_LEN_SYM_RESULT_ActiveRecord__'):][:60]:<62} "
              f"runs={tot:6d} nonzero={nz:6d} values={dict(c.most_common(5))}")
    json.dump({"witnesses": rows,
               "binding": {str(k): {str(a): b for a, b in v.items()} for k, v in binding.items()},
               "lenval": {k: {str(a): b for a, b in v.items()} for k, v in lenval.items()}},
              open(OUT, "w"))
    print(f"\nwrote {OUT}")
    print("P18-DIAG-DONE")


main()
