#!/usr/bin/env python3
"""Bulk DIVERSE seeds, v3 — vary every DECISION dimension. PORT of
notifications_index/_diverse_seeds3.py (v3.1) for people_stream, 2026-09-10.

Why v3 exists (notifications, _COMPLETION_CAMPAIGN_20260910.md §4): the old
seeder assigned only the `len(...)` keys, so EVERY boolean dispatch dimension
stayed at its default in every "diverse" run — and that is exactly where the
`tree_missing` branch outcomes live. The seeder, not the app, was the
constraint on tree completeness.

What this port carries over from the notifications repairs:

  * **universe from `symbolic_vars`, not `concolic_seeds`** (§6.1). Every dump
    carries `symbolic_vars`; only some carry seeds, so a seeds-derived domain
    is degenerate (`['']`) and seeds keys that are DERIVED or harness-owned.
  * **the STRIDE fix** (§7.3(b)). v3.1's universe was built at stride 120 and
    MISSED a variable minted in 3 dumps of 109 401, so a whole tree_missing
    target was unreachable BY CONSTRUCTION. Here the stride ADAPTS: the whole
    corpus is scanned unless it exceeds `--max-scan` (default 20 000), and the
    scan prints how many dumps each dimension was seen in, with a RARE list
    for anything minted in < 5 — a variable in that list is one a coarser
    stride would have lost.
  * **`SYM_PARAM_*` is a REAL dimension** (§7.5). v3.1 deny-listed it
    wholesale after blaming it for a JVM abort that §7.4 later reattributed to
    the discovery arm, and that cost a whole dimension: the first rooted
    attempt at a branch drove 19 runs against the wrong statement alias
    because the parameter had been stripped. This port therefore VARIES this
    endpoint's request parameters over the values the CORPUS has produced for
    them (plus `''`), and prints the domain it derived.
  * DENY-list for derived / identity keys (`*_type` is derived from an STI
    profile; `*_guid` / `*_id` / `*_diaspora_handle` are identities), applied
    to inherited templates too so a stale override cannot be smuggled back in.

usage: _v3_seeds.py [N] [out.json] [--stride K] [--max-scan M] [--rebuild]
                    [--census]        # census only: build nothing, print the
                                      # dimensions and what the OLD seeder varied
"""
import glob, json, os, random, re, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "_seed_universe3.json")
args = [a for a in sys.argv[1:] if not a.startswith("--")]
N = int(args[0]) if args else 6000
OUT = args[1] if len(args) > 1 else os.path.join(HERE, "_v3_seeds.json")


def _flag(name, default):
    for i, a in enumerate(sys.argv):
        if a == name:
            return int(sys.argv[i + 1])
    return default


STRIDE = _flag("--stride", 0)          # 0 = adaptive (see below)
MAX_SCAN = _flag("--max-scan", 20000)
REBUILD = "--rebuild" in sys.argv
CENSUS = "--census" in sys.argv
random.seed()

LEN_DOM = [0, 1, 2, 4]
CNT_DOM = [0, 1, 2, 4]
P_EMPTY = 0.15
EMPTYABLE = ("_username", "_first_name", "_last_name", "_text", "_name")
CNT_SUF = ("_size", "_count", "_sum")
DENY_SUF = ("_type", "_guid", "_diaspora_handle", "_id", "_person_id",
            "_birthday_year")
DENY_SUB = ("set_rendered_content_type", "_plucked")

# --- THIS ENDPOINT'S REQUEST PARAMETERS (the SYM_PARAM_show lesson) --------
# Genuine symbolic request parameters, owned by run_dse.rb and seeded through
# `ConcolicTargets.seed_for`. They are DIMENSIONS, not harness bookkeeping, so
# they are varied — over the values the corpus itself recorded for them, never
# over invented ones. `_param_domains()` derives that below.
PARAMS = ("SYM_PARAM_person_id", "SYM_PARAM_username")
# run_dse.rb:157/159 — the value used when the seed dict omits the key, so
# it is part of the dimension even though it never appears in a seed dict.
PARAM_DEFAULTS = {"SYM_PARAM_person_id": "1",
                  "SYM_PARAM_username": "bob@example.org"}
