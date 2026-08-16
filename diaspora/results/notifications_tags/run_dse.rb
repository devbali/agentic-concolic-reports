# frozen_string_literal: true
#
# run_dse.rb — "notifications_tags" batch, prefix-directed DSE.
#
# Replaces the old run_concolic.rb / run_concolic_seeds.rb workflow (defaults
# run -> feed CoverageChecker.concrete_values back as seed_overrides). That
# workflow is UNSOUND here: symbolic var names carry the interceptor's per-run
# call ordinal (SYM_RESULT_<func>_<idx>, src/ruby_runtime/call_interceptor.rb),
# so flipping an early branch renumbers every later var and a suggestion
# harvested from run A can name a different query in run B.
#
# Instead: classic DSE prefix extension. From an observed path [c0..cn], emit
# one child per k that INHERITS the parent's seed dict (prefix c0..c_{k-1}
# replays identically, so those ordinals stay valid) and adds EXACTLY ONE flip
# for c_k. Dedup on path signature; expand until the worklist drains.
#
# Neither src/ nor the shared concolic_targets.rb is modified — this is purely
# a runner-local exploration strategy.
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot <abs path to this file>
#
# Env: MAX_RUNS (per entrypoint, default 300), TIME_BUDGET (per entrypoint
#      seconds, default 300), ONLY (comma-separated entrypoint filter).

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "/home/dev/project/reports/diaspora/results/notifications_tags/targets"
require "json"
require "set"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

# Batch-local wall fixes live in results/notifications_tags/targets.rb and are
# installed AFTER the shared targets (declare_target is last-one-wins). That
# file also carries the ActsAsTaggableOn::Tag constant load, which used to sit
# here runner-locally.
$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
NotificationsTagsTargets.install!($interceptor)

RESULTS     = File.dirname(File.expand_path(__FILE__))
MAX_RUNS    = (ENV["MAX_RUNS"] || 300).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 300).to_i
ONLY        = (ENV["ONLY"] || "").split(",").map(&:strip).reject(&:empty?)

# ---------------------------------------------------------------------------
# Harness (same shape as the batch's original run_concolic.rb).
#
# The symbolic user is rebuilt PER RUN, after seed_overrides is set, so its
# column vars (SYM_USER_NT_*, SYM_PERSON_NT_*) are seedable by the DSE like
# any other symbolic var. Their names are content-derived (not ordinal), so
# they are stable across runs.
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
  user.define_singleton_method(:gender) { "" }
  user.define_singleton_method(:contacts) { Contact.all }
  user.define_singleton_method(:blocks) { Block.all }
  user.define_singleton_method(:aspects) { Aspect.all }
  user.define_singleton_method(:post_default_aspects) { Aspect.all }
  user.define_singleton_method(:post_default_public) { true }
  user.define_singleton_method(:invited_by) { nil }
  user.define_singleton_method(:followed_tags) { ActsAsTaggableOn::Tag.all }
  user.define_singleton_method(:unread_notifications) { Notification.all }
  user.define_singleton_method(:tag_followings) { TagFollowing.all }
  user.define_singleton_method(:visible_shareables) { |*_a| Post.all }
  user
end

class StubWarden
  def initialize(user); @user = user; end
  def authenticate!(*_); @user; end
  def authenticated?(*_); true; end
  def user(*_); @user; end
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

def run_one(spec, scn, label, seeds)
  ConcolicTargets.seed_overrides = seeds
  user = symbolic_user("NT")
  ctrl, tc = make_harness(spec[:ctrl])
  signed_in = scn.fetch(:signed_in, true)
  ctrl.singleton_class.define_method(:current_user)    { signed_in ? user : nil }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  tc.instance_variable_get(:@request).env["warden"] = StubWarden.new(user)
  dump = $interceptor.run(
    lambda {
      tc.process(spec[:action], method: scn.fetch(:method, "GET"),
                                params: scn[:params], format: scn[:format])
      :ok
    },
    {}, label: label, script: "run_dse.rb"
  )
  # RUNNER-LOCAL WORKAROUND for a src/ruby_runtime leak (reported, not patched):
  # CallInterceptor keeps an unbounded @all_calls history across runs — every
  # intercepted call of every run stays resident, so a long DSE grows without
  # bound. #run only ever reads @all_calls[old_count..], so dropping the
  # history after each run is behaviour-neutral for the dumps.
  hist = $interceptor.instance_variable_get(:@all_calls)
  hist.clear if hist.respond_to?(:clear)
  dump
end

# ---------------------------------------------------------------------------
# PC extraction + flipping
# ---------------------------------------------------------------------------
def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

def parse_literal(lit)
  case lit
  when "True"  then true
  when "False" then false
  when /\A'(.*)'\z/m then Regexp.last_match(1)
  when /\A"(.*)"\z/m then Regexp.last_match(1)
  when /\A-?\d+\z/   then lit.to_i
  end
