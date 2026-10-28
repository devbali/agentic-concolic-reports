"""_blockaid_fold — results3-local extraction normaliser (2026-09-08).

GOAL: every statement the extractor emits must be consumable by blockaid
(src/queries_from_runs/subsume, coverage mode) — only `_MY_UID` / `_NOW`
constants, no `_SYM_RESULT_*` / `_assoc_*` residue, no aggregate select lists,
no LEFT joins, no identifier-as-literal renders, correct AND/OR precedence.

WHY A LOCAL MODULE: src/ is not to be edited (CLAUDE.md source discipline);
the established pattern for fold repairs is results3/_experiment/variant_d/
assoc_fold.py (subclass + narrow, additive monkeypatch).  This module builds on
that one and is installed by the three results3 extractor drivers.

WHAT IT FIXES (each item was measured on the 2026-09-01 / 09-07 extractions,
see queries_from_runs/_REFERENCE_COMPARISON_20260908.md §5):

 E1  people_show driver: `assoc_fold.install()` was called but the driver
     instantiated the BASE `RunTransformer`, so `assoc_bind_map` was never
     built and every `assoc_*` bind stayed a placeholder.  -> the drivers now
     use `Transformer` from this module (AssocFoldingTransformer subclass).
 E2  `SYM_RESULT_<users producer>_person_id` (the principal's person; `users`
     has no person_id column) fell through `_bind_value` to a placeholder.
     -> resolved to the my-person join (`people AS p WHERE p.owner_id =
     _MY_UID`, the same encoding transform.py already uses for SYM_PERSON_*).
 E3  `..._row2_<col>` / `..._item2_<col>` suffixes (row N>1 of the same
     producer relation) were not stripped by pcs._suffix_candidates.
     -> stripped; the bind resolves to the same producer alias, and the
     resulting `x IN (t.c, t.c)` is folded to `x = t.c`.
 E4  A finder whose note is not a SELECT ("User query (class-level finder;
     WHERE unavailable ...)" — `User.find_by(username:)`) had no producer.
     -> a synthetic `SELECT "users".* FROM "users"` producer (flagged
     finder-without-where, exactly the convention transform.py documents).
 E5  `_Build.assemble_where` chained raw `exp.And` nodes; an `exp.Or`
     conjunct was rendered without parentheses (`a AND b OR c AND d`),
     changing precedence.  -> Or conjuncts are wrapped in `exp.Paren`.
 E6  The app's own SQL carries double-quoted STRING literals
     (`"roles"."name" = "admin"`, `"likes"."target_type" = "Post"`); the
     postgres-dialect parse made them identifiers, rendered as a backticked identifier.
     -> double-quoted tokens that are not schema identifiers become '...'.
 E7  `'t'` / `'f'` on boolean columns (app fragment `posts.public = 't'`)
     -> TRUE / FALSE.
 E8  blockaid view conventions on the emitted SQL: `COUNT(*)` -> the pk of
     every FROM table (StripCountStar generalised to joins); `SUM(t.a)` ->
     `t.id, t.a` (the paper's rule); DISTINCT dropped (set semantics);
     `LEFT OUTER JOIN t` with an OR arm on t -> two statements (inner arm /
     other arm without t), otherwise INNER JOIN (FK-backed).
 E9  Any bind still unresolved after E1-E4 is BROADENED (its conjunct dropped,
     or its element removed from an IN list) and the statement is flagged
     `broadened-bind:<name>` so the driver emits a NOTE — the declaration
     survives, the placeholder does not.
 E11 will_paginate's `SELECT COUNT(*) FROM (SELECT DISTINCT t.id ...) subquery`
     note was unparseable for the fold (21,037 errors on the 09-01 corpus, the
     statement silently absent) -> the inner SELECT is used as the producer.
 E10 (opt-in, people_show) the concrete-principal corpus (POLICY_HEADER F6):
     a literal equal to PRINCIPAL_LITERAL_USER_ID on a users-FK column is
     read as `_MY_UID` and flagged `literal-principal`.
"""
from __future__ import annotations

import dataclasses
import re
from typing import List, Optional, Set

import sqlglot
from sqlglot import exp

import os

