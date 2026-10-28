# frozen_string_literal: true
#
# LAB-LEVEL CHECK — belongs beside the application, e.g.
# reports/diaspora/tools/test_target_boundary_is_verbatim_shared.rb
#
# Lifted verbatim (paths unchanged) out of
# src_new/runtimes/ruby_runtime/tests/test_name_boundary_seed.rb on
# 2026-09-26, when that file was decoupled from the application tree. It is
# NOT a property of the engine: it is Rule T applied to ONE application's
# files — the target functions are shared app-wide, so the seed shim must be
# byte-identical in every `concolic_targets.rb` copy, or a fix applied to one
# endpoint silently leaves the others on the old behaviour.
#
# It was already half-dead where it stood: `ROOT/concolic_targets.rb` (the
# shared master) was retired to _trash/ on 2026-09-25, so `boundary_files`
# now finds only the `results3/*/` copies.
#
# Run with: ruby test_target_boundary_is_verbatim_shared.rb

require "minitest/autorun"

class TestTargetBoundaryIsVerbatimShared < Minitest::Test
  ROOT = "/home/dev/project/reports/diaspora"

  def boundary_files
    Dir[File.join(ROOT, "concolic_targets.rb")] +
      Dir[File.join(ROOT, "results3", "*", "concolic_targets.rb")] +
      Dir[File.join(ROOT, "results4", "*", "concolic_targets.rb")]
  end

  def shim_of(path)
    src = File.read(path)
    m = /  SEED_MISS = .*?\n  def seed_for\(/m.match(src)
    m && m[0]
  end

  # Rule T: the target functions are shared app-wide. The shim must be
  # byte-identical everywhere, or a "fix" applied to one endpoint silently
  # leaves the others on the old behaviour.
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
