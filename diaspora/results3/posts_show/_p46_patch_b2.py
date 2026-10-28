#!/usr/bin/env python3
"""B-2: make `user.person` mint the `people.owner_id` statement it stands for.

usage: _p46_patch_b2.py <path-to-run_dse.rb>

WHY. `User has_one :person, foreign_key: :owner_id`, so the concrete round
issues `SELECT "people".* FROM "people" WHERE "people"."owner_id" = ? LIMIT ?`.
posts_show replaced the reader with a bare singleton that returns the pinned
symbolic person and issues NOTHING, so that statement has no corpus note
anywhere -- mock_note_check NOTE-MISMATCH under
`ActiveRecord::Associations::SingularAssociation.find_target`, and
note_fidelity PRED-OP-DIFF (its best-matching note is the `people.id`
belongs_to direction instead). Rule D1: a mock may replace execution, never
evidence.

There is NO waiver route. mock_note_check.py implements no exemption list (I
read all 255 lines; `--aliases` and `--dump-list` are its only knobs, and the
"or a waiver" text at :209 is prose that still sets `red = True`), and
DISCIPLINE.md §9 "Rule S -- every shim is RUN; there are no waivers" forbids one
by name. `concrete_aliases.json` cannot help either: aliasing only redirects
WHERE the checker looks for a note, and no `people.owner_id` note exists
anywhere in this corpus to redirect to. It must be minted.

THE FIX is people_show's primary arm (people_show/targets.rb:939-952): fire the
REAL association reader so the already-declared W3 `SingularAssociation#
find_target` target (posts_show/concolic_targets.rb:1066-1105, whose has_one
branch renders exactly this direction at :1090-1093) mints the note under the
same frame the concrete run tags -- then return the PINNED person unchanged.

WHY NOT people_stream's arm. people_stream/targets.rb:445 wraps the same idea
in `@__ps_person_noted ||= (...)`. That memo is correct THERE because
people_stream builds its user fresh per run; posts_show builds `$posts_user`
ONCE at boot (run_dse.rb:137, handed to every run at :206). A boot-lifetime
`||=` would mint the note in the first run of the process and in no other dump
-- a worse gap than the one being closed, and one that looks green on a spot
check. No memo is needed: the W3-memo at concolic_targets.rb:1107-1136 is keyed
per run and resets on the run label.

WHY NOT return the reader's result. That would replace SYM_PERSON_PO with the
W3 mock's `assoc_person` symbol, renaming every SYM_PERSON_PO_* bind
(SYM_PERSON_PO_id alone appears ~1.2e6 times) and voiding app.json's
identity_prefix / non_principal_identity_name vetoes. Non-additive.

PC IMPACT: none expected. The W3 body only renders a string and calls
`symbolic_instance`, which records no path condition; it adds an
`assoc_person_*` symbolic-var family per run. The differential must confirm
this -- if PCs move, this reasoning is wrong and the patch reverts.
"""
import sys

ANCHOR = '''  user.define_singleton_method(:person) { person }'''

REPLACEMENT = '''  # B-2 (docs/BOUNDARY_NOTE_GAPS_20260915.md; people_show/targets.rb:939-952),
  # applied 2026-09-25. `User has_one :person, foreign_key: :owner_id` -- the
  # concrete round issues `SELECT "people".* FROM "people" WHERE
  # "people"."owner_id" = ? LIMIT ?`, and a bare singleton issues nothing, so
  # that statement had NO corpus note (Rule D1: a mock may replace execution,
  # never evidence; and mock_note_check has no waiver hook, DISCIPLINE.md §9).
  # Fire the REAL reader so the declared W3 SingularAssociation#find_target
  # target (concolic_targets.rb:1066) mints the note under the frame the
  # concrete run tags it with, then return the PINNED person so every
  # SYM_PERSON_PO_* bind keeps its identity.
  #
  # Deliberately NO boot-lifetime memo: $posts_user is built once (line 137),
  # unlike people_stream's per-run user, so people_stream's
  # `@__ps_person_noted ||=` (its targets.rb:445) would mint in exactly ONE
  # run per process. The W3-memo (concolic_targets.rb:1107) already makes this
  # fire once per run and resets on the run label.
  #
  # `association(:person).reader` is safe on a symbolic User because
  # symbolic_instance sets @association_cache = {} and disables the cache
  # builder (concolic_targets.rb:393-394) for exactly this path.
  user.define_singleton_method(:person) do
    begin
      association(:person).reader
    rescue StandardError
      nil
    end
    person
  end'''


def main() -> int:
    path = sys.argv[1]
    s = open(path).read()
    if 'B-2 (docs/BOUNDARY_NOTE_GAPS_20260915.md' in s:
        print(f'{path}: already patched')
        return 0
    if s.count(ANCHOR) != 1:
        print(f'{path}: user.person anchor not found exactly once '
              f'({s.count(ANCHOR)})', file=sys.stderr)
        return 1
    open(path, 'w').write(s.replace(ANCHOR, REPLACEMENT))
    print(f'{path}: user.person now fires the real has_one reader')
    return 0


if __name__ == '__main__':
    sys.exit(main())
