#!/usr/bin/env python3
"""B-2 follow-up: make `user.person` mint its statement in EVERY run, not run 1.

usage: _p46_patch_b2reset.py <path-to-run_dse.rb>

WHAT WENT WRONG. `_p46_patch_b2.py` replaced the bare `user.person` singleton
with one that fires the real association reader, so the declared W3
`SingularAssociation#find_target` target would mint
`SELECT "people".* FROM "people" WHERE "people"."owner_id" = ? LIMIT 1`.
Its docstring says, correctly, that no boot-lifetime memo was used --
`$posts_user` is built ONCE (run_dse.rb:137), so a `||=` would fire in the
first run of the process and never again.

The memo was avoided. The CACHE was not. `association(:person)` is itself
cached in the record's `@association_cache`, and once that Association has
loaded its target, `.reader` returns it WITHOUT calling `find_target` again.
On a boot-scoped user that cache never clears between runs, so the effect is
identical to the memo the docstring rules out.

MEASURED on the live v2 corpus (2026-09-25, 87 000 dumps):
  * the `owner_id` note appears in run **1 only**, of `auth_html` and
    `auth_json` -- 2 dumps in 87 000; 0 hits in a 6 000-dump random sample;
  * yet 2 859 of 3 000 dumps carry an `assoc_person` symbolic var, all of them
    the BELONGS_TO direction (`people.id = $$(..._row_person_id)`) from other
    models -- i.e. W3 fires constantly, just never for `user.person`.
It "looked green on a spot check" exactly as the hand-off warned: the 60-dump
cand2 differential passed, because `mock_note_check` only needs the note to
exist SOMEWHERE in the corpus and with 25 runs/scenario the first runs are a
large fraction of a small corpus.

THE FIX. Reset the association before reading it, so `find_target` runs again.
Intra-run duplication is already handled: the W3-memo
(concolic_targets.rb:1200-1211) keys on `[owner.object_id, reflection.name]`
and clears whenever the interceptor's run label changes, so a second read in
the SAME run returns the memoized target without re-entering the interceptor --
one note per run, not one per call.

NOT a PC change: the W3 body only renders a string and calls
`symbolic_instance`, which records no path condition. The differential must
confirm that.
"""
import sys

ANCHOR = '''  user.define_singleton_method(:person) do
    begin
      association(:person).reader
    rescue StandardError
      nil
    end
    person
  end'''

REPLACEMENT = '''  user.define_singleton_method(:person) do
    begin
      # `reset` BEFORE `reader`, 2026-09-25. Firing the reader alone minted the
      # note in the FIRST run of the process and no other: `association(:person)`
      # is cached in @association_cache, and once loaded, `.reader` returns the
      # target without re-entering `find_target`. $posts_user is built once at
      # boot (line 137), so that cache never clears between runs -- the same
      # first-run-only failure a `||=` memo would have caused, via AR's cache
      # instead of ours. Measured before the fix: the owner_id note appeared in
      # run 1 of auth_html and auth_json only, 2 dumps in 87 000.
      #
      # Intra-run duplication is already prevented by the W3-memo
      # (concolic_targets.rb:1200-1211), which keys on
      # [owner.object_id, reflection.name] and clears on the run label -- so a
      # second read in the same run is free and mints no second statement.
      association(:person).reset
      association(:person).reader
    rescue StandardError
      nil
    end
    person
  end'''


def main() -> int:
    path = sys.argv[1]
    s = open(path).read()
    if 'association(:person).reset' in s:
        print(f'{path}: already patched')
        return 0
    if s.count(ANCHOR) != 1:
        print(f'{path}: B-2 reader anchor not found exactly once '
              f'({s.count(ANCHOR)})', file=sys.stderr)
        return 1
    open(path, 'w').write(s.replace(ANCHOR, REPLACEMENT))
    print(f'{path}: user.person now resets the association before reading')
    return 0


if __name__ == '__main__':
    sys.exit(main())
