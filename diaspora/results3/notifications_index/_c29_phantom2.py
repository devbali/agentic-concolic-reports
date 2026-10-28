#!/usr/bin/env python3
"""C29 — the PHANTOM question, asked precisely.

`_c29_phantom.py` flagged 28 decisions recorded only in runs seeding some
`*_guid = ""`. That class is TOO COARSE and the first pass says so: the flagged
decisions are the `AND (1=0)` photos subtree, which exists exactly when an owner
is NOT PERSISTED -- and an unpersisted ActiveRecord row legitimately has no guid
(`Diaspora::Guid` assigns it before validation on create). That is a MODELLED
state, deliberately symbolic since `concolic_targets.rb:669-690`, not an
out-of-domain seed.

The out-of-domain state is narrower and this measures exactly it:

    a base whose `<base>_guid` is SEEDED "" while the run itself RECORDS
    `(<base>_persisted == True)` TAKEN

-- a row the run says came back persisted and yet carries an empty guid, which
the application's NOT NULL column and before_validation hook forbid. For the
runs carrying at least one such pair: every decision and every statement
recorded in them and in NO other run.

Read-only.  usage: DUMP_LIST=.. OUT=.. [WORKERS=3] python3 -u _c29_phantom2.py
"""
import collections, json, os, re, sys, time
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for, renamer   # noqa: E402
import coverage_report as CR                                     # noqa: E402
from coverage_assumptions import ALIASES                         # noqa: E402

LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_c29_R1.txt"))
OUT = os.environ.get("OUT", os.path.join(HERE, "_c29_phantom2.json"))
WORKERS = int(os.environ.get("WORKERS", "3"))
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
_BIND = re.compile(r"\$\$\([^)]*\)")
_PERS = re.compile(r"^\((SYM_\w+)_persisted == True\)$")

FILES = [l.strip() for l in open(LIST) if l.strip()]
N = len(FILES)


def one(p):
    try:
        d = json.load(open(p))
    except Exception:
        return None
    seeds = d.get("concolic_seeds") or {}
    ev = d.get("events") or []
    # SEED keys are ORDINAL-named and PC exprs are CANONICAL, so the seed key
    # must go through the SAME renamer before the two can be compared. (The
    # first cut of this script compared raw tails and matched NOTHING, which
    # is why the control below is run and reported rather than assumed.)
    amap = alias_map_for([(e.get("result_name"), e.get("note"))
                          for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    rn = renamer(amap)
    empty_guid_bases = {rn(k)[:-5] for k, v in seeds.items()
                        if k.endswith("_guid") and v == ""}
    CR.canonicalize_ordinals(d)
    exprs, stmts = set(), set()
    persisted_true, persisted_false = set(), set()
    for e in d.get("events") or []:
        t = e.get("type")
        if t == "path_condition" and e.get("expr") is not None:
            x = fixlen(str(e["expr"]))
            exprs.add(x)
            m = _PERS.match(x)
            if m:
                (persisted_true if e.get("taken") else persisted_false).add(m.group(1))
        elif t == "symbolic_call" and e.get("note"):
            nt = str(e["note"])
            if nt.lstrip().upper().startswith(("SELECT", "INSERT", "UPDATE", "DELETE")):
                stmts.add(_BIND.sub("$$()", nt)[:400])
    bad = persisted_true & empty_guid_bases          # exact canonical match
    ok = persisted_false & empty_guid_bases          # the legitimate arm (control)
    return (1 if bad else 0), sorted(bad)[:4], exprs, stmts, (1 if ok else 0), \
        (1 if empty_guid_bases else 0)


if __name__ == "__main__":
    t0 = time.time()
    etot = collections.Counter(); stot = collections.Counter()
    ein = collections.Counter(); sin = collections.Counter()
    nbad = 0; n = 0; nok = 0; nseed = 0; examples = collections.Counter()
    with Pool(WORKERS) as pool:
        for i, r in enumerate(pool.imap_unordered(one, FILES, chunksize=300)):
            if r is None:
                continue
            n += 1
            flag, bad, exprs, stmts, okflag, seedflag = r
            nbad += flag; nok += okflag; nseed += seedflag
            for b in bad:
                examples[b] += 1
            for x in exprs:
                etot[x] += 1
                if flag:
                    ein[x] += 1
            for x in stmts:
                stot[x] += 1
                if flag:
                    sin[x] += 1
            if (i + 1) % 30000 == 0:
                print(f"  {i+1}/{N}  {time.time()-t0:.0f}s", flush=True)
    ph_e = sorted(x for x in ein if ein[x] == etot[x])
    ph_s = sorted(x for x in sin if sin[x] == stot[x])
    print(f"\ncorpus {n} runs; distinct exprs {len(etot)}, statements {len(stot)}")
    print(f"runs seeding SOME base's guid to \"\"                      : {nseed}")
    print(f"  CONTROL - of them, runs recording such a base UNPERSISTED : {nok}")
    print(f"  runs recording such a base PERSISTED (OUT OF DOMAIN)      : {nbad}")
    print(f"  decisions recorded ONLY in them : {len(ph_e)}")
    print(f"  statements issued ONLY in them  : {len(ph_s)}")
    for x in ph_e[:40]:
        print(f"    PHANTOM DECISION  (in {etot[x]} runs)  {x[:120]}")
    for x in ph_s[:20]:
        print(f"    PHANTOM STATEMENT (in {stot[x]} runs)  {x[:120]}")
    print("  top bases:", examples.most_common(8))
    json.dump({"n": n, "runs_out_of_domain": nbad,
               "runs_with_empty_guid_seed": nseed, "control_unpersisted": nok,
               "phantom_exprs": [[x, etot[x]] for x in ph_e],
               "phantom_statements": [[x, stot[x]] for x in ph_s],
               "top_bases": examples.most_common(20)}, open(OUT, "w"), indent=1)
    print(f"\nwall {time.time()-t0:.0f}s")
    print("C29-PHANTOM2-DONE", flush=True)
