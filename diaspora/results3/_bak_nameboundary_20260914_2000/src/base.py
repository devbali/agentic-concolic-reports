"""
SymbolicVar — base class for all symbolic variable types.

Provides:
- Static path condition stack (thread-safe)
- Caller frame detection for source-location tracking
- A uniform _record() method that subclasses call from comparison dunders
"""

from __future__ import annotations

import inspect
import os
import threading
import typing as t

from .path_condition import PathCondition

_SKIP_MODULES: t.Set[str] = {"path_condition", "base", "inspect"}


#: The spelling of a container's cardinality variable. See ``len_var_name``.
LEN_PREFIX = "SYM_LEN_"


def len_var_name(name: t.Optional[str]) -> t.Optional[str]:
    """Cardinality variable name for a container named `name`.

    THE ONE PLACE A LENGTH VARIABLE IS SPELLED (mirrors
    ``ruby_runtime/base.rb``'s ``SymbolicVar.len_var_name``).

    This used to mint ``len(X)`` literally. That is a legal Z3 symbol
    (verified: ``Int('len(X)')`` solves fine) and a legal JSON string, but
    NOT a legal Python identifier -- and ``concolic_engine/solver.py``
    transports Z3 terms as PYTHON SOURCE which it ``exec``/``eval``s::

        exec  "len(X) = Int('len(X)')"  -> SyntaxError: cannot assign to
                                           function call here
        eval  "len(X) > 3"              -> NameError: name 'len' is not defined

    so every batch inserted a ``fix_len_names`` rename (``len(X)`` ->
    ``SYM_LEN_X``) at load time. That second dialect cost the project seven
    recorded multi-hour failures -- one of them a FALSE PASS -- because
    tables built at one stage were queried with names from the other, and
    the miss is SILENT.

    The name is therefore minted in the solver-legal spelling here instead.
    ``len(X)`` was the ONLY non-identifier name either runtime ever produced,
    so this removes the dialect at its source. Readers of OLD dumps still
    convert, via ``concolic_engine.names`` / ``concolic_engine.dump_ingest``.
    Rationale and migration:
    ``reports/diaspora/docs/NAME_BOUNDARY_PLAN_20260914.md``.

    Returns None for an anonymous container -- it has no Z3 identity.
    """
    return f"{LEN_PREFIX}{name}" if name else None


class SymbolicVar:
    """Base class for symbolic variable types.

    Maintains a static path condition stack (SymbolicVar._stack) that
    records every comparison made during execution. The stack is
    retrieved and cleared by the call_interceptor after each run.
    """

    _stack: t.ClassVar[t.List[PathCondition]] = []
    _lock: t.ClassVar[threading.Lock] = threading.Lock()

    # Z3 sort for declaration purposes; scalar subclasses (int/bool/string)
    # set this so a named var can self-register into the current run's
    # symbolic_vars when it records a PC (see _record). Container types
    # leave it None — their length vars register explicitly at creation.
    _z3_sort: t.ClassVar[t.Optional[str]] = None

    # ── Subclass registration ─────────────────────────────────────────

    def __init_subclass__(cls, **kwargs: t.Any) -> None:
        super().__init_subclass__(**kwargs)
        mod = cls.__module__
        _SKIP_MODULES.add(mod.split(".")[-1])

    # ── Stack management ──────────────────────────────────────────────

    @classmethod
    def _push(cls, pc: PathCondition) -> None:
        with cls._lock:
            cls._stack.append(pc)

    @classmethod
    def get_path_conditions(cls) -> t.List[PathCondition]:
        with cls._lock:
            return list(cls._stack)

    @classmethod
    def clear_path_conditions(cls) -> None:
        with cls._lock:
            cls._stack.clear()

    @classmethod
    def save_and_clear(cls) -> t.List[PathCondition]:
        """Snapshot the current path condition stack and reset it."""
        with cls._lock:
            snapshot = list(cls._stack)
            cls._stack.clear()
        return snapshot

    # ── Name ──────────────────────────────────────────────────────────

    @property
    def name(self) -> str | None:
        return self._name

    # ── Source-location helpers ───────────────────────────────────────

    @staticmethod
    def _caller_frame() -> tuple[str, int, str]:
        """Walk the stack to find the frame outside SymbolicVar internals."""
        stack = inspect.stack()
        for frame_info in stack:
            filename = frame_info.filename
            mod_guess = os.path.splitext(os.path.basename(filename))[0]
            if mod_guess not in _SKIP_MODULES and "/py_runtime/" not in filename:
                return (filename, frame_info.lineno, frame_info.function)
        for frame_info in stack[1:]:
            if "/py_runtime/" not in frame_info.filename:
                return (frame_info.filename, frame_info.lineno, frame_info.function)
        return ("<unknown>", 0, "<unknown>")

    def _record(
        self, expr: str, op_name: str, taken: bool
    ) -> None:
        """Record a path condition for a comparison.

        Also ensures the recording variable is registered in the CURRENT
        run's symbolic_vars: the interceptor's per-run reset clears the
        registration table, so a named var constructed before the run
        would otherwise be referenced by its PCs while missing from the
        dump's declarations (the checker then drops those PCs as
        unevaluable). Every declared symbolic var that participates in a
        run belongs in that run's JSON.
        """
        loc = self._caller_frame()
        pc = PathCondition(
            expr=expr,
            op_name=op_name,
            frame=loc,
            taken=taken,
        )
        self._push(pc)
        self._ensure_registered()

    def _ensure_registered(self) -> None:
        name = getattr(self, "_name", None)
        if not name or self._z3_sort is None:
            return
        # Use the base-class accessors: the symbolic subclasses deliberately
        # raise on int()/str() conversion (silent concretization guard).
        if isinstance(self, int):
            value: t.Any = int.__int__(self)
        elif isinstance(self, str):
            value = str.__str__(self)
        else:
            value = getattr(self, "value", None)
        from .symbolic_func import ensure_var_registered

        ensure_var_registered(
            name=name,
            sort=self._z3_sort,
            value=value,
            note=getattr(self, "_note", None),
        )