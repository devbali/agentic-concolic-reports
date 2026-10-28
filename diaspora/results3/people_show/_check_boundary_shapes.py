#!/usr/bin/env python3
# _check_boundary_shapes.py — did the fresh dumps emit the 4 sanctioned family shapes?
import json, glob, re
from collections import Counter

files = sorted(glob.glob('/home/dev/project/reports/diaspora/results3/people_show/dump_*.json'))
want = {
    'P1_update_notif': re.compile(r'UPDATE "notifications" SET "notifications"\."unread"', re.I),
    'P2_exists_posts': re.compile(r'SELECT 1 AS one FROM "posts" WHERE "posts"\."guid"', re.I),
    'P2_exists_aspects': re.compile(r'SELECT 1 AS one FROM "aspects"', re.I),
    'P9_pluck_tags':   re.compile(r'SELECT "tags"\."name" FROM "tags"', re.I),
    'P10_owner_dir':   re.compile(r'WHERE "people"\."owner_id"', re.I),
    'P10_person_by_id': re.compile(r'SELECT "people"\.\* FROM "people" WHERE "people"\."id"', re.I),
    'P6_update_user':  re.compile(r'UPDATE "users" SET', re.I),
}
c = Counter()
for f in files:
    d = json.load(open(f))
    text = json.dumps(d)
    for k, pat in want.items():
        if pat.search(text):
            c[k] += 1
print("total dumps:", len(files))
for k in want:
    print(f"{k}: {c[k]}")