# App-specific input for src/queries_from_runs (E12, 2026-09-11): the
# package is app-agnostic and REQUIRES an app config (schema, FKs,
# principal/identity conventions, symbol-name shapes, inflections).
# Set before ANY queries_from_runs import that reads it at module level.
os.environ.setdefault("QFR_APP_CONFIG",
                      "/home/dev/project/reports/diaspora/queries_config/app.json")

from queries_from_runs import pcs as _pcs
from queries_from_runs import schema as schema_mod
from queries_from_runs import transform as _t
from queries_from_runs.transform import TransformedQuery, _Producer

import assoc_fold  # results3/_experiment/variant_d (sys.path set by the driver)

_SCHEMA = schema_mod.load_schema()
_ALL_IDENTS: Set[str] = set(_SCHEMA) | {c for cols in _SCHEMA.values() for c in cols}
_USERS_FK_COLS: Set[str] = {"users.id"} | {
    f"{t}.{c}" for (t, c, rt, rc) in schema_mod.load_fks() if rt == "users"
}
_FK_PAIRS = {(t, c, rt, rc) for (t, c, rt, rc) in schema_mod.load_fks()}
_NONSELECT_FINDER_RE = re.compile(r"^User query \(class-level finder; WHERE unavailable")
_DQ_RE = re.compile(r'"([^"]*)"')

PRINCIPAL_LITERAL_USER_ID: Optional[int] = None  # set by the people_show driver


# --------------------------------------------------------------------------
# E6/E7 — note pre-clean (before the postgres-dialect parse)
# --------------------------------------------------------------------------
_orig_tokenize = _t._tokenize_binds


def _preclean(sql: str) -> str:
    def dq(m):
        tok = m.group(1)
        s, e = m.start(), m.end()
        if tok in _ALL_IDENTS or tok == "":
            return m.group(0)
        if e < len(sql) and sql[e] == ".":
            return m.group(0)
        if s > 0 and sql[s - 1] == ".":
            return m.group(0)
        return "'" + tok.replace("'", "''") + "'"
    return _DQ_RE.sub(dq, sql)


_COUNT_SUBQ_RE = re.compile(r"^\s*SELECT\s+COUNT\(\*\)\s+FROM\s+\((SELECT\s+DISTINCT\s+.*)\)\s+(?:AS\s+)?\w+\s*$", re.S | re.I)


def _tokenize_binds_clean(sql: str) -> str:
    m = _COUNT_SUBQ_RE.match(sql)
    if m:  # E11: will_paginate `COUNT(*) FROM (SELECT DISTINCT t.id ...) subquery_for_count`
        sql = m.group(1)  # the counted rows; the DISTINCT is dropped by E8 later
    return _orig_tokenize(_preclean(sql))


# --------------------------------------------------------------------------
# E3 — row-N / item-N suffix stripping
# --------------------------------------------------------------------------
_orig_suffix = _pcs._suffix_candidates


def _suffix_candidates_rowN(suffix: str):
    yield from _orig_suffix(suffix)
    m = re.match(r"^(?:row|item)\d+_(.+)$", suffix)
    if m:
        yield m.group(1)


# --------------------------------------------------------------------------
# E2 — principal person_id, on top of assoc_fold's _bind_value
# --------------------------------------------------------------------------
_inner_bind_value = None  # captured in install(), AFTER assoc_fold.install()


def _bind_value_principal(self, bind: str):
    m = re.match(r"^(.*)_person_id$", bind)
    if m:
        rname = m.group(1)
        prod = self.rt.producers.get(rname)
        if prod is not None and prod.primary_table == "users" and "person_id" not in _SCHEMA.get("users", {}):
            return exp.column("id", table=self.ensure_myperson())
    return _inner_bind_value(self, bind)


# --------------------------------------------------------------------------
# E5 — parenthesised OR conjuncts
# --------------------------------------------------------------------------
def _assemble_where_paren(self, ast: exp.Select) -> None:
    seen: Set[str] = set()
    conj: List[exp.Expression] = []
    for c in self.extra_conjuncts:
        if isinstance(c, exp.Or):
            c = exp.Paren(this=c)
        key = c.sql()
        if key in seen:
            continue
        seen.add(key)
        conj.append(c)
    if not conj:
        return
    node = conj[0]
    for c in conj[1:]:
        node = exp.And(this=node, expression=c)
    ast.set("where", exp.Where(this=node))


