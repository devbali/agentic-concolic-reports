"""THE RESIDUAL, CHARACTERISED (campaign §24 step 5 / §22(b)).

For every cube the exact enumerator still reports as remaining, say WHICH of
four things it is, measured on the corpus, on the CORRECTED canonical names
(statement-keyed photos, 441 nodes):

  CONJUNCTION-FORECLOSURE  some member `d` of the cube is never evaluated by
        ANY run that matches the cube's gate conjunction `P`, while runs DO
        match `P` (§16b's own "never" test lifted to the conjunction, §19).
        The engine cannot see it: its inference is pairwise.
  STRUCTURAL-UNMODELLED    the runs that match `P` end in the DECLARED-
        UNMODELLED federation-discovery boundary (POLICY_HEADER's terminal
        substitution: `first_name` / `as_api_response` on a nil profile) at a
        rate >= THRESH. The app itself 500s there; no seeding reaches past it.
  FAITHFUL-APP-ERROR       same, with the signature the APPLICATION also
        raises (`mentions_container` on a nil target, §22).
  REACHABLE-BUT-UNDRIVEN   some matching run evaluates every member and the
        matching runs mostly complete: nothing structural stands in the way,
        the corpus simply has not walked this assignment.
  (NO-RUN-MATCHES-P is reported separately: the gate combination itself is
   undriven, so the test cannot decide.)

Priority: foreclosure, then the two error classes, then no-match, then
undriven — and the full cross-tab is printed so nothing is hidden by the
priority order.

usage: REM=_remaining_after.jsonl DUMP_LIST=<pruned snapshot> \
       [THRESH=0.9] python3 -u _c11_residual.py
"""
import json, os, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals            # noqa: E402

REM = os.environ.get("REM", "_remaining_after.jsonl")
DL = os.environ["DUMP_LIST"]
THRESH = float(os.environ.get("THRESH", "0.9"))
OUT = os.environ.get("JSON_OUT", "_c11_residual.json")

# error signatures, from §22 (measured over 4 000 constructed dumps)
DECLARED_SIG = re.compile(r"first_name|as_api_response")
FAITHFUL_SIG = re.compile(r"mentions_container|linked_object")
GON_SIG = re.compile(r"gon_helper")

cubes = [json.loads(l) for l in open(os.path.join(HERE, REM))]
print(f"remaining cubes: {len(cubes)}", flush=True)

need = set()
for c in cubes:
    need.update(c["asg"])
    need.update(c.get("pre") or {})
print(f"expressions to index: {len(need)}", flush=True)

dumps = [l.strip() for l in open(DL) if l.strip()]
pol = {}          # (expr, outcome) -> bitmask over dumps
ev = {}           # expr -> bitmask
err_kind = []     # per dump: '', 'declared', 'faithful', 'gon', 'other'
t0 = time.time()
for i, fp in enumerate(dumps):
    if i and i % 20000 == 0:
        print(f"   [{i}/{len(dumps)}] {time.time()-t0:.0f}s", flush=True)
    try:
        d = json.load(open(fp))
    except Exception:
        err_kind.append("")
        continue
    e = d.get("error") or {}
    msg = f"{e.get('type','')} {e.get('message','')} {e.get('backtrace','')}"
    if not e:
        err_kind.append("")
    elif DECLARED_SIG.search(msg):
        err_kind.append("declared")
    elif FAITHFUL_SIG.search(msg):
        err_kind.append("faithful")
    elif GON_SIG.search(msg):
        err_kind.append("gon")
    else:
        err_kind.append("other")
    b = 1 << i
    canonicalize_ordinals(d)
    seen = defaultdict(set)
    for evt in d.get("events") or ():
        if evt.get("type") == "path_condition":
            ex = evt["expr"]
            if ex in need:
                seen[ex].add(bool(evt.get("taken")))
    for ex, outs in seen.items():
        ev[ex] = ev.get(ex, 0) | b
        for o in outs:
            pol[(ex, o)] = pol.get((ex, o), 0) | b
    del d
print(f"   indexed {len(dumps)} dumps in {time.time()-t0:.0f}s", flush=True)
print("   dump error census: " + str(dict(Counter(err_kind))), flush=True)

