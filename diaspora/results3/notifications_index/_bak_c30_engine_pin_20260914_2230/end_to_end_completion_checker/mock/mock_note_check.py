#!/usr/bin/env python3
"""DETERMINISTIC MOCK CHECKER (the script form — Bali directive
2026-08-25: "why did we not do every mock; make it a lot more
deterministic, more just like a script that is run").

    python3 mock_note_check.py <concrete_run.json> <batch_dir> [--aliases a.json]

No per-mock manifest entries, no hand-written fixtures. The inputs are
things that already exist mechanically:
  LEFT:  the concrete run's REAL statements, each tagged with the
         target-function frame it was issued under (concrete_run_probe's
         sql.active_record capture + the tracer's frame thread-local);
  RIGHT: the corpus's notes for the SAME target function (symbolic_call
         events grouped by target).

Per target function that issued real statements, the verdict is a shape
comparison (tables + predicate columns + projection, literals/binds
wildcarded — same normalizer as statement_diff):
  NOTE-OK        every real statement shape under this target has a
                 matching corpus-note shape for this target (aliases map
                 applies)
  NOTE-MISSING   the target issues real SQL but has NO SQL-shaped corpus
                 note at all — the Person#name class: a target mock
                 emitting junk/no evidence over a SQL-reaching body
  NOTE-MISMATCH  notes exist but no shape matches this real statement —
                 the pluck-projection class
Targets that issued no real statements are listed as no-sql (nothing to
check here; the shim contract for them is T1's job).
Exit 1 on any NOTE-MISSING / NOTE-MISMATCH.

This subsumes the manifest's :target_note entries; hand fixtures remain
only for (a) M2 100%-coverage top-ups on branches the endpoint scenario
does not reach and (b) shim probes for methods outside any target frame.
"""
import glob
import json
import os
import sys
from collections import defaultdict

import re

# --- statement normalizer (inlined 2026-08-26 from the retired statement_diff.py;
#     the SQL-level differ now lives in reports/diaspora/tools/) ---
try:
    import sqlglot
    from sqlglot import exp
    HAVE_SQLGLOT = True
except ImportError:
    HAVE_SQLGLOT = False



# INSTR-7 (conversations adversary R4, 2026-08-30): both judges compared
# SELECTs only, so a run with four `UPDATE "users"` scored green. A data
# access is any DML statement; transaction control and pragmas are not.
_DML = ("SELECT", "INSERT", "UPDATE", "DELETE", "WITH", "REPLACE")
def _is_dml(sql):
    return str(sql or "").lstrip().upper().startswith(_DML)

def _wildcard(sql):
    s = re.sub(r"\$\$\([^)]*\)", "?", sql)
    s = re.sub(r"'[^']*'", "'?'", s)
    return re.sub(r"\b\d+\b", "?", s)


def normalize_sqlglot(sql):
    try:
        ast = sqlglot.parse_one(_wildcard(sql), read="postgres")
    except Exception:
        return normalize_regex(sql)
    if not isinstance(ast, exp.Select):
        return normalize_regex(sql)
    tables = {t.name.lower() for t in ast.find_all(exp.Table)}
    projection = set()
    for e in ast.expressions:
        if isinstance(e, exp.Star) or e.find(exp.Star) is not None or isinstance(
                e, (exp.Count, exp.Sum, exp.Max, exp.Min, exp.Avg)):
            projection.add("*")
        else:
            for col in e.find_all(exp.Column):
                projection.add(f"{col.table.lower()}.{col.name.lower()}"
                               if col.table else col.name.lower())
    predicates = set()
    where = ast.args.get("where")
    if where is not None:
        for cmp_node in where.find_all(exp.EQ, exp.NEQ, exp.GT, exp.LT,
                                       exp.GTE, exp.LTE, exp.In, exp.Is):
            for col in cmp_node.find_all(exp.Column):
                predicates.add(f"{col.table.lower()}.{col.name.lower()}"
                               if col.table else col.name.lower())
    return {"tables": tables, "projection": projection, "predicates": predicates}


def normalize_regex(sql):
    s = _wildcard(sql)
    tables = set()
    for m in re.finditer(r'\bFROM\s+[`"]?(\w+)[`"]?', s, re.I):
        tables.add(m.group(1).lower())
    for m in re.finditer(r'\bJOIN\s+[`"]?(\w+)[`"]?', s, re.I):
        tables.add(m.group(1).lower())
    for m in re.finditer(r',\s*[`"](\w+)[`"](?:\s+AS\s+\S+)?', s):
        tables.add(m.group(1).lower())
    sel = re.search(r"\ASELECT\s+(.*?)\s+FROM\b", s, re.I | re.S)
    sel = sel.group(1) if sel else ""
    if re.search(r"(\*|COUNT|SUM|MAX|MIN)", sel, re.I) and not re.search(
            r'[`"]\w+[`"]\.[`"]\w+[`"]', sel):
        projection = {"*"}
    else:
        projection = {f"{t.lower()}.{c.lower()}" for t, c in
                      re.findall(r'[`"]?(\w+)[`"]?\.[`"]?(\w+)[`"]?', sel)}
    where = re.search(r"\bWHERE\b(.*)\Z", s, re.I | re.S)
    where = where.group(1) if where else ""
    predicates = {f"{t.lower()}.{c.lower()}" for t, c in re.findall(
        r'[`"]?(\w+)[`"]?\.[`"]?(\w+)[`"]?\s*(?:=|<>|!=|<|>|IN\b|IS\b)', where, re.I)}
    return {"tables": tables, "projection": projection, "predicates": predicates}


normalize = normalize_sqlglot if HAVE_SQLGLOT else normalize_regex




def main():
    args = sys.argv[1:]
    if len(args) < 2:
        sys.exit("usage: mock_note_check.py <concrete_run.json> <batch_dir> [--aliases a.json]")
    run_path, batch = args[0], args[1]
    aliases = {}
    if "--aliases" in args:
        aliases = json.load(open(args[args.index("--aliases") + 1]))

    corpus_notes = defaultdict(set)   # target -> set of note strings
    for f in glob.glob(os.path.join(batch, "dump_*.json")):
        d = json.load(open(f))
        for ev in d.get("events") or []:
            if ev.get("type") == "symbolic_call" and ev.get("result_name"):
                t = str(ev.get("target") or "").replace("#", ".")
                n = str(ev.get("note") or "")
                if _is_dml(n):
                    corpus_notes[t].add(n)

    real_by_target = defaultdict(list)
    for sc in json.load(open(run_path)):
        for st in sc.get("statements") or []:
            frame = (st.get("under") or "(outside any target frame)").replace("#", ".")
            if _is_dml(st["sql"]):
                real_by_target[frame].append(st["sql"])

    red = False
    print(f"== mock_note_check: {len(real_by_target)} target frames issued real SELECTs; "
          f"{len(corpus_notes)} targets carry corpus notes ==\n")
    for tgt, stmts in sorted(real_by_target.items()):
        note_sources = [tgt] + aliases.get(tgt, [])
        notes = set()
        for n in note_sources:
            notes |= corpus_notes.get(n, set())
        note_shapes = [normalize(n) for n in notes]
        if tgt == "(outside any target frame)":
            print(f"-- statements OUTSIDE any target frame ({len(stmts)}) — each needs a "
                  "declared target or a waiver (evidence minted nowhere):")
            for s in sorted(set(stmts))[:8]:
                print(f"     {s[:110]}")
            red = True
            print()
            continue
        if not note_shapes:
            red = True
            print(f"NOTE-MISSING  {tgt}  <-- RED: issues real SQL, zero SQL-shaped corpus notes")
            for s in sorted(set(stmts))[:4]:
                print(f"     real: {s[:110]}")
            print()
            continue
        all_shapes = [normalize(n) for ns_ in corpus_notes.values() for n in ns_]

        def matches(n, shapes):
            return any(ns["tables"] == n["tables"] and ns["projection"] >= n["projection"]
                       and ns["predicates"] >= n["predicates"] for ns in shapes)

        bad, elsewhere = [], []
        for st in set(stmts):
            n = normalize(st)
            if matches(n, note_shapes):
                continue
            # frame nesting: the statement tags to the INNERMOST frame, but
            # its note may live under the OUTER target that intercepted the
            # call concolically — a note anywhere in the corpus counts, with
            # an annotation (never silently)
            (elsewhere if matches(n, all_shapes) else bad).append(st)
        if elsewhere:
            print(f"NOTE-OK*      {tgt}  ({len(elsewhere)} shape(s) matched under a DIFFERENT target — frame nesting)")
        if bad:
            red = True
            print(f"NOTE-MISMATCH {tgt}  <-- RED: {len(bad)} real statement shape(s) with NO corpus note anywhere")
            for st in bad[:4]:
                print(f"     real: {st[:110]}")
        if not bad and not elsewhere:
            print(f"NOTE-OK       {tgt}  ({len(set(stmts))} real shapes matched)")
    print()
    print("RESULT: RED — target mocks with missing/mismatched notes above."
          if red else "RESULT: every SQL-issuing target's notes match its real statements.")
    sys.exit(1 if red else 0)


if __name__ == "__main__":
    main()
