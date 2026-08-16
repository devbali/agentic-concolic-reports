# frozen_string_literal: true
# ============================================================================
# run_dse.rb — "streams" batch, prefix-directed DSE.
#
# Drives the REAL StreamsController actions (8 entrypoints) through Rails'
# own controller-test machinery. Every path condition in the dumps comes from
# real app code branching on symbolic query results.
#
# WHY PREFIX-DIRECTED DSE (and not the old seed-suggestion loop)
# --------------------------------------------------------------
# The interceptor names symbolic results with a PER-RUN CALL ORDINAL
# (SYM_RESULT_<func>_<idx>, src/ruby_runtime/call_interceptor.rb:140).
# Those names are NOT stable across runs: flipping an early branch changes
# how many intercepted calls happen before a later one and renumbers every
# later var. So feeding CoverageChecker.concrete_values (a cross-product over
# vars harvested from DIFFERENT runs) back as seed_overrides is unsound.
#
# Instead: from an observed path [c0..cn] emit one child per k that INHERITS
# the parent's seed dict (so prefix c0..c_{k-1} replays identically and those
# ordinals stay valid) and adds EXACTLY ONE flip for c_k. Dedup on the path
# signature; expand until the worklist drains or a cap is hit.
#
# Nothing under src/ and nothing in concolic_targets.rb is modified — this is
# purely a runner-local exploration strategy.
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot <abs path to this file>
#
# Env:
#   MODE=explore|dse   (default dse). explore = one default run per
#                      entrypoint per format, printing PCs/errors; writes to
#                      $EXPLORE_DIR, never into the batch result dirs.
#   ONLY=ep1,ep2       restrict to these entrypoints
#   MAX_RUNS           per-entrypoint execution cap (default 900)
#   TIME_BUDGET        per-entrypoint seconds (default 420)
# ============================================================================
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
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

# ---------------------------------------------------------------------------
# BATCH-LOCAL TARGET OVERLAY (results/streams/targets.rb).
#
# All the wall fixes that used to live inline in this runner now live there:
#   1. Post.blocked_people          -> length-SEEDABLE SymbolicList
#   2. Stream::Aspect#aspect_ids    -> nil (was [1]; Arel cannot quote the
#                                      SymbolicList the interceptor re-wraps)
#   3. User#has_hidden_shareables_of_type? -> concrete seed-driven bool
#   4. User#aspect_ids / #followed_tag_ids -> [1]  (pluck is unsupported)
# `declare_target` is last-one-wins, so this overrides the shared §I mocks.
#
# OVERLAY=0 installs ONLY the shared targets — the honest "before" baseline.
# ---------------------------------------------------------------------------
OVERLAY = ENV.fetch("OVERLAY", "1") != "0"
if OVERLAY
  require "/home/dev/project/reports/diaspora/results/streams/targets"
  StreamsTargets.install!($interceptor)
else
  warn "[streams] OVERLAY=0 — shared concolic_targets.rb only (baseline)"
end

RESULTS     = ENV["RESULTS_DIR"] || "/home/dev/project/reports/diaspora/results/streams"
EXPLORE_DIR = ENV["EXPLORE_DIR"] || "/home/dev/.claude/jobs/302ac302/tmp/streams_explore"
MODE        = ENV["MODE"] || "dse"
MAX_RUNS    = (ENV["MAX_RUNS"] || 900).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 420).to_i
ONLY        = (ENV["ONLY"] || "").split(",").map(&:strip).reject(&:empty?)

# ActsAsTaggableOn::Tag (app/models/acts_as_taggable_on-tag.rb) is namespaced;
# used by Stream::FollowedTag / Stream::Multi via user.followed_tags.
begin
  ActsAsTaggableOn::Tag
rescue NameError
  require "/home/dev/project/ruby_examples/dse-apps/apps/diaspora/app/models/acts_as_taggable_on-tag.rb"
end

