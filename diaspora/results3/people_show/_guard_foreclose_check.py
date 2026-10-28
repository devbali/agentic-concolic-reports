#!/usr/bin/env python3
"""Positive control + structural check against the real 4984-dump corpus.

Q1 (harness fidelity): does the corpus contain ANY dump where closed_account
    is taken TRUE AND the run still has a full render (>=20 pcs)? If the
    guard-firing runs are ALWAYS short/truncated, the guard forecloses the
    full clique (structural), matching the replay's 0/64 MissingTemplate.

Q2 (corpus ground truth): the 270 Template::Error + 9 MissingTemplate corpus
    dumps -- do they carry fewer pcs than clean runs on average? Guards abort
    early -> fewer exprs evaluated.
"""
import glob, json, re

LEN = re.compile(r"len\(([^()]+)\)")
def norm(s):
    return LEN.sub(lambda m: "SYM_LEN_" + m.group(1), s)

def pcs_of(d):
    out = []
    for e in d.get("events") or []:
        if e.get("type") == "path_condition":
            out.append((norm(e["expr"]), bool(e.get("taken"))))
    return out

files = [f for f in glob.glob("/home/dev/project/reports/diaspora/results3/people_show/dump_*.json")
         if "replay" not in f]
clean, err_tpl, miss_tpl = 0, 0, 0
clean_pcs, err_pcs, miss_pcs = [], [], []
guard_true_full = 0   # closed_account True AND >= 20 pcs
guard_true_short = 0  # closed_account True AND < 20 pcs
no_guard_full = 0     # no closed_account pc at all AND >= 20 pcs
guard_pcs = []
for f in files:
    d = json.load(open(f))
    err = (d.get("error") or {}).get("type")
    pcs = pcs_of(d)
    npc = len(pcs)
    has_guard_true = any(("closed_account" in e and t) for e, t in pcs)
    if err is None:
        clean += 1; clean_pcs.append(npc)
    elif err == "ActionView::Template::Error":
        err_tpl += 1; err_pcs.append(npc)
    elif err == "ActionView::MissingTemplate":
        miss_tpl += 1; miss_pcs.append(npc)
    if has_guard_true:
        guard_pcs.append(npc)
        if npc >= 20: guard_true_full += 1
        else: guard_true_short += 1
    elif npc >= 20:
        no_guard_full += 1

def avg(x): return round(sum(x)/len(x), 1) if x else 0
print("files:", len(files))
print("clean:", clean, "avg pcs", avg(clean_pcs))
print("Template::Error:", err_tpl, "avg pcs", avg(err_pcs))
print("MissingTemplate:", miss_tpl, "avg pcs", avg(miss_pcs))
print()
print("dumps with closed_account taken TRUE:", len(guard_pcs), "avg pcs", avg(guard_pcs))
print("  guard_true AND full(>=20 pcs):", guard_true_full)
print("  guard_true AND short(<20 pcs):", guard_true_short)
print("dumps with NO guard pc AND full(>=20):", no_guard_full)