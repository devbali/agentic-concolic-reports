#!/usr/bin/env python3
"""§76.1 — DECOMPOSE the OR-refined remaining by PART.

Reads _parts_OD0911.json (written by _part_decomp.py: one entry per demand
part, with its MEMBERS, sat, covered, remaining) and answers, with numbers:
how many parts, the width distribution WEIGHTED BY REMAINING MASS, the top
parts by remaining with their members named by DECISION FAMILY, and how much
of the remaining the emitter could reach.
Read-only. Caged like everything else.
"""
import json, os, re, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
P = json.load(open(os.path.join(HERE, os.environ.get("PARTS_IN", "_parts_OD0911.json"))))
parts = P["parts"]
tot = sum(p["remaining"] for p in parts)
print(f"PARTS {len(parts)}  remaining_total {tot}  (census totals: {P['totals']})")

# ---- decision families -----------------------------------------------------
def family(e):
    if "_not_found" in e:
        return "find_by_N_not_found" if "FinderMethods_find_by" in e else "findpublic_not_found"
    if re.search(r"_public == ", e):            return "public gate"
    if e.startswith("(SYM_LEN_") or e.startswith("(Length("):
        return "length gate (Length(param))" if "SYM_PARAM" in e else "length gate (rows!=0)"
    if "_size ==" in e:                          return "size gate (CollectionProxy#size)"
    if "_text_empty" in e:                       return "text decision (empty)"
    if "_text_has_mention" in e:                 return "text decision (has_mention)"
    if "_guid" in e:                             return "guid"
    if e.startswith("(assoc_"):                  return "assoc/dispatch"
    if "Anonymous_process" in e:                 return "text decision (rendered)"
    if "diaspora_handle" in e:                   return "diaspora_handle"
    if re.match(r"^\((\w+) != \1\)$", e.strip()):return "self-compare (unsat)"
    return "other"

famtot, famparts = Counter(), Counter()
for p in parts:
    fs = {family(m) for m in p["members"]}
    for f in fs:
        famparts[f] += 1
        famtot[f] += p["remaining"]

# ---- width distribution, weighted ------------------------------------------
w_parts, w_mass = Counter(), Counter()
for p in parts:
    w_parts[p["width"]] += 1
    w_mass[p["width"]] += p["remaining"]
print("\n=== WIDTH DISTRIBUTION (parts / remaining mass / share) ===")
for w in sorted(w_parts, reverse=True):
    print(f"  width {w:>3}: parts {w_parts[w]:>5}  remaining {w_mass[w]:>12}  "
          f"{100.0*w_mass[w]/max(tot,1):6.2f} %")

print("\n=== CONCENTRATION ===")
srt = sorted(parts, key=lambda p: -p["remaining"])
run = 0
for k in (1, 5, 10, 25, 50, 100, 250, 500, 1000):
    if k <= len(srt):
        s = sum(p["remaining"] for p in srt[:k])
        print(f"  top {k:>5} parts hold {s:>12}  {100.0*s/max(tot,1):6.2f} %")
zero = sum(1 for p in parts if p["remaining"] == 0)
print(f"  parts with remaining == 0: {zero}")

print("\n=== TOP PARTS BY REMAINING, members by family ===")
for p in srt[:int(os.environ.get("TOPN", "12"))]:
    print(f"\n  part#{p['i']} width={p['width']} remaining={p['remaining']} "
          f"sat={p['sat']} covered={p['covered']} leaf_groups={p['leaf_groups']} "
          f"cubes={p['cubes']} forecl={p['forecl']} bound={p['bound']}")
    c = Counter(family(m) for m in p["members"])
    for f, n in c.most_common():
        print(f"      {n:>3} x {f}")
    for m in p["members"][:int(os.environ.get("MEMBERS", "0"))]:
        print(f"        - {m[:110]}")

print("\n=== FAMILY SHARE (a part counts once per family it contains) ===")
for f, m in famtot.most_common():
    print(f"  {f:<34} parts {famparts[f]:>5}  mass-in-those-parts {m:>12}  "
          f"{100.0*m/max(tot,1):6.2f} %")

# ---- what the EMITTER reached ---------------------------------------------
for tag, fn in (("cap8 (p12)", "_enum_emit_ORDEMAND.json"),
                ("cap64 (PD)", os.environ.get("EMIT_IN", "_enum_emit_PD64.json"))):
    fp = os.path.join(HERE, fn)
    if not os.path.exists(fp):
        print(f"\nEMIT {tag}: {fn} absent")
        continue
    E = json.load(open(fp))
    st = E["emit_stats"]
    per = Counter()
    for it in E["missing"]:
        per[it["clique"]] += 1
    print(f"\n=== EMITTER REACH — {tag} ({fn}) ===")
    print(f"  cubes={st['cubes']} mass={st['mass']} of remaining={E['remaining_total']} "
          f"({100.0*st['mass']/max(int(E['remaining_total']),1):.2f} %)")
    print(f"  zero_pieces={st['zero']} capped_sets={st['capped_sets']} "
          f"region_bound={st['region_bound']} no_model={st['no_model']} "
          f"mismatch={st['mismatch']} unreach_skipped={st['unreach_skipped']}")
    print(f"  sets with at least one cube: {len(per)}; "
          f"max cubes in one set: {max(per.values()) if per else 0}")
    del E
print("\nPART REPORT DONE")
