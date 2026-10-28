#!/usr/bin/env python3
"""CONSTRUCT the remaining cubes, grouped by GATE COMBINATION (RUNBOOK Phase 2,
2026-09-11): before calling any remaining cube a residue, BUILD it and replay.

people_stream settled the method: all 768 cubes it had labelled
MULTI-GATE-FORECLOSED were reachable — 12/12 gate combinations realised by
DIRECT CONSTRUCTION and driven to remaining = 0 with no declaration. "No run
has produced this" is not "the program cannot"; only A GATE THAT FLIPS BACK
DESPITE ITS SEED is impossibility evidence.

Input: the emitter's cubes (`EMIT_REACHABLE_ONLY=0`, so unreachable leaf groups
are INCLUDED — that default was flipped for exactly this rule). Each carries
`gates` (the leaf group's gate prefix), `node_constraint` and `concrete_values`
(a Z3 model of the whole cube).

Output: one seed per GATE COMBINATION x variant, built by
  * fixing the gate outcomes AND the member outcomes from the SAT model,
  * seeding EVERY ordinal backing each canonical name (the many-ordinal rule),
  * UNSEEDING keys whose absence is what the decision reads (`__prior` family),
  * choosing a base by MAX OVERLAP for context only.
"""
import json, os, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from coverage_report import canonicalize_ordinals  # noqa: E402
from concolic_engine.names import NameSpace  # noqa: E402

EMIT = os.environ.get("EMIT_IN", os.path.join(HERE, "_enum_emit_gateaware.json"))
K = int(os.environ.get("VARIANTS_PER_COMBO", "4"))
VARIANTS = ("auth_html", "anon_html", "auth_json", "anon_json")
DOMAIN = defaultdict(Counter); RAW = {}
cubes = json.load(open(EMIT))["missing"]
print(f"cubes emitted: {len(cubes)}")

by_combo = defaultdict(list)
for c in cubes:
    key = tuple(sorted((g, bool(v)) for g, v in (c.get("gates") or {}).items()))
    by_combo[key].append(c)
print(f"distinct GATE COMBINATIONS: {len(by_combo)}")
for k, v in sorted(by_combo.items(), key=lambda kv: -len(kv[1]))[:10]:
    print(f"  {len(v):7d} cubes  gates={len(k)}  " +
          "; ".join(f"{g.split('__')[-1][:40]}={'T' if o else 'F'}" for g, o in k[:3]))

files = [l.strip() for l in open(os.environ["DUMP_LIST"]) if l.strip()]
files = [f if os.path.isabs(f) else os.path.join(HERE, f) for f in files]
index = []
for p in files:
    try:
        d = json.load(open(p))
    except Exception:
        continue
    amap = canonicalize_ordinals(d)
    inv = defaultdict(list)
    for o, c in (amap or {}).items():
        inv[c].append(o)
    ex = {str(e.get("expr", "")) for e in d.get("events") or ()
          if e.get("type") == "path_condition"}
    base = os.path.basename(p)
    v = next((x for x in VARIANTS if base.startswith("dump_" + x)), None)
    index.append((p, v, ex, dict(inv), len(d.get("concolic_seeds") or {})))
    for sv in d.get("symbolic_vars") or ():
        nm, val = sv.get("name"), sv.get("value")
        if nm is not None and not isinstance(val, (dict, list)):
            DOMAIN[nm][repr(val)] += 1
            RAW.setdefault((nm, repr(val)), val)
    del d
print(f"indexed {len(index)} bases")
_DOMAIN_NS = NameSpace(DOMAIN, name="observed value DOMAIN")
XBOUND = Counter()

_PRIOR = re.compile(r"__prior\b")
def to_seed(v):
    if isinstance(v, bool) or v is None or isinstance(v, int):
        return v
    s = str(v)
    if s in ("True", "False"):
        return s == "True"
    try:
        return int(s)
    except ValueError:
        return s.strip('"')

# ---- CONSTRUCTOR FIX (2026-09-11), both defects notifications found ---------
# (1) NEGATIONS MUST BE IN DOMAIN. A model value only has to SATISFY the cube;
#     the solver is free to invent one the variable never takes at runtime
#     (notifications' `k + 424242` sentinel). Measured here BEFORE the fix:
#     2 912 of 11 910 constructed values (24.5%) were out of the observed
#     domain, over 4 variables — the three `as_api_response_N_row_guid`
#     (model '' vs observed '..._guid_v') and `SYM_PARAM_id` (model
#     'ABCDEFGHIJKLMNOP' when the corpus's own 16-char value is
#     'ABCKLDEMFNGHOIJP'). An out-of-domain seed forecloses every downstream
#     keyed on that variable, which is one source of the UNEVALUATED 68%.
#     Resolve each NEGATED variable to the MOST-OFTEN-OBSERVED value that
#     still satisfies the cube's constraint on it.
# (2) WRITE ORDER. When several members sit on ONE variable, a negation's
#     substitute must not clobber a positive's exact value: negatives first,
#     positives LAST.
_EQ = re.compile(r"^\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*==\s*(.+?)\s*\)$")
_NE = re.compile(r"^\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*!=\s*(.+?)\s*\)$")

