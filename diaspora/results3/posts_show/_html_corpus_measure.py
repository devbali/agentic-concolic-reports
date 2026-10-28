#!/usr/bin/env python3
"""§48 — is the PRE-W7 html corpus evidence of the html arm?

Every html dump written before the §46 (W7) render repair is crash-truncated:
it terminates in ActionView::Template::Error (or, after §14 and before W7, in
NotImplementedError SymbolicString#scrub) somewhere inside the view. Under
DISCIPLINE §16b a partial walk blocks only a CLOSED PREFIX, so such a dump is
never harmful — it contributes its own profile like any other run and nothing
is retracted. But it is not evidence of the html ARM either.

This measures both halves, through the ENGINE'S OWN LOAD PATH
(canonicalize_ordinals + fix_len_names), never a raw read:

  (a) how many html dumps and how many DISTINCT html outcome profiles exist
      post-fix vs pre-fix;
  (b) whether the pre-fix html dumps contribute any (evaluation SET, outcome
      CUBE) that the post-fix html dumps do not.

The fix boundary is the mtime of `targets.rb.pre_htmlrender`, the copy taken
immediately before the W7 edit — an objective timestamp, not a label guess.
Nothing is deleted.

usage: DUMP_LIST=<snapshot> _html_corpus_measure.py [--boundary <path>]
"""
import glob, hashlib, json, os, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals, fix_len_names  # noqa: E402

BOUND_FILE = (sys.argv[sys.argv.index("--boundary") + 1]
              if "--boundary" in sys.argv
              else os.path.join(HERE, "targets.rb.pre_htmlrender"))
BOUND = os.path.getmtime(BOUND_FILE)

_list = os.environ.get("DUMP_LIST")
if _list:
    dumps = sorted(l.strip() for l in open(_list) if l.strip())
    dumps = [d if os.path.isabs(d) else os.path.join(HERE, d) for d in dumps]
else:
    dumps = sorted(glob.glob(os.path.join(HERE, "dump_*.json")))
print(f"boundary: {os.path.basename(BOUND_FILE)} mtime={BOUND:.0f}")
print(f"population: {len(dumps)} dumps")

# class -> counters
n_by = Counter()
term_by = Counter()
cubes = defaultdict(set)     # class -> {profile digest}
sets_ = defaultdict(set)     # class -> {evaluation-set digest}
cube_owner = {}              # digest -> example path (pre-fix html only)
set_owner = {}

for i, p in enumerate(dumps):
    try:
        d = json.load(open(p))
    except Exception:
        n_by["unparseable"] += 1
        continue
    lbl = d.get("label") or os.path.basename(p)
    scen = "html" if "_html" in lbl else ("json" if "_json" in lbl else "other")
    era = "post" if os.path.getmtime(p) > BOUND else "pre"
    cls = f"{scen}-{era}"
    n_by[cls] += 1
    err = (d.get("error") or {}).get("type") or "<ok>"
    term_by[(cls, err)] += 1
    canonicalize_ordinals(d)
    d = fix_len_names(d)
    acc = {}
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            acc.setdefault(e["expr"], set()).add(bool(e.get("taken")))
    ck = hashlib.blake2b(
        ";".join(f"{k}:{''.join('1' if v else '0' for v in sorted(acc[k]))}"
                 for k in sorted(acc)).encode(), digest_size=16).hexdigest()
    sk = hashlib.blake2b("\x00".join(sorted(acc)).encode(),
                         digest_size=16).hexdigest()
    cubes[cls].add(ck)
    sets_[cls].add(sk)
    if cls == "html-pre":
        cube_owner.setdefault(ck, p)
        set_owner.setdefault(sk, p)
    del d
    if i % 20000 == 19999:
        print(f"  ... {i+1}/{len(dumps)}", flush=True)

print("\n== POPULATION BY CLASS ==")
for k in sorted(n_by):
    print(f"  {k:16s} {n_by[k]:7d} dumps   distinct cubes {len(cubes[k]):6d}   "
          f"distinct eval-sets {len(sets_[k]):5d}")
print("\n== TERMINALS BY CLASS ==")
for (k, e), v in sorted(term_by.items()):
    print(f"  {k:16s} {e:34s} {v:7d}")

only_c = cubes["html-pre"] - cubes["html-post"]
only_s = sets_["html-pre"] - sets_["html-post"]
print("\n== (a) POST-FIX vs PRE-FIX html ==")
print(f"  html-pre  dumps {n_by['html-pre']:7d}  cubes {len(cubes['html-pre']):6d}  sets {len(sets_['html-pre']):5d}")
print(f"  html-post dumps {n_by['html-post']:7d}  cubes {len(cubes['html-post']):6d}  sets {len(sets_['html-post']):5d}")
print("\n== (b) DOES THE PRE-FIX HTML CORPUS CONTRIBUTE ANYTHING THE POST-FIX ONE DOES NOT? ==")
print(f"  cubes ONLY in pre-fix html : {len(only_c)}")
print(f"  eval-SETS ONLY in pre-fix html: {len(only_s)}")
for s in list(only_s)[:5]:
    print(f"     e.g. {os.path.basename(set_owner[s])}")
also = cubes["html-pre"] - cubes["html-post"] - cubes["json-pre"] - cubes["json-post"]
print(f"  cubes only in pre-fix html AND in no json dump either: {len(also)}")
print(f"\nVERDICT_PREFIX_HTML_UNIQUE_CUBES={len(only_c)} "
      f"UNIQUE_SETS={len(only_s)}")
