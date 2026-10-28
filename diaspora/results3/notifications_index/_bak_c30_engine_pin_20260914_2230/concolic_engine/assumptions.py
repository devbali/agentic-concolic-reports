"""
Assumptions — user-declared facts about program structure.

Assumptions let an agent (or human) tell the concolic engine things
it can't prove automatically:

- **Independence**: Two code regions don't affect each other's branch
  outcomes. The coverage checker cuts the edge between them, so the
  combination of their outcomes is not demanded. Since 2026-09-10 it only
  ever speaks about a pair some run evaluated TOGETHER — see below.

- **SymbolicConstraint**: An extra Z3 constraint applied to every SMT
  query (e.g. ``a < 200``). Makes some missing paths UNSAT, reducing
  the search space.

- **UntrackedPath**: A PC source that is marked not-important. The
  missing branch is reported but does NOT count toward completeness.

- **OneSideUntrackedPath**: Like UntrackedPath but only one side of
  the branch is untracked; the other side is enforced normally.

Design goal: Assumptions should never cause false negatives (miss a
real bug), only false positives (report something as covered when
it technically isn't).

Identifying a path condition
----------------------------
An assumption names the path condition it applies to by **source location**
(``PathSource``), by **branch expression** (``expr``), or by both. Which one to
use follows from where the path condition was recorded.

**Path conditions recorded at a mock boundary are intended design, not a
workaround.** A target function that stands in for an external boundary decides
its own outcome — "did this query return a row?" — with an explicit symbolic
comparison inside the mock, and returns a concrete value so the caller branches
consistently. That is the only way the decision can be recorded at all when the
host language's truthiness is not interceptable (see ``src/TODO.txt``): the
application writes ``rescue RecordNotFound`` or a bare ``if row``, neither of
which the runtime can observe. In the diaspora experiment this is where **~64%
of all path conditions come from**, and it is how a *generic* interceptor is
supposed to work — one shared mock serving every finder in the program.

The consequence for assumptions is direct: **every decision made by one mock
shares that mock's source location.** In that experiment all twelve finder
decisions in a single entrypoint — the action's own 404 lookup and the
response presenter's field lookups alike — record at
``concolic_targets.rb:331 in block in finder_mock``. Measured across the whole
corpus, 129 of 146 distinct branch expressions (88%) sit at a source shared
with at least one other expression. The same is true of conditions recorded
inside framework internals: ``blank.rb:126`` is where *every* ``.blank?`` on a
symbolic string records.

So:

- **``expr``** identifies a *decision* — use it for mock-boundary and
  framework-internal conditions, which is most of them.
- **``source``** identifies a *site* — use it when a site really does host one
  decision, typically a branch written in application code.
- **both** requires both to match: one decision at one site.
- **neither** matches nothing. A blank assumption is inert, never a wildcard;
  untracking is a relaxation, so an under-specified assumption must not
  silently apply to every branch in the program.

Expression matching is exact — no globbing, no regex.

A caveat that belongs with ``expr``: if the runtime names symbolic results with
a per-run call ordinal, the same expression can denote different calls in
different runs (flipping an early branch renumbers later variables). The
execution tree is already keyed by expression, so this is not new, but an
assumption keyed by ``expr`` inherits it — check that the decision you are
naming means the same thing in every run you feed the checker.
"""

from __future__ import annotations

import dataclasses
import typing as t


