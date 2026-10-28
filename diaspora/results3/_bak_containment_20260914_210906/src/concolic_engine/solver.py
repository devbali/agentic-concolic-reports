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
import logging
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
            var_names = [d.split("=")[0].strip() for d in var_declarations]
            extracted = _build_variable_map(var_names, model)
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
    for expr_str in eval_exprs:
        try:
            parsed_eval[expr_str] = eval(expr_str, {"__builtins__": {}}, local_env)
        except Exception as e:
            logger.warning("Failed to parse eval expr '%s': %s", expr_str, e)

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
        if z3.is_true(val):
            outcomes[expr_str] = True
        elif z3.is_false(val):
            outcomes[expr_str] = False
        else:
            logger.warning("Expression '%s' evaluated to %s, not a boolean literal",
                           expr_str, val)

    extracted: t.Dict[str, t.Any] = {}
    if var_declarations:
        var_names = [d.split("=")[0].strip() for d in var_declarations]
        extracted = _build_variable_map(var_names, model)
        # A variable of an evaluated expression that the constraints never
        # mention is absent from the model, so the witness would not pin the
        # value the outcome above was read at. Complete exactly those — not
        # the whole declaration list, which would bury the witness in
        # hundreds of irrelevant defaults.
        for name in var_names:
            if name in extracted or name not in wanted:
                continue
            var = local_env.get(name)
            if var is None:
                continue
            try:
                extracted[name] = _concrete(
                    model.eval(var, model_completion=True), str(var.sort()))
            except Exception as e:  # noqa: BLE001
                logger.warning("Failed to complete variable '%s': %s", name, e)

    return ModelResult("sat", extracted, outcomes, elapsed)
