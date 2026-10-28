#!/usr/bin/env python3
"""Explain a drive round, the way §12.10 did — per SEED KEY and per CUBE.

Per key (the §12.10 measurement, reproduced on the round's own dumps):
    honoured        the run minted the variable and it equals the seed
    contradicted    the run minted it and it differs
    never evaluated the run never minted the variable at all

Per cube (new, §14, owner point 3/4): for every witness the round aimed at,
how many of its MEMBERS any single run of the round actually evaluated, which
members were never evaluated by any of them, and what the ENABLING GATES were
doing in those runs. A member that stays unevaluated while its enabling gates
are all set the way the model asked is direct evidence that the pairwise
foreclosure inference missed a gate — which is the §16b conjunction refinement
of §13.3(2), and is what the owner asked to see named.

usage: NEW_SINCE=<file|epoch> PLAN=_enable_plan_E1.json python3 -u _seed_audit.py \
           [--glob 'dump_*E1*.json'] [--sample N]
"""
import glob, json, os, random, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals   # noqa: E402

_UNLEN = re.compile(r"len\(([^()]+)\)")


def opt(flag, default=None):
    a = sys.argv[1:]
    return a[a.index(flag) + 1] if flag in a else default


PAT = opt("--glob") or os.environ.get("ROUND_GLOB") or "dump_*.json"
SAMPLE = int(opt("--sample", os.environ.get("SEED_AUDIT_SAMPLE", "2500")))
PLAN = os.environ.get("PLAN")

files = sorted(glob.glob(os.path.join(HERE, PAT)))
since = os.environ.get("NEW_SINCE")
if since:
    t = os.path.getmtime(since) if os.path.exists(since) else float(since)
    files = [f for f in files if os.path.getmtime(f) > t]
print(f"round dumps matching {PAT}"
      + (f" newer than {since}" if since else "") + f": {len(files)}")
if not files:
    print("NOTHING TO AUDIT"); sys.exit(1)
if SAMPLE and len(files) > SAMPLE:
    random.seed(20260910)
    files = sorted(random.sample(files, SAMPLE))
    print(f"sampled {len(files)}")

# ---------------------------------------------------------------- per key --
hon = con = nev = 0
per_run_never = []
never_by_key = Counter()
con_by_key = Counter()
# ---------------------------------------------------------------- per cube -
# CUBES=<remaining.jsonl>: the per-cube half now reads the ENUMERATOR's cube
# list directly (the overlay seeder has no per-cube plan to carry). Sampled,
# because the full cross-product is 22 562 cubes x the round's dumps.
CUBES = os.environ.get("CUBES")
cubes = []
if CUBES:
    allc = []
    for line in open(CUBES):
        if not line.strip():
            continue
        r = json.loads(line)
        if not r.get("reachable"):
            continue
        full = dict(r.get("pre") or {}); full.update(r.get("asg") or {})
        allc.append({"idx": len(allc), "cube": sorted(full.items()),
                     "req": {}, "set": r.get("set")})
    ncap = int(os.environ.get("CUBE_SAMPLE", "2000"))
    if len(allc) > ncap:
        random.seed(20260911)
        cubes = random.sample(allc, ncap)
    else:
        cubes = allc
    print(f"cubes from {CUBES}: {len(allc)} reachable, auditing a sample of {len(cubes)}")
elif PLAN and os.path.exists(PLAN):
    plan = json.load(open(PLAN))
    cubes = [p for p in plan.get("plans", []) if p.get("status") == "ok"]
    print(f"plan cubes (solved): {len(cubes)}")
best_hit = [0] * len(cubes)          # most members any one run evaluated
realised = [0] * len(cubes)          # runs that walked the whole cube as demanded
member_unseen = [None] * len(cubes)  # members no run of the round evaluated
gate_obs = [None] * len(cubes)       # enabling gate -> Counter(outcome) as observed
for i, c in enumerate(cubes):
    member_unseen[i] = set(x for x, _w in c["cube"])
    gate_obs[i] = defaultdict(Counter)

