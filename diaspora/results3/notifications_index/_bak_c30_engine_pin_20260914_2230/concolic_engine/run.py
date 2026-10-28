"""
Data model for a single concolic execution run.

A Run captures:
- The symbolic variables declared for the program under test
- The ordered sequence of path conditions (branch decisions)
- Call events interleaved with path conditions
- Symbolic call events (function calls whose return values become symbolic)
- The concrete input values that produced this execution

Runs can be constructed programmatically or deserialized from a JSON
RunDump via Run.from_dict(). The JSON schema is defined by the runtime's
call_interceptor (see py_runtime/call_interceptor.py).
"""

from __future__ import annotations

import dataclasses
import typing as t

from .assumptions import PathSource


@dataclasses.dataclass(frozen=True)
class SymbolicVar:
    """A concolic variable descriptor.

    Attributes:
        name: Variable name, e.g. "x", "s".
        sort: Z3 sort name, e.g. "Int", "String", "BitVec(32)".
        bitwidth: Bit width for BitVec sorts, or None for others.
        low: Optional lower bound.
        high: Optional upper bound.
        note: Optional human-facing context (e.g. the SQL query this var
              stands in for, from the runtime's `note:` kwarg). Dumped and
              carried through from_dict; never part of Z3 names/exprs.
        value: Optional concrete seed value of the var (from the runtime's
              `value:` kwarg). Used by queries_from_runs to instantiate
              $$(SYMNAME) binds; never part of Z3 names/exprs.
    """

    name: str
    sort: str = "Int"
    bitwidth: t.Optional[int] = None
    low: t.Optional[int] = None
    high: t.Optional[int] = None
    note: t.Optional[str] = None
    value: t.Any = None

    def to_dict(self) -> t.Dict[str, t.Any]:
        d: t.Dict[str, t.Any] = {"name": self.name, "sort": self.sort}
        if self.bitwidth is not None:
            d["bitwidth"] = self.bitwidth
        if self.low is not None:
            d["low"] = self.low
        if self.high is not None:
            d["high"] = self.high
        if self.note is not None:
            d["note"] = self.note
        if self.value is not None:
            d["value"] = self.value
        return d

    @staticmethod
    def from_dict(d: t.Dict[str, t.Any]) -> SymbolicVar:
        return SymbolicVar(
            name=d["name"],
            sort=d.get("sort", "Int"),
            bitwidth=d.get("bitwidth"),
            low=d.get("low"),
            high=d.get("high"),
            note=d.get("note"),
            value=d.get("value"),
        )


# ---------------------------------------------------------------------------
# Path condition — a branch decision
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class PathCondition:
    """A branch decision along the execution path.

    Attributes:
        expr: Z3-parseable expression string, e.g. "(x > 10)".
        taken: Whether this branch was taken (True) or not (False).
        source: Structured source location (PathSource).
        idx: Position in the PC sequence (0-based, set by Run).
    """

    expr: str
    taken: bool
    source: t.Union[str, PathSource] = ""
    idx: int = -1

    def __post_init__(self) -> None:
        # Normalize string sources to PathSource for consistency
        if isinstance(self.source, str) and self.source:
            from concolic_engine.assumptions import PathSource as PS

            parts = self.source.split(" in ")
            func = parts[1].rstrip("()") if len(parts) > 1 else ""
            loc_parts = parts[0].rsplit(":", 1)
            file = loc_parts[0]
            lineno = int(loc_parts[1]) if len(loc_parts) > 1 and loc_parts[1].isdigit() else 0
            object.__setattr__(
                self, "source", PS(file=file, lineno=lineno, function=func)
            )

    @property
    def source_location(self) -> str:
        if isinstance(self.source, str):
            return self.source
        return str(self.source)

    def to_z3_constraint(self) -> str:
        return self.expr if self.taken else f"Not({self.expr})"

    def source_key(self) -> t.Tuple[str, int, str]:
        """Return (file, lineno, function) for assumption matching."""
        if isinstance(self.source, str):
            return ("", 0, "")
        return (self.source.file, self.source.lineno, self.source.function)

    def to_dict(self) -> t.Dict[str, t.Any]:
        d: t.Dict[str, t.Any] = {
            "expr": self.expr,
            "taken": self.taken,
        }
        if isinstance(self.source, PathSource):
            d["file"] = self.source.file
            d["lineno"] = self.source.lineno
            d["function"] = self.source.function
        elif self.source:
            d["source_str"] = self.source
        return d

    @staticmethod
    def from_dict(d: t.Dict[str, t.Any]) -> PathCondition:
        source: t.Union[str, PathSource]
        if "file" in d:
            source = PathSource(
                file=d.get("file", ""),
                lineno=d.get("lineno", 0),
                function=d.get("function", ""),
            )
        elif "source_str" in d:
            source = d["source_str"]
        else:
            source = ""
        return PathCondition(
            expr=d["expr"],
            taken=d.get("taken", True),
            source=source,
        )