# ---------------------------------------------------------------------------
# Symbolic current_user. Built INSIDE each run (so seed_overrides apply to its
# column vars and they register into that run's dump). Identity (id/person_id)
# stays concrete because it is fed into REAL where-clauses (Arel quoting a
# SymbolicInt crashes in sql rendering, not an app branch).
# ---------------------------------------------------------------------------
def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user)")
  person.define_singleton_method(:id) { 1 }
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:id) { 1 }
  user.define_singleton_method(:guid) { "abc123" }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:diaspora_handle) { "alice@example.org" }
  user.define_singleton_method(:language) { "en" }
  user.define_singleton_method(:gender)    { "" }
  user.define_singleton_method(:contacts)    { Contact.all }
  user.define_singleton_method(:blocks)      { Block.all }
  user.define_singleton_method(:aspects)     { Aspect.all }
  user.define_singleton_method(:post_default_aspects) { Aspect.all }
  user.define_singleton_method(:post_default_public)  { true }
  # `if current_user.getting_started` (streams_controller.rb:33) and
  # Stream::Multi#welcome? are BARE truthiness on the value — the Ruby
  # truthiness gap (src/TODO.txt) means a SymbolicBool there records NO path
  # condition and is always truthy. Runner-local workaround: return a CONCRETE
  # bool driven by a seed so both sides of that app branch are at least
  # EXECUTED. Reported honestly: this branch is not recordable as a PC.
  user.define_singleton_method(:getting_started) do
    ConcolicTargets.seed_overrides.fetch("USER_GETTING_STARTED", true)
  end
  user.define_singleton_method(:invited_by) { nil }
  # NOTE: `followed_tags`, `aspect_ids`, `followed_tag_ids` and
  # `has_hidden_shareables_of_type?` used to be patched here; they now live in
  # results/streams/targets.rb (StreamsUserOverrides), guarded by
  # `respond_to?(:concolic_attrs)`.

  # OPTIONAL app-query SUBSTITUTION, explored as a separate DSE root so both
  # variants are on record (knob "SUBSTITUTE_USER_VISIBLE_QUERIES").
  #
  # OFF (default): the REAL User::Querying#visible_shareables /
  #   #visible_shareable_ids run. With the targets.rb overlay they now BUILD
  #   correctly (the Arel "can't quote SymbolicList/SymbolicInt" walls are gone)
  #   and reach the database — where BOTH aspects and multi hit the same
  #   remaining wall: visible_shareable_sql emits
  #   "(SELECT ...) UNION ALL (SELECT ...) ORDER BY ... LIMIT ...", which SQLite
  #   (the RAILS_ENV=concolic DB) rejects -> ActiveRecord::StatementInvalid.
  #   That is an ENVIRONMENT wall (the app targets MySQL/PostgreSQL), not a
  #   mocking gap: 8 dumps, all with 0 PCs because it fires before any branch.
  # ON: substitute the query so the DOWNSTREAM real app code (Post.for_a_stream
  #   -> excluding_blocks/excluding_hidden_shareables, Stream::Base#stream_posts)
  #   is reached. This REPLACES app SQL, so it is a root knob, never the default,
  #   and every dump records which variant produced it.
  if ConcolicTargets.seed_overrides["SUBSTITUTE_USER_VISIBLE_QUERIES"]
    user.define_singleton_method(:visible_shareables)    { |*_a| Post.all }
    user.define_singleton_method(:visible_shareable_ids) { |*_a| [1] }
  end
  user
end

class StubWarden
  def initialize(&blk); @blk = blk; end
  def authenticate!(*_); @blk.call; end
  def authenticated?(*_); !@blk.call.nil?; end
  def user(*_); @blk.call; end
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
# One execution of a real StreamsController action under a seed assignment.
# ---------------------------------------------------------------------------
def run_one(cfg, label, seeds)
  ConcolicTargets.seed_overrides = seeds
  # keep the interceptor's global call log from growing without bound
  $interceptor.instance_variable_set(:@all_calls, [])
  $cuser = nil
  # streams#public is the one action with `except: :public` — reachable both
  # anonymously and signed-in. SIGNED_IN is a runner-local root knob (not a
  # symbolic var) so both request shapes are explored under one entrypoint.
  signed_in = seeds.fetch("SIGNED_IN", cfg[:signed_in])
  ctrl, tc = make_harness(StreamsController)
  ctrl.singleton_class.define_method(:current_user)    { signed_in ? $cuser : nil }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  tc.instance_variable_get(:@request).env["warden"] = StubWarden.new { $cuser }
  src = lambda do
    $cuser = symbolic_user("ST") if signed_in
    tc.process(cfg[:action], method: "GET", params: cfg[:params], format: cfg[:format])
    :ok
  end
  $interceptor.run(src, {}, label: label, script: "run_dse.rb")
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

