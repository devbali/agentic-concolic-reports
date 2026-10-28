#!/usr/bin/env python3
"""C29 — PHANTOM DECISIONS: is any decision recorded ONLY in runs that carry an
out-of-domain seed the application cannot produce?

The coordinator's question (2026-09-14). 2 074 of 2 074 `No route matches` runs
carry `SYM_RESULT_..._devise_user_first_1_username = ""` as a SEED, and
`app/models/user.rb:37-38` validates `username` for presence and against
`/\\A[A-Za-z0-9_]+\\z/`, so a persisted `User` cannot carry `""`. The runs are
therefore exploring a state the application cannot reach. That does not make
the policy unsound by itself -- but any decision (or statement) recorded ONLY
in such runs is PHANTOM: the corpus's only evidence for it comes from a state
the app forecloses.

This measures it, over the corpus of record, for THREE out-of-domain seed
classes, not just the one:

  U   `*_username == ""`        (user.rb:37-38 presence + format)
  G   `*_guid == ""`            (every Diaspora guid column is NOT NULL and set
                                 by `Diaspora::Guid` before_validation)
  D   `*_diaspora_handle == ""` (person.rb validates presence + uniqueness)

For each class: the runs carrying it (by SEED, which is what makes it the rig's
choice rather than the app's), and then, over the WHOLE corpus, every recorded
path-condition EXPRESSION and every issued STATEMENT that appears in those runs
and in NO other run.

Read-only.  usage: DUMP_LIST=.. OUT=.. [WORKERS=4] python3 -u _c29_phantom.py
"""
import collections, json, os, re, sys, time
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for            # noqa: E402
import coverage_report as CR                                     # noqa: E402
from coverage_assumptions import ALIASES                         # noqa: E402

LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_c29_R1.txt"))
OUT = os.environ.get("OUT", os.path.join(HERE, "_c29_phantom.json"))
WORKERS = int(os.environ.get("WORKERS", "4"))
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
_BIND = re.compile(r"\$\$\([^)]*\)")

FILES = [l.strip() for l in open(LIST) if l.strip()]
N = len(FILES)

CLASSES = {
    "U_username_empty": lambda k, v: k.endswith("_username") and v == "",
    "G_guid_empty": lambda k, v: k.endswith("_guid") and v == "",
    "D_handle_empty": lambda k, v: k.endswith("_diaspora_handle") and v == "",
}


def one(p):
    try:
        d = json.load(open(p))
    except Exception:
        return None
    seeds = d.get("concolic_seeds") or {}
    tags = set()
    for name, pred in CLASSES.items():
        for k, v in seeds.items():
            if pred(k, v):
                tags.add(name)
                break
    ev = d.get("events") or []
    alias_map_for([(e.get("result_name"), e.get("note"))
                   for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    CR.canonicalize_ordinals(d)
    exprs, stmts = set(), set()
    for e in d.get("events") or []:
        t = e.get("type")
        if t == "path_condition" and e.get("expr") is not None:
            exprs.add(fixlen(str(e["expr"])))
        elif t == "symbolic_call" and e.get("note"):
            nt = str(e["note"])
            if nt.lstrip().upper().startswith(("SELECT", "INSERT", "UPDATE", "DELETE")):
                stmts.add(_BIND.sub("$$()", nt)[:400])
    return tags, exprs, stmts


if __name__ == "__main__":
    t0 = time.time()
    # expr/stmt -> [runs total, runs inside each class]
    etot = collections.Counter(); stot = collections.Counter()
    ein = {c: collections.Counter() for c in CLASSES}
    sin = {c: collections.Counter() for c in CLASSES}
    runs_in = collections.Counter(); n = 0
    with Pool(WORKERS) as pool:
        for i, r in enumerate(pool.imap_unordered(one, FILES, chunksize=300)):
            if r is None:
                continue
            n += 1
            tags, exprs, stmts = r
            for c in tags:
                runs_in[c] += 1
            for x in exprs:
                etot[x] += 1
                for c in tags:
                    ein[c][x] += 1
            for x in stmts:
                stot[x] += 1
                for c in tags:
                    sin[c][x] += 1
            if (i + 1) % 20000 == 0:
                print(f"  {i+1}/{N}  {time.time()-t0:.0f}s", flush=True)
    res = {"n": n, "list": LIST, "classes": {}}
    print(f"\ncorpus {n} runs; distinct exprs {len(etot)}, distinct statements {len(stot)}")
    for c in CLASSES:
        ph_e = sorted(x for x in ein[c] if ein[c][x] == etot[x])
        ph_s = sorted(x for x in sin[c] if sin[c][x] == stot[x])
        print(f"\n=== {c}: {runs_in[c]} runs carry this out-of-domain SEED")
        print(f"    decisions recorded ONLY in them : {len(ph_e)}")
        print(f"    statements issued ONLY in them  : {len(ph_s)}")
        for x in ph_e[:40]:
            print(f"      PHANTOM DECISION  (in {etot[x]} runs)  {x[:120]}")
        for x in ph_s[:20]:
            print(f"      PHANTOM STATEMENT (in {stot[x]} runs)  {x[:120]}")
        res["classes"][c] = {"runs": runs_in[c],
                             "phantom_exprs": [[x, etot[x]] for x in ph_e],
                             "phantom_statements": [[x, stot[x]] for x in ph_s]}
    json.dump(res, open(OUT, "w"), indent=1)
    print(f"\nwall {time.time()-t0:.0f}s")
    print("C29-PHANTOM-DONE", flush=True)
