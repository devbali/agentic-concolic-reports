#!/usr/bin/env python3
"""C30 — turn `_c30_analyze.py`'s MATCHED-CONTEXT DIFFERENTIALS into the
ENABLING_GATES file `_c30_construct.py` reads (§40.5a).

A statement-keyed alias is itself a CONDITION: when a member's canonical name
came from an `AliasAssumption(key="statement")` whose family resolves to
several statements, WHICH sibling a run issues is decided by some OTHER
decision. A build that writes the member without that decision builds a run in
which the member's variable is never MINTED — `evaluated=N, realised=0`.

The differential already ranks, for the literal the ladder dies on and for
every literal whose drop row says NEVER EVALUATED, the decisions that separate
the runs that DO evaluate it from the runs that do not. This script takes the
separators that are STRONG (>= MINSEP absolute rate gap and >= MINRATE on the
evaluating side) and emits them as gates.

  usage: ANALYZE=_c30_analyze_<stamp>.json OUT=_c30_gates_<stamp>.json
         [MINSEP=0.5] [MINRATE=0.6] [TOPN=4] python3 _c30_gates_from_analyze.py

A gate whose expr appears with BOTH wants across a set's differentials is
DROPPED (it cannot discriminate consistently) and said so on stdout — never
silently resolved by picking one.
Read-only apart from OUT.
"""
import collections
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ANALYZE = os.environ.get("ANALYZE", os.path.join(HERE, "_c30_analyze.json"))
OUT = os.environ.get("OUT", os.path.join(HERE, "_c30_gates.json"))
MINSEP = float(os.environ.get("MINSEP", "0.5"))
MINRATE = float(os.environ.get("MINRATE", "0.6"))
TOPN = int(os.environ.get("TOPN", "4"))

# The constructor can only WRITE a gate of the shapes `(<var> == True|False)`,
# `(<var> == <int>)` and `(<var> > <int>)` (`_c30_construct.py::lit_of`). A
# string equality is not one of them, so it would be silently skipped there and
# would only have eaten a TOPN slot here. It is filtered out AND COUNTED, never
# dropped in silence. Likewise a separator naming a variable the cube itself
# already decides: the constructor refuses it ("the cube already decides this
# one") because a gate contradicting a member would pick a different base row.
_WRITABLE = re.compile(r"^\((\w+) (?:== (?:True|False|-?\d+)|> -?\d+)\)$")
_VAR = re.compile(r"^\((\w+) ")


def _var(e):
    m = _VAR.match(e)
    return m.group(1) if m else None


A = json.load(open(ANALYZE))
out, dropped_total, kept_total, unwritable_total, incube_total = {}, 0, 0, 0, 0
for g in A:
    si = g["i"]
    cand = collections.defaultdict(set)      # expr -> {want}
    score = {}
    unwritable, incube = set(), set()
    cubevars = {v for v in (_var(e) for e in g["members"]) if v}
    cubevars |= {v for v in (_var(e[4:-1]) for e in g["members"]
                             if e.startswith("Not(")) if v}
    for li, r in (g.get("differentials") or {}).items():
        if not r or not r.get("rows"):
            continue
        n = 0
        for x in r["rows"]:
            ev, ne = x["evaluating_rate"], x["not_evaluating_rate"]
            if abs(ev - ne) < MINSEP:
                continue
            if ev < MINRATE:
                continue
            if not _WRITABLE.match(x["expr"]):
                unwritable.add(x["expr"]); continue
            if _var(x["expr"]) in cubevars:
                incube.add(x["expr"]); continue
            cand[x["expr"]].add(bool(x["want"]))
            score[x["expr"]] = max(score.get(x["expr"], 0.0), abs(ev - ne))
            n += 1
            if n >= TOPN:
                break
    gates, dropped = [], []
    for e, wants in cand.items():
        if len(wants) != 1:
            dropped.append(e)
            continue
        gates.append({"expr": e, "want": next(iter(wants)), "sep": round(score[e], 3)})
    gates.sort(key=lambda x: -x["sep"])
    gates = gates[:TOPN]
    if gates:
        out[str(si)] = gates
    kept_total += len(gates)
    dropped_total += len(dropped)
    unwritable_total += len(unwritable)
    incube_total += len(incube)
    print(f"set{si}: {len(gates)} gate(s); {len(unwritable)} not writable, "
          f"{len(incube)} already in the cube"
          + (f", {len(dropped)} DROPPED (both wants): {dropped}" if dropped else ""))
    for x in gates:
        print(f"      {'T' if x['want'] else 'F'} sep={x['sep']:.2f}  {x['expr'][:100]}")

json.dump(out, open(OUT, "w"), indent=1)
print(f"\nwrote {OUT}: {kept_total} gates over {len(out)} sets "
      f"(MINSEP={MINSEP} MINRATE={MINRATE} TOPN={TOPN}); {dropped_total} dropped, "
      f"{unwritable_total} not writable, {incube_total} already in the cube")
print("C30-GATES-DONE")