t0 = time.time()
for n, fp in enumerate(files):
    if n and n % 2000 == 0:
        print(f"  [{n}/{len(files)}] {time.time()-t0:.0f}s", flush=True)
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    seeds = d.get("concolic_seeds") or {}
    minted = {v.get("name"): v.get("value") for v in (d.get("symbolic_vars") or ())}
    nk = 0
    for k, sv in seeds.items():
        if k not in minted:
            nev += 1; nk += 1; never_by_key[k] += 1
            continue
        mv = minted[k]
        same = (str(mv) == str(sv)) or (mv == sv)
        if same:
            hon += 1
        else:
            con += 1; con_by_key[k] += 1
    if seeds:
        per_run_never.append(nk / len(seeds))
    if cubes:
        canonicalize_ordinals(d)
        pcs = {}
        for e in d.get("events") or ():
            if e.get("type") == "path_condition":
                ex = e["expr"]
                # The dumps spell a length `len(X)`; the enumerator's cubes
                # spell it `SYM_LEN_X` (coverage_report.fix_len_names converts
                # at load). Without this every length member — most of the
                # gating on this endpoint — reads as "never evaluated".
                ex2 = _UNLEN.sub(r"SYM_LEN_\1", ex)
                pcs.setdefault(ex, set()).add(bool(e.get("taken")))
                if ex2 != ex:
                    pcs.setdefault(ex2, set()).add(bool(e.get("taken")))
        for i, c in enumerate(cubes):
            hit = 0
            allmatch = True
            for x, w in c["cube"]:
                if x in pcs:
                    hit += 1
                    member_unseen[i].discard(x)
                    if w not in pcs[x]:
                        allmatch = False
                else:
                    allmatch = False
            if hit > best_hit[i]:
                best_hit[i] = hit
            if allmatch:
                realised[i] += 1
            for g, w in (c.get("req") or {}).items():
                if g in pcs:
                    for o in pcs[g]:
                        gate_obs[i][g][bool(o)] += 1
    del d

tot = hon + con + nev
print("\n=== PER SEED KEY (§12.10 measurement, this round) ===")
for lbl, n in (("honoured", hon), ("contradicted", con), ("never evaluated", nev)):
    print(f"  {lbl:18s} {n:9d}  {100.0*n/max(1,tot):5.1f} %")
if per_run_never:
    per_run_never.sort()
    q = lambda f: per_run_never[min(len(per_run_never)-1, int(f*len(per_run_never)))]
    print(f"  per-run never-evaluated share: median {q(.5):.2f}  p90 {q(.9):.2f}")
print("  top never-evaluated keys: " +
      "; ".join(f"{k.split('__')[-1][:44]}={v}" for k, v in never_by_key.most_common(8)))
print("  top contradicted keys:    " +
      "; ".join(f"{k.split('__')[-1][:44]}={v}" for k, v in con_by_key.most_common(8)))

if cubes:
    full = sum(1 for i, c in enumerate(cubes) if best_hit[i] == len(c["cube"]))
    walked = sum(1 for r in realised if r)
    print("\n=== PER CUBE (the round's own targets) ===")
    print(f"  cubes aimed at:                       {len(cubes)}")
    print(f"  cubes with EVERY member evaluated by some run: {full}"
          f"  ({100.0*full/len(cubes):.1f} %)")
    print(f"  cubes REALISED (all members, demanded outcomes, one run): {walked}"
          f"  ({100.0*walked/len(cubes):.1f} %)")
    hist = Counter()
    for i, c in enumerate(cubes):
        hist[len(c["cube"]) - best_hit[i]] += 1
    print("  members STILL unevaluated (best run), by count: " +
          ", ".join(f"{k}:{v}" for k, v in sorted(hist.items())))
    # which members, and what the enabling gates were doing
    umem = Counter()
    for i, c in enumerate(cubes):
        for x in member_unseen[i]:
            umem[x] += 1
    print("  most-often-unevaluated MEMBERS:")
    for x, n in umem.most_common(10):
        print(f"    {n:5d}x  {x[:120]}")
    print("  enabling gates as OBSERVED in the round's runs, for cubes that "
          "still missed a member (gate: demanded -> observed counts):")
    shown = 0
    for i, c in enumerate(cubes):
        if best_hit[i] == len(c["cube"]) or not member_unseen[i]:
            continue
        if shown >= 6:
            break
        shown += 1
        print(f"    cube#{c['idx']} depth={c.get('depth')} gates={len(c.get('req') or {})} "
              f"base={c.get('base')} agree={c.get('base_agree')}")
        print(f"      unevaluated: " +
              "; ".join(x.split('__')[-1][:60] for x in sorted(member_unseen[i])[:4]))
        for g, w in list((c.get("req") or {}).items())[:5]:
            obs = gate_obs[i].get(g)
            print(f"      gate {g.split('__')[-1][:58]}  demanded={w}  "
                  f"observed={dict(obs) if obs else 'NEVER EVALUATED'}")
    out = os.path.join(HERE, f"_seed_audit_{os.environ.get('TAG','R')}.json")
    json.dump({"files": len(files), "honoured": hon, "contradicted": con,
               "never": nev, "cubes": len(cubes), "full_member_coverage": full,
               "realised": walked,
               "unevaluated_members": umem.most_common(50)},
              open(out, "w"), indent=1)
    print(f"\nwrote {out}")