end

# Flip a single path condition to the desired outcome by assigning its
# variable. Handles every PC shape this runtime emits:
#   (VAR == LIT)      scalar equality / boolean predicate readers ("== True")
#   (VAR != LIT)      inequality; (len(X) != 0) from SymbolicList empty?/any?;
#                     (VAR != 0) from SymbolicInt zero?/nonzero?
#   (VAR < N) (VAR <= N) (VAR > N) (VAR >= N)   SymbolicInt ordering
# Returns nil for shapes we cannot invert (those are counted and reported,
# never silently dropped). `len(X)` is a legal seed key: the collection mocks
# read seed_for("len(<name>_rows)", 1).
def flip_seed(expr, want_taken)
  m = /\A\((\S+) (==|!=|<=|>=|<|>) (.+)\)\z/m.match(expr.to_s.strip)
  return nil unless m
  var, op, lit = m[1], m[2], m[3].strip
  parsed = parse_literal(lit)
  return nil if parsed.nil? && !%w[True False].include?(lit)

  other = lambda do |v|
    case v
    when true, false then !v
    when Integer     then v + 1
    when String      then v.empty? ? "concolic_other" : ""
    end
  end

  value =
    case op
    when "==" then want_taken ? parsed : other.call(parsed)
    when "!=" then want_taken ? other.call(parsed) : parsed
    when "<"  then parsed.is_a?(Integer) ? (want_taken ? parsed - 1 : parsed + 1) : nil
    when "<=" then parsed.is_a?(Integer) ? (want_taken ? parsed : parsed + 1) : nil
    when ">"  then parsed.is_a?(Integer) ? (want_taken ? parsed + 1 : parsed - 1) : nil
    when ">=" then parsed.is_a?(Integer) ? (want_taken ? parsed : parsed - 1) : nil
    end
  return nil if value.nil?

  { var => value }
end

# ---------------------------------------------------------------------------
# Entrypoints, each with one or more REQUEST SCENARIOS.
#
# Why scenarios: branches on request params (params[:type], params[:show],
# params[:set_unread], params[:q].length, request.format, user_signed_in?) are
# NOT symbolic — ActionController parses request params into plain Strings, so
# those comparisons record NO path condition. The concolic search cannot reach
# them by flipping seeds. Driving each concrete request shape as its own DSE
# ROOT is the honest substitute: it exercises the app path and reveals the wall
# on it, without fabricating any path condition. Every scenario is explored
# with the same prefix-directed flipping, so symbolic branches reached only
# under one scenario still get both sides.
# ---------------------------------------------------------------------------
ENTRYPOINTS = [
  { ep: "notifications_index", ctrl: NotificationsController, action: :index,
    scenarios: [
      { name: "plain",       params: {}, format: :json },
      { name: "typed",       params: { type: "liked" }, format: :json },
      { name: "unread_only", params: { show: "unread", page: 2, per_page: 5 }, format: :json }
    ] },
  { ep: "notifications_update", ctrl: NotificationsController, action: :update,
    scenarios: [
      { name: "mark_read",   params: { id: 1 }, method: "PUT", format: :json },
      { name: "mark_unread", params: { id: 1, set_unread: "true" }, method: "PUT", format: :json }
    ] },
  { ep: "notifications_read_all", ctrl: NotificationsController, action: :read_all,
    scenarios: [
      { name: "plain", params: {}, format: :json },
      { name: "typed", params: { type: "mentioned" }, format: :json }
    ] },
  { ep: "tags_index", ctrl: TagsController, action: :index,
    scenarios: [
      { name: "query",       params: { q: "ruby" }, format: :json },
      { name: "hash_query",  params: { q: "#ruby", limit: 5 }, format: :json },
      { name: "short_query", params: { q: "r" }, format: :json }
    ] },
  { ep: "tags_show", ctrl: TagsController, action: :show,
    scenarios: [
      { name: "lower",    params: { name: "testtag", page: 1 }, format: :json },
      { name: "capitals", params: { name: "TestTag", page: 1 }, format: :json },
      { name: "anon",     params: { name: "testtag", page: 1 }, format: :json, signed_in: false }
    ] },
  { ep: "tag_followings_index", ctrl: TagFollowingsController, action: :index,
    scenarios: [{ name: "plain", params: {}, format: :json }] },
  { ep: "tag_followings_create", ctrl: TagFollowingsController, action: :create,
    scenarios: [
      { name: "named", params: { name: "cooltag" }, method: "POST", format: :json },
      { name: "blank", params: { name: "" },        method: "POST", format: :json }
    ] },
  { ep: "tag_followings_destroy", ctrl: TagFollowingsController, action: :destroy,
    scenarios: [{ name: "by_tag_id", params: { id: "1" }, method: "DELETE", format: :json }] },
  { ep: "tag_followings_manage", ctrl: TagFollowingsController, action: :manage,
    scenarios: [
      { name: "html",   params: {}, format: :html },
      { name: "mobile", params: {}, format: :mobile }
    ] },
].freeze

