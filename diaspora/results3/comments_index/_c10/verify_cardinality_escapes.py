#!/usr/bin/env python3
"""Independent check: is every cardinality_consistency_audit CONTRADICTION on
this batch explained by a decision RECORDED IN THE SAME DUMP?

Re-implements the audit's flagging logic verbatim (same regexes), then, for
each flagged event, asks whether the dump ALSO records, for the SAME list/step:
  (E1) `<step>_keys_many == False`  — the distinct-FK count is 1 while the row
       count is many (T-o / M-7: AR emits `= ?`, never `IN (one)`), or
  (E2) `<...>_not_found == True` on ANY row of that step (M-13 partial load).
Prints the explained/unexplained split. Unexplained > 0 is a real corpus defect.
"""
import glob, json, os, re, sys
from collections import defaultdict

BIND_RE = re.compile(r"\$\$\(([A-Za-z_][A-Za-z0-9_]*)\)")
BULK_EMITTER_RE = re.compile(r"(load_intermediate|preload|Preloader|includes)", re.I)
LIMIT1_RE = re.compile(r"\bLIMIT\s+(1|\$\$\([^)]*\)|\?)\s*\Z", re.I)
GT1_RE = re.compile(r"\(\s*(?:len\(|SYM_LEN_)([A-Za-z0-9_]+)\)?\s*>\s*1\s*\)")
KEYSMANY_RE = re.compile(r"\(\s*([A-Za-z0-9_]+)_keys_many\s*==\s*(True|False)\s*\)")
NOTFOUND_RE = re.compile(r"\(\s*([A-Za-z0-9_]+?)_?(?:k\d+_)?not_found\s*==\s*True\s*\)")

batch = sys.argv[1].rstrip("/")
files = sorted(glob.glob(os.path.join(batch, "dump_*.json")))
tot = defaultdict(int)
unexplained_examples = defaultdict(list)
for p in files:
    try: d = json.load(open(p))
    except Exception: continue
    evs = d.get("events") or []
    many, keysmany, notfound = {}, {}, {}
    for ev in evs:
        if ev.get("type") != "path_condition": continue
        e = str(ev.get("expr", "")).strip(); tk = bool(ev.get("taken"))
        m = GT1_RE.match(e)
        if m: many[m.group(1)] = tk
        mk = KEYSMANY_RE.match(e)
        if mk: keysmany[mk.group(1)] = (tk == (mk.group(2) == "True"))
        mn = NOTFOUND_RE.match(e)
        if mn and tk: notfound[mn.group(1)] = True
    if not many: continue
    notes = [(str(ev.get("note") or ""), str(ev.get("target") or ""))
             for ev in evs if ev.get("type") == "symbolic_call"]
    notes += [(str(sv.get("note") or ""), "") for sv in (d.get("symbolic_vars") or [])]
    for note, emitter in notes:
        if not note.lstrip().upper().startswith("SELECT"): continue
        bulk = bool(BULK_EMITTER_RE.search(emitter))
        single_row = bool(LIMIT1_RE.search(note.strip()))
        binds = BIND_RE.findall(note)
        if not binds: continue
        for lst, is_many in many.items():
            base = lst[:-5] if lst.endswith("_rows") else lst
            own = [b for b in binds if b.startswith(base + "_row") and "_row" not in b[len(base)+4:]]
            if not own: continue
            uses_in = bool(re.search(r"\bIN\s*\(\s*\$\$\(", note, re.I))
            partial = any(k and any(b.startswith(k) for b in binds) for k in notfound)
            if partial: continue
            bad = None
            if is_many and not uses_in and bulk and not single_row:
                bad = "MANY/bulk/`=`"
            elif is_many and uses_in and len(own) < 2:
                bad = "MANY/`IN`(1)"
            elif (not is_many) and uses_in and len(own) > 1:
                bad = "ONE/`IN`(n)"
            if not bad: continue
            # E1: a _keys_many == False recorded for the STEP this note binds
            e1 = False
            for b in own:
                for km, val in keysmany.items():
                    if b.startswith(km) and val is False: e1 = True
            # E1b: any _keys_many False on a step of the SAME list
            if not e1:
                for km, val in keysmany.items():
                    if km.startswith(base + "_row") and val is False: e1 = True
            # E2: a not_found True on ANY row of the same list
            e2 = any(k.startswith(base + "_row") for k in notfound)
            tag = "E1 keys_many=False" if e1 else ("E2 sibling not_found" if e2 else "UNEXPLAINED")
            tot[(bad, tag)] += 1
            if tag == "UNEXPLAINED" and len(unexplained_examples[bad]) < 4:
                unexplained_examples[bad].append((os.path.basename(p), re.sub(r"\s+"," ",note)[:110]))
print(f"== escape verification over {len(files)} dumps ==")
for k in sorted(tot): print(f"  {tot[k]:8d}  {k[0]:16s} {k[1]}")
u = sum(v for k, v in tot.items() if k[1] == "UNEXPLAINED")
print(f"\nunexplained events: {u}")
for bad, ex in unexplained_examples.items():
    for f, n in ex: print(f"   {bad}  {f}  {n}")
sys.exit(1 if u else 0)
