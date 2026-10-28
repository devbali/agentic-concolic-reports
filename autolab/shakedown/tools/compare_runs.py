#!/usr/bin/env python3
"""compare_runs.py -- before/after comparison of two shakedown runs.

Reads two run trees (each a directory holding `manifest.jsonl`, `results/`
and `runs/`) and emits one JSON with every number the re-run was asked to
answer, kept SEPARATE the way the shakedown report keeps them:

  counts        ran_clean / no_paths / failed / harness_error / not_attempted
  failures      every failure named individually, with stage + message
  dml           DML-carrying notes, per dump and per endpoint (question 3)
  reach         target-function reach distribution (question 4)
  profiles      RC-1 blast radius (question 6)

DML measurement, stated exactly.  Every recorded note (`SymbolicVar.note`
and `SymbolicCallEvent.note`) is either a JSON object `{"refs":…,"text":…}`
whose `text` is a SQL statement, or prose.  A note is DML-CARRYING iff its
text parses (sqlglot) to an Insert / Update / Delete, or -- when sqlglot
refuses -- begins with INSERT/UPDATE/DELETE.  Counted three ways, because
they answer different questions:
    notes       every DML note occurrence (a statement is usually noted
                twice: once on the SymbolicVar, once on the call event)
    statements  DISTINCT normalised DML statement texts in the dump
    endpoints   endpoints with at least one DML statement anywhere

Usage: compare_runs.py <old_run_dir> <new_run_dir> <out_json>
"""
from __future__ import annotations

import collections
import glob
import json
import os
import re
import sys

WRITEY = re.compile(r'(save|create|update|destroy|delete|insert|touch|'
                    r'increment|decrement|toggle|upsert|import|write)', re.I)
DML_HEAD = re.compile(r'^\s*(INSERT|UPDATE|DELETE)\b', re.I)
STMT = re.compile(r'\b(SELECT|INSERT|UPDATE|DELETE)\b', re.I)


def note_text(n):
    """The SQL (or prose) a note carries."""
    if isinstance(n, dict):
        return n.get("text", "") or ""
    if isinstance(n, str):
        if n.lstrip().startswith("{"):
            try:
                return json.loads(n).get("text", "") or ""
            except Exception:
                return n
        return n
    return ""


def clean(t: str) -> str:
    """Bind markers and inlined Times are not SQL -- same rule as pipeline.py."""
    t = re.sub(r"\$\$\(([^)]*)\)", "'__BIND__'", t)
    t = re.sub(r"(?<![\'\"])\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?"
               r"(?: ?[+-]\d{2}:?\d{2}| UTC)?", "'__TS__'", t)
    return t


def dml_kind(sql: str):
    """INSERT/UPDATE/DELETE, by parse; falls back to the leading keyword."""
    import sqlglot
    from sqlglot import exp
    if not STMT.search(sql):
        return None
    try:
        tree = sqlglot.parse_one(sql)
    except Exception:
        m = DML_HEAD.match(sql)
        return m.group(1).upper() if m else None
    if isinstance(tree, exp.Insert):
        return "INSERT"
    if isinstance(tree, exp.Update):
        return "UPDATE"
    if isinstance(tree, exp.Delete):
        return "DELETE"
    return None


