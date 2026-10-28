#!/usr/bin/env python3
"""NOTE-LESS TARGET CALL AUDIT (the B-8 / M-9 class).

    PYTHONPATH=src python3 noteless_call_audit.py <batch_dir> [--sample N]

A `symbolic_call` event with NO note is a target invocation whose statement
was never recorded: the interceptor takes the note from the returned value,
and a mock returning a falsy value (a finder that found nothing, a false
predicate) has nothing to hang it on. The statement then vanishes from the
corpus and therefore from the extracted policy — on comments_index this
silently dropped the endpoint's own access-control reads, and one dump
extracted to "no SELECT queries recorded for this endpoint" while the real
request read `posts` (adversary round 5, 2026-08-29).

Fix in the batch: publish the note out of band immediately before returning
the falsy value —

    Thread.current[:concolic_pending_note] = sql_for(receiver, args)
    next nil

which `CallInterceptor.extract_note` reads once (a note on the value still
wins, and the channel is always cleared).

Documented walls (render, head, redirect_to, …) legitimately carry no SQL
note and are listed separately as `wall` rather than counted as findings.
"""
import glob
import json
import os
import sys
from collections import defaultdict

WALLS = ("render", "head", "redirect_to", "url_for", "gon", "fetch_and_save",
         "default_render", "_set_rendered_content_type", "devise_mapping",
         "assert_is_devise_resource!", "validate", "status=", "push",
         "escape_segment", "discovery")


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    batch = args[0].rstrip("/")
    sample = int(args[args.index("--sample") + 1]) if "--sample" in args else 0
    files = sorted(glob.glob(os.path.join(batch, "dump_*.json")))
    if sample and len(files) > sample:
        step = len(files) / float(sample)
        files = [files[int(i * step)] for i in range(sample)]

    noteless = defaultdict(lambda: {"events": 0, "dumps": 0, "example": ""})
    walls = defaultdict(int)
    n = tot = 0
    for p in files:
        try:
            d = json.load(open(p))
        except Exception:
            continue
        n += 1
        seen = set()
        for ev in d.get("events") or []:
            if ev.get("type") != "symbolic_call" or not ev.get("result_name"):
                continue
            tot += 1
            note = str(ev.get("note") or "").strip()
            if note:
                continue
            t = str(ev.get("target") or "")
            if any(w in t.lower() for w in WALLS):
                walls[t] += 1
                continue
            f = noteless[t]
            f["events"] += 1
            f["example"] = os.path.basename(p)
            if t not in seen:
                f["dumps"] += 1
                seen.add(t)

    print(f"== noteless_call_audit: {n} dumps, {tot} target-call events ==\n")
    if walls:
        print(f"-- documented walls with no SQL note ({len(walls)} targets) --")
        for t, c in sorted(walls.items(), key=lambda kv: -kv[1])[:6]:
            print(f"  {c:8d}  {t}")
        print()
    if not noteless:
        print("RESULT: pass — every non-wall target call carries a note.")
        sys.exit(0)
    te = sum(f["events"] for f in noteless.values())
    td = sum(f["dumps"] for f in noteless.values())
    print(f"-- NOTE-LESS target calls ({len(noteless)} targets, {td} dumps, {te} events) --")
    print("   each is a statement the corpus never recorded, so the extracted policy loses it")
    for t, f in sorted(noteless.items(), key=lambda kv: -kv[1]["events"])[:12]:
        print(f"  {f['events']:8d} events / {f['dumps']:6d} dumps   {t}\n           e.g. {f['example']}")
    print("\nRESULT: RED — publish the note via Thread.current[:concolic_pending_note] "
          "before returning a falsy value (B-8).")
    sys.exit(1)


if __name__ == "__main__":
    main()
