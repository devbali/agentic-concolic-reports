#!/usr/bin/env python3
"""B-6 — make `sql_for` render a finder's OWN conditions on the Relation path.

    usage: _p48_patch_b6.py <dir-or-file>          # idempotent

THE DEFECT. posts_show's `sql_for` ignores `args` when the receiver is a
Relation:

    def sql_for(receiver, args)
      if receiver.is_a?(Class) ... end
      render_relation_sql(receiver)        # <-- args dropped

so `likes.find_by(author_id: X)` renders only the `likes` relation and the
condition `find_by` itself supplies never reaches the note. Measured on the v2
corpus: this is the sole remaining `mock_note_check` RED (3 shapes, all
auth-only) and 3 of the 3 remaining `note_fidelity` PRED-OP-DIFFs —

    real: SELECT "likes".* ... AND "likes"."author_id" = ? LIMIT ?
    note: SELECT "likes".* ...                      (no author_id)

from `app/models/post.rb:136-144` and `app/models/poll.rb:36`:

    def like_for(user)    = likes.find_by(author_id: user.person.id)
    def reshare_for(user) = reshares.find_by(author_id: user.person.id)
    def participation_answer(user) = poll_participations.find_by(author_id: ...)

The dropped conjunct is `author_id = <the signed-in user>` — a PRINCIPAL
predicate — so the extracted policy currently claims the endpoint discloses
every like on a post when it discloses only the viewer's own. This is a
soundness defect in the policy, not only a fidelity one.

THIS IS A BACK-PORT, NOT A NEW FIX. comments_index, people_stream,
notifications_index and conversations_index have all carried this repair since
2026-08-21 ("the severed contacts chain"), whose comment describes posts_show's
bug verbatim: "carries its WHERE in ARGS, which the Relation branch never
rendered: the note collapsed to the bare relation SQL". posts_show almost
certainly lost it in the 2026-09-09 Rule-T re-sync — the same event already
known to have silently deleted `ConcreteSymbolicString` here.

SCOPE — DELIBERATELY MINIMAL. Only two things change:

  1. `relation_args_where` is added (ported verbatim from
     people_stream/concolic_targets.rb).
  2. `sql_for`'s Relation path appends it.

NOT ported, on the "minimal changes only" rule: `class_finder_sql` /
`extract_finder_where` / `default_projection` (posts_show renders class-level
finders as a prose string — a real but SEPARATE gap that is not currently RED,
so it does not get folded into a fix being validated for something else), and
the `ConcolicKwargsToPositional` shim. The thread-local fallback inside
`relation_args_where` is kept because it is harmless when nothing sets the
key (it simply returns nil) and removing it would make this a non-verbatim
port for no gain.

WHY THE PRIMARY PATH IS EXPECTED TO SUFFICE HERE. AR 5.2's signature is
`find_by(arg, *args)`, so `find_by(author_id: X)` binds the hash to `arg` and
the interceptor's call_args is `{"arg" => {author_id: X}}` — a non-empty Hash
VALUE, which is exactly what `relation_args_where` scans for. The thread-local
exists for `*rest`-signature finders called with keyword syntax, which is not
this site. Measured by the differential, not assumed.

The patch refuses unless each anchor matches exactly once, and is idempotent.
"""
import os
import sys

ANCHOR_SQLFOR = '''  def sql_for(receiver, args)
    if receiver.is_a?(Class)
      return "#{receiver.name} query (class-level finder), args=#{render_args(args)}"
    end
    render_relation_sql(receiver)
  rescue Exception => e # rubocop:disable Lint/RescueException'''

