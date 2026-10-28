# frozen_string_literal: true
#
# test_name_boundary_seed.rb — the acceptance test for the 2026-09-14 length
# rename (reports/diaspora/docs/NAME_BOUNDARY_PLAN_20260914.md §8.6).
#
# Two directions, and BOTH are required:
#
#   1. the runtimes mint the solver-legal spelling `SYM_LEN_X`, so no batch
#      needs a `fix_len_names` rename on a fresh dump;
#   2. a seed written in the OLD spelling `len(X)` — every seed file and dump
#      snapshot on disk before today — still TAKES under the new runtime.
#
# (2) is the one that cannot be skipped. `seed_for` matches exactly and falls
# back to `default` SILENTLY, so "the seed works" and "the seed is quietly
# defaulting" look identical from outside. The test therefore asserts the
# VALUE that came back, never merely the absence of an error.

require "minitest/autorun"
require_relative "ruby_runtime/base"
require_relative "ruby_runtime/int"
require_relative "ruby_runtime/list"
require_relative "ruby_runtime/dict"

# The shim is NOT copied here. An executable copy would pass even if the
# SHIPPED file were broken -- which is the whole failure mode this change
# exists to end. The real `concolic_targets.rb` source is extracted and
# evaluated instead, so these tests exercise the code that actually runs.
BOUNDARY_ROOT = File.expand_path("../reports/diaspora", __dir__)

def self.load_shim(path, into:)
  src = File.read(path)
  m = /^  # Sentinel distinguishing.*?^  def seed_for\(var_name, default\).*?^  end$/m.match(src)
  raise "no seed shim found in #{path}" unless m
  mod = Module.new do
    class << self
      attr_accessor :seed_overrides, :seed_suffixes
    end
    self.seed_overrides = {}
    self.seed_suffixes  = {}
  end
  Object.const_set(into, mod)
  # `seeds_used` is the conversations_index variant's bookkeeping; stub it so
  # that variant evaluates unchanged.
  # The shipped code names its own module explicitly (`ConcolicTargets.seed_
  # overrides`). Evaluating two variants in one process needs two modules, so
  # the self-reference is rewritten to `self.` -- inside a `module_function`
  # method `self` IS the module, so this is the same call, not a weakened one.
  body = m[0].gsub("ConcolicTargets.", "self.")
  mod.module_eval("module_function\ndef seeds_used; @seeds_used ||= {}; end\n" + body,
                  path, 1)
  mod
end

# The plain variant, from the top-level boundary file.
ConcolicTargets = load_shim(File.join(BOUNDARY_ROOT, "concolic_targets.rb"),
                            into: :ConcolicTargets)

class TestMintedSpelling < Minitest::Test
  def test_list_length_var_is_a_legal_python_identifier
    # The whole point: `len(X)` is legal Z3 and legal JSON but NOT legal
    # Python, and solver.py transports Z3 terms as Python source.
    name = SymbolicList.new(3, name: "rows").symbolic_len.sym_name
    assert_equal "SYM_LEN_rows", name
    assert_match(/\A[A-Za-z_][A-Za-z0-9_]*\z/, name,
                 "a minted name must be a legal Python identifier")
  end

  def test_dict_length_var_too
    assert_equal "SYM_LEN_d",
                 SymbolicVar.len_var_name("d")
  end

  def test_anonymous_containers_have_no_length_identity
    assert_nil SymbolicVar.len_var_name(nil)
    assert_nil SymbolicVar.len_var_name("")
    assert_nil SymbolicList.new(2).symbolic_len.sym_name
  end

  def test_recorded_expr_carries_the_new_spelling
    SymbolicVar.clear_path_conditions
    list = SymbolicList.new(0, name: "rows")
    list.empty?
    exprs = SymbolicVar.get_path_conditions.map(&:expr)
    refute_empty exprs
    assert exprs.any? { |e| e.include?("SYM_LEN_rows") },
           "expected SYM_LEN_rows in #{exprs.inspect}"
    refute exprs.any? { |e| e.include?("len(") },
           "no expr may still carry the old dialect: #{exprs.inspect}"
  end
end

