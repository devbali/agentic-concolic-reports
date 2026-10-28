#!/usr/bin/env python3
"""WHAT WOULD RE-KEYING THE find_by FAMILY BY IDENTITY DO TO `remaining`?

Asked by the coordinator alongside the identity question. §63 REFUTES the
identity premise on this endpoint (0 of 36 ordinal pairs agree in every run; 0
seed contradictions; all four cells of every 2x2 populated), so this number is
the MAGNITUDE OF AN UNSOUND MOVE, not a proposal. It is measured because the
size of what identity would buy is part of judging whether the premise is worth
re-testing anywhere else.

The rewrite: every `SYM_RESULT_..._FinderMethods_find_by_<N>_not_found` becomes
one name, `..._find_by_MEMO_not_found`, at LOAD, before the universe is built —
exactly what a `DecisionAlias`-style memo-hit re-keying would do. Everything
else (assumptions, pins, foreclosure inference, the factorised census) is
untouched, so the output is directly comparable to `_enum_p5_cost.log`.
"""
import json, os, re, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
import _exact_enum_emit as EE                                  # noqa: E402
import coverage_report as CR                                   # noqa: E402
from concolic_engine.run import Run                            # noqa: E402
from coverage_assumptions import build as build_assumptions    # noqa: E402

MERGE = re.compile(r"(FinderMethods_find_by)_\d+(_not_found)")
REPL = r"\1_MEMO\2"


def load_merged():
    lst = os.environ["DUMP_LIST"]
    dumps = sorted(l.strip() for l in open(lst) if l.strip())
    dumps = [d if os.path.isabs(d) else os.path.join(HERE, d) for d in dumps]
    print(f"DUMP_LIST {lst}: {len(dumps)} dumps", flush=True)
    runs, merged = [], 0
    for p in dumps:
        try:
            raw = json.load(open(p))
            if hasattr(CR, "canonicalize_ordinals"):
                CR.canonicalize_ordinals(raw)
            for ev in raw.get("events") or ():
                if ev.get("type") == "path_condition":
                    e = str(ev.get("expr", ""))
                    ne = MERGE.sub(REPL, e)
                    if ne != e:
                        ev["expr"] = ne
                        merged += 1
            r = Run.from_dict(CR.fix_len_names(raw))
            if hasattr(CR, "apply_len_bounds"):
                r = CR.apply_len_bounds(r)
            if hasattr(CR, "share_run_objects"):
                r = CR.share_run_objects(r)
            runs.append(r)
        except Exception:
            pass
    print(f"loaded {len(runs)} runs; rewrote {merged} find_by not_found PCs", flush=True)
    return runs


def main():
    t0 = time.time()
    runs = load_merged()
    A = build_assumptions(runs)
    U = EE.build_universe(runs, A, int(os.environ.get("MAX_CLIQUES", "16384")))
    if U is None:
        print("PROJECTION CAP HIT"); return 2
    print(f"universe built in {time.time()-t0:.0f}s", flush=True)
    res = EE.census(U, U["cliques"], EE.var_index(U["decls"]), {}, {}, 20000, 0,
                    use_forecl=True)
    json.dump(res, open(os.path.join(HERE, "_whatif_wf_merge.json"), "w"), indent=1)
    print(f"DONE in {time.time()-t0:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
