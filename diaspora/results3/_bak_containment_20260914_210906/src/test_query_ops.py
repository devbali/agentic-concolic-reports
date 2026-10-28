"""Tests for the query-ops runtime additions (mirrors the Ruby test section):

- SymbolicBool (plain wrapper; ==/!=/bool tracked)
- note attribute on factories, registered vars in RunDump
- SymbolicList as length-only wrapper
- interceptor receiver-passing (3-arity mocks) and symbolic pass-through
- engine roundtrip with note fields present
"""

import re
import json

import pytest

from py_runtime import (
    CallInterceptor,
    SymbolicBool,
    SymbolicInt,
    SymbolicList,
    SymbolicVar,
    symbool,
    symlist,
)
from py_runtime.symbolic_func import (
    reset_symbolic_state,
    save_and_clear_registered_vars,
)


def setup_function(_fn):
    SymbolicVar.clear_path_conditions()
    reset_symbolic_state()


# ── SymbolicBool ───────────────────────────────────────────────────────


def test_symbool_eq_records_pc():
    b = SymbolicBool(False, name="flag")
    assert (b == True) is False  # noqa: E712
    pcs = SymbolicVar.get_path_conditions()
    assert len(pcs) == 1
    assert pcs[0].expr == "(flag == True)"
    assert pcs[0].taken is False


def test_symbool_ne_records_pc():
    b = SymbolicBool(True, name="flag")
    assert (b != False) is True  # noqa: E712
    pcs = SymbolicVar.get_path_conditions()
    assert len(pcs) == 1
    assert pcs[0].taken is True


def test_symbool_truthiness_records_pc():
    """Python truthiness IS hookable (unlike Ruby — see src/TODO.txt)."""
    b = SymbolicBool(False, name="flag")
    if b:
        taken = True
    else:
        taken = False
    assert taken is False
    pcs = SymbolicVar.get_path_conditions()
    assert len(pcs) == 1
    assert pcs[0].expr == "(flag == True)"
    assert pcs[0].taken is False


def test_symbool_factory_registers_var_with_note():
    b = symbool("nf", False, note="SELECT 1")
    assert isinstance(b, SymbolicBool)
    assert b.note == "SELECT 1"
    vars_ = save_and_clear_registered_vars()
    assert len(vars_) == 1
    assert vars_[0] == {
        "name": "nf", "sort": "Bool", "value": False, "note": "SELECT 1",
    }


# ── SymbolicList (length-only) ─────────────────────────────────────────


def test_symlist_bool_records_length_pc():
    l = SymbolicList(0, name="rows")
    assert not l
    pcs = SymbolicVar.get_path_conditions()
    assert len(pcs) == 1
    assert pcs[0].expr == "(SYM_LEN_rows != 0)"
    assert pcs[0].taken is False


def test_symlist_length_is_symbolic_and_compares():
    l = SymbolicList(3, name="rows")
    assert isinstance(l.length, SymbolicInt)
    assert l.length > 1
    pcs = SymbolicVar.get_path_conditions()
    assert len(pcs) == 1
    assert "SYM_LEN_rows > 1" in pcs[0].expr


def test_symlist_element_access_raises():
    l = SymbolicList(2, name="rows")
    with pytest.raises(NotImplementedError):
        l[0]
    with pytest.raises(NotImplementedError):
        list(iter(l))
    with pytest.raises(NotImplementedError):
        l.append(1)


def test_symlist_note_registers_length_var():
    SymbolicList(2, name="rows", note="SELECT * FROM posts")
    vars_ = save_and_clear_registered_vars()
    assert len(vars_) == 1
    assert vars_[0]["name"] == "SYM_LEN_rows"
    # The reason for the spelling (2026-09-14): solver.py transports Z3
    # terms as PYTHON SOURCE it exec/evals, so a minted name must be a legal
    # Python identifier. Assert the PROPERTY, not just the literal.
    assert re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", vars_[0]["name"])
    assert vars_[0]["note"] == "SELECT * FROM posts"


def test_symlist_iterable_seed_backcompat():
    l = SymbolicList([1, 2, 3], name="rows")
    assert l.concrete_length == 3


# ── Interceptor: receiver-passing + note vars in dump ─────────────────


class FakeRelation:
    def to_sql(self):
        return "SELECT * FROM posts WHERE id = 1"

    def find(self, _id):
        raise RuntimeError("real body must not run")