REPL_SQLFOR = '''  def sql_for(receiver, args)
    if receiver.is_a?(Class)
      return "#{receiver.name} query (class-level finder), args=#{render_args(args)}"
    end
    base = render_relation_sql(receiver)
    # B-6 BACK-PORT, posts_show batch-local, 2026-09-25.
    # Statement-shape fidelity (2026-08-21, the severed contacts chain, ported
    # from people_stream/comments_index/notifications_index/conversations_index
    # which have carried this since then):
    # `relation.find_by(conditions)` -- here `post.likes.find_by(author_id:)`,
    # `post.reshares.find_by(author_id:)` and
    # `poll.poll_participations.find_by(author_id:)`
    # (app/models/post.rb:136-144, app/models/poll.rb:36) -- carries its WHERE
    # in ARGS, which this Relation branch never rendered: the note collapsed to
    # the bare relation SQL and DROPPED the `author_id = <signed-in user>`
    # conjunct. That is a PRINCIPAL predicate, so the extracted policy claimed
    # the endpoint discloses every like on a post rather than only the viewer's
    # own. Measured on v2: the sole remaining mock_note_check RED (3 shapes).
    # Only a non-empty Hash arg qualifies, so records/to_a/pluck calls -- which
    # carry none -- keep their notes byte-identical. No pk fallback: a bare
    # scalar arg on a relation call is not evidence of a WHERE.
    extra = relation_args_where(receiver, args)
    if extra
      base.include?(" WHERE ") ? "#{base} AND #{extra}" : "#{base} WHERE #{extra}"
    else
      base
    end
  rescue Exception => e # rubocop:disable Lint/RescueException'''

ANCHOR_HELPER = '''  # Render args for class-level finders / fallbacks (readable, no inspect noise).
  def render_args(args)'''

REPL_HELPER = '''  # Relation-receiver companion to a class finder's WHERE extraction: render
  # the first non-empty Hash in args as table-qualified conditions, nil
  # otherwise. Deliberately NO primary-key fallback -- a bare scalar arg on a
  # relation call is not evidence of a WHERE.
  # PORTED VERBATIM from people_stream/concolic_targets.rb (B-6, 2026-09-25).
  def relation_args_where(receiver, args)
    return nil unless args.is_a?(Hash)
    table = receiver.respond_to?(:klass) && receiver.klass.respond_to?(:table_name) &&
            receiver.klass.table_name
    return nil unless table
    args.each_value do |v|
      if v.is_a?(Hash) && !v.empty?
        return v.map { |k, vv| %("#{table}"."#{k}" = #{render_arg_value(vv)}) }.join(" AND ")
      end
    end
    # Fallback: the ConcolicKwargsToPositional thread-local used by the sibling
    # batches (the interceptor's param binding drops the re-packed hash for
    # *rest-signature finders called with keyword syntax). posts_show does not
    # install that shim, so this is inert here -- kept so the port stays
    # verbatim and so installing the shim later needs no edit at this site.
    tc = Thread.current[:concolic_finder_conds]
    if tc.is_a?(Hash) && !tc.empty?
      return tc.map { |k, vv| %("#{table}"."#{k}" = #{render_arg_value(vv)}) }.join(" AND ")
    end
    nil
  end

  # Render args for class-level finders / fallbacks (readable, no inspect noise).
  def render_args(args)'''


def patch(path):
    src = open(path).read()

    if 'def relation_args_where' in src and 'extra = relation_args_where' in src:
        print(f'  {path}: already patched (idempotent no-op)')
        return False

    for name, anchor in (('sql_for', ANCHOR_SQLFOR), ('render_args', ANCHOR_HELPER)):
        n = src.count(anchor)
        if n != 1:
            sys.exit(f'REFUSING: {path}: anchor {name!r} matched {n} times (expected 1)')

    src = src.replace(ANCHOR_SQLFOR, REPL_SQLFOR, 1)
    src = src.replace(ANCHOR_HELPER, REPL_HELPER, 1)
    open(path, 'w').write(src)
    print(f'  {path}: PATCHED (relation_args_where added; sql_for folds it)')
    return True


def main():
    t = sys.argv[1] if len(sys.argv) > 1 else '.'
    f = t if os.path.isfile(t) else os.path.join(t, 'concolic_targets.rb')
    if not os.path.exists(f):
        sys.exit(f'no such file: {f}')
    patch(f)


if __name__ == '__main__':
    main()
