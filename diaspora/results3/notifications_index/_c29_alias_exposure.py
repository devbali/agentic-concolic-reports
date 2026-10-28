#!/usr/bin/env python3
"""C29 — HOW EXPOSED IS EACH ENDPOINT to the statement-keyed-alias defect?

An `AliasAssumption(key="statement")` collapses a call ORDINAL to a STATEMENT
identity. When one family resolves to SEVERAL statements, a demand that names
one of them carries a HIDDEN CONDITION: the decision that makes the run issue
THAT statement rather than a sibling. A builder that writes the member without
that decision builds a run in which the member's variable is never minted.

This counts, per endpoint, the alias FAMILIES and how many sibling statements
each resolves to over a sample of that endpoint's own corpus. Families with
more than one sibling are the exposed ones.

  usage: ENDPOINT=<dir> SNAP=<dump list> [SAMPLE=400] python3 -u _c29_alias_exposure.py
Read-only; writes nothing outside this batch directory.
"""
import collections, json, os, random, re, sys

R3 = "/home/dev/project/reports/diaspora/results3"
EP = os.environ["ENDPOINT"]
SNAP = os.environ["SNAP"]
SAMPLE = int(os.environ.get("SAMPLE", "400"))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, os.path.join(R3, EP))
from concolic_engine.assumptions import alias_map_for, AliasAssumption  # noqa: E402
import coverage_assumptions as CA                                       # noqa: E402

AL = [a for a in getattr(CA, "ALIASES", []) or []]
stmt = [a for a in AL if getattr(a, "key", None) == "statement"]
print(f"endpoint {EP}: {len(AL)} alias assumption(s), {len(stmt)} with key='statement'")
for a in stmt:
    print(f"   pattern {getattr(a, 'result_pattern', '?')}")
if not stmt:
    print("NOT EXPOSED: no statement-keyed alias")
    print("C29-ALIAS-EXPOSURE-DONE"); sys.exit(0)

files = [l.strip() for l in open(SNAP) if l.strip()]
random.seed(29)
files = random.sample(files, min(SAMPLE, len(files)))
fam = collections.defaultdict(set)
_H = re.compile(r"^(SYM_RESULT_\w+?)_([0-9a-f]{8})$")
seen = 0
for p in files:
    try:
        d = json.load(open(p))
    except Exception:
        continue
    seen += 1
    amap = alias_map_for([(e.get("result_name"), e.get("note"))
                          for e in d.get("events") or ()
                          if e.get("type") == "symbolic_call"], AL)
    for _ordinal, canon in (amap or {}).items():
        m = _H.match(canon)
        fam[m.group(1) if m else canon].add(canon)
print(f"sampled {seen} dumps from {os.path.basename(SNAP)}")
multi = {k: v for k, v in fam.items() if len(v) > 1}
print(f"alias FAMILIES seen: {len(fam)};  with MORE THAN ONE sibling statement: {len(multi)}")
for k, v in sorted(fam.items(), key=lambda kv: -len(kv[1])):
    mark = "  <- EXPOSED" if len(v) > 1 else ""
    print(f"   {len(v):2d} sibling(s)  {k}{mark}")
print("C29-ALIAS-EXPOSURE-DONE")