def _install_find_mock(ci):
    def find_mock(receiver, args, name):
        sql = receiver.to_sql()
        nf = symbool(f"{name}_not_found", False, note=sql)
        if nf == True:  # noqa: E712 — explicit compare (mirrors Ruby)
            raise LookupError(f"concolic: empty result for: {sql}")
        return symlist("rows", 2, note=sql)

    FakeRelation.find = ci._make_wrapper(FakeRelation.find, returns=find_mock)


def test_receiver_passing_and_dump_notes():
    ci = CallInterceptor.get_instance()
    _install_find_mock(ci)

    def src(x):
        rows = FakeRelation().find(1)
        if rows.length > 1:
            pass
        if x > 5:
            pass

    dump = ci.run(src, {"x": 7}, label="recv-test")
    assert dump.get("error") is None

    by_name = {v["name"]: v for v in dump["symbolic_vars"]}
    nf_name = next(n for n in by_name if "not_found" in n)
    assert by_name[nf_name]["sort"] == "Bool"
    assert by_name[nf_name]["note"] == "SELECT * FROM posts WHERE id = 1"
    assert by_name["SYM_LEN_rows"]["value"] == 2

    exprs = [e["expr"] for e in dump["events"] if e["type"] == "path_condition"]
    assert any("not_found" in e for e in exprs)
    assert any("SYM_LEN_rows" in e for e in exprs)

    # JSON-serializable end to end
    json.dumps(dump)


def test_engine_roundtrip_with_notes():
    from concolic_engine.run import Run

    ci = CallInterceptor.get_instance()

    def src(x):
        nf = symbool("q_not_found", False, note="SELECT 1 FROM t")
        if nf == True:  # noqa: E712
            pass
        if x > 5:
            pass

    dump = ci.run(src, {"x": 7}, label="roundtrip")
    r = Run.from_dict(json.loads(json.dumps(dump)))
    assert len(r.path_conditions) == 2
    names = [sv.name for sv in r.symbolic_vars]
    assert "q_not_found" in names
    assert r.concrete_values["q_not_found"] is False


# ── Symbolic model instance ────────────────────────────────────────────


class Post:
    """Stand-in for a real app model with behavior methods."""

    def __init__(self):
        raise RuntimeError("__init__ must never run for symbolic instances")

    def visible_to(self, user_id):
        # Real app logic branching on attributes
        if self.public == True:  # noqa: E712
            return True
        return self.author_id == user_id

    def display_name(self):
        return f"post-{self.guid}"


def _post_attrs(sql="SELECT * FROM posts"):
    from py_runtime import symbool, symint, symstr
    return {
        "id": symint("post_id", 1, note=sql),
        "author_id": symint("post_author_id", 7, note=sql),
        "public": symbool("post_public", False, note=sql),
        "guid": symstr("post_guid", "g-1", note=sql),
    }


def test_symbolic_instance_isinstance_and_init_skipped():
    from py_runtime import make_symbolic_instance
    post = make_symbolic_instance(Post, _post_attrs())
    assert isinstance(post, Post)  # real class — behavior methods available


def test_symbolic_instance_attr_reads_are_symbolic():
    from py_runtime import SymbolicBool, SymbolicInt, make_symbolic_instance
    post = make_symbolic_instance(Post, _post_attrs())
    assert isinstance(post.public, SymbolicBool)
    assert isinstance(post.author_id, SymbolicInt)


def test_symbolic_instance_real_method_records_pcs():
    from py_runtime import SymbolicVar, make_symbolic_instance
    post = make_symbolic_instance(Post, _post_attrs())
    result = post.visible_to(7)
    assert result is True  # public=False, author_id=7 == 7
    pcs = SymbolicVar.get_path_conditions()
    exprs = [pc.expr for pc in pcs]
    assert "(post_public == True)" in exprs      # first branch, not taken
    assert any("post_author_id" in e for e in exprs)  # second branch, taken
    taken = {pc.expr: pc.taken for pc in pcs}
    assert taken["(post_public == True)"] is False


def test_symbolic_instance_strict_rejects_concrete_attrs():
    from py_runtime import make_symbolic_instance
    with pytest.raises(TypeError):
        make_symbolic_instance(Post, {"id": 1})
    # non-strict allows it
    post = make_symbolic_instance(Post, {"id": 1}, strict=False)
    assert post.id == 1


def test_symbolic_instance_concolic_attrs_accessor():
    from py_runtime import concolic_attrs, make_symbolic_instance
    attrs = _post_attrs()
    post = make_symbolic_instance(Post, attrs)
    assert set(concolic_attrs(post)) == set(attrs)
    assert concolic_attrs(object()) == {}