def scan_dump(path: str) -> dict:
    d = json.load(open(path))
    notes = []                      # (holder, name, raw_text)
    for sv in d.get("symbolic_vars", ()):
        if sv.get("note"):
            notes.append(("var", sv.get("name"), note_text(sv["note"])))
    for e in d.get("events", ()):
        if e.get("note"):
            notes.append((e.get("type"), e.get("target"), note_text(e["note"])))

    dml_notes = 0
    dml_stmts = collections.Counter()
    dml_tables = collections.Counter()
    writey_prose = []               # a writey target whose note is not a statement
    for holder, name, raw in notes:
        t = clean(raw)
        k = dml_kind(t)
        if k:
            dml_notes += 1
            dml_stmts[(k, t.strip())] += 1
            m = re.search(r'(?:INTO|UPDATE|FROM)\s+"?([a-z_][a-z0-9_]*)"?', t, re.I)
            dml_tables[(k, m.group(1) if m else "?")] += 1
        elif not STMT.search(t) and WRITEY.search(name or ""):
            writey_prose.append({"target": name, "note": t[:200]})

    # declarations / reach
    decl = d.get("declarations") or {}
    tf = {n for n, s in decl.items()
          if (s.get("kind") if isinstance(s, dict) else s) == "target_function"}
    shim = {n for n, s in decl.items()
            if (s.get("kind") if isinstance(s, dict) else s) == "shim"}
    called = {e.get("target") for e in d.get("events", ())
              if e.get("type") in ("call", "symbolic_call")}
    called.discard(None)
    return {
        "notes": len(notes),
        "dml_notes": dml_notes,
        "dml_statements": sorted(f"{k}|{s}" for k, s in dml_stmts),
        "dml_by_table": {f"{k} {t}": n for (k, t), n in dml_tables.items()},
        "writey_prose_notes": writey_prose,
        "declared_target_functions": len(tf),
        "declared_shims": len(shim),
        "declarations": len(decl),
        "reach": len(tf & called),
        "reached": sorted(tf & called),
    }


