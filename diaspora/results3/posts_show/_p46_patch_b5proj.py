#!/usr/bin/env python3
"""B-5, PROJECTION HALF ONLY: make Calculations#ids note its real projection.

usage: _p46_patch_b5proj.py <path-to-targets.rb>

WHY. Real:  SELECT "mentions"."id" FROM "mentions" WHERE ...
     Note:  SELECT "mentions".*    FROM "mentions" WHERE ...
`mock_note_check.matches()` (mock_note_check.py:225-227) requires the NOTE's
projection to be a SUPERSET of the real one, and `normalize_sqlglot` maps
`"mentions".*` to {"*"} and `"mentions"."id"` to {"mentions.id"}; {"*"} is not
>= {"mentions.id"}, so the shape is RED. note_fidelity scores it STAR-OVER,
also RED. After this patch the note's projection is {"mentions.id"}, the
tables are equal, and the note's predicates are a superset of the real ones --
all three conditions hold, both checks go green for this shape.

WHAT THIS DELIBERATELY DOES *NOT* DO -- the rename.
The canonical mock (reports/diaspora/concolic_targets.rb:699-722) also renames
the list from `<name>_ids` to `<name>_<pk>`, i.e.
    SYM_RESULT_ActiveRecord__Calculations_ids_1_ids  ->  ..._ids_1_id
(and its length var with it; the REPRESENTATIVE is already `..._ids_1_id` in
both, so only the list and its length move). That half is separable -- the
canonical `pk` block feeds both, but one-directionally -- and it is NOT needed
for either check. Measured reasons to hold it back:

  * Zero precedent. Five endpoints carry the canonical mock, but grepping the
    first 400 dumps of each shows `Calculations_ids` in 0 of them -- none has
    ever exercised it. posts_show is the only endpoint that reaches it, so the
    rename has never actually been run anywhere.
  * It silently breaks eight batch-local analysis scripts whose regexes are
    suffix-anchored on `_ids`: _p29_construct.py:36 (load-bearing -- it PARSES
    the length gate to build construction targets, and a non-match drops the
    gate), _p23_index.py:67-72, _p15_explain.py:88, _p16_remaining.py:21,
    _p23_gaps.py:39, _p15_classify.py:30, _p29_perkey.py:55,
    _p29_witness_class.py:13.
  * It is a name-boundary change, and names are baked into the corpus, so it
    is only cheap AT a regeneration -- which is exactly why it is being
    surfaced as a decision rather than taken silently.

What the rename would buy is NOT completion: per
docs/BOUNDARY_NOTE_GAPS_20260915.md:261-271 it closes a DOWNSTREAM defect --
`ids` is not a column, so queries_from_runs' `<producer>_<column>` bind
recursion cannot resolve `$$(..._1_ids)` and ships a placeholder (72 notes /
150 dumps). That matters for the extraction/benchmark phase, not for the
checker's verdict.
"""
import sys

ANCHOR = '''    interceptor.declare_target(calc, :ids, returns: lambda do |receiver, args, name|
      vn  = "#{name}_ids"
      sql = ct.sql_for(receiver, args)
      rv  = "#{name}_id"'''

REPLACEMENT = '''    interceptor.declare_target(calc, :ids, returns: lambda do |receiver, args, name|
      vn  = "#{name}_ids"
      sql = ct.sql_for(receiver, args)
      # B-5 (projection half), 2026-09-25: `.ids` selects the PRIMARY KEY, not
      # the row. `sql_for` renders the relation, so the note said
      # `SELECT "mentions".* FROM ...` while the real statement is
      # `SELECT "mentions"."id" FROM ...`; mock_note_check requires the note's
      # projection to be a superset of the real one and {"*"} is not a superset
      # of {"mentions.id"}, so the shape was unmatchable (RED), and
      # note_fidelity scored it STAR-OVER. Rewrite the projection the same way
      # the `exists?` mock rewrites its own (concolic_targets.rb:595-602).
      # Never let the rewrite crash the mock.
      begin
        _pk = begin
          _k = ct.model_class(receiver)
          (_k.respond_to?(:primary_key) && _k.primary_key) || "id"
        rescue StandardError
          "id"
        end
        _tbl = (receiver.respond_to?(:table_name) && receiver.table_name) ||
               (receiver.respond_to?(:klass) && receiver.klass.table_name)
        _proj = _tbl ? %("#{_tbl}"."#{_pk}") : %("#{_pk}")
        sql = sql.sub(/\\ASELECT\\s+(DISTINCT\\s+)?.*?\\s+FROM /m, "SELECT #{_proj} FROM ")
      rescue StandardError
        nil
      end
      rv  = "#{name}_id"'''


def main() -> int:
    path = sys.argv[1]
    s = open(path).read()
    if 'B-5 (projection half)' in s:
        print(f'{path}: already patched')
        return 0
    if s.count(ANCHOR) != 1:
        print(f'{path}: Calculations#ids anchor not found exactly once '
              f'({s.count(ANCHOR)})', file=sys.stderr)
        return 1
    open(path, 'w').write(s.replace(ANCHOR, REPLACEMENT))
    print(f'{path}: Calculations#ids note now projects the primary key')
    return 0


if __name__ == '__main__':
    sys.exit(main())
