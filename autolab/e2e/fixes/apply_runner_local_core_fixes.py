#!/usr/bin/env python3
"""apply_runner_local_core_fixes.py — FIX-2, FIX-7, FIX-9 and FIX-11 WITHOUT
editing the shared target library.

WHY THIS FILE EXISTS, AND WHY THE FIRST ATTEMPT WAS WRONG.
I first applied these four as edits to `targets/core.rb` and
`targets/endpoints/comments_index.rb`. The auto lab's own suite caught it:

    FAIL core.rb == reports/diaspora/results4/aspect_memberships_create/concolic_targets.rb: DRIFTED
    FAIL comments_index.rb == reports/diaspora/results4/comments_index/targets.rb: DRIFTED

`test/test_install.rb:156-166` asserts §5, "the library is byte-identical to
the results4 gold it was copied from". That is a real invariant, not a
formality — the library's claim is that it IS those files, and results4 is the
reference corpus other work is locked against. Both files are reverted and
byte-identical again; the attempted versions are kept beside them as
`*.e2e_attempt` for whoever decides the library's own copy should change.

So the same four repairs are made from the RUNNER, which is the technique the
gold layers themselves name ("Overriding from this file is the technique §9
already uses", comments_index.rb). Each is installed only where it is needed.

  FIX-2  re-declare `DeviseController#devise_mapping` to return the REAL
         `Devise.mappings[:user]`. `core.rb`'s stub is a closure-local
         `Object` whose `to` returns itself, so Devise gets the stub where it
         expects the model class. The real mapping exists in the booted app
         (measured, probes/probe_fixes.out: `Devise.mappings.keys == [:user]`,
         `Devise.mappings[:user].to == User`).
  FIX-7  define `SymbolicVar.len_var_name` — the method core.rb:1395 and
         :1483 call and the runtime deleted. It is only ever used to build a
         SEED KEY, and the spelling is the one core.rb:98-124's own name
         boundary documents (`SYM_LEN_<var>`).
  FIX-9  prepend `each`/`map` onto `SymbolicList` so Gate 1b's representative
         row can actually be reached. A subclass's own methods still win, so
         `comments_index`'s richer `IterableSymbolicList` is untouched.
  FIX-11 clear the per-run thread-local memos at the top of every run, from
         the driver, which is where run boundaries live. `comments_index.rb`
         memoises in `Thread.current[:comments_rows_memo]` and calls it "for
         the life of the RUN", but nothing scoped it to one.
"""
from __future__ import annotations
import shutil, sys

DRIVER = "/home/dev/project/reports/autolab/entrypoints/lib/autolab_dse.rb"

# ---- FIX-7 + FIX-9: installed for EVERY endpoint, right after boot --------
BOOT_OLD = '''    install_asset_helper_stubs!
    $interceptor = CallInterceptor.instance'''
BOOT_NEW = '''    install_asset_helper_stubs!
    install_runtime_compat_shims!
    $interceptor = CallInterceptor.instance'''

METHOD_ANCHOR = '''  def install_asset_helper_stubs!'''

