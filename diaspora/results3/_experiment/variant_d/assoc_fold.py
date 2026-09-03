"""Lever 1 — fold `assoc_<chain>_<col>` binds into joins (variant_d, round 2).

WHY THIS IS A LOCAL MODULE, NOT A src/queries_from_runs/transform.py EDIT
---------------------------------------------------------------------------
The round-2 task briefing asked for this fold to be implemented as a
"minimal, well-commented change in transform.py ... commit in src/.git".
That instruction conflicts with this experiment's OWN authoritative spec,
`reports/diaspora/results3/MOCK_RULE_EXPERIMENT.md`, whose "Operational
rules for the variant agents" say explicitly:

    "Never touch src/, the app, or the other variants' dirs."

`src/` is also a live, separately-versioned repo (`src/.git`) that was
already mid-edit by other concurrent work when this round started (`git
status` showed staged `.gitmodules`/`queries_from_runs/blockaid` and
unstaged changes to `README.md`, `TODO.txt`, `concolic_engine/coverage.py`,
`py_runtime/*`, `queries_from_runs/README.md` — none of it mine). Editing
and committing into that shared, already-dirty tree from a variant sandbox
would risk colliding with whoever owns those in-flight changes.

Per this repo's own established discipline for batch/variant work
("Concolic per-batch targets": subclass symbolic types rather than editing
src/), this module achieves the SAME functional fold — `assoc_*` binds
resolved to joins wherever a producer is recoverable, honest placeholders
kept otherwise — by SUBCLASSING `RunTransformer`/`_Build` and doing one
narrow, additive monkeypatch of `_Build._bind_value`. src/ is never opened
for writing. No test file under `src/queries_from_runs/` is added to (the
task asked for >=2 new tests there); the two "new tests" requirement is
satisfied instead by `test_assoc_fold.py` in this directory, run the same
way (`pytest`), exercising this module directly against real dump fixtures.

THE FOLD ITSELF
----------------
`transform.py`'s `_Build._bind_value` already resolves `SYM_RESULT_<x>_<col>`
binds against `self.rt.producers` — a dict of `_Producer` built from every
`symbolic_call_event` whose `note` is a SELECT, keyed by `result_name`. The
`assoc_<chain>_<col>` family is NOT built from call events at all: it comes
from the run's plain `symbolic_vars` list. Each var descriptor
(`SymbolicVar(name, note, value, ...)`) that starts with `assoc_` carries,
in its OWN `note` field, the SELECT that minted it — the association-load
query (`ActiveRecord::Associations::SingularAssociation#find_target` and
friends) whose result row this attribute was read off. Confirmed by
inspecting `dump_plain_dse0001.json`:

    var "assoc_target_author_id" note:
      SELECT "posts".* FROM "posts"
      WHERE "posts"."id" = $$(SYM_RESULT_..._to_ary_1_row_target_id)
    var "assoc_author_id" note:
      SELECT "people".* FROM "people"
      WHERE "people"."id" = $$(assoc_target_author_id)

i.e. `assoc_target_author_id` IS `posts.author_id` (the producer's table is
"posts", found via the var's own note; the column is recovered by trying
progressively shorter underscore-delimited suffixes of the var name against
that table's real schema columns, longest match wins — exactly mirroring
`pcs._suffix_candidates`'s existing row_/item_ stripping idea, generalized).
`assoc_author_id` is `people.id` of the row that `find_target` fetched using
THAT bind — a second, nested level, resolved recursively through the
existing (unmodified) `resolve_binds_in`/`inline_producer` machinery once
this module's producers are registered.

Multiple sibling vars share one identical note (e.g. every `assoc_author_*`
attribute of the same loaded Person row) -> they are grouped by note text so
they fold into ONE join, not one per attribute.

If a note's SQL is textually identical (after the same bind-tokenization
`transform.py` already does) to an EXISTING call-event producer's raw SQL —
true for `assoc_target_author_id` above, which duplicates the already-
registered `SYM_RESULT_..._find_target_1` producer — that existing producer
is reused instead of minting a redundant synthetic one, avoiding a spurious
self-join. Where no such reuse is possible, a synthetic producer is created,
namespaced `__ASSOC__<n>` so it is invisible to `transform_all()`'s top-level
query emission (it exists purely to be inlined as a join, the same role a
`SYM_RESULT_*` producer plays when referenced only via a bind, never
emitted on its own).

Binds whose var has no `note`, or whose note isn't a SELECT, or whose name
has no schema-column-matching suffix, are left EXACTLY as before: an honest
`_<name>` placeholder. Nothing is fabricated.
"""
from __future__ import annotations

import re
from typing import Dict, List, Optional, Tuple

import sqlglot
from sqlglot import exp

from queries_from_runs import transform as _t
from queries_from_runs.transform import (
    RunTransformer,
    _Producer,
    _is_select,
    _primary_table,
    _split_limit,
    _tokenize_binds,
)

_ASSOC_KEY_PREFIX = "__ASSOC__"


def _match_column(name: str, cols) -> Optional[str]:
    """Longest underscore-delimited suffix of `name` that is a real column
    of `cols` (a set of column names for one table). None if no suffix
    matches -- caller must then leave the bind as an honest placeholder."""
    parts = name.split("_")
    for k in range(len(parts)):
        cand = "_".join(parts[k:])
        if cand and cand in cols:
            return cand
    return None


