#!/usr/bin/env jruby
# frozen_string_literal: true
# ============================================================================
# run_dse.rb — "likes" batch, prefix-directed DSE (replaces the seed-suggestion
# loop in run_concolic.rb).
#
# WHY
# ---
# The interceptor names mock results with a PER-RUN CALL ORDINAL
# (SYM_RESULT_<func>_<idx>, src/ruby_runtime/call_interceptor.rb:140). Flipping
# an early branch changes how many intercepted calls happen before a later one,
# renumbering every later var. So feeding CoverageChecker.concrete_values back
# wholesale as seed_overrides mixes var names harvested under DIFFERENT
# execution prefixes — unsound, and it does not converge.
#
# Instead: classic DSE prefix extension. From an observed path [c0..cn], emit
# one child per k that INHERITS the parent's seed dict (so the prefix c0..c_{k-1}
# replays identically and those ordinals stay valid) and adds EXACTLY ONE flip
# for c_k. Dedup on the path signature; expand until the worklist drains.
#
# Nothing in src/ or concolic_targets.rb is modified — this is purely a
# runner-local exploration strategy plus runner-local harness plumbing.
#
# Entrypoints (one dir each):
#   likes_create  POST   /posts/:id/likes  -> LikesController#create
#   likes_destroy DELETE /likes/:id        -> LikesController#destroy
#   likes_index   GET    /posts/:id/likes  -> LikesController#index (anonymous)
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot <abs path to this file>
# Env:
#   EP           comma list of entrypoints to run (default: all three)
#   MAX_RUNS     per-entrypoint execution cap  (default 4000)
#   TIME_BUDGET  per-entrypoint seconds        (default 900)
#   DUMP_CAP     per-entrypoint dump cap       (default 1500)
#   SYM_PERSON   "1" (default) = current_user.person.id stays SYMBOLIC so
#                Person#owns? records a real PC; "0" = concrete 1.
#   OUT_DIR      write results here instead of the batch dir (measurement runs)
#   LIKES_CAST_FIX / LIKES_INT_NEXT_SHIM  see results/likes/targets.rb
#
# TERMINATION NOTE (worth porting to the reference runner — see `other_value`
# below): int flips must map into a FINITE domain ({0,1}), not `v + 1`. With
# `v + 1` this batch ran 4000 executions over 3 distinct paths without the
# worklist ever draining, because likes_destroy's PC compares two SYMBOLIC vars
# (`person.id == like.author_id`) so each generation invents a new integer.
# With {0,1} the same worklist drains in 375 executions.
# ============================================================================
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "/home/dev/project/reports/diaspora/results/likes/targets"
require "json"
require "set"
require "digest"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
# Batch-local overlay (TARGETS_ADDENDUM): installs AFTER the shared targets so
# its declarations win. See results/likes/targets.rb for what it does and, more
# importantly, for what it deliberately does NOT close (W-A, W-C).
LikesTargets.install!($interceptor)

# OUT_DIR lets a measurement pass write somewhere other than the batch dir, so
# a "what would the src/ int.rb patch buy us" experiment cannot contaminate the
# delivered results.
RESULTS     = ENV["OUT_DIR"] && !ENV["OUT_DIR"].empty? ? ENV["OUT_DIR"] : File.dirname(File.expand_path(__FILE__))
MAX_RUNS    = (ENV["MAX_RUNS"]    || 4000).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 900).to_i
DUMP_CAP    = (ENV["DUMP_CAP"]    || 1500).to_i
SYM_PERSON  = (ENV["SYM_PERSON"]  || "1") == "1"

require "action_controller/test_case"

# ---------------------------------------------------------------------------
# Runner-local plumbing (app + src are read-only).
#
# `symbolic_instance(Post, ...)` builds records with klass.allocate, so the
# real has_many :likes reader crashes inside AR before any symbolic op is
# reached. That is harness plumbing, not a concolic finding — supply the
# association as a symbolic `Like.all` relation on CONCOLIC instances only
# (guarded by #concolic_attrs, real Posts untouched). Carried over verbatim
# from run_concolic.rb, which is where it was first proven.
# ---------------------------------------------------------------------------
module PostLikeAssociations
  def likes
    respond_to?(:concolic_attrs) ? Like.all : super
  end
end
Post.prepend(PostLikeAssociations)

