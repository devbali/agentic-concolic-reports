#!/usr/bin/env python3
"""DIRECT CONSTRUCTION of the 12 gate combinations holding the 768 (coordinator,
2026-09-11). "No run produced this combination" is not "the program cannot", and
the seeder's `0 REACHABLE` says only that no BASE run walks the set under
compatible gates. There are only 12 combinations: build them from the solver's
own assignment instead of from a base.

Per combination:
  * fix the gate outcomes AND every member outcome (the enumerator already
    established the cube SATISFIABLE, so the assignment is the model);
  * seed EVERY ordinal backing each canonical name (the alias map is many-to-one
    by design — seeding one contradicts the demand whenever the path takes
    another, _demand_root.py's 2026-09-09 defect);
  * UNSEED rule: a `X == X__prior` self-compare is realised by REMOVING the key,
    never by writing one;
  * the base contributes CONTEXT ONLY — it is chosen for maximum overlap, not
    compatibility, and every demanded dimension is overwritten.

Then the replay is classified PER KEY: honoured / contradicted / never-evaluated.

usage: _x7_construct12.py            env: DUMP_LIST, PER_COMBO (default 4)
writes _construct_roots.json and _construct12_plan.json
"""
import glob, json, os, re, sys
from collections import defaultdict, Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
import coverage_report as CR  # noqa: E402

PER = int(os.environ.get("PER_COMBO", "4"))
DL = os.environ.get("DUMP_LIST")
files = ([l.strip() for l in open(DL) if l.strip()] if DL
         else sorted(glob.glob(os.path.join(HERE, "dump_*.json"))))

REM = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_remaining_s1post.jsonl")
rows = [json.loads(l) for l in open(REM)]
combos = defaultdict(list)
for r in rows:
    combos[tuple(sorted((r.get("pre") or {}).items()))].append(r)
print(f"{len(rows)} remaining assignments in {len(combos)} gate combinations; "
      f"constructing {PER} seeds per combination")

_SELF = re.compile(r"^\((SYM_[A-Za-z0-9_]+) == \1__prior\)$")
_CMP2 = re.compile(r"^\(([A-Za-z_][A-Za-z0-9_]*) (==|!=) ([A-Za-z_][A-Za-z0-9_]*)\)$")
_EQT  = re.compile(r"^\(([A-Za-z_][A-Za-z0-9_]*) == True\)$")
_EQI  = re.compile(r"^\(([A-Za-z_][A-Za-z0-9_]*) == (-?\d+)\)$")
_NEI  = re.compile(r"^\(([A-Za-z_][A-Za-z0-9_]*) != (-?\d+)\)$")
_GTI  = re.compile(r"^\(([A-Za-z_][A-Za-z0-9_]*) > (-?\d+)\)$")
_LEI  = re.compile(r"^\(([A-Za-z_][A-Za-z0-9_]*) <= (-?\d+)\)$")
_EQS  = re.compile(r"^\(([A-Za-z_][A-Za-z0-9_]*) == (?:StringVal\()?'((?:[^'\\]|\\.)*)'\)?\)$")
_NES  = re.compile(r"^\(([A-Za-z_][A-Za-z0-9_]*) != (?:StringVal\()?'((?:[^'\\]|\\.)*)'\)?\)$")
PIN = 424242

def plan_for(expr, want):
    """[(canonical_var, value)] realising expr==want, or None. A self-compare
    returns ('__UNSEED__', var)."""
    m = _SELF.match(expr)
    if m:
        # §12.5, MEASURED on this endpoint (402/402 in DR5): the decision is
        # controlled by the seed key's PRESENCE, not its value —
        #   V present -> TAKEN (205/205), V absent -> NOT TAKEN (197/197).
        # So taken is realised by SEEDING V and not_taken by DELETING it.
        # (people_stream's script returns None for the not-taken side; that
        # direction is what left 14 of this endpoint's 355 combinations
        # NOT-CONSTRUCTIBLE.)
        return [("__UNSEED__", m.group(1))] if not want else [(m.group(1), PIN)]
    m = _EQT.match(expr)
    if m:
        return [(m.group(1), bool(want))]
    m = _EQI.match(expr)
    if m:
        v, k = m.group(1), int(m.group(2))
        return [(v, k if want else k + PIN)]
    m = _NEI.match(expr)
    if m:
        v, k = m.group(1), int(m.group(2))
        return [(v, (k + PIN) if want else k)]
    m = _GTI.match(expr)
    if m:
        v, k = m.group(1), int(m.group(2))
        # DOMAIN-AWARE (2026-09-11). The mock SNAPS a collection length to a
        # small domain — `targets.rb:749-753` for the actors list is
        #     an = 0 if an.negative?;  an = 4 if an > 1        # domain {0,1,4}
        # so writing `k` for NOT(> k) with k>1 (e.g. 3) is snapped to 4 and the
        # decision comes back TRUE. Write 1: it satisfies NOT(> k) for every
        # k>=1 and is never 0 (a zero-length list forecloses the very row
        # decisions the cube is about, §12.10).
        return [(v, (k + 1) if want else (1 if k >= 1 else 0))]
    m = _LEI.match(expr)
    if m:
        v, k = m.group(1), int(m.group(2))
        return [(v, k if want else (k + 1))]
    m = _EQS.match(expr)
    if m:
        v, k = m.group(1), m.group(2)
        return [(v, k if want else (k + "_ctother"))]
    m = _NES.match(expr)
    if m:
        v, k = m.group(1), m.group(2)
        return [(v, (k + "_ctother") if want else k)]
    m = _CMP2.match(expr)
    if m:
        a, op, b = m.group(1), m.group(2), m.group(3)
        eq = (want == (op == "=="))
        return [(a, PIN), (b, PIN if eq else PIN + 1)]
    return None

