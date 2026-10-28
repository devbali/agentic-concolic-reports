#!/usr/bin/env python3
"""Max multi-clause conjunction depth reached per corpus (baseline vs composed).

Conjunction depth = number of DISTINCT "interesting" expr families co-recorded
in one run (via_user dot/blank/guid, first1 dot/blank, rows>0, plus the
stream/profile/guard families).
"""
import json
import os
import re

BASELINE = "/tmp/pp_preserve"
NEW = "/home/dev/project/reports/diaspora/results3/people_show"

FAMILIES = {
    "vd": re.compile(r"Contains\(StringVal\('\.'\), SubString\(SYM_PERSON_via_user_diaspora_handle, 0, [12]\)\)"),
    "vb": re.compile(r"\(SubString\(SYM_PERSON_via_user_diaspora_handle, 0, (?:Length\(SYM_PERSON_via_user_diaspora_handle\) - 0|1)\) == ''\)"),
    "vg": re.compile(r"\(SYM_PERSON_via_user_guid == ''\)"),
    "vc": re.compile(r"\(SYM_PERSON_via_user_closed_account == True\)"),
    "f1b": re.compile(r"\(SubString\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, (?:Length\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle\) - 0|1)\) == ''\)"),
    "f1d": re.compile(r"Contains\(StringVal\('\.'\), SubString\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, [12]\)\)"),
    "rows": re.compile(r"\(len\(SYM_RESULT_ActiveRecord__Relation_(?:records_\d+_rows|to_a_\d+_rows)\) [>!]=? 0\)"),
    "nsfw": re.compile(r"\(assoc_profile_nsfw == True\)"),
    "pd": re.compile(r"\(assoc_profile_public_details == True\)"),
    "guidE": re.compile(r"\(assoc_author_guid == ''\)"),
    "by": re.compile(r"\(assoc_profile_birthday_year <= \d+\)"),
    "nf1": re.compile(r"\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True\)"),
}

def depth_stats(dirpath):
    files = sorted(f for f in os.listdir(dirpath) if f.startswith("dump_") and f.endswith(".json"))
    depths = {}
    max_run = None
    for f in files:
        try:
            d = json.load(open(os.path.join(dirpath, f)))
        except Exception:
            continue
        flags = set()
        for pc in d.get("events", []):
            if pc.get("type") != "path_condition":
                continue
            e = pc.get("expr", "")
            for k, pat in FAMILIES.items():
                if pat.search(e):
                    flags.add(k)
        depths.setdefault(len(flags), 0)
        depths[len(flags)] += 1
        if max_run is None or len(flags) > max_run[1]:
            max_run = (f, len(flags), sorted(flags))
    return depths, max_run

for name, path in [("BASELINE", BASELINE), ("COMPOSED", NEW)]:
    depths, max_run = depth_stats(path)
    print(f"===== {name} =====")
    for d in sorted(depths):
        print(f"  depth {d}: {depths[d]} runs")
    print(f"  max: {max_run}")