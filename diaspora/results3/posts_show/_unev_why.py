#!/usr/bin/env python3
"""§76.2(c) — WHY the constructed seeds' gate outcomes came out UNEVALUATED.

Reuses notifications' §19 method (`_conj_forecl.py`) on posts_show's own
artefacts. posts_show's constructor tags no combo id in the seeds, so the
conjunction is recovered FROM THE RUN: for an UNEVALUATED gate `g` in a drive
dump, `P` is the set of OTHER seeded gates that the run DID evaluate with their
seeded value — the prefix that run actually walked.

    (g, P) is a CONJUNCTION FORECLOSURE iff some corpus run matches P and NO
    run matching P evaluates g.                       (§16b's own 'never' test)

Buckets, in this order (first match wins, so they are disjoint):
    RENDER-ERROR  the run terminated in an error   -> the walk stopped early
    ALIAS         the run walked a SIBLING statement alias of g's own family
                  (same target + note family, different statement hash), so a
                  seed naming g's alias cannot be reached from that base
    CONJUNCTION-FORECLOSURE / REACHABLE / NO-MATCH   as above
Read-only; caged.
"""
import glob, json, os, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from coverage_report import canonicalize_ordinals  # noqa: E402
from concolic_engine.names import NameSpace  # noqa: E402

EMIT_IN = os.environ.get("EMIT_IN", "_enum_emit_ORDEMAND.json")
TAG = os.environ.get("DRIVE_TAG", "OD0911")
MAXPAIRS = int(os.environ.get("MAXPAIRS", "600"))

cubes = json.load(open(os.path.join(HERE, EMIT_IN)))["missing"]
wanted = {}
for c in cubes:
    for k, v in (c.get("gates") or {}).items():
        wanted.setdefault(k, set()).add(bool(v))
del cubes
print(f"gate decisions seeded by this round: {len(wanted)}", flush=True)

DIM = re.compile(r"^\(\s*([A-Za-z_][A-Za-z0-9_]*)")
dim_of = {g: (DIM.match(g).group(1) if DIM.match(g) else None) for g in wanted}
# alias family: strip the 8-hex statement hash the aliaser mints
HASHRE = re.compile(r"_[0-9a-f]{8}_")
fam_of = {g: HASHRE.sub("_#_", g) for g in wanted}
families = defaultdict(set)
for g, f in fam_of.items():
    families[f].add(g)

files = sorted(glob.glob(os.path.join(HERE, f"dump_*{TAG}*.json")))
print(f"drive dumps: {len(files)}", flush=True)

# 2026-09-14 NAME-BOUNDARY FIX (concolic_engine.names) -- same defect as
# `_gc_realise.py`, and worse here: the gates dropped by the silent miss were
# also missing from `honoured`, which is the conjunction PREFIX the "never"
# test runs against. A prefix short its length conditions matches a strictly
# LARGER set of corpus runs, so `nb` was inflated and pairs were classified
# REACHABLE that are not. 11 of the 44 gate decisions in the emit file are
# `SYM_LEN_*`; every one of them was invisible.
XBOUND = Counter()
per = Counter()
pairs = Counter()                 # (g, P) -> unevaluated events
bucket = Counter()                # first-match bucket per unevaluated event
errkinds = Counter()
t0 = time.time()
for n, fp in enumerate(files):
    if n and n % 4000 == 0:
        print(f"  [{n}/{len(files)}] {time.time()-t0:.0f}s", flush=True)
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    amap = canonicalize_ordinals(d)
    seeds = d.get("concolic_seeds") or {}
    NS = NameSpace(seeds, name="dump concolic_seeds", alias_map=amap)
    err = d.get("error") or (d.get("terminal") or {}).get("error") if isinstance(d.get("terminal"), dict) else d.get("error")
    obs = defaultdict(set)
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            obs[str(e.get("expr", ""))].add(bool(e.get("taken")))
    OBS = NameSpace(obs, name="observed path conditions", alias_map=amap)
    state = {}
    for g in wanted:
        dv = dim_of[g]
        if not dv:
            continue
        sv = NS.resolve(dv)
        if sv is None:
            continue                      # genuinely not seeded in this run
        if dv not in seeds:
            XBOUND["seed key reached only across the name boundary"] += 1
        o = OBS.resolve(g)
        if o and g not in obs:
            XBOUND["observed PC reached only across the name boundary"] += 1
        if not o:
            state[g] = ("UNEVALUATED", bool(sv))
        elif bool(sv) in o:
            state[g] = ("REALISED", bool(sv))
        else:
            state[g] = ("CONTRADICTED", bool(sv))
    for g, (st, sv) in state.items():
        per[st] += 1
    honoured = tuple(sorted((g, sv) for g, (st, sv) in state.items() if st == "REALISED"))
    for g, (st, sv) in state.items():
        if st != "UNEVALUATED":
            continue
        if err:
            bucket["RENDER-ERROR"] += 1
            errkinds[str(err)[:60]] += 1
            continue
        sibs = families[fam_of[g]] - {g}
        if any(s in obs for s in sibs):
            bucket["ALIAS"] += 1
            continue
        pairs[(g, honoured)] += 1
    del d
