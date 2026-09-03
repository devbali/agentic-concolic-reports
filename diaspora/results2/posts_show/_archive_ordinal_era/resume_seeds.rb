#!/usr/bin/env jruby
# frozen_string_literal: true
#
# posts_show — resume pass: drive the checker's suggested seeds directly.
#
# Per COMPLETION_BRIEF.md step 2.1: "each missing combo's concrete_values is
# a full seed assignment ... many combos will close by execution since the
# worklist was merely capped." Loads coverage_summary.json's `missing` list
# (already regenerated with max_missing_per_clique=256) and, for each combo,
# drives ONE execution per scenario (auth, anon) with those seeds. New
# distinct paths are written as dump_seedNNNN.json; dumps that replay an
# already-seen path (by PC signature, checked against the FULL existing
# corpus, not just this run) are silently skipped, matching run_dse.rb's own
# dedup discipline.
#
# Reuses run_dse.rb's helper prefix (requires/targets install/symbolic_user/
# make_harness/run_one/path_conditions/digest/sig_of) verbatim by eval'ing
# its source up to the `t0 = Time.now` main-loop marker, passing the real
# path so __FILE__ (and so HERE) stays correct — same pattern documented in
# the concolic-assumptions-and-crash-isolation memory.
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
#       /home/dev/project/reports/diaspora/results2/posts_show/resume_seeds.rb

require "json"

HERE = File.dirname(File.expand_path(__FILE__))
run_dse_path = File.join(HERE, "run_dse.rb")
src = File.read(run_dse_path)
marker = "\nt0 = Time.now\n"
idx = src.index(marker)
raise "marker not found in run_dse.rb" unless idx
prefix = src[0...idx]
eval(prefix, TOPLEVEL_BINDING, run_dse_path)

# ---------------------------------------------------------------------------
# Load existing corpus signatures so we never rewrite a dump we already have.
# ---------------------------------------------------------------------------
existing_sigs = {}
Dir.glob(File.join(HERE, "dump_*.json")).each do |f|
  begin
    d = JSON.parse(File.read(f))
    pcs = (d["events"] || []).select { |e| e["type"] == "path_condition" }
                              .map { |e| [e["expr"], e["taken"] ? true : false] }
    sig = Digest::SHA256.hexdigest(pcs.map { |e, t| "#{e}:#{t}" }.join("|"))[0, 16]
    existing_sigs[sig] = File.basename(f)
  rescue StandardError => e
    warn "[resume_seeds] could not parse #{f}: #{e.class}"
  end
end
puts "[resume_seeds] #{existing_sigs.size} existing distinct-path signatures loaded"

# ---------------------------------------------------------------------------
# Load the checker's suggested seeds.
# ---------------------------------------------------------------------------
summary_path = File.join(HERE, "coverage_summary.json")
summary = JSON.parse(File.read(summary_path))
missing = summary["missing"] || []
puts "[resume_seeds] #{missing.size} missing combos loaded from coverage_summary.json"

results = { "new_paths" => 0, "duplicate_paths" => 0, "errors" => Hash.new(0), "runs" => 0 }
counter = 0

missing.each_with_index do |m, mi|
  seeds = m["concrete_values"] || {}
  next if seeds.empty?

  %w[auth anon].each do |scenario|
    counter += 1
    label = format("seed%04d", counter)
    begin
      dump = run_one(scenario, "#{scenario}_#{label}", seeds)
    rescue Exception => e # rubocop:disable Lint/RescueException
      results["errors"]["harness:#{e.class}"] += 1
      next
    end
    results["runs"] += 1
    results["errors"]["run:#{dump['error']['type']}"] += 1 if dump["error"]

    pcs = (dump["events"] || []).select { |e| e["type"] == "path_condition" }
                                 .map { |e| [e["expr"], e["taken"] ? true : false] }
    sig = Digest::SHA256.hexdigest(pcs.map { |e, t| "#{e}:#{t}" }.join("|"))[0, 16]

    if existing_sigs.key?(sig)
      results["duplicate_paths"] += 1
      next
    end
    existing_sigs[sig] = "dump_#{scenario}_#{label}.json"
    results["new_paths"] += 1
    File.write(File.join(HERE, "dump_#{scenario}_#{label}.json"), JSON.pretty_generate(dump))

    if results["new_paths"] <= 10 || results["new_paths"] % 20 == 0
      puts format("[combo %d/%d %s] NEW path -> dump_%s_%s.json (pcs=%d)",
                  mi + 1, missing.size, scenario, scenario, label, pcs.size)
    end
  end
end

File.write(File.join(HERE, "resume_seeds_summary.json"), JSON.pretty_generate(results))
puts "\n== resume_seeds.rb done =="
puts results.to_json
