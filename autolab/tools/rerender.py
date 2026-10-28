#!/usr/bin/env python3
"""rerender.py — refresh every stored `rendered.sql` from its stored policy.

`tools/build_store.py` COPIES `rendered.sql` out of the evidence store, so each
one is frozen at whatever `domains/ruby_rails_sql/render.py` did on the day its
pipeline ran.  Two renderer fixes landed after round 3 (the `classify_note`
read in `_AtomBuild._inline`, and `[any]`-stripping in `_producer_of`), which
left most stored renders describing a renderer that no longer exists.

This tool re-renders from `policy/policy.txt` — not from the dumps.  The policy
IR is the stored artefact and it round-trips verbatim (`stats/INDEX.md`), so
parsing it back and rendering is exactly the IR -> SQL hook under test, with no
re-exploration and nothing upstream of the hook able to move.

    rerender.py [--write] [--only <endpoint>]...

Default is a DRY RUN: it reports which files would change and by how much, and
writes nothing.  `--write` rewrites `rendered.sql` in place and records the
refresh in that run's `stats.json` under `rendered_sql`.

Needs sqlglot:  venvs/queries_from_runs/bin/python3 tools/rerender.py
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
AUTOLAB = HERE.parent
sys.path.insert(0, "/home/dev/project/src_new")

_VIEWS_RE = re.compile(r"^--\s+(\d+) atoms in; (\d+) views out\.", re.M)


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def _views_out(sql: str):
    """The view count the render states in its own header, or None."""
    m = _VIEWS_RE.search(sql)
    return int(m.group(2)) if m else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--only", action="append", default=[])
    args = ap.parse_args()

    from dumps_to_policy.syntax.policy_text import parse_policy
    from domains.ruby_rails_sql.render import render_sql

    runs = sorted((AUTOLAB / "endpoints").glob("*/*/*/policy/policy.txt"))
    if args.only:
        keep = set(args.only)
        runs = [p for p in runs if p.parts[-5] in keep]

    changed, same, failed, missing = [], [], [], []
    for pol in runs:
        run_dir = pol.parent.parent
        ep = run_dir.parts[-3]
        target = run_dir / "rendered.sql"
        try:
            policy = parse_policy(pol.read_text())
            sql = render_sql(policy, app_config=None)
        except Exception as exc:
            failed.append((str(run_dir.relative_to(AUTOLAB)),
                           f"{type(exc).__name__}: {exc}"))
            continue
        old = target.read_text() if target.exists() else None
        rec = {"endpoint": ep, "run": str(run_dir.relative_to(AUTOLAB)),
               "views_before": _views_out(old) if old else None,
               "views_after": _views_out(sql),
               "bytes_before": len(old) if old else None,
               "bytes_after": len(sql)}
        if old is None:
            missing.append(rec)
        elif _sha(old) == _sha(sql):
            same.append(rec)
            continue
        else:
            changed.append(rec)
        if args.write:
            target.write_text(sql)
            stats = run_dir / "stats.json"
            if stats.exists():
                doc = json.loads(stats.read_text())
                doc["rendered_sql"] = {
                    "refreshed": True,
                    "source": "policy/policy.txt, re-rendered by "
                              "tools/rerender.py",
                    "renderer": "domains.ruby_rails_sql.render.render_sql",
                    "views": rec["views_after"],
                    "views_when_first_stored": rec["views_before"],
                    "sha256": _sha(sql),
                }
                stats.write_text(json.dumps(doc, indent=1) + "\n")

    def _summary(rows):
        moved = [r for r in rows
                 if r["views_before"] is not None
                 and r["views_after"] is not None
                 and r["views_after"] != r["views_before"]]
        return moved

    print(f"== rerender: {len(runs)} stored runs "
          f"({'WROTE' if args.write else 'dry run'}) ==")
    print(f"   rendered.sql identical to a fresh render : {len(same)}")
    print(f"   rendered.sql changed                     : {len(changed)}")
    print(f"   rendered.sql absent, now produced        : {len(missing)}")
    print(f"   render raised                            : {len(failed)}")
    moved = _summary(changed + missing)
    if moved:
        print(f"\n-- view count moved ({len(moved)} runs) --")
        for r in sorted(moved, key=lambda r: r["views_after"] - r["views_before"])[:40]:
            print(f"  {r['views_before']:>4} -> {r['views_after']:<4}  "
                  f"{r['endpoint']}")
        d = sum(r["views_after"] - r["views_before"] for r in moved)
        print(f"   net change in views across those runs: {d:+d}")
    if failed:
        print(f"\n-- render raised ({len(failed)}) --")
        for run, err in failed[:20]:
            print(f"  {run}\n      {err}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
