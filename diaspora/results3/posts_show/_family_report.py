#!/usr/bin/env python3
"""§76.2(a) — name the residual's DECISION FAMILIES from the instruments that
already ran: _disq_why.json (the 52 genuinely two-sided / 21 unresolved) and
_sep_pairs.json. Pure bookkeeping over small files."""
import json, os, re
from collections import Counter
HERE = os.path.dirname(os.path.abspath(__file__))

def family(e):
    if "_not_found" in e:
        return "find_by_N_not_found" if "FinderMethods_find_by" in e else "findpublic_not_found"
    if re.search(r"_public ==", e):              return "public gate"
    if e.startswith("(SYM_LEN_"):                return "length gate (rows != 0)"
    if e.startswith("(Length("):                 return "length gate (Length(param))"
    if "_size ==" in e:                          return "size gate (CollectionProxy#size)"
    if "_text_empty" in e:                       return "text decision (empty)"
    if "_text_has_mention" in e:                 return "text decision (has_mention)"
    if "_guid" in e:                             return "guid"
    if e.startswith("(assoc_"):                  return "assoc / dispatch"
    if "Anonymous_process" in e:                 return "text decision (rendered)"
    if "diaspora_handle" in e:                   return "diaspora_handle"
    if re.match(r"^\((\w+) != \1\)$", e.strip()):return "self-compare (unsat)"
    return "other"

D = json.load(open(os.path.join(HERE, "_disq_why.json")))
print("keys:", list(D))
for k in D:
    v = D[k]
    if isinstance(v, list) and v and isinstance(v[0], (str, list)):
        names = [x if isinstance(x, str) else x[0] for x in v]
        c = Counter(family(n) for n in names)
        print(f"\n=== {k}: {len(names)} ===")
        for f, n in c.most_common():
            print(f"  {n:>4}  {f}")
        for n in names[:4]:
            print(f"    e.g. {n[:104]}")
    elif isinstance(v, dict):
        c = Counter(family(n) for n in v)
        print(f"\n=== {k}: {len(v)} ===")
        for f, n in c.most_common():
            print(f"  {n:>4}  {f}")
print("\nFAMILY REPORT DONE")