# index the corpus once: alias map + evaluated set per dump, keeping seeds lazily
wanted = set()
for p, rs in combos.items():
    for e, _ in p:
        wanted.add(e)
    for r in rs[:PER]:
        wanted.update((r.get("asg") or {}).keys())

idx = []
for fp in files:
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    amap = CR.canonicalize_ordinals(d) or {}
    # amap is {ordinal_result_name: canonical_result_name}; keep it that way —
    # `ordinals()` walks it to find every ordinal whose canonical is a prefix of
    # the demanded column name.
    inv = {o: c for o, c in amap.items() if isinstance(o, str) and isinstance(c, str)}
    ev = {e["expr"] for e in (d.get("events") or ()) if e.get("type") == "path_condition"}
    idx.append((fp, inv, ev & wanted))
print(f"indexed {len(idx)} dumps")

def ordinals(inv, canon, seeds):
    """LEN SPELLING (RUNBOOK Phase 2): the enumerator names a length
    `SYM_LEN_X`, the runtime seeds it as `len(X)`. Convert, resolve the inner
    canonical to every backing ordinal, then re-wrap."""
    if canon.startswith("SYM_LEN_"):
        return ["len(" + k + ")" for k in _ordinals_raw(inv, canon[8:])]
    return _ordinals_raw(inv, canon)


def _ordinals_raw(inv, canon):
    """Every RUNTIME key backing a canonical column name. The alias map is
    many-to-one by design, so all of them are seeded — seeding one contradicts
    the demand whenever the path takes another (_demand_root.py's 2026-09-09
    defect, same shape)."""
    out = []
    for o, c in inv.items():
        if canon.startswith(c):
            out.append(o + canon[len(c):])
    if not out:
        out = [canon]
    return sorted(set(out))

roots, plan = [], []
for ci, (pre, rs) in enumerate(sorted(combos.items(), key=lambda kv: -len(kv[1])), 1):
    made = 0
    for r in rs:
        if made >= PER:
            break
        full = dict(pre); full.update(r.get("asg") or {})
        want = set(full)
        # base = MAXIMUM OVERLAP (context only), not compatibility
        fp, inv, ev = max(idx, key=lambda t: len(t[2] & want))
        try:
            base = json.load(open(fp)).get("concolic_seeds") or {}
        except Exception:
            base = {}
        seed = dict(base)
        bad = []
        # WRITE ORDER (defect found by the CT2 replay, 2026-09-11). A family
        # like `SYM_NOTE_TYPE_PROFILE` contributes EIGHT members on ONE
        # variable — seven `== k` demanded False (each writing the sentinel
        # k+PIN) and one demanded True (writing the real k). In dict order the
        # sentinel can be written LAST and clobber the real value, so the
        # compare is evaluated and takes the other side. The replay then reads
        # as "CONTRADICTED despite its seed", i.e. as impossibility evidence,
        # when it is nothing but write order: 76 of 355 combinations were
        # mis-classified that way. NEGATIVES FIRST, POSITIVES LAST — a demanded
        # equality pins its variable exactly and must win.
        for e, v in sorted(full.items(), key=lambda kv: (bool(kv[1]), kv[0])):
            pl = plan_for(e, v)
            if pl is None:
                bad.append(e); continue
            for var, val in pl:
                if var == "__UNSEED__":
                    for k in ordinals(inv, val, seed):
                        seed.pop(k, None)
                    continue
                for k in ordinals(inv, var, seed):
                    seed[k] = val
        if bad:
            plan.append({"combo": ci, "status": "NOT-CONSTRUCTIBLE", "exprs": bad})
            break
        seed["__ctcombo__"] = ci
        roots.append(seed)
        plan.append({"combo": ci, "status": "CONSTRUCTED", "base": os.path.basename(fp),
                     "overlap": len(ev & want), "members": len(full),
                     "demanded": {e: v for e, v in full.items()}})
        made += 1
    if ci <= 6 or made == 0:
        print(f"  [{ci:2d}] {len(rs):5d} assignments -> {made} constructed seeds")

OUT = os.environ.get("OUT_ROOTS") or os.path.join(HERE, "_construct_roots.json")
json.dump(roots, open(OUT, "w"))
json.dump(plan, open(OUT.replace("_roots.json", "_plan.json"), "w"), indent=1)
print(f"\nwrote {len(roots)} constructed seeds over {len(combos)} combinations")
