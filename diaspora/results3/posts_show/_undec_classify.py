#!/usr/bin/env python3
"""§76.2(b) — classify the UNDECIDABLE decisions by WHY no matched context
exists, instead of by `_oneflip_seeds.py`'s inherited name heuristic (which
mis-sorts both ways on this endpoint: it calls `evilq_like_public_1_text_empty`
a gate because the ALIAS contains `_public`, and it does not recognise
`SYM_LEN_..._rows != 0` as a length gate at all).

  SELF-COMPARE    (X != X)  — UNSAT; no context can ever exist. The
                  DecisionAlias artefact (call_interceptor.rb:142-144).
  PINNED          an ARGUMENT P expression, declared ONE-SIDED after two
                  falsifier rounds (TR0910a 45 seeds, TR0910w 3 024 seeds,
                  HIT=0 both). No matched context BY DECLARATION.
  GATE            a length gate: flipping it changes WHICH decisions are
                  evaluated, so no EXACT matched context can exist at any
                  corpus size (it is measured under the co-evaluated keying).
  ADDRESSABLE     a one-flip seed can construct the missing context. THESE are
                  the only ones a round can close.
"""
import json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(HERE, "_undecidable_kinds_OD.json")))
und = D["undecidable"]
# ARGUMENT P, verbatim from POLICY_HEADER.txt: four guid (P2) + three
# NullRelation lengths (P1).
P2 = re.compile(r"as_api_response_[1-4]_row_guid")
P1 = re.compile(r"_records_(7|8|10)_rows != 0")
SELF = re.compile(r"^\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*!=\s*\1\s*\)$")
out = {"SELF-COMPARE": [], "PINNED": [], "GATE": [], "ADDRESSABLE": []}
for e in und:
    if SELF.match(e.strip()):
        out["SELF-COMPARE"].append(e)
    elif P2.search(e) or P1.search(e):
        out["PINNED"].append(e)
    elif e.startswith("(SYM_LEN_") or e.startswith("(len(") or e.startswith("(Length("):
        out["GATE"].append(e)
    else:
        out["ADDRESSABLE"].append(e)
print(f"UNDECIDABLE decisions: {len(und)}")
for k in ("SELF-COMPARE", "PINNED", "GATE", "ADDRESSABLE"):
    print(f"\n=== {k}: {len(out[k])} ===")
    for e in out[k]:
        print(f"   {e[:110]}")
json.dump({"undecidable": und, "by_reason": out,
           "addressable": out["ADDRESSABLE"]},
          open(os.path.join(HERE, "_undec_classified.json"), "w"), indent=1)
print(f"\nONLY {len(out['ADDRESSABLE'])} of {len(und)} can be closed by a round.")
print("UNDEC CLASSIFY DONE")