def var_values(dump)
  h = {}
  (dump["symbolic_vars"] || []).each { |v| h[v["name"]] = v["value"] }
  (dump["symbolic_results"] || []).each { |v| h[v["name"]] ||= v["value"] }
  h
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

# Digest-keyed dedup: keep the worklist/seen sets O(40 bytes) per entry instead
# of retaining whole JSON/expression strings (the box runs several JRuby boots
# concurrently under -Xmx1000m).
def seed_key(seeds)
  Digest::SHA1.hexdigest(JSON.generate(seeds.sort_by { |k, _| k.to_s }.to_h))
end

# ---------------------------------------------------------------------------
# Flipping one path condition.
#
# PC exprs this runtime emits (int.rb/bool.rb/string.rb/list.rb):
#   (VAR == LIT) (VAR != LIT) (VAR < LIT) (VAR <= LIT) (VAR > LIT) (VAR >= LIT)
#   (len(NAME) != 0)                          <- SymbolicList empty?/any?
#   (VAR == True)                             <- boolean predicate readers
#   (VAR_A == VAR_B)                          <- symbolic vs symbolic compare
# Every var name here is exactly the seed_overrides key the mock used
# (seed_for(var_name, ...) in concolic_targets.rb), including "len(NAME)".
# Returns a seed Hash, or nil when the shape cannot be inverted (counted and
# reported, never silently dropped).
# ---------------------------------------------------------------------------
OPERAND_VAR = /\A(?:len\()?[A-Za-z_][A-Za-z0-9_]*\)?\z/.freeze

def parse_operand(str)
  s = str.strip
  case s
  when "True"  then [:lit, true]
  when "False" then [:lit, false]
  when "nil", "None" then [:lit, nil]
  when /\A-?\d+\z/ then [:lit, s.to_i]
  when /\A'(.*)'\z/m then [:lit, Regexp.last_match(1)]
  when /\A"(.*)"\z/m then [:lit, Regexp.last_match(1)]
  when OPERAND_VAR then [:var, s]
  else [:unknown, nil]
  end
end

def bump(v)
  case v
  when true, false then !v
  when Integer     then v + 1
  when String      then v.empty? ? "concolic_other" : ""
  end
end

MIRROR = { "==" => "==", "!=" => "!=", "<" => ">", ">" => "<", "<=" => ">=", ">=" => "<=" }.freeze

# value for `target op other` == want
def value_for(op, other, want)
  case op
  when "==" then want ? other : bump(other)
  when "!=" then want ? bump(other) : other
  when "<"  then other.is_a?(Integer) ? (want ? other - 1 : other) : nil
  when "<=" then other.is_a?(Integer) ? (want ? other : other + 1) : nil
  when ">"  then other.is_a?(Integer) ? (want ? other + 1 : other) : nil
  when ">=" then other.is_a?(Integer) ? (want ? other : other - 1) : nil
  end
end

def flip_seed(expr, want_taken, vals)
  m = /\A\((.+?) (==|!=|<=|>=|<|>) (.+)\)\z/m.match(expr.to_s.strip)
  return nil unless m
  lhs, op, rhs = parse_operand(m[1]), m[2], parse_operand(m[3])

  if lhs[0] == :var && rhs[0] == :lit
    target, other, eff = lhs[1], rhs[1], op
  elsif lhs[0] == :lit && rhs[0] == :var
    target, other, eff = rhs[1], lhs[1], MIRROR[op]
  elsif lhs[0] == :var && rhs[0] == :var
    # symbolic-vs-symbolic (e.g. aspects.size == user.aspects.size): move the
    # RHS var relative to the LHS var's concrete value in THIS run.
    return nil unless vals.key?(lhs[1])
    target, other, eff = rhs[1], vals[lhs[1]], MIRROR[op]
  else
    return nil
  end
  return nil if other.nil?

  v = value_for(eff, other, want_taken)
  return nil if v.nil?
  { target => v }
end

