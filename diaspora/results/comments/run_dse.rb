#!/usr/bin/env jruby
# frozen_string_literal: true
#
# comments batch — prefix-directed DSE over the REAL CommentsController.
#
# WHY PREFIX-DIRECTED DSE (and not the old seed-suggestion loop)
# --------------------------------------------------------------
# The interceptor names every symbolic result with a per-run call ordinal
# (SYM_RESULT_<func>_<idx>, src/ruby_runtime/call_interceptor.rb:140).
# Flipping an early branch changes how many intercepted calls happen before a
# later one, which RENUMBERS every later var. So feeding CoverageChecker's
# `concrete_values` back wholesale as seed_overrides mixes var names harvested
# under different execution prefixes and never converges.
#
# Instead: from an observed path [c0 .. cn] emit one child per k that INHERITS
# the parent's seed dict (so the prefix c0..c_{k-1} replays identically and
# those ordinals stay valid) and adds EXACTLY ONE flip for c_k. Dedup on the
# path signature; expand until the worklist drains.
#
# Every PC this app emits has the shape "(VAR == LITERAL)", so a flip is just
# assigning VAR the literal (taken) or any different value (not taken).
#
# Nothing in src/ or concolic_targets.rb is modified — this is a runner-local
# exploration strategy only.
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
#       /home/dev/project/reports/diaspora/results/comments/run_dse.rb <entrypoint>
#
#   <entrypoint>: comments_create | comments_index | comments_new | comments_destroy
#
# Env: MAX_RUNS (default 1500), TIME_BUDGET seconds (default 1800)

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "/home/dev/project/reports/diaspora/results/comments/targets"
require "json"
require "set"
require "digest"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
$interceptor = CallInterceptor.instance

# Shared generic AR interception first, then the BATCH-LOCAL overlay — the
# wall fixes that used to live inline in this runner now live in
# results/comments/targets.rb (see the addendum: the shared concolic_targets.rb
# is the wrong home for batch-specific mocks). `declare_target` uses
# define_method, so the overlay's declarations replace the shared ones.
ConcolicTargets.install!($interceptor)
CommentsTargets.install!($interceptor)

BATCH_DIR   = File.dirname(File.expand_path(__FILE__))
ENTRY       = ARGV[0] or abort("usage: run_dse.rb <entrypoint>")
MAX_RUNS    = (ENV["MAX_RUNS"] || 1500).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 1800).to_i

# ---------------------------------------------------------------------------
# Symbolic current_user — same harness as the verified posts_show reference.
# user.id stays SYMBOLIC (README "Symbolic entrypoint variables"); person.id
# is pinned concrete because it is written into new records as a foreign key
# (AR integer cast -> SymbolicInt#to_i wall) — same as the reference runner.
# ---------------------------------------------------------------------------
def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person")
  person.define_singleton_method(:id) { 1 }
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User")
  user.define_singleton_method(:guid) { "abc123" }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:aspects)        { Aspect.all }
  user.define_singleton_method(:aspect_ids)     { [1] }
  user.define_singleton_method(:photos)         { Photo.all }
  user.define_singleton_method(:participations) { Participation.all }
  user.define_singleton_method(:contacts)       { Contact.all }
  user.define_singleton_method(:blocks)         { Block.all }
  user
end

$cm_user = symbolic_user("CM")

def make_harness(controller_class)
  cname = controller_class.to_s.sub(/Controller\z/, "ControllerTest")
  Object.const_set(cname, Class.new(ActionController::TestCase)) unless Object.const_defined?(cname)
  test_class = Object.const_get(cname)
  test_class.instance_variable_set(:@concolic_ctrl, controller_class)
  def test_class.determine_default_controller_class(_name)
    @concolic_ctrl
  end
  tc = test_class.new("noop")
  tc.setup_controller_request_and_response
  tc.instance_variable_set(:@routes, Rails.application.routes)
  ctrl = tc.instance_variable_get(:@controller)
  [ctrl, tc]
end

# ---------------------------------------------------------------------------
# Entrypoints. `signed_in:false` for comments#index because the real
# controller declares `before_action :authenticate_user!, except: :index` —
# index is the one anonymous-reachable action, and the anonymous branch
# (PostService#find! -> find_public!) is what that route actually exercises.
# ---------------------------------------------------------------------------
ENTRYPOINTS = {
  "comments_create"  => { action: :create,  signed_in: true,
                          params: { post_id: "5", text: "a concolic comment" },
                          format: :json },
  "comments_index"   => { action: :index,   signed_in: false,
                          params: { post_id: "5" },
                          format: :json },
  "comments_new"     => { action: :new,     signed_in: true,
                          params: { post_id: "5" },
                          format: :mobile },
  "comments_destroy" => { action: :destroy, signed_in: true,
                          params: { id: "42" },
                          format: :json },
}.freeze

CFG = ENTRYPOINTS.fetch(ENTRY)
OUT = File.join(BATCH_DIR, ENTRY)
Dir.mkdir(OUT) unless File.directory?(OUT)