# ---------------------------------------------------------------------------
# Symbolic current_user. Built INSIDE interceptor.run so (a) its vars are
# declared in the dump's symbolic_vars and (b) seed_overrides actually reach
# them (symbolic_instance reads seed_for at construction time).
#
# person.id is left SYMBOLIC by default (README "Symbolic entrypoint
# variables"): LikeService#destroy -> user.owns?(like) -> Person#owns? does
# `self.id == obj.author_id`, which only records a path condition when the
# receiver is a SymbolicInt. With a concrete `1` it is Integer#== on a
# symbolic arg -> no PC at all (the concrete-receiver gap).
# ---------------------------------------------------------------------------
def build_symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user)")
  person.define_singleton_method(:id) { 1 } unless SYM_PERSON
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:guid) { "abc123" }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:contacts)       { Contact.all }
  user.define_singleton_method(:participations) { Participation.all }
  user
end

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
  [tc.instance_variable_get(:@controller), tc]
end

# ---------------------------------------------------------------------------
# Entrypoint table. Direct action invocation (ctrl.send(action)) is the same
# boundary run_concolic.rb / run_proper.rb use: it runs the REAL action body
# but bypasses process_action, hence also `before_action :authenticate_user!`
# and the `rescue_from Diaspora::NonPublic` handler (reported in REPORT.md).
# ---------------------------------------------------------------------------
#
# `scenarios` = request-format variants. LikesController#create is the only
# action with a `respond_to` block (html -> head :created, mobile -> redirect,
# json -> like.as_api_response), and the format is chosen by the REQUEST, not
# by a symbolic value — so it is not reachable by seed flipping. Each format
# gets its own DSE worklist; all their dumps land in the same entrypoint dir.
# destroy/index render unconditionally, so one scenario each.
ENTRYPOINTS = {
  "likes_create"  => { ctrl: :LikesController, action: :create,
                       params: { post_id: 1 }, anon: false, tag: "LKC",
                       scenarios: %i[html json mobile] },
  "likes_destroy" => { ctrl: :LikesController, action: :destroy,
                       params: { id: 1 }, anon: false, tag: "LKD",
                       scenarios: %i[html] },
  # authenticate_user! except: :index -> genuinely anonymous, so LikeService
  # gets a nil user and PostService takes the real find_public! path.
  "likes_index"   => { ctrl: :LikesController, action: :index,
                       params: { post_id: 1 }, anon: true, tag: "LKI",
                       scenarios: %i[json] }
}.freeze