# ---------------------------------------------------------------------------
# Call event — a target function invocation
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class CallEvent:
    """A call to a target function during execution.

    Unlike PathCondition, CallEvents do not represent a fork in the
    execution. They are markers that indicate "at this point in the
    path, the target was called with these arguments."

    Attributes:
        target_name: Name of the called function, e.g. "vulnerable".
        args: Concrete arguments passed to the function.
        source: Structured source location (PathSource).
        idx: Position in the Run's event sequence (0-based).
    """

    target_name: str
    args: t.Dict[str, t.Any]
    source: t.Union[str, PathSource] = ""
    idx: int = -1

    def to_dict(self) -> t.Dict[str, t.Any]:
        d: t.Dict[str, t.Any] = {
            "type": "call",
            "target_name": self.target_name,
            "args": dict(self.args),
        }
        if isinstance(self.source, PathSource):
            d["file"] = self.source.file
            d["lineno"] = self.source.lineno
            d["function"] = self.source.function
        elif self.source:
            d["source_str"] = self.source
        return d

    @staticmethod
    def from_dict(d: t.Dict[str, t.Any]) -> CallEvent:
        source: t.Union[str, PathSource]
        if "file" in d:
            source = PathSource(
                file=d.get("file", ""),
                lineno=d.get("lineno", 0),
                function=d.get("function", ""),
            )
        elif "source_str" in d:
            source = d["source_str"]
        else:
            source = ""
        return CallEvent(
            target_name=d.get("target_name", d.get("target", "")),
            args=d.get("args", {}),
            source=source,
        )


# ---------------------------------------------------------------------------
# SymbolicCallEvent — a function call whose return value became symbolic
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class SymbolicCallEvent:
    """A call to a function whose return value is treated as symbolic.

    Unlike a regular CallEvent, SymbolicCallEvent indicates that the
    return value of the called function becomes a symbolic variable
    (a SYM_RESULT_* variable). Downstream code that uses this return
    value enters symbolic (path-tracking) mode from that point.

    Attributes:
        target_name: Name of the called function.
        args: Concrete arguments passed to the function.
        result_name: The generated symbolic variable name, e.g.
                     "SYM_RESULT_vulnerable_1".
        result_value: The concrete return value.
        result_sort: Z3 sort of the return value ("Int", "String", etc.).
        source: Structured source location (PathSource).
        note: Optional SQL/context note (the query this query-mock stood in
              for, rendered with $$(SYMNAME) for symbolic binds). Carried
              through from_dict; dump only.
        idx: Position in the Run's event sequence (0-based).
    """

    target_name: str
    args: t.Dict[str, t.Any]
    result_name: str
    result_value: t.Any
    result_sort: str = "Int"
    source: t.Union[str, PathSource] = ""
    note: t.Optional[str] = None
    idx: int = -1

    def to_dict(self) -> t.Dict[str, t.Any]:
        d: t.Dict[str, t.Any] = {
            "type": "symbolic_call",
            "target_name": self.target_name,
            "args": dict(self.args),
            "result_name": self.result_name,
            "result_value": self.result_value,
            "result_sort": self.result_sort,
        }
        if isinstance(self.source, PathSource):
            d["file"] = self.source.file
            d["lineno"] = self.source.lineno
            d["function"] = self.source.function
        elif self.source:
            d["source_str"] = self.source
        if self.note is not None:
            d["note"] = self.note
        return d

    @staticmethod
    def from_dict(d: t.Dict[str, t.Any]) -> SymbolicCallEvent:
        source: t.Union[str, PathSource]
        if "file" in d:
            source = PathSource(
                file=d.get("file", ""),
                lineno=d.get("lineno", 0),
                function=d.get("function", ""),
            )
        elif "source_str" in d:
            source = d["source_str"]
        else:
            source = ""
        return SymbolicCallEvent(
            target_name=d.get("target_name", d.get("target", "")),
            args=d.get("args", {}),
            result_name=d.get("result_name", ""),
            result_value=d.get("result_value"),
            result_sort=d.get("result_sort", "Int"),
            source=source,
            note=d.get("note"),
        )


