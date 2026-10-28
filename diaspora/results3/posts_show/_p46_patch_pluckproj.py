#!/usr/bin/env python3
"""Make Calculations#pluck's note project the plucked columns.

usage: _p46_patch_pluckproj.py <path-to-targets.rb>

WHY, and why only now. `_p46_patch_pluck.py` took `:pluck` out of this batch's
`_descend` deny-list so that
`mentions_in_comments_for_post(post_id).pluck(:id)` stops running for real and
unnoted (mock_note_check's unwaivable "statements OUTSIDE any target frame").
That worked -- 59/59 dumps of the first v2 drive carry a `Calculations.pluck`
frame. But bringing the statement INTO frame means its note is now COMPARED,
and the mock renders the relation via `sql_for`, so it said:

    note: SELECT "mentions".*     FROM "mentions" INNER JOIN comments ON ...
    real: SELECT "mentions"."id"  FROM "mentions" INNER JOIN comments ON ...

`mock_note_check.matches()` needs the NOTE's projection to be a SUPERSET of the
real one, and `{"*"}` is not a superset of `{"mentions.id"}`; note_fidelity
scores the same thing STAR-OVER. So without this the pluck fix would only have
traded an outside-frame RED for a projection RED -- caught by inspecting the
live v2 corpus ten minutes into the drive, rather than after it.

This is the same defect B-5 fixes for `Calculations#ids`, and the same repair:
`.pluck` selects the NAMED COLUMNS, not the row, so rewrite the projection.
Columns already qualified (`"t"."c"`, `t.c`) or containing an expression are
passed through untouched rather than being double-quoted.

NOTE-ONLY: it edits the string handed to the list/representative, never a
value, so no path condition can move.

SCOPE: batch-local (`targets.rb`). The shared file declares `pluck` UNSUPPORTED
rather than mocking it, so there is no canonical version to diverge from.
"""
import sys

ANCHOR = '''    interceptor.declare_target(calc, :pluck, returns: lambda do |receiver, args, name|
      vn  = "#{name}_plucked"
      sql = ct.sql_for(receiver, args)'''

REPLACEMENT = '''    interceptor.declare_target(calc, :pluck, returns: lambda do |receiver, args, name|
      vn  = "#{name}_plucked"
      sql = ct.sql_for(receiver, args)
      # 2026-09-25: `.pluck` selects the NAMED COLUMNS, not the row, but
      # `sql_for` renders the relation -- so the note said
      # `SELECT "mentions".* FROM ...` where the real statement is
      # `SELECT "mentions"."id" FROM ...`. mock_note_check needs the note's
      # projection to be a superset of the real one and {"*"} is not a superset
      # of {"mentions.id"}, so the shape was unmatchable and note_fidelity
      # scored STAR-OVER. Exactly the B-5 defect and repair, one mock over.
      # This became visible only once `pluck` was taken out of `_descend`
      # (_p46_patch_pluck.py): before that the statement was issued with no
      # frame at all, so its note was never compared.
      begin
        _cols = args.is_a?(::Hash) ? args.values.compact.flatten : []
        unless _cols.empty?
          _tbl = (receiver.respond_to?(:table_name) && receiver.table_name) ||
                 (receiver.respond_to?(:klass) && receiver.klass.table_name)
          _proj = _cols.map do |c|
            s = c.to_s
            # already qualified, or an expression -- pass through untouched
            (s.include?(".") || s.include?("(") || s.include?("\\"")) ? s
                                                                     : (_tbl ? %("#{_tbl}"."#{s}") : %("#{s}"))
          end.join(", ")
          sql = sql.sub(/\\ASELECT\\s+(DISTINCT\\s+)?.*?\\s+FROM /m, "SELECT #{_proj} FROM ")
        end
      rescue StandardError
        nil # projection rewrite must never crash the mock
      end'''


def main() -> int:
    path = sys.argv[1]
    s = open(path).read()
    if "`.pluck` selects the NAMED COLUMNS" in s:
        print(f'{path}: already patched')
        return 0
    if s.count(ANCHOR) != 1:
        print(f'{path}: pluck declaration anchor not found exactly once '
              f'({s.count(ANCHOR)})', file=sys.stderr)
        return 1
    open(path, 'w').write(s.replace(ANCHOR, REPLACEMENT))
    print(f'{path}: pluck note now projects the plucked columns')
    return 0


if __name__ == '__main__':
    sys.exit(main())
