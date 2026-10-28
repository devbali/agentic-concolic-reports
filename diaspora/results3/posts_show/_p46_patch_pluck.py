#!/usr/bin/env python3
"""Stop posts_show's `_descend` filter from killing the `pluck` target.

usage: _p46_patch_pluck.py <path-to-concolic_targets.rb>

WHY (measured 2026-09-25). `mock_note_check` reports, unconditionally RED and
with no waiver hook anywhere in the checker:

    -- statements OUTSIDE any target frame (2) -- each needs a declared target
       or a waiver (evidence minted nowhere):
         SELECT "mentions"."id" FROM "mentions" INNER JOIN comments ON
         mentions.mentions_container_id = comments.id AND ...

That statement is `PostService#mark_mention_notifications_read` doing
    mention_ids.concat(mentions_in_comments_for_post(post_id).pluck(:id))
(targets.rb:130-137). `mark_user_notifications` is DESCENDED on purpose -- the
batch wants the app's real method to run -- but `:pluck` is in the SAME
`_descend` list (concolic_targets.rb:483-486), and that list is applied by
overriding `declare_target` itself. So posts_show's OWN `Calculations#pluck`
mock (targets.rb:704-709, complete with a `pluck_rep` representative) is
declared and then silently discarded, real `pluck` runs, and the statement is
issued with no interceptor frame and no note.

WHY THIS CHANGES NO PATH CONDITION -- the argument that makes it safe:
`mention_ids` is an `IterableSymbolicList` (from the `.ids` mock), and that
class defines

    def concat(*_others)
      self
    end                                   # targets.rb:142-144

so the value `pluck` returns is DISCARDED at its only call site. Declaring the
target therefore only mints the missing evidence (an in-frame symbolic_call
carrying the rendered SQL); it cannot move a branch. The accompanying
differential must show identical path conditions -- if it does not, this
assumption is wrong at some OTHER pluck call site and the patch must be
reverted rather than argued around.

SCOPE. `_descend` is BATCH-LOCAL (it exists only in posts_show's and
people_stream's copies, not in reports/diaspora/concolic_targets.rb), so this
is not a Rule T boundary move. people_stream keeps `:pluck` in its own list and
is unaffected.
"""
import sys

ANCHOR = '''    _descend = %i[default_render pluck blocked_people
                  render render_to_string render_to_body
                  people_from_string build_mentioned_people_json
                  mark_user_notifications]'''

REPLACEMENT = '''    # 2026-09-25: `pluck` REMOVED from this list. It was killing this batch's
    # own Calculations#pluck mock (targets.rb:704-709), so
    # `mentions_in_comments_for_post(post_id).pluck(:id)` inside the
    # (deliberately descended) mark_user_notifications ran for real and issued
    # `SELECT "mentions"."id" FROM "mentions" INNER JOIN comments ON ...` with
    # no frame and no note -- mock_note_check's unwaivable "statements OUTSIDE
    # any target frame" RED. Safe because its only call site immediately
    # discards the result: `mention_ids.concat(...)` and
    # IterableSymbolicList#concat returns self unchanged (targets.rb:142-144).
    _descend = %i[default_render blocked_people
                  render render_to_string render_to_body
                  people_from_string build_mentioned_people_json
                  mark_user_notifications]'''


def main() -> int:
    path = sys.argv[1]
    s = open(path).read()
    if '2026-09-25: `pluck` REMOVED from this list' in s:
        print(f'{path}: already patched')
        return 0
    if s.count(ANCHOR) != 1:
        print(f'{path}: _descend anchor not found exactly once '
              f'({s.count(ANCHOR)})', file=sys.stderr)
        return 1
    open(path, 'w').write(s.replace(ANCHOR, REPLACEMENT))
    print(f'{path}: pluck removed from _descend')
    return 0


if __name__ == '__main__':
    sys.exit(main())