# --------------------------------------------------------------------------
# E1/E4 — the transformer
# --------------------------------------------------------------------------
class Transformer(assoc_fold.AssocFoldingTransformer):
    def __init__(self, run, **kw):
        super().__init__(run, **kw)
        for i, ev in enumerate(run.symbolic_call_events):
            note = str(getattr(ev, "note", "") or "")
            if ev.result_name in self.producers or not _NONSELECT_FINDER_RE.match(note):
                continue
            order = getattr(ev, "idx", -1)
            if order < 0:
                order = i
            self.producers[ev.result_name] = _Producer(
                ev.result_name, 'SELECT "users".* FROM "users"', ev.target_name, "users", order
            )


# --------------------------------------------------------------------------
# E8/E9/E10 — post-pass on the emitted SQL
# --------------------------------------------------------------------------
def _tables(ast: exp.Select):
    out = []
    for t in ast.find_all(exp.Table):
        out.append((t.name, t.alias or t.name))
    return out


def _base_table(alias: str, tabs) -> str:
    for name, a in tabs:
        if a == alias:
            return name
    return re.sub(r"\d+$", "", alias)


def _drop_conjuncts(where: Optional[exp.Where], pred) -> Optional[exp.Where]:
    if where is None:
        return None
    conj = [c for c in _t._conjuncts(where) if not pred(c)]
    conj = [exp.Paren(this=c) if isinstance(c, exp.Or) else c for c in conj]
    if not conj:
        return None
    node = conj[0]
    for c in conj[1:]:
        node = exp.And(this=node, expression=c)
    return exp.Where(this=node)


def _mentions(node: exp.Expression, alias: str) -> bool:
    return any(c.table == alias for c in node.find_all(exp.Column))