# ---------------------------------------------------------------------------
# Run — a single execution
# ---------------------------------------------------------------------------

Event = t.Union[PathCondition, CallEvent, SymbolicCallEvent]


@dataclasses.dataclass
class Run:
    """A single concolic execution run.

    Attributes:
        symbolic_vars: The symbolic variables for this run.
        events: Ordered sequence of path conditions and call events.
        concrete_values: Map of var name → concrete input value.
        label: Optional human-readable label.
        symbolic_results: Map of result_name → concrete value for
                          symbolic function return values.
        script: Optional inline Python source code that generated
                this run.  Embedding the script makes each dump
                JSON self-contained — a sub-agent can re-execute
                the run without the original runner context.
    """

    symbolic_vars: t.List[SymbolicVar]
    events: t.List[Event]
    concrete_values: t.Dict[str, t.Any]
    label: t.Optional[str] = None
    symbolic_results: t.Dict[str, t.Any] = dataclasses.field(default_factory=dict)
    script: t.Optional[str] = None
    error: t.Optional[t.Dict[str, t.Any]] = None

    def __post_init__(self) -> None:
        for i, ev in enumerate(self.events):
            object.__setattr__(ev, "idx", i)
        sv_names = {sv.name for sv in self.symbolic_vars}
        cv_names = set(self.concrete_values.keys())
        missing = sv_names - cv_names
        if missing:
            raise ValueError(
                f"Run '{self.label}': concrete_values missing for vars: {missing}"
            )

    # -- convenience accessors -------------------------------------------

    @property
    def path_conditions(self) -> t.List[PathCondition]:
        return [e for e in self.events if isinstance(e, PathCondition)]

    @property
    def call_events(self) -> t.List[CallEvent]:
        return [e for e in self.events if isinstance(e, CallEvent)]

    @property
    def symbolic_call_events(self) -> t.List[SymbolicCallEvent]:
        return [e for e in self.events if isinstance(e, SymbolicCallEvent)]

    def all_symbolic_vars(self) -> t.List[SymbolicVar]:
        """Return all symbolic vars including SYM_RESULT_* vars from calls."""
        result_vars = []
        for e in self.symbolic_call_events:
            result_vars.append(SymbolicVar(
                name=e.result_name,
                sort=e.result_sort,
            ))
        return self.symbolic_vars + result_vars

    def z3_declarations(self) -> t.List[str]:
        lines: t.List[str] = []
        for sv in self.symbolic_vars:
            if sv.sort == "Int":
                lines.append(f"{sv.name} = Int('{sv.name}')")
            elif sv.sort == "String":
                lines.append(f"{sv.name} = String('{sv.name}')")
            elif sv.sort.startswith("BitVec"):
                bw = sv.bitwidth or 32
                lines.append(f"{sv.name} = BitVec('{sv.name}', {bw})")
            elif sv.sort == "Bool":
                lines.append(f"{sv.name} = Bool('{sv.name}')")
            elif sv.sort == "Real":
                lines.append(f"{sv.name} = Real('{sv.name}')")
            else:
                lines.append(f"{sv.name} = {sv.sort}('{sv.name}')")
        # Also declare symbolic function result vars
        for e in self.symbolic_call_events:
            sort = e.result_sort
            if sort == "Int":
                lines.append(f"{e.result_name} = Int('{e.result_name}')")
            elif sort == "String":
                lines.append(f"{e.result_name} = String('{e.result_name}')")
            elif sort == "Bool":
                lines.append(f"{e.result_name} = Bool('{e.result_name}')")
            elif sort == "Real":
                lines.append(f"{e.result_name} = Real('{e.result_name}')")
        return lines

    def short_summary(self) -> str:
        error_suffix = f" ERROR:{self.error['type']}" if self.error else ""
        return (
            f"Run({self.label or '?'}): {len(self.symbolic_vars)} vars, "
            f"{len(self.path_conditions)} branches, "
            f"{len(self.call_events)} calls, "
            f"{len(self.symbolic_call_events)} symbolic calls, "
            f"values={self.concrete_values}{error_suffix})"
        )

    # -- JSON IR ---------------------------------------------------------

    def to_dict(self) -> t.Dict[str, t.Any]:
        """Serialize this Run to a JSON-serializable dict."""
        d: t.Dict[str, t.Any] = {
            "schema_version": "1.0",
            "label": self.label,
            "symbolic_vars": [sv.to_dict() for sv in self.symbolic_vars],
            "concrete_values": dict(self.concrete_values),
            "events": [
                ev.to_dict() if isinstance(ev, (PathCondition, CallEvent, SymbolicCallEvent))
                else {"type": type(ev).__name__, str(ev): True}
                for ev in self.events
            ],
        }
        if self.symbolic_results:
            d["symbolic_results"] = dict(self.symbolic_results)
        if self.script:
            d["script"] = self.script
        if self.error:
            d["error"] = dict(self.error)
        return d

    @staticmethod
    def from_dict(d: t.Dict[str, t.Any]) -> Run:
        """Deserialize a Run from a JSON RunDump dict.

        Accepts both the engine's to_dict() output and the runtime's
        RunDump format (from py_runtime's call_interceptor).
        """
        # Parse symbolic vars — handle both engine and runtime formats
        raw_vars = d.get("symbolic_vars", [])
        symbolic_vars: t.List[SymbolicVar] = []
        concrete_values: t.Dict[str, t.Any] = {}

        for raw in raw_vars:
            if "bitwidth" in raw or "low" in raw or "sort" in raw:
                # Engine format (SymbolicVar)
                sv = SymbolicVar.from_dict(raw)
                symbolic_vars.append(sv)
            else:
                # Runtime format: {"name": "x", "sort": "Int", "value": 5}
                sv = SymbolicVar(
                    name=raw["name"],
                    sort=raw.get("sort", "Int"),
                )
                symbolic_vars.append(sv)
                if "value" in raw:
                    concrete_values[raw["name"]] = raw["value"]

        # If concrete_values provided at top level, use those
        if "concrete_values" in d:
            concrete_values = dict(d["concrete_values"])
        # If neither source had values, something is wrong
        if not concrete_values:
            # Try to extract from symbolic_vars with 'value' key
            for raw in raw_vars:
                if "value" in raw:
                    concrete_values[raw["name"]] = raw["value"]

        # Parse symbolic_results (optional)
        symbolic_results: t.Dict[str, t.Any] = {}
        if "symbolic_results" in d:
            for raw in d["symbolic_results"]:
                if isinstance(raw, dict) and "name" in raw:
                    symbolic_results[raw["name"]] = raw.get("value")

        # Parse events
        raw_events = d.get("events", [])
        events: t.List[Event] = []

        for raw in raw_events:
            ev_type = raw.get("type", "")
            if ev_type == "symbolic_call":
                ce = SymbolicCallEvent.from_dict(raw)
                events.append(ce)
            elif ev_type == "path_condition" or ("expr" in raw and "taken" in raw):
                pc = PathCondition.from_dict(raw)
                events.append(pc)
            elif ev_type == "call":
                ce = CallEvent.from_dict(raw)
                events.append(ce)
            else:
                # Try to determine from keys
                if "expr" in raw:
                    events.append(PathCondition.from_dict(raw))
                elif "target_name" in raw or "target" in raw:
                    events.append(CallEvent.from_dict(raw))

        return Run(
            symbolic_vars=symbolic_vars,
            events=events,
            concrete_values=concrete_values,
            label=d.get("label"),
            symbolic_results=symbolic_results,
            script=d.get("script"),
            error=d.get("error"),
        )


# -- Engine-level helper: load RunDump JSON files -----------------------

import json


def load_run_dump(path: str) -> Run:
    """Load a Run from a JSON file written by any runtime's call_interceptor."""
    with open(path) as f:
        data = json.load(f)
    return Run.from_dict(data)


def load_run_dumps(paths: t.List[str]) -> t.List[Run]:
    """Load multiple RunDump JSON files."""
    return [load_run_dump(p) for p in paths]