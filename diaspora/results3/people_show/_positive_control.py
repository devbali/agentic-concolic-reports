#!/usr/bin/env python3
"""Positive control: does the replay harness itself render people_show (non-404)
under BENIGN seeds? If yes, the 404 MissingTemplate is caused by the closed-account
seeds (genuine guard-foreclose). If even benign seeds 404, the harness is broken.

We emulate the harness by checking an actual corpus dump that IS a clean people_show
render (no error, e.g. dump_anon_mobile_presenter_0001.json has error None, 25 pcs) --
that proves the dual scenario CAN render. Then we confirm the replay's seed for item 0
forces closed_account=True (guard) which the corpus never does.
"""
import json, glob, re

cs = json.load(open("reports/diaspora/results3/people_show/coverage_summary.json"))
print("summary: complete=%s truncated=%s missing=%d solver_lost=%d unevaluable=%s" % (
    cs["coverage_complete"], cs["truncated"], len(cs["missing"]),
    cs["solver_lost"], len(cs["unevaluable_exprs"])))

# 1. Does the corpus contain clean people_show renders (positive control for harness)?
import os
files = [f for f in glob.glob("reports/diaspora/results3/people_show/dump_*.json") if "replay" not in f]
clean = [f for f in files if (json.load(open(f)).get("error") is None)]
tpl_err = [f for f in files if (json.load(open(f)).get("error") or {}).get("type")=="ActionView::Template::Error"]
miss = [f for f in files if (json.load(open(f)).get("error") or {}).get("type")=="ActionView::MissingTemplate"]
print("corpus: total=%d clean=%d TemplateError=%d MissingTemplate=%d" % (len(files), len(clean), len(tpl_err), len(miss)))

# 2. How many of the 64 missing items force closed_account=True or not_found=True?
def has(seq, keys, val=True):
    return any(k in seq and v is val for k, v in seq.items()
               for kk in keys if kk in k) if seq else False

s = json.load(open("/tmp/per_item_sat.json"))
rows = s["rows"]
n_closed = sum(1 for r in rows if has(r.get("model") or {}, ["closed_account"], True))
n_notfound = sum(1 for r in rows if has(r.get("model") or {}, ["not_found"], True))
n_guard = sum(1 for r in rows if has(r.get("model") or {}, ["closed_account","not_found"], True))
print("missing items (of 64): forcing closed_account=True: %d ; forcing not_found=True: %d ; either guard: %d" % (
    n_closed, n_notfound, n_guard))

# 3. Of those forcing closed_account, do they ALSO require post-guard branches (unreachable)?
#    closed_account=True alone forecloses people_show (guard raises first).
n_closed_only_simple = sum(1 for r in rows
    if r.get("model", {}).get("SYM_PERSON_via_user_closed_account") is True
    and not any("_rows" in k for k in r["model"]))
print("items with SYM_PERSON_via_user_closed_account=True (guard):", n_closed_only_simple)