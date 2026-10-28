#!/usr/bin/env python3
"""List the EXTRA (table, column) pairs a policy discloses relative to the
benchmark reference — i.e. exactly what drags disclosure_precision below 1.0.

Usage: _extra_pairs.py <results.jsonl> [task_id_substring]
"""
import json
import os
import sys

BENCH = "/home/dev/project/policy-extraction-bench"
sys.path.insert(0, BENCH)
from bench import grade, sqlnorm, tasks as tasklib  # noqa: E402


def main():
    path = sys.argv[1]
    want = sys.argv[2] if len(sys.argv) > 2 else None

    all_tasks = {t["task_id"]: t for t in tasklib.load()}
    schema_cache = {}

    for line in open(path):
        rec = json.loads(line)
        tid = rec.get("task_id")
        if want and want not in tid:
            continue
        task = all_tasks.get(tid)
        if task is None:
            print(f"{tid}: no such task")
            continue
        app = task["app"]
        if app not in schema_cache:
            schema_cache[app] = sqlnorm.parse_schema(tasklib.schema_path(task))
        sc = schema_cache[app]

        ref = grade.analyse(tasklib.reference(task), sc)
        got = grade.analyse(rec.get("answer_sql", ""), sc)
        extra = got["columns"] - ref["columns"]
        missing = ref["columns"] - got["columns"]
        p, r, f = grade.prf(got["columns"], ref["columns"])
        print(f"=== {tid} ===")
        print(f"  pred_cols={len(got['columns'])} ref_cols={len(ref['columns'])}")
        print(f"  disclosure_precision={p:.4f} recall={r:.4f} f1={f:.4f}")
        print(f"  EXTRA pairs ({len(extra)}):")
        for t, c in sorted(extra):
            print(f"    + {t}.{c}")
        if missing:
            print(f"  MISSING pairs ({len(missing)}):")
            for t, c in sorted(missing):
                print(f"    - {t}.{c}")
        print()


if __name__ == "__main__":
    main()