def scan_run(root: str) -> dict:
    man = {}
    mpath = os.path.join(root, "manifest.jsonl")
    for line in open(mpath):
        line = line.strip()
        if line:
            r = json.loads(line)
            man[r["endpoint"]] = r          # last wins: a re-drive supersedes

    detail = {}
    for f in glob.glob(os.path.join(root, "results", "*.json")):
        eid = os.path.basename(f)[:-5]
        try:
            detail[eid] = json.load(open(f))
        except Exception:
            pass

    per_ep = {}
    for eid in sorted(man):
        dumps = sorted(glob.glob(os.path.join(root, "runs", eid, "dump_*.json")))
        scans = [scan_dump(p) for p in dumps]
        stmts = set()
        for s in scans:
            stmts |= set(s["dml_statements"])
        tables = collections.Counter()
        for s in scans:
            for k, n in s["dml_by_table"].items():
                tables[k] += n
        prose = [p for s in scans for p in s["writey_prose_notes"]]
        d = detail.get(eid) or {}
        per_ep[eid] = {
            "verdict": man[eid].get("verdict"),
            "dumps": len(dumps),
            "dml_notes": sum(s["dml_notes"] for s in scans),
            "dml_statements": sorted(stmts),
            "n_dml_statements": len(stmts),
            "dml_by_table": dict(tables),
            "writey_prose_notes": prose,
            "declared_target_functions": max((s["declared_target_functions"]
                                              for s in scans), default=0),
            "declarations": max((s["declarations"] for s in scans), default=0),
            "reach_best": max((s["reach"] for s in scans), default=0),
            "reach_worst": min((s["reach"] for s in scans), default=0),
            "reached": sorted({t for s in scans for t in s["reached"]}),
            "reads_profiles": bool(d.get("reads_profiles")),
            "profiles_select_star": bool(d.get("profiles_select_star")),
            "profiles_columns": d.get("profiles_columns") or [],
            "profiles_shapes": d.get("profiles_shapes") or [],
            "path_conditions_max": d.get("path_conditions_max"),
            "failures": [{"stage": f.get("stage"), "type": f.get("type"),
                          "message": f.get("message"), "file": f.get("file")}
                         for f in (d.get("failures") or ())],
            "completion_complete": (d.get("completion") or {}).get("complete"),
            "stages": d.get("stages"),
            "run_seconds": man[eid].get("run_seconds"),
            "dumps_on_disk_manifest": man[eid].get("dumps"),
        }

    counts = collections.Counter(v["verdict"] for v in per_ep.values())
    all_stmts = set()
    for v in per_ep.values():
        all_stmts |= set(v["dml_statements"])
    tables = collections.Counter()
    for v in per_ep.values():
        for k, n in v["dml_by_table"].items():
            tables[k] += n
    reach_dist = collections.Counter(v["reach_best"] for v in per_ep.values())
    reached_all = collections.Counter()
    for v in per_ep.values():
        for t in v["reached"]:
            reached_all[t] += 1
    # how many DUMPS called each target function
    dump_reach = collections.Counter()
    n_dumps = 0
    for eid in per_ep:
        for p in sorted(glob.glob(os.path.join(root, "runs", eid, "dump_*.json"))):
            n_dumps += 1
            for t in scan_dump(p)["reached"]:
                dump_reach[t] += 1

    return {
        "root": root,
        "endpoints": len(per_ep),
        "counts": dict(counts),
        "dumps_total": n_dumps,
        "per_endpoint": per_ep,
        "dml": {
            "endpoints_with_dml": sum(1 for v in per_ep.values()
                                      if v["n_dml_statements"]),
            "total_dml_notes": sum(v["dml_notes"] for v in per_ep.values()),
            "distinct_dml_statements_corpus": len(all_stmts),
            "by_table": dict(tables),
            "writey_prose_endpoints": sorted(e for e, v in per_ep.items()
                                             if v["writey_prose_notes"]),
        },
        "reach": {
            "distribution": dict(sorted(reach_dist.items())),
            "median": sorted(v["reach_best"] for v in per_ep.values())
                      [len(per_ep) // 2] if per_ep else None,
            "zero_reach": sum(1 for v in per_ep.values() if v["reach_best"] == 0),
            "max": max((v["reach_best"] for v in per_ep.values()), default=0),
            "distinct_targets_called": len(reached_all),
            "targets_by_endpoint_count": dict(reached_all.most_common()),
            "targets_by_dump_count": dict(dump_reach.most_common()),
        },
        "profiles": {
            "readers": sorted(e for e, v in per_ep.items() if v["reads_profiles"]),
            "select_star": sorted(e for e, v in per_ep.items()
                                  if v["profiles_select_star"]),
        },
        "failures": [dict(endpoint=e, **f) for e, v in sorted(per_ep.items())
                     for f in v["failures"]],
        "completion_verdicts": dict(collections.Counter(
            str(v["completion_complete"]) for v in per_ep.values())),
        "zero_path_conditions": sorted(e for e, v in per_ep.items()
                                       if (v["path_conditions_max"] or 0) == 0),
    }


def main():
    old_root, new_root, out = sys.argv[1], sys.argv[2], sys.argv[3]
    old, new = scan_run(old_root), scan_run(new_root)
    eps = sorted(set(old["per_endpoint"]) | set(new["per_endpoint"]))
    moved = []
    for e in eps:
        o = old["per_endpoint"].get(e) or {}
        n = new["per_endpoint"].get(e) or {}
        delta = {}
        for k in ("verdict", "dumps", "n_dml_statements", "reach_best",
                  "declared_target_functions", "declarations",
                  "reads_profiles", "profiles_select_star",
                  "path_conditions_max", "completion_complete"):
            if o.get(k) != n.get(k):
                delta[k] = [o.get(k), n.get(k)]
        if delta:
            moved.append({"endpoint": e, "delta": delta})
    res = {"old": old, "new": new, "moved": moved,
           "moved_count": len(moved)}
    json.dump(res, open(out, "w"), indent=2)
    for side, r in (("OLD", old), ("NEW", new)):
        print(f"[{side}] {r['root']}")
        print(f"   endpoints={r['endpoints']} dumps={r['dumps_total']} "
              f"counts={r['counts']}")
        print(f"   dml: endpoints_with_dml={r['dml']['endpoints_with_dml']} "
              f"notes={r['dml']['total_dml_notes']} "
              f"distinct_stmts={r['dml']['distinct_dml_statements_corpus']}")
        print(f"   dml by table: {r['dml']['by_table']}")
        print(f"   writey-prose endpoints: {r['dml']['writey_prose_endpoints']}")
        print(f"   reach dist={r['reach']['distribution']} "
              f"median={r['reach']['median']} zero={r['reach']['zero_reach']} "
              f"distinct_targets={r['reach']['distinct_targets_called']}")
        print(f"   profiles readers={r['profiles']['readers']}")
        print(f"   completion={r['completion_verdicts']}")
        print(f"   failures={len(r['failures'])}")
        for f in r["failures"]:
            print(f"      {f['endpoint']:44s} {f['stage']}:{f['type']} "
                  f"{(f.get('message') or '')[:110]}")
    print(f"\nendpoints whose measured fields moved: {len(moved)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
