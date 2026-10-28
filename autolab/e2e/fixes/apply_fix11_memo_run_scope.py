#!/usr/bin/env python3
"""apply_fix11_memo_run_scope.py — a per-run memo that is not per-run.

THE DEFECT, MEASURED.  `comments_index` writes 12 dumps at MAX_RUNS=24 and
**5 of them are REFUSED** by `validate_provenance`:

    dump_anon_json_dse0009.json: symbol
    'SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id' is an
    attribute of a value the dump types `obj<Comment>`, but the dump's type
    table declares no such type. §5.2: the table is PER-DUMP so a dump is
    self-describing …

(the same message for dse0016, dse0019, dse0022, dse0023).

THE MECHANISM, MEASURED RATHER THAN INFERRED.  Reading the type table out of
every dump this endpoint wrote:

    dump            calls Relation#records   type table          verdict
    dse0001..0004   no                       Post / (none)       ok
    dse0005         YES  (the FIRST one)     Comment, Mention,
                                             Person, Post,
                                             Profile             ok
    dse0007, 0008   no                       (none)              ok
    dse0009         YES                      Person, Post,
                                             Profile             REFUSED
    dse0016/19/22/23 YES                     Person, Post[,
                                              Profile]           REFUSED

The first run that materialises the relation declares `Comment`; every later
one emits the same 41 `…records_1_row*` symbols and declares everything EXCEPT
`Comment`.

`targets/endpoints/comments_index.rb:968` memoises the materialised list in

    memo = (Thread.current[:comments_rows_memo] ||= {})

and its own comment (lines 959-966) says the list is "MEMOIZED by its own SQL
for the life of the RUN".  Nothing scopes it to a run: `Thread.current`
belongs to the PROCESS, one process drives every run of an endpoint, and the
driver clears `@all_calls` between runs but not this.  So from the second
materialisation onward the memo HITS, `ct.symbolic_instance` is never called
again — and `symbolic_instance` is where
`SymbolicFunc.register_type(tname, decl)` fires
(`comments_index.rb:1905-1915`).  Meanwhile
`SymbolicFunc.save_and_clear_types` empties the type table at every run
boundary.  The symbols survive the run; their type declaration does not.

THE FIX IS THE PATTERN THIS LIBRARY ALREADY USES.  `core.rb:1928-1933`, the
`SingularAssociation#find_target` memo, is the same shape and gets it right:

    state = (Thread.current[:concolic_loaded_target_memo] ||= { label: nil, entries: {} })
    label = CallInterceptor.instance.instance_variable_get(:@current_run_label)
    if state[:label] != label
      state[:label] = label
      state[:entries] = {}
    end

and its comment names the contract: "the whole cache resets when the label
changes: the same 'clear per run' contract".  This applies that guard to the
rows memo, so it becomes what it already claims to be.

WHY IT DID NOT SHOW BEFORE.  Both shakedowns ran MAX_RUNS=2 and neither of
`comments_index`'s two dumps reached `Relation#records` at all, so the memo
was never hit twice.  The defect is not new; the depth is.
"""
from __future__ import annotations
import shutil, sys

F = "/home/dev/project/reports/autolab/targets/endpoints/comments_index.rb"

OLD = '''      memo = (Thread.current[:comments_rows_memo] ||= {})
      hit  = memo[sql]'''

NEW = '''      # e2e FIX-11 (2026-09-26). The comment above says this list is
      # "MEMOIZED by its own SQL for the life of the RUN". It was not:
      # `Thread.current` belongs to the PROCESS and one process drives every
      # run of an endpoint, so the memo survived run boundaries. Because a
      # memo HIT skips `ct.symbolic_instance` — which is where
      # `SymbolicFunc.register_type` fires (§CommentsTargets, below) — while
      # `SymbolicFunc.save_and_clear_types` empties the per-run type table,
      # every run after the first to materialise this relation emitted
      # `…records_1_row*` symbols typed `obj<Comment>` with no `Comment` in
      # its own type table, and `validate_provenance` refused the dump
      # (§5.2). MEASURED: 5 of comments_index's 12 dumps at MAX_RUNS=24.
      #
      # The guard is the one core.rb:1928-1933 already uses for the
      # SingularAssociation loaded-target memo, verbatim in shape: the whole
      # cache resets when the run label changes.
      memo_state = (Thread.current[:comments_rows_memo_state] ||= { label: nil, memo: {} })
      run_label = begin
        CallInterceptor.instance.instance_variable_get(:@current_run_label)
      rescue StandardError
        nil
      end
      if memo_state[:label] != run_label
        memo_state[:label] = run_label
        memo_state[:memo] = {}
      end
      memo = (Thread.current[:comments_rows_memo] = memo_state[:memo])
      hit  = memo[sql]'''


def main():
    apply = "--apply" in sys.argv
    s = open(F).read()
    n = s.count(OLD)
    if n != 1:
        print(f"!! anchor x{n}")
        return 1
    if apply:
        shutil.copy(F, F + ".bak_e2e_fix11")
        open(F, "w").write(s.replace(OLD, NEW))
        print(f"patched {F}")
    else:
        print(f"anchor unique; would patch {F}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