# ---------------------------------------------------------------------------
# PathSource — structured code location
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class PathSource:
    """A structured code location that an agent can use to locate source.

    Replaces the free-text 'source' string on PathCondition and CallEvent.
    An agent can use these fields to fetch the actual source code, analyze
    data dependencies, or make informed assumptions.

    Attributes:
        file: File path (absolute or relative to project root).
        lineno: Line number (1-based).
        col_offset: Column offset (1-based, optional).
        function: Function or method name.
        snippet: A short snippet of the source line (optional, for display).

    ``file`` and ``lineno`` default to empty so that ``PathSource()`` is a
    valid "no location given" value. Assumptions use it as their default
    field, and one keyed only by ``expr`` leaves it unset.
    """

    file: str = ""
    lineno: int = 0
    function: str = ""
    col_offset: int = 0
    snippet: str = ""

    def __str__(self) -> str:
        loc = f"{self.file}:{self.lineno}"
        if self.col_offset:
            loc += f":{self.col_offset}"
        if self.function:
            loc += f" in {self.function}()"
        return loc

    def __repr__(self) -> str:
        return f"PathSource({self.file}:{self.lineno}, func={self.function})"


# ---------------------------------------------------------------------------
# Matching a path condition — see "Identifying a path condition" above
# ---------------------------------------------------------------------------


def _source_key(src: t.Optional[PathSource]) -> t.Tuple[str, int, str]:
    if src is None:
        return ("", 0, "")
    return (src.file, src.lineno, src.function)


def _declared(src: t.Optional[PathSource]) -> bool:
    """True if this PathSource actually names a location (not the empty default)."""
    return _source_key(src) != ("", 0, "")


def _matches(
    a_source: t.Optional[PathSource],
    a_expr: str,
    source: t.Optional[PathSource],
    expr: str,
) -> bool:
    """Does an assumption's (source, expr) identify this path condition?

    - expr only     -> exact match on the branch expression
    - source only   -> match on (file, lineno, function)   [original behaviour]
    - both          -> both must match (names one decision at one site)
    - neither       -> matches nothing; a blank assumption is inert, never
                       a wildcard. Untracking is a relaxation, so an
                       under-specified assumption must not silently apply
                       to every branch in the program.

    Expression matching is EXACT — no globbing, no regex. Assumptions can only
    ever make a report more permissive, so the matcher is deliberately the
    least surprising thing that works.
    """
    want_expr = bool(a_expr)
    want_source = _declared(a_source)
    if not want_expr and not want_source:
        return False
    if want_expr and a_expr != expr:
        return False
    if want_source and _source_key(a_source) != _source_key(source):
        return False
    return True


# ---------------------------------------------------------------------------
# Assumption — base class
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class Assumption:
    """Base class for all assumptions.

    An assumption is a user-declared fact about program behavior that
    the concolic engine may use to reduce the search space.

    Attributes:
        description: Human-readable explanation of this assumption.
        agent_notes: Optional metadata from the agent that made this
                     assumption (confidence level, reasoning, etc.).
    """

    description: str = ""
    agent_notes: str = ""


