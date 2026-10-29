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

import html.entities
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
PAYLOADS = ("'", '"', "1 1", "\\",
            # Unbalanced: an input that appears TWICE inside quotes balances a lone
            # quote (`like '%'%'|| x like '%'%'` still parses); these do not.
            "'(", '"(')

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


# -- E5: the sanitizer chains a note's ref can carry ({name, apply}) -----------------
#
# Python twins of the PHP functions, checked against PHP on random strings by
# test_sanitizers.py. Only the behaviour that matters for a byte string the
# oracle builds (ASCII payloads around arbitrary model values) is modelled.

ENT_COMPAT, ENT_QUOTES_DOUBLE, ENT_QUOTES_SINGLE = 2, 2, 1          # bits of PHP's ENT_* flags
ENT_HTML401, ENT_SUBSTITUTE = 0, 8
PHP_DEFAULT_HTML_FLAGS = 3 | 8                                     # ENT_QUOTES | ENT_SUBSTITUTE | ENT_HTML401 (PHP >= 8.1)


def _htmlspecialchars(s: str, flags: int = PHP_DEFAULT_HTML_FLAGS, encoding=None, double_encode: bool = True) -> str:
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "&":
            if not double_encode:
                m = re.match(r"&(#[0-9]+|#x[0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]*);", s[i:])
                if m and (m.group(1).startswith("#") or m.group(1) in html.entities.entitydefs):
                    out.append(m.group(0))
                    i += len(m.group(0))
                    continue
            out.append("&amp;")
        elif c == "<":
            out.append("&lt;")
        elif c == ">":
            out.append("&gt;")
        elif c == '"' and flags & 2:
            out.append("&quot;")
        elif c == "'" and flags & 1:
            out.append("&#039;")
        else:
            out.append(c)
        i += 1
    return "".join(out)


def _escapeshellarg(s: str) -> str:
    return "'" + s.replace("'", "'\\''") + "'"


def _escapeshellcmd(s: str) -> str:
    """PHP's ext/standard/exec.c: a quote is left alone when a later one of the same kind
    exists (and that later one, the pending close, is left alone too); otherwise escaped."""
    out, pending = [], None
    for x, c in enumerate(s):
        if c in "#&;`|*?~<>^()[]{}$\\\x0A\xFF":
            out.append("\\" + c)
        elif c in "'\"":
            if pending is None and s.find(c, x + 1) != -1:
                pending = c
            elif pending is not None and pending == c:
                pending = None
            else:
                out.append("\\")
            out.append(c)
        else:
            out.append(c)
    return "".join(out)


SANITIZERS = {
    "addslashes": lambda s, *a: re.sub(r"([\\'\"])", r"\\\1", s).replace("\0", "\\0"),
    "mysqli_real_escape_string": lambda s, *a: s.translate({0: "\\0", 10: "\\n", 13: "\\r", 92: "\\\\",
                                                            39: "\\'", 34: '\\"', 26: "\\Z"}),
    "htmlspecialchars": _htmlspecialchars,
    # htmlentities differs only for non-ASCII; the oracle's payloads are ASCII.
    "htmlentities": _htmlspecialchars,
    "escapeshellarg": lambda s, *a: _escapeshellarg(s),
    "escapeshellcmd": lambda s, *a: _escapeshellcmd(s),
    "trim": lambda s, chars=" \t\n\r\0\x0B", *a: s.strip(chars),
    "strtolower": lambda s, *a: s.translate({c: c + 32 for c in range(65, 91)}),
    "strtoupper": lambda s, *a: s.translate({c: c - 32 for c in range(97, 123)}),
}


def apply_chain(value: str, chain: list) -> str:
    for fn, args in chain:
        value = SANITIZERS[fn](value, *args)
    return value


def _ref_name(ref) -> str:
    return ref["name"] if isinstance(ref, dict) else ref


