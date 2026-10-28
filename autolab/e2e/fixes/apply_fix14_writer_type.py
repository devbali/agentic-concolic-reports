#!/usr/bin/env python3
"""apply_fix14_writer_type.py — `SingularAssociation#writer` is declared an
OBJECT whose fields nothing ever declares, and `validate_provenance` refuses
every dump that reaches it.

MEASURED, sweep 2 (the post-fix sweep), on `admin_users_close_account` (6 of
its 9 dumps) and `comments_create` (dumps 1, 2, …):

    dump_auth_html_dse0001.json: events[16]
    (ActiveRecord::Associations::SingularAssociation#writer) returns obj<?>? as
    'SYM_RESULT_ActiveRecord__Associations__SingularAssociation_writer_1', and
    NOT ONE symbol in this run declares itself an attribute of it. Either the
    run never looked inside the object -- in which case the result is
    `opaque`, not an object -- or the symbols that stand for its fields are
    related to it by their spelling alone, which §4.1.1c refuses.

THE DECLARATION IS THE PROBLEM, AND THE MESSAGE NAMES THE FIX.
`targets/core.rb:1848-1854` declares

    interceptor.declare_target(
      ActiveRecord::Associations::SingularAssociation, :writer,
      kind: CallInterceptor::SHIM, type: "obj<?>?",
      returns: ->(_r, args, _n) { args["record"] })

It hands back the record that was ASSIGNED. That record was minted somewhere
else, under its own symbol, and its attribute symbols carry
`origin: {kind: "attr", of: <that other symbol>}`. So nothing is ever an
attribute of the WRITER'S result, by construction -- not occasionally, but
always. The declared `obj<?>?` promises a structure this symbol can never
have, and §4.1.1c's provenance rule is right to refuse it.

`opaque?` is the honest type, and it is the one the refusal message itself
proposes: "Either the run never looked inside the object -- in which case the
result is `opaque`, not an object". Nothing about the shim changes: same
kind (SHIM), same returns, same recorded statement. An `opaque` behind a SHIM
is exactly the case `dumps_to_policy/normalize.py:341` keeps a `sig` line for,
and the corrected `opaque_sites` check classifies it `by_design`.

NOT FIXED IN `targets/core.rb`: that file is byte-identical to the results4
gold and `test/test_install.rb:156-166` asserts it. Re-declared from the
runner, like FIX-2.

WHY IT APPEARED ONLY NOW. No round-1 endpoint reached an association
assignment -- 113 of 161 died at `set_locale` and the rest stopped earlier.
It is not new; it was behind the wall.
"""
from __future__ import annotations
import shutil, sys

DRIVER = "/home/dev/project/reports/autolab/entrypoints/lib/autolab_dse.rb"

OLD = '''    # -------------------------------------------------------------------
    # FIX-3: principal-column pins (users.language, profiles.gender)'''

NEW = '''    # -------------------------------------------------------------------
    # FIX-14: SingularAssociation#writer is opaque, not an object
    # -------------------------------------------------------------------
    # `core.rb:1848-1854` declares the writer `type: "obj<?>?"` and returns
    # `args["record"]` -- the record that was ASSIGNED, minted elsewhere under
    # its own symbol, whose attribute symbols are `attr` origins OF THAT OTHER
    # SYMBOL. So nothing is ever an attribute of the writer's result, and
    # `validate_provenance` refuses the dump (§4.1.1c). MEASURED in sweep 2 on
    # `admin_users_close_account` (6 of 9 dumps) and `comments_create`.
    #
    # `opaque?` is what the refusal message itself proposes -- "the run never
    # looked inside the object -- in which case the result is `opaque`, not an
    # object". Same kind, same returns, same recorded statement; only the
    # declared TYPE changes, to the one that is true.
    if defined?(::ActiveRecord::Associations::SingularAssociation) &&
       !::ConcolicTargets.instance_variable_get(:@autolab_candidate_writer_type)
      $interceptor.declare_target(
        ::ActiveRecord::Associations::SingularAssociation, :writer,
        kind: CallInterceptor::SHIM, type: "opaque?",
        returns: ->(_r, args, _n) { args["record"] })
      ::ConcolicTargets.instance_variable_set(:@autolab_candidate_writer_type, true)
      warn "[autolab] candidate principal plumbing: SingularAssociation#writer " \\
           "re-declared opaque? (its result's fields are attributes of another " \\
           "symbol, so obj<?>? can never be satisfied)"
    end

    # -------------------------------------------------------------------
    # FIX-3: principal-column pins (users.language, profiles.gender)'''


def main():
    apply = "--apply" in sys.argv
    s = open(DRIVER).read()
    n = s.count(OLD)
    if n != 1:
        print(f"!! anchor x{n}")
        return 1
    if apply:
        shutil.copy(DRIVER, DRIVER + ".bak_fix14")
        open(DRIVER, "w").write(s.replace(OLD, NEW, 1))
        print("driver patched with FIX-14")
    else:
        print("anchor unique; would patch the driver")
    return 0


if __name__ == "__main__":
    sys.exit(main())