def test_symbolic_instance_note_flows_to_registered_vars():
    from py_runtime import make_symbolic_instance
    make_symbolic_instance(Post, _post_attrs(sql="SELECT 42"))
    vars_ = save_and_clear_registered_vars()
    assert len(vars_) == 4
    assert all(v["note"] == "SELECT 42" for v in vars_)


# ── Symbolic string length ─────────────────────────────────────────────


def test_symstr_length_is_symbolic_and_records_on_compare():
    from py_runtime import SymbolicInt, symstr
    s = symstr("guid", "abcdef")
    save_and_clear_registered_vars()
    ln = s.length
    assert isinstance(ln, SymbolicInt)
    assert ln > 3
    pcs = SymbolicVar.get_path_conditions()
    assert len(pcs) == 1
    assert pcs[0].expr == "(Length(guid) > 3)"
    assert pcs[0].taken is True


def test_symsubstring_length_is_concrete():
    from py_runtime import symstr
    s = symstr("header", "Bearer token")
    sub = s[7:]  # SymbolicSubstring
    SymbolicVar.clear_path_conditions()
    assert sub.length == 5  # concrete int — no PC from the length read itself


# ── Parity-audit fixes (B1–B6) ─────────────────────────────────────────


def test_unnamed_symbolic_rhs_renders_concrete_value():
    from py_runtime import SymbolicInt, SymbolicVar
    SymbolicVar.clear_path_conditions()
    x = SymbolicInt(5, name="x")
    y = SymbolicInt(3)  # unnamed
    x > y
    pc = SymbolicVar.get_path_conditions()[-1]
    assert pc.expr == "(x > 3)"  # not "(x > None)"


def test_string_compare_with_non_string_raises():
    from py_runtime import symstr
    s = symstr("s", "ab")
    with pytest.raises(NotImplementedError):
        s == 5
    with pytest.raises(NotImplementedError):
        s != [1]


def test_symdict_registers_len_var():
    from py_runtime import symdict
    save_and_clear_registered_vars()
    symdict("opts", {"a": 1})
    vars_ = save_and_clear_registered_vars()
    assert any(v["name"] == "SYM_LEN_opts" and v["sort"] == "Int" and v["value"] == 1
               for v in vars_)


def test_to_symbolic_none_passthrough_and_bool_wraps_symbolicbool():
    from py_runtime import SymbolicBool
    from py_runtime.symbolic_func import _to_symbolic
    assert _to_symbolic(None, name="r") is None
    wrapped = _to_symbolic(True, name="r")
    assert isinstance(wrapped, SymbolicBool)
    assert wrapped.value is True


def test_run_bool_kwarg_becomes_symbolicbool():
    from py_runtime import SymbolicBool
    from py_runtime.call_interceptor import CallInterceptor

    seen = {}

    def source(flag):
        seen["type"] = type(flag).__name__
        seen["is_symbool"] = isinstance(flag, SymbolicBool)

    CallInterceptor.get_instance().run(source, {"flag": True}, label="boolkw")
    assert seen["is_symbool"], f"expected SymbolicBool, got {seen['type']}"


def test_call_events_carry_per_target_name():
    from py_runtime.call_interceptor import CallInterceptor
    interceptor = CallInterceptor.get_instance()

    @interceptor.target(lambda a, n: 1)
    def alpha_target(x):
        pass

    @interceptor.target(lambda a, n: 2)
    def beta_target(x):
        pass

    def source(x):
        alpha_target(x)
        beta_target(x)

    dump = interceptor.run(source, {"x": 1}, label="multi-target")
    call_targets = [e["target"] for e in dump["events"] if e["type"] == "call"]
    assert "alpha_target" in call_targets, call_targets
    assert "beta_target" in call_targets, call_targets


# ── str(s) identity (keeps tracking); lossy channels stay closed ──────


def test_str_of_symbolic_string_is_identity():
    from py_runtime import SymbolicString, symstr
    s = symstr("guid", "g-1")
    t = str(s)
    assert t is s  # tracking survives the defensive cast
    SymbolicVar.clear_path_conditions()
    t == "admin"
    assert SymbolicVar.get_path_conditions()[0].expr == "(guid == StringVal('admin'))"


def test_string_lossy_channels_still_raise():
    from py_runtime import symstr
    s = symstr("guid", "g-1")
    with pytest.raises(NotImplementedError):
        f"{s}"          # __format__
    with pytest.raises(NotImplementedError):
        "a" + s         # __radd__ (plain lhs)
    with pytest.raises(NotImplementedError):
        s + "a"         # __add__
    with pytest.raises(NotImplementedError):
        "%s" % s        # __rmod__ (plain lhs)