# ---------------------------------------------------------------------------
# IndependenceAssumption
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class IndependenceAssumption(Assumption):
    """Declares that two path sources produce independent branch decisions.

    The coverage checker removes the edge between the two expressions, so
    their combination is not demanded. The removal is strictly PAIRWISE —
    each expression keeps its edges to everything else — and it applies
    INSIDE each evaluation set that holds both (coverage.py step 5).

    **A declaration over a pair NO RUN ever evaluated together is INERT**
    (co-evaluation semantics, 2026-09-10 — see coverage.py's docstring and
    DISCIPLINE §16). There is no demand over such a pair to relax, so do not
    write one: it is noise in the report and a free, unprobed PASS in the
    assumption gate. This retires a whole genre of declaration —
    "these are different request formats / different controller arms /
    mutually exclusive scenarios, so no run records both" — which the
    checker now derives from the same evidence for itself.

    ----------
    SAFETY WARNING
    ----------
    This is the MOST DANGEROUS assumption in the system.  If wrong, Z3
    will never see combined constraints from both branches, and paths
    requiring a specific combination of decisions will be silently missed.

    The concolic framework traces **access patterns** — the sequence of
    target function calls (with their arguments) that execute along a
    path.  Independence is about whether the *combination* of two branch
    decisions could produce an access pattern that neither branch alone
    would produce.

    **You may ONLY declare independence when:**

    No combination of (PC #1 outcome, PC #2 outcome) produces a call
    sequence or argument shape that the individual branch trees don't
    already cover.  Concretely, this means:

    1. ~~The two PC sources are in execution paths that are mutually
       exclusive~~ — RETIRED 2026-09-10. Mutual exclusion needs no
       declaration: a pair no run co-evaluates carries no demand. If you
       find yourself writing this argument, delete the declaration instead.

    2. Neither branch's concrete arguments to target functions depend
       on the other branch's outcome *in a way that the engine tracks*
       — i.e., through a symbolic variable or a @target return value.
       Plain Python locals, state outside the model (loggers, caches,
       connection pools), and immutable constants are irrelevant.

    **The practical test:** "Can I imagine a concrete execution where
    the sequence of target function calls (the access trace) is
    different for (A=True, B=False) vs (A=True, B=True) vs the
    individual branch trees?"  If yes, don't assume independence.

    Attributes:
        source_a: The first path source.
        source_b: The second path source.
    """

    source_a: PathSource = dataclasses.field(default_factory=PathSource)
    source_b: PathSource = dataclasses.field(default_factory=PathSource)
    expr_a: str = ""
    expr_b: str = ""

    def __post_init__(self) -> None:
        if not self.description:
            a = self.expr_a or str(self.source_a)
            b = self.expr_b or str(self.source_b)
            object.__setattr__(self, "description", f"Independence: {a} || {b}")


# ---------------------------------------------------------------------------
# SymbolicConstraintAssumption
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class SymbolicConstraintAssumption(Assumption):
    """An extra Z3 constraint fed into every SMT query the checker makes.

    This narrows the solver's search space. For example, if the agent
    knows ``a`` is always less than 200, this assumption adds
    ``a < 200`` to every query, making any path requiring ``a >= 200``
    UNSAT — the checker won't report it as missing coverage.

    The constraint string must be a valid Z3 expression using the same
    variable names declared in the runs' ``SymbolicVar`` list.

    Attributes:
        z3_expr: A Z3-parseable expression string, e.g. ``"a < 200"``.
                 Will be fed into every SMT query alongside the normal
                 prefix and missing-branch constraints.
    """

    z3_expr: str = ""

    def __post_init__(self) -> None:
        if not self.description and self.z3_expr:
            object.__setattr__(
                self,
                "description",
                f"SymbolicConstraint: {self.z3_expr}",
            )


# ---------------------------------------------------------------------------
# UntrackedPathAssumption
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class UntrackedPathAssumption(Assumption):
    """Marks a PC source as untracked — missing branches are noted but
    do NOT count toward completeness.

    Use this when a particular branch point is not interesting for
    coverage (e.g. a sanity check, a logging guard, an assertion that
    the agent considers irrelevant to the target's logic).

    The tree node still exists. The missing side is reported in the
    result's ``missing`` list but the overall ``complete`` flag is
    computed as if that node's missing side was satisfied.

    Attributes:
        source: The PathSource of the PC to untrack.
    """

    source: PathSource = dataclasses.field(default_factory=PathSource)
    expr: str = ""

    def __post_init__(self) -> None:
        if not self.description:
            object.__setattr__(
                self,
                "description",
                f"UntrackedPath: {self.expr or self.source}",
            )