def _instantiate(text: str, refs: dict, values: dict[str, t.Any]) -> str:
    def sub(m):
        ref = refs.get(m.group(1), m.group(1))
        v = values.get(_ref_name(ref))
        if v is None:
            return ""
        v = str(v)
        return apply_chain(v, ref.get("apply", [])) if isinstance(ref, dict) else v
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
        # `concrete_call`: app mode's real mysqli_query (E1) -- same note, plus the DB's verdict.
        if event["type"] not in ("symbolic_call", "concrete_call") or event["target"] not in families:
            continue
        family = families[event["target"]]
        text, refs = _note(event)
        site = {"sink": event["target"], "family": family, "file": event.get("file"),
                "lineno": event.get("lineno"), "statement": text}
        if event["type"] == "concrete_call" and isinstance(event.get("summary"), dict):
            site["db_errno"] = event["summary"].get("errno")
        concrete = _instantiate(text, refs, values)
        if not parses(family, concrete):
            out.append(site | {"kind": "malformed-at-reach", "instance": concrete, "witness": values})
            continue
        for name in dict.fromkeys(_ref_name(r) for r in refs.values()):
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


# -- M4: the reflected-XSS oracle (E6 output events) ------------------------------
#
# An `output` event says a symbolic value was printed, with its sealed note
# (refs, and any sanitizer chain applied to it). For each input the note
# carries, ask Z3 -- exactly as `_inject` does -- for a value that satisfies
# every path condition before the echo and contains a MARKER that would be
# page structure if it survived: `"'><acexss...>`. Apply the ref's sanitizer
# chain; if the marker's `<` survives, the site is an XSS candidate. Nothing
# here is the verdict: the judge replays the witness and counts it only if the
# marker parses as an element or attribute (decision (f), structural only).

XSS_MARKER = "acexss"


def xss_payload(site: str) -> str:
    import hashlib
    return f"\"'><{XSS_MARKER}{hashlib.sha1(site.encode()).hexdigest()[:8]}>"


def xss_findings(dump: dict, timeout_ms: int = 5000) -> list[dict]:
    run = Run.from_dict(dump)
    values = {v["name"]: v.get("value") for v in dump["symbolic_vars"]
              if v.get("origin", {}).get("kind") == "input"}
    out, prefix, seen = [], [], set()
    for event in dump["events"]:
        if event["type"] == "path_condition":
            prefix.append((json.dumps(event["expr"], sort_keys=True, separators=(",", ":")), event["taken"]))
            continue
        if event["type"] != "output":
            continue
        text, refs = _note(event)
        site = f"{event.get('file')}:{event.get('lineno')}"
        for ref in refs.values():
            name = _ref_name(ref)
            if (site, name) in seen:
                continue
            seen.add((site, name))
            chain = ref.get("apply", []) if isinstance(ref, dict) else []
            payload = xss_payload(site)
            if "<" not in apply_chain(payload, chain):
                continue                          # the sanitizer encodes it: not a candidate
            hit = _witness_containing(run, prefix, name, values, payload, timeout_ms)
            if hit is not None:
                out.append({"sink": "echo", "family": "xss", "file": event.get("file"), "lineno": event.get("lineno"),
                            "statement": text, "kind": "xss-candidate", "carried": name, "payload": payload,
                            "instance": _instantiate(text, refs, hit), "witness": hit, "offset": event.get("offset")})
    return out


def _witness_containing(run, prefix, name, values, payload, timeout_ms):
    ctx = z3.Context()
    lo = Lowering(run.symbols(), ctx)
    try:
        conds = [lo.cond(e if taken else ("not", e)) for e, taken in prefix]
        var = lo.var(name)
    except Exception:  # noqa: BLE001
        return None
    if not z3.is_string(var):
        return None
    s = z3.Solver(ctx=ctx)
    s.set("timeout", timeout_ms)
    s.add(*conds, *lo.axioms, z3.Contains(var, z3.StringVal(payload, ctx)), z3.Not(lo.is_null(Sym(name))))
    if s.check() != z3.sat:
        return None
    m = s.model()
    witness = dict(values)
    for d in m.decls():
        if d.arity() == 0 and d.name() in witness:
            witness[d.name()] = m[d].as_string() if z3.is_string_value(m[d]) else witness[d.name()]
        elif d.arity() == 0 and d.name().startswith("is_null(") and z3.is_true(m[d]):
            witness[d.name()[len("is_null("):-1]] = None
    witness[name] = m.eval(var, model_completion=True).as_string()
    return witness
