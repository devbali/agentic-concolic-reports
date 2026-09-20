# CONCRETE CHECKER, capture side (RUNBOOK Phase 5; formerly "C1/C2").
# Runs the endpoint (or a slice of it) CONCRETELY — real code, no
# concolic mocks — and records the ground truth in TARGET-FUNCTION
# currency, not SQL: which target functions the real path invokes, and
# which app lines it executes. Compare against the corpus with
# end_to_end_completion_checker/concrete_checker.py.
#
# Invocation (coverage needs JRuby --debug):
#   JRUBY_OPTS=--debug scripts/diaspora-concolic \
#     /abs/reports/diaspora/tools/concrete_checker/concrete_run_probe.rb \
#     /abs/<batch>/concrete_manifest.rb
#
# PREREQUISITE: a working fixture environment (real DB with concrete
# records). Target functions ALWAYS run for real here — a mode that
# stubbed them was removed (Bali, 2026-08-25): real code with a faked
# target boundary is exactly what the concolic engine does, so a
# "concrete" run built that way is not ground truth and shares the
# failure mode of the mocks it is supposed to check.
#
# Manifest:
#   CONCRETE_SCENARIOS = [
#     { name: "notifications-index",
#       targets: [[ActiveRecord::FinderMethods, :find_by], ...],  # the batch's declared pairs
#       coverage_filter: %r{apps/diaspora/(app|lib)/},
#       body: -> { <drive the endpoint concretely against fixtures> } },
#   ]
#
# CRASH ISOLATION: a scenario body can abort the JVM natively (observed:
# the mention-parse path on this JRuby), and a JVM abort takes the whole
# process — per-scenario `error` capture only catches Ruby exceptions.
# When bodies are risky, run ONE scenario per invocation (separate
# manifests) so the crasher names itself — same rule as the DSE runner's
# per-seed crash isolation. concrete_checker.py accepts multiple
# concrete_run.json files.
#
# Output: concrete_run.json next to the manifest —
#   [{name, target_calls: [{target, args}...], coverage: {file: [lines]},
#     error: <if the body raised — recorded, with calls captured up to it>}]
require "json"
COLLECT_COVERAGE = ENV["CONCRETE_COVERAGE"] == "1"
if COLLECT_COVERAGE
  require "coverage"
  Coverage.start
end
require "./config/environment"
require_relative "target_call_probe"

# Resolve the corpus's live target strings into (Module, :meth) pairs —
# the DETERMINISTIC target list (no hand-authored list): every target that
# fired concolically is traced concretely. Unresolvable names (batch-local
# aliases, Anonymous singletons) are reported and skipped.
def targets_from_corpus(batch_dir, exclude: {}, extra: [])
  # exclude: {"Mod.meth" => "reason"} — targets deliberately NOT traced
  # concretely (e.g. framework plumbing whose super chain breaks under
  # alias-wrapping on this Ruby); each exclusion is printed with its
  # reason so the waiver is visible in every run
  require "json"
  names = {}
  Dir.glob(File.join(batch_dir, "dump_*.json")).each do |f|
    d = JSON.parse(File.read(f))
    (d["events"] || []).each do |ev|
      names[ev["target"]] = true if ev["type"] == "symbolic_call" && ev["result_name"]
    end
  end
  pairs = []
  skipped = []
  names.keys.each do |t|
    if exclude.key?(t)
      warn "[concrete] target EXCLUDED by manifest waiver: #{t} (#{exclude[t]})"
      next
    end
    mod_name, meth = t.rpartition(".").values_at(0, 2)
    begin
      mod = mod_name.split("::").inject(Object) { |m, c| m.const_get(c) }
      ok = (mod.respond_to?(:method_defined?) &&
            (mod.method_defined?(meth) || mod.private_method_defined?(meth))) ||
           mod.respond_to?(meth)
      ok ? pairs << [mod, meth.to_sym] : skipped << t
    rescue NameError
      skipped << t
    end
  end
  warn "[concrete] targets_from_corpus: #{pairs.size} resolved, skipped: #{skipped.join(', ')}" unless skipped.empty?
  # extra: concrete forms of batch-local ALIASES (corpus names that do not
  # exist in the clean app resolve here under their real method)
  pairs + extra
end

manifest = ARGV[0] or abort "usage: concrete_run_probe.rb <concrete_manifest.rb>"
load File.expand_path(manifest)
abort "manifest must define CONCRETE_SCENARIOS" unless defined?(CONCRETE_SCENARIOS)

# Coverage is CUMULATIVE for the whole manifest and read ONCE at the end
# (Coverage.peek_result per scenario triggers native crashes on this
# JRuby); enable with CONCRETE_COVERAGE=1. Target-call capture is always
# per scenario.
# Manifests that issue several requests inside ONE scenario body must clear
# the cache between them: `CompletionChecker.new_request!`.
module CompletionChecker
  def self.new_request!
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
      ActiveRecord::Base.connection.clear_query_cache
    end
  rescue StandardError
    nil
  end
end

results = CONCRETE_SCENARIOS.map do |sc|
  err = nil
  # Per-frame REAL statement capture: every sql.active_record statement is
  # tagged with the target-function frame it was issued under — the input
  # to the DETERMINISTIC per-mock note-fidelity check (mock_note_check.py).
  statements = []
  sub = if defined?(ActiveSupport::Notifications)
    ActiveSupport::Notifications.subscribe("sql.active_record") do |*sargs|
      payload = sargs.last
      next if payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name].to_s)
      statements << { "sql" => payload[:sql].to_s,
                      "under" => Thread.current[:cc_target_frame] }
    end
  end
  # Each REAL request gets its own AR query cache; this rig runs many
  # requests in one process, so without clearing it a statement REPEATED by a
  # later request is marked `cached` and silently dropped from ground truth —
  # every multi-request manifest under-reports, and the gap grows with the
  # request count (conversations_index INSTR-2, 2026-08-29). Clearing here
  # keeps the within-request caching (which is real) while restoring the
  # between-request reads (which are also real).
  begin
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
      ActiveRecord::Base.connection.clear_query_cache
    end
  rescue StandardError
    nil
  end
  calls = CompletionChecker::TargetCallProbe.capture(targets: sc[:targets]) do
    begin
      sc[:body].call
    rescue StandardError => e
      err = "#{e.class}: #{e.message[0, 140]}"
    end
  end
  ActiveSupport::Notifications.unsubscribe(sub) if sub
  { "name" => sc[:name], "target_calls" => calls,
    "statements" => statements, "coverage" => {}, "error" => err }
end

if COLLECT_COVERAGE
  filter = CONCRETE_SCENARIOS.map { |sc| sc[:coverage_filter] }.compact.first
  cumulative = {}
  Coverage.result.each do |file, lines|
    next if filter && file !~ filter
    executed = []
    lines.each_with_index { |c, i| executed << i + 1 if c && c > 0 }
    cumulative[file] = executed unless executed.empty?
  end
  results << { "name" => "_cumulative_coverage",
               "target_calls" => [], "coverage" => cumulative, "error" => nil }
end

out = File.join(File.dirname(File.expand_path(manifest)), "concrete_run.json")
File.write(out, JSON.pretty_generate(results))
results.each do |r|
  puts format("%-24s target_calls=%-4d files_covered=%-4d %s",
              r["name"], r["target_calls"].size,
              r["coverage"].size, r["error"] ? "ERROR: #{r['error']}" : "")
end
puts "wrote #{out}"