# ---------------------------------------------------------------------------
# OneSideUntrackedPathAssumption
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class OneSideUntrackedPathAssumption(Assumption):
    """Untracks only ONE side of a branch point.

    The ``tracked_side`` is enforced — the Z3 solver must find concrete
    values for it, and missing coverage on that side blocks completeness.

    The OTHER side is untracked — missing coverage there does NOT block
    completeness (Z3 still runs so the constraint feeds the solver).

    .. code-block:: text

        | Missing side     | Z3 runs? | In missing list? | Blocks complete? |
        |------------------|----------|------------------|------------------|
        | *tracked* side   | ✅       | ✅               | ✅               |
        | *untracked* side | ✅       | ❌               | ❌               |

    Use this when one branch leads to an important access pattern (e.g.
    ``if user_id: return get_user_data(user_id)``) and the other is a
    no-op (``else: return None``). You want the solver to *always*
    explore the important side, but you don't care about covering the
    useless side to declare completeness.

    Contrast with ``UntrackedPathAssumption`` which untracks BOTH sides
    — both the taken and not-taken branches are excluded from the
    completeness check.

    Attributes:
        source: The PathSource of the PC.
        tracked_side: Which outcome is tracked — ``"taken"``
            (the PC's condition is true) or ``"not_taken"`` (the PC's
            condition is false).  The other side is untracked.
    """

    source: PathSource = dataclasses.field(default_factory=PathSource)
    tracked_side: str = "taken"
    expr: str = ""

    def __post_init__(self) -> None:
        if self.tracked_side not in ("taken", "not_taken"):
            raise ValueError(
                f"tracked_side must be 'taken' or 'not_taken', got {self.tracked_side!r}"
            )
        if not self.description:
            untracked = "not_taken" if self.tracked_side == "taken" else "taken"
            who = self.expr or self.source
            object.__setattr__(
                self,
                "description",
                f"OneSideUntracked({who}): tracking '{self.tracked_side}', untracking '{untracked}'",
            )


# ---------------------------------------------------------------------------
# AliasAssumption — re-key a decision by WHAT produced it (mostly: by its loop)
# ---------------------------------------------------------------------------

import hashlib as _hashlib
import re as _re

_BIND_RE = _re.compile(r"\$\$\([^)]*\)")
_STR_LIT_RE = _re.compile(r"'(?:[^']|'')*'")
_NUM_LIT_RE = _re.compile(r'(?<![A-Za-z0-9_"])-?\d+(?![A-Za-z0-9_"])')
_FROM_RE = _re.compile(r'FROM\s+"?([A-Za-z0-9_]+)"?', _re.I)
_STMT_RE = _re.compile(r"^\s*(SELECT|INSERT|UPDATE|DELETE|WITH)\b", _re.I)


def is_statement_note(note: t.Optional[str]) -> bool:
    """A note that records a STATEMENT (as opposed to prose: a wall marker, a
    "preloaded association ... no statement" explanation, a render probe)."""
    return bool(note) and bool(_STMT_RE.match(str(note)))


def statement_key(note: str, keep_binds: bool = True) -> str:
    """The identity of the statement a note stands for.

    Whitespace is collapsed; string and numeric LITERALS are wildcarded
    (a page offset or a type literal is data, not identity); ``$$(VAR)``
    BINDS are kept verbatim when ``keep_binds`` — a read keyed on a
    different owner is a different statement (DISCIPLINE §14: bind identity
    is part of the statement). ``keep_binds=False`` wildcards the binds too
    and identifies statements by SHAPE only; it exists so the gate can be
    validated against a deliberately unsound alias, not for declaring one.
    """
    n = _re.sub(r"\s+", " ", str(note or "").strip())
    parts = _BIND_RE.split(n)
    binds = _BIND_RE.findall(n)
    out = []
    for i, p in enumerate(parts):
        p = _STR_LIT_RE.sub("'?'", p)
        p = _NUM_LIT_RE.sub("?", p)
        out.append(p)
        if i < len(binds):
            out.append(binds[i] if keep_binds else "$$(?)")
    return "".join(out)


def call_shape(
    target: t.Optional[str], note: t.Optional[str], args: t.Optional[t.Mapping[str, t.Any]],
) -> t.Tuple[str, str, t.Tuple[t.Tuple[str, str], ...]]:
    """The SHAPE of one target call: ``(target, note with binds and string
    literals wildcarded, argument shape)`` — the currency of the assumption
    gate's access trace (``end_to_end_completion_checker/assumption/
    assumption_checker.py::access_trace``) and, since 2026-09-11, of the
    engine's per-decision FOOTPRINT (``coverage.py::infer_footprints``). One
    function so the two can never disagree on what a shape is. Binds are
    wildcarded, so a shape is the same under every alias renaming."""
    n = _BIND_RE.sub("?", str(note or ""))
    n = _re.sub(r"'[^']*'", "'?'", n)
    arg_shape = tuple(sorted((k, type(v).__name__) for k, v in (args or {}).items()
                             if v is not None))
    return (str(target or ""), n, arg_shape)


