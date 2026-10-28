#!/usr/bin/env python3
"""P40d — ANATOMY of the demand sets, and the closure arithmetic.

Q2 of the brief: are the wide sets genuinely-interacting decisions, or per-row
decisions over independent collections that nothing has separated?

Also computes the bound that constrains EVERY lever:
    a single run realises exactly ONE leaf per demand set, so the number of
    ADDITIONAL runs needed to close the endpoint is at least
        max over sets of (remaining leaves in that set).
Read-only.  Verdict line: `P40D-DONE`.
"""
import json, os, re, collections
B = os.path.dirname(os.path.abspath(__file__))
S = json.load(open(f"{B}/_p40_sets.json"))
M = S["_members_all"]
_W_census = S["_all_widths"]; _R_census = [int(x) for x in S["_rem_all"]]
# `_p23_enum.census` iterates `sorted(enumerate(cliques), key=len)` (a STABLE
# sort) and appends per-set rows in THAT order, so the per-set arrays are in
# census order while `_members_all` is in clique order. Rebuild the permutation
# the same way and ASSERT it -- a silent misalignment here would attribute the
# widest sets' contents to the wrong sets.
_perm = [i for i, _ in sorted(enumerate(M), key=lambda t: len(t[1]))]
assert [len(M[ci]) for ci in _perm] == _W_census, "census permutation does not reproduce the widths"
W = [0]*len(M); R = [0]*len(M)
for pos, ci in enumerate(_perm):
    W[ci] = _W_census[pos]; R[ci] = _R_census[pos]
N = len(M)
print("census->clique permutation reconstructed and asserted against the width vector")
print(f"demand sets: {N}   total remaining: {sum(R)}")

# ---- the closure bound ----------------------------------------------------
order = sorted(range(N), key=lambda i: -R[i])
print("\n=== CLOSURE ARITHMETIC ===")
print(f"  max remaining in a single set : {R[order[0]]}   (width {W[order[0]]})")
print(f"  a run covers at most ONE leaf per set, so closing this endpoint needs")
print(f"  at least {R[order[0]]} further runs, each landing a DISTINCT leaf of that set.")
corpus = 48943
print(f"  the whole corpus is {corpus} distinct outcome profiles.")
over = [i for i in range(N) if R[i] > corpus]
print(f"  sets whose remaining alone exceeds the whole corpus: {len(over)} of {N}")
print(f"  they hold {sum(R[i] for i in over)} of {sum(R)} remaining "
      f"({100.0*sum(R[i] for i in over)/max(1,sum(R)):.1f} %)")

# ---- how the remaining is distributed over sets ---------------------------
print("\n=== REMAINING PER SET — DISTRIBUTION ===")
buckets = [0, 1, 10, 100, 1000, 10000, 100000, 10**9]
lab = ["0 (closed)", "1-9", "10-99", "100-999", "1k-9999", "10k-99999", ">=100k"]
cnt = [0]*7; hold = [0]*7
for r in R:
    for k in range(7):
        if buckets[k] <= r < buckets[k+1]:
            cnt[k] += 1; hold[k] += r; break
for k in range(7):
    print(f"  {lab[k]:>12}: {cnt[k]:>4} sets holding {hold[k]:>10}")
print(f"  sets already CLOSED (remaining 0): {cnt[0]} of {N}")
print(f"  sets that would need <= 100 further distinct leaves: {cnt[1]+cnt[2]} "
      f"holding {hold[1]+hold[2]}")

# ---- family anatomy -------------------------------------------------------
FAM = re.compile(r"records_([a-z_]+)_[0-9a-f]{8}|to_ary_([a-z_]+)_[0-9a-f]{8}")
ORD = re.compile(r"as_api_response_(\d+)_row_(\w+)")
def family(e):
    m = FAM.search(e)
    if m: return "coll:" + (m.group(1) or m.group(2))
    m = ORD.search(e)
    if m: return "apirow:" + m.group(2)
    if "records_2_rows" in e: return "coll:TOP(records_2)"
    if "find_by" in e: return "finder:find_by"
    if "findpublic" in e: return "finder:findpublic"
    if "evilq" in e: return "finder:evilq"
    if "SYM_PARAM" in e: return "param"
    if "size_1_size" in e: return "coll:size"
    return "other:" + e[:40]

print("\n=== THE 15 SETS HOLDING THE MOST REMAINING ===")
for i in order[:15]:
    fams = collections.Counter(family(e) for e in M[i])
    print(f"\n  set#{i}  width={W[i]}  remaining={R[i]}")
    print(f"    distinct families {len(fams)}: {dict(fams)}")

print("\n=== ACROSS ALL SETS OF WIDTH >= 13 ===")
wide = [i for i in range(N) if W[i] >= 13]
print(f"  {len(wide)} sets, holding {sum(R[i] for i in wide)} remaining")
nf = collections.Counter(len(set(family(e) for e in M[i])) for i in wide)
print(f"  distinct families per wide set: {dict(sorted(nf.items()))}")
mx = collections.Counter()
for i in wide:
    for f in set(family(e) for e in M[i]): mx[f] += 1
print(f"  family occurrence over wide sets: {dict(mx.most_common(20))}")
# how many members of a wide set belong to the single largest family?
share = []
for i in wide:
    c = collections.Counter(family(e) for e in M[i])
    share.append(c.most_common(1)[0][1] / len(M[i]))
share.sort()
print(f"  largest-family share of a wide set: median {share[len(share)//2]:.2f} "
      f"min {share[0]:.2f} max {share[-1]:.2f}")
json.dump({"max_remaining_single_set": R[order[0]],
           "sets_over_corpus": len(over),
           "remaining_in_those": sum(R[i] for i in over),
           "total_remaining": sum(R)},
          open(f"{B}/_p40_anatomy.json", "w"), indent=1)
print("\nP40D-DONE")
