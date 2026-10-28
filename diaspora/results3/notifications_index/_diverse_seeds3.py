#!/usr/bin/env python3
"""Bulk DIVERSE seeds, v3.1 (2026-09-10) — vary every DECISION dimension.

Why v3 exists. Census of this corpus: 146 distinct `concolic_seeds` keys, of
which `_diverse_seeds2.py` assigns 22 `len(...)` keys and re-rolls 2 STI ints.
**Every one of the ~86 boolean dispatch dimensions stays at its default in
every "diverse" run** — `_not_found`, `_persisted`, `_text_has_dlink`,
`_text_dlink_is_post`, `_mention_inline_name`, `_disp_has_dlink`, `_text_nil`,
`_target_is_photo` — and all 13 `tree_missing` branch outcomes live in that
untouched set. Measured on the first 1 200 v3 runs: `*_not_found` went from
7-true / 2 696-false (corpus-wide, for `find_by_1`) to 480 / 433, and the
never-observed not-taken sides of `_text_dlink_is_post` and
`_mention_inline_name` appeared immediately. The seeder, not the app, was the
constraint.

**v3.0 was withdrawn and this is its replacement.** v3.0 built each key's
domain by sampling `concolic_seeds`, which only a minority of dumps carry, so
its string domains were degenerate (`['']`) and — worse — it seeded keys that
are DERIVED or that belong to the harness:

  * `SYM_PARAM_show` is the REQUEST VARIANT and is owned by `VARIANTS`.
    Setting it to `''` desynchronises the runner's own bookkeeping; seed #119
    of `_diverseR3.json` was the first with `SYM_PARAM_show: ""` and six of
    seven variants took a **JVM abort at run 119** (`free(): invalid pointer`;
    `hs_err_pid*.log` in the app dir — a pre-existing abort class, cf. the
    Aug 25/27/30 files, not something v3 introduced).
  * `..._row_type` is DERIVED from `SYM_NOTE_TYPE_PROFILE`. Pinning it to one
    STI class while the profile says another is an inconsistent state: the one
    variant that survived logged `I18n::InvalidLocale` on 2 967 of 6 000 runs.

So v3.1 uses an explicit ALLOW-LIST of decision dimensions and an explicit
DENY-LIST of derived / identity / harness keys, and it takes its universe from
`symbolic_vars` (present in EVERY dump) rather than from `concolic_seeds`.

  VARY   every Bool var (the seedable dispatch decisions)
         every `len(...)` var                    -> {0, 1, 2, 4}
         SYM_NOTE_TYPE_PROFILE -> 0..8, SYM_POST_STI -> 0..2
           (the top value is the out-of-range defensive default, a real
            observed state -- _COMPLETION_CAMPAIGN_20260910.md §1.2)
         `*_size` / `*_count` / `*_sum`          -> {0, 1, 2, 4}
           (`Relation_size_2_size > 0 :: not_taken` is a tree_missing target)
         `*_username` / `*_first_name` / `*_last_name` -> '' at p=0.15
           (`== StringVal('')` is a tree_missing target)
  NEVER  SYM_PARAM_*, *_type, *_guid, *_diaspora_handle, *_id, *_person_id,
         *_birthday_year, the render/pluck probes, and anything not named above

usage: _diverse_seeds3.py [N] [out.json] [--stride K] [--rebuild]
"""
import glob, json, os, random, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "_seed_universe3.json")
args = [a for a in sys.argv[1:] if not a.startswith("--")]
N = int(args[0]) if args else 6000
OUT = args[1] if len(args) > 1 else os.path.join(HERE, "_diverseR3.json")
STRIDE = 40
for i, a in enumerate(sys.argv):
    if a == "--stride": STRIDE = int(sys.argv[i + 1])
REBUILD = "--rebuild" in sys.argv
random.seed()

