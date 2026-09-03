#!/usr/bin/env python3
"""Turn the checker's remaining BLOCKING combinations into SEED_SUFFIXES
scenarios for run_dse.rb.

Exact-name demand seeds are frequently inert on deep decisions: a variable's
name carries the CALL ORDINAL of the mock that minted it, and the ordinal moves
as soon as an earlier decision changes the call sequence (measured: 11 runs
seeded `find_by_1_profile_disp_has_dlink=true`, none of them evaluated that
variable). What the combination actually says is a DIMENSION ("a collection is
empty AND a target-chain guid is blank"), which `SEED_SUFFIXES` sets whatever
ordinal carries it.
"""
import json, os, re, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
summary = json.load(open(os.path.join(HERE, "coverage_summary.json")))
missing = [m for m in summary.get("missing", []) if not m.get("untracked")]

def suffix_of(var: str):
    if var.startswith("SYM_LEN_"):
        return "_rows)"                      # every len(...) var
    for s in ("_text_dlink_is_post", "_text_has_dlink", "_disp_dlink_is_post",
              "_disp_has_dlink", "_text_has_mention", "_mention_inline_name",
              "_target_is_photo", "_text_nil", "_not_found", "_persisted",
              "_person_id", "_guid", "_unread", "_sharing", "_receiving"):
        if var.endswith(s):
            return s
    return None

def value_for(suffix, raw):
    if suffix == "_rows)":
        return int(raw)
    if isinstance(raw, bool):
        return raw
    if isinstance(raw, str):
        if raw in ("True", "False"):
            return raw == "True"
        return raw
    return raw

scen = collections.OrderedDict()
for m in missing:
    vals = m.get("concrete_values") or {}
    atoms = re.findall(r"\(([A-Za-z_][A-Za-z0-9_]*)", m["node_constraint"])
    smap = {}
    for var in atoms:
        s = suffix_of(var)
        if not s or var not in vals:
            continue
        smap[s] = value_for(s, vals[var])
    if not smap:
        continue
    key = json.dumps(smap, sort_keys=True)
    scen.setdefault(key, 0)
    scen[key] += 1

out = [json.loads(k) for k in scen]
json.dump(out, open(os.path.join(HERE, "_demand_suffixes.json"), "w"), indent=1)
print(f"{len(missing)} blocking combos -> {len(out)} distinct suffix scenarios")
for k, n in list(scen.items())[:12]:
    print(f"  x{n:<3} {k}")
