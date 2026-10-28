#!/usr/bin/env python3
"""Is the UNEVALUATED residue an ALIAS miss?

Hypothesis (coordinator, 2026-09-11): the four `to_ary_notifications_*`
statement aliases are selected UPSTREAM of the gate prefix by request-level
inputs (list variant / type filter / unread filter / params — all seeded
dimensions). A base that matches the gate conjunction but walks a DIFFERENT
alias cannot carry the cube's members, and gate-matching does not check the
alias.

Test, on the replay's own data and with no new runs: for every UNEVALUATED
combination, compare the alias hashes named by the members that went
UNEVALUATED against the aliases the chosen BASE run actually walked.

usage: PLAN=_construct_CT5_plan.json python3 -u _alias_miss.py 'dump_*CT5*.json'
"""
import glob, json, os, re, sys
from collections import defaultdict, Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
from coverage_report import canonicalize_ordinals  # noqa: E402

_UNLEN = re.compile(r"len\(([^()]+)\)")
_ALIAS = re.compile(r"_([0-9a-f]{8})(?:_|\b)")
PAT = sys.argv[1] if len(sys.argv) > 1 else "dump_*CT5*.json"
PLAN = os.environ.get("PLAN", "_construct_CT5_plan.json")
REPORT = os.environ.get("REPORT", "_construct_report.json")


def pcs_of(d):
    canonicalize_ordinals(d)
    out = set()
    for e in d.get("events") or ():
        if e.get("type") == "path_condition":
            ex = e["expr"]
            out.add(ex)
            out.add(_UNLEN.sub(r"SYM_LEN_\1", ex))
    return out


plan = json.load(open(os.path.join(HERE, PLAN)))
demanded, base_of = {}, {}
for p in plan:
    if p.get("status") == "CONSTRUCTED":
        demanded.setdefault(p["combo"], {}).update(p["demanded"])
        base_of.setdefault(p["combo"], []).append(p.get("base"))
rep = json.load(open(os.path.join(HERE, REPORT)))
unev = [int(c) for c, v in rep["per_combo"].items() if v == "UNEVALUATED"]
print(f"UNEVALUATED combinations: {len(unev)} of {len(rep['per_combo'])}")

# what each combination's runs actually walked
seen = defaultdict(set)
for fp in sorted(glob.glob(os.path.join(HERE, PAT))):
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    c = (d.get("concolic_seeds") or {}).get("__ctcombo__")
    if c in demanded:
        seen[c] |= pcs_of(d)
    del d

_bc = {}


def base_aliases(name):
    """The aliases the BASE run itself walked (its canonicalized PCs)."""
    if name in _bc:
        return _bc[name]
    fp = os.path.join(HERE, name)
    al = set()
    try:
        al = {m for e in pcs_of(json.load(open(fp))) for m in _ALIAS.findall(e)}
    except Exception:
        pass
    if len(_bc) > 2000:
        _bc.clear()
    _bc[name] = al
    return al


tot = differ = same = nobase = 0
miss_alias = Counter()
examples = []
for c in unev:
    miss = [e for e in demanded[c] if e not in seen[c]]
    if not miss:
        continue
    want_al = {m for e in miss for m in _ALIAS.findall(e)}
    if not want_al:
        continue                       # the miss names no aliased statement
    tot += 1
    bal = set()
    for b in base_of.get(c, []):
        if b:
            bal |= base_aliases(b)
    if not bal:
        nobase += 1
        continue
    unmet = want_al - bal
    if unmet:
        differ += 1
        for a in unmet:
            miss_alias[a] += 1
        if len(examples) < 4:
            examples.append((c, sorted(want_al), sorted(bal), sorted(unmet),
                             miss[0][-80:]))
    else:
        same += 1

print(f"\n=== ALIAS TEST over the UNEVALUATED combinations whose missed "
      f"members name an aliased statement ===")
print(f"  combinations tested:                              {tot}")
print(f"  base walked a DIFFERENT alias than the cube needs: {differ}"
      f"   ({100.0*differ/max(1,tot):.1f} %)")
print(f"  base walked the right alias, member still missed:  {same}"
      f"   ({100.0*same/max(1,tot):.1f} %)")
print(f"  base's aliases unreadable:                         {nobase}")
if miss_alias:
    print("\n  aliases the base failed to carry, most often first:")
    for a, n in miss_alias.most_common(8):
        print(f"    {n:4d}x  {a}")
for c, w, b, u, m in examples:
    print(f"\n  combo#{c}: cube needs {w}, base walked {b}, MISSING {u}")
    print(f"    e.g. unevaluated member …{m}")
json.dump({"tested": tot, "alias_differs": differ, "alias_same": same,
           "no_base": nobase, "by_alias": miss_alias.most_common(20)},
          open(os.path.join(HERE, "_alias_miss.json"), "w"), indent=1)
print("\nwrote _alias_miss.json")
