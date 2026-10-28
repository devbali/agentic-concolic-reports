#!/usr/bin/env python3
"""Bulk DIVERSE seeds, v2 (2026-09-09) — assign EVERY length input.

v1 (`_diverse_seeds.py`) randomised only the `len(...)` keys ALREADY PRESENT
in a template dump's `concolic_seeds`. Measured over its 6 000 seeds: 3 394
carried ZERO length keys and the dominant demanded variable
(`records_notifications_8513a914` = `len(SYM_RESULT_ActiveRecord__Relation_
records_1_rows)`, present in 1 854 of the 1 830 missing witnesses) was left at
its default of 1 in >90% of seeds. Corpus census: that variable is > 1 in
only 2 071 of 51 362 runs. A "diverse" run that leaves the dominant variable
at default cannot cover the dominant demand.

v2: the length-input UNIVERSE is the set of raw `len(...)` symbolic-var names
observed across the corpus (27 names; census 2026-09-09). Every seed assigns
EVERY one of them (unknown keys are harmless: `seed_for` is a lookup at the
mint site). Domain {0,1,2,4}: the runtime clamps any value > 1 to "many"
(targets.rb `len_i = 3 if len_i > 1`, actors `an = 4 if an > 1`), so this is
{0, 1, many, many} — P(len > 1) = 1/2, P(== 0) = 1/4, balanced for the
thresholds the PCs test (`> 1` x7 862, `== 0` x468, `!= 0`, `> 0`, `> 3`).
Render/pluck probes (`set_rendered_content_type_*`, `*_plucked`) are always 1
in the corpus and never demanded — left untouched.

Context (every non-length seed) is inherited from a REAL dump so the deep
decisions are reached; SYM_NOTE_TYPE_PROFILE / SYM_POST_STI are re-rolled
with probability 1/2 (they are clique members too).

Usage: python3 _diverse_seeds2.py [N] [out.json] [--stride K]
"""
import glob, json, os, random, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
args = [a for a in sys.argv[1:] if not a.startswith("--")]
N = int(args[0]) if args else 4000
OUT = args[1] if len(args) > 1 else os.path.join(HERE, "_diverseR2.json")
STRIDE = 7
for i, a in enumerate(sys.argv):
    if a == "--stride":
        STRIDE = int(sys.argv[i + 1])
random.seed()

DOM = (0, 1, 2, 4)
SKIP = ("set_rendered_content_type", "_plucked")

templates, universe = [], set()
files = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
for p in files[::STRIDE]:
    try:
        d = json.load(open(p))
    except Exception:
        continue
    for sv in d.get("symbolic_vars") or ():
        nm = sv.get("name") or ""
        if nm.startswith("len(") and not any(s in nm for s in SKIP):
            universe.add(nm)
    s = d.get("concolic_seeds") or {}
    if s:
        templates.append(s)
universe = sorted(universe)
print(f"{len(templates)} seed templates (stride {STRIDE} over {len(files)} dumps); "
      f"length universe {len(universe)} keys")
if not templates or not universe:
    sys.exit(1)

out, seen = [], set()
for _ in range(N * 3):
    if len(out) >= N:
        break
    t = dict(random.choice(templates))
    for k in universe:
        t[k] = random.choice(DOM)
    if "SYM_NOTE_TYPE_PROFILE" in t and random.random() < 0.5:
        t["SYM_NOTE_TYPE_PROFILE"] = random.randint(0, 7)
    if "SYM_POST_STI" in t and random.random() < 0.5:
        t["SYM_POST_STI"] = random.randint(0, 1)
    key = json.dumps(t, sort_keys=True)
    if key in seen:
        continue
    seen.add(key)
    out.append(t)
json.dump(out, open(OUT, "w"))
from collections import Counter
c = Counter(v for s in out for k, v in s.items() if k.startswith("len("))
print(f"wrote {len(out)} diverse seeds -> {OUT}; len value spread {dict(sorted(c.items()))}")
