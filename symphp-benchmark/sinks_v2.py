"""The sink oracle on the v2 engine: the statement is a TERM, not a note.

Same criterion as `sinks.py` (a SQL or shell statement that fails to PARSE,
inherited from Witcher's fault escalation) and the same two verdicts, asked of
a different record. On main a `.` over a symbolic string is a `concat` term,
and every target call encodes each argument as its term. So a sink's call
event (`symbolic_call` for a shell sink or Witcher-Test's SQL sinks, E1's
`concrete_call` for an app's real `mysqli_query`) already carries the WHOLE
statement as a term over the inputs. The harness's note on that event says
only which argument is the statement and what its text was on this run:

    {"statement_arg": "<arg key>", "text": "<this run's statement>"}

For each sink call:

1. **malformed-at-reach.** This run's text does not parse (the harness's
   `text`; if absent, the term evaluated at this run's values).
2. **injectable.** Otherwise, for each input the term reads and each payload in
   `sinks.PAYLOADS`, Z3 is asked -- through the engine's own lowering,
   `dump_ir.smt.Lowering`, of the term AND of every path condition recorded
   before the sink -- for an assignment where the input contains the payload,
   the statement contains it too, and the sink is still reached. The statement
   is then evaluated under that model (`z3.substitute` of every symbol, then
   `simplify`), and kept if it does not parse.

Z3 cannot be asked "does not parse" directly; the payload containment is the
query, the parser is the check. Evaluating the term rather than splicing the
witness into a template means every operation between the input and the sink
that the IR models (substring, itos, ite, concatenation order) is honoured.

Nothing here is the verdict on the benchmark: `judge.py` replays each finding
against the unmodified application under PHP 7.4, as before.
"""

from __future__ import annotations

import json
import typing as t

import z3

import engine  # noqa: F401  (puts the v2 engine on sys.path)
import sinks
from dump_ir import expr as _expr
from dump_ir.run import Run
from dump_ir.smt import Lowering, Unlowerable
from dump_ir.term import Lit, Sym, from_json as _leaf

SQL, SHELL = sinks.SQL, sinks.SHELL
PAYLOADS = sinks.PAYLOADS
parses = sinks.parses


def term_of(raw: t.Any):
    """One argument position's term: an operator tree, a leaf, or None (no term)."""
    if isinstance(raw, dict) and "op" in raw:
        return _expr.from_json(raw)
    try:
        return _leaf(raw)
    except ValueError:
        return None


def render(node) -> str:
    """A readable statement: literals inline, each symbol as `$$(name)`, other terms as `$${...}`."""
    if isinstance(node, Sym):
        return f"$$({node.name})"
    if isinstance(node, Lit):
        return "" if node.value is None else str(node.value)
    if node.op == "concat":
        return "".join(render(a) for a in node.args)
    return "$${" + json.dumps(_expr.to_json(node), sort_keys=True, separators=(",", ":")) + "}"


def statement(event: dict) -> tuple[t.Any, str | None]:
    """(the statement's term, this run's text) from a sink call event and its harness note."""
    try:
        note = json.loads(event.get("note") or "{}")
    except json.JSONDecodeError:
        note = {}
    if not isinstance(note, dict) or "statement_arg" not in note:
        return None, None
    raw = (event.get("args") or {}).get(note["statement_arg"])
    return (term_of(raw) if raw is not None else None), note.get("text")


class Assignment:
    """Every symbol of one run pinned to a value: evaluates a lowered term to a Python value."""

    def __init__(self, lo: Lowering, run: Run, values: dict[str, t.Any]):
        self.lo, self.run, self.values = lo, run, dict(values)

    def pairs(self) -> list:
        out = []
        symbols = self.run.symbols()
        for name, v in self.values.items():
            sv = symbols.get(name)
            if sv is None or sv.sort is None:
                continue
            try:
                var = self.lo.var(name)
                null = self.lo.is_null(Sym(name))
            except Unlowerable:
                continue
            if z3.is_const(null) and not z3.is_true(null) and not z3.is_false(null):
                out.append((null, z3.BoolVal(v is None, self.lo.ctx)))
            if v is None:
                v = "" if z3.is_string(var) else 0 if z3.is_int(var) else False if z3.is_bool(var) else None
            lit = _z3_value(var, v)
            if lit is not None:
                out.append((var, lit))
        return out

    def eval(self, term_z3) -> t.Any:
        out = z3.simplify(z3.substitute(term_z3, *self.pairs()))
        if z3.is_string_value(out):
            return out.as_string()
        if z3.is_true(out) or z3.is_false(out):
            return z3.is_true(out)
        if z3.is_int_value(out):
            return out.as_long()
        return None


