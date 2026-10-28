"""dump_ingest — THE ONE PLACE A DUMP IS TURNED INTO SOMETHING THE CHECKER READS.

WHY THIS MODULE EXISTS
----------------------
Loading a dump means applying up to two renames, and until 2026-09-14 every
batch carried its own copy of both:

  * **LENGTH SPELLING** (`fix_len_names`). The runtimes used to mint a
    container's cardinality variable literally as ``len(X)``. That is a legal
    Z3 symbol (verified: ``Int('len(X)')`` solves) and a legal JSON string,
    but NOT a legal Python identifier -- and `solver.py` transports Z3 terms
    as PYTHON SOURCE which it ``exec``/``eval``s::

        exec  "len(X) = Int('len(X)')"  -> SyntaxError
        eval  "len(X) > 3"              -> NameError: name 'len' is not defined

    so each batch renamed ``len(X)`` -> ``SYM_LEN_X`` at load.
    **The runtimes now mint the solver-legal spelling directly**
    (`ruby_runtime/base.rb`'s `SymbolicVar.len_var_name`,
    `py_runtime/base.py`'s `len_var_name`), so this rename is a NO-OP on any
    dump written after that change. It stays here because ~1.0 M dumps on
    disk predate it, and they must keep loading identically -- forever.

  * **ORDINAL vs CANONICAL** (`canonicalize_ordinals`). Unrelated, and NOT
    going away: an `AliasAssumption` re-identifies a result by WHAT it did
    rather than WHEN it ran. That is an empirical claim about the program,
    many-to-one and per-run, and the assumption gate exists to falsify it.
    See `concolic_engine.names` for the distinction; do not conflate them.

The copies were the defect. A survey on 2026-09-14 found **48 independent
definitions of `fix_len_names`, of which 15 were semantically distinct** --
notably, some rewrote ``concolic_seeds`` keys and some did not, while every
copy's docstring claimed the latter. `canonicalize_ordinals` deliberately
leaves ``concolic_seeds`` alone because THE RUNTIME consumes it; a copy that
renamed seeds anyway produced a half-converted dict (measured: 10.4 % of one
snapshot's keys) that neither the runtime nor the checker reads. Seven
recorded multi-hour failures came out of this family, one of them a FALSE
PASS.

So: **one function, and the invariants are ASSERTED, not documented.**
Documentation demonstrably did not work -- the RUNBOOK had said "convert both
ways" since 2026-09-11 and four agents hit the trap in one night afterwards.

WHAT IS GUARANTEED
------------------
1. ``concolic_seeds`` is NEVER rewritten. It is the RUNTIME's dict, in the
   runtime's own spelling, and it is preserved verbatim under `RAW_SEEDS_KEY`
   as well. `check_invariants` re-asserts this on the way out.
2. A dump whose seeds carry BOTH length spellings is REPORTED, not silently
   used: that is the half-converted state, and no lookup on it can be trusted.
3. The length rename is idempotent and total, so old and new dumps normalise
   to the SAME text -- which is what keeps path signatures comparable across
   a mixed corpus. (Coverage matches paths by string-comparing ``expr``;
   without this, one program path would split into two signatures.)

Design: imports `names` only at module level; `assumptions` is imported
LAZILY inside `canonicalize_ordinals`, which pulls in Z3. NOTE, so nobody
relies on a guarantee that is not there today: `concolic_engine/__init__.py`
imports `run`/`solver`/`coverage`/`assumptions` eagerly, so importing ANY
submodule of this package already drags Z3 in. The lazy import here is
therefore discipline, not yet a saving -- it becomes one if that `__init__`
is ever slimmed. A caller that genuinely must not touch Z3 should import
`concolic_engine.names`' functions by path, or use the length half only after
that `__init__` is fixed.

Reference: ``reports/diaspora/docs/NAME_BOUNDARY_PLAN_20260914.md``.
"""

from __future__ import annotations

import copy
import json
import typing as t

from .names import LEN_RE, SYM_LEN_RE, NameSpace, to_checker

__all__ = [
    "RAW_SEEDS_KEY", "MixedSpelling",
    "fix_len_names", "canonicalize_ordinals", "normalize",
    "load", "check_invariants",
]

#: Key under which `normalize` keeps ``concolic_seeds`` exactly as it was on
#: disk. Same name and meaning as `assumption_checker.RAW_SEEDS_KEY`, so a
#: dump normalised here satisfies `assumption_checker.seeds_as_written`.
RAW_SEEDS_KEY = "_raw_concolic_seeds"

#: Fields in which a variable name can appear. ``concolic_seeds`` is
#: DELIBERATELY absent -- see the module docstring.
_NAME_FIELDS_EVENT = ("expr", "result_name", "note")


class MixedSpelling(ValueError):
    """A dump straddles the name boundary: the same variable appears under
    both length spellings, so no lookup on it can be trusted. Raised by
    `check_invariants` (and by `normalize(strict=True)`)."""