def run_one(ep, scenario, label, seeds)
  cfg = ENTRYPOINTS.fetch(ep)
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(Object.const_get(cfg[:ctrl]))
  anon = cfg[:anon]
  tag  = cfg[:tag]
  ctrl.singleton_class.define_method(:current_user)   { $concolic_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { !anon }
  begin
    ctrl.request.format = scenario
  rescue StandardError => e
    warn "[#{ep}/#{scenario}] could not set request format: #{e.class}"
  end
  ctrl.params = cfg[:params].merge(format: scenario).with_indifferent_access
  action = cfg[:action]
  dump = $interceptor.run(lambda {
    $concolic_user = anon ? nil : build_symbolic_user(tag)
    ctrl.send(action)
    :ok
  }, {}, label: label, script: "run_dse.rb")
  # RUNNER-LOCAL LEAK WORKAROUND (src/ is read-only): CallInterceptor keeps an
  # UNBOUNDED @all_calls history across runs (src/ruby_runtime/
  # call_interceptor.rb — `@all_calls << TargetCall` per intercepted call, only
  # ever sliced, never trimmed). Over thousands of DSE executions that retains
  # every arg hash + PC snapshot and OOMs the JVM. The dump is already built by
  # the time run() returns, so dropping the history here is safe and changes no
  # recorded output. Reported in REPORT.md rather than patched in src/.
  $interceptor.instance_variable_get(:@all_calls).clear
  dump
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

def var_values(dump)
  h = {}
  (dump["symbolic_vars"] || []).each { |v| h[v["name"]] = v["value"] }
  h
end

# Digest-keyed dedup: keep 32-byte hex keys in the Sets, never the full
# expression / seed JSON strings (memory-frugal — the JVM is capped at 1000m).
def sig_of(pcs)
  Digest::MD5.hexdigest(pcs.map { |e, t| "#{e}:#{t}" }.join("|"))
end

def seed_key(seeds)
  Digest::MD5.hexdigest(JSON.generate(seeds.sort.to_h))
end

# ---------------------------------------------------------------------------
# Branch flipping.
#
# Every PC this app emits has one of these shapes:
#   (VAR == True|False)            symbolic bool / boolean predicate reader
#   (len(VAR) != 0)                SymbolicList empty?/any?
#   (VAR == <int|'str'>)           symbolic scalar vs literal
#   (VAR_A == VAR_B)               two symbolic scalars (Person#owns?:
#                                  person.id == like.author_id)
# Returns a LIST of candidate single-var seed deltas (for the two-var shape
# either side may be the one worth moving; both are enqueued and the path
# signature dedups whatever collides). nil/[] => not invertible, counted and
# reported rather than silently dropped.
# ---------------------------------------------------------------------------
IDENT = /(?:len\([A-Za-z_][A-Za-z0-9_]*\)|[A-Za-z_][A-Za-z0-9_]*)/.freeze
PC_RE = /\A\((#{IDENT}) (==|!=|<|<=|>|>=) (.+)\)\z/m.freeze

def parse_literal(lit)
  case lit
  when "True"  then [true]
  when "False" then [false]
  when /\A'(.*)'\z/m then [Regexp.last_match(1)]
  when /\A"(.*)"\z/m then [Regexp.last_match(1)]
  when /\A-?\d+\z/   then [lit.to_i]
  end
end

# A value guaranteed DIFFERENT from `v`.
#
# TERMINATION: this must be a deterministic INVOLUTION-ish map into a finite
# domain, not `v + 1`. With `v + 1` the DSE never drains: flipping
# `(person_id == author_id)` to false seeds author_id = person_id + 1, the next
# generation sees the new value and seeds +1 again, so the seed space is
# infinite even though the PATH space is 3 paths wide (observed: 4000 runs,
# 3 distinct paths, worklist still growing). Mapping every int to {0,1} keeps
# the reachable seed space finite, so the worklist provably drains.
def other_value(v)
  case v
  when true, false then !v
  when Integer     then v.zero? ? 1 : 0
  when String      then v.empty? ? "concolic_other" : ""
  end
end

# Value for `x` such that `x <op> pivot` evaluates to `want`.
def value_against(pivot, op, want)
  case op
  when "==" then want ? pivot : other_value(pivot)
  when "!=" then want ? other_value(pivot) : pivot
  else
    return nil unless pivot.is_a?(Integer)
    case op
    when "<"  then want ? pivot - 1 : pivot
    when "<=" then want ? pivot     : pivot + 1
    when ">"  then want ? pivot + 1 : pivot
    when ">=" then want ? pivot     : pivot - 1
    end
  end
end

def flip_candidates(expr, want_taken, vars)
  m = PC_RE.match(expr.to_s.strip)
  return [] unless m
  lhs, op, rhs = m[1], m[2], m[3].strip

  lit = parse_literal(rhs)
  if lit
    v = value_against(lit[0], op, want_taken)
    return v.nil? ? [] : [{ lhs => v }]
  end

  return [] unless /\A#{IDENT}\z/.match?(rhs)

  out = []
  if vars.key?(lhs)
    v = value_against(vars[lhs], op, want_taken)
    out << { rhs => v } unless v.nil?
  end
  if vars.key?(rhs)
    # `lhs op rhs` with rhs pivoted: for ==/!= the relation is symmetric;
    # for the ordered comparisons invert the operator when moving lhs.
    inv = { "<" => ">", "<=" => ">=", ">" => "<", ">=" => "<=" }.fetch(op, op)
    v = value_against(vars[rhs], inv, want_taken)
    out << { lhs => v } unless v.nil?
  end
  out
end

# ---------------------------------------------------------------------------
# Prefix-directed exploration of ONE entrypoint.
# ---------------------------------------------------------------------------
def explore(ep)
  dir = File.join(RESULTS, ep)
  require "fileutils"
  FileUtils.mkdir_p(dir)
  Dir.glob(File.join(dir, "dump_*.json")).each { |f| File.delete(f) }

  started        = Time.now
  seen_paths     = Set.new   # shared across scenarios: dedup on the PATH, so a
                             # format variant that reproduces a known path costs
                             # no dump
  unflippable    = Hash.new(0)
  errors         = Hash.new(0)
  error_examples = {}
  runs = 0
  written = 0
  pc_total = 0
  stop_reason = "worklist_drained"
  per_scenario = {}

  ENTRYPOINTS.fetch(ep)[:scenarios].each do |scenario|
    puts "\n== #{ep} [#{scenario}] :: prefix-directed DSE " \
         "(MAX_RUNS=#{MAX_RUNS} TIME_BUDGET=#{TIME_BUDGET}s) =="
    s_runs = 0
    s_written = 0
    # One INDEPENDENT worklist per scenario — a seed set is only meaningful
    # relative to the execution prefix it was derived from, and the request
    # format changes that prefix.
    stack      = [{}]
    seen_seeds = Set.new

  until stack.empty?
    if runs >= MAX_RUNS      then stop_reason = "max_runs";    break end
    if Time.now - started > TIME_BUDGET then stop_reason = "time_budget"; break end
    if written >= DUMP_CAP   then stop_reason = "dump_cap";    break end

    seeds = stack.pop
    key = seed_key(seeds)
    next if seen_seeds.include?(key)
    seen_seeds << key

    runs += 1
    s_runs += 1
    label = format("%s%04d", scenario, s_runs)

    begin
      dump = run_one(ep, scenario, label, seeds)
    rescue Exception => e # rubocop:disable Lint/RescueException
      errors["harness:#{e.class}"] += 1
      error_examples["harness:#{e.class}"] ||= "#{e.message.to_s[0, 200]}"
      puts "  [#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 140]}"
      next
    end

    if dump["error"]
      k = "run:#{dump['error']['type']}"
      errors[k] += 1
      error_examples[k] ||= {
        "message" => dump["error"]["message"].to_s[0, 300],
        "frame"   => dump["error"]["traceback"].to_s.lines.first(3).map(&:strip)
      }
    end

    pcs  = path_conditions(dump)
    vars = var_values(dump)
    sig  = sig_of(pcs)

    # Persist a dump when it is a NEW path, and ALWAYS for the first run of a
    # scenario — otherwise a format variant whose path signature coincides with
    # an already-seen one leaves no artifact at all, and the run that proves the
    # variant executed (e.g. likes#create's format.mobile branch) is invisible.
    if !seen_paths.include?(sig) || s_runs == 1
      new_path = seen_paths.add?(sig) ? true : false
      written += 1
      s_written += 1
      pc_total += pcs.size
      File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
      if s_written <= 6 || s_written % 25 == 0
        puts format("  [%s] dumps=%d runs=%d pcs=%d stack=%d new_path=%s %s",
                    label, written, runs, pcs.size, stack.size, new_path,
                    dump["error"] ? "error=#{dump['error']['type']}" : "")
      end
    end

    # Expand: one child per branch point, flipping exactly that branch and
    # inheriting the parent's seeds so the prefix replays identically.
    pcs.each do |expr, taken|
      cands = flip_candidates(expr, !taken, vars)
      if cands.empty?
        unflippable[expr] += 1
        next
      end
      cands.each do |fl|
        child = seeds.merge(fl)
        stack.push(child) unless seen_seeds.include?(seed_key(child))
      end
    end
  end

    per_scenario[scenario.to_s] = {
      "runs" => s_runs, "dumps_written" => s_written,
      "seed_sets_tried" => seen_seeds.size,
      "stack_remaining" => stack.size,
      "worklist_exhausted" => stack.empty?
    }
    puts "  [#{scenario}] runs=#{s_runs} dumps=#{s_written} " \
         "drained=#{stack.empty?} stack=#{stack.size}"
  end

  drained = per_scenario.values.all? { |s| s["worklist_exhausted"] }
  stop_reason = "worklist_drained" if drained && stop_reason == "worklist_drained"
  elapsed = Time.now - started
  summary = {
    "endpoint"           => ep,
    "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
    "runs_executed"      => runs,
    "dumps_written"      => written,
    "distinct_paths"     => seen_paths.size,
    "path_conditions_in_dumps" => pc_total,
    "scenarios"          => per_scenario,
    "seed_sets_tried"    => per_scenario.values.sum { |s| s["seed_sets_tried"] },
    "stack_remaining"    => per_scenario.values.sum { |s| s["stack_remaining"] },
    "worklist_exhausted" => drained,
    "stop_reason"        => stop_reason,
    "max_runs"           => MAX_RUNS,
    "time_budget"        => TIME_BUDGET,
    "elapsed_seconds"    => elapsed.round(1),
    "run_errors"         => errors,
    "run_error_examples" => error_examples,
    "unflippable_pcs"    => unflippable,
    "sym_person_id_symbolic" => SYM_PERSON
  }
  File.write(File.join(dir, "exploration_summary.json"), JSON.pretty_generate(summary))
  puts "  -> #{ep}: runs=#{runs} paths=#{written} drained=#{drained} (#{stop_reason}) #{elapsed.round(1)}s"
  puts "     errors: #{errors.inspect}"
  puts "     unflippable: #{unflippable.keys.size} distinct shapes #{unflippable.keys.first(4).inspect}"
  summary
end

selected = (ENV["EP"] && !ENV["EP"].empty?) ? ENV["EP"].split(",").map(&:strip) : ENTRYPOINTS.keys
t0 = Time.now
all = selected.map { |ep| explore(ep) }
File.write(File.join(RESULTS, "exploration_index.json"), JSON.pretty_generate(all))
File.write(File.join(RESULTS, "elapsed_seconds.txt"), format("%.1f\n", Time.now - t0))
puts "\n== likes batch DSE done in #{(Time.now - t0).round(1)}s =="