def _z3_value(var, v):
    ctx = var.ctx
    if z3.is_string(var) and isinstance(v, str):
        return z3.StringVal(v, ctx)
    if z3.is_int(var) and isinstance(v, int) and not isinstance(v, bool):
        return z3.IntVal(v, ctx)
    if z3.is_bool(var) and isinstance(v, bool):
        return z3.BoolVal(v, ctx)
    return None


def run_values(dump: dict) -> tuple[dict, dict]:
    """(this run's input values, every symbol's value: inputs and each target result)."""
    inputs = {v["name"]: v.get("value") for v in dump["symbolic_vars"]
              if v.get("origin", {}).get("kind") == "input"}
    every = dict(inputs)
    for e in dump["events"]:
        if e.get("type") == "symbolic_call" and isinstance(e.get("result_value"), dict):
            lit = term_of(e["result_value"])
            if isinstance(lit, Lit):
                every[e["result_name"]] = lit.value
    return inputs, every


def findings(dump: dict, families: dict[str, str], timeout_ms: int = 5000) -> list[dict]:
    """Every sink finding in one dump. `families` maps target name -> SQL/SHELL."""
    run = Run.from_dict(dump)
    inputs, every = run_values(dump)
    out = []
    prefix: list[tuple[t.Any, bool, dict]] = []
    for event in dump["events"]:
        if event["type"] == "path_condition":
            prefix.append((event["expr"], bool(event["taken"]), event))
            continue
        if event["type"] not in ("symbolic_call", "concrete_call") or event.get("target") not in families:
            continue
        family = families[event["target"]]
        term, text = statement(event)
        if term is None:
            continue
        site = {"sink": event["target"], "family": family, "file": event.get("file"),
                "lineno": event.get("lineno"), "statement": render(term)}
        if event["type"] == "concrete_call" and isinstance(event.get("summary"), dict):
            site["db_errno"] = event["summary"].get("errno")
        ctx = z3.Context()
        lo = Lowering(run.symbols(), ctx)
        try:
            stmt = lo.term(term)
        except (Unlowerable, z3.Z3Exception):
            continue
        if text is None:
            text = Assignment(lo, run, every).eval(stmt)
        if not isinstance(text, str):
            continue
        if not parses(family, text):
            out.append(site | {"kind": "malformed-at-reach", "instance": text, "witness": inputs})
            continue
        carried = [n for n in sorted(_expr.symbols(term)) if n in inputs]
        for name in carried:
            hit = _inject(run, lo, stmt, prefix, name, inputs, every, family, timeout_ms)
            if hit is not None:
                out.append(site | {"kind": "injectable", "carried": name} | hit)
                break
    return out


def _lowered_prefix(lo: Lowering, prefix) -> list | None:
    conds = []
    for raw, taken, _ in prefix:
        try:
            c = lo.term(_expr.from_json(raw))
        except (Unlowerable, z3.Z3Exception, ValueError):
            return None                       # an unlowerable prefix proposes nothing (as in sinks.py)
        conds.append(c if taken else z3.Not(c))
    return conds


def _inject(run, lo, stmt, prefix, name, inputs, every, family, timeout_ms):
    """A payload-bearing value for `name` that still reaches the sink and breaks the statement, or None."""
    conds = _lowered_prefix(lo, prefix)
    if conds is None:
        return None
    try:
        var = lo.var(name)
        null = lo.is_null(Sym(name))
    except Unlowerable:
        return None
    if not z3.is_string(var) or not z3.is_string(stmt):
        return None
    for payload in PAYLOADS:
        p = z3.StringVal(payload, lo.ctx)
        s = z3.Solver(ctx=lo.ctx)
        s.set("timeout", timeout_ms)
        s.add(*conds, *lo.axioms, z3.Contains(var, p), z3.Contains(stmt, p), z3.Not(null))
        if s.check() != z3.sat:
            continue
        witness = _witness(s.model(), lo, inputs)
        values = {**every, **witness}
        instance = Assignment(lo, run, values).eval(stmt)
        if isinstance(instance, str) and not parses(family, instance):
            return {"payload": payload, "instance": instance, "witness": witness}
    return None


def _witness(m, lo: Lowering, inputs: dict) -> dict:
    """The model's value for every input it constrains; the rest keep this run's value."""
    witness = dict(inputs)
    names = {d.name(): d for d in m.decls() if d.arity() == 0}
    for n in inputs:
        null = names.get(f"is_null({n})")
        if null is not None and z3.is_true(m[null]):
            witness[n] = None
        elif n in names:
            val = m[names[n]]
            if z3.is_string_value(val):
                witness[n] = val.as_string()
        elif null is not None and witness[n] is None:
            witness[n] = ""                   # present, and nothing else asked of it (drive._from_model)
    return witness
