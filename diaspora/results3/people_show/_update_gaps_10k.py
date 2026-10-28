#!/usr/bin/env python3
"""Update the STRUCTURAL_GAPS resolution addendum with the 10k scale result."""
PATH = "/home/dev/project/reports/diaspora/results3/people_show/STRUCTURAL_GAPS.md"
with open(PATH) as f:
    txt = f.read()

old = ("The 64 therefore remains the honest bounded-count floor, and is now the\n"
       "strongest possible claim: MISSING is unchanged at 64 across (a) deeper drain\n"
       "(69fe5bb), (b) multi-var composition (a67ae0e), and (c) dual-format\n"
       "co-rendering (this addendum) — three independent strategies, same 64.")
new = ("The 64 therefore remains the honest bounded-count floor, and is now the\n"
       "strongest possible claim: MISSING is unchanged at 64 across SIX corpus\n"
       "configurations — (a) deeper drain (69fe5bb), (b) multi-var composition\n"
       "(a67ae0e), (c) dual-format co-rendering at 5000 runs (bf9650c), and\n"
       "(d) dual-format scale-out to 10000 runs / 2606 dual paths / 4984-dump\n"
       "mixed corpus (2026-09-04 03:55 addendum) — independent strategies and\n"
       "scales, same 64. The dual frontier is large-but-saturating (2606 paths\n"
       "at 10k, not drained) yet MISSING does not move: the ordinal-naming\n"
       "collision and control-flow foreclosure are scale-invariant.")
assert old in txt, "anchor not found"
with open(PATH, "w") as f:
    f.write(txt.replace(old, new))
print("updated STRUCTURAL_GAPS.md")