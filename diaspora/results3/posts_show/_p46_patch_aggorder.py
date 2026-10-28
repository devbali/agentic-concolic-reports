#!/usr/bin/env python3
"""Drop ORDER BY from aggregate notes, the way ActiveRecord drops it.

usage: _p46_patch_aggorder.py <path-to-concolic_targets.rb>

WHY. note_fidelity_audit, ORDER-DIFF (1, and it is RED):

  ActiveRecord::Calculations.sum
     real: SELECT SUM("poll_answers"."vote_count") FROM "poll_answers"
           WHERE "poll_answers"."poll_id" = ?
     note: SELECT SUM("poll_answers"."vote_count") FROM "poll_answers"
           WHERE "poll_answers"."poll_id" = $$(assoc_poll_id) ORDER BY id ASC

Both sides are behaving correctly and they still disagree:

  * the relation GENUINELY carries the ordering -- app/models/poll.rb:8,
    `has_many :poll_answers, -> { order "id ASC" }`, and poll.rb:41 calls
    `poll_answers.sum("vote_count")` on it -- so `sql_for` renders it;
  * ActiveRecord then REMOVES it before issuing the aggregate.
    activerecord-5.2.4.3/lib/active_record/relation/calculations.rb:269-270:

        # PostgreSQL doesn't like ORDER BY when there are no GROUP BY
        relation = unscope(:order).distinct!(false)

    in `execute_simple_calculation`, i.e. the no-GROUP-BY path this mock
    stands for.

So the note describes an ordering the real statement provably never has. This
could be waived -- `note_fidelity_declared` in completion_config.json accepts
`{"match": ..., "verdicts": ["ORDER-DIFF"], "reason": ...}` -- but a waiver is
for shapes the instrument CANNOT express, and this one it can: mirror AR's own
`unscope(:order)` in the note.

Scoped exactly as AR scopes it: only on the aggregate path, and only when the
note carries no LIMIT/OFFSET (AR keeps the ordering on the limit/offset branch
at calculations.rb:267, which builds a count subquery instead). A note that has
no ORDER BY is left byte-identical.

This is a NOTE-ONLY change: it edits the string handed to `symint`, never the
value, so no path condition can move.

SCOPE: batch-local. The canonical reports/diaspora/concolic_targets.rb has the
same gap; promoting it is a Rule T boundary move -- flagged, not taken.
"""
import sys

ANCHOR = '''        rescue StandardError
          nil # projection rewrite must never crash the mock
        end
        symint(vn, seed_for(vn, m == :count ? 1 : 0), note: note)'''

REPLACEMENT = '''          # 2026-09-25, note_fidelity ORDER-DIFF: AR strips the ordering
          # before issuing a simple (no GROUP BY) aggregate --
          # activerecord-5.2.4.3 relation/calculations.rb:269-270,
          #   # PostgreSQL doesn't like ORDER BY when there are no GROUP BY
          #   relation = unscope(:order).distinct!(false)
          # -- but `sql_for` renders the relation as the app scoped it, and
          # `Poll has_many :poll_answers, -> { order "id ASC" }`
          # (app/models/poll.rb:8) genuinely carries one. The note therefore
          # described an ordering the real statement provably never has.
          # Mirror AR: drop it, but ONLY on the no-LIMIT/OFFSET path, because
          # AR keeps the ordering on the limit/offset branch (:267, which
          # builds a count subquery instead). Note-only: the value is
          # untouched, so no path condition can move.
          note = note.sub(/\\s+ORDER\\s+BY\\s+.*\\z/mi, "") unless note =~ /\\b(LIMIT|OFFSET)\\b/i
        rescue StandardError
          nil # projection rewrite must never crash the mock
        end
        symint(vn, seed_for(vn, m == :count ? 1 : 0), note: note)'''


def main() -> int:
    path = sys.argv[1]
    s = open(path).read()
    if 'note_fidelity ORDER-DIFF: AR strips the ordering' in s:
        print(f'{path}: already patched')
        return 0
    if s.count(ANCHOR) != 1:
        print(f'{path}: aggregate-mock anchor not found exactly once '
              f'({s.count(ANCHOR)})', file=sys.stderr)
        return 1
    open(path, 'w').write(s.replace(ANCHOR, REPLACEMENT))
    print(f'{path}: aggregate notes no longer carry a stripped ORDER BY')
    return 0


if __name__ == '__main__':
    sys.exit(main())
