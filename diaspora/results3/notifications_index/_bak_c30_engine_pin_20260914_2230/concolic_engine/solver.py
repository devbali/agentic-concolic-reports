"""
SMT solver interface for the concolic engine.

Wraps Z3 to check satisfiability of constraint strings and extract
concrete models. Only the sorts and functions actually used by the
coverage checker are exposed.

Two entry points, both stateless (a fresh ``z3.Solver`` per call):

- ``check_satisfiability`` — "is this set of constraints SAT, and if so give
  me the variable values". Unchanged.
- ``solve_and_evaluate`` — the same, plus "and tell me the truth value of
  each of THESE expressions under that model". The extra expressions are
  evaluated with ``model_completion=True``, so an expression the model left
  unconstrained still gets a definite value and costs no solver call. It is
  what lets the coverage checker determinise a whole outcome assignment from
  ONE query instead of one query per decision (owner ruling, 2026-09-12).
  It also reports z3's ``unknown`` as its own status instead of folding it
  into "unsat" — with a single query there is no second chance to notice a
  timeout, and a timeout must never read as "covered".
"""

from __future__ import annotations

import functools
import keyword
import logging
import re
import time
import typing as t

import z3  # type: ignore[import-untyped]

logger = logging.getLogger(__name__)

# Z3 functions available in the eval() namespace for parsing constraints.
_Z3_NAMESPACE: t.Dict[str, t.Any] = {
    "BitVec": z3.BitVec,
    "Int": z3.Int,
    "Bool": z3.Bool,
    "Real": z3.Real,
    "String": z3.String,
    "StringVal": z3.StringVal,
    "And": z3.And,
    "Or": z3.Or,
    "Not": z3.Not,
    "UGT": z3.UGT,
    "UGE": z3.UGE,
    "ULT": z3.ULT,
    "ULE": z3.ULE,
    "PrefixOf": z3.PrefixOf,
    "SuffixOf": z3.SuffixOf,
    "Contains": z3.Contains,
    "IndexOf": z3.IndexOf,
    "LastIndexOf": z3.LastIndexOf,
    "SubString": z3.SubString,
    "Length": z3.Length,
}

#: The namespace entries that MINT a variable or literal and therefore need
#: to be told which Z3 context to mint it in. Everything else in
#: ``_Z3_NAMESPACE`` infers its context from its arguments.
_CTX_BOUND = ("Int", "Bool", "Real", "String", "BitVec", "StringVal")


def _namespace(ctx: t.Optional[z3.Context]) -> t.Dict[str, t.Any]:
    """The eval() namespace, optionally bound to a private Z3 context.

    ``ctx=None`` is the global context — what ``check_satisfiability`` has
    always used. A private context is what makes a query REPRODUCIBLE: Z3's
    model choice for a formula with several models depends on state carried
    in the context, so the identical query issued twice in one process can
    (and demonstrably does) come back with different models. That is
    invisible when the caller only reads `sat`/`unsat`, and decisive when the
    caller reads the MODEL — a resumed pass must return the result the
    unbroken pass would have.
    """
    if ctx is None:
        return dict(_Z3_NAMESPACE)
    ns = dict(_Z3_NAMESPACE)
    for name in _CTX_BOUND:
        ns[name] = functools.partial(_Z3_NAMESPACE[name], ctx=ctx)
    return ns


class SolverResult(t.NamedTuple):
    satisfiable: bool
    model: t.Optional[t.Dict[str, t.Any]]
    solver_elapsed_ms: float


class ModelResult(t.NamedTuple):
    """``solve_and_evaluate``'s answer.

    ``status`` is ``"sat"`` / ``"unsat"`` / ``"unknown"`` — the third is z3
    giving up (timeout, incomplete theory) and is NOT "unsat".
    ``outcomes`` maps each requested expression to its truth value under the
    model (``None`` unless ``status == "sat"``); an expression that could not
    be parsed or did not evaluate to a boolean literal is simply absent, and
    the caller decides what that means.
    """

    status: str
    model: t.Optional[t.Dict[str, t.Any]]
    outcomes: t.Optional[t.Dict[str, bool]]
    solver_elapsed_ms: float