def shape_str(shape: t.Tuple[str, str, t.Tuple[t.Tuple[str, str], ...]]) -> str:
    """One-line, JSON-safe rendering of a ``call_shape`` (for footprints in a
    summary file and for the gate's declared-test input). Injective on the
    tuple: the separator never occurs in a target name, and a note has no
    newline."""
    target, note, arg_shape = shape
    return f"{target} | {note} | " + " ".join(f"{k}:{ty}" for k, ty in arg_shape)


def loop_key(note: str) -> str:
    """The identity of the LOOP whose rows a statement produces: WHAT is read
    (the table) and WHOSE rows they are (the binds, already rewritten to the
    producing chain by ``_alias_core``).

    Everything that only makes a VARIANT of the same loop is dropped — an
    extra scope, a type or flag predicate over literals, an ordering, a page
    window. ``FROM notifications BY $$(<principal>_id)`` names the
    notifications loop whether the run read the plain, typed, unread or
    typed-and-unread variant of that list. A different bind — a photos read
    keyed on ``..._row_target_guid`` rather than
    ``..._row_target_mentions_container_guid`` — is a different OWNER chain
    and so a different loop.

    The CALL SITE is not in the key because it is already in the name:
    ``canonical_result_name`` keeps the result's stem, so ``Relation_to_ary``
    and ``Relation_records`` on one table with one bind stay two names.
    """
    n = statement_key(note)
    m = _FROM_RE.search(n)
    table = _re.sub(r"[^A-Za-z0-9_]", "_", m.group(1)) if m else "stmt"
    return f"FROM {table} BY {' '.join(_BIND_RE.findall(n))}"


def canonical_result_name(result_name: str, key: str) -> str:
    """``<stem>_<table>_<8 hex of key>`` — the ordinal suffix of
    ``result_name`` replaced by an identifier of WHAT the call resolved to.
    Same statement key ⇒ same name in every run; the table keeps it readable
    and the hash keeps two statements on one table apart."""
    stem = _re.sub(r"_\d+$", "", result_name)
    m = _FROM_RE.search(key)
    table = _re.sub(r"[^A-Za-z0-9_]", "_", m.group(1)) if m else "stmt"
    return f"{stem}_{table}_{_hashlib.sha1(key.encode()).hexdigest()[:8]}"