METHOD_NEW = '''  # e2e FIX-7 + FIX-9 (2026-09-26), RUNNER-LOCAL. Both repair calls that
  # `targets/core.rb` makes into the symbolic runtime, and neither edits it:
  # `test/test_install.rb:156-166` asserts the library is byte-identical to
  # the results4 gold, and it is.
  def install_runtime_compat_shims!
    return unless defined?(::SymbolicVar)

    # FIX-7. `core.rb:1395` and `:1483` call `SymbolicVar.len_var_name(vn)`,
    # which `src_new/runtimes/ruby_runtime/base.rb:33` DELETED (DESIGN_IR
    # §4.1.1c change 3 -- "a length is the `length` OPERATOR ... there is no
    # name to mint"), so every relation materialisation raised
    #   NoMethodError: undefined method `len_var_name' for SymbolicVar:Module
    # MEASURED in e2e/fixtrial as soon as the principal resolved; invisible
    # before that because nothing got far enough to materialise a relation.
    #
    # Both call sites use the result ONLY as a seed key. A seed key is this
    # library's own business, not the runtime's, and the spelling below is the
    # one `core.rb:98-124` already documents and `length_var?` already
    # accepts. Defined here rather than restored in the runtime: the runtime's
    # own test (`tests/test_name_boundary_seed.rb:116`) asserts the deletion,
    # and it is right to.
    unless ::SymbolicVar.respond_to?(:len_var_name)
      ::SymbolicVar.define_singleton_method(:len_var_name) do |var_name|
        "SYM_LEN_#{var_name}"
      end
      warn "[autolab] runtime compat: SymbolicVar.len_var_name re-provided " \\
           "as a SEED KEY only (see install_runtime_compat_shims!)"
    end

    # FIX-9. `core.rb:1386-1389` says the `to_a`/`to_ary`/`records` mock
    # attaches "a single representative model row so SQL-free
    # display/serialisation iteration COMPLETES" -- but it builds a plain
    # `SymbolicList`, whose `each`/`map` are in `LIST_STUBS`
    # (`list.rb:285-311`) and raise "contents out of scope". The
    # representative existed and nothing could reach it. MEASURED: with FIX-7
    # in, `SymbolicList#each is not supported` at `list.rb:305` was the next
    # wall on every endpoint that materialises a relation.
    #
    # PREPENDED ON THE BASE CLASS, not defined on a subclass, because
    # core.rb hardcodes `SymbolicList.new` at :1395. A SUBCLASS'S OWN METHODS
    # STILL WIN over a module prepended to its parent, so
    # `comments_index`'s richer `IterableSymbolicList` (second representative,
    # M-13) is untouched where it is installed.
    #
    # Both methods record the SAME canonical compare the runtime's own
    # `any?`/`none?` record (`list.rb:163-172`), and `map` records it too
    # because a JSON render reaches a collection through `map` and never
    # compares its length otherwise (comments_index D9). NO `Enumerable` is
    # included anywhere: a module included into a subclass goes BEFORE the
    # superclass and would shadow the `any?`/`none?` that record the decision.
    if defined?(::SymbolicList) &&
       !::SymbolicList.instance_variable_get(:@autolab_iterable)
      iter = Module.new do
        def each
          return to_enum(:each) unless block_given?
          nonempty = concrete_length != 0
          record!("(#{@symbolic_len} != 0)", "each", taken: nonempty)
          yield @representative if nonempty && @representative
          self
        end

        def map
          return to_enum(:map) unless block_given?
          nonempty = concrete_length != 0
          record!("(#{@symbolic_len} != 0)", "map", taken: nonempty)
          (nonempty && @representative) ? [yield(@representative)] : []
        end
        alias_method :collect, :map

        # Ruby's own `[].first` is nil and so is AR's; every OTHER rep-less
        # access still raises loudly. Same carve-out comments_index makes.
        def first(*args)
          return nil if args.empty? && @representative.nil? && concrete_length.zero?
          super
        end
      end
      ::SymbolicList.prepend(iter)
      ::SymbolicList.instance_variable_set(:@autolab_iterable, true)
      warn "[autolab] runtime compat: SymbolicList#each/#map provided so Gate " \\
           "1b's representative row is reachable"
    end
  end

''' + METHOD_ANCHOR

# ---- FIX-11: clear per-run thread-local memos, from the driver -----------
RESET_OLD = '''    ConcolicTargets.seed_overrides = seeds
    terminal_box[:value] = nil
    terminal_box[:handled] = nil   # e2e FIX-13: per-run, like :value'''
RESET_NEW = '''    ConcolicTargets.seed_overrides = seeds
    terminal_box[:value] = nil
    terminal_box[:handled] = nil   # e2e FIX-13: per-run, like :value
    clear_per_run_memos!'''

MEMO_ANCHOR = '''  # E2E INVENTORY ADDITION (2026-09-26, reports/autolab/e2e). ADDITIVE ONLY:'''
MEMO_NEW = '''  # e2e FIX-11 (2026-09-26), RUNNER-LOCAL. A memo that claims to be per-run
  # and is not.
  #
  # `targets/endpoints/comments_index.rb:968` memoises a materialised relation
  # in `Thread.current[:comments_rows_memo]` and its own comment says the list
  # is "MEMOIZED by its own SQL for the life of the RUN". Nothing scoped it:
  # `Thread.current` belongs to the PROCESS and one process drives every run.
  # Because a memo HIT skips `ConcolicTargets.symbolic_instance` -- which is
  # where `SymbolicFunc.register_type` fires -- while
  # `SymbolicFunc.save_and_clear_types` empties the per-run type table, every
  # run after the first to materialise that relation emitted
  # `…records_1_row*` symbols typed `obj<Comment>` with no `Comment` in its
  # own type table, and `validate_provenance` REFUSED the dump (§5.2).
  #
  # MEASURED: 5 of comments_index's 12 dumps at MAX_RUNS=24. The mechanism was
  # read off the dumps, not inferred -- the FIRST run to call
  # `Relation#records` (dse0005) declares `Comment` and is accepted; dse0009,
  # 0016, 0019, 0022 and 0023 all call it, all emit the same 41 symbols, and
  # none declares `Comment`.
  #
  # CLEARED HERE, NOT FIXED THERE: `targets/endpoints/comments_index.rb` is
  # byte-identical to the results4 gold and `test/test_install.rb:156-166`
  # asserts that. The driver owns run boundaries -- it already clears
  # `CallInterceptor#@all_calls` between runs for the same reason -- so this
  # is where a per-run cache belongs.
  #
  # `core.rb:1928-1933`'s own loaded-target memo does scope itself, by run
  # label; the keys below are the ones that do NOT.
  PER_RUN_MEMO_KEYS = %i[
    comments_rows_memo
    concolic_loaded_target_memo
    concolic_autosave_seen
    concolic_autosave_depth
    concolic_pending_note
    concolic_finder_conds
    concolic_update_all_values
    concolic_write_args
  ].freeze

  def clear_per_run_memos!
    PER_RUN_MEMO_KEYS.each { |k| Thread.current[k] = nil }
  end

''' + MEMO_ANCHOR

