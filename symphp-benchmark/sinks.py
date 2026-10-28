"""The sink oracle: does a REACHABLE input break a sink's statement?

The same criterion SymPHP inherits from Witcher's fault escalation -- a SQL or
shell statement that fails to PARSE -- asked of ACE's dumps instead of a
segfaulting interpreter. For each sink call a dump records (a `symbolic_call`
to a SQL or shell target, whose note is the statement with every symbolic part
left as `$$(ref)`):

1. **malformed-at-reach.** Instantiate the note with THIS run's values. If it
   does not parse, the path that reached the sink is itself the witness --
   Witcher-Test's sinks are all of this kind (`select ... id=0'`).
2. **injectable.** Otherwise, for each input the note carries, ask Z3 for a
   value that satisfies every path condition recorded BEFORE the sink (so the
   sink is still reached) and contains a syntax-breaking payload. Instantiate,
   parse, and keep the first that breaks. The path conditions are lowered by
   the engine's own `concolic.solver.Lowering`, so a payload the
   application's checks forbid is never proposed.

Every finding carries a concrete request. Nothing here is the verdict on the
benchmark: `judge.py` replays each one against the real application and a real
MySQL, and only a replayed fault counts.
"""

from __future__ import annotations

import json
import re
import subprocess
import typing as t

import sqlglot
import z3
from sqlglot.errors import ParseError, TokenError

from concolic.model.term import Sym
from concolic.model.run import Run
from concolic.solver import Lowering

SQL = "sql"
SHELL = "shell"

#: Payloads tried per carried input, in order. Each breaks a different
#: lexical context: single-quoted, double-quoted, bare numeric, backslash.
PAYLOADS = ("'", '"', "1 1", "\\")

REF = re.compile(r"\$\$\(([^)]+)\)")


def parses(family: str, text: str) -> bool:
    if family == SQL:
        try:
            sqlglot.parse(text, read="mysql")
            return True
        except (ParseError, TokenError):
            return False
    # The shell the benchmark's sinks reach: /bin/sh, which is dash on the
    # Ubuntu images both tools run on.
    return subprocess.run(["sh", "-n", "-c", text], capture_output=True).returncode == 0


def _note(event: dict) -> tuple[str, dict[str, str]]:
    note = event.get("note")
    if note is None:
        return "", {}
    try:
        sealed = json.loads(note)
        if isinstance(sealed, dict) and "text" in sealed:
            return sealed["text"], dict(sealed.get("refs") or {})
    except json.JSONDecodeError:
        pass
    return note, {}


def _instantiate(text: str, refs: dict[str, str], values: dict[str, t.Any]) -> str:
    def sub(m):
        v = values.get(refs.get(m.group(1), m.group(1)))
        return "" if v is None else str(v)
    return REF.sub(sub, text)


def findings(dump: dict, families: dict[str, str], timeout_ms: int = 5000) -> list[dict]:
    """Every sink finding in one dump. `families` maps target name -> SQL/SHELL."""
    run = Run.from_dict(dump)
    values = {v["name"]: v.get("value") for v in dump["symbolic_vars"]
              if v.get("origin", {}).get("kind") == "input"}
    out = []
    prefix: list[tuple[str, bool]] = []
    for event in dump["events"]:
        if event["type"] == "path_condition":
            prefix.append((json.dumps(event["expr"], sort_keys=True, separators=(",", ":")), event["taken"]))
            continue
        if event["type"] != "symbolic_call" or event["target"] not in families:
            continue
        family = families[event["target"]]
        text, refs = _note(event)
        site = {"sink": event["target"], "family": family, "file": event.get("file"),
                "lineno": event.get("lineno"), "statement": text}
        concrete = _instantiate(text, refs, values)
        if not parses(family, concrete):
            out.append(site | {"kind": "malformed-at-reach", "instance": concrete, "witness": values})
            continue
        for name in dict.fromkeys(refs.values()):
            hit = _inject(run, prefix, name, text, refs, values, family, timeout_ms)
            if hit is not None:
                out.append(site | {"kind": "injectable", "carried": name} | hit)
                break
    return out


def _inject(run, prefix, name, text, refs, values, family, timeout_ms):
    """A payload-bearing value for `name` that still reaches the sink, or None."""
    ctx = z3.Context()
    lo = Lowering(run.symbols(), ctx)
    try:
        conds = [lo.cond(e if taken else ("not", e)) for e, taken in prefix]
        var = lo.var(name)
    except Exception:  # noqa: BLE001 -- an unlowerable prefix proposes nothing
        return None
    if not z3.is_string(var):
        return None
    for payload in PAYLOADS:
        s = z3.Solver(ctx=ctx)
        s.set("timeout", timeout_ms)
        s.add(*conds, *lo.axioms, z3.Contains(var, z3.StringVal(payload, ctx)))
        s.add(z3.Not(lo.is_null(Sym(name))))
        if s.check() != z3.sat:
            continue
        m = s.model()
        witness = dict(values)
        for d in m.decls():
            if d.arity() == 0 and d.name() in witness:
                witness[d.name()] = m[d].as_string() if z3.is_string_value(m[d]) else witness[d.name()]
            elif d.arity() == 0 and d.name().startswith("is_null(") and z3.is_true(m[d]):
                witness[d.name()[len("is_null("):-1]] = None
        witness[name] = m.eval(var, model_completion=True).as_string()
        instance = _instantiate(text, refs, witness)
        if not parses(family, instance):
            return {"payload": payload, "instance": instance, "witness": witness}
    return None