@dataclasses.dataclass(frozen=True)
class AliasAssumption(Assumption):
    """Declares that a decision is identified by WHAT produced it, not by WHEN
    it was made — and, for a LOOP, by the loop rather than by the statement.

    Mostly this is about loops. A runtime that names results with a per-run
    call ordinal (``SYM_RESULT_<target>_<idx>``) makes the same expression
    denote different decisions in different runs whenever an earlier branch
    changes the call sequence (the caveat in this module's docstring). Every
    other assumption kind is keyed statically on (source, expr) and so
    inherits that ambiguity. This kind re-keys: every symbolic result whose
    name matches ``result_pattern`` is renamed, per run, to
    ``canonical_result_name(name, <key>(note))`` — an identifier of what its
    ``symbolic_call`` note records — and every symbolic variable,
    path-condition expression, note and concrete value derived from that
    result is renamed with it, including the decisions made about its ROWS
    (``<list>_row_<chain>``) and its cardinality (``SYM_LEN_<list>_rows``).
    Results whose call carried no STATEMENT note (a read answered from
    memory, a wall, prose) are left alone.

    **What "the same loop" means** (``key="loop"``, see ``loop_key``): the
    same list stem — the call site, which the canonical name keeps — reading
    the same table keyed on the same binds, ACROSS the list's variants and
    ACROSS its iterations. A decision made about a row is the same decision
    on iteration 1 or iteration 5, and whether the row came from the unread
    list or the full list. A different OWNER chain in the binds is a
    different loop and does not merge.

    "The loop only needs to be hit once" is not a separate claim; it follows.
    If every iteration makes the same decisions, seeing one iteration sees
    them all — which is why ``k`` is a property of this kind and not of a
    second one.

    This is an IDENTITY claim, not a relaxation: two (expr, run) pairs are
    declared one decision iff the same loop produced them. It is sound
    exactly when that holds, and the gate's derived test checks it — the
    statement census under each name, identical intervention effects on a
    snapshot of each aliased reading, and a replay at ``k + 1`` rows
    requiring the same intervention effects and the same target-call shapes
    (see ``end_to_end_completion_checker/assumption/assumption_checker.py``).
    A FAIL withdraws the declaration.

    Inert unless declared: with no alias in the set the runs the checker
    sees are exactly the runs it was given.

    Attributes:
        result_pattern: regex (full match) over symbolic result names.
        key: ``"statement"`` (default) identifies by the statement with binds
             kept — one identity per statement, so a list's variants stay
             apart; ``"loop"`` widens that to the loop the statement iterates
             (table + binds, variants folded); ``"shape"`` wildcards binds
             too — UNSOUND for any read keyed on a run-dependent owner,
             provided only so the gate's test can be shown to fail.
        k: the iteration at which the identity kicks in. ``k=1`` (default)
           aliases every iteration to the first. The field exists so the
           claim can be weakened later ("iterations from the k-th on are the
           same decision") without a second kind; the gate replays at
           ``k + 1`` rows either way.
    """

    result_pattern: str = ""
    key: str = "statement"
    k: int = 1

    def __post_init__(self) -> None:
        if self.key not in ("statement", "loop", "shape"):
            raise ValueError(
                f"key must be 'statement', 'loop' or 'shape', got {self.key!r}")
        if self.k < 1:
            raise ValueError(f"k must be >= 1, got {self.k!r}")
        if not self.description:
            object.__setattr__(
                self, "description",
                f"Alias: {self.result_pattern} by {self.key}"
                + (f" (k={self.k})" if self.key == "loop" else ""))

    def matches(self, result_name: str) -> bool:
        return bool(self.result_pattern) and bool(
            _re.fullmatch(self.result_pattern, result_name or ""))


def _alias_core(
    events: t.Sequence[t.Tuple[str, t.Optional[str]]],
    aliases: t.Sequence["AliasAssumption"],
) -> t.Tuple[t.Dict[str, str], t.Dict[str, str]]:
    """(``{ordinal: canonical name}``, ``{ordinal: statement key}``) for one run.

    ``events`` is the run's ``(result_name, note)`` sequence in call order.
    A note's binds may name EARLIER results; before a key is taken those are
    rewritten to the earlier result's CHAIN identity — ``<stem>_<table>``,
    the canonical name without its hash — so a nested read keyed on "a row
    of the notifications list" has one identity whichever variant of that
    list (plain / typed / unread) produced the row, exactly as the runtime's
    own one-fact rule (rendered SQL with bind NAMES, which carry no upstream
    variant) treats it; a different owner CHAIN (``_row_target_guid`` vs
    ``_row_target_mentions_container_guid``) stays a different bind and so a
    different statement. A ``key="loop"`` alias widens the same rule to the
    reading itself: the key becomes ``loop_key`` of that rendered note, so a
    list's variants are one loop and everything derived from it — its rows'
    decisions and its length — is renamed with it.  Pure function of
    (events, aliases): the engine and the gate compute the same maps from the
    same dump.
    """
    amap: t.Dict[str, str] = {}
    kmap: t.Dict[str, str] = {}   # ordinal -> chain identity used inside keys
    keys: t.Dict[str, str] = {}
    if not aliases:
        return amap, keys
    for rn, note in events:
        if not rn or not is_statement_note(note):
            continue   # no statement recorded: nothing to identify the call by
        a = next((x for x in aliases if x.matches(rn)), None)
        if a is None:
            continue
        rendered = renamer(kmap)(note)
        key = (loop_key(rendered) if a.key == "loop"
               else statement_key(rendered, keep_binds=(a.key == "statement")))
        canon = canonical_result_name(rn, key)
        if rn not in amap:
            amap[rn] = canon
            kmap[rn] = _re.sub(r"_[0-9a-f]{8}$", "", canon)
            keys[rn] = key
    return amap, keys