# ---- FIX-2: re-declare devise_mapping to return the REAL mapping ---------
DEVISE_ANCHOR = '''    # -------------------------------------------------------------------
    # FIX-3: principal-column pins (users.language, profiles.gender)'''
DEVISE_NEW = '''    # -------------------------------------------------------------------
    # FIX-2: devise_mapping must hand Devise the MODEL CLASS
    # -------------------------------------------------------------------
    # `core.rb:1988-2003` builds a closure-local `dev_stub = Object.new` and
    # gives it `def dev_stub.to(*_); self; end`, so `mapping.to` returns the
    # STUB where Devise expects the resource class. MEASURED: all six
    # endpoints that call `devise_mapping` stop with a NoMethodError on a bare
    # `#<Object>`, and every missing name is a `User` CLASS method --
    #   sessions_new             authentication_keys
    #     (devise-4.7.1/lib/devise/parameter_sanitizer.rb:158)
    #   registrations_new        new_with_session
    #   devise_passwords_new     new
    #   devise_passwords_create  send_reset_password_instructions
    #   devise_passwords_edit    reset_password_by_token
    #   devise_passwords_update  reset_password_by_token / new
    # -- and all five are present on `::User` (measured, probe_fixes.out).
    #
    # The stub is closure-local, so it cannot be reached; the target is
    # RE-DECLARED instead, which the registry names as the override mechanism
    # ("Last declaration for a (class, method) wins"). It returns the app's
    # OWN `Devise.mappings[:user]`, which exists in the booted app and whose
    # `.to` IS `User` (measured). Same kind and same declared type, so the
    # declaration table keeps its shape.
    if defined?(::DeviseController) && defined?(::Devise) &&
       !::ConcolicTargets.instance_variable_get(:@autolab_candidate_devise_mapping)
      mapping = begin
        ::Devise.mappings[:user]
      rescue StandardError
        nil
      end
      if mapping
        $interceptor.declare_target(
          ::DeviseController, :devise_mapping,
          kind: CallInterceptor::SHIM, type: "opaque",
          returns: ->(_r, _a, _n) { mapping })
        ::ConcolicTargets.instance_variable_set(:@autolab_candidate_devise_mapping, true)
        warn "[autolab] candidate principal plumbing: devise_mapping re-declared " \\
             "to the real Devise.mappings[:user] (to == #{mapping.to})"
      end
    end

    # -------------------------------------------------------------------
    # FIX-3: principal-column pins (users.language, profiles.gender)'''


def main():
    apply = "--apply" in sys.argv
    s = open(DRIVER).read()
    edits = [(BOOT_OLD, BOOT_NEW), (METHOD_ANCHOR, METHOD_NEW),
             (RESET_OLD, RESET_NEW), (MEMO_ANCHOR, MEMO_NEW),
             (DEVISE_ANCHOR, DEVISE_NEW)]
    for old, _new in edits:
        n = s.count(old)
        if n != 1:
            print(f"!! anchor x{n}: {old[:60]!r}")
            return 1
    for old, new in edits:
        s = s.replace(old, new, 1)
    if apply:
        shutil.copy(DRIVER, DRIVER + ".bak_runner_local")
        open(DRIVER, "w").write(s)
        print("driver patched with the runner-local FIX-2/7/9/11")
    else:
        print("all 5 anchors unique; would patch the driver")
    return 0


if __name__ == "__main__":
    sys.exit(main())