ERR_MASK = {k: 0 for k in ("", "declared", "faithful", "gon", "other")}
for i, k in enumerate(err_kind):
    ERR_MASK[k] |= 1 << i

cls = Counter()
cross = Counter()
rows = []
for c in cubes:
    pre = c.get("pre") or {}
    match = None
    for g, o in pre.items():
        m = pol.get((g, bool(o)), 0)
        match = m if match is None else (match & m)
        if not match:
            break
    if match is None:                      # no gates at all: every run matches
        match = (1 << len(dumps)) - 1
    n_match = bin(match).count("1") if match else 0
    forecl = [d_ for d_ in c["asg"] if n_match and not (match & ev.get(d_, 0))]
    if not n_match:
        kind = "NO-RUN-MATCHES-P"
        rates = {}
    else:
        rates = {k: bin(match & v).count("1") / n_match for k, v in ERR_MASK.items()}
        if forecl:
            kind = "CONJUNCTION-FORECLOSURE"
        elif rates["declared"] >= THRESH:
            kind = "STRUCTURAL-UNMODELLED"
        elif rates["faithful"] >= THRESH:
            kind = "FAITHFUL-APP-ERROR"
        elif rates["declared"] + rates["faithful"] + rates["gon"] + rates["other"] >= THRESH:
            kind = "ERRORED-MIXED"
        else:
            kind = "REACHABLE-BUT-UNDRIVEN"
    cls[kind] += 1
    cross[(kind, "err>=%.0f%%" % (100 * THRESH) if rates and
           sum(v for k, v in rates.items() if k) >= THRESH else "err<thresh")] += 1
    rows.append({"kind": kind, "matching_runs": n_match,
                 "foreclosed_members": forecl[:3], "rates": rates})

# ---- pair level, directly comparable with §19.1 --------------------------
pairs = {}
for c in cubes:
    key = tuple(sorted((c.get("pre") or {}).items()))
    for d_ in c["asg"]:
        pairs.setdefault((d_, key), 0)
        pairs[(d_, key)] += 1
pf = pr = pn = 0
prsamp = []
for (d_, key), nc in pairs.items():
    match = None
    for g, o in key:
        m = pol.get((g, bool(o)), 0)
        match = m if match is None else (match & m)
        if not match:
            break
    if match is None:
        match = (1 << len(dumps)) - 1
    nm_ = bin(match).count("1") if match else 0
    if not nm_:
        pn += 1
        continue
    nb = bin(match & ev.get(d_, 0)).count("1")
    if nb == 0:
        pf += 1
    else:
        pr += 1
        if len(prsamp) < 8:
            prsamp.append((nb, nm_, d_))
print("\n=== §19's test at the PAIR level, on the CORRECTED canonical names ===")
print(f"  distinct (member, gate conjunction) pairs in the residue: {len(pairs)}")
print(f"  CONJUNCTION FORECLOSURE (runs match P, none evaluates the member): {pf}")
print(f"  REACHABLE               (some matching run DOES evaluate it)     : {pr}")
print(f"  NO RUN MATCHES P        (undecidable by this test)               : {pn}")
for nb, nm_, d_ in prsamp:
    print(f"      reachable: {nb}/{nm_} matching runs evaluate  {d_[-80:]}")

print("\n=== THE RESIDUAL, BY CLASS ===")
tot = max(1, len(cubes))
for k, n in cls.most_common():
    print(f"  {k:26s} {n:6d}   ({100.0*n/tot:5.1f} %)")
print("\n=== cross-tab (class x whether the matching runs mostly ERROR) ===")
for (k, e), n in sorted(cross.items()):
    print(f"  {k:26s} {e:14s} {n:6d}")
mem = Counter(m for r in rows for m in r["foreclosed_members"])
if mem:
    print("\n=== the foreclosed members, most common first ===")
    for m, n in mem.most_common(10):
        print(f"  {n:6d}  {m[-96:]}")
json.dump({"n": len(cubes), "classes": dict(cls), "rows": rows},
          open(os.path.join(HERE, OUT), "w"))
print(f"\nwrote {OUT}")
