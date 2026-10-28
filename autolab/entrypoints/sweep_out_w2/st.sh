#!/bin/bash
Q=/home/dev/project/reports/autolab/entrypoints/sweep_out_w2/queue
/home/dev/project/venvs/sky/bin/python3 -m sweep.queue status --out "$Q" 2>/dev/null | \
 PYTHONPATH=/home/dev/project/src_new /home/dev/project/venvs/sky/bin/python3 -c '
import json,sys,collections
d=json.load(sys.stdin); c=d["counts"]
o=d.get("orphans",{}); ol=o.get("orphans",[]) if isinstance(o,dict) else o
st=collections.Counter(e["state"] for e in d["entries"])
bill=sum(1 for e in d["entries"] if e.get("billing"))
print(f"queued={c[\"queued\"]} provisioned={c[\"provisioned\"]} running={c[\"running\"]} done={c[\"done\"]} failed={c[\"failed\"]} billing={bill} orphans={len(ol)}")
'
