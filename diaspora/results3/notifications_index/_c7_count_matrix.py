#!/usr/bin/env python3
"""C7 per-request statement COUNT MATRIX — corpus vs a real run.

Two rules this implements deliberately (DISCIPLINE 14):
  * PRESENCE is a GLOBAL question: "can the corpus produce this shape at all"
    is asked against the WHOLE corpus, never against one request class. A7-8
    cost a round by scoping it.
  * MULTIPLICITY is a SCOPED question: only over-emission compares like with
    like, and a request class with no ground-truth run is SKIPPED, never given
    a verdict inferred from the gap.
It also names the evidence it read (§15: a judge that ignores what you hand it
prints a green about nothing) and states every population.

usage: _c7_count_matrix.py <batch> --runs <run.json> [<run.json> ...]
                           [--scenario-map name=RUNNAME ...]
"""
import glob, json, os, re, sys, collections

def norm(sql):
    s = re.sub(r"\s+", " ", str(sql).strip())
    s = re.sub(r"\$\$\([^)]*\)", "?", s)      # corpus $$(VAR) binds
    s = re.sub(r"\$\d+", "?", s)
    s = s.replace("?", "?")
    s = re.sub(r"'[^']*'", "?", s)
    s = re.sub(r"\btrue\b|\bfalse\b", "?", s, flags=re.I)
    s = re.sub(r"\b\d+\b", "?", s)
    s = re.sub(r"\(\s*\?(\s*,\s*\?)*\s*\)", "(?)", s)   # IN (?,?,?) -> IN (?)
    return s

def is_sql(n):
    return bool(re.match(r"^\s*(SELECT|INSERT|UPDATE|DELETE|WITH)\b", str(n), re.I))

batch = sys.argv[1]
runs = []
if "--runs" in sys.argv:
    for a in sys.argv[sys.argv.index("--runs")+1:]:
        if a.startswith("--"): break
        runs.append(a)
if not runs:
    print("ERROR: no --runs given. This judge names the evidence it reads and "
          "refuses to fall back to anything else."); sys.exit(2)

print("judging runs:")
gt = {}          # scenario label -> Counter of shapes
for r in runs:
    if not os.path.exists(r):
        print(f"  ERROR unreadable: {r}"); sys.exit(2)
    data = json.load(open(r))
    entries = data if isinstance(data, list) else [data]
    for e in entries:
        c = collections.Counter()
        for s in e.get("statements") or []:
            sql = s["sql"] if isinstance(s, dict) else str(s)
            c[norm(sql)] += 1
        gt[f"{os.path.basename(r)}::{e.get('name')}"] = c
        print(f"  {r} :: {e.get('name')}  ({sum(c.values())} statements, {len(c)} shapes)")

files = sorted(glob.glob(os.path.join(batch, "dump_*.json")))
print(f"\ncorpus POPULATION: {len(files)} dump files (whole corpus, no sampling)")
corpus_global = collections.Counter()          # shape -> events
corpus_dumps  = collections.Counter()          # shape -> dumps
per_variant_max = collections.defaultdict(collections.Counter)   # variant -> shape -> max per dump
variant_dumps = collections.Counter()
for p in files:
    try: d = json.load(open(p))
    except Exception: continue
    v = (d.get("concolic_scenario") or {}).get("name") or "<none>"
    variant_dumps[v] += 1
    per_dump = collections.Counter()
    # DEDUPE THE PROBE PAIR (fixed 2026-09-01, C7; the first version of this
    # judge over-counted every exists?-family statement by exactly 2x and
    # reported a `roles` over-emission that does not exist).
    # A through-load probe emits `Anonymous.load_intermediate` carrying the
    # statement, and the real target event that follows carries the SAME note —
    # one statement, two events. Verified by tracing a single run: the rig calls
    # Role.is_admin? / Role.moderator? exactly ONCE each, matching the real
    # request, while the corpus recorded four `FROM "roles"` notes.
    # A `load_intermediate` whose note is NOT repeated by the next symbolic_call
    # is a preload step in its own right and still counts.
    evs = [e for e in (d.get("events") or []) if e.get("type") == "symbolic_call"]
    for i, ev in enumerate(evs):
        n = ev.get("note")
        if not n or not is_sql(n): continue
        key = norm(n)
        if str(ev.get("target", "")).endswith("load_intermediate"):
            nxt = evs[i+1] if i + 1 < len(evs) else None
            if nxt is not None and not str(nxt.get("target", "")).endswith("load_intermediate") \
               and nxt.get("note") and norm(nxt["note"]) == key:
                continue      # the paired target event will count it
        per_dump[key] += 1
    for k, c in per_dump.items():
        corpus_global[k] += c
        corpus_dumps[k]  += 1
        if c > per_variant_max[v][k]: per_variant_max[v][k] = c
