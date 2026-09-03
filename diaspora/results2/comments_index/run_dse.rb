#!/usr/bin/env jruby
# frozen_string_literal: true
#
# comments_index — prefix-directed DSE over the REAL CommentsController#index,
# results2 rerun with a FULLY SYMBOLIC params[:post_id].
#
# Ported from ../../results/comments/run_dse.rb, restricted to the single
# comments_index entrypoint (action :index, signed_in: false, format :json —
# index is the one anonymous-reachable action on this controller:
# `before_action :authenticate_user!, except: :index`).
#
# THE POINT OF THIS RERUN (results2/README.md): entrypoint arguments must be
# symbolic. The original comments batch pinned params[:post_id] = "5" as a
# concrete Ruby String, so PostService#find_public! -> Post.where(id: "5")
# rendered a concrete literal bind, never a $$(SYM_PARAM_post_id) one. Here
# params[:post_id] is `symstr("SYM_PARAM_post_id", ...)`, seeded "5" so the
# default run reproduces the original behavior, but the id now flows into the
# WHERE clause as a genuine symbolic bind (verified in the dumps' `note`
# fields on the ActiveRecord::FinderMethods.first symbolic_call event, e.g.
# `SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(SYM_PARAM_post_id)`).
#
# WHY PREFIX-DIRECTED DSE (unchanged rationale from the source batch)
# --------------------------------------------------------------
# The interceptor names every symbolic result with a per-run call ordinal
# (SYM_RESULT_<func>_<idx>, src/ruby_runtime/call_interceptor.rb:140).
# Flipping an early branch changes how many intercepted calls happen before a
# later one, which RENUMBERS every later var. So feeding CoverageChecker's
# `concrete_values` back wholesale as seed_overrides mixes var names harvested
# under different execution prefixes and never converges.
#
# Instead: from an observed path [c0 .. cn] emit one child per k that INHERITS
# the parent's seed dict (so prefix c0..c_{k-1} replays identically and those
# ordinals stay valid) and adds EXACTLY ONE flip for c_k. Dedup on the path
# signature; expand until the worklist drains.
#
# Nothing in src/, the shared concolic_targets.rb, or the diaspora app source
# is modified — this directory carries PRIVATE copies of concolic_targets.rb
# and targets.rb (results2/README.md layout) that this runner requires
# locally, and this runner is a runner-local exploration strategy only.
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
#       /home/dev/project/reports/diaspora/results2/comments_index/run_dse.rb
#
# Env: MAX_RUNS (default 1500), TIME_BUDGET seconds (default 1800)

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
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
$interceptor = CallInterceptor.instance

ConcolicTargets.install!($interceptor)
CommentsTargets.install!($interceptor)

HERE        = File.dirname(File.expand_path(__FILE__))
ENTRY       = "comments_index"
MAX_RUNS    = (ENV["MAX_RUNS"] || 1500).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 1800).to_i

# ---------------------------------------------------------------------------
# comments_index is anonymous (before_action :authenticate_user!, except:
# :index) — current_user is nil, no symbolic_user harness is needed here.
# ---------------------------------------------------------------------------
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

CFG = {
  action: :index, signed_in: false, format: :json,
  param_key: :post_id, param_sym_name: "SYM_PARAM_post_id", param_default: "5"
}.freeze

OUT = HERE