def finalize(tq: TransformedQuery) -> List[TransformedQuery]:
    """Apply E7-E10 to one TransformedQuery; may return two (LEFT-join arms)."""
    try:
        ast = sqlglot.parse_one(tq.sql, read="mysql")
    except Exception:
        return [tq]
    if not isinstance(ast, exp.Select):
        return [tq]
    flags = set(tq.flags)
    tabs = _tables(ast)

    # E9 broaden leftover binds ------------------------------------------
    leftover = set()
    for col in list(ast.find_all(exp.Column)):
        if col.name.startswith("_") and col.name not in (_t.MY_UID, _t.NOW):
            leftover.add(col.name[1:])
    if leftover:
        for node in list(ast.find_all(exp.In)):
            exprs = [e for e in node.expressions if not (isinstance(e, exp.Column) and e.name[1:] in leftover)]
            if exprs and len(exprs) != len(node.expressions):
                node.set("expressions", exprs)
            # an emptied IN list keeps its placeholder columns and is dropped as a whole below
        ast.set("where", _drop_conjuncts(ast.args.get("where"),
                                         lambda c: any(cc.name[1:] in leftover for cc in c.find_all(exp.Column))))
        for name in sorted(leftover):
            flags.add(("broadened-param:" if name.startswith("SYM_PARAM_") else "broadened-bind:") + name)

    # E3 dedupe IN lists ---------------------------------------------------
    for node in list(ast.find_all(exp.In)):
        seen, exprs = set(), []
        for e in node.expressions:
            k = e.sql()
            if k not in seen:
                seen.add(k)
                exprs.append(e)
        if exprs and len(exprs) == 1 and not node.args.get("query"):
            node.replace(exp.EQ(this=node.this, expression=exprs[0]))
        elif len(exprs) != len(node.expressions):
            node.set("expressions", exprs)

    # E7 't'/'f' on boolean columns ----------------------------------------
    for node in list(ast.find_all(exp.EQ, exp.NEQ)):
        lhs, rhs = node.this, node.expression
        if isinstance(lhs, exp.Column) and isinstance(rhs, exp.Literal) and rhs.is_string and rhs.this in ("t", "f"):
            base = _base_table(lhs.table, tabs)
            if _SCHEMA.get(base, {}).get(lhs.name) == "boolean":
                rhs.replace(exp.Boolean(this=(rhs.this == "t")))

    # E10 literal principal ------------------------------------------------
    if PRINCIPAL_LITERAL_USER_ID is not None:
        for node in list(ast.find_all(exp.EQ)):
            lhs, rhs = node.this, node.expression
            if isinstance(lhs, exp.Column) and isinstance(rhs, exp.Literal) and not rhs.is_string \
                    and str(rhs.this) == str(PRINCIPAL_LITERAL_USER_ID):
                base = _base_table(lhs.table, tabs)
                if f"{base}.{lhs.name}" in _USERS_FK_COLS:
                    rhs.replace(exp.column(_t.MY_UID))
                    flags.add("literal-principal")

    # E8 aggregates / DISTINCT --------------------------------------------
    sel = ast.expressions
    if len(sel) == 1 and isinstance(sel[0], exp.Count) and isinstance(sel[0].this, exp.Star):
        ast.set("expressions", [exp.column("id", table=a) for (_n, a) in tabs])
        flags.add("count-as-pk")
    elif len(sel) == 1 and isinstance(sel[0], exp.Sum) and isinstance(sel[0].this, exp.Column):
        c = sel[0].this
        ast.set("expressions", [exp.column("id", table=c.table), exp.column(c.name, table=c.table)])
        flags.add("sum-as-pk-col")
    if ast.args.get("distinct"):
        ast.set("distinct", None)

    # E8 LEFT joins --------------------------------------------------------
    outs = [ast]
    for j in list(ast.args.get("joins") or []):
        if (j.side or "").upper() != "LEFT":
            continue
        t = j.this
        alias = t.alias or t.name
        where = ast.args.get("where")
        or_node = None
        for c in _t._conjuncts(where):
            inner = c.this if isinstance(c, exp.Paren) else c
            if isinstance(inner, exp.Or) and _mentions(inner, alias):
                or_node = c
                break
        if or_node is None:
            j.set("side", None)
            j.set("kind", "INNER")
            flags.add("left-as-inner")
            continue
        inner = or_node.this if isinstance(or_node, exp.Paren) else or_node
        arms = list(inner.flatten()) if isinstance(inner, exp.Or) else [inner]
        with_t = [a for a in arms if _mentions(a, alias)]
        without_t = [a for a in arms if not _mentions(a, alias)]
        a1 = ast.copy()
        j1 = [jj for jj in a1.args["joins"] if (jj.this.alias or jj.this.name) == alias][0]
        j1.set("side", None)
        j1.set("kind", "INNER")
        repl = with_t[0] if len(with_t) == 1 else exp.Paren(this=exp.or_(*with_t))
        for c in _t._conjuncts(a1.args.get("where")):
            if c.sql() == or_node.sql():
                c.replace(repl)
        a2 = ast.copy()
        a2.set("joins", [jj for jj in a2.args["joins"] if (jj.this.alias or jj.this.name) != alias])
        repl2 = without_t[0] if len(without_t) == 1 else exp.Paren(this=exp.or_(*without_t))
        for c in _t._conjuncts(a2.args.get("where")):
            if c.sql() == or_node.sql():
                c.replace(repl2)
        a2.set("where", _drop_conjuncts(a2.args.get("where"), lambda c: _mentions(c, alias)))
        flags.add("left-join-split")
        outs = [a1, a2] if without_t else [a1]
        break

    result = []
    for a in outs:
        _t._quote_columns(a)
        result.append(dataclasses.replace(
            tq, sql=a.sql(dialect="mysql"), n_tables=len(list(a.find_all(exp.Table))),
            flags=tuple(sorted(flags)), placeholders=(),
        ))
    return result


def install() -> None:
    """Idempotent, additive, in-process only."""
    global _inner_bind_value
    assoc_fold.install()
    if _t._Build._bind_value is not _bind_value_principal:
        _inner_bind_value = _t._Build._bind_value  # assoc_fold's patched one
        _t._Build._bind_value = _bind_value_principal
    if _t._Build.assemble_where is not _assemble_where_paren:
        _t._Build.assemble_where = _assemble_where_paren
    if _pcs._suffix_candidates is not _suffix_candidates_rowN:
        _pcs._suffix_candidates = _suffix_candidates_rowN
    if _t._tokenize_binds is not _tokenize_binds_clean:
        _t._tokenize_binds = _tokenize_binds_clean
        assoc_fold._tokenize_binds = _tokenize_binds_clean