# Branch outcomes proven UNREACHABLE in this environment (a witness, e.g. a
# native abort that destroys the dump before it is written). Seeding one wastes
# the run, so any seed that would assign it is dropped and COUNTED. EMPTY for
# this endpoint: no such witness has been established. Add (key, value) pairs
# with the evidence in the comment, never on suspicion.
PIN_OFF = {}


def denied(n):
    # A request PARAMETER is a dimension, never a denied identity key — and it
    # would otherwise be caught by the `_id` / `_person_id` suffixes, which is
    # exactly the SYM_PARAM_show mistake in miniature.
    if n in PARAMS:
        return False
    return (n in PARAMS_DENY or n.endswith(DENY_SUF)
            or any(s in n for s in DENY_SUB))


EXTRA_INT_DIMS = {}   # no STI / note-type profile dimension here
PARAMS_DENY = set()          # SYM_PARAM_* keys that are NOT dimensions here


def build_universe():
    bools, lens, cnts, empt = Counter(), Counter(), Counter(), Counter()
    params = {}
    files = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
    stride = STRIDE or max(1, (len(files) + MAX_SCAN - 1) // MAX_SCAN)
    used = files[::stride]
    for p in used:
        try:
            d = json.load(open(p))
        except Exception:
            continue
        for sv in d.get("symbolic_vars") or ():
            n, s = sv.get("name") or "", sv.get("sort")
            if not n:
                continue
            if n in PARAMS:
                continue
            if denied(n):
                continue
            if s == "Bool":
                bools[n] += 1
            elif n.startswith("len("):
                lens[n] += 1
            elif s == "Int" and n.endswith(CNT_SUF):
                cnts[n] += 1
            elif s == "String" and n.endswith(EMPTYABLE):
                empt[n] += 1
        for k, v in (d.get("concolic_seeds") or {}).items():
            if k in PARAMS and isinstance(v, str):
                params.setdefault(k, Counter())[v] += 1
    rare = sorted(n for c in (bools, lens, cnts, empt) for n, k in c.items() if k < 5)
    u = {"bools": sorted(bools), "lens": sorted(lens),
         "counts": sorted(cnts), "emptyable": sorted(empt),
         "params": {k: sorted(c) for k, c in params.items()},
         "mint_counts": {n: k for c in (bools, lens, cnts, empt)
                         for n, k in c.items()},
         "rare": rare, "dumps": len(used), "stride": stride,
         "population": len(files)}
    json.dump(u, open(CACHE, "w"), indent=1)
    return u


U = build_universe() if (REBUILD or CENSUS or not os.path.exists(CACHE)) \
    else json.load(open(CACHE))
DIMS = (len(U["bools"]) + len(U["lens"]) + len(U["counts"])
        + len(U["emptyable"]) + len(PARAMS) + len(EXTRA_INT_DIMS))
print(f"seed universe: {len(U['bools'])} bool, {len(U['lens'])} len, "
      f"{len(U['counts'])} count, {len(U['emptyable'])} emptyable-string, "
      f"{len(PARAMS)} request-param, {len(EXTRA_INT_DIMS)} explicit-int "
      f"= {DIMS} DIMENSIONS "
      f"(scanned {U['dumps']} of {U.get('population', '?')} dumps, stride {U['stride']})")
if U.get("rare"):
    print(f"  RARE (minted in < 5 scanned dumps — a coarser stride LOSES these): "
          f"{len(U['rare'])}")
    for n in U["rare"][:20]:
        print(f"    {U['mint_counts'].get(n)}x  {n}")
for k in PARAMS:
    print(f"  request param {k}: corpus domain {U['params'].get(k, [])} "
          f"+ runner default {PARAM_DEFAULTS.get(k)!r} + ''")


# --- what the OLD seeder varied, for the census ---------------------------
OLD = os.path.join(HERE, "_diverse_seeds2.py")
old_keys = set()
if os.path.exists(OLD):
    _src = open(OLD).read()
    old_keys = set(re.findall(r"[\"']((?:SYM_|len\()[^\"']+)[\"']", _src))
print(f"OLD seeder ({os.path.basename(OLD) if os.path.exists(OLD) else 'NONE ON DISK'}): "
      f"{len(old_keys)} literal keys named")

# The honest OLD-vs-NEW comparison is over the corpus's own seed dicts: which
# of this endpoint's dimensions ever took more than ONE value in the corpus.
files = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
stride = U["stride"]
vals = {}
for p in files[::stride]:
    try:
        s = (json.load(open(p)) or {}).get("concolic_seeds") or {}
    except Exception:
        continue
    for k, v in s.items():
        vals.setdefault(k, set()).add(json.dumps(v, default=str))
ALLDIMS = (list(U["bools"]) + list(U["lens"]) + list(U["counts"])
           + list(U["emptyable"]) + list(PARAMS) + list(EXTRA_INT_DIMS))
varied = [k for k in ALLDIMS if len(vals.get(k, ())) > 1]
seeded_at_all = [k for k in ALLDIMS if k in vals]
print(f"DIMENSION CENSUS: {len(ALLDIMS)} dimensions the v3 seeder varies; "
      f"the corpus's EXISTING seeds vary {len(varied)} of them "
      f"({len(seeded_at_all)} appear in a seed dict at all, at any value)")
bykind = [("bool", U["bools"]), ("len", U["lens"]), ("count", U["counts"]),
          ("emptyable-string", U["emptyable"]), ("request-param", list(PARAMS)),
          ("explicit-int", list(EXTRA_INT_DIMS))]
for kind, ks in bykind:
    v = sum(1 for k in ks if len(vals.get(k, ())) > 1)
    print(f"   {kind:18s} {v:4d} varied / {len(ks):4d} dimensions")
if CENSUS:
    sys.exit(0)

templates = []
for p in files[::stride]:
    try:
        s = (json.load(open(p)) or {}).get("concolic_seeds") or {}
    except Exception:
        continue
    if s:
        templates.append({k: v for k, v in s.items()
                          if not denied(k) and k not in PARAMS})
print(f"{len(templates)} seed templates (stride {stride} over {len(files)} dumps)")
if not templates:
    print("NO TEMPLATES — the corpus records no concolic_seeds; "
          "run the runner port first"); sys.exit(1)

out, seen, dropped = [], set(), 0
for _ in range(N * 4):
    if len(out) >= N:
        break
    t = dict(random.choice(templates))
    for k in U["bools"]:
        t[k] = random.choice((True, False))
    for k in U["lens"]:
        t[k] = random.choice(LEN_DOM)
    for k in U["counts"]:
        t[k] = random.choice(CNT_DOM)
    for k in U["emptyable"]:
        if random.random() < P_EMPTY:
            t[k] = ""
    for k in PARAMS:
        dom = U["params"].get(k, [])
        d = sorted(set(dom) | {"", PARAM_DEFAULTS.get(k, "")})
        t[k] = random.choice(d)
    for k, dom in EXTRA_INT_DIMS.items():
        t[k] = random.choice(dom)
    if any(t.get(k) == v for k, v in PIN_OFF.items()):
        dropped += 1
        continue
    for k, v in PIN_OFF.items():
        t.pop(k, None)
    key = json.dumps(t, sort_keys=True, default=str)
    if key in seen:
        continue
    seen.add(key)
    out.append(t)
if "--dry-run" in sys.argv:
    print(f"DRY RUN: built {len(out)} seeds IN MEMORY, wrote nothing "
          f"({dropped} dropped by PIN_OFF)")
else:
    json.dump(out, open(OUT, "w"))
    print(f"wrote {len(out)} v3 seeds -> {OUT} ({dropped} dropped by PIN_OFF)")
bl = Counter(v for s in out for v in s.values() if isinstance(v, bool))
print(f"bool spread {dict(bl)}; keys/seed {len(out[0]) if out else 0}; "
      f"no denied keys: {not any(denied(k) for s in out for k in s)}")
