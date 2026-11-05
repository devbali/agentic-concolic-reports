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

**Sanitizers (P3).** Under `--sanitizers` a sanitizer on a symbolic subject is
a shim (sanitizers_v2.php): its result is a fresh symbol, its call event
carries the subject's term, and its note names the function, the subject's
argument key and the other arguments. Z3 knows nothing of the function, so the
symbol is free in the query; what makes the verdict right is the evaluation
step: every sanitizer result reached before the sink is RECOMPUTED, in event
order, by applying the Python twin (`sinks.SANITIZERS`, tested against PHP) to
its subject evaluated under the candidate. So `'...'` . addslashes(x) . `'` is
not a finding and `id=` . addslashes(x) is. A path condition on a sanitizer's
result is checked the same way -- the candidate is dropped if, with the twin's
value, the branch would go the other way -- and each finding lists those
branches under `assumes`, since they are relations the IR does not track.

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

#: PHP 7.4's default flags for htmlspecialchars/htmlentities (ENT_COMPAT | ENT_HTML401): `'` is NOT
#: escaped. The apps and the judge run 7.4; sinks.SANITIZERS (v1) keeps PHP 8.1's ENT_QUOTES default.
PHP74_HTML_FLAGS = 2


def _html74(s: str, flags: int = PHP74_HTML_FLAGS, *rest) -> str:
    return sinks._htmlspecialchars(s, flags, *rest)


#: The Python twins sinks_v2 applies (checked against sanitizers_v2.php and php:7.4 by test_sanitizers_v2.py).
SANITIZERS = {**sinks.SANITIZERS, "htmlspecialchars": _html74, "htmlentities": _html74}
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


class Sanitizer(t.NamedTuple):
    result: str          # the shim's result symbol
    fn: str
    subject: t.Any       # the subject's term
    args: list           # the other arguments, concrete


def sanitizers(dump: dict) -> list[Sanitizer]:
    """Every sanitizer shim call in the dump, in event order (P3)."""
    out = []
    for e in dump["events"]:
        if e.get("type") != "symbolic_call" or not e.get("note"):
            continue
        try:
            note = json.loads(e["note"])
        except (TypeError, json.JSONDecodeError):
            continue
        if not isinstance(note, dict) or note.get("sanitizer") not in SANITIZERS:
            continue
        raw = (e.get("args") or {}).get(note.get("subject"))
        subject = term_of(raw) if raw is not None else None
        if subject is not None:
            out.append(Sanitizer(e["result_name"], note["sanitizer"], subject, list(note.get("args") or [])))
    return out


def _php_string(v: t.Any) -> str:
    """PHP's string conversion of a scalar a twin receives."""
    if v is None or v is False:
        return ""
    if v is True:
        return "1"
    return str(v)


def recompute(lo: Lowering, run: Run, values: dict, shims: list[Sanitizer]) -> dict:
    """`values` with every sanitizer result recomputed by its twin, in order (each may read an earlier one)."""
    values = dict(values)
    for sh in shims:
        try:
            subject = Assignment(lo, run, values).eval(lo.term(sh.subject))
        except (Unlowerable, z3.Z3Exception):
            continue
        if subject is None:
            continue
        values[sh.result] = SANITIZERS[sh.fn](_php_string(subject), *sh.args)
    return values


def carried_inputs(term, inputs: dict, shims: list[Sanitizer]) -> list[str]:
    """The inputs a statement reads, directly or through a sanitizer's subject."""
    by_result = {sh.result: sh for sh in shims}
    seen, todo = set(), set(_expr.symbols(term))
    while todo:
        n = todo.pop()
        if n in seen:
            continue
        seen.add(n)
        if n in by_result:
            todo |= set(_expr.symbols(by_result[n].subject))
    return [n for n in sorted(seen) if n in inputs]


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
    shims = {sh.result: sh for sh in sanitizers(dump)}
    before: list[Sanitizer] = []              # the sanitizer calls recorded so far, in order
    out = []
    prefix: list[tuple[t.Any, bool, dict]] = []
    for event in dump["events"]:
        if event["type"] == "symbolic_call" and event.get("result_name") in shims:
            before.append(shims[event["result_name"]])
            continue
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
        for name in carried_inputs(term, inputs, before):
            hit = _inject(run, lo, stmt, prefix, name, inputs, every, family, timeout_ms, list(before))
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


