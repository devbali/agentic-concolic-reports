#!/usr/bin/env python3
"""Name the MEMBERS of the top parts by decision family, from p12's own emit
(each cube carries its part's gate assignment and, in `cube`, the surviving
members it pins). No census needed."""
import json, os, re
from collections import Counter, defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
E = json.load(open(os.path.join(HERE, "_enum_emit_ORDEMAND.json")))
items = E["missing"]
print("cube keys:", sorted(items[0].keys()))
TOP = [int(x) for x in os.environ.get("TOP", "28,30,29,27,26,23,22,25,24,14,157").split(",")]
def family(e):
    if "_not_found" in e:
        return "find_by_N_not_found" if "FinderMethods_find_by" in e else "findpublic_not_found"
    if re.search(r"_public ==", e):               return "public gate"
    if e.startswith("(SYM_LEN_"):                 return "length gate (rows != 0)"
    if e.startswith("(Length("):                  return "length gate (Length(param))"
    if "_size ==" in e:                           return "size gate (CollectionProxy#size)"
    if "_text_empty" in e:                        return "text decision (empty)"
    if "_text_has_mention" in e:                  return "text decision (has_mention)"
    if "_guid" in e:                              return "guid"
    if e.startswith("(assoc_"):                   return "assoc / dispatch"
    if "Anonymous_process" in e:                  return "text decision (rendered)"
    if "diaspora_handle" in e:                    return "diaspora_handle"
    if re.match(r"^\((\w+) != \1\)$", e.strip()): return "self-compare (unsat)"
    return "other"
EXPR = re.compile(r"\(([^()]*(?:\([^()]*\))?[^()]*)\)")
by_clique = defaultdict(list)
for it in items:
    by_clique[it["clique"]].append(it)
allfam = Counter(); allfam_parts = Counter()
for ci, lst in by_clique.items():
    g = lst[0].get("gates") or {}
    members = set(g)
    for it in lst:
        for k in (it.get("cube") or it.get("assignment") or {}):
            members.add(k)
    c = Counter(family(m) for m in members)
    for f in c:
        allfam_parts[f] += 1
    allfam.update(c)
    if ci in TOP:
        print(f"\n=== part#{ci} width={lst[0]['width']} surviving={lst[0]['surviving']} "
              f"gates={len(g)} members_seen={len(members)} ===")
        for f, n in c.most_common():
            print(f"   {n:>3} x {f}")
        for m in sorted(members)[:24]:
            print(f"     - {m[:104]}")
print("\n=== FAMILY TOTALS over all 1677 parts (members visible in the emit) ===")
for f, n in allfam.most_common():
    print(f"  {n:>6} member-slots in {allfam_parts[f]:>5} parts   {f}")
print("\nTOPPARTS DONE")
