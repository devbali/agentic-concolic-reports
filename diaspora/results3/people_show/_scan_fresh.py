#!/usr/bin/env python3
# _scan_fresh.py — post-fix scan: which P-target regions fire per scenario.
import json, glob, re, sys

FILES = sorted(glob.glob('/home/dev/project/reports/diaspora/results3/people_show/dump_*.json'))

# Demand shapes (C01-C09 real-run universe + P-targets)
SHAPES = {
    # C01: contacts find_by (P-4)
    "C01_contact_find_by":   re.compile(r'contact_for|"contacts".*person_id|SELECT .*"contacts".*FROM "contacts"', re.I),
    # C02: blocks find_by (P-5)
    "C02_block_find_by":     re.compile(r'block_for|"blocks".*person_id|SELECT .*"blocks".*FROM "blocks"', re.I),
    # P-2: aspects exists?
    "P2_aspects_exists":     re.compile(r'SELECT 1 AS one FROM "aspects"', re.I),
    # P-7: Photo.visible count
    "P7_photo_count":        re.compile(r'COUNT\(\*\) FROM "photos"', re.I),
    # P-9: tags pluck
    "P9_tags_pluck":         re.compile(r'pluck|SELECT "tags"\."name" FROM "tags"', re.I),
    # P-1: write/update DML
    "P1_write_dml":          re.compile(r'\b(update|insert|delete)\b', re.I),
    # P-3: closed_account / find_by guid-username
    "P3_closed":             re.compile(r'closed_account', re.I),
    # P-6: presenter as_json
    "P6_as_json":            re.compile(r'as_json|preloads', re.I),
    # P-8: find_target/profile
    "P8_profile_find":       re.compile(r'find_target|SELECT "profiles"\.\* FROM "profiles"', re.I),
    # P-10: owner_id direction
    "P10_owner_id":          re.compile(r'author_id|owner_id', re.I),
    # stream (mobile)
    "stream":                re.compile(r'for_a_stream|stream_posts|decorated_stream', re.I),
    # 401 (NM-1 C07)
    "C07_401":               re.compile(r'401|Unauthenticated|warden', re.I),
}

def dump_shapes(path):
    with open(path) as f:
        d = json.load(f)
    text = json.dumps(d)
    notes = " ".join(str(e.get("note","")) for e in d.get("events",[]) if e.get("type")=="symbolic_call")
    err = (d.get("error") or {}).get("type","")
    hits = {k: bool(pat.search(text + " " + notes)) for k, pat in SHAPES.items()}
    return hits, err

from collections import defaultdict
scen_hits = defaultdict(lambda: {k: 0 for k in SHAPES})
scen_total = defaultdict(int)
scen_err = defaultdict(lambda: defaultdict(int))

for f in FILES:
    base = f.split('/')[-1]
    # scenario = e.g. dump_anon_handle_0001.json -> anon_handle
    parts = base[len('dump_'):-len('.json')].split('_')
    if parts[0] in ('anon','auth'):
        scen = parts[0] + '_' + parts[1]
    else:
        scen = parts[0]
    hits, err = dump_shapes(f)
    scen_total[scen] += 1
    for k, v in hits.items():
        if v: scen_hits[scen][k] += 1
    if err:
        scen_err[scen][err.split('::')[-1][:30]] += 1

print(f"{'scenario':<24} {'n':>3}  " + " ".join(f"{k:<14}" for k in SHAPES))
for scen in sorted(scen_total):
    row = scen_hits[scen]
    print(f"{scen:<24} {scen_total[scen]:>3}  " + " ".join(f"{row[k]:>3}/{scen_total[scen]:<10}" for k in SHAPES))
    if scen_err[scen]:
        print(f"  errors: {dict(scen_err[scen])}")