def _inject(run, lo, stmt, prefix, name, inputs, every, family, timeout_ms, shims=()):
    """A payload-bearing value for `name` that still reaches the sink and breaks the statement, or None."""
    conds = _lowered_prefix(lo, prefix)
    if conds is None:
        return None
    sanitized = {sh.result: sh for sh in shims}
    # The prefix decisions that read a sanitizer's result: re-checked under the twin, and listed.
    on_sanitized = [(c, ev) for c, (raw, _, ev) in zip(conds, prefix)
                    if _expr.symbols(_expr.from_json(raw)) & set(sanitized)]
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
        s.add(*conds, *lo.axioms, z3.Contains(var, p), z3.Not(null))
        if not shims:
            s.add(z3.Contains(stmt, p))       # with a sanitizer in between, the twin decides (recompute)
        if s.check() != z3.sat:
            continue
        witness = _witness(s.model(), lo, inputs)
        values = recompute(lo, run, {**every, **witness}, list(shims))
        at = Assignment(lo, run, values)
        if any(at.eval(c) is not True for c, _ in on_sanitized):
            continue                          # with the sanitizer's real value the sink is not reached this way
        instance = at.eval(stmt)
        if isinstance(instance, str) and not parses(family, instance):
            hit = {"payload": payload, "instance": instance, "witness": witness}
            if on_sanitized:
                hit["assumes"] = [f"{str(ev.get('file') or '').rsplit('/', 1)[-1]}:{ev.get('lineno')}: a branch on "
                                  + ", ".join(f"{sanitized[n].fn}(...) = {n}"
                                              for n in sorted(_expr.symbols(_expr.from_json(ev['expr'])) & set(sanitized)))
                                  for _, ev in on_sanitized]
            return hit
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


# -- P7: the reflected-XSS oracle on output TERMS (E6) ---------------------------------
#
# An `output` event carries the echoed value's term and this run's text. For each input
# the term reads (directly or through a sanitizer shim), Z3 is asked -- exactly as for a
# sink -- for a value that satisfies every earlier path condition and contains a marker
# that would be page structure if it survived (`"'><acexss...>`). Each sanitizer result
# is recomputed by its twin, the term is evaluated under the candidate, and the site is a
# candidate only if `<acexss` appears in the evaluated output. Nothing here is the
# verdict: the judge replays the witness and counts it only if the marker parses as an
# element or attribute (decision (f), unchanged).

def xss_findings(dump: dict, timeout_ms: int = 5000) -> list[dict]:
    run = Run.from_dict(dump)
    inputs, every = run_values(dump)
    shims = {sh.result: sh for sh in sanitizers(dump)}
    before: list[Sanitizer] = []
    out, prefix, seen = [], [], set()
    for event in dump["events"]:
        if event["type"] == "symbolic_call" and event.get("result_name") in shims:
            before.append(shims[event["result_name"]])
            continue
        if event["type"] == "path_condition":
            prefix.append((event["expr"], bool(event["taken"]), event))
            continue
        if event["type"] != "output" or "term" not in event:
            continue
        term = term_of(event["term"])
        if term is None:
            continue
        site = f"{event.get('file')}:{event.get('lineno')}"
        ctx = z3.Context()
        lo = Lowering(run.symbols(), ctx)
        try:
            text_t = lo.term(term)
        except (Unlowerable, z3.Z3Exception):
            continue
        if not z3.is_string(text_t):
            continue
        for name in carried_inputs(term, inputs, before):
            if (site, name) in seen:
                continue
            seen.add((site, name))
            payload = sinks.xss_payload(site)
            hit = _xss_witness(run, lo, text_t, prefix, name, inputs, every, payload, timeout_ms, list(before))
            if hit is not None:
                out.append({"sink": "echo", "family": "xss", "file": event.get("file"), "lineno": event.get("lineno"),
                            "statement": render(term), "kind": "xss-candidate", "carried": name, "payload": payload,
                            "offset": event.get("offset"), **hit})
    return out


def _xss_witness(run, lo, text_t, prefix, name, inputs, every, payload, timeout_ms, shims):
    conds = _lowered_prefix(lo, prefix)
    if conds is None:
        return None
    try:
        var = lo.var(name)
        null = lo.is_null(Sym(name))
    except Unlowerable:
        return None
    if not z3.is_string(var):
        return None
    sanitized = {sh.result for sh in shims}
    on_sanitized = [(c, ev) for c, (raw, _, ev) in zip(conds, prefix)
                    if _expr.symbols(_expr.from_json(raw)) & sanitized]
    s = z3.Solver(ctx=lo.ctx)
    s.set("timeout", timeout_ms)
    s.add(*conds, *lo.axioms, z3.Contains(var, z3.StringVal(payload, lo.ctx)), z3.Not(null))
    if s.check() != z3.sat:
        return None
    witness = _witness(s.model(), lo, inputs)
    at = Assignment(lo, run, recompute(lo, run, {**every, **witness}, shims))
    if any(at.eval(c) is not True for c, _ in on_sanitized):
        return None
    instance = at.eval(text_t)
    marker = "<" + sinks.XSS_MARKER
    if not isinstance(instance, str) or marker not in instance:
        return None                               # a sanitizer (or the term) encodes it: not a candidate
    hit = {"instance": instance, "witness": witness}
    if on_sanitized:
        hit["assumes"] = [f"{str(ev.get('file') or '').rsplit('/', 1)[-1]}:{ev.get('lineno')}" for _, ev in on_sanitized]
    return hit