print(f"\n=== GATE OUTCOMES, DRIVE {TAG} ===")
for k, v in per.most_common():
    print(f"  {k:14s} {v}")
print(f"\nUNEVALUATED events bucketed early: "
      f"RENDER-ERROR {bucket['RENDER-ERROR']}  ALIAS {bucket['ALIAS']}")
for k, v in errkinds.most_common(6):
    print(f"    error: x{v:<6} {k}")
print(f"distinct (unevaluated gate, honoured-prefix) pairs to test: {len(pairs)} "
      f"covering {sum(pairs.values())} events", flush=True)

top = pairs.most_common(MAXPAIRS)
print(f"testing the top {len(top)} pairs ({sum(n for _, n in top)} events, "
      f"{100.0*sum(n for _,n in top)/max(1,sum(pairs.values())):.1f} % of the class)")

need = set()
for (g, P), _n in top:
    need.add(g)
    for x, _w in P:
        need.add(x)
DL = os.environ["DUMP_LIST"]
dumps = [l.strip() for l in open(DL) if l.strip()]
print(f"indexing {len(dumps)} corpus dumps for {len(need)} expressions", flush=True)
pol, ev = {}, {}
t0 = time.time()
for i, fp in enumerate(dumps):
    if i and i % 8000 == 0:
        print(f"   [{i}/{len(dumps)}] {time.time()-t0:.0f}s", flush=True)
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    canonicalize_ordinals(d)
    b = 1 << i
    o = defaultdict(set)
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            x = str(e.get("expr", ""))
            if x in need:
                o[x].add(bool(e.get("taken")))
    for x, os_ in o.items():
        ev[x] = ev.get(x, 0) | b
        for w in os_:
            pol[(x, w)] = pol.get((x, w), 0) | b
    del d
print(f"   indexed in {time.time()-t0:.0f}s", flush=True)

cls = Counter(); events = Counter(); examples = defaultdict(list)
for (g, P), n in top:
    match = None
    for x, w in P:
        mm = pol.get((x, bool(w)), 0)
        match = mm if match is None else (match & mm)
        if not match:
            break
    nm = bin(match).count("1") if match else 0
    if nm == 0:
        cls["NO-MATCH"] += 1; events["NO-MATCH"] += n
        examples["NO-MATCH"].append((n, len(P), g)); continue
    nb = bin(match & ev.get(g, 0)).count("1")
    k = "CONJUNCTION-FORECLOSURE" if nb == 0 else "REACHABLE"
    cls[k] += 1; events[k] += n
    examples[k].append((n, nm, nb, g))
print("\n=== §16b's 'never' test, applied to the honoured-prefix CONJUNCTION ===")
for k in ("CONJUNCTION-FORECLOSURE", "REACHABLE", "NO-MATCH"):
    print(f"  {k:26s} pairs {cls[k]:>5}   unevaluated events {events[k]:>8}")
for k in ("REACHABLE", "CONJUNCTION-FORECLOSURE"):
    print(f"\n  top {k}:")
    for t in sorted(examples[k], reverse=True)[:6]:
        print(f"    {t}")
json.dump({"per": dict(per), "bucket": dict(bucket),
           "pairs_tested": len(top), "classes": dict(cls), "events": dict(events),
           "errkinds": errkinds.most_common(12)},
          open(os.path.join(HERE, "_unev_why.json"), "w"), indent=1)
if XBOUND:
    print("\n=== NAME-BOUNDARY CROSSINGS (would have been silent misses) ===")
    for k, v in XBOUND.most_common():
        print(f"  {k:52s} {v}")
print("\nUNEV WHY DONE")
