#!/usr/bin/env jruby
# frozen_string_literal: true
#
# posts_show — proper concolic exploration (prefix-directed DSE).
#
# PROVENANCE / STATUS (2026-08-14)
# --------------------------------
# This is the reference runner, restored VERBATIM and re-run for this round. It
# reproduced the reference result exactly — 2113 distinct paths, whose coverage
# check gives 2112 tree nodes / 0 missing / complete=true.
#
# It is, however, memory-hungry: it keeps the full search frontier alive as
# materialised Ruby Hashes plus full-text `seen_seeds`/`seen_paths` sets, and
# CallInterceptor#run never trims its @all_calls history. Standalone that is
# tolerable; on the shared box (13 concurrent batch agents, now a hard
# -J-Xmx1000m per JVM) this run reached ~1.8GB RSS and was killed while
# draining the residual worklist.
#
# ../run_dse.rb implements the SAME algorithm made memory-frugal (digest-keyed
# dedup sets, a parent-id worklist instead of per-entry seed dicts, and an
# @all_calls trim) and covers all 9 entrypoints of the batch, posts_show
# included. Prefer it for re-runs; this file is kept as the provenance record.
#
# WHY THIS REPLACES THE OLD coverage_loop.rb
# ------------------------------------------
# The previous loop fed CoverageChecker's `concrete_values` dicts back as
# seed_overrides wholesale. Those dicts are cross-products over vars drawn
# from DIFFERENT runs, and symbolic var names carry the interceptor's
# per-run call ordinal (SYM_RESULT_..._first_1 / _2 / _3, minted at
# src/ruby_runtime/call_interceptor.rb:140). Flipping an EARLY branch
# changes the sequence of intercepted calls, which RENUMBERS every later
# var. Verified in the archived dumps:
#
#   r1: first_1 = EvilQuery visibility SELECT ...        (found)
#       first_2 = stream/interactions SELECT ...
#   r2: first_1 = EvilQuery visibility SELECT ...        (seeded not_found)
#       first_2 = author-fallback SELECT posts.* WHERE id=1 AND author_id=1
#       first_3 = stream/interactions SELECT ...   <-- same query, new name
#
# So a suggestion naming `first_3_*` is meaningless unless the run it is
# applied to has the same execution prefix. Seeding cross-products chased a
# moving target: 100 runs -> 296 tree nodes / 289 missing, never converging.
#
# THE FIX: classic DSE prefix extension. From an observed path
# [c0, c1, ... cn], generate one child per k that keeps the parent's seeds
# (so prefix c0..c_{k-1} replays identically, and the ordinals of those vars
# are therefore identical) and adds exactly ONE flip for c_k. Ordinals are
# assigned in execution order, so a flip at k can only renumber vars AFTER
# k — never the prefix it depends on. Each seed dict is then meaningful for
# the run it is applied to.
#
# This modifies neither src/ (source discipline) nor the shared
# concolic_targets.rb — it is purely a runner-local exploration strategy.
#
# Usage:
#   /home/dev/project/scripts/diaspora-concolic <abs path to this file>
#
# Env: MAX_RUNS (default 1200), TIME_BUDGET seconds (default 3000)

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
# The LIVE framework target declarations, shared by all 13 batches.
require "/home/dev/project/reports/diaspora/concolic_targets"
require "json"
require "set"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)

RESULTS = File.dirname(File.expand_path(__FILE__))

MAX_RUNS    = (ENV["MAX_RUNS"] || 1200).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 3000).to_i

require "action_controller/test_case"

# ---------------------------------------------------------------------------
# Symbolic user — unchanged from the verified coverage_loop.rb harness.
# id stays SYMBOLIC (README: "Symbolic entrypoint variables").
# ---------------------------------------------------------------------------
def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person")
  person.define_singleton_method(:id) { 1 }
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User")
  user.define_singleton_method(:guid) { "abc123" }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:aspects)       { Aspect.all }
  user.define_singleton_method(:aspect_ids)    { [1] }
  user.define_singleton_method(:photos)        { Photo.all }
  user.define_singleton_method(:participations){ Participation.all }
  user.define_singleton_method(:contacts)      { Contact.all }
  user.define_singleton_method(:blocks)        { Block.all }
  user
end

$posts_user = symbolic_user("PO")

def make_harness(controller_class)
  cname = controller_class.to_s.sub(/Controller\z/, "ControllerTest")
  Object.const_set(cname, Class.new(ActionController::TestCase)) unless Object.const_defined?(cname)
  test_class = Object.const_get(cname)
  test_class.instance_variable_set(:@concolic_ctrl, controller_class)
  def test_class.determine_default_controller_class(name)
    @concolic_ctrl
  end
  tc = test_class.new("noop")
  tc.setup_controller_request_and_response
  tc.instance_variable_set(:@routes, Rails.application.routes)
  ctrl = tc.instance_variable_get(:@controller)
  [ctrl, tc]
