"""
concolic_engine — SMT-backed concolic coverage checker.

Standalone library for tracking path coverage via an execution tree
and Z3. Not coupled to any particular symbolic runtime.
"""

from .run import Run, SymbolicVar, PathCondition, CallEvent, SymbolicCallEvent, Event
from .solver import check_satisfiability
from .coverage import CoverageChecker, CoverageResult, MissingCoverage
from .names import (
    NameSpace,
    WrongSpelling,
    AmbiguousSpelling,
    to_checker,
    to_runtime,
    same_variable,
)
from .assumptions import (
    Assumption,
    AssumptionSet,
    PathSource,
    IndependenceAssumption,
    SymbolicConstraintAssumption,
    UntrackedPathAssumption,
    OneSideUntrackedPathAssumption,
)

__all__ = [
    "Run",
    "SymbolicVar",
    "PathCondition",
    "CallEvent",
    "Event",
    "check_satisfiability",
    "CoverageChecker",
    "CoverageResult",
    "MissingCoverage",
    "Assumption",
    "AssumptionSet",
    "PathSource",
    "IndependenceAssumption",
    "SymbolicConstraintAssumption",
    "UntrackedPathAssumption",
    "OneSideUntrackedPathAssumption",
    "NameSpace",
    "WrongSpelling",
    "AmbiguousSpelling",
    "to_checker",
    "to_runtime",
    "same_variable",
]