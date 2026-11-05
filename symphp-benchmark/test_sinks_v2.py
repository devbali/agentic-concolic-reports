"""sinks_v2 (the v2 engine's sink oracle) on hand-written dumps in the runtime's wire shape.

usage: build/venv/bin/python -m pytest -q test_sinks_v2.py      (needs the v2 engine checked out)
"""

from __future__ import annotations

import json

import pytest

import engine

pytestmark = pytest.mark.skipif(not engine.V2, reason="needs the v2 engine (php-runtime/real-apps-v2)")

if engine.V2:
    import sinks_v2

FAM = {"mysqli_query": "sql", "system": "shell"}


def lit(v):
    return {"lit": {"sort": "str", "value": v}}


def sym(n):
    return {"sym": n}


def cat(*parts):
    out = parts[0]
    for p in parts[1:]:
        out = {"op": "concat", "args": [out, p]}
    return out


def inp(name, value):
    return {"name": name, "type": "str?", "sort": "String", "value": value,
            "origin": {"kind": "input", "name": name}}


def sink(stmt, text=None, target="mysqli_query", kind="symbolic_call", key="sql", line=6):
    note = {"statement_arg": key}
    if text is not None:
        note["text"] = text
    e = {"type": kind, "target": target, "args": {key: stmt}, "note": json.dumps(note),
         "file": "/app/x.php", "lineno": line, "function": None}
    if kind == "symbolic_call":
        e |= {"result_name": f"SYM_RESULT_{target}_1", "result_type": "bool", "result_sort": "Bool",
              "result_value": {"lit": {"sort": "bool", "value": True}}}
    else:
        e["summary"] = {"text": text, "errno": 0}
    return e


def pc(expr, taken, line=3):
    return {"type": "path_condition", "expr": expr, "taken": taken, "file": "/app/x.php", "lineno": line,
            "function": None}


def dump(vars_, events):
    return {"label": "t", "symbolic_vars": vars_, "events": events,
            "declarations": {"mysqli_query": {"kind": "target_function"}, "system": {"kind": "target_function"}}}


def isnull(n):
    return {"op": "==", "args": [sym(n), {"lit": {"sort": "null"}}]}


QUOTED = cat(lit("select * from user where username='"), sym("GET_id"), lit("'"))


def test_injectable_through_a_concat_term():
    d = dump([inp("GET_id", "a")], [pc(isnull("GET_id"), False), sink(QUOTED, "select * from user where username='a'")])
    [f] = sinks_v2.findings(d, FAM)
    assert f["kind"] == "injectable" and f["carried"] == "GET_id" and f["payload"] == "'"
    assert "'" in f["witness"]["GET_id"]
    assert f["instance"] == "select * from user where username='" + f["witness"]["GET_id"] + "'"
    assert f["statement"] == "select * from user where username='$$(GET_id)'"


def test_the_concrete_call_of_an_app_mode_sink_is_read_the_same_way():
    d = dump([inp("GET_id", "a")], [sink(QUOTED, "select * from user where username='a'", kind="concrete_call")])
    [f] = sinks_v2.findings(d, FAM)
    assert f["kind"] == "injectable" and f["db_errno"] == 0


def test_malformed_at_reach_from_this_runs_text():
    d = dump([], [sink(lit("select * from user where id=0'"), "select * from user where id=0'")])
    [f] = sinks_v2.findings(d, FAM)
    assert f["kind"] == "malformed-at-reach" and f["instance"] == "select * from user where id=0'"


def test_without_a_text_the_term_is_evaluated_at_this_runs_values():
    d = dump([inp("GET_id", "x'")], [sink(QUOTED)])
    [f] = sinks_v2.findings(d, FAM)
    assert f["kind"] == "malformed-at-reach" and f["instance"] == "select * from user where username='x''"


def test_a_guard_that_admits_only_a_harmless_value_gives_no_finding():
    # guarded.php: the sink is reached only when id === 'trickE'.
    eq = {"op": "==", "args": [sym("GET_id"), lit("trickE")]}
    d = dump([inp("GET_id", "trickE")], [pc(isnull("GET_id"), False), pc(eq, True),
                                         sink(QUOTED, "select * from user where username='trickE'")])
    assert sinks_v2.findings(d, FAM) == []


def test_the_payload_must_survive_into_the_statement():
    # The statement keeps only the first character of the input: a payload that
    # is cut off is not proposed, and "'" alone (which fits) breaks the quote.
    first = {"op": "substring", "args": [sym("GET_id"), {"lit": {"sort": "int", "value": 0}},
                                         {"lit": {"sort": "int", "value": 1}}]}
    stmt = cat(lit("select * from user where username='"), first, lit("'"))
    d = dump([inp("GET_id", "ab")], [sink(stmt, "select * from user where username='a'")])
    [f] = sinks_v2.findings(d, FAM)
    assert f["kind"] == "injectable" and f["instance"] == "select * from user where username='''"


def test_a_numeric_context_is_broken_by_a_bare_space():
    stmt = cat(lit("select * from user where id="), sym("GET_id"))
    d = dump([inp("GET_id", "1")], [sink(stmt, "select * from user where id=1")])
    [f] = sinks_v2.findings(d, FAM)
    assert f["kind"] == "injectable" and not sinks_v2.parses("sql", f["instance"])


def test_a_shell_sink():
    stmt = cat(lit("ls "), sym("POST_f"))
    d = dump([inp("POST_f", "x")], [sink(stmt, "ls x", target="system", key="cmd")])
    [f] = sinks_v2.findings(d, FAM)
    assert f["family"] == "shell" and f["kind"] == "injectable"


def test_the_dump_round_trips_through_the_engine():
    from dump_ir.run import Run
    d = dump([inp("GET_id", "a")], [pc(isnull("GET_id"), False), sink(QUOTED, "x", kind="concrete_call")])
    run = Run.from_dict(d)
    assert [type(e).__name__ for e in run.events] == ["PathCondition", "ConcreteCallEvent"]
