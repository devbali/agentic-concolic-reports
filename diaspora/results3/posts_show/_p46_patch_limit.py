#!/usr/bin/env python3
"""Make the SingularAssociation#find_target note carry the LIMIT it stands for.

usage: _p46_patch_limit.py <path-to-concolic_targets.rb>

WHY. `note_fidelity_audit` classifies LIMIT-DIFF ("real has a LIMIT, the note
does not") as RED, deliberately -- note_fidelity_audit.py:40-48 records that
the shape normaliser used to wildcard LIMIT away, so "a single-row read noted
as a bulk read ... scored EXACT (comments_index adversary round 4,
2026-08-28)", and the audit now compares it explicitly.

`ActiveRecord::Associations::SingularAssociation#find_target` is a single-row
read BY CONSTRUCTION: AR 5.2 implements it as `scope.take`, i.e.
`limit(1).records.first`, so every real statement it issues ends `LIMIT ?`:

    SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ? LIMIT ?
    SELECT "polls".*    FROM "polls"    WHERE "polls"."status_message_id" = ? LIMIT ?
    SELECT "people".*   FROM "people"   WHERE "people"."id" = ? LIMIT ?
    ... (7 distinct shapes in the posts_show concrete run)

The mock builds its note BY HAND from the reflection (concolic_targets.rb
~1082-1093) and never emitted the LIMIT, so every one of those scored
LIMIT-DIFF. This is a pure note-string repair: the mock already returns exactly
one `symbolic_instance`, so the note now says what the mock actually models.

NOT declarable as an instrument artefact: `note_fidelity_declared`
(completion_config.json) could exempt the verdict, but the honest move is to
render the LIMIT, because the note would otherwise describe a bulk read that
the mock does not perform. A declaration is for cases where the instrument
CANNOT express the real shape; here it can, in eleven characters.

SCOPE: batch-local. The canonical reports/diaspora/concolic_targets.rb has the
same gap; promoting this is a Rule T boundary move -- flagged, not taken.
"""
import sys

ANCHOR = ('                %(SELECT "#{table}".* FROM "#{table}" '
          'WHERE "#{table}"."#{col}" = #{render_arg_value(fk_raw)})')

REPLACEMENT = (
    '                # LIMIT 1: AR 5.2 SingularAssociation#find_target is\n'
    '                # `scope.take` == `limit(1).records.first`, so the real\n'
    '                # statement always ends `LIMIT ?`. Without it every\n'
    '                # find_target shape scored LIMIT-DIFF (RED) in\n'
    '                # note_fidelity_audit -- a single-row read described as a\n'
    '                # bulk one. The mock returns exactly one symbolic_instance,\n'
    '                # so this makes the note say what the mock models.\n'
    '                %(SELECT "#{table}".* FROM "#{table}" '
    'WHERE "#{table}"."#{col}" = #{render_arg_value(fk_raw)} LIMIT 1)')


def main() -> int:
    path = sys.argv[1]
    s = open(path).read()
    if 'so the real\n                # statement always ends `LIMIT ?`' in s:
        print(f'{path}: already patched')
        return 0
    if s.count(ANCHOR) != 1:
        print(f'{path}: find_target note anchor not found exactly once '
              f'({s.count(ANCHOR)})', file=sys.stderr)
        return 1
    open(path, 'w').write(s.replace(ANCHOR, REPLACEMENT))
    print(f'{path}: find_target note now renders LIMIT 1')
    return 0


if __name__ == '__main__':
    sys.exit(main())