# One execution of the REAL CommentsController action under a seed assignment.
#
# rescue_from is part of the action's real behaviour (head :not_found /
# authenticate_user!), but it only fires inside AbstractController#process_action.
# We invoke the action body directly (as the verified reference runner does) and
# then dispatch escaping exceptions through the controller's OWN
# `rescue_with_handler`, so the declared rescue_from blocks still run for real.
def run_one(label, seeds)
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(CommentsController)
  u = CFG[:signed_in] ? $cm_user : nil
  ctrl.singleton_class.define_method(:current_user)      { u }
  ctrl.singleton_class.define_method(:user_signed_in?)   { !u.nil? }
  # devise's authenticate_user! -> warden, which the controller-test rig has
  # no middleware for. It is a guard, not concolic logic.
  ctrl.singleton_class.define_method(:authenticate_user!) { :authenticate_user_called }
  ctrl.params = CFG[:params].with_indifferent_access
  begin
    ctrl.request.format = CFG[:format]
  rescue StandardError => e
    warn "[warn] could not set request format: #{e.class}"
  end

  action = CFG[:action]
  body = lambda do
    begin
      ctrl.send(action)
    rescue Exception => e # rubocop:disable Lint/RescueException
      handled = begin
        ctrl.send(:rescue_with_handler, e)
      rescue Exception # a handler that itself raises -> let the original stand
        nil
      end
      raise e unless handled
      handled
    end
    :ok
  end

  dump = $interceptor.run(body, {}, label: label, script: "run_dse.rb")

  # RUNNER-LOCAL LEAK WORKAROUND (reported, not patched in src/):
  # CallInterceptor keeps an unbounded @all_calls history ACROSS runs
  # (src/ruby_runtime/call_interceptor.rb — `run` only slices
  # @all_calls[old_count..]). Over thousands of DSE executions that retains
  # every TargetCall (args + pc_snapshot) and OOMs the JVM. `run` recomputes
  # old_count at entry, so clearing the array between runs is safe.
  $interceptor.instance_variable_set(:@all_calls, [])

  dump
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

# Flip a single path condition. Every PC this app emits has the shape
# "(VAR == LITERAL)" (the runtime tracks equality on symbolic scalars, and
# boolean predicate readers record "(VAR == True)"). Returns nil for shapes we
# cannot invert (e.g. "(len(X) != 0)" on a SymbolicList) — those are counted
# and reported, never silently dropped.
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

# SymbolicList length PCs "(len(X) != 0)" are flippable too — seed the length.
def flip_len_seed(expr, want_taken)
  m = /\A\((len\(.+\)) != 0\)\z/m.match(expr.to_s.strip)
  return nil unless m
  { m[1] => (want_taken ? 1 : 0) }
end

def flip_any(expr, want_taken)
  flip_seed(expr, want_taken) || flip_len_seed(expr, want_taken)
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

# Memory-frugal dedup: the sets below hold 16-byte digests, never the full
# seed JSON / path-signature strings (the JVM heap is capped at 1000m).
def digest(str)
  Digest::MD5.digest(str)
end

# ---------------------------------------------------------------------------
# Prefix-directed exploration
# ---------------------------------------------------------------------------
puts "== #{ENTRY} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
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
  key = digest(JSON.generate(seeds.sort.to_h))
  next if seen_seeds.include?(key)
  seen_seeds << key

  runs += 1
  label = format("dse%04d", runs)

  begin
    dump = run_one(label, seeds)
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts "[#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 160]}"
    errors["harness:#{e.class}"] += 1
    next
  end

  errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

  pcs = path_conditions(dump)
  sig = digest(sig_of(pcs))

  next if seen_paths.include?(sig)

  seen_paths << sig
  written += 1
  File.write(File.join(OUT, "dump_#{label}.json"), JSON.pretty_generate(dump))

  if written <= 8 || written % 25 == 0
    puts format("[%s] paths=%d runs=%d pcs=%d stack=%d %s",
                label, written, runs, pcs.size, stack.size,
                dump["error"] ? "error=#{dump['error']['type']}" : "")
  end

  pcs.each do |(expr, taken)|
    fl = flip_any(expr, !taken)
    if fl.nil?
      unflippable[expr] += 1
      next
    end
    child = seeds.merge(fl)
    ckey = digest(JSON.generate(child.sort.to_h))
    stack.push(child) unless seen_seeds.include?(ckey)
  end
end

elapsed = Time.now - started

summary = {
  "entrypoint"         => ENTRY,
  "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
  "signed_in"          => CFG[:signed_in],
  "params"             => CFG[:params],
  "request_format"     => CFG[:format].to_s,
  "runs_executed"      => runs,
  "distinct_paths"     => written,
  "seed_sets_tried"    => seen_seeds.size,
  "stack_remaining"    => stack.size,
  "worklist_exhausted" => stack.empty?,
  "max_runs"           => MAX_RUNS,
  "time_budget"        => TIME_BUDGET,
  "elapsed_seconds"    => elapsed.round(1),
  "run_errors"         => errors,
  "unflippable_pcs"    => unflippable
}
File.write(File.join(OUT, "exploration_summary.json"), JSON.pretty_generate(summary))

puts "\n== #{ENTRY} exploration done =="
puts "  runs executed  : #{runs}"
puts "  distinct paths : #{written}"
puts "  worklist empty : #{stack.empty?}"
puts "  elapsed        : #{elapsed.round(1)}s"
puts "  run errors     : #{errors.inspect}"
puts "  unflippable    : #{unflippable.keys.size} distinct PC shapes"
