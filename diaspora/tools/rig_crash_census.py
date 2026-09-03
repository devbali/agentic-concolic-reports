#!/usr/bin/env python3
"""rig_crash_census — a run that crashed in the RIG's own code is a wrong
recording, never evidence.

Conversations cycle 21 (2026-08-30, A6-7): a repair cast every finder bind
through `value_for_database`, the runtime refused `to_i` on a symbolic value,
and every scalar-cid run died with `NotImplementedError` AFTER recording its
cid decision — so coverage read `complete` at 117 nodes while the corpus held
no `= ?` / `IN (?, ?)` conversations read at all. Coverage is a claim about
decisions; statements are a separate claim.

This census fails when any dump's terminal error is one the rig itself
raises (NotImplementedError from the symbolic runtime, NoMethodError on a
rep, the interceptor's own errors), and prints the histogram of every
terminal class so a batch can state, per class, that it is a REAL app
terminal.

usage: rig_crash_census.py <batch_dir> [--allow CLASS,...]
"""
import glob, json, os, sys, collections

RIG_CLASSES = ("NotImplementedError", "Concolic", "SymbolicRuntime")
RIG_MESSAGE_MARKERS = ("symbolic", "Symbolic", "concolic rep", "rows_mock", "SymbolicInt", "SymbolicString")

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(2)
    batch = sys.argv[1]
    allow = set()
    if "--allow" in sys.argv:
        allow = set(sys.argv[sys.argv.index("--allow") + 1].split(","))
    hist = collections.Counter(); rig = collections.Counter(); sample = {}
    files = glob.glob(os.path.join(batch, "dump_*.json"))
    for p in files:
        try:
            d = json.load(open(p))
        except Exception:
            hist["<unparseable>"] += 1; continue
        # A rig may record its terminal in EITHER field: conversations' rig uses
        # `error`; comments' rig reserves `error` for unexpected failures and puts
        # app terminals in `concolic_terminal`. Reading one field only printed
        # 20 879 x "<ok>" over a field empty by construction (2026-09-01) — a
        # census that examines a field the rig never writes proves nothing.
        e = d.get("error") or d.get("concolic_terminal")
        if not e:
            hist["<ok>"] += 1; continue
        if isinstance(e, dict):
            t = str(e.get("type")); m = str(e.get("message", ""))
            cause = e.get("cause")
            if cause:
                ct = str(cause.get("type") if isinstance(cause, dict) else cause)
                cm = str(cause.get("message", "") if isinstance(cause, dict) else "")
                t = f"{t}<-{ct}"; m = m + " || cause: " + cm
        else:
            t = str(e); m = ""
        hist[t] += 1
        if t not in allow and (any(c in t for c in RIG_CLASSES) or
                               (t in ("NoMethodError", "TypeError") and any(k in m for k in RIG_MESSAGE_MARKERS))):
            rig[t] += 1; sample.setdefault(t, (os.path.basename(p), m[:140]))
    print(f"== rig_crash_census: {len(files)} dumps ==")
    for t, n in hist.most_common():
        print(f"   {n:7d}  {t}{'   <-- RIG' if t in rig else ''}")
    for t, (f, m) in sample.items():
        print(f"   e.g. {t}: {f}: {m}")
    if rig:
        print(f"RESULT: FAIL — {sum(rig.values())} dump(s) terminated inside the rig's own code "
              f"({', '.join(rig)}); they recorded decisions without the statements those runs "
              f"would have issued. Fix the rig, delete them, re-seed the arms they covered.")
        sys.exit(1)
    print("RESULT: pass — every terminal class is an application terminal (state that per class in the report).")

if __name__ == "__main__":
    main()