def polarity(cube):
    """var -> 'neg' if the cube forces it AWAY from a value, else 'pos'."""
    pol = {}
    for part in (cube["node_constraint"] or "").split(" AND "):
        part = part.strip(); want = True
        m = re.match(r"^Not\((.*)\)$", part, re.S)
        if m:
            part, want = m.group(1).strip(), False
        me, mn = _EQ.match(part), _NE.match(part)
        if me:
            pol[me.group(1)] = 'pos' if want else 'neg'
        elif mn:
            pol[mn.group(1)] = 'neg' if want else 'pos'
    return pol

def in_domain_value(var, modelled, neg):
    """Most-often-observed value for `var` that is still compatible."""
    # 2026-09-14 NAME-BOUNDARY FIX (concolic_engine.names). DOMAIN is keyed by
    # POST-`canonicalize_ordinals` `symbolic_vars` names -- canonical, but
    # `len(X)`-spelled -- while `var` arrives from the checker's model in
    # `SYM_LEN_X` spelling. `DOMAIN.get(var)` therefore missed on every length
    # variable and the falsy answer was read as "no observed domain, keep the
    # solver's value", defeating repair (1) for exactly the length family.
    d = _DOMAIN_NS.resolve(var)
    if not d:
        return modelled, False
    if repr(modelled) in d:
        return modelled, False
    if not neg:
        return modelled, False            # a positive must keep its exact value
    for rep, _n in d.most_common():
        if rep != repr(modelled):
            return RAW[(var, rep)], True  # observed, and different: satisfies !=
    return modelled, False

per_variant = defaultdict(list)
made = nobase = 0
substituted = Counter()
for key, group in by_combo.items():
    c = max(group, key=lambda x: int(x.get("assignments", "1")))
    want = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", c["node_constraint"]))
    best = sorted(index, key=lambda t: (-len(want & {w for e in t[2]
                  for w in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", e)}), -t[4]))[:K]
    if not best:
        nobase += 1
        continue
    for p, v, _ex, inv, _n in best:
        try:
            seeds = dict(json.load(open(p)).get("concolic_seeds") or {})
        except Exception:
            continue
        _SEED_NS = NameSpace(seeds, name="base concolic_seeds",
                             alias_map={o: c2 for c2, os_ in inv.items() for o in os_})
        pol = polarity(c)
        items = list((c.get("concrete_values") or {}).items())
        # (2) negatives FIRST, positives LAST
        items.sort(key=lambda kv: 0 if pol.get(kv[0]) == 'neg' else 1)
        for k, val in items:
            if _PRIOR.search(k):
                seeds.pop(k, None)          # UNSEED: absence is the signal
                continue
            use, subbed = in_domain_value(k, val, pol.get(k) == 'neg')   # (1)
            if subbed:
                substituted[k] += 1
            # 2026-09-14 NAME-BOUNDARY FIX. `k` is a CHECKER-side name
            # (`SYM_LEN_X`, canonical); `seeds` is the RUNTIME dict (`len(X)`,
            # raw ordinals -- `canonicalize_ordinals` leaves seeds alone) and
            # `inv` is keyed by the BARE canonical, so neither could match a
            # `SYM_LEN_..._rows` or a suffixed canonical. `ords` came back []
            # and the demanded value was DROPPED with no counter and no print:
            # 4,720 of 25,580 constructed values (18.5%) in round OD0911, and
            # the length family is the dominant gating family on posts_show,
            # so cubes were "constructed" and replayed WITHOUT the pin they
            # exist for. `keys_for` resolves spelling, suffix and every
            # backing ordinal (all of them must be written -- the alias map is
            # many-to-one, so seeding one contradicts the demand whenever the
            # path takes another). [] now means a genuine absence, and it is
            # COUNTED rather than silent.
            ords = _SEED_NS.keys_for(k)
            if not ords:
                XBOUND["demanded value DROPPED: name absent under every spelling"] += 1
            elif k not in seeds:
                XBOUND["seed key reached only across the name boundary"] += 1
            for o in ords:                  # EVERY ordinal backing the canonical
                seeds[o] = to_seed(use)
        per_variant[v or "auth_html"].append(seeds)
        made += 1
if XBOUND:
    print("\n=== NAME-BOUNDARY ACCOUNTING (formerly silent) ===")
    for k, v in XBOUND.most_common():
        print(f"  {k:56s} {v}")
print(f"\nconstructed seeds: {made}   combinations with no base: {nobase}")
print(f"OUT-OF-DOMAIN negations replaced with an observed value: {sum(substituted.values())}"
      f" over {len(substituted)} variables")
for k, n in substituted.most_common(8):
    print(f"   x{n:<5} {k[:76]}")
for v, lst in per_variant.items():
    out = os.path.join(HERE, f"_demandR_{v}.json")
    json.dump(lst, open(out, "w"))
    print(f"  {v}: {len(lst)} -> {os.path.basename(out)}")
json.dump({"combinations": len(by_combo), "made": made, "no_base": nobase,
           "combo_sizes": sorted((len(v) for v in by_combo.values()), reverse=True)[:50]},
          open(os.path.join(HERE, "_construct_plan.json"), "w"), indent=1)
