"""
SymbolicList — a symbolic wrapper around a symbolic length plus ONE optional
representative element.

Per design (PLAN_symbolic_query_ops.md §5 + DESIGN_sampled_content_list.md
§1–5 — Gate 1b): a SymbolicList models the "how many rows" dimension of a
query result symbolically (unchanged) PLUS, when a ``representative:`` is
supplied, holds a single representative element (typically a symbolic model
instance). Element-ACCESS ops (``[0]``, ``in``) use that one representative
row; iteration (``__iter__`` and the map/iteration stubs) STAYS
unimplemented — iteration is handled by caller-wrapping at the mocked
boundary, never executed against the list.

Back-compat: a list with ``representative=None`` behaves EXACTLY as before
(every element/iteration op raises NotImplementedError).

Tracked operations::

    if result:        # bool() → records (SYM_LEN_X != 0) / negation
    if not result:    # same
    len(result)       # concrete int (Python requires int); use
    result.length     # → SymbolicInt for PC-recording comparisons
    result[0]         # → representative when set (else raise)

Representative must be a SYMBOLIC value (SymbolicInt / SymbolicString / a
symbolic model instance) — element access returns that symbolic rep, so
``result[0] == "hello"`` records a PC via the rep's own ``==``
(SymbolicString.__eq__). It must NOT be a plain concrete scalar.

Membership (``x in result`` / contains) is NOT implemented in either runtime:
no Z3 path-condition support for set/similarity membership, so a contains
check can't be recorded as a sound PC. Use element access (``result[0] == x``)
with a symbolic rep instead.

All other list operations (incl. iteration and membership) raise
NotImplementedError.
"""

from __future__ import annotations

import typing as t

from .base import SymbolicVar, len_var_name
from .int_ import SymbolicInt

_LIST_STUBS = [
    # Iteration & indexing beyond the rep — contents out of scope by design
    "__setitem__", "__delitem__", "__iter__", "__reversed__",
    # Mutation
    "append", "extend", "insert", "remove", "pop", "clear", "sort", "reverse",
    "__add__", "__iadd__", "__mul__", "__imul__",
    # Copy / conversion
    "copy", "count", "index", "items",
]


def _raise_method(name: str) -> t.Callable[..., t.Any]:
    def _stub(*args: t.Any, **kwargs: t.Any) -> t.Any:
        raise NotImplementedError(
            f"SymbolicList.{name} is not supported (contents out of scope). "
            "Only bool()/length are tracked symbolically."
        )
    _stub.__name__ = name
    return _stub


class SymbolicList(SymbolicVar):
    """Concolic symbolic list: a wrapper around a symbolic length ONLY.

    Attributes:
        _name: Optional symbolic variable name.
        _concrete_length: Concrete seed for the length.
        _len_sym: SymbolicInt for the length; comparisons on it record
                  Z3-queryable PCs.
    """

    def __init__(
        self,
        length: t.Union[int, t.Iterable[t.Any], None] = 0,
        *,
        name: str | None = None,
        note: str | None = None,
        representative: t.Any = None,
    ) -> None:
        # Back-compat: accept an iterable seed and use only its length.
        self._representative: t.Any = representative
        if length is None:
            length = 0
        if not isinstance(length, int):
            length = len(list(length))
        self._name: str | None = name
        self._note: str | None = note
        self._concrete_length: int = length
        len_name = len_var_name(name)
        if len_name:
            from .symbolic_func import register_var
            register_var(name=len_name, sort="Int", value=length, note=note)
        self._len_sym: SymbolicInt = SymbolicInt(length, name=len_name)

    # ── Representative element (Gate 1b) ────────────────────────────────

    @property
    def representative(self) -> t.Any:
        """The single representative element, or None if not set."""
        return self._representative

    # ── Element access (only with a representative; else back-compat raise) ──

    def __getitem__(self, key: t.Any) -> t.Any:
        """`result[0]` returns the rep; anything else raises (single rep row)."""
        if self._representative is not None and key == 0:
            return self._representative
        raise NotImplementedError(
            "SymbolicList only supports index 0 with a representative "
            "(contents out of scope; a single rep row is modeled)."
        )

    def __contains__(self, _other: t.Any) -> bool:
        """``x in result`` is NOT implemented (no Z3 membership PC support).

        Membership/contains has no sound Z3 path-condition recording, so this
        raises loudly instead of silently concretizing. The supported path is
        element access ``result[0]`` which returns the symbolic representative
        whose own ``==`` records a PC.
        """
        raise NotImplementedError(
            "SymbolicList.__contains__ (contains) is not supported: membership "
            "has no Z3 path-condition support. Use element access "
            "(result[0] == x) with a symbolic representative instead."
        )

    # ── Accessors ─────────────────────────────────────────────────────

    @property
    def name(self) -> str | None:
        return self._name

    @property
    def note(self) -> str | None:
        return self._note

    @property
    def concrete_length(self) -> int:
        """Concrete length — for interceptor serialization only."""
        return self._concrete_length

    @property
    def length(self) -> SymbolicInt:
        """The symbolic length; comparisons on it record PCs."""
        return self._len_sym

    # Alias kept for existing callers.
    @property
    def symbolic_len(self) -> SymbolicInt:
        return self._len_sym

    def __len__(self) -> int:
        """Concrete length (Python requires a real int from __len__).

        Not PC-recording. Use ``.length`` (SymbolicInt) in comparisons
        for tracked length constraints.
        """
        return self._concrete_length

    # ── Boolean context (records PC on length) ────────────────────────

    def __bool__(self) -> bool:
        result = self._concrete_length > 0
        len_name = str(self._len_sym)
        expr = f"({len_name} != 0)"
        self._record(expr, "__bool__", taken=result)
        return result

    # ── Representation (not tracked) ──────────────────────────────────

    def __repr__(self) -> str:
        if self._name:
            return f"<SymList {self._name} len={self._concrete_length}>"
        return f"<SymList len={self._concrete_length}>"


# Apply stubs for everything else
for _name in _LIST_STUBS:
    setattr(SymbolicList, _name, _raise_method(_name))


# ── Factory ────────────────────────────────────────────────────────────


def symlist(
    name: str,
    length: t.Union[int, t.Iterable[t.Any], None] = 0,
    note: str | None = None,
    representative: t.Any = None,
) -> SymbolicList:
    """Create a named SymbolicList (symbolic length, optional rep)."""
    return SymbolicList(length, name=name, note=note, representative=representative)
