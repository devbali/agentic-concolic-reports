"""(1) CHECK the W-G withdrawal predicate against the declarations it must
remove — exactly the 60 in the eight gate-FAILed classes, nothing else;
(2) emit _confinement_withdrawn.json (the 1 806 inferred pairs of the 247
non-PASS confinement classes, class-whole) and _prior_footprints.json
(expr -> footprint, for CoverageChecker(prior_footprints=), the §16c
cross-pass tripwire)."""
import json, os, sys, re

B = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, B)
sys.path.insert(0, "/home/dev/project/src")
import coverage_assumptions as CA


def _stream(path):
    f = open(path, encoding="utf-8")
    while f.read(1) != "[":
        pass
    depth, in_str, esc, buf = 0, False, False, []
    while True:
        chunk = f.read(1 << 20)
        if not chunk:
            return
        start = 0
        for n, c in enumerate(chunk):
            if in_str:
                if esc:
                    esc = False
                elif c == "\\":
                    esc = True
                elif c == '"':
                    in_str = False
                continue
            if c == '"':
                in_str = True
            elif c in "[{":
                if depth == 0:
                    start = n
                depth += 1
            elif c in "]}":
                depth -= 1
                if depth == 0:
                    buf.append(chunk[start:n + 1])
                    yield json.loads("".join(buf))
                    buf = []
                    start = n + 1
        if depth:
            buf.append(chunk[start:])


class _Fake:
    def __init__(self, d):
        self.description = d
        self.expr_a = self.expr_b = ""


# ---- (1) the predicate, on every tier2 declaration of the cert3 pass -------
wg = 0
tier2 = 0
fp = {}
for a in _stream(os.path.join(B, "_assumptions_declared_cert3.json")):
    t = a.get("type")
    if t == "IndependenceAssumption":
        d = a.get("description") or ""
        if d.startswith("disjoint reps: "):
            tier2 += 1
            if CA._withdrawn_by_gate_class(_Fake(d)):
                wg += 1
    elif t == "ConfinementAssumption":
        for side in ("a", "b"):
            f = a.get("footprint_" + side) or []
            if f:
                fp.setdefault(a["expr_" + side], set()).update(f)
print(f"[W-G] tier2 declarations {tier2}; withdrawn by the gate-class predicate {wg} (must be 60)")
assert wg == 60, wg

# ---- (2) the confinement withdrawals, class-whole --------------------------
rows = json.load(open(os.path.join(B, "_c11_withdraw_conf.json")))
pairs = sorted({tuple(sorted(p)) for r in rows for p in r["pairs"]})
json.dump([list(p) for p in pairs], open(os.path.join(B, "_confinement_withdrawn.json"), "w"), indent=0)
print(f"[conf] withdrawn pairs written: {len(pairs)} (classes {len(rows)}; "
      f"FAIL {sum(1 for r in rows if r['verdict']=='FAIL')}, "
      f"NOT-COMPARABLE {sum(1 for r in rows if r['verdict']=='NOT-COMPARABLE')})")

json.dump({e: sorted(v) for e, v in fp.items()},
          open(os.path.join(B, "_prior_footprints.json"), "w"))
print(f"[prior] footprints for {len(fp)} expressions written")
