#!/usr/bin/env python3
"""Stop empty symbolic lists from handing out a representative row.

usage: _p46_patch_emptylist.py <path-to-targets.rb>

WHY. `empty_relation_emission_audit` is RED:

    -- OVER-EMISSION: a note reads a row of an EMPTY list (4 shapes, 17001 dumps) --
       SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" =
         $$(SYM_RESULT_ActsAsApi__Collection_as_api_response_{1..4}_row_id)

The `as_api_response` mock mints its representative EAGERLY (targets.rb:828),
before the seeded length at :829 is consulted, so for a len-0 list the rep
object still exists and escapes into the render. `IterableSymbolicList`'s
emptiness guard lives in `__rows` and is wired only to `each`, `ITERATION_OPS`
and `as_api_response`; `first`, `last` and `[]` are inherited from
`SymbolicList` (src/ruby_runtime/list.rb:110-143) and return `@representative`
with no length check, as does the public `attr_reader :representative` itself.

src is NOT at fault and needs no change. list.rb:106-107 states the contract:
"absence -- '0 rows' -- was already decided at the mock boundary before a
rep-carrying list is ever produced, so returning the rep here is safe." The
mock is what breaks that contract, so the repair belongs here.

*** THIS PATCH CHANGES PATH CONDITIONS, BY DESIGN. ***
The escaped rep does not merely emit a note -- it is branched on. Traced in
dump_auth_json0112_P23Baujsaujs0038r0.json (len(..._as_api_response_2) = 0):
  (SYM_RESULT_ActsAsApi__Collection_as_api_response_2_row_guid == '')
      at active_support/core_ext/object/blank.rb:126
  (SYM_RESULT_..._3_row_guid != StringVal(''))
      at action_dispatch/journey/formatter.rb:41
Both vanish once the rep is gone. A differential gate of "path conditions byte
identical" WILL and SHOULD go red here; the correct gate is "identical except
the `*_as_api_response_*_row_*` families in runs whose `len(...)` is 0".

The precedent for the shape is comments_index's M-4 repair
(comments_index/targets.rb:917-959: `rep = nil` unless `len.positive?`), which
ADVERSARY_WINS.md:462 names as the general remedy: "rows_mock must not mint a
representative row OR any preload for a length-0 relation. Gating only the
preload leaves the decisions over non-existent rows (they come from
symbolic_instance)."

Why construct-then-attach rather than a local `Integer(seed)` guard: the
runtime coerces the length at list.rb:63-76, and `length = length.length if
length.respond_to?(:length) && !length.is_a?(Integer)` runs BEFORE
`Integer(length)`, so a String seed "0" yields length 1, not 0. Deferring to
the constructor keeps that coercion bit-for-bit identical to today; a
pre-computed Integer() would silently change it.

The empty-case `first`/`last`/`[]` overrides give real Array semantics (nil)
so that a repless empty list cannot turn an app-level `.first` into a
NotImplementedError. Non-empty behaviour is untouched and still delegates to
src.
"""
import sys

CLASS_ANCHOR = '''  class IterableSymbolicList < SymbolicList
    def each(&blk)'''

CLASS_REPLACEMENT = '''  class IterableSymbolicList < SymbolicList
    # 2026-09-25, empty_relation_emission OVER-EMISSION repair.
    #
    # src exposes `attr_reader :representative` only (list.rb:51), so a mock
    # that wants to honour list.rb:106-107's contract ("absence was already
    # decided at the mock boundary before a rep-carrying list is ever
    # produced") needs to attach the rep AFTER the runtime has computed the
    # concrete length. Precedent for a batch-local writer on this subclass:
    # comments_index/targets.rb:952 (second_representative).
    attr_writer :representative

    # Real Array semantics for the empty case. src's first/last/[]
    # (list.rb:110-143) hand back @representative with no length check, and
    # raise NotImplementedError when there is none -- so without these a
    # correctly repless empty list would turn an app-level `.first` into a
    # wall where it used to return a (bogus) row. Non-empty behaviour is
    # untouched: `super` still runs.
    def first(*args)
      return nil if args.empty? && concrete_length.zero?
      super
    end

    def last(*args)
      return nil if args.empty? && concrete_length.zero?
      super
    end

    def [](*args)
      return nil if args.length == 1 && args[0] == 0 && concrete_length.zero?
      super
    end

    def each(&blk)'''

MINT_ANCHOR = '''          rep = ct.symbolic_instance(klass, "#{name}_row", note)
          IterableSymbolicList.new(ct.seed_for("len(#{name})", 1),
                                   name: name, note: note, representative: rep)'''

MINT_REPLACEMENT = '''          # 2026-09-25: the rep used to be minted HERE, eagerly, before the
          # seeded length below was consulted -- so for a len-0 list it still
          # escaped into the render and the corpus asserted a `profiles` read
          # AND a `<rep>_guid` decision for a row that does not exist
          # (empty_relation_emission OVER-EMISSION: 4 shapes, 17001 dumps).
          # Build the list FIRST, then attach the rep only if it is non-empty.
          # Constructing first is deliberate: the runtime's own length
          # coercion (list.rb:63-76) turns a String seed "0" into 1, and a
          # local Integer(seed) guard would silently diverge from it.
          lst = IterableSymbolicList.new(ct.seed_for("len(#{name})", 1),
                                         name: name, note: note)
          if lst.concrete_length.positive?
            lst.representative = ct.symbolic_instance(klass, "#{name}_row", note)
          end
          lst'''


def main() -> int:
    path = sys.argv[1]
    s = open(path).read()
    if 'empty_relation_emission OVER-EMISSION repair' in s:
        print(f'{path}: already patched')
        return 0
    for name, anchor in (('IterableSymbolicList class', CLASS_ANCHOR),
                         ('as_api_response mint', MINT_ANCHOR)):
        if s.count(anchor) != 1:
            print(f'{path}: {name} anchor not found exactly once '
                  f'({s.count(anchor)})', file=sys.stderr)
            return 1
    s = s.replace(CLASS_ANCHOR, CLASS_REPLACEMENT).replace(
        MINT_ANCHOR, MINT_REPLACEMENT)
    open(path, 'w').write(s)
    print(f'{path}: empty lists no longer carry a representative row')
    return 0


if __name__ == '__main__':
    sys.exit(main())
