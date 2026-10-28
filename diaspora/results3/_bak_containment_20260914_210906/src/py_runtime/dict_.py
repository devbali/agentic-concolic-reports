"""
SymbolicDict — a symbolic wrapper around Python dict for concolic testing.

Only len() and bool() are tracked symbolically. Everything else raises
NotImplementedError. This is sufficient for the common pattern::

    if result:       # bool() → records (len(result) != 0)
    if not result:   # bool() → records (len(result) == 0)

Key access (result["key"]), iteration, and mutation are not tracked.
"""

from __future__ import annotations

import typing as t

from .base import SymbolicVar, len_var_name
from .int_ import SymbolicInt

_DICT_STUBS = [
    "__getitem__", "__setitem__", "__delitem__", "__iter__", "__reversed__",
    "__contains__",  # "key in d"
    "keys", "values", "items",
    "get", "pop", "popitem", "setdefault", "update", "clear", "copy",
    "fromkeys",
    # Output format — NOT __repr__/__str__/__format__ (those are defined)
]


def _raise_method(name: str) -> t.Callable[..., t.Any]:
    def _stub(*args: t.Any, **kwargs: t.Any) -> t.Any:
        raise NotImplementedError(
            f"SymbolicDict.{name} is not supported in the concolic runtime. "
            "Only len() and bool() are tracked symbolically."
        )
    _stub.__name__ = name
    return _stub


class SymbolicDict(SymbolicVar):
    """Concolic symbolic dict wrapper.

    Tracks only ``len()`` and ``bool()``.  ``bool()`` records a PC on
    the length, so ``if result:`` and ``if not result:`` produce path
    conditions like ``(len(SYM_RESULT_X) != 0)`` which Z3 can solve.

    Attributes:
        _name: Optional symbolic variable name.
        _items: The concrete Python dict payload (not tracked symbolically).
        _len_sym: A SymbolicInt whose value equals len(self._items). The
                  int ``len()`` property returns this SymbolicInt, so
                  comparisons on length create Z3-queryable PCs.
    """

    def __init__(
        self,
        items: t.Optional[t.Dict[str, t.Any]] = None,
        *,
        name: str | None = None,
    ) -> None:
        self._name: str | None = name
        self._items: t.Dict[str, t.Any] = dict(items) if items is not None else {}
        len_name = len_var_name(name)
        if len_name:
            # Register the length var so dumps declare it — otherwise
            # (SYM_LEN_X != 0) PCs reference an undeclared var and the
            # engine's Z3 eval fails with "name not defined".
            from .symbolic_func import register_var
            register_var(name=len_name, sort="Int", value=len(self._items))
        self._len_sym: SymbolicInt = SymbolicInt(
            len(self._items),
            name=len_name,
        )

    # ── Name ──────────────────────────────────────────────────────────

    @property
    def name(self) -> str | None:
        return self._name

    # ── Length (symbolically tracked) ─────────────────────────────────

    def __len__(self) -> int:
        """Return the concrete length.

        The len itself is not recorded as a PC — only comparisons
        on ``self._len_sym`` (e.g. in ``__bool__``) create PCs.
        """
        return len(self._items)

    @property
    def symbolic_len(self) -> SymbolicInt:
        """The symbolic length variable for Z3 queries."""
        return self._len_sym

    # ── Boolean context (records PC on length) ────────────────────────

    def __bool__(self) -> bool:
        """Record PC for bool conversion (if result: / if not result:).

        Records ``(len(X) != 0)`` or ``(len(X) == 0)`` depending on
        whether the dict is empty.
        """
        result = len(self._items) > 0
        len_name = str(self._len_sym)
        expr = f"({len_name} != 0)"
        loc = self._caller_frame()
        from .path_condition import PathCondition
        pc = PathCondition(expr=expr, op_name="__bool__", frame=loc, taken=result)
        self._push(pc)
        return result

    # ── Representation (not tracked) ──────────────────────────────

    def __repr__(self) -> str:
        if self._name:
            return f"<SymDict {self._name} = {self._items!r}>"
        return f"<SymDict {self._items!r}>"


# Apply stubs for everything else
for _name in _DICT_STUBS:
    setattr(SymbolicDict, _name, _raise_method(_name))


# ── Factory ────────────────────────────────────────────────────────────


def symdict(name: str, items: t.Optional[t.Dict[str, t.Any]] = None) -> SymbolicDict:
    """Create a named SymbolicDict for concolic testing.

    Args:
        name: Variable name for Z3 and path condition traces.
        items: Optional initial items (concrete, not tracked symbolically).

    Returns:
        A new SymbolicDict with the given name and items.
    """
    return SymbolicDict(items, name=name)