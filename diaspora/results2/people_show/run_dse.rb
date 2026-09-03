#!/usr/bin/env jruby
# frozen_string_literal: true
#
# people_show — results2 rerun with a FULLY SYMBOLIC entrypoint argument.
#
# Ported from ../../results/people/run_dse.rb, restricted to PeopleController
# #show ONLY, keeping the source batch's single canonical scenario
# ("anon_handle": anonymous, params[:username] = "bob@example.org" — the
# diaspora-handle-shaped username form, which is the one that reaches
# find_person's real `Person.where(diaspora_handle: ...).first` finder; the
# source batch's own header note explains why anonymous is canonical here:
# it avoids the signed-in `mark_corresponding_notifications_read`
# SymbolicList#each wall that would otherwise truncate every path at 2 PCs).
# The source people batch did not explore a signed-in `show` variant (see
# ../../results/people/REPORT.md), so there is no second scenario to port.
#
# THE POINT OF THIS RERUN (results2/README.md + task brief):
#   params[:username] goes from a concrete Ruby String to a genuine
#   SymbolicString (SYM_PARAM_username, seeded "bob@example.org"), so the
#   people lookup's WHERE clause carries a $$(SYM_PARAM_username) bind
#   instead of the literal. See targets.rb §B for the two walls this
#   exposed (diaspora_id?'s lstrip/downcase, and the finder's own downcase)
#   and how each was closed WITHOUT touching src/, concolic_targets.rb, or
#   the app source.
#
# WHY PREFIX-DIRECTED DSE (see BATCH_BRIEFING.md / main README.md): the
# interceptor names symbolic results with a PER-RUN call ordinal
# (SYM_RESULT_<func>_<idx>, call_interceptor.rb:140) — NOT stable across
# runs. Feeding CoverageChecker.concrete_values back wholesale is unsound.
# Instead: from an observed path [c0..cn], emit one child per k that
# INHERITS the parent's seeds (prefix c0..c_{k-1} replays identically) and
# adds exactly one flip for c_k. Dedup on path signature; expand until the
# worklist drains or a cap is hit.
#
# Touches neither src/, the shared concolic_targets.rb, nor the diaspora app
# source — this directory carries PRIVATE copies of concolic_targets.rb and
# targets.rb (results2/README.md layout).
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
#       /home/dev/project/reports/diaspora/results2/people_show/run_dse.rb
#
# Env: MAX_RUNS (default 300), TIME_BUDGET seconds (default 1200).

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require_relative "concolic_targets"
require_relative "targets"
require "json"
require "set"
require "digest"
require "fileutils"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
PeopleTargets.install!($interceptor)          # ported §1-§6, unchanged
PeopleShowSymParams.install!($interceptor)    # NEW: diaspora_id? boundary mock + User#person

HERE        = File.dirname(File.expand_path(__FILE__))
MAX_RUNS    = (ENV["MAX_RUNS"] || 300).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 1200).to_i

# Devise/warden plumbing substitute (no warden env in the controller-test rig).
# Ported verbatim from results/people/run_dse.rb; unused on this scenario's
# anonymous path (current_user is nil) but kept for parity with the source
# harness in case a signed-in variant is added later.
class StubWarden
  def initialize(user)
    @user = user
  end
  def authenticate!(*_a); @user; end
  def authenticated?(*_a); true; end
  def user(*_a); @user; end
end

def make_harness(controller_class)
  cname = controller_class.to_s.sub(/Controller\z/, "ControllerTest")
  Object.const_set(cname, Class.new(ActionController::TestCase)) unless Object.const_defined?(cname)
  test_class = Object.const_get(cname)
  test_class.instance_variable_set(:@concolic_ctrl, controller_class)
  def test_class.determine_default_controller_class(_name); @concolic_ctrl; end
  tc = test_class.new("noop")
  tc.setup_controller_request_and_response
  tc.instance_variable_set(:@routes, Rails.application.routes)
  [tc.instance_variable_get(:@controller), tc]
end

PARAM_SYM_NAME = "SYM_PARAM_username"
PARAM_DEFAULT  = "bob@example.org"

# ---------------------------------------------------------------------------
# One execution of a REAL PeopleController#show under a seed assignment.
# ---------------------------------------------------------------------------
def run_one(label, seeds)
  ConcolicTargets.seed_overrides = seeds
  PeopleTargets.begin_run!
  user = PeopleTargets.symbolic_user("PE") # built fresh; unused as current_user (anon scenario)
  ctrl, tc = make_harness(PeopleController)
  ctrl.singleton_class.define_method(:current_user)    { nil }
  ctrl.singleton_class.define_method(:user_signed_in?) { false }
  tc.instance_variable_get(:@request).env["warden"] = StubWarden.new(user)

  sym_username = PeopleShowSymParams.symbolic_username(PARAM_DEFAULT)

  dump = $interceptor.run(
    -> {
      tc.process(:show, method: "GET", params: { username: sym_username }, format: nil)
      :ok
    },
    {}, label: label, script: "run_dse.rb"
  )
  # RUNNER-LOCAL MEMORY TRIM (src/ gap, reported — do not patch src/):
  # CallInterceptor keeps an unbounded @all_calls history across runs
  # (call_interceptor.rb — #run only ever reads the slice belonging to the
  # current run). Clearing between runs is behaviour-preserving.
  $interceptor.instance_variable_get(:@all_calls).clear
  dump
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

