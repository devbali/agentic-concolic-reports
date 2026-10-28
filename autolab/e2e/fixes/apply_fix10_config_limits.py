#!/usr/bin/env python3
"""apply_fix10_config_limits.py — make each endpoint's config.json declare the
limits the sweep actually runs.

THE DEFECT.  `config.json` is the document the gates read: `concolic.review`
quotes it verbatim and the campaign digests it (`config_digest`).  All 161
scaffolded configs declare

    "scenarios": {"<variant>": {"MAX_RUNS": "6", "TIME_BUDGET": "600"}},
    "limits": {"max_runs": 6, ...}

and NO RUN HAS EVER USED THOSE NUMBERS.  Shakedown run 1 and run 2 both drove
`MAX_RUNS=2, TIME_BUDGET=120`; this e2e sweep drives 24 / 300.  A real review
item produced by the dry run reads, in full:

    "Scenario 'auth_json' is selected by the environment
     [MAX_RUNS=6, TIME_BUDGET=600]. The claim is that this is one of the modes
     the endpoint really has, and that the set of scenarios is the whole set."

— a false statement about every run that has ever been made from this config.

THE FIX, IN TWO HALVES.
  * `tools/sweep.py` now READS the limits from each endpoint's config.json and
    records `config_max_runs` / `config_time_budget` / `limits_overridden` in
    the manifest, so a divergence can never again be silent (done in place).
  * this script writes the limits the sweep will actually use INTO the
    configs, so the document and the run agree.

WHY 24 / 300, MEASURED, not chosen for comfort.  In the shakedown, 125 of 161
endpoints finished with `worklist_exhausted: false` and a non-empty worklist —
cut off by MAX_RUNS, not by the budget and not by having nothing left. DSE
itself cost 390.8 s across ALL 161 endpoints (max 9.8 s each) against ~180 s
of JRuby+Rails boot per endpoint, so depth was nearly free and the shallowness
was a harness choice. At 24 the e2e sweep's own numbers show the change is
real, and it is worth stating exactly rather than in the obvious summary:
`aspect_memberships_create` went from 2 dumps to 23 with its path-condition
count UNCHANGED at 16 (it already reached 16 in one dump) -- what it gained is
21 more DISTINCT PATHS, and with them two runs that hit
`ActiveRecord::AssociationTypeMismatch` and 251 branches still on its
worklist. `comments_index` gained on every axis: 2 dumps -> 12, 4 path
conditions -> 17, reach 1 -> 3.

Usage: apply_fix10_config_limits.py [--apply] [--max-runs N] [--time-budget N]
"""
from __future__ import annotations
import argparse, json, os, shutil

SCAFFOLD = "/home/dev/project/reports/autolab/entrypoints/scaffold"
GENERATOR = "/home/dev/project/reports/autolab/entrypoints/tools/scaffold.py"

# THE GENERATOR IS PATCHED TOO, and that is the point. `scaffold.py:228-229,262`
# hardcode `"MAX_RUNS": "6"`, `"TIME_BUDGET": "600"` and `"max_runs": 6`, so
# rewriting the 161 configs WITHOUT touching the generator means the next
# `scaffold.py` run silently puts the stale numbers back — which is exactly
# how the document and the run drifted apart in the first place.
GEN_EDITS = [
    ('                    "MAX_RUNS": "6",\n                    "TIME_BUDGET": "600",',
     '                    # e2e FIX-10 (2026-09-26): the limits a sweep really\n'
     '                    # drives. Were 6/600, and no run had ever used them --\n'
     '                    # both shakedowns drove 2/120. `concolic.review` quotes\n'
     '                    # this block verbatim, so a stale number here is a\n'
     '                    # false statement in every campaign review item.\n'
     '                    "MAX_RUNS": "%(max_runs)d",\n'
     '                    "TIME_BUDGET": "%(time_budget)d",'),
    ('                "max_runs": 6,',
     '                "max_runs": %(max_runs)d,  # e2e FIX-10; see scenarios above'),
]

NOTE = ("Run limits set to the values the auto-lab sweep actually drives "
        "(reports/autolab/e2e/fixes/apply_fix10_config_limits.py, 2026-09-26). "
        "They were 6/600 and no run had ever used them: both shakedowns drove "
        "2/120. 125 of 161 endpoints were truncated by MAX_RUNS with work "
        "still on the worklist, while DSE cost 390.8 s across all 161 against "
        "~180 s of boot each, so depth was nearly free.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--max-runs", type=int, default=24)
    ap.add_argument("--time-budget", type=int, default=300)
    a = ap.parse_args()

    # ---- the GENERATOR first, so a later regeneration cannot undo this ----
    g = open(GENERATOR).read()
    gen_ok = True
    for frag, repl in GEN_EDITS:
        if g.count(frag) != 1:
            print(f"  !! generator anchor x{g.count(frag)}: {frag[:40]!r}")
            gen_ok = False
            continue
        g = g.replace(frag, repl % {"max_runs": a.max_runs,
                                    "time_budget": a.time_budget})
    if gen_ok:
        if a.apply:
            shutil.copy(GENERATOR, GENERATOR + ".bak_e2e_fix10")
            open(GENERATOR, "w").write(g)
            print(f"  patched {GENERATOR}")
        else:
            print(f"  would patch {GENERATOR}")

    changed = 0
    for eid in sorted(os.listdir(SCAFFOLD)):
        p = os.path.join(SCAFFOLD, eid, "config.json")
        if not os.path.isfile(p):
            continue
        cfg = json.load(open(p))
        before = json.dumps(cfg, sort_keys=True)
        for _name, sc in (cfg.get("scenarios") or {}).items():
            sc["MAX_RUNS"] = str(a.max_runs)
            sc["TIME_BUDGET"] = str(a.time_budget)
        cfg.setdefault("limits", {})["max_runs"] = a.max_runs
        cfg.setdefault("autolab", {})["run_limits_note"] = NOTE
        if json.dumps(cfg, sort_keys=True) == before:
            continue
        changed += 1
        if a.apply:
            shutil.copy(p, p + ".bak_e2e_fix10")
            with open(p, "w") as fh:
                json.dump(cfg, fh, indent=2)
                fh.write("\n")
    print(f"{'patched' if a.apply else 'would patch'} {changed} config.json files "
          f"-> MAX_RUNS={a.max_runs} TIME_BUDGET={a.time_budget}")


if __name__ == "__main__":
    main()
