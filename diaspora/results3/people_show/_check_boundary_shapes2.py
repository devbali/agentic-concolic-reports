#!/usr/bin/env python3
# _check_boundary_shapes2.py — decoded-note shape check for the 4 sanctioned families.
import json, glob, re
from collections import Counter

files = sorted(glob.glob('/home/dev/project/reports/diaspora/results3/people_show/dump_*.json'))
want = {
    'P1_update_notif':   re.compile(r'UPDATE "notifications" SET .*"unread"', re.I),
    'P2_exists_posts':   re.compile(r'SELECT 1 AS one FROM "posts" WHERE "posts"\."guid"', re.I),
    'P2_exists_aspects': re.compile(r'SELECT 1 AS one FROM "aspects"', re.I),
    'P2_exists_roles':   re.compile(r'SELECT 1 AS one FROM "roles"', re.I),
    'P9_pluck_tags':     re.compile(r'SELECT "tags"\."name" FROM "tags"', re.I),
    'P10_owner_dir':     re.compile(r'WHERE "people"\."owner_id"', re.I),
    'P10_user_scope':    re.compile(r'SELECT .*"users"\.\* FROM "users" WHERE "users"\."id"', re.I),
    'P3_closed':         re.compile(r'closed_account', re.I),
}
c = Counter()
scen_hits = {}
for f in files:
    d = json.load(open(f))
    scen = f.split('/')[-1].split('_')[1]
    notes = " ".join(str(e.get('note', '')) for e in d.get('events', []) if e.get('type') == 'symbolic_call')
    for k, pat in want.items():
        if pat.search(notes):
            c[k] += 1
            scen_hits.setdefault(k, set()).add(scen)
print("total dumps:", len(files))
for k in want:
    print(f"{k}: {c[k]}  (in scenarios: {sorted(scen_hits.get(k, set()))})")