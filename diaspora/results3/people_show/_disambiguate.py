#!/usr/bin/env python3
"""Disambiguate WHICH closed_account/not_found each model forces."""
import json

s = json.load(open("/tmp/per_item_sat.json"))
rows = s["rows"]

def keys_with_true(model, substr):
    return sorted(k for k, v in model.items() if substr in k and v is True)

person_closed = notfnd_person = found_person = 0
only_result_guards = 0
for r in rows:
    m = r.get("model") or {}
    pc = [k for k in keys_with_true(m, "closed_account") if k.startswith("SYM_PERSON_")]
    rn = [k for k in keys_with_true(m, "not_found") if k.startswith("SYM_PERSON_")]
    res_closed = [k for k in keys_with_true(m, "closed_account") if k.startswith("SYM_RESULT_")]
    res_nf = [k for k in keys_with_true(m, "not_found") if k.startswith("SYT_RESULT_")]
    # general: any not_found on RESULT finders
    res_any_nf = [k for k, v in m.items() if "not_found" in k and v is True]
    res_any_ca = [k for k, v in m.items() if "closed_account" in k and v is True]

    if pc: person_closed += 1
    if rn: notfnd_person += 1

    # finder-level (FinderMethods) not_found / closed_account
    finder_nf = [k for k in res_any_nf if "FinderMethods" in k]
    finder_ca = [k for k in res_any_ca if "FinderMethods" in k]

    # counts
    counts = {"finder_nf": len(finder_nf), "finder_ca": len(finder_ca),
              "res_nf_all": len(res_any_nf), "res_ca_all": len(res_any_ca),
              "person_ca": len(pc), "person_nf": len(rn)}
    r["_c"] = counts

print(f"{'idx':>3} {'persCA':>6} {'persNF':>6} {'fndrNF':>6} {'fndrCA':>6} {'resNF':>6} {'resCA':>6}")
for r in rows:
    c = r["_c"]
    print(f"{r['idx']:3d} {c['person_ca']:6d} {c['person_nf']:6d} {c['finder_nf']:6d} {c['finder_ca']:6d} {c['res_nf_all']:6d} {c['res_ca_all']:6d}")

n_person_ca = sum(1 for r in rows if r["_c"]["person_ca"])
n_finder_nf = sum(1 for r in rows if r["_c"]["finder_nf"] and not r["_c"]["person_ca"])
print("\nitems forcing SYM_PERSON_via_user_closed_account=True (real guard):", n_person_ca, "/", len(rows))