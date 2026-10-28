#!/usr/bin/env python3
"""Build the gate's --declared input: ONE REPRESENTATIVE PAIR PER REP-PAIR CLASS.

The gate probes a CLAIM, and the claim this tier makes is per rep-pair class
("decisions on a <finder> rep are independent of decisions on an <api row>
rep"), not per ordinal instance — the same granularity notifications' C7-A used
(14 pairs, one per family pair). Probing every instance would re-probe one claim
hundreds of times at ~15 s each; probing one per class probes each claim once.
A class whose representative FAILS is withdrawn ENTIRELY, instance included.
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(HERE, "_tier_recover.json")))
reps = D["class_representative"]
out = []
for cls, (a, b) in sorted(reps.items()):
    out.append({
        "type": "IndependenceAssumption",
        "expr_a": a, "expr_b": b,
        "description": f"tier2 disjoint reps (class representative): {cls}",
        "agent_notes": ("PROPOSAL, 2026-09-11 coordinator ruling. Ported criterion of "
                        "notifications_index `_tier2_disjoint_reps`: two decisions on "
                        "DIFFERENT symbolic reps neither gate nor feed each other and each "
                        "statement shape either can produce is keyed on its own rep's id. "
                        "Lengths (W-E), the post_key dispatch (W-C) and not_found x "
                        "not_found (W-F) are excluded before probing. This entry is the "
                        "REPRESENTATIVE of its rep-pair class; a FAIL withdraws the class."),
    })
p = os.path.join(HERE, "_tier2_declared.json")
json.dump(out, open(p, "w"), indent=1)
print(f"{len(out)} class representatives -> {p}")
print(f"(covering {sum(n for _, n in D['classes'])} candidate pairs "
      f"in {len(D['classes'])} classes)")
