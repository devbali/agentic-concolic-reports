#!/usr/bin/env python3
"""Find EXACT-duplicate dumps: same variant, same path signature (ordered
(expr,taken)), same note multiset, same consumed seeds, same error. Such a
dump adds no evidence to any check (coverage tree, note shapes, audits) and
its only effect is memory. Writes a list of redundant files."""
import glob, hashlib, json, os, sys

batch = sys.argv[1].rstrip("/")
out = sys.argv[2]
VARIANTS = ("html_plain", "html_withcid", "json_plain", "json_withcid", "mobile_plain", "mobile_withcid", "js_plain", "js_withcid", "xml_plain", "xml_withcid")  # C-8: ten variants (js/xml added, adversary round 3)
files = sorted(glob.glob(os.path.join(batch, "dump_*.json")))
seen = {}
dups = []
for p in files:
    try:
        d = json.load(open(p))
    except Exception:
        continue
    base = os.path.basename(p)
    v = next((x for x in VARIANTS if base.startswith("dump_"+x)), "?")
    h = hashlib.md5()
    h.update(v.encode())
    for ev in d.get("events") or []:
        if ev.get("type") == "path_condition":
            h.update(f"{ev.get('expr')}|{bool(ev.get('taken'))}\n".encode())
    notes = sorted(str(ev.get("note") or "") for ev in (d.get("events") or [])
                   if ev.get("type") == "symbolic_call")
    for nt in notes:
        h.update(("N:"+nt+"\n").encode())
    h.update(("S:"+json.dumps(d.get("concolic_seeds") or {}, sort_keys=True)).encode())
    h.update(("E:"+json.dumps(d.get("error") or {}, sort_keys=True)).encode())
    h.update(("SC:"+json.dumps(d.get("concolic_scenario") or {}, sort_keys=True)).encode())
    k = h.hexdigest()
    if k in seen:
        dups.append(base)
    else:
        seen[k] = base
    del d
with open(out, "w") as fh:
    fh.write("\n".join(dups))
print(f"total={len(files)} distinct={len(seen)} duplicates={len(dups)}")
