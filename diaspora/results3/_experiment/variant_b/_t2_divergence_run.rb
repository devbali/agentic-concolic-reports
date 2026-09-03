#!/usr/bin/env jruby
# frozen_string_literal: true
#
# _t2_divergence_run.rb — variant_b T2 data-flow divergence probe, ONE SIDE.
#
# Starts Ruby `Coverage` (lines: true) BEFORE `config/environment` loads (so
# gem/app code compiled during boot is instrumented -- Coverage in
# CRuby/JRuby only tracks lines in files whose compilation happened AFTER
# Coverage.start), then `load`s run_dse.rb (a fresh JRuby process per
# invocation -- avoids double-patching declare_target by re-installing
# targets on an already-patched class, which a same-process double-`load`
# would cause).
#
# Env:
#   T2_SEED_JSON   -- path to a JSON file: [{ "var" => seed, ... }] (ONE
#                      seed dict; becomes the sole EXTRA_SEEDS_JSON root)
#   T2_LABEL       -- label suffix for this run's dump + coverage output
#   T2_OUT         -- path to write the coverage-result JSON

require "coverage"
Coverage.start(lines: true)

ENV["EXTRA_SEEDS_JSON"] = ENV["T2_SEED_JSON"]
ENV["SEEDS_ONLY"]       = "1"
ENV["MAX_RUNS"]         = "1"
ENV["TIME_BUDGET"]      = "120"
ENV["LABEL_SUFFIX"]     = "_#{ENV['T2_LABEL']}"

load File.join(File.dirname(File.expand_path(__FILE__)), "run_dse.rb")

result = Coverage.result
# Keep the file small: drop files with zero total hits (never touched at
# all) to cut noise; keep everything else verbatim.
trimmed = {}
result.each do |file, arr|
  total = arr.compact.sum
  trimmed[file] = arr if total > 0
end

File.write(ENV["T2_OUT"], JSON.generate(trimmed))
warn "[t2] wrote #{ENV['T2_OUT']} (#{trimmed.size} files with coverage)"