# One execution of the REAL CommentsController#index under a seed assignment.
#
# rescue_from is part of the action's real behaviour (head :not_found /
# authenticate_user!), but it only fires inside AbstractController#process_action.
# We invoke the action body directly (as the verified reference runner does) and
# then dispatch escaping exceptions through the controller's OWN
# `rescue_with_handler`, so the declared rescue_from blocks still run for real.
def run_one(label, seeds)
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(CommentsController)
  ctrl.singleton_class.define_method(:current_user)      { nil }
  ctrl.singleton_class.define_method(:user_signed_in?)   { false }
  # devise's authenticate_user! -> warden, which the controller-test rig has
  # no middleware for. It is a guard, not concolic logic. (Not exercised on
  # the :index action anyway — before_action excepts it — kept for parity.)
  ctrl.singleton_class.define_method(:authenticate_user!) { :authenticate_user_called }

  begin
    ctrl.request.format = CFG[:format]
  rescue StandardError => e
    warn "[warn] could not set request format: #{e.class}"
  end

  action = CFG[:action]
  body = lambda do
    # THE SYMBOLIC ENTRYPOINT ARGUMENT: params[:post_id] is a fresh
    # SymbolicString each run, named SYM_PARAM_post_id, seeded from
    # ConcolicTargets.seed_overrides (falls back to the original "5"). This is
    # what makes the posts lookup's WHERE bind render $$(SYM_PARAM_post_id)
    # instead of a concrete literal.
    #
    # BUGFIX (results2 completion pass, coverage_report.py investigation):
    # this MUST run inside the $interceptor.run(body, ...) block, not before
    # it. CallInterceptor#run calls SymbolicFunc.reset! at its very start
    # (src/ruby_runtime/call_interceptor.rb:262), which clears
    # @registered_vars — including any symstr/symint/symbool call made
    # *before* `run` starts. The original version of this runner called
    # `symstr(CFG[:param_sym_name], ...)` above, outside `body`, so the
    # registration was wiped before the dump snapshot ran and
    # SYM_PARAM_post_id NEVER appeared in any dump's `symbolic_vars` list —
    # even though the var was used correctly everywhere else (SQL binds,
    # the `Length(SYM_PARAM_post_id) < 16` PC). Z3 then couldn't parse that
    # PC (undeclared free variable) and CoverageChecker silently dropped it
    # into `unevaluable_exprs`, excluding the length-dispatch expression
    # from the combination-coverage universe entirely. Moving the
    # declaration inside `body` (after `run` resets state) fixes this.
    post_id_seed = ConcolicTargets.seed_for(CFG[:param_sym_name], CFG[:param_default])
    sym_post_id  = symstr(CFG[:param_sym_name], post_id_seed)
    ctrl.params  = { CFG[:param_key] => sym_post_id }.with_indifferent_access

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

# Flip a single "(VAR == LITERAL)" path condition — the shape emitted by
# scalar-equality comparisons and boolean predicate readers.
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

# NEW for results2: SymbolicString#length on a symbolic entrypoint param is a
# SymbolicInt named "Length(VAR)" (src/ruby_runtime/string.rb:194), and
# PostService#post_key branches on it ("id_or_guid.to_s.length < 16 ? :id :
# :guid") — this branch did not exist when post_id was a concrete String
# (concrete comparisons record no PC). Flip it by seeding VAR with a string
# of the length needed to flip the inequality the OTHER way, so both the
# :id-lookup and :guid-lookup queries get explored.
def flip_length_seed(expr, want_taken)
  m = /\A\(Length\(([A-Za-z_][A-Za-z0-9_]*)\) (<=|>=|==|!=|<|>) (-?\d+)\)\z/m.match(expr.to_s.strip)
  return nil unless m
  var, op, n = m[1], m[2], m[3].to_i

  len =
    case op
    when "<"  then want_taken ? n - 1 : n
    when "<=" then want_taken ? n     : n + 1
    when ">"  then want_taken ? n + 1 : n
    when ">=" then want_taken ? n     : n - 1
    when "==" then want_taken ? n     : n + 1
    when "!=" then want_taken ? n + 1 : n
    else return nil
    end
  len = 0 if len.negative?
  { var => ("g" * len) }
end

def flip_any(expr, want_taken)
  flip_seed(expr, want_taken) || flip_len_seed(expr, want_taken) || flip_length_seed(expr, want_taken)
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

  puts format("[%s] paths=%d runs=%d pcs=%d stack=%d %s",
              label, written, runs, pcs.size, stack.size,
              dump["error"] ? "error=#{dump['error']['type']}" : "")

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
  "params"             => {
    CFG[:param_key].to_s => {
      "symbolic_name" => CFG[:param_sym_name],
      "seed"          => CFG[:param_default]
    }
  },
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
