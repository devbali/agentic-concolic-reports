#!/usr/bin/env python3
"""Family composition of the 64 missing items (current coverage_summary.json).

For each missing item, count how many DISTINCT expr families appear in its
node_constraint, and which families. This tells us what co-occurrence depth
a run would need to witness it.
"""
import json
import os
import re

HERE = "/home/dev/project/reports/diaspora/results3/people_show"

with open(os.path.join(HERE, "coverage_summary.json")) as f:
    d = json.load(f)
missing = d.get("missing", [])

FAMILIES = {
    "vd": re.compile(r"Contains\(StringVal\('\.'\), SubString\(SYM_PERSON_via_user_diaspora_handle, 0, [12]\)\)"),
    "vb": re.compile(r"\(SubString\(SYM_PERSON_via_user_diaspora_handle, 0, (?:Length\(SYM_PERSON_via_user_diaspora_handle\) - 0|1)\) == ''\)"),
    "vg": re.compile(r"\(SYM_PERSON_via_user_guid == ''\)"),
    "vge": re.compile(r"Not\(\(SYM_PERSON_via_user_guid != StringVal\(''\)\)\)"),
    "vc": re.compile(r"\(SYM_PERSON_via_user_closed_account == True\)"),
    "vdlen": re.compile(r"Contains\(StringVal\('\.'\), SubString\(SYM_PERSON_via_user_diaspora_handle, 0, Length\(SYM_PERSON_via_user_diaspora_handle\) - 0\)\)"),
    "f1b": re.compile(r"\(SubString\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, (?:Length\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle\) - 0|1)\) == ''\)"),
    "f1d": re.compile(r"Contains\(StringVal\('\.'\), SubString\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, [12]\)\)"),
    "f1dlen": re.compile(r"Contains\(StringVal\('\.'\), SubString\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, Length\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle\) - 0\)\)"),
    "rows": re.compile(r"\(len\(SYM_RESULT_ActiveRecord__Relation_(?:records_\d+_rows|to_a_\d+_rows)\) [>!]=? 0\)"),
    "nsfw": re.compile(r"\(assoc_profile_nsfw == True\)"),
    "pd": re.compile(r"\(assoc_profile_public_details == True\)"),
    "guidE": re.compile(r"\(assoc_author_guid == ''\)"),
    "by": re.compile(r"\(assoc_profile_birthday_year <= \d+\)"),
    "nf1": re.compile(r"\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found == True\)"),
    "ca1": re.compile(r"\(SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account == True\)"),
    "cont": re.compile(r"Contains\(StringVal\('@'\), (?:SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle|SYM_PERSON_via_user_diaspora_handle)\)"),
}

import collections
fam_counts = collections.Counter()
depth_counts = collections.Counter()
samples = {}
for i, m in enumerate(missing):
    nc = m.get("node_constraint", "")
    fams = tuple(sorted(k for k, pat in FAMILIES.items() if pat.search(nc)))
    fam_counts[fams] += 1
    depth_counts[len(fams)] += 1
    if fams not in samples:
        samples[fams] = (i, nc)

print("== missing item depth distribution ==")
for d in sorted(depth_counts):
    print(f"  depth {d}: {depth_counts[d]} items")
print("\n== distinct family-sets (with item counts) ==")
for fams, n in fam_counts.most_common(20):
    print(f"  n={n}: {fams}")
print("\n== first sample per family-set ==")
shown = 0
for fams, (i, nc) in samples.items():
    if shown >= 3:
        break
    print(f"\n--- item {i} families={fams} ---")
    print(nc[:600])
    shown += 1