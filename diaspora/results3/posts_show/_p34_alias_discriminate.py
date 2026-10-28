#!/usr/bin/env python3
"""P34 — §40.5a for posts_show: THE DECISIONS THAT DISCRIMINATE EACH SIBLING
STATEMENT OF AN EXPOSED ALIAS FAMILY.

§40.5a (notifications_index, ported): a statement-keyed alias is itself a
CONDITION.  When a family resolves to several statements the run issues them
ALTERNATIVELY, and which one it issues is decided by some OTHER decision.  A
build that writes a member without that decision builds a run in which the
member's variable is NEVER MINTED — the seed "takes", the demand is
unrealised, and the leaf reads unconstructible.

posts_show is the worst-exposed endpoint measured (6 of 7 families; mentions 6
siblings, photos 5, likes 4, comments 4, tags 4, participations 3), so this
finds, per sibling, the literals that separate the runs that mint it from the
runs that mint a SIBLING of the same family — the matched-context differential
`_c29_enable.py` used, generalised over every family instead of one read.

Currency: every dump goes through THIS batch's `gate_canon.canonicalize_for_gate`
(= `canonicalize_ordinals` + `fix_len_names`) before any name is read, so the
literals are spelled the way the constructor and the engine spell them.  RUNBOOK
Phase 2's name-boundary trap, which §94.0 already hit once on this endpoint.

  usage: SNAP=<dump list> [SAMPLE=4000] [MINSEP=0.35] python3 -u _p34_alias_discriminate.py
  out:   _p34_alias_discriminators.json   (and a readable summary on stdout)
Read-only over the corpus; writes one file in this batch directory.
"""
import collections, json, os, random, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
SNAP = os.environ["SNAP"]
SAMPLE = int(os.environ.get("SAMPLE", "4000"))
MINSEP = float(os.environ.get("MINSEP", "0.35"))
TOP = int(os.environ.get("TOP", "12"))
OUT = os.environ.get("OUT", os.path.join(HERE, "_p34_alias_discriminators.json"))

import gate_canon                                     # noqa: E402
import coverage_assumptions as CA                     # noqa: E402
ALIASES = list(getattr(CA, "ALIASES", []) or [])
print(f"aliases: {len(ALIASES)}")

_H = re.compile(r"^(SYM_RESULT_\w+?)_([0-9a-f]{8})$")
files = [l.strip() for l in open(SNAP) if l.strip()]
random.seed(34)
files = random.sample(files, min(SAMPLE, len(files)))

runs = []            # (minted_canonical_set, literal_set)
fam = collections.defaultdict(set)
for i, p in enumerate(files):
    try:
        d = json.load(open(p))
    except Exception:
        continue
    amap = gate_canon.canonicalize_for_gate(d, ALIASES)
    minted = set()
    for _o, canon in (amap or {}).items():
        m = _H.match(canon)
        if m:
            fam[m.group(1)].add(canon)
            minted.add(canon)
    lits = {(str(e.get("expr", "")), bool(e.get("taken")))
            for e in d.get("events") or () if e.get("type") == "path_condition"}
    runs.append((minted, lits))
    if (i + 1) % 500 == 0:
        print(f"  {i+1}/{len(files)} dumps", flush=True)
print(f"sampled {len(runs)} dumps; {len(fam)} alias families", flush=True)

exposed = {k: sorted(v) for k, v in fam.items() if len(v) > 1}
print(f"EXPOSED families (more than one sibling statement): {len(exposed)}")
for k, v in sorted(exposed.items(), key=lambda kv: -len(kv[1])):
    print(f"   {len(v)} siblings  {k}")

# literal -> the set of run indices that record it with that outcome
litruns = collections.defaultdict(set)
for i, (_m, lits) in enumerate(runs):
    for L in lits:
        litruns[L].add(i)

out = {}
for family, sibs in sorted(exposed.items(), key=lambda kv: -len(kv[1])):
    famruns = {s: {i for i, (m, _l) in enumerate(runs) if s in m} for s in sibs}
    ctx = set().union(*famruns.values())     # runs that mint SOME member
    print(f"\n{'='*78}\n=== {family}   {len(sibs)} siblings, minted in {len(ctx)} of {len(runs)} runs")
    fam_out = {}
    for s in sibs:
        pos = famruns[s]
        neg = ctx - pos                      # mints a SIBLING, not this one
        if not pos or not neg:
            print(f"  {s.split('_')[-1]}: pos={len(pos)} neg={len(neg)} — NO DIFFERENTIAL")
            fam_out[s] = {"pos": len(pos), "neg": len(neg), "discriminators": [],
                          "note": "one side empty"}
            continue
        rows = []
        for L, rs in litruns.items():
            a = len(pos & rs) / len(pos)
            b = len(neg & rs) / len(neg)
            if abs(a - b) > MINSEP and max(a, b) > 0.5:
                rows.append((round(abs(a - b), 4), round(a, 4), round(b, 4), L[0], L[1]))
        rows.sort(reverse=True)
        fam_out[s] = {"pos": len(pos), "neg": len(neg),
                      "discriminators": [{"sep": r[0], "rate_mints": r[1],
                                          "rate_sibling": r[2], "expr": r[3],
                                          "taken": r[4]} for r in rows[:TOP]]}
        print(f"  {s}: mints in {len(pos)}, siblings in {len(neg)}, "
              f"{len(rows)} separator(s) > {MINSEP}")
        for r in rows[:5]:
            print(f"      {'T' if r[4] else 'F'} {r[1]*100:5.1f}% vs {r[2]*100:5.1f}%  {r[3][:100]}")
    out[family] = {"siblings": sibs, "per_sibling": fam_out}

json.dump({"sample": len(runs), "min_separation": MINSEP,
           "exposed_families": len(exposed), "families": out},
          open(OUT, "w"), indent=1)
print(f"\nwrote {OUT}")
print("P34-ALIAS-DISCRIMINATE-DONE")