def _concrete(z3_val: t.Any, sort_name: str) -> t.Any:
    """One Z3 value -> a plain Python value, by sort."""
    if sort_name.startswith("BitVec"):
        return z3_val.as_long()
    if "Int" in sort_name and "BitVec" not in sort_name:
        return z3_val.as_long()
    if sort_name == "Bool":
        return z3.is_true(z3_val)
    if sort_name == "Real":
        return float(z3_val.numerator_as_long()) / float(
            z3_val.denominator_as_long()
        )
    if "String" in sort_name:
        return z3_val.as_string()
    return str(z3_val)


def _build_variable_map(
    var_names: t.List[str], model: z3.ModelRef
) -> t.Dict[str, t.Any]:
    """Extract concrete values from a Z3 model for the given var names."""
    result: t.Dict[str, t.Any] = {}
    decls = model.decls()
    name_to_decl = {d.name(): d for d in decls}
    for name in var_names:
        decl = name_to_decl.get(name)
        if decl is None:
            continue
        result[name] = _concrete(model[decl], str(decl.range()))
    return result


# ══════════════════════════════════════════════════════════════════════════
# THE PYTHON-TEXT NAME BOUNDARY  (containment, 2026-09-14 — see §11 of
# reports/diaspora/docs/NAME_BOUNDARY_PLAN_20260914.md)
# ══════════════════════════════════════════════════════════════════════════
#
# This module transports Z3 terms as PYTHON SOURCE: a declaration is
# ``exec``'d and a constraint is ``eval``'d. That imposes a requirement no
# other part of the system has — a variable's name must be a legal Python
# identifier, and must not shadow a name the eval namespace needs:
#
#     exec  "len(X) = Int('len(X)')"  -> SyntaxError: cannot assign to
#                                        function call here
#     eval  "len(X) > 3"              -> NameError: name 'len' is not defined
#     exec  "Int = Int('Int')"        -> shadows the constructor; EVERY later
#                                        declaration then fails
#
# Z3 itself has no such requirement (``Int('len(X)')`` solves fine), nor does
# JSON, nor do the runtimes, the dumps, the seeds or the path signatures.
# ``len(X)`` is the name the runtime means and the name ~1,007,044 dumps on
# disk carry, so it stays the ONE TRUE NAME everywhere and the constraint is
# CONTAINED HERE: names are sanitised on the way INTO the Python text and the
# model's keys are mapped back on the way OUT, so every caller only ever sees
# the real name. One site instead of the sixty hand-rolled rewrite copies
# (15 divergent behaviours, seven multi-hour incidents, one false PASS) that
# the leak produced.
#
# WHAT MAY BE SANITISED, AND WHAT MUST NOT BE
# -------------------------------------------
# The hard part is not the encoding, it is telling a NAME from a SOLVER TERM,
# and that CANNOT be decided by shape. Measured over 150 dumps across all six
# endpoints, the non-identifier ``symbolic_vars[].name`` strings are three
# different things:
#
#   ``len(X)``     1,599   a genuine VARIABLE. z3 has no ``len``, so the
#                          declaration is a SyntaxError and the constraint a
#                          NameError.                       -> SANITISE
#   ``Length(X)``     50   a Z3 TERM over a declared ``String`` variable,
#                          resolving through ``_Z3_NAMESPACE["Length"]``.
#                                                            -> LEAVE ALONE
#   ``(- X)``          6   a Z3 TERM (unary minus) over a declared ``Int``.
#                                                            -> LEAVE ALONE
#
# For the two TERM shapes the declaration line fails harmlessly (``exec`` is
# per-line inside a ``try``) and the constraint then evaluates correctly. A
# character-set rule would rewrite them on BOTH sides and mint a fresh
# uninterpreted constant disconnected from the string/int variable, severing
# ``Length(X) == |X|`` and making formulas MORE SATISFIABLE -- silent, and in
# the sat-permissive direction. That is the very defect class this module
# exists to remove.
#
# So the discriminator is THE SOLVER'S OWN FUNCTION TABLE, read at runtime:
# a string whose leading token is a head bound in ``_Z3_NAMESPACE``, or a
# bare parenthesised operator form, is a TERM and is left exactly alone;
# any other non-identifier string is a NAME and is sanitised. Deriving the
# exempt set from ``_Z3_NAMESPACE`` rather than hard-coding it means a
# function bound there later is exempted automatically -- and generalising
# along "is this head a solver function?" (the axis that carries the
# meaning) rather than "does this string contain a bracket?" (the axis that
# does not) is what makes a future ``size(X)`` or ``count(X)`` name work
# without anybody having to notice.

