#!/usr/bin/env python3
"""In dual dumps: check the TAKEN status of the bare records_1/2 !=0 PCs.
Demanded outcome for missing Family-B is Not(records_1 != 0) i.e. taken=FALSE
(records_1 == 0, since anon Block.none/Contact.none are empty)."""
import json, glob, re

full_re = re.compile(r"len\(SYM_RESULT_ActiveRecord__Relation_(records_[12])(?:_rows)?\) != 0")

taken_false = 0; taken_true = 0; seen = 0
ex_false = ex_true = None
for f in glob.glob("/home/dev/project/reports/diaspora/results3/people_show/dump_anon_mobile_presenter_*.json"):
    try: d = json.load(open(f))
    except: continue
    ev = d.get("events",[])
    for e in ev:
        if e.get("type")!="path_condition": continue
        s = e.get("expr","")
        if full_re.search(s) and "records_1" in s:
            seen += 1
            if e.get("taken") is False:
                taken_false += 1; ex_false = ex_false or (f, s, e.get("taken"))
            else:
                taken_true += 1; ex_true = ex_true or (f, s, e.get("taken"))
print(f"bare records_1 !=0 PCs: {seen}; taken=False (records_1==0): {taken_false}; taken=True (records_1!=0): {taken_true}")
print("example taken=False:", ex_false)
print("example taken=True: ", ex_true)