"""Tests for assoc_fold.py (Lever 1, round 2, variant_d).

These live HERE, not under src/queries_from_runs/, because assoc_fold.py
itself is a variant-local module (see its docstring for why: this
experiment's own MOCK_RULE_EXPERIMENT.md forbids touching src/). Run with:

    PYTHONPATH=src:reports/diaspora/results3/_experiment/variant_d \
        venvs/queries_from_runs/bin/python -m pytest \
        reports/diaspora/results3/_experiment/variant_d/test_assoc_fold.py -q

The task asked for ">=2 new tests covering the assoc-fold" in
src/queries_from_runs/test_queries_from_runs.py; since that file is under
src/ (out of scope, see assoc_fold.py's docstring), the equivalent
coverage is provided here instead, against the SAME real dump fixtures
this batch already has on disk (no synthetic-only fixtures needed for the
core cases — the real corpus already exhibits both a single-level and a
two-level (nested) assoc chain).
"""
from __future__ import annotations

import json
import os

# App-specific input for src/queries_from_runs (E12, 2026-09-11): the
# package is app-agnostic and REQUIRES an app config (schema, FKs,
# principal/identity conventions, symbol-name shapes, inflections).
# Set before ANY queries_from_runs import that reads it at module level.
os.environ.setdefault("QFR_APP_CONFIG",
                      "/home/dev/project/reports/diaspora/queries_config/app.json")

from concolic_engine.run import Run
from queries_from_runs.transform import RunTransformer

from assoc_fold import AssocFoldingTransformer, install

install()

_HERE = os.path.dirname(os.path.abspath(__file__))
_DUMP_0001 = os.path.join(_HERE, "dump_plain_dse0001.json")


def _load(path):
    with open(path) as f:
        return Run.from_dict(json.load(f))


def test_baseline_has_assoc_placeholders():
    """Sanity check on the fixture itself: confirm the UNPATCHED base
    RunTransformer really does leave assoc_* placeholders on dump0001 --
    if this stops being true (e.g. the fixture is replaced), the "after"
    test below would trivially pass for the wrong reason."""
    run = _load(_DUMP_0001)
    rt = RunTransformer(run)
    rq = rt.transform_all()
    assert rq.errors == []
    all_placeholders = {p for q in rq.queries for p in q.placeholders}
    assert "assoc_target_author_id" in all_placeholders
    assert "assoc_author_id" in all_placeholders
    assert "assoc_target_id" in all_placeholders


def test_assoc_fold_resolves_nested_and_shared_chain():
    """The AssocFoldingTransformer folds all three assoc placeholders from
    the baseline test above into real joins on the same dump, with no
    unparsed/errored producers, AND recovers the correct FK relationship:
    people.id = posts.author_id (assoc_target_author_id was posts.author_id;
    the join must connect through the posts row, not just drop the
    predicate)."""
    run = _load(_DUMP_0001)
    rt = AssocFoldingTransformer(run)
    rq = rt.transform_all()
    assert rq.errors == []

    all_placeholders = {p for q in rq.queries for p in q.placeholders}
    assert "assoc_target_author_id" not in all_placeholders
    assert "assoc_author_id" not in all_placeholders
    assert "assoc_target_id" not in all_placeholders

    by_name = {q.result_name: q for q in rq.queries}
    author_lookup = by_name["SYM_RESULT_ActiveRecord__Associations__SingularAssociation_find_target_3"]
    assert author_lookup.placeholders == ()
    assert "`people`.`id` = `posts`.`author_id`" in author_lookup.sql
    # the nested nothing-left-unresolved case: profiles keyed off the
    # author's people row keyed off the post row keyed off notifications --
    # a THREE-level chain (assoc_author_id -> assoc_target_author_id ->
    # SYM_RESULT_..._row_target_id), all folded, no placeholders anywhere.
    profile_lookup = by_name["SYM_RESULT_ActiveRecord__Associations__SingularAssociation_find_target_4"]
    assert profile_lookup.placeholders == ()
    assert "`profiles`.`person_id` = `people`.`id`" in profile_lookup.sql
    assert "`people`.`id` = `posts`.`author_id`" in profile_lookup.sql


def test_shared_note_produces_single_join_not_duplicated():
    """Multiple assoc_author_* attribute vars (id, guid, persisted, ...)
    share ONE note (the same find_target SELECT on people) -- they must
    fold to the SAME join, not one join per attribute. Regression guard
    for the note-grouping in _register_assoc_producers: if grouping broke
    and instead keyed per-var-name, a query referencing two assoc_author_*
    binds would double-join `people`."""
    run = _load(_DUMP_0001)
    rt = AssocFoldingTransformer(run)
    # Every var in the "assoc_author_*" family must resolve to the SAME
    # producer key once registered (that's what "one join" means here).
    author_attr_names = [
        sv.name
        for sv in run.symbolic_vars
        if sv.name.startswith("assoc_author_")
    ]
    assert len(author_attr_names) >= 3, "fixture should have several sibling attrs"
    keys = {rt.assoc_bind_map[n][0] for n in author_attr_names if n in rt.assoc_bind_map}
    assert len(keys) == 1, f"sibling assoc_author_* vars should share one producer, got {keys}"


def test_unrecoverable_assoc_bind_stays_an_honest_placeholder():
    """A bind with no schema-column-matching suffix (e.g. a Ruby-side
    derived attribute like `_year` that isn't a DB column) must NOT be
    fabricated into a fake join -- it must remain exactly the placeholder
    the base transformer already produces."""
    run = _load(_DUMP_0001)
    derived = [sv for sv in run.symbolic_vars if sv.name.endswith("_created_at_year")]
    assert derived, "fixture should contain a derived (non-column) assoc attribute"
    rt = AssocFoldingTransformer(run)
    for sv in derived:
        assert sv.name not in rt.assoc_bind_map, (
            f"{sv.name} has no real schema column and must stay unresolved"
        )