# ---------------------------------------------------------------------------
# Per-entrypoint prefix-directed exploration
# ---------------------------------------------------------------------------
def explore(spec)
  ep  = spec[:ep]
  dir = File.join(RESULTS, ep)
  Dir.mkdir(dir) unless Dir.exist?(dir)
  Dir.glob(File.join(dir, "dump_*.json")).each { |f| File.delete(f) }

  puts "\n== #{ep} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
  started = Time.now

  # One DSE root per request scenario; the scenario index rides along on the
  # worklist so a flip stays inside the scenario that produced it.
  scenarios   = spec[:scenarios]
  stack       = scenarios.each_index.map { |i| [i, {}] }.reverse
  seen_seeds  = Set.new
  seen_paths  = Set.new
  unflippable = Hash.new(0)
  errors      = Hash.new(0)
  runs        = 0
  written     = 0
  max_pcs     = 0

  until stack.empty?
    if runs >= MAX_RUNS
      puts "[stop] MAX_RUNS reached"
      break
    end
    if Time.now - started > TIME_BUDGET
      puts "[stop] time budget exhausted"
      break
    end

    si, seeds = stack.pop
    scn = scenarios[si]
    key = "#{si}|#{JSON.generate(seeds.sort.to_h)}"
    next if seen_seeds.include?(key)
    seen_seeds << key

    runs += 1
    label = format("%s_dse%04d", scn[:name], runs)

    begin
      dump = run_one(spec, scn, label, seeds)
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "[#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 140]}"
      errors["harness:#{e.class}"] += 1
      next
    end

    errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

    pcs = path_conditions(dump)
    max_pcs = pcs.size if pcs.size > max_pcs
    # Dedup per scenario: a repeated path within a scenario adds nothing to the
    # tree, but the SAME signature under a different scenario is a different
    # concrete request shape (often a different wall) and is kept.
    sig = "#{si}|#{sig_of(pcs)}"

    next if seen_paths.include?(sig)

    seen_paths << sig
    written += 1
    dump["concolic_seeds"] = seeds
    dump["concolic_scenario"] = scn.reject { |k, _| k == :params }
                                   .merge(params: scn[:params].to_s)
    File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))

    if written <= 3 || written % 20 == 0
      puts format("  [%s] paths=%d runs=%d pcs=%d stack=%d %s",
                  label, written, runs, pcs.size, stack.size,
                  dump["error"] ? "error=#{dump['error']['type']}" : "")
    end

    pcs.each do |expr, taken|
      fl = flip_seed(expr, !taken)
      if fl.nil?
        unflippable[expr] += 1
        next
      end
      child = seeds.merge(fl)
      ckey = "#{si}|#{JSON.generate(child.sort.to_h)}"
      stack.push([si, child]) unless seen_seeds.include?(ckey)
    end
  end

  elapsed = Time.now - started
  summary = {
    "entrypoint"         => ep,
    "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip), one root per request scenario",
    "scenarios"          => scenarios.map { |s| { "name" => s[:name], "params" => s[:params].to_s,
                                                  "format" => s[:format].to_s,
                                                  "signed_in" => s.fetch(:signed_in, true) } },
    "runs_executed"      => runs,
    "distinct_paths"     => written,
    "seed_sets_tried"    => seen_seeds.size,
    "stack_remaining"    => stack.size,
    "worklist_exhausted" => stack.empty?,
    "max_pcs_on_a_path"  => max_pcs,
    "max_runs"           => MAX_RUNS,
    "time_budget"        => TIME_BUDGET,
    "elapsed_seconds"    => elapsed.round(1),
    "run_errors"         => errors,
    "unflippable_pcs"    => unflippable
  }
  File.write(File.join(dir, "exploration_summary.json"), JSON.pretty_generate(summary))
  puts format("  -> runs=%d paths=%d drained=%s maxpcs=%d elapsed=%.1fs errors=%s",
              runs, written, stack.empty?, max_pcs, elapsed, errors.inspect)
  summary
end

batch_started = Time.now
all = []
ENTRYPOINTS.each do |spec|
  next if !ONLY.empty? && !ONLY.include?(spec[:ep])
  all << explore(spec)
end
batch_elapsed = Time.now - batch_started

File.write(File.join(RESULTS, "exploration_summary.json"),
           JSON.pretty_generate({ "batch" => "notifications_tags",
                                  "elapsed_seconds" => batch_elapsed.round(1),
                                  "entrypoints" => all }))
File.write(File.join(RESULTS, "elapsed_seconds.txt"), "#{batch_elapsed.round(1)}\n")
puts "\n== batch done in #{batch_elapsed.round(1)}s =="