# ---------------------------------------------------------------------------
# Entrypoints
# ---------------------------------------------------------------------------
ENTRYPOINTS = {
  "streams_aspects"       => { action: :aspects,       params: { a_ids: [1] }, signed_in: true },
  "streams_public"        => { action: :public,        params: {},             signed_in: false },
  "streams_activity"      => { action: :activity,      params: {},             signed_in: true },
  "streams_multi"         => { action: :multi,         params: {},             signed_in: true },
  "streams_commented"     => { action: :commented,     params: {},             signed_in: true },
  "streams_liked"         => { action: :liked,         params: {},             signed_in: true },
  "streams_mentioned"     => { action: :mentioned,     params: {},             signed_in: true },
  "streams_followed_tags" => { action: :followed_tags, params: {},             signed_in: true },
}.freeze

# streams#multi's `if current_user.getting_started` is a truthiness-gap branch
# (records no PC). Seed BOTH sides as separate DSE roots so both are executed.
# Runner-local root knobs (NOT symbolic vars — they select a request shape or
# a documented workaround variant). Kept in the dedup signature.
KNOBS = ["SIGNED_IN", "USER_GETTING_STARTED", "SUBSTITUTE_USER_VISIBLE_QUERIES",
         "USER_HAS_HIDDEN_SHAREABLES"].freeze

ROOTS = Hash.new { |_h, _k| [{}] }
ROOTS["streams_multi"] = [
  { "USER_GETTING_STARTED" => true },
  { "USER_GETTING_STARTED" => false },
]
# GET /public is reachable anonymously (authenticate_user! except: :public) and
# signed-in; the two shapes execute different code (Post.for_a_stream skips
# excluding_hidden_content entirely when user is nil), so both are roots.
ROOTS["streams_public"] = [
  { "SIGNED_IN" => false },
  { "SIGNED_IN" => true },
]
# aspects/multi are the two actions that go through User::Querying's visible-*
# queries; explore both the real-query variant (walls) and the substituted one.
ROOTS["streams_aspects"] = [{}, { "SUBSTITUTE_USER_VISIBLE_QUERIES" => true }]
ROOTS["streams_multi"] = [
  { "USER_GETTING_STARTED" => true },
  { "USER_GETTING_STARTED" => false },
  { "USER_GETTING_STARTED" => true,  "SUBSTITUTE_USER_VISIBLE_QUERIES" => true },
  { "USER_GETTING_STARTED" => false, "SUBSTITUTE_USER_VISIBLE_QUERIES" => true },
]

# `if user.has_hidden_shareables_of_type?` (post.rb:111) is another bare-`if`
# truthiness-gap branch: targets.rb makes the value a CONCRETE seed-driven bool,
# but no PC ever references it, so DSE can never flip it on its own. Expand it
# into an explicit root wherever a symbolic user exists (skipped for the
# anonymous streams#public root, where `for_a_stream` never touches the user).
if OVERLAY
  ROOTS_HH = {}
  ENTRYPOINTS.each_key do |ep|
    base = ROOTS[ep]
    ROOTS_HH[ep] = base.flat_map do |r|
      next [r] if r["SIGNED_IN"] == false
      [r, r.merge("USER_HAS_HIDDEN_SHAREABLES" => true)]
    end
  end
  ROOTS_HH.each { |ep, v| ROOTS[ep] = v }
end

selected = ENTRYPOINTS.keys
selected = selected.select { |k| ONLY.include?(k) } unless ONLY.empty?

# ===========================================================================
# EXPLORE mode
# ===========================================================================
if MODE == "explore"
  FileUtils.mkdir_p(EXPLORE_DIR)
  selected.each do |ep|
    base = ENTRYPOINTS[ep]
    roots = ROOTS[ep]
    %i[json html].product(roots).each do |fmt, root|
      cfg = base.merge(format: fmt)
      label = "#{ep}_#{fmt}#{roots.size > 1 ? "_#{root.to_a.flatten.join('_')}" : ''}"
      dump = run_one(cfg, label, root)
      File.write(File.join(EXPLORE_DIR, "dump_#{label}.json"), JSON.pretty_generate(dump))
      pcs = path_conditions(dump)
      err = dump["error"]
      puts "[#{label}] PCs=#{pcs.size} error=#{err ? "#{err['type']}: #{err['message'].to_s[0, 110]}" : 'none'}"
      pcs.each { |e, t| puts "    PC #{t ? 'T' : 'F'} #{e}" }
      if err
        (err["traceback"] || "").split("\n").first(6).each { |l| puts "      tb #{l}" }
      end
    end
  end
  exit 0