#: Marks an encoded name. Chosen to be absent from every name the runtimes
#: mint (``SYM_RESULT_``/``SYM_PARAM_``/``len(...)``); see `to_py_identifier`
#: for why a name that *does* start with it is encoded rather than passed
#: through.
_ENC_PREFIX = "Z3ID_"

_PY_IDENT_RE = re.compile(r"\A[A-Za-z_][A-Za-z0-9_]*\Z")

#: Names that ARE legal identifiers but still must not appear bare in the
#: transported text: Python keywords (a SyntaxError as an assignment target)
#: and the Z3 constructors/combinators the eval namespace provides (binding
#: one would shadow it for every later declaration and expression).
_RESERVED: t.FrozenSet[str] = frozenset(keyword.kwlist) | frozenset(
    getattr(keyword, "softkwlist", ())) | frozenset(_Z3_NAMESPACE)


def _is_plain_identifier(name: str) -> bool:
    """Can `name` be used verbatim as a Python variable in the transport?"""
    return bool(
        _PY_IDENT_RE.match(name)
        and name not in _RESERVED
        and not name.startswith(_ENC_PREFIX)
    )


#: ``Length(X)``, ``(Length(X))``, ``SubString(s, 0, 2)`` -- a call whose head
#: might be a solver function. The head is looked up in ``_Z3_NAMESPACE``
#: AT CALL TIME, so binding a new function there exempts it automatically.
_HEAD_CALL_RE = re.compile(r"\A\s*\(?\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(")

#: ``(- X)``, ``(+ a b)`` -- a parenthesised form led by an OPERATOR rather
#: than by a word. No name is spelled this way; every such string the corpus
#: carries is a z3 term over a variable declared elsewhere.
_OP_FORM_RE = re.compile(r"\A\s*\(\s*[^\sA-Za-z0-9_()]")


def is_solver_term(s: str) -> bool:
    """Is `s` a Z3 TERM over variables declared elsewhere, rather than a NAME?

    A term must be left EXACTLY alone: rewriting it into an identifier mints
    a fresh uninterpreted constant, severs its relationship to the variable
    it is built from (``Length(X)`` from ``X``), and makes the formula more
    satisfiable -- silently, and in the unsound direction.

    Decided by the SOLVER'S OWN TABLE, not by shape: a leading token bound in
    `_Z3_NAMESPACE`, or a parenthesised operator form. ``len(X)`` is NOT a
    term, because z3 has no ``len`` -- which is exactly why it has to be
    sanitised, and exactly why the test is a namespace lookup rather than a
    check for brackets.
    """
    m = _HEAD_CALL_RE.match(s)
    if m and m.group(1) in _Z3_NAMESPACE:
        return True
    return bool(_OP_FORM_RE.match(s))


