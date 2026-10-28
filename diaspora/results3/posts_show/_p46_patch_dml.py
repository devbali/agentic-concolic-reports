#!/usr/bin/env python3
"""Apply the posts_show-local relation-DML note fix to a concolic_targets.rb.

usage: _p46_patch_dml.py <path-to-concolic_targets.rb>

WHY (measured 2026-09-25). `mock_note_check` reports
    NOTE-MISMATCH ActiveRecord::Relation.update_all  <-- RED
    real: UPDATE "notifications" SET "unread" = 'f' WHERE "notifications"."recipient_id" = ? AND ...
because the mock (DESIGN #7, concolic_targets.rb:722-727) renders its note with
`sql_for(receiver, args)`, which renders the RELATION -- a SELECT. All four
`Relation.update_all` notes in the corpus are `SELECT "notifications".* ...`.
mock_note_check normalises the real UPDATE through a regex that finds no FROM
(tables == set()), so a SELECT note whose tables are {notifications} can never
match it; and the judge's `_is_dml` filter drops a SELECT note, so the write is
not witnessable either.

SCOPE. This patches posts_show's BATCH-LOCAL copy only. The canonical
reports/diaspora/concolic_targets.rb carries the same defect at its own
DESIGN #7 block, but promoting this fix there is a Rule T boundary move that
would need every closed endpoint re-validated -- flagged, not taken.

The template is the file's own `dml_update_note` (concolic_targets.rb:186-204),
written for instance-level update_column(s). The relation-level analogue takes
its predicate from the relation instead: render the relation, keep everything
from WHERE on, and swap the SELECT head for the DML head.
"""
import sys

ANCHOR = '''    %i[update_all delete_all].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        symint("#{name}_#{m}_count", 1, note: sql_for(receiver, args))
      end)
    end'''

REPLACEMENT = '''    %i[update_all delete_all].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        symint("#{name}_#{m}_count", 1, note: relation_dml_note(m, receiver, args))
      end)
    end'''

HELPER_ANCHOR = '''  def render_arg_value(v)'''

HELPER = '''  # posts_show-local, 2026-09-25: relation-level DML must render AS DML.
  #
  # `sql_for` renders the RELATION -- `SELECT "t".* FROM "t" WHERE ...` -- so
  # every `update_all` / `delete_all` note in the corpus came out a SELECT and
  # mock_note_check could never match it against the real
  # `UPDATE "notifications" SET "unread" = 'f' WHERE ...` (its normaliser finds
  # no FROM in an UPDATE, so tables == set(), which never equals {notifications}).
  # The judge's `_is_dml` filter drops a SELECT note too, so the write was not
  # witnessable either.
  #
  # Same shape as `dml_update_note` above (instance-level update_column(s)),
  # but the predicate comes from the relation: render the relation with
  # `render_relation_sql` (so symbolic binds still show as $$(SYMNAME)), keep
  # everything from WHERE onwards, and swap the SELECT head for the DML head.
  def relation_dml_note(op, receiver, args)
    table = if receiver.respond_to?(:klass) && receiver.klass.respond_to?(:table_name)
              receiver.klass.table_name
            elsif receiver.class.respond_to?(:table_name)
              receiver.class.table_name
            else
              receiver.class.name
            end
    tail = render_relation_sql(receiver)[/\\s(WHERE\\s.*)\\z/m, 1]
    where = tail ? " #{tail}" : ""
    return %(DELETE FROM "#{table}"#{where}) if op == :delete_all

    # AR 5.2 Relation#update_all(updates) -- the interceptor keys call_args by
    # the ORIGINAL method's parameter name, so the hash arrives under
    # "updates". Accept the symbol and a lone positional as well, since a
    # silent miss here would put "(unknown columns)" in the note and the
    # mismatch would look like an app change rather than a plumbing miss.
    updates = nil
    if args.is_a?(Hash)
      updates = args["updates"] || args[:updates]
      updates ||= args.values.first if args.size == 1
    end
    sets = if updates.is_a?(Hash) && !updates.empty?
             updates.map { |k, v| %("#{table}"."#{k}" = #{render_arg_value(v)}) }.join(", ")
           else
             "(unknown columns)"
           end
    %(UPDATE "#{table}" SET #{sets}#{where})
  rescue Exception => e # rubocop:disable Lint/RescueException
    # Never wall the mock (same contract as sql_for:163-171). The marker text
    # is deliberately distinctive so a B-4-style silent degradation is
    # greppable in the corpus rather than looking like a legitimate note.
    "#{op} note render FAILED: #{e.class}#{e.message[0, 60]}"
  end

  def render_arg_value(v)'''


def main() -> int:
    path = sys.argv[1]
    s = open(path).read()
    if 'def relation_dml_note' in s:
        print(f'{path}: already patched')
        return 0
    if s.count(ANCHOR) != 1:
        print(f'{path}: DESIGN #7 anchor not found exactly once '
              f'({s.count(ANCHOR)})', file=sys.stderr)
        return 1
    if s.count(HELPER_ANCHOR) != 1:
        print(f'{path}: render_arg_value anchor not found exactly once '
              f'({s.count(HELPER_ANCHOR)})', file=sys.stderr)
        return 1
    s = s.replace(ANCHOR, REPLACEMENT).replace(HELPER_ANCHOR, HELPER)
    open(path, 'w').write(s)
    print(f'{path}: relation_dml_note applied')
    return 0


if __name__ == '__main__':
    sys.exit(main())
