import json, sys, glob, os
sys.path.insert(0, "/home/dev/project/src_new")
from sweep.queue.store import QueueStore
Q = "/home/dev/project/reports/autolab/entrypoints/sweep_out_w3/queue"
BOX = "/home/dev/project/reports/autolab/entrypoints/sweep_out_w3/boxes"

def corpus_evidence(endpoint):
    """Did the agent LIST the dumps, and did it OPEN one?"""
    listed = opened = tools = 0
    for d in glob.glob(f"{BOX}/*batch-{endpoint}-*/"):
        p = os.path.join(d, "ctl", "events.ndjson")
        if not os.path.exists(p):
            continue
        for line in open(p):
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            b = r.get("body") or {}
            if b.get("kind") != "tool_start":
                continue
            tools += 1
            inp = str((b.get("payload") or {}).get("input") or "")
            if "batch" in inp or "dump" in inp:
                listed += 1
            # opening a dump: reading its CONTENT, not just listing the dir
            if ("dump_" in inp and any(v in inp for v in
                    ("cat ", "head ", "json.load", "open(", "read", "jq", "python"))):
                opened += 1
    return tools, listed, opened

rows = []
for e in QueueStore(Q).all():
    if e.kind != "batch":
        continue
    r = e.response or {}
    row = r.get("row") or {}
    tools, listed, opened = corpus_evidence(e.endpoint)
    rows.append({
        "endpoint": e.endpoint, "state": str(e.state),
        "exit_reason": r.get("exit_reason"), "hello": r.get("hello"),
        "packet": bool(r.get("packet")), "invalid": r.get("invalid_reason") or "",
        "box_hours": row.get("box_hours"),
        "derived_usd": (r.get("cost") or {}).get("usd"),
        "tokens": row.get("tokens"),
        "tool_calls": tools, "touched_batch": listed, "opened_dump": opened,
        "last_error": (e.last_error or "")[:200],
    })
rows.sort(key=lambda x: x["endpoint"])
print(json.dumps(rows, indent=1, default=str))