# ---------------------------------------------------------------------------
# Flip a single path condition — ported verbatim from
# results/people/run_dse.rb (handles ==, !=, len(...) != 0 / == 0, and
# integer ordering <=/</>=/> exactly, since every PC in this app compares a
# var to a literal — see that file's comment for why the boundary assignment
# is exact, not heuristic). This app's PCs include the ConcolicDate
# birthday_year <= 1004 ordering compare (dump_anon_handle_0002.json in the
# source batch), so the ordering branch is required here too.
# ---------------------------------------------------------------------------
def parse_literal(lit)
  case lit
  when "True"  then true
  when "False" then false
  when /\AStringVal\('(.*)'\)\z/m then Regexp.last_match(1)
  when /\A'(.*)'\z/m then Regexp.last_match(1)
  when /\A"(.*)"\z/m then Regexp.last_match(1)
  when /\A-?\d+\z/   then lit.to_i
  end
end

def other_value(parsed)
  case parsed
  when true, false then !parsed
  when Integer     then parsed + 1
  when String      then parsed.empty? ? "concolic_other" : ""
  end
end

def flip_seed(expr, want_taken)
  s = expr.to_s.strip

  if (m = /\A\(len\((.+)\) != 0\)\z/m.match(s))
    return { "len(#{m[1]})" => (want_taken ? 1 : 0) }
  end
  if (m = /\A\(len\((.+)\) == 0\)\z/m.match(s))
    return { "len(#{m[1]})" => (want_taken ? 0 : 1) }
  end

  if (m = /\A\(([A-Za-z_][A-Za-z0-9_]*) (<=|>=|<|>) (-?\d+)\)\z/m.match(s))
    var, op, n = m[1], m[2], m[3].to_i
    value =
      case op
      when "<=" then want_taken ? n : n + 1
      when "<"  then want_taken ? n - 1 : n
      when ">=" then want_taken ? n : n - 1
      when ">"  then want_taken ? n + 1 : n
      end
    return { var => value }
  end

  m = /\A\(([A-Za-z_][A-Za-z0-9_]*) (==|!=) (.+)\)\z/m.match(s)
  return nil unless m
  var, op, lit = m[1], m[2], m[3].strip

  parsed = parse_literal(lit)
  return nil if parsed.nil?

  equal_wanted = (op == "==") ? want_taken : !want_taken
  value = equal_wanted ? parsed : other_value(parsed)
  return nil if value.nil?

  { var => value }
end

# ---------------------------------------------------------------------------
# Prefix-directed DSE over the single "anon_handle" scenario.
# ---------------------------------------------------------------------------
DIR = HERE
FileUtils.mkdir_p(DIR)
Dir.glob(File.join(DIR, "dump_*.json")).each { |f| File.delete(f) }

started     = Time.now
seen_paths  = Set.new
seen_seeds  = Set.new
unflippable = Hash.new(0)
errors      = Hash.new(0)
runs        = 0
written     = 0
capped      = nil

puts "\n=== people_show :: prefix-directed DSE (anon_handle) ==="

stack = [[{}, 0]]
first_run = true

until stack.empty?
  if runs >= MAX_RUNS
    capped = "MAX_RUNS"
    break
  end
  if Time.now - started > TIME_BUDGET
    capped = "TIME_BUDGET"
    break
  end

  seeds, min_k = stack.pop
  key = Digest::SHA1.hexdigest(JSON.generate(seeds.sort.to_h) + "|#{min_k}")
  next if seen_seeds.include?(key)
  seen_seeds << key

  runs += 1
  label = format("anon_handle_%04d", runs)

  begin
    dump = run_one(label, seeds)
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts "  [#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 200]}"
    errors["harness:#{e.class}"] += 1
    next
  end

  errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

  pcs = path_conditions(dump)
  sig = Digest::SHA1.hexdigest(sig_of(pcs))

  if first_run || !seen_paths.include?(sig)
    seen_paths << sig
    first_run = false
    written += 1
    File.write(File.join(DIR, "dump_#{label}.json"), JSON.pretty_generate(dump))
    puts format("  [%s] paths=%d runs=%d pcs=%d stack=%d %s",
                label, written, runs, pcs.size, stack.size,
                dump["error"] ? "error=#{dump['error']['type']}" : "")
  end

  pcs.each_with_index do |(expr, taken), k|
    next if k < min_k
    fl = flip_seed(expr, !taken)
    if fl.nil?
      unflippable[expr] += 1
      next
    end
    child = seeds.merge(fl)
    ckey = Digest::SHA1.hexdigest(JSON.generate(child.sort.to_h) + "|#{k + 1}")
    stack.push([child, k + 1]) unless seen_seeds.include?(ckey)
  end
end

elapsed = Time.now - started
summary = {
  "entrypoint"      => "people_show",
  "strategy"        => "prefix-directed DSE (seed inheritance + single-branch flip)",
  "scenario"        => {
    "name" => "anon_handle", "action" => "show",
    "params" => { "username" => { "symbolic_name" => PARAM_SYM_NAME, "seed" => PARAM_DEFAULT, "type" => "SymbolicString (SymUsernameString)" } },
    "format" => "nil (html/format.all)", "signed_in" => false, "method" => "GET",
  },
  "runs_executed"      => runs,
  "distinct_paths"     => written,
  "seed_sets_tried"    => seen_seeds.size,
  "worklist_exhausted" => capped.nil?,
  "capped_by"          => capped,
  "max_runs"           => MAX_RUNS,
  "time_budget"        => TIME_BUDGET,
  "elapsed_seconds"    => elapsed.round(1),
  "run_errors"         => errors,
  "unflippable_pcs"    => unflippable,
}
File.write(File.join(DIR, "exploration_summary.json"), JSON.pretty_generate(summary))
puts format("\n== people_show run_dse.rb done: runs=%d paths=%d drained=%s elapsed=%.1fs errors=%s ==",
            runs, written, capped.nil?, elapsed, errors.inspect)