end

# One execution of the REAL PostsController#show under a seed assignment.
def run_one(label, seeds)
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(PostsController)
  ctrl.singleton_class.define_method(:current_user) { $posts_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { false }
  ctrl.params = { id: 1 }.with_indifferent_access
  $interceptor.run(-> { ctrl.send(:show); :ok }, {}, label: label, script: "run_proper.rb")
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

# ---------------------------------------------------------------------------
# Flip a single path condition.
#
# Every PC this entrypoint emits has the shape "(VAR == LITERAL)" — the
# runtime only tracks equality on symbolic scalars, and boolean predicate
# readers record "(VAR == True)". To force the condition to the desired
# outcome, assign VAR either the literal (taken) or any different value
# (not taken). Returns nil for shapes we cannot invert (e.g. len(...) on a
# SymbolicList); those are counted and reported rather than silently dropped.
# ---------------------------------------------------------------------------
def flip_seed(expr, want_taken)
  m = /\A\(([A-Za-z_][A-Za-z0-9_]*) == (.+)\)\z/m.match(expr.to_s.strip)
  return nil unless m
  var, lit = m[1], m[2].strip

  parsed =
    case lit
    when "True"  then true
    when "False" then false
    when /\A'(.*)'\z/m then Regexp.last_match(1)
    when /\A"(.*)"\z/m then Regexp.last_match(1)
    when /\A-?\d+\z/   then lit.to_i
    else return nil
    end

  value =
    if want_taken
      parsed
    else
      case parsed
      when true, false then !parsed
      when Integer     then parsed + 1
      when String      then parsed.empty? ? "concolic_other" : ""
      else return nil
      end
    end

  { var => value }
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

# ---------------------------------------------------------------------------
# Prefix-directed exploration
# ---------------------------------------------------------------------------
puts "== posts_show :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
started = Time.now

stack       = [{}]
seen_seeds  = Set.new
seen_paths  = Set.new
unflippable = Hash.new(0)
runs        = 0
written     = 0
errors      = Hash.new(0)

until stack.empty?
  if runs >= MAX_RUNS
    puts "[stop] MAX_RUNS reached"
    break
  end
  if Time.now - started > TIME_BUDGET
    puts "[stop] time budget exhausted"
    break
  end

  seeds = stack.pop
  key = JSON.generate(seeds.sort.to_h)
  next if seen_seeds.include?(key)
  seen_seeds << key

  runs += 1
  label = format("dse%04d", runs)

  begin
    dump = run_one(label, seeds)
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts "[#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 120]}"
    errors["harness:#{e.class}"] += 1
    next
  end

  errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

  pcs = path_conditions(dump)
  sig = sig_of(pcs)

  # Only persist genuinely new paths — a repeated path adds nothing to the
  # execution tree and would only inflate the dump count.
  next if seen_paths.include?(sig)

  seen_paths << sig
  written += 1
  File.write(File.join(RESULTS, "dump_#{label}.json"), JSON.pretty_generate(dump))

  if written <= 5 || written % 25 == 0
    puts format("[%s] paths=%d runs=%d pcs=%d stack=%d %s",
                label, written, runs, pcs.size, stack.size,
                dump["error"] ? "error=#{dump['error']['type']}" : "")
  end

  # Expand: one child per branch point, flipping exactly that branch and
  # inheriting the parent's seeds so the prefix replays identically.
  pcs.each_with_index do |(expr, taken), _k|
    fl = flip_seed(expr, !taken)
    if fl.nil?
      unflippable[expr] += 1
      next
    end
    child = seeds.merge(fl)
    ckey = JSON.generate(child.sort.to_h)
    stack.push(child) unless seen_seeds.include?(ckey)
  end
end

elapsed = Time.now - started

summary = {
  "strategy"        => "prefix-directed DSE (seed inheritance + single-branch flip)",
  "runs_executed"   => runs,
  "distinct_paths"  => written,
  "seed_sets_tried" => seen_seeds.size,
  "stack_remaining" => stack.size,
  "worklist_exhausted" => stack.empty?,
  "max_runs"        => MAX_RUNS,
  "elapsed_seconds" => elapsed.round(1),
  "run_errors"      => errors,
  "unflippable_pcs" => unflippable
}
File.write(File.join(RESULTS, "exploration_summary.json"), JSON.pretty_generate(summary))
File.write(File.join(RESULTS, "elapsed_seconds.txt"), "#{elapsed.round(1)}\n")

puts "\n== exploration done =="
puts "  runs executed  : #{runs}"
puts "  distinct paths : #{written}"
puts "  worklist empty : #{stack.empty?}"
puts "  elapsed        : #{elapsed.round(1)}s"
puts "  run errors     : #{errors.inspect}"
puts "  unflippable    : #{unflippable.keys.size} distinct PC shapes"
