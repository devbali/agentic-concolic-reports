#!/usr/bin/env python3
"""CONCRETE CHECKER, compare side (RUNBOOK Phase 5; formerly "C1/C2" —
generalized from SQL to TARGET FUNCTIONS).

    python3 concrete_checker.py <concrete_run.json>... <batch_dir> [--corpus-coverage cov.json]

Ground truth = a concrete run of the endpoint (captured with
concrete_run_probe.rb: target-function invocations + line coverage).
Both comparisons are in engine-native currency:

TARGET SIDE (the generalized statement check — Class S detector for ANY
target family, SQL or not): every target function the concrete run
invoked must appear as a symbolic_call event in the corpus. A target the
real path reaches that the corpus never recorded = a mock swallowed a
target function. Reported per target with corpus event counts.

COVERAGE SIDE (the Class B detector): every app line the concrete run
executed should be visible to the corpus.
  - With --corpus-coverage (union coverage from a corpus collected under
    a runner coverage flag): exact line diff — concrete-executed lines
    absent from corpus coverage are blind spots.
  - Without it (interim): approximate via corpus EVENT SITES — the
    (file, line) locations of recorded PCs and target calls. A concrete
    file with executed lines but ZERO corpus events is flagged; per-file
    line-level gaps are listed as candidates only (clearly labeled
    approximate — event sites are branch/target locations, not full
    execution traces).

PREREQUISITE for the capture side: a working fixture environment —
target functions run for REAL during the concrete run (a stub mode was
removed: real code with a faked target boundary is the concolic engine's
own structure, not ground truth).
Exit 1 on any missing target.
"""
import glob
import json
import os
import re
import sys
from collections import defaultdict


def normalize_target(label):
    # probe labels "Mod#meth" / "Mod.meth" vs event targets "Mod.meth"
    return label.replace("#", ".")


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        sys.exit("usage: concrete_checker.py <concrete_run.json>... <batch_dir> [--corpus-coverage cov.json]")
    if "--corpus-coverage" in args:
        i = args.index("--corpus-coverage")
        corpus_cov_path = args[i + 1]
        args = args[:i] + args[i + 2:]
    else:
        corpus_cov_path = None
    aliases = {}
    if "--aliases" in args:
        i = args.index("--aliases")
        # {concrete_label: [corpus_labels]} — batch-declared naming
        # equivalence (e.g. call-site-stable finder ALIASES in the concolic
        # runner are literal alias_method copies of find_by)
        aliases = json.load(open(args[i + 1]))
        args = args[:i] + args[i + 2:]
    run_paths, batch = args[:-1], args[-1]

    scenarios = []
    for rp in run_paths:
        scenarios.extend(json.load(open(rp)))

    corpus_targets = defaultdict(int)
    event_sites = defaultdict(set)          # file -> {lines with any event}
    for f in glob.glob(os.path.join(batch, "dump_*.json")):
        d = json.load(open(f))
        for ev in d.get("events") or []:
            if ev.get("type") == "symbolic_call" and ev.get("target"):
                corpus_targets[normalize_target(str(ev["target"]))] += 1
            fl, ln = ev.get("file"), ev.get("lineno")
            if fl and ln:
                event_sites[fl].add(int(ln))

    corpus_cov = json.load(open(corpus_cov_path)) if corpus_cov_path else None

    red = False
    for sc in scenarios:
        name = sc.get("name")
        print(f"== scenario {name} ==")
        if sc.get("error"):
            print(f"   note: body raised ({sc['error']}) — trace kept up to the error")

        seen = defaultdict(lambda: [0, 0])   # target -> [depth0 count, nested count]
        for c in sc.get("target_calls") or []:
            d = int(c.get("depth", 0))
            seen[normalize_target(c["target"])][0 if d == 0 else 1] += 1
        print("-- TARGET SIDE: concrete target-function invocations vs corpus events --")
        for tgt, (top, nested) in sorted(seen.items()):
            in_corpus = corpus_targets.get(tgt, 0)
            by_method = [t for t in corpus_targets
                         if t.rsplit(".", 1)[-1] == tgt.rsplit(".", 1)[-1]] if in_corpus == 0 else []
            via_alias = [t for t in aliases.get(tgt, []) if corpus_targets.get(t, 0) > 0]
            if in_corpus > 0:
                mark = f"present ({in_corpus} corpus events)"
            elif via_alias:
                mark = (f"present via declared alias {via_alias[0]} "
                        f"({corpus_targets[via_alias[0]]} events)")
            elif by_method:
                # runtime label drift (e.g. anonymous singleton classes record
                # as "Anonymous.<meth>"): same method name, different owner
                # label — annotated match, verify identity by hand once
                mark = (f"method-name match: corpus records it as "
                        f"{by_method[0]} ({corpus_targets[by_method[0]]} events) — label drift, verify once")
            elif top == 0:
                # every concrete call was INSIDE another target frame: under
                # interception the outer mock fires first and this inner
                # never runs — its evidence lives in the outer's note
                mark = "nested-only: SUBSUMED by outer targets (no corpus events needed)"
            else:
                red = True
                mark = "MISSING FROM CORPUS  <-- RED (swallowed target)"
            print(f"   {tgt:<70} top x{top:<4} nested x{nested:<4} {mark}")
        if not seen:
            print("   (no target functions invoked)")

        print("-- COVERAGE SIDE" + (" (exact, corpus coverage supplied)" if corpus_cov
                                    else " (APPROXIMATE via corpus event sites)") + " --")
        for fl, lines in sorted((sc.get("coverage") or {}).items()):
            short = re.sub(r"^.*?(app|lib)/", r"\1/", fl)
            if corpus_cov is not None:
                missing = sorted(set(lines) - set(corpus_cov.get(fl, [])))
                if missing:
                    red = True
                    print(f"   {short}: {len(missing)} concrete lines never covered by corpus: {missing[:10]}")
                else:
                    print(f"   {short}: fully corpus-covered ({len(lines)} lines)")
            else:
                sites = event_sites.get(fl, set())
                if not sites:
                    print(f"   {short}: executed concretely, ZERO corpus events in file "
                          f"({len(lines)} lines) — inspect (approximate signal)")
                else:
                    print(f"   {short}: {len(lines)} concrete lines; corpus has "
                          f"{len(sites)} event sites in file (line-exact check needs --corpus-coverage)")
        print()

    print("RESULT: RED — targets missing from corpus above (generalized Class S)."
          if red else "RESULT: every concretely-invoked target function is present in the corpus.")
    sys.exit(1 if red else 0)


if __name__ == "__main__":
    main()
