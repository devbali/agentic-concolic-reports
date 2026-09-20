# MOCK CHECKER — the main per-mock verification driver (plain name for
# what CHECKS.md Part I calls T1 + M2 + C1-shape). Runs against the CLEAN
# app (no concolic mocks installed) so every probe exercises REAL bodies.
#
# Invocation (through the app-booting runner script, coverage needs
# JRuby --debug):
#   JRUBY_OPTS=--debug scripts/diaspora-concolic \
#     /abs/path/reports/diaspora/tools/concrete_checker/mock_checker.rb \
#     /abs/path/<batch>/mock_manifest.rb
#
# The manifest defines MOCK_PROBES, one entry per mock in the batch's
# mock ledger:
#
#   MOCK_PROBES = [
#     { kind: :shim,                       # shim mock: T1 + M2
#       name: "person-name_from_attrs",
#       targets: [[ActiveRecord::FinderMethods, :find_by], ...],
#       coverage_of: [Person, :name_from_attrs, :singleton],
#       fixture: -> { Person.name_from_attrs("a", "b", "h@x") } },
#     { kind: :target_note,                # target mock: note shape check
#       name: "profile-tags-pluck",
#       real_sql: -> { p = Profile.new; p.id = 1; p.tags.select(:name).to_sql },
#       note:     -> { <the note string the mock would emit> } },
#   ]
#
# Verdicts:
#   shim  PASS = zero target-function invocations during fixture AND 100%
#         of the real method's executable lines covered (T1 + M2; a probe
#         that misses a branch can still hide a target call).
#   target_note  PASS = normalized shape equality (tables, table.col in
#         projection and predicates; literals/binds wildcarded).
# Writes mock_checker_report.json next to the manifest; exit 1 on any FAIL.
require "coverage"
Coverage.start
require "json"
require "./config/environment"
require_relative "target_call_probe"

manifest = ARGV[0] or abort "usage: mock_checker.rb <mock_manifest.rb>"
load File.expand_path(manifest)
abort "manifest must define MOCK_PROBES" unless defined?(MOCK_PROBES)

def method_line_range(owner, meth, singleton)
  m = singleton ? owner.method(meth) : owner.instance_method(meth)
  file, start = m.source_location
  return nil unless file && File.exist?(file)
  lines = File.readlines(file)
  depth = 0
  opener = /\b(def|do|if|unless|case|while|until|begin|class|module)\b/
  fin = start
  (start - 1).upto(lines.size - 1) do |i|
    l = lines[i].sub(/#.*$/, "")
    depth += l.scan(opener).size - l.scan(/\bend\b/).size
    # modifier if/unless don't open blocks — but `x = if ...`, `(if ...`,
    # `|| if`, `return if` DO open one (found 2026-08-26: `result = if size`
    # in Profile#image_url was miscounted as a modifier, truncating the
    # range and reporting 100% over lines that never ran)
    mods = l.scan(/\S\s+(if|unless|while|until)\s/).size
    mods -= l.scan(/(=|\(|\|\||&&|,|return)\s+(if|unless|while|until)\s/).size
    depth -= mods if mods > 0
    if depth <= 0
      fin = i + 1
      break
    end
  end
  [file, start, fin]
end

def normalize_sql(sql)
  s = sql.gsub(/\$\$\([^)]*\)/, "?").gsub(/'[^']*'/, "'?'").gsub(/\b\d+\b/, "?")
  tables = s.scan(/\b(?:FROM|JOIN)\s+[`"]?(\w+)[`"]?/i).flatten.map(&:downcase)
  tables += s.scan(/,\s*[`"](\w+)[`"]/).flatten.map(&:downcase)
  cols = s.scan(/[`"]?(\w+)[`"]?\.[`"]?(\w+)[`"]?/).map { |t, c| "#{t.downcase}.#{c.downcase}" }
  { tables: tables.uniq.sort, cols: cols.uniq.sort }
end

results = []
MOCK_PROBES.each do |probe|
  name = probe[:name]
  begin
    case probe[:kind]
    when :shim
      calls = CompletionChecker::TargetCallProbe.capture(
        targets: probe[:targets], raise_on_call: probe[:raise_on_call] || false,
        &probe[:fixture])
      cov = Coverage.peek_result rescue Coverage.result(stop: false, clear: false)
      owner, meth, sing = probe[:coverage_of]
      range = method_line_range(owner, meth, sing == :singleton)
      if range
        file, s, f = range
        counts = (cov[file] || [])[s - 1...f] || []
        executable = counts.each_index.select { |i| counts[i] }
        missed = executable.select { |i| counts[i] == 0 }.map { |i| s + i }
        cov_ok = missed.empty? && !executable.empty?
        cov_msg = cov_ok ? "100% (#{executable.size} lines)" :
                  "MISSED lines #{missed.first(8).inspect} of #{file}:#{s}-#{f}" \
                  "#{executable.empty? ? ' (no coverage data — JRuby needs --debug)' : ''}"
      else
        cov_ok, cov_msg = false, "method source not found"
      end
      ok = calls.empty? && cov_ok
      results << { "name" => name, "kind" => "shim", "pass" => ok,
                   "target_calls" => calls.map { |c| c["target"] }.uniq,
                   "coverage" => cov_msg }
    when :target_note
      real = normalize_sql(probe[:real_sql].call.to_s)
      note = normalize_sql((probe[:note].respond_to?(:call) ? probe[:note].call : probe[:note]).to_s)
      ok = real == note
      results << { "name" => name, "kind" => "target_note", "pass" => ok,
                   "real" => real, "note" => note }
    else
      results << { "name" => name, "pass" => false, "error" => "unknown kind #{probe[:kind]}" }
    end
  rescue => e
    results << { "name" => name, "pass" => false,
                 "error" => "#{e.class}: #{e.message[0, 120]}" }
  end
end

report = File.join(File.dirname(File.expand_path(manifest)), "mock_checker_report.json")
File.write(report, JSON.pretty_generate(results))

failed = results.reject { |r| r["pass"] }
results.each do |r|
  status = r["pass"] ? "PASS" : "FAIL"
  extra = r["error"] || (r["kind"] == "shim" ?
    "targets=#{(r['target_calls'] || []).inspect} coverage=#{r['coverage']}" :
    (r["pass"] ? "" : "real=#{r['real']} note=#{r['note']}"))
  puts format("%-6s %-32s %s", status, r["name"], extra)
end
puts "#{results.size - failed.size}/#{results.size} mocks pass — report: #{report}"
exit(failed.empty? ? 0 : 1)
