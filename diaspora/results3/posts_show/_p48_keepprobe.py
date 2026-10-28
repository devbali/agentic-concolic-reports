#!/usr/bin/env python3
"""Re-run ONE confinement flip probe with keep=True, against the INSTRUMENTED
targets tree, to capture the crashing dump the gate throws away.

    usage: PYTHONPATH=/home/dev/project/src python3 _p48_keepprobe.py [MAX_BASES]

WHY THIS EXISTS.

The 2026-09-28 gate refuted 2,086/2,086 ConfinementAssumption pairs. 1,068 of
the 1,693 FAILs cite an out-of-footprint shape that is not SQL at all:

    ActiveRecord::Associations::CollectionProxy.records
      | Reshare query (render_relation_sql failed: NoMethodError
        undefined method `value' for #<Arel::Nod...), args= |

i.e. `sql_for`'s rescue storing exception text where a note belongs — B-4's
signature. Where that string does and does not appear was measured:

    v3 corpus, all 151,648 dumps ........... 0
    _cov_P48COV.json (coverage-only) ....... 0
    _assumptions_declared.json ............. 0
    _p48_P48GATE_probes.ckpt.jsonl ......... 0
    _c1/_gate_engine.log ................... 0   (truncates before the paren)
    coverage_summary.json .................. 1,068   <- ONLY here

So the note is minted during the gate's assumption phase and nowhere else, and
every cached artifact that would have preserved it is either truncated or
doesn't hold it. The reason there is no evidence is `run_probe`'s `keep`
parameter: at :910-922 it DELETES every probe dump (and the seed file) unless
`keep` is true, and the gate runs with keep=False — the checkpoint header
records `"keep": "False"`.

`_confinement_composition` (:2161-2215) is where the traces come from:

    seeds = dict(seeds_as_written(sd))          # PRE-canonicalize-hook dict
    fa    = flipped_seeds(sd, seeds, ea, da)    # flip A via the RECORDED PC
    ra    = cache.run(fa, scen, "conf_0")       # -> run_probe(..., keep)

and criterion (i) at :2267-2272 is `leak_a = (ta ^ base) - fpa`, computed over
`shape_str(x) for x in trace_of(ra)`. So the crashed note is in a REPLAY TRACE,
and a replay with keep=True must preserve it.

WHAT THIS SCRIPT DOES, and what it deliberately does not.

It replicates that one call — same `seeds_as_written`, same `flipped_seeds`,
same `run_probe` — with two differences:

  1. `keep=True`, so the dump and the seed file survive;
  2. `cfg["runner"]` points at `_p48_diag/run_dse.rb`, whose
     `concolic_targets.rb` has `sql_for`'s rescue widened to print the full
     error class, message, receiver and backtrace, plus a `BindParam#value`
     rescue that names `node.class` and its ancestors.

It does NOT modify anything under src/, does not change any logic, and does not
run a gate. It retains an artifact that is normally deleted.

It walks candidate base dumps until one produces the crash, because which base
the gate used is not recorded in the withdrawal file (only the pair is).
"""
import glob
import json
import os
import sys

B = '/home/dev/project/reports/diaspora/results3/posts_show'
sys.path.insert(0, '/home/dev/project/src')
sys.path.insert(0, B)

import end_to_end_completion_checker.assumption.assumption_checker as AC  # noqa: E402

# The expressions that actually appear in CRASH-TAINTED refutations, ranked by
# frequency (written by the extraction step; see _p48_diag/_crash_exprs.json).
# The first attempt used only `(Length(SYM_PARAM_id) < 16)` because it was the
# most common expression across ALL pairs -- but that is not the same as the
# expression whose FLIP produces the crash. 32 probe dumps from 8 bases gave 0
# crashes and rendered the Reshare note correctly, so that choice was wrong.
# The `assoc_root_*` / `assoc_status_message_*` family perturbs the ROOT POST
# the Reshare relation is built from, which is the likelier trigger.
EXPRS = json.load(open(os.path.join(B, '_p48_diag', '_crash_exprs.json')))

MAX_BASES = int(sys.argv[1]) if len(sys.argv) > 1 else 3
MAX_EXPRS = int(sys.argv[2]) if len(sys.argv) > 2 else 10


def bases_for(expr, want):
    """Up to `want` dumps that EVALUATE `expr` and carry seeds, sampled ACROSS
    the corpus (strided) rather than from its head -- the first attempt drew 8
    consecutive early anon_html dumps, whose seed dicts are shallow."""
    out = []
    files = sorted(glob.glob(os.path.join(B, 'v3', 'dump_*.json')))
    for p in files[::max(1, len(files) // 4000)]:
        d = AC._load_dump_uncached(p)
        if not AC.outcomes_of(d, expr):
            continue
        seeds = dict(AC.seeds_as_written(d))
        if not seeds:
            continue
        out.append((p, d, seeds))
        if len(out) >= want:
            break
    return out


def main():
    cfg = json.load(open(os.path.join(B, '_p48_assumption_manifest.json')))
    # Point the runner at the INSTRUMENTED tree. Everything else (workdir,
    # env, env_by_scenario) is the batch's own.
    cfg['runner'] = cfg['runner'].replace('/posts_show/run_dse.rb',
                                          '/posts_show/_p48_diag/run_dse.rb')
    print(f"runner: {cfg['runner']}")
    print(f"batch_dir: {cfg['batch_dir']}")

    pairs = []
    for expr in EXPRS[:MAX_EXPRS]:
        bs = bases_for(expr, MAX_BASES)
        print(f"  {len(bs)} base(s) evaluate {expr[:70]}")
        for b in bs:
            pairs.append((expr,) + b)
    print(f"total probe launches planned: {len(pairs)}")

    for i, (EXPR_A, p, sd, seeds) in enumerate(pairs, 1):
        scen = (sd.get('concolic_scenario') or {}).get('name')
        dim = AC._runtime_key(sd, EXPR_A) if hasattr(AC, '_runtime_key') else None
        fa = AC.flipped_seeds(sd, seeds, EXPR_A, EXPR_A)
        if fa is None:
            print(f"  [{i}] {os.path.basename(p)}: flip not inferable, skip")
            continue
        name = f"p48k{i}"
        print(f"  [{i}] {os.path.basename(p)} scenario={scen} -> running probe {name} (keep=True)")
        res = AC.run_probe(cfg, name, fa, True, scen)
        print(f"       probe produced {len(res)} dump(s)")
        hit = False
        for bn, dd in res.items():
            for ev in dd.get('events') or []:
                if 'render_relation_sql failed' in str(ev.get('note') or ''):
                    print(f"       *** CRASH NOTE FOUND in {bn}")
                    print(f"       target: {ev.get('target')}")
                    print(f"       note  : {ev.get('note')}")
                    hit = True
        if hit:
            print("\nRETAINED probe dumps (not deleted):")
            for bn in res:
                print("   ", bn)
            return 0
    print("\nno crash reproduced across the bases tried")
    return 1


if __name__ == '__main__':
    sys.exit(main())