def alias_map_for(
    events: t.Sequence[t.Tuple[str, t.Optional[str]]],
    aliases: t.Sequence["AliasAssumption"],
) -> t.Dict[str, str]:
    """``{ordinal result name: canonical name}`` for one run (see _alias_core)."""
    return _alias_core(events, aliases)[0]


def alias_keys_for(
    events: t.Sequence[t.Tuple[str, t.Optional[str]]],
    aliases: t.Sequence["AliasAssumption"],
) -> t.Dict[str, str]:
    """``{ordinal result name: statement key}`` — the identity each aliased
    result was given, for the gate's identity test."""
    return _alias_core(events, aliases)[1]


def renamer(amap: t.Dict[str, str]) -> t.Callable[[t.Optional[str]], t.Optional[str]]:
    """A function applying an alias map to any text carrying result names
    (var names, exprs, notes, seed keys). Longest name first; a name is never
    matched as a prefix of a longer ordinal (``records_1`` vs ``records_11``).
    Compiled once — call it for every string of one run."""
    if not amap:
        return lambda s: s
    pat = _re.compile(
        r"(" + "|".join(sorted(map(_re.escape, amap), key=len, reverse=True)) + r")(?![0-9])")
    return lambda s: pat.sub(lambda m: amap[m.group(1)], s) if s else s


def rename_with(amap: t.Dict[str, str], text: t.Optional[str]) -> t.Optional[str]:
    return renamer(amap)(text)


# ---------------------------------------------------------------------------
# AssumptionSet — collection of assumptions
# ---------------------------------------------------------------------------


