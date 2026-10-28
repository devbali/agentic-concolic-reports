#!/usr/bin/env python3
"""Did the OF0911B round FALSIFY any ARGUMENT P pin? A pin claims one side of
an expression never occurs; a single run recording that side falsifies it.
This is the THIRD falsifier round for the seven pins (TR0910a, TR0910w, this)."""
import glob, json, os, re, sys
from collections import Counter
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from coverage_report import canonicalize_ordinals  # noqa: E402
PINS = {
 "(SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_guid != StringVal(''))": True,
 "(SYM_RESULT_ActsAsApi__Collection_as_api_response_2_row_guid != StringVal(''))": True,
 "(SYM_RESULT_ActsAsApi__Collection_as_api_response_3_row_guid != StringVal(''))": True,
 "(SYM_RESULT_ActsAsApi__Collection_as_api_response_4_row_guid != StringVal(''))": True,
 "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_7_rows != 0)": True,
 "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_8_rows != 0)": True,
 "(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_10_rows != 0)": True,
}
files = sorted(glob.glob(os.path.join(HERE, f"dump_*{os.environ.get('TAG','OF0911B')}*.json")))
print(f"round dumps: {len(files)}")
seen = Counter(); hits = Counter()
for fp in files:
    try:
        d = json.load(open(fp))
    except Exception:
        continue
    canonicalize_ordinals(d)
    for e in d.get("events") or ():
        if e.get("type") != "path_condition":
            continue
        x = str(e.get("expr", ""))
        if x in PINS:
            seen[x] += 1
            if bool(e.get("taken")) == PINS[x]:
                hits[x] += 1
    del d
print(f"\n=== ARGUMENT P — third falsifier round ===")
for e in PINS:
    print(f"  evaluated {seen[e]:>6}   HIT(pinned side taken) {hits[e]:>4}   {e[:78]}")
print(f"\nTOTAL HIT = {sum(hits.values())}  (any HIT falsifies the pin)")
print("FALSIFY DONE")
