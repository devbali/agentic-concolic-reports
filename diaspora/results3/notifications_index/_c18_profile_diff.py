#!/usr/bin/env python3
"""C18 — the GROUND-TRUTH DIFFERENTIAL behind the A = 0 gate conjunctions.

Every one of the 12 A = 0 gate prefixes the C17R2 pass still names has the
SAME shape: all eight `(SYM_NOTE_TYPE_PROFILE == k)` NOT taken (the dispatch
index is outside the mock's 0..7 profile table), together with
`_row_target_not_found` and `_row_target_mentions_container_not_found`
FALSE (both found).

This measures, over the WHOLE corpus, what a run with an out-of-range
dispatch index actually does with those gates, against the same counts for
an in-range run.

  usage: [DUMP_LIST=..] [WORKERS=4] python3 -u _c18_profile_diff.py [out.json]
"""
import json, os, re, sys
from collections import Counter
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals   # noqa: E402
import coverage_assumptions as CA                   # noqa: E402

LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_c18.txt"))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_c18_profile_diff.json")
W = int(os.environ.get("WORKERS", "4"))
PROF = [f"(SYM_NOTE_TYPE_PROFILE == {k})" for k in range(8)]
_UNLEN = re.compile(r"len\(([^()]+)\)")
WATCH = re.compile(r"_row_target_not_found == True\)$"
                   r"|_row_target_mentions_container_not_found == True\)$"
                   r"|devise_user_first_1_person_not_found == True\)$"
                   r"|Core__ClassMethods_find_by_1_not_found == True\)$")


def one(fp):
    c = Counter()
    try:
        d = json.load(open(fp))
    except Exception:
        c["BAD"] += 1; return c
    v = None
    for sv in d.get("symbolic_vars") or ():
        if sv.get("name") == "SYM_NOTE_TYPE_PROFILE":
            v = sv.get("value")
    canonicalize_ordinals(d, CA.ALIASES)
    pcs = {}
    for e in d.get("events") or ():
        if e.get("type") != "path_condition":
            continue
        ex = e["expr"]; tk = bool(e.get("taken"))
        pcs.setdefault(ex, set()).add(tk)
        ex2 = _UNLEN.sub(r"SYM_LEN_\1", ex)
        pcs.setdefault(ex2, set()).add(tk)
    seen = [p for p in PROF if p in pcs]
    if len(seen) < 8:
        c["profile-not-fully-dispatched"] += 1
        return c
    oor = all(True not in pcs[p] for p in PROF)
    tag = "OOR" if oor else "INRANGE"
    c[f"{tag}:runs"] += 1
    c[f"{tag}:value={v}"] += 1
    err = (d.get("error") or {}).get("type") or "-"
    c[f"{tag}:err={err}"] += 1
    for ex, outs in pcs.items():
        if not WATCH.search(ex):
            continue
        fam = ("target_not_found" if ex.endswith("_row_target_not_found == True)") else
               "mentions_container_not_found"
               if ex.endswith("_row_target_mentions_container_not_found == True)") else
               "person_not_found"
               if "devise_user_first_1_person_not_found" in ex else
               "core_find_by_1_not_found")
        for o in outs:
            c[f"{tag}:{fam}:{o}"] += 1
        c[f"{tag}:{fam}:EVALUATED"] += 1
    return c


def main():
    files = [l.strip() for l in open(LIST) if l.strip()]
    T = Counter()
    with ProcessPoolExecutor(max_workers=W) as ex:
        for i, r in enumerate(ex.map(one, files, chunksize=200)):
            T.update(r)
            if (i + 1) % 30000 == 0:
                print(f"[diff] {i+1}/{len(files)}", flush=True)
    print(f"\ncorpus {len(files)} dumps")
    for k in sorted(T):
        print(f"  {T[k]:9d}  {k}")
    json.dump(dict(T), open(OUT, "w"), indent=1)
    print(f"\nC18-PROFILE-DIFF-DONE {OUT}")


if __name__ == "__main__":
    main()
