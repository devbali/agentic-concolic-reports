#!/usr/bin/env python3
"""For the dual corpus, determine whether a single dump CAN witness the
cross-format base conjunction that the 48 missing items need:
  Not(records_1 != 0) AND Not(records_2 != 0) AND <rows family present>
plus which additional conjunct families (profile_public, birthday, guid,
NOTC, PD) co-occur in the SAME dump alongside bare records==0 and rows>0.
"""
import json, glob, re

def pcs(d):
    return [e.get("expr","") for e in d.get("events",[]) if e.get("type")=="path_condition"]

rows_re = re.compile(r"SYM_RESULT_ActiveRecord__Relation_(records_[0-9]+_rows|to_a_1_rows)")
bare1_re = re.compile(r"SYM_RESULT_ActiveRecord__Relation_records_1\b")
bare2_re = re.compile(r"SYM_RESULT_ActiveRecord__Relation_records_2\b")

def has(expr, re_): return bool(re_.search(expr))

counts = {"any":0, "bare_zero":0, "rows_present":0, "bare_zero_AND_rows":0}
detail = {"prof_pub":0,"birthday":0,"guid":0,"notc":0,"pd":0,"author_guid":0}
sample = None
for f in glob.glob("/home/dev/project/reports/diaspora/results3/people_show/dump_anon_mobile_presenter_*.json"):
    try: d = json.load(open(f))
    except: continue
    pl = pcs(d)
    if not pl: continue
    counts["any"]+=1
    bare_zero = any(("records_1" in s and "!= 0" in s) for s in pl)
    bare_zero2 = any(("records_2" in s and "!= 0" in s) for s in pl)
    rows = any(rows_re.search(s) for s in pl)
    if bare_zero: counts["bare_zero"]+=1
    if rows: counts["rows_present"]+=1
    if bare_zero and bare_zero2 and rows:
        counts["bare_zero_AND_rows"]+=1
        joined="\n".join(pl)
        if "assoc_profile_public_details" in joined: detail["prof_pub"]+=1
        if "birthday" in joined: detail["birthday"]+=1
        if "guid" in joined: detail["guid"]+=1
        if "not" in joined.lower(): detail["notc"]+=1
        if "provider_display_name" in joined: detail["pd"]+=1
        if "author_guid" in joined: detail["author_guid"]+=1
        if sample is None: sample=(f,pl)

print("dual dumps:", counts["any"])
print("  bare records_1 !=0 PC:", counts["bare_zero"])
print("  rows family present:", counts["rows_present"])
print("  bare records_1==0 AND records_2==0 AND rows:", counts["bare_zero_AND_rows"])
print("  of those, also carry:")
for k,v in detail.items(): print(f"    {k}: {v}")
if sample:
    f,pl=sample
    print("\nsample dump:",f)
    for s in pl[:40]: print("   ", s[:110])