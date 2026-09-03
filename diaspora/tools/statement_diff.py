#!/usr/bin/env python3
"""C1 statement differential (CHECKS.md Part IV) — THE completion check.

    PYTHONPATH=src venvs/queries_from_runs/bin/python \\
        statement_diff.py <real_stmts.json> <batch_dir> [--views extracted.sql]

Left side:  ground truth — the statements a REAL run of the endpoint
            issued (captured with the runtime-side statement_log probe).
Right side: the corpus's emitted notes and, with --views, the folded
            extraction output (violations 5/8 proved evidence can be
            recorded and still lost at fold time — check both layers).

Normalizes both sides to {tables, projection columns, predicate columns}
with literals wildcarded and binds ($$()/?/N) unified — via sqlglot when
available (the same machinery the fold uses), regex fallback otherwise.
Verdict per real statement: MATCHED / MIS-SHAPED (tables match,
projection or predicate columns differ — the pluck class) / SWALLOWED
(no counterpart over these tables — the preload class).
Exit 1 on any SWALLOWED or MIS-SHAPED.
"""
import glob
import json
import os
import re
import sys

try:
    import sqlglot
    from sqlglot import exp
    HAVE_SQLGLOT = True
except ImportError:
    HAVE_SQLGLOT = False


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
        sys.exit("usage: statement_diff.py <real_stmts.json> <batch_dir> [--views extracted.sql]")
    real_path, batch = args[0], args[1]
    views_path = args[args.index("--views") + 1] if "--views" in args else None

    raw = json.load(open(real_path))
    real = [(r["sql"] if isinstance(r, dict) else str(r)) for r in raw]
    real = [sql for sql in real if re.match(r"\s*SELECT", sql, re.I)]

    notes = set()
    for f in glob.glob(os.path.join(batch, "dump_*.json")):
        d = json.load(open(f))
        for ev in d.get("events") or []:
            n = str(ev.get("note") or "")
            if re.match(r"\s*SELECT", n, re.I):
                notes.add(n)
    sides = {"corpus notes": [normalize(n) for n in notes]}
    if views_path:
        blocks = [b for b in re.split(r";\s*\n", open(views_path).read())
                  if re.match(r"\s*(--[^\n]*\n\s*)*SELECT", b, re.I)]
        sides["folded views"] = [normalize(b) for b in blocks]

    print(f"(normalizer: {'sqlglot' if HAVE_SQLGLOT else 'regex fallback'})")
    red = False
    for label, shapes in sides.items():
        print(f"== C1 diff vs {label} ({len(shapes)} statements on the right) ==")
        for sql in real:
            n = normalize(sql)
            exact = any(s["tables"] == n["tables"] and s["projection"] >= n["projection"]
                        and s["predicates"] >= n["predicates"] for s in shapes)
            table_only = any(s["tables"] >= n["tables"] for s in shapes)
            verdict = "MATCHED   " if exact else ("MIS-SHAPED" if table_only else "SWALLOWED ")
            red = red or not exact
            print(f"  {verdict} {re.sub(r'\s+', ' ', sql)[:120]}")
            if not exact:
                print(f"             real shape: tables={sorted(n['tables'])} "
                      f"proj={sorted(n['projection'])} preds={sorted(n['predicates'])}")
        print()
    print("RESULT: RED — swallowed or mis-shaped statements above (Class S)."
          if red else "RESULT: every real statement matched.")
    sys.exit(1 if red else 0)


if __name__ == "__main__":
    main()