end

# ===========================================================================
# DSE mode
# ===========================================================================
FMT = (ENV["FORMAT"] || "json").to_sym
overall = {}
t_all = Time.now

selected.each do |ep|
  cfg = ENTRYPOINTS[ep].merge(format: FMT)
  dir = File.join(RESULTS, ep)
  FileUtils.mkdir_p(dir)
  Dir.glob(File.join(dir, "dump_*.json")).each { |f| File.delete(f) }

  puts "\n===== #{ep} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS} TIME_BUDGET=#{TIME_BUDGET}s) ====="
  started = Time.now
  stack       = ROOTS[ep].dup
  seen_seeds  = Set.new
  seen_paths  = Set.new
  unflippable = Hash.new(0)
  errors      = Hash.new(0)
  runs = 0
  written = 0
  stopped = nil
  seed_index = {}

  until stack.empty?
    if runs >= MAX_RUNS
      stopped = "MAX_RUNS"
      break
    end
    if Time.now - started > TIME_BUDGET
      stopped = "TIME_BUDGET"
      break
    end

    seeds = stack.pop
    key = seed_key(seeds)
    next if seen_seeds.include?(key)
    seen_seeds << key

    runs += 1
    label = format("dse%04d", runs)
    begin
      dump = run_one(cfg, label, seeds)
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "  [#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 120]}"
      errors["harness:#{e.class}"] += 1
      next
    end
    errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

    pcs = path_conditions(dump)
    # Dedup on the path signature PLUS the non-symbolic root knobs, so each
    # root variant keeps at least one dump on record even when it produces an
    # identical PC sequence (e.g. the getting_started branch records no PC —
    # Ruby truthiness gap — but both sides really were executed).
    sig = Digest::SHA1.hexdigest(sig_of(pcs) + "||" + KNOBS.map { |k| "#{k}=#{seeds[k].inspect}" }.join(","))
    next if seen_paths.include?(sig)
    seen_paths << sig
    written += 1
    File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
    seed_index[label] = { "seeds" => seeds, "pcs" => pcs.map { |e, t| "#{t ? 'T' : 'F'} #{e}" },
                          "error" => dump["error"] && dump["error"]["type"] }
    if written <= 3 || written % 20 == 0
      puts format("  [%s] paths=%d runs=%d pcs=%d stack=%d %s", label, written, runs,
                  pcs.size, stack.size, dump["error"] ? "error=#{dump['error']['type']}" : "")
    end

    vals = var_values(dump)
    pcs.each do |(expr, taken)|
      fl = flip_seed(expr, !taken, vals)
      if fl.nil?
        unflippable[expr] += 1
        next
      end
      child = seeds.merge(fl)
      stack.push(child) unless seen_seeds.include?(seed_key(child))
    end
  end

  elapsed = Time.now - started
  summary = {
    "entrypoint"         => ep,
    "action"             => cfg[:action].to_s,
    "format"             => FMT.to_s,
    "signed_in"          => cfg[:signed_in],
    "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
    "roots"              => ROOTS[ep],
    "runs_executed"      => runs,
    "distinct_paths"     => written,
    "seed_sets_tried"    => seen_seeds.size,
    "stack_remaining"    => stack.size,
    "worklist_exhausted" => stack.empty?,
    "stopped_by"         => stopped,
    "max_runs"           => MAX_RUNS,
    "time_budget"        => TIME_BUDGET,
    "elapsed_seconds"    => elapsed.round(1),
    "run_errors"         => errors,
    "unflippable_pcs"    => unflippable,
  }
  File.write(File.join(dir, "exploration_summary.json"), JSON.pretty_generate(summary))
  File.write(File.join(dir, "seed_index.json"), JSON.pretty_generate(seed_index))
  overall[ep] = summary
  puts format("  -> runs=%d paths=%d exhausted=%s stopped_by=%s elapsed=%.1fs errors=%s",
              runs, written, stack.empty?, stopped.inspect, elapsed, errors.inspect)
end

File.write(File.join(RESULTS, "exploration_summary.json"), JSON.pretty_generate(overall))
File.write(File.join(RESULTS, "elapsed_seconds.txt"), format("%.1f\n", Time.now - t_all))
puts "\n== streams batch DSE done in #{(Time.now - t_all).round(1)}s =="
