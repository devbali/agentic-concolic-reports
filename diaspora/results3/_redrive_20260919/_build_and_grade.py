#!/usr/bin/env python3
"""Build a bench results jsonl from the baseline one, substituting fresh policy
SQL for the endpoints that were re-driven, then hand it to bench.grade.

Usage:
  _build_and_grade.py <baseline.jsonl> <out.jsonl> <task_id>=<new.sql> [...]
"""
import json
import os
import sys


def main():
    base, out = sys.argv[1], sys.argv[2]
    subs = {}
    for a in sys.argv[3:]:
        tid, path = a.split("=", 1)
        subs[tid] = path

    rows = [json.loads(l) for l in open(base) if l.strip()]
    n = 0
    for r in rows:
        tid = r["task_id"]
        if tid in subs:
            p = subs[tid]
            if not os.path.exists(p):
                print(f"MISSING new sql for {tid}: {p}", file=sys.stderr)
                sys.exit(2)
            with open(p, encoding="utf-8") as fh:
                r["answer_sql"] = fh.read()
            r["source_file"] = p
            r["run"] = r.get("run", "") + "-modfix"
            n += 1
            print(f"substituted {tid} <- {p} ({len(r['answer_sql'])} chars)")
    if n != len(subs):
        print(f"WARNING: {len(subs)} substitutions requested, {n} applied", file=sys.stderr)

    with open(out, "w") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")
    print(f"wrote {out} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