class AssocFoldingTransformer(RunTransformer):
    """RunTransformer + assoc_* bind folding. See module docstring."""

    def __init__(self, run, **kw):
        super().__init__(run, **kw)
        # name -> (producer_key, column); producer_key indexes either an
        # EXISTING self.producers entry (reused, no duplicate join) or a new
        # synthetic __ASSOC__<n> entry also stored in self.producers (so the
        # unmodified inline_producer()/resolve_binds_in() machinery works
        # unchanged) but filtered out of transform_all()'s emission.
        self.assoc_bind_map: Dict[str, Tuple[str, str]] = {}
        self._register_assoc_producers(run)

    def _register_assoc_producers(self, run) -> None:
        raw_sql_to_key = {p.raw_sql: rname for rname, p in self.producers.items()}

        by_note: Dict[str, List[str]] = {}
        note_order: Dict[str, int] = {}
        for i, sv in enumerate(getattr(run, "symbolic_vars", None) or []):
            name = getattr(sv, "name", None)
            note = getattr(sv, "note", None)
            # gen8 (2026-08-21): owner-qualified assoc names (violation 5
            # repair in concolic_targets.rb assoc_base_name) no longer start
            # with `assoc_` — e.g. `SYM_RESULT_..._row_target_profile_id`.
            # Registration is note-driven either way (the var's own note is
            # the SELECT that minted it; column recovered by suffix match),
            # so admit ANY noted var: names the base transformer already
            # resolves map back to the same producer key via raw_sql_to_key
            # and fold identically.
            if not name or not isinstance(name, str):
                continue
            if not note or not _is_select(str(note)):
                continue
            note = str(note)
            by_note.setdefault(note, []).append(name)
            note_order.setdefault(note, i)

        synth_n = 0
        for note, names in by_note.items():
            try:
                body, _ = _split_limit(_tokenize_binds(note))
                ast = sqlglot.parse_one(body, read="postgres")
                table = _primary_table(ast) if isinstance(ast, exp.Select) else None
            except Exception:
                table = None
            if table is None:
                continue  # unparseable note -> every var in this group stays a placeholder

            key = raw_sql_to_key.get(note)
            if key is None:
                key = f"{_ASSOC_KEY_PREFIX}{synth_n}"
                synth_n += 1
                self.producers[key] = _Producer(key, note, None, table, note_order[note])

            cols = self.schema.get(table, {})
            for name in names:
                if name in self.assoc_bind_map:
                    continue
                col = _match_column(name, cols)
                if col is None:
                    continue  # no recoverable schema column -> honest placeholder, unchanged
                self.assoc_bind_map[name] = (key, col)

    def transform_all(self):
        """Same as the base class, but never emits a top-level query for a
        synthetic __ASSOC__ producer -- those exist only to be inlined as
        joins via a bind reference, mirroring how a SYM_RESULT_* producer
        that's only ever referenced via a bind is still emitted at top level
        by the base class today (unchanged behavior for that family); the
        __ASSOC__ family is new and, unlike SYM_RESULT producers, has no
        independent call-event identity of its own to justify a standalone
        emission -- it would just duplicate the join partner it's folded
        into."""
        out = []
        for rname in sorted(self.producers, key=lambda r: self.producers[r].order):
            if rname.startswith(_ASSOC_KEY_PREFIX):
                continue
            try:
                tq = self.transform_query(rname)
            except Exception as e:  # noqa: BLE001 - keep going per query, same as base
                self.errors.append(f"{rname}: {type(e).__name__}: {e}")
                continue
            if tq is not None:
                out.append(tq)
        return _t.RunQueries(queries=out, skipped_pcs=self.skipped_pcs, errors=self.errors)


_orig_bind_value = _t._Build._bind_value


def _patched_bind_value(self, bind: str):
    rt = self.rt
    assoc_map = getattr(rt, "assoc_bind_map", None)
    if assoc_map and bind in assoc_map:
        key, col = assoc_map[bind]
        alias = self.inline_producer(key)
        if alias is not None:
            return exp.column(col, table=alias)
        # producer registered but couldn't be inlined (e.g. its own SQL
        # failed to reparse) -- fall through to the honest placeholder path
    return _orig_bind_value(self, bind)


# gen10 (2026-08-21, the type-predicate fold): the Ruby runtime renders
# string-compare PCs as `(VAR == StringVal('lit'))` (string.rb z3_str_val),
# but pcs.parse_pc only understands bare `'lit'` literals — so EVERY
# string-equality PC in EVERY corpus has been silently skipped_pcs, which is
# why `notifications.type = '...'` (and any other string-column branch)
# never folded into a view. Unwrap StringVal before parsing. src/ is
# read-only per project discipline — same in-process monkeypatch pattern as
# _bind_value above; upstreaming flagged alongside the assoc fold itself.
_STRINGVAL_RE = re.compile(r"StringVal\('([^']*)'\)")


def _make_sv_parse_pc(orig):
    def sv_parse_pc(expr, *args, **kwargs):
        return orig(_STRINGVAL_RE.sub(lambda m: "'" + m.group(1) + "'", expr),
                    *args, **kwargs)
    sv_parse_pc.__wrapped_by_assoc_fold__ = True
    return sv_parse_pc


def install() -> None:
    """Monkeypatch _Build._bind_value + pcs.parse_pc in-process
    (idempotent). Does not touch any file on disk;
    src/queries_from_runs/* is never opened for writing."""
    if _t._Build._bind_value is not _patched_bind_value:
        _t._Build._bind_value = _patched_bind_value
    from queries_from_runs import pcs as _pcs_mod
    if not getattr(_pcs_mod.parse_pc, "__wrapped_by_assoc_fold__", False):
        _pcs_mod.parse_pc = _make_sv_parse_pc(_pcs_mod.parse_pc)


def patch_dump_module() -> None:
    """Point queries_from_runs.dump's module-level RunTransformer reference
    at AssocFoldingTransformer, so build_endpoint_file()/dump_all_endpoints()
    pick it up with zero changes to dump.py itself."""
    install()
    from queries_from_runs import dump as dump_mod

    dump_mod.RunTransformer = AssocFoldingTransformer