class TestLegacySeedsStillTake < Minitest::Test
  def setup
    ConcolicTargets.seed_overrides = {}
    ConcolicTargets.seed_suffixes  = {}
  end

  # THE test. A pre-rename seed file keys length seeds `len(X)`; the runtime
  # now asks for `SYM_LEN_X`. Without the shim this returns the default and
  # says nothing.
  def test_old_spelling_seed_is_honoured_by_a_new_spelling_lookup
    ConcolicTargets.seed_overrides = { "len(rows)" => 7 }
    assert_equal 7, ConcolicTargets.seed_for("SYM_LEN_rows", 1),
                 "a len(X)-keyed seed must still take under the new runtime"
  end

  def test_new_spelling_seed_is_honoured_by_an_old_spelling_lookup
    ConcolicTargets.seed_overrides = { "SYM_LEN_rows" => 7 }
    assert_equal 7, ConcolicTargets.seed_for("len(rows)", 1)
  end

  def test_asked_for_spelling_wins_when_both_are_present
    ConcolicTargets.seed_overrides = { "SYM_LEN_rows" => 7, "len(rows)" => 9 }
    assert_equal 7, ConcolicTargets.seed_for("SYM_LEN_rows", 1)
    assert_equal 9, ConcolicTargets.seed_for("len(rows)", 1)
  end

  def test_a_genuine_absence_still_returns_the_default
    ConcolicTargets.seed_overrides = { "SYM_LEN_other" => 7 }
    assert_equal 1, ConcolicTargets.seed_for("SYM_LEN_rows", 1)
  end

  # A seed of nil/false must be distinguishable from "not seeded" — the
  # sentinel exists for this and `fetch(k, default)` got it right before.
  def test_a_falsy_seed_is_not_mistaken_for_an_absent_one
    ConcolicTargets.seed_overrides = { "len(rows)" => 0 }
    assert_equal 0, ConcolicTargets.seed_for("SYM_LEN_rows", 5)
    ConcolicTargets.seed_overrides = { "len(flag)" => false }
    assert_equal false, ConcolicTargets.seed_for("SYM_LEN_flag", true)
  end

  def test_non_length_names_are_untouched
    ConcolicTargets.seed_overrides = { "SYM_RESULT_find_by_1_ok" => true }
    assert_equal true, ConcolicTargets.seed_for("SYM_RESULT_find_by_1_ok", false)
    assert_equal [:x], ConcolicTargets.seed_aliases(:x)
  end

  def test_length_var_recognises_both_spellings
    assert ConcolicTargets.length_var?("len(rows)")
    assert ConcolicTargets.length_var?("SYM_LEN_rows")
    refute ConcolicTargets.length_var?("SYM_RESULT_x")
  end

  # Under the old spelling a length name ended with ")", so a suffix seed
  # could never match one. The new spelling ends with a bare suffix and would
  # start matching — silently widening what a suffix seed captures. That must
  # not happen as a side effect of a rename.
  def test_suffix_seeding_does_not_newly_capture_length_vars
    refute "len(SYM_RESULT_x_rows)".end_with?("_rows"),
           "premise: the old spelling could never match a bare suffix"
    assert "SYM_LEN_SYM_RESULT_x_rows".end_with?("_rows"),
           "premise: the new spelling would match, hence the guard"
  end
end

# The notifications_index variant is the divergent one: exact seed first, then
# SUFFIX seeding, then the default. It carries the one behaviour guard this
# change introduced, so it is tested against its own shipped source.
NotifTargets = load_shim(
  File.join(BOUNDARY_ROOT, "results3", "notifications_index", "concolic_targets.rb"),
  into: :NotifTargets)

class TestSuffixSeedingVariant < Minitest::Test
  def setup
    NotifTargets.seed_overrides = {}
    NotifTargets.seed_suffixes  = {}
  end

  def test_both_length_spellings_are_accepted_here_too
    NotifTargets.seed_overrides = { "len(rows)" => 7 }
    assert_equal 7, NotifTargets.seed_for("SYM_LEN_rows", 1)
  end

  def test_suffix_seeding_still_works_for_ordinary_vars
    NotifTargets.seed_suffixes = { "_disp_has_dlink" => true }
    assert_equal true,
                 NotifTargets.seed_for("SYM_RESULT_find_by_1_profile_disp_has_dlink", false)
  end

  # THE GUARD. Under the old spelling a length name ended with ")", so no
  # suffix could ever match one. `SYM_LEN_X_rows` ends with a bare suffix and
  # WOULD start matching — silently widening what a suffix seed captures.
  # A rename must not change which decisions a scenario explores.
  def test_a_suffix_seed_does_not_capture_a_length_var
    NotifTargets.seed_suffixes = { "_rows" => 9 }
    assert_equal 1, NotifTargets.seed_for("SYM_LEN_SYM_RESULT_x_rows", 1),
                 "suffix seeding must not newly capture a cardinality var"
  end

  def test_an_exact_seed_still_beats_a_suffix_seed
    NotifTargets.seed_overrides = { "SYM_RESULT_a_flag" => 1 }
    NotifTargets.seed_suffixes  = { "_flag" => 2 }
    assert_equal 1, NotifTargets.seed_for("SYM_RESULT_a_flag", 0)
  end
end

class TestTargetBoundaryIsVerbatimShared < Minitest::Test
  ROOT = File.expand_path("../reports/diaspora", __dir__)

  def boundary_files
    Dir[File.join(ROOT, "concolic_targets.rb")] +
      Dir[File.join(ROOT, "results3", "*", "concolic_targets.rb")]
  end

  def shim_of(path)
    src = File.read(path)
    m = /  SEED_MISS = .*?\n  def seed_for\(/m.match(src)
    m && m[0]
  end

  # Rule T: the target functions are shared app-wide. The shim must be
  # byte-identical everywhere, or a "fix" applied to one endpoint silently
  # leaves the others on the old behaviour — which is the class of defect
  # this whole change exists to end.
  def test_every_copy_carries_the_identical_shim
    files = boundary_files
    refute_empty files
    shims = files.to_h { |f| [f, shim_of(f)] }
    missing = shims.select { |_f, s| s.nil? }.keys
    assert_empty missing, "no seed shim in: #{missing.inspect}"
    assert_equal 1, shims.values.uniq.size,
                 "the shim has drifted between boundary copies"
  end

  def test_no_copy_still_asks_for_the_old_spelling_directly
    offenders = boundary_files.select { |f| File.read(f).include?('seed_for("len(') }
    assert_empty offenders,
                 "these ask for a hard-coded len(...) seed key: #{offenders.inspect}"
  end
end