print(f"corpus variants: {dict(variant_dumps)}")
print(f"corpus distinct SQL shapes: {len(corpus_global)}\n")

# ---- PRESENCE (global) ----
all_gt = collections.Counter()
for c in gt.values(): all_gt.update(c)
missing = [k for k in all_gt if k not in corpus_global]
print(f"== PRESENCE (global: the WHOLE corpus vs the union of all ground-truth runs) ==")
print(f"   ground-truth distinct shapes: {len(all_gt)}   MISSING FROM CORPUS: {len(missing)}")
for k in sorted(missing): print(f"     MISSING  {k[:160]}")

extra = [k for k in corpus_global if k not in all_gt]
print(f"\n   corpus shapes with NO ground-truth counterpart: {len(extra)}"
      f"   (over-emission candidates; a shape only some scenario issues is not one)")
for k in sorted(extra)[:40]: print(f"     EXTRA    x{corpus_global[k]:<7} {k[:150]}")
if len(extra) > 40: print(f"     ... and {len(extra)-40} more")

# ---- MULTIPLICITY (scoped) ----
print(f"\n== MULTIPLICITY (scoped; corpus MAX per dump vs the run's count) ==")
for label, c in gt.items():
    print(f"\n-- {label} --")
    # SCOPE THE COMPARISON (fixed 2026-09-01, C7). The first version took the
    # max across ALL variants and compared it to ONE variant's ground truth, so
    # the mobile drawer's legitimate second `roles` read was reported as an
    # over-emission against the html run. "Only over-emission compares like
    # with like" was quoted in this file's own docstring and then not
    # implemented — exactly the failure DISCIPLINE 14 records.
    fam = "mobile" if "mobile" in label.lower() else \
          "html"   if "html"   in label.lower() else \
          "json"   if "json"   in label.lower() else \
          "xml"    if "xml"    in label.lower() else None
    vs = [v for v in per_variant_max if v != "<none>" and (fam is None or v.startswith(fam))]
    if not vs:
        print(f"   SKIPPED: corpus has no '{fam}' variant to compare "
              f"(a class with no counterpart is skipped, never given a verdict "
              f"inferred from the gap)"); continue
    print(f"   corpus variants compared: {sorted(vs)}")
    over, under = [], []
    for k, want in sorted(c.items()):
        got = max((per_variant_max[v][k] for v in vs), default=0)
        if got > want: over.append((k, got, want))
        elif got < want: under.append((k, got, want))
    print(f"   shapes judged: {len(c)}   UNDER: {len(under)}   OVER: {len(over)}")
    for k, got, want in under: print(f"     UNDER corpus_max={got} real={want}  {k[:140]}")
    for k, got, want in over:  print(f"     OVER  corpus_max={got} real={want}  {k[:140]}")

print("\nNOTE (M-18 / T-ae): these ground-truth counts come from "
      "ActionController::TestCase#process, which does NOT run "
      "ActionDispatch::Executor, so AR's query cache never engages. They are an "
      "UPPER BOUND on a real Rack request, not a production count. Shape "
      "PRESENCE is unaffected.")
