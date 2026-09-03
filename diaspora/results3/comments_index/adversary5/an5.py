#!/usr/bin/env python3
"""Round-4 helper: split a concrete_run.json scenario's ordered statement list
into per-REQUEST segments and print each request's statement shapes.
Read-only; segments at a `users` finder (signed-in) or a bare post finder (anon)."""
import json, re, sys, collections

def norm(s):
    return re.sub(r'\s+', ' ', s.strip())

def shape(sql):
    s = norm(sql)
    s = re.sub(r'\?', '?', s)
    return s

BARE_POST = re.compile(r'^SELECT "posts"\.\* FROM "posts" WHERE "posts"\."(id|guid)" = \? ORDER BY')
USERS = re.compile(r'^SELECT "users"\.\* FROM "users" WHERE "users"\."id" = \?')

for path in sys.argv[1:]:
    data = json.load(open(path))
    print("=" * 100); print(path)
    for sc in data:
        if sc["name"] == "_cumulative_coverage":
            continue
        segs = []
        cur = None
        for st in sc.get("statements", []):
            s = shape(st["sql"])
            if cur is None or USERS.match(s) or BARE_POST.match(s):
                cur = []
                segs.append(cur)
            cur.append((st.get("under"), s))
        print(f"-- {sc['name']}  error={sc.get('error')}  requests_detected={len(segs)}  statements={sum(len(x) for x in segs)}")
        for i, seg in enumerate(segs):
            print(f"  [req {i:02d}]  {len(seg)} statements")
            for frame, s in seg:
                print(f"      ({frame}) {s[:200]}")