LEN_DOM = [0, 1, 2, 4]
CNT_DOM = [0, 1, 2, 4]
P_EMPTY = 0.15
RARE_TRUE = ("_stale_language",)
P_RARE_TRUE = 0.02
EMPTYABLE = ("_username", "_first_name", "_last_name")
CNT_SUF = ("_size", "_count", "_sum")
DENY_SUF = ("_type", "_guid", "_diaspora_handle", "_id", "_person_id",
            "_birthday_year")
DENY_SUB = ("set_rendered_content_type", "_plucked")


def denied(n):
    return (n.startswith("SYM_PARAM_") or n.endswith(DENY_SUF)
            or any(s in n for s in DENY_SUB))


def build_universe():
    bools, lens, cnts, empt = set(), set(), set(), set()
    files = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
    used = files[::STRIDE]
    for p in used:
        try:
            d = json.load(open(p))
        except Exception:
            continue
        for sv in d.get("symbolic_vars") or ():
            n, s = sv.get("name") or "", sv.get("sort")
            if not n or denied(n):
                continue
            if s == "Bool":
                bools.add(n)
            elif n.startswith("len("):
                lens.add(n)
            elif s == "Int" and n.endswith(CNT_SUF):
                cnts.add(n)
            elif s == "String" and n.endswith(EMPTYABLE):
                empt.add(n)
    u = {"bools": sorted(bools), "lens": sorted(lens),
         "counts": sorted(cnts), "emptyable": sorted(empt),
         "dumps": len(used), "stride": STRIDE}
    json.dump(u, open(CACHE, "w"))
    return u


U = build_universe() if (REBUILD or not os.path.exists(CACHE)) else json.load(open(CACHE))
print(f"seed universe: {len(U['bools'])} bool, {len(U['lens'])} len, "
      f"{len(U['counts'])} count, {len(U['emptyable'])} emptyable-string "
      f"(from {U['dumps']} dumps)")

templates = []
files = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
for p in files[::STRIDE]:
    try:
        s = (json.load(open(p)) or {}).get("concolic_seeds") or {}
    except Exception:
        continue
    if s:
        # inherit CONTEXT only: strip every key this build owns, and every
        # key on the deny-list, so a template can never smuggle a stale
        # SYM_PARAM_show / _row_type override back in.
        templates.append({k: v for k, v in s.items() if not denied(k)})
print(f"{len(templates)} seed templates (stride {STRIDE} over {len(files)} dumps)")
if not templates:
    sys.exit(1)

out, seen = [], set()
for _ in range(N * 4):
    if len(out) >= N:
        break
    t = dict(random.choice(templates))
    for k in U["bools"]:
        # RARE_TRUE (2026-09-10, measured): `..._stale_language == True` sets an
        # invalid locale and the request dies at i18n before anything else is
        # decided -- 422 of 422 probe runs with it True raised
        # `I18n::InvalidLocale`, 0 of 378 with it False. It is a real decision
        # and stays in the domain, but at 1/2 it burned half the campaign's
        # runs on a two-decision path. p=0.02 keeps it exercised.
        t[k] = (random.random() < P_RARE_TRUE) if k.endswith(RARE_TRUE) \
            else random.choice((True, False))
    for k in U["lens"]:
        t[k] = random.choice(LEN_DOM)
    for k in U["counts"]:
        t[k] = random.choice(CNT_DOM)
    for k in U["emptyable"]:
        if random.random() < P_EMPTY:
            t[k] = ""
    t["SYM_NOTE_TYPE_PROFILE"] = random.randint(0, 8)
    t["SYM_POST_STI"] = random.randint(0, 2)
    key = json.dumps(t, sort_keys=True, default=str)
    if key in seen:
        continue
    seen.add(key)
    out.append(t)
json.dump(out, open(OUT, "w"))
from collections import Counter
bl = Counter(v for s in out for v in s.values() if isinstance(v, bool))
print(f"wrote {len(out)} v3.1 seeds -> {OUT}; bool spread {dict(bl)}; "
      f"no SYM_PARAM_* / _type / _guid / _id keys: "
      f"{not any(denied(k) for s in out for k in s)}")