def to_py_identifier(name: str) -> str:
    """A name -> a legal Python identifier. PURE, TOTAL and INJECTIVE.

    Identity on any name that is already usable verbatim, so the overwhelming
    majority of names (``SYM_RESULT_...``, ``SYM_PARAM_...``) are untouched
    and the transported text is unchanged from what it has always been.

    Otherwise the name is escape-encoded into ``Z3ID_<enc>``::

        len(rows)        -> Z3ID_len_0028rows_0029
        a-b              -> Z3ID_a_002Db
        if               -> Z3ID_if
        Int              -> Z3ID_Int
        Z3ID_x           -> Z3ID_Z3ID__005Fx          (never passed through)

    ENCODING.  Each character maps to itself if it is ASCII alphanumeric;
    ``_`` maps to ``__``; any other character with code point ``cp`` maps to
    ``_HHHH`` (four upper-case hex digits) when ``cp < 0x10000`` and to
    ``_UHHHHHH`` (six) otherwise.

    INJECTIVITY.  The map is a union of two branches with DISJOINT ranges,
    each injective on its own domain:

    1.  The pass-through branch's range is exactly the plain identifiers,
        none of which start with ``Z3ID_`` (`_is_plain_identifier` excludes
        them) -- and it is the identity, hence injective.
    2.  The encoded branch's range is exactly ``Z3ID_`` + an encoding, so
        every image starts with ``Z3ID_``. Disjoint from (1).
    3.  ``enc`` is UNIQUELY DECODABLE, hence injective: scanning left to
        right, a character that is not ``_`` is a literal; a ``_`` opens an
        escape whose length is fixed by the character that follows it --
        ``_`` (a literal underscore, 2 chars), ``U`` (8 chars) or a hex digit
        (5 chars). Those three cases are disjoint because ``U`` is not a hex
        digit and ``_`` is neither. So no two distinct names encode alike,
        and `from_py_identifier` inverts the map exactly.

    There is therefore NO collision risk to exclude: two different names
    cannot become the same Python variable, which is precisely the failure
    that would silently merge two Z3 constants into one.
    """
    if _is_plain_identifier(name):
        return name
    out = [_ENC_PREFIX]
    for ch in name:
        if ("a" <= ch <= "z") or ("A" <= ch <= "Z") or ("0" <= ch <= "9"):
            out.append(ch)
        elif ch == "_":
            out.append("__")
        else:
            cp = ord(ch)
            out.append("_%04X" % cp if cp < 0x10000 else "_U%06X" % cp)
    return "".join(out)


def from_py_identifier(ident: str) -> str:
    """The exact inverse of `to_py_identifier`. PURE and TOTAL.

    ``from_py_identifier(to_py_identifier(n)) == n`` for every ``n``.

    OUTSIDE the encoder's image it is the IDENTITY, and that is checked
    rather than assumed: the decoded name is re-encoded and the result must
    reproduce the input, otherwise the input is returned untouched. Without
    that check ``Z3ID_ZZ`` -- a name nothing ever minted -- would "decode" to
    ``ZZ``, and a reader that can turn a name it does not recognise into a
    DIFFERENT name is the exact failure this module exists to prevent.
    """
    if not ident.startswith(_ENC_PREFIX):
        return ident
    decoded = _decode(ident)
    return decoded if to_py_identifier(decoded) == ident else ident


def _decode(ident: str) -> str:
    """Raw escape-decode of an encoded body; `from_py_identifier` validates."""
    if not ident.startswith(_ENC_PREFIX):
        return ident
    body = ident[len(_ENC_PREFIX):]
    out: t.List[str] = []
    i = 0
    n = len(body)
    while i < n:
        ch = body[i]
        if ch != "_":
            out.append(ch)
            i += 1
            continue
        if i + 1 >= n:
            return ident                                   # malformed
        nxt = body[i + 1]
        if nxt == "_":
            out.append("_")
            i += 2
        elif nxt == "U":
            hexs = body[i + 2:i + 8]
            if len(hexs) != 6 or any(c not in "0123456789ABCDEF" for c in hexs):
                return ident                               # malformed
            out.append(chr(int(hexs, 16)))
            i += 8
        else:
            hexs = body[i + 1:i + 5]
            if len(hexs) != 4 or any(c not in "0123456789ABCDEF" for c in hexs):
                return ident                               # malformed
            out.append(chr(int(hexs, 16)))
            i += 5
    return "".join(out)


#: Splits transported text into quoted string literals and everything else.
#: A Z3 symbol lives INSIDE a literal (``Int('len(X)')``) and must never be
#: rewritten: leaving it alone is what keeps the model's own key spelling
#: equal to the true name, so the "map back on the way out" step is exact
#: rather than a second guess.
_STR_LIT_RE = re.compile(
    r"'(?:[^'\\]|\\.)*'"          # single-quoted
    r'|"(?:[^"\\]|\\.)*"'         # double-quoted
)


def _decl_lhs(decl: str) -> str:
    """The variable a declaration binds: everything left of the first ``=``.

    ``=`` cannot occur inside a name (a name that contained one would be
    encoded anyway), and the right-hand side's ``==`` is to the right of the
    first ``=``, so the split is unambiguous for the declaration shape this
    module has always accepted (``<name> = <Sort>('<name>')``).
    """
    return decl.split("=", 1)[0].strip()


def _rewrite_outside_literals(text: str, subs: t.Sequence[t.Tuple[str, str]]) -> str:
    """Apply `subs` to `text`, skipping over quoted string literals.

    `subs` is ordered LONGEST RAW NAME FIRST so a name that is a substring of
    another cannot pre-empt it. A substitution can never cascade into another
    substitution's output: every raw name in `subs` contains a character that
    is not ``[A-Za-z0-9_]`` or is reserved, while every replacement consists
    only of ``[A-Za-z0-9_]`` -- so no replacement text can contain a raw name
    that still has to be substituted, except a reserved one, which is why
    reserved names are matched on an identifier boundary.
    """
    if not subs:
        return text
    out: t.List[str] = []
    pos = 0
    for m in _STR_LIT_RE.finditer(text):
        out.append(_sub_names(text[pos:m.start()], subs))
        out.append(m.group(0))
        pos = m.end()
    out.append(_sub_names(text[pos:], subs))
    return "".join(out)


def _sub_names(chunk: str, subs: t.Sequence[t.Tuple[str, str]]) -> str:
    for raw, ident in subs:
        if raw not in chunk:
            continue
        if _PY_IDENT_RE.match(raw):
            # A reserved-but-identifier-shaped name (``Int``, ``if``): match
            # whole tokens only, and NEVER a token that is being CALLED. A
            # declared variable is never called, so ``X(`` is always the Z3
            # constructor of that name -- which is exactly how
            # ``Int = Int('Int')`` keeps its right-hand side intact while its
            # left-hand side is renamed out of the way of the namespace.
            chunk = re.sub(
                r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])(?!\s*\()" % re.escape(raw),
                ident, chunk)
        else:
            chunk = chunk.replace(raw, ident)
    return chunk


def _contain_names(
    var_declarations: t.Optional[t.List[str]],
    *expr_lists: t.Sequence[str],
) -> t.Tuple[t.Optional[t.List[str]], t.List[t.List[str]], t.List[str]]:
    """Sanitise every name that cannot survive the Python-text transport.

    Returns ``(declarations, [rewritten expr list, ...], raw_var_names)``.
    ``raw_var_names`` is in the TRUE spelling — it is what the model is read
    back under, because the Z3 symbol inside the declaration's string literal
    is deliberately left alone.

    Nothing is copied and nothing is rewritten when every name is already a
    plain identifier, which is the common case.
    """
    raw_names = [_decl_lhs(d) for d in (var_declarations or [])]
    subs = [(n, to_py_identifier(n)) for n in raw_names
            if not _is_plain_identifier(n) and not is_solver_term(n)]
    if not subs:
        return var_declarations, [list(e) for e in expr_lists], raw_names
    subs.sort(key=lambda p: len(p[0]), reverse=True)
    decls = [_rewrite_outside_literals(d, subs) for d in (var_declarations or [])]
    exprs = [[_rewrite_outside_literals(e, subs) for e in lst] for lst in expr_lists]
    return decls, exprs, raw_names


def _free_const_names(expr: t.Any, acc: t.Set[str]) -> None:
    """Names of the uninterpreted constants (i.e. variables) in ``expr``."""
    stack = [expr]
    seen: t.Set[int] = set()
    while stack:
        e = stack.pop()
        if e.get_id() in seen:
            continue
        seen.add(e.get_id())
        if z3.is_const(e) and e.decl().kind() == z3.Z3_OP_UNINTERPRETED:
            acc.add(e.decl().name())
            continue
        stack.extend(e.children())


def check_satisfiability(
    constraint_exprs: t.List[str],
    var_declarations: t.Optional[t.List[str]] = None,
    timeout_ms: int = 5000,
) -> SolverResult:
    """Check whether a set of Z3 constraints is satisfiable.

    Args:
        constraint_exprs: Z3 constraint strings, e.g. ["x > 5", "x < 10"].
        var_declarations: Z3 variable declaration strings, e.g.
                          ["x = Int('x')", "y = Int('y')"].
        timeout_ms: Solver timeout in milliseconds.

    Returns:
        SolverResult(satisfiable, model_dict or None, elapsed_ms).
    """
    solver = z3.Solver()
    solver.set("timeout", timeout_ms)

    local_env: t.Dict[str, t.Any] = dict(_Z3_NAMESPACE)

    # THE NAME BOUNDARY: names become Python text here and nowhere else.
    var_declarations, (constraint_exprs,), raw_names = _contain_names(
        var_declarations, constraint_exprs)

    if var_declarations:
        for decl in var_declarations:
            try:
                exec(decl, {"__builtins__": {}}, local_env)
            except Exception as e:
                logger.warning("Failed to eval var decl '%s': %s", decl, e)

    for expr_str in constraint_exprs:
        try:
            parsed = eval(expr_str, {"__builtins__": {}}, local_env)
            solver.add(parsed)
        except Exception as e:
            logger.warning("Failed to parse constraint '%s': %s", expr_str, e)
            return SolverResult(False, None, 0.0)

    t0 = time.monotonic()
    result = solver.check()
    t1 = time.monotonic()
    elapsed = (t1 - t0) * 1000.0

    if result == z3.sat:
        model = solver.model()
        if var_declarations:
            # ...and back out of it: `raw_names` is the TRUE spelling, and
            # the Z3 symbols were never renamed (only the Python variables
            # were), so the model's own decl names already match it.
            extracted = _build_variable_map(raw_names, model)
            return SolverResult(True, extracted, elapsed)
        return SolverResult(True, {}, elapsed)
    elif result == z3.unsat:
        return SolverResult(False, None, elapsed)
    else:
        logger.warning("Z3 returned %s (timeout/unknown)", result)
        return SolverResult(False, None, elapsed)


def solve_and_evaluate(
    constraint_exprs: t.List[str],
    var_declarations: t.Optional[t.List[str]] = None,
    eval_exprs: t.Sequence[str] = (),
    timeout_ms: int = 5000,
) -> ModelResult:
    """Solve once, then read every expression of ``eval_exprs`` off the model.

    The point is the second half. ``check_satisfiability`` answers "is this
    SAT"; determinising an outcome ASSIGNMENT over n decisions with it costs
    up to 2n queries, each on a formula that grows as the walk descends. Here
    one ``check()`` produces a model and every decision's outcome is read out
    of it with ``model_completion=True`` — a decision the constraints left
    free gets z3's default value rather than another query, which is exactly
    the freedom the greedy walk was spending solver calls to resolve.

    Args:
        constraint_exprs: Z3 constraint strings, as ``check_satisfiability``.
        var_declarations: Z3 variable declaration strings.
        eval_exprs: boolean Z3 expression strings to evaluate under the model.
        timeout_ms: Solver timeout in milliseconds.

    Returns:
        ModelResult(status, model_dict or None, outcomes or None, elapsed_ms).

    A constraint that fails to parse yields ``"unsat"`` with a warning, which
    is what ``check_satisfiability`` has always done (the coverage checker
    filters unparseable expressions out of its universe up front with a
    tautology probe, so this is a defence, not a path).
    """
    # A PRIVATE context (see ``_namespace``): the same query must produce the
    # same model every time it is asked, in this process and the next one.
    ctx = z3.Context()
    solver = z3.Solver(ctx=ctx)
    solver.set("timeout", timeout_ms)

    local_env: t.Dict[str, t.Any] = _namespace(ctx)

    # THE NAME BOUNDARY: names become Python text here and nowhere else.
    # `eval_exprs` is rewritten too -- it is the KEY of the `outcomes` dict,
    # so the caller's own spelling is restored before returning.
    var_declarations, (constraint_exprs, sane_evals), raw_names = _contain_names(
        var_declarations, constraint_exprs, list(eval_exprs))
    eval_back = dict(zip(sane_evals, eval_exprs))

    if var_declarations:
        for decl in var_declarations:
            try:
                exec(decl, {"__builtins__": {}}, local_env)
            except Exception as e:
                logger.warning("Failed to eval var decl '%s': %s", decl, e)

    for expr_str in constraint_exprs:
        try:
            parsed = eval(expr_str, {"__builtins__": {}}, local_env)
            solver.add(parsed)
        except Exception as e:
            logger.warning("Failed to parse constraint '%s': %s", expr_str, e)
            return ModelResult("unsat", None, None, 0.0)

    # parsed up front: a parse failure here must not be mistaken for a
    # solver answer, and the ASTs are needed twice (evaluation, and the
    # variable sweep below).
    parsed_eval: t.Dict[str, t.Any] = {}
    for expr_str in sane_evals:
        try:
            parsed_eval[expr_str] = eval(expr_str, {"__builtins__": {}}, local_env)
        except Exception as e:
            logger.warning("Failed to parse eval expr '%s': %s",
                           eval_back.get(expr_str, expr_str), e)

    t0 = time.monotonic()
    result = solver.check()
    t1 = time.monotonic()
    elapsed = (t1 - t0) * 1000.0

    if result == z3.unsat:
        return ModelResult("unsat", None, None, elapsed)
    if result != z3.sat:
        logger.warning("Z3 returned %s (timeout/unknown)", result)
        return ModelResult("unknown", None, None, elapsed)

    model = solver.model()

    outcomes: t.Dict[str, bool] = {}
    wanted: t.Set[str] = set()
    for expr_str, parsed in parsed_eval.items():
        _free_const_names(parsed, wanted)
        try:
            val = model.eval(parsed, model_completion=True)
        except Exception as e:  # noqa: BLE001 - a non-boolean / exotic term
            logger.warning("Failed to evaluate '%s' under the model: %s", expr_str, e)
            continue
        key = eval_back.get(expr_str, expr_str)
        if z3.is_true(val):
            outcomes[key] = True
        elif z3.is_false(val):
            outcomes[key] = False
        else:
            logger.warning("Expression '%s' evaluated to %s, not a boolean literal",
                           key, val)

    extracted: t.Dict[str, t.Any] = {}
    if var_declarations:
        # `raw_names` is the TRUE spelling; the Z3 symbols were never
        # renamed, so the model's decl names already match it.
        var_names = raw_names
        extracted = _build_variable_map(var_names, model)
        # A variable of an evaluated expression that the constraints never
        # mention is absent from the model, so the witness would not pin the
        # value the outcome above was read at. Complete exactly those — not
        # the whole declaration list, which would bury the witness in
        # hundreds of irrelevant defaults.
        for name in var_names:
            if name in extracted or name not in wanted:
                continue
            # `local_env` is keyed by the PYTHON-TEXT name, `name` by the
            # true one -- this is the one read that crosses back the other way.
            var = local_env.get(to_py_identifier(name))
            if var is None:
                continue
            try:
                extracted[name] = _concrete(
                    model.eval(var, model_completion=True), str(var.sort()))
            except Exception as e:  # noqa: BLE001
                logger.warning("Failed to complete variable '%s': %s", name, e)

    return ModelResult("sat", extracted, outcomes, elapsed)
