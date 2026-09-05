#!/usr/bin/env python3
"""R2 re-judge DETAIL: print the exact real statements that fail to find a
corpus note anywhere, per run, with their target frame. Also print what the
corpus HAS for those targets (sample notes) so we can classify each residual
as: warden-users-load / P-7 (declared open) / P-8 (declared open) / NEW.
"""
import glob
import json
import os
import re
import sys
from collections import defaultdict

BATCH = "/home/dev/project/reports/diaspora/results3/people_show"
RUNS = os.path.join(BATCH, "adversary", "runs")
ALIASES = json.load(open(os.path.join(BATCH, "concrete_aliases.json")))

_DML = ("SELECT", "INSERT", "UPDATE", "DELETE", "WITH", "REPLACE")
def _is_dml(sql):
    return str(sql or "").lstrip().upper().startswith(_DML)

def _wildcard(sql):
    s = re.sub(r"\$\$\([^)]*\)", "?", sql)
    s = re.sub(r"'[^']*'", "'?'", s)
    return re.sub(r"\b\d+\b", "?", s)

try:
    import sqlglot
    from sqlglot import exp
    HAVE = True
except ImportError:
    HAVE = False

def normalize_sqlglot(sql):
    try:
        ast = sqlglot.parse_one(_wildcard(sql), read="postgres")
    except Exception:
        return None
    if not isinstance(ast, exp.Select):
        return None
    tables = {t.name.lower() for t in ast.find_all(exp.Table)}
    projection = set()
    for e in ast.expressions:
        if isinstance(e, exp.Star) or e.find(exp.Star) is not None or isinstance(
                e, (exp.Count, exp.Sum, exp.Max, exp.Min, exp.Avg)):
            projection.add("*")
        else:
            for col in e.find_all(exp.Column):
                projection.add(f"{col.table.lower()}.{col.name.lower()}" if col.table else col.name.lower())
    predicates = set()
    where = ast.args.get("where")
    if where is not None:
        for cmp_node in where.find_all(exp.EQ, exp.NEQ, exp.GT, exp.LT, exp.GTE, exp.LTE, exp.In, exp.Is):
            for col in cmp_node.find_all(exp.Column):
                predicates.add(f"{col.table.lower()}.{col.name.lower()}" if col.table else col.name.lower())
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
    if re.search(r"(\*|COUNT|SUM|MAX|MIN)", sel, re.I) and not re.search(r'[`"]\w+[`"]\.[`"]\w+[`"]', sel):
        projection = {"*"}
    else:
        projection = {f"{t.lower()}.{c.lower()}" for t, c in re.findall(r'[`"]?(\w+)[`"]?\.[`"]?(\w+)[`"]?', sel)}
    where = re.search(r"\bWHERE\b(.*)\Z", s, re.I | re.S)
    where = where.group(1) if where else ""
    predicates = {f"{t.lower()}.{c.lower()}" for t, c in re.findall(
        r'[`"]?(\w+)[`"]?\.[`"]?(\w+)[`"]?\s*(?:=|<>|!=|<|>|IN\b|IS\b)', where, re.I)}
    return {"tables": tables, "projection": projection, "predicates": predicates}

normalize = normalize_sqlglot if HAVE else normalize_regex

# corpus notes: target -> set of notes
corpus_notes = defaultdict(set)
for f in glob.glob(os.path.join(BATCH, "dump_*.json")):
    d = json.load(open(f))
    for ev in d.get("events") or []:
        if ev.get("type") == "symbolic_call" and ev.get("result_name"):
            t = str(ev.get("target") or "").replace("#", ".")
            n = str(ev.get("note") or "")
            if _is_dml(n):
                corpus_notes[t].add(n)

# also notes on symbolic_vars
for f in glob.glob(os.path.join(BATCH, "dump_*.json")):
    d = json.load(open(f))
    for sv in d.get("symbolic_vars") or []:
        n = str(sv.get("note") or "")
        if _is_dml(n):
            # attach under the note's own target if parseable, else skip
            pass

all_shapes = [normalize(n) for ns_ in corpus_notes.values() for n in ns_ if normalize(n)]
all_shapes = [s for s in all_shapes if s]

def matches(n, shapes):
    return any(ns["tables"] == n["tables"] and ns["projection"] >= n["projection"]
               and ns["predicates"] >= n["predicates"] for ns in shapes)

for f in sorted(glob.glob(os.path.join(RUNS, "C*.json"))):
    name = os.path.basename(f)
    print("=" * 110)
    print(f"### {name}")
    for sc in json.load(open(f)):
        for st in sc.get("statements") or []:
            sql = st["sql"]
            if not _is_dml(sql):
                continue
            frame = (st.get("under") or "(outside)").replace("#", ".")
            note_sources = [frame] + ALIASES.get(frame, [])
            notes = set()
            for ns in note_sources:
                notes |= corpus_notes.get(ns, set())
            note_shapes = [normalize(n) for n in notes if normalize(n)]
            n = normalize(sql)
            if n and matches(n, note_shapes):
                continue
            # else: residual
            print(f"  under={frame}")
            print(f"    REAL : {sql[:220]}")
            if n and matches(n, all_shapes):
                print(f"    -> shape EXISTS in corpus under a DIFFERENT target (frame nesting)")
            elif n is None:
                print(f"    -> not a parseable select (non-SELECT DML?): {sql[:100]}")
            else:
                print(f"    -> NO corpus note with tables={n['tables']} anywhere")
                # sample corpus notes for this target
                for ns in note_sources:
                    if corpus_notes.get(ns):
                        for note in sorted(corpus_notes[ns])[:3]:
                            print(f"       corpus[{ns}]: {note[:160]}")