@dataclasses.dataclass
class AssumptionSet:
    """A collection of assumptions for a concolic analysis session."""

    assumptions: t.List[Assumption] = dataclasses.field(default_factory=list)

    def add(self, assumption: Assumption) -> None:
        self.assumptions.append(assumption)

    # -- query helpers ---------------------------------------------------
    #
    # Every query below matches on EITHER identity — see "Identifying a path
    # condition" in the module docstring. An assumption that declares only a
    # source matches by source (the original behaviour, unchanged); one that
    # declares only an expr matches by expr; one that declares both requires
    # both, which is how you name a single decision that also has a
    # distinguishing source.

    def are_independent(
        self,
        source_a: t.Optional[PathSource],
        source_b: t.Optional[PathSource],
        expr_a: str = "",
        expr_b: str = "",
    ) -> bool:
        """Check if any IndependenceAssumption covers these two path conditions."""
        # Two occurrences of the SAME decision are never independent of each
        # other. Identity is the expr when we have one (mock-boundary PCs share
        # a source by design), else the source key.
        if expr_a and expr_b:
            if expr_a == expr_b:
                return False
        elif _source_key(source_a) == _source_key(source_b):
            return False

        for a in self.assumptions:
            if not isinstance(a, IndependenceAssumption):
                continue
            fwd = (_matches(a.source_a, a.expr_a, source_a, expr_a)
                   and _matches(a.source_b, a.expr_b, source_b, expr_b))
            rev = (_matches(a.source_a, a.expr_a, source_b, expr_b)
                   and _matches(a.source_b, a.expr_b, source_a, expr_a))
            if fwd or rev:
                return True
        return False

    def is_untracked(self, source: t.Optional[PathSource], expr: str = "") -> bool:
        """Check if this path condition is marked as fully untracked."""
        for a in self.assumptions:
            if not isinstance(a, UntrackedPathAssumption):
                continue
            if _matches(a.source, a.expr, source, expr):
                return True
        return False

    def is_one_side_untracked(
        self, source: t.Optional[PathSource], side: str, expr: str = ""
    ) -> bool:
        """Check if a specific side of this path condition is untracked.

        Returns True if there is a OneSideUntrackedPathAssumption matching this
        path condition and the given ``side`` is the untracked one (i.e. not the
        tracked_side).

        Args:
            source: The source location to check (may be None).
            side: The outcome to check — ``"taken"`` or ``"not_taken"``.
            expr: The branch expression, e.g.
                ``"(SYM_RESULT_..._find_by_5_not_found == True)"``.

        Returns:
            True if this specific side should not block completeness.
        """
        for a in self.assumptions:
            if not isinstance(a, OneSideUntrackedPathAssumption):
                continue
            if _matches(a.source, a.expr, source, expr) and side != a.tracked_side:
                return True
        return False

    def symbolic_constraints(self) -> t.List[str]:
        """Return all SymbolicConstraint assumption Z3 expressions."""
        return [
            a.z3_expr
            for a in self.assumptions
            if isinstance(a, SymbolicConstraintAssumption) and a.z3_expr
        ]

    # -- aliases -----------------------------------------------------------

    def aliases(self) -> t.List["AliasAssumption"]:
        return [a for a in self.assumptions if isinstance(a, AliasAssumption)]

    def alias_map(self, run: t.Any) -> t.Dict[str, str]:
        """Per-run ``{ordinal result name: canonical name}`` (empty when no
        alias is declared)."""
        aliases = self.aliases()
        if not aliases:
            return {}
        events = [(e.result_name, e.note) for e in run.symbolic_call_events]
        return alias_map_for(events, aliases)

    def apply_aliases(self, runs: t.Sequence[t.Any]) -> t.List[t.Any]:
        """Runs with every declared alias applied — the SAME list object
        when no alias is declared (inert), otherwise new Run objects with
        symbolic vars, events (exprs, result names, notes) and concrete
        values renamed. Runs are never mutated."""
        if not self.aliases():
            return runs if isinstance(runs, list) else list(runs)
        from .run import Run, PathCondition, SymbolicCallEvent  # local: avoid an import cycle
        out = []
        for run in runs:
            amap = self.alias_map(run)
            if not amap:
                out.append(run)
                continue
            rn = renamer(amap)
            svs = [dataclasses.replace(sv, name=rn(sv.name)) for sv in run.symbolic_vars]
            evs = []
            for ev in run.events:
                if isinstance(ev, PathCondition):
                    evs.append(dataclasses.replace(ev, expr=rn(ev.expr)))
                elif isinstance(ev, SymbolicCallEvent):
                    evs.append(dataclasses.replace(
                        ev, result_name=rn(ev.result_name), note=rn(ev.note)))
                else:
                    evs.append(ev)
            out.append(Run(
                symbolic_vars=svs, events=evs,
                concrete_values={rn(k): v for k, v in run.concrete_values.items()},
                label=run.label,
                symbolic_results={rn(k): v for k, v in run.symbolic_results.items()},
                script=run.script, error=run.error))
        return out

    # -- misc ------------------------------------------------------------

    def __bool__(self) -> bool:
        return len(self.assumptions) > 0

    def __len__(self) -> int:
        return len(self.assumptions)

    def __repr__(self) -> str:
        if not self.assumptions:
            return "AssumptionSet([])"
        lines = [f"AssumptionSet ({len(self.assumptions)}):"]
        for a in self.assumptions:
            lines.append(f"  - {a.description}")
        return "\n".join(lines)