def _rename_in_place(dump: dict, rn: t.Callable[[t.Optional[str]], t.Optional[str]]) -> None:
    """Apply `rn` to every field that can carry a variable name.

    ``concolic_seeds`` is not among them, by design and by test."""
    for sv in dump.get("symbolic_vars") or ():
        if sv.get("name"):
            sv["name"] = rn(sv["name"])
        if sv.get("note"):
            sv["note"] = rn(sv["note"])
    for ev in dump.get("events") or ():
        for k in _NAME_FIELDS_EVENT:
            if ev.get(k):
                ev[k] = rn(ev[k])
    cv = dump.get("concrete_values")
    if isinstance(cv, dict):
        dump["concrete_values"] = {rn(k): v for k, v in cv.items()}
    for sr in dump.get("symbolic_results") or ():
        if sr.get("name"):
            sr["name"] = rn(sr["name"])


def fix_len_names(dump: dict) -> dict:
    """``len(X)`` -> ``SYM_LEN_X`` everywhere a name can appear, IN PLACE.

    A no-op on dumps written by the current runtimes, which mint
    ``SYM_LEN_X`` already. Idempotent. Never touches ``concolic_seeds``.

    Returns the same object it was given (callers historically expected a
    return value; this one does not allocate a second dump, which is what
    OOM-killed the 22 k-dump report in 2026-08-27)."""
    _rename_in_place(dump, to_checker)
    return dump


def canonicalize_ordinals(dump: dict, aliases: t.Sequence[t.Any] = ()) -> t.Dict[str, str]:
    """Ordinal result names -> canonical alias names, IN PLACE.

    Returns the ``{ordinal: canonical}`` map for this dump ({} when nothing
    aliases). ``concolic_seeds`` is left ORDINAL-named: it is what the RUNTIME
    consumes, and the runtime names results by call order and has never heard
    of an alias. `assumption_checker._runtime_key` / `_live_seed_key` map back."""
    if not aliases:
        return {}
    from .assumptions import alias_map_for, renamer   # lazy: pulls in Z3
    evs = [(ev.get("result_name"), ev.get("note"))
           for ev in dump.get("events") or ()
           if ev.get("type") == "symbolic_call"]
    amap = alias_map_for(evs, aliases)
    if amap:
        _rename_in_place(dump, renamer(amap))
    return dict(amap)


def check_invariants(dump: dict, raw_seeds: t.Optional[dict], where: str = "dump") -> None:
    """Assert what the copies kept getting wrong. Raises `MixedSpelling`.

    1. ``concolic_seeds`` was not rewritten -- it still is, byte for byte,
       what was on disk. A rewritten seed dict is read by NOBODY: the runtime
       reads its own spelling and the checker reads `symbolic_vars`.
    2. No variable appears in the seed dict under BOTH length spellings. That
       is the half-converted state; `NameSpace(strict_ambiguity=True)` is the
       general form of the same check."""
    seeds = dump.get("concolic_seeds")
    if raw_seeds is not None and seeds != raw_seeds:
        added = sorted(set(seeds or {}) - set(raw_seeds or {}))
        raise MixedSpelling(
            "%s: concolic_seeds was REWRITTEN by the load path (%d key(s) "
            "differ, e.g. %s). Seeds belong to the RUNTIME and must be left "
            "in the runtime's own spelling -- a rewritten seed key controls "
            "nothing, silently. See dump_ingest's module docstring."
            % (where, len(added), added[:3] or "<removed>"))
    if isinstance(seeds, dict):
        ns = NameSpace(seeds, name="%s concolic_seeds" % where)
        both = [k for k in seeds
                if LEN_RE.search(k) and any(s in seeds for s in ns.siblings(k))]
        if both:
            raise MixedSpelling(
                "%s: concolic_seeds holds the SAME variable under both length "
                "spellings (%s). The dict was built from two stages at once; "
                "no lookup on it can be trusted."
                % (where, ", ".join(sorted(both)[:3])))


def normalize(dump: dict, aliases: t.Sequence[t.Any] = (), *,
              strict: bool = True, where: str = "dump") -> t.Dict[str, str]:
    """Canonicalise ordinals, then length-rename, IN PLACE. Returns the alias map.

    Order matters and is not free to change: the alias map is derived from
    ``symbolic_call`` notes and result names in their RAW form, so
    canonicalisation must run BEFORE any other rename touches them."""
    raw_seeds = copy.deepcopy(dump.get("concolic_seeds") or {})
    amap = canonicalize_ordinals(dump, aliases)
    fix_len_names(dump)
    dump[RAW_SEEDS_KEY] = raw_seeds
    if strict:
        check_invariants(dump, raw_seeds, where)
    return amap


def load(path: str, aliases: t.Sequence[t.Any] = (), *,
         strict: bool = True) -> t.Tuple[dict, t.Dict[str, str]]:
    """``(normalised dump, alias map)`` for the dump at `path`."""
    with open(path) as fh:
        dump = json.load(fh)
    return dump, normalize(dump, aliases, strict=strict, where=path)
