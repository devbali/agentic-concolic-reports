# frozen_string_literal: true
# ============================================================================
# run_dse.rb — "people" batch, prefix-directed dynamic symbolic execution.
#
# Replaces the old seed-suggestion feedback loop in run_concolic.rb.
#
# WHY (the key insight)
# ---------------------
# The interceptor mints symbolic result names with a PER-RUN CALL ORDINAL
# (SYM_RESULT_<func>_<idx>, src/ruby_runtime/call_interceptor.rb:140).
# Those names are NOT stable across runs: flipping an early branch changes how
# many intercepted calls happen before a later one, renumbering every later
# var. Feeding CoverageChecker.concrete_values (a cross-product harvested from
# DIFFERENT runs) back as seed_overrides is therefore unsound and does not
# converge.
#
# Instead this runner does classic DSE prefix extension: from an observed path
# [c0..cn] it emits one child per k that INHERITS the parent's seed dict (so
# prefix c0..c_{k-1} replays identically and the ordinals of those vars stay
# valid) and adds EXACTLY ONE flip for c_k. Ordinals are assigned in execution
# order, so a flip at k can only renumber vars AFTER k. Paths are deduped on
# their signature; the worklist is expanded until it drains (or a cap trips,
# which is recorded in exploration_summary.json and reported).
#
# SCOPE / HONESTY
# ---------------
# * Neither src/ nor the shared concolic_targets.rb nor the app source is
#   modified. All wall fixes live in the batch-local overlay
#   results/people/targets.rb, installed after the shared targets.
# * ONE canonical request scenario per entrypoint is explored (documented in
#   SCENARIOS below and in REPORT.md). Mixing several request shapes into one
#   entrypoint dir mixes var namespaces and makes the per-entrypoint execution
#   tree meaningless, so alternative shapes were probed separately and are
#   reported as prose, not as dumps. The single exception is
#   people_retrieve_remote, whose two shapes both record ZERO path conditions
#   (nothing to mix).
# * Runs that crash are KEPT — the PCs recorded before the crash are real and
#   the error is reported.
#
# Env: MAX_RUNS (per entrypoint, default 400), TIME_BUDGET (per entrypoint
# seconds, default 600).
#
# Usage: /home/dev/.claude/jobs/302ac302/tmp/concolic-slot <abs path to this file>
# ============================================================================
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "/home/dev/project/reports/diaspora/results/people/targets"
require "json"
require "set"
require "fileutils"
require "digest"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
# Batch-local overlay — see results/people/targets.rb. MUST install after the
# shared targets: declare_target uses define_method, so last one wins.
PeopleTargets.install!($interceptor)

RESULTS   = File.dirname(File.expand_path(__FILE__))
MAX_RUNS    = (ENV["MAX_RUNS"] || 400).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 600).to_i

# Wall fixes previously inlined here (PersonSymAssociations prepend, asset-path
# stub, concrete current-user overrides) now live in results/people/targets.rb,
# together with the new NullRelation short-circuit. This file keeps only the DSE
# algorithm and the request-scenario wiring.

# Devise/warden plumbing substitute (no warden env in the controller-test rig).
class StubWarden
  def initialize(user)
    @user = user
  end
  def authenticate!(*_a); @user; end
  def authenticated?(*_a); true; end
  def user(*_a); @user; end
end

# Built FRESH per run so that seed_overrides apply to the current user's
# symbolic columns too (a user built once at boot would freeze its vars).
# Definition lives in results/people/targets.rb §4.
def symbolic_user(tag)
  PeopleTargets.symbolic_user(tag)
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

# ---------------------------------------------------------------------------
# One execution of a REAL PeopleController action under a seed assignment.
# ---------------------------------------------------------------------------
def run_one(scen, label, seeds)
  ConcolicTargets.seed_overrides = seeds
  # Per-run environment reset (gon RequestStore) — see targets.rb §6.
  PeopleTargets.begin_run!
  user = symbolic_user("PE")
  signed_in = scen[:signed_in]
  ctrl, tc = make_harness(PeopleController)
  ctrl.singleton_class.define_method(:current_user)    { signed_in ? user : nil }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  tc.instance_variable_get(:@request).env["warden"] = StubWarden.new(user)
  dump = $interceptor.run(
    -> {
      tc.process(scen[:action], method: scen[:method] || "GET",
                 params: scen[:params], format: scen[:format])
      :ok
    },
    {}, label: label, script: "run_dse.rb"
  )
  # RUNNER-LOCAL MEMORY TRIM (src/ gap, reported — do not patch src/):
  # CallInterceptor keeps an unbounded @all_calls history for the lifetime of
  # the process (src/ruby_runtime/call_interceptor.rb:69/127). #run only ever
  # reads the slice belonging to the current run (old_count = @all_calls.size
  # at entry), so dropping the history between runs is behaviour-preserving and
  # keeps a multi-thousand-run DSE inside the JRuby heap cap.
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
# Flip a single path condition to the opposite outcome.
#
# PC shapes that occur in this batch:
#   "(VAR == LITERAL)"    scalar equality (finder not_found, boolean predicate
#                         readers, id/guid compares) -> seed VAR
#   "(VAR != LITERAL)"    the companion emitted after an == on the same var
#   "(len(VAR) != 0)"     SymbolicList emptiness (Relation#records/find_by_sql
#                         via blank?/present?) -> seed "len(VAR)" with 1 / 0
#   "(VAR <= INT)" & co.  integer ordering — appears once date columns become
#                         ConcolicDate and PeopleHelper#birthday_format's
#                         `bday.year <= 1004` starts recording instead of
#                         crashing (targets.rb §5a). Every PC in this app
#                         compares a var against a LITERAL, so the boundary
#                         assignment below is exact, not a heuristic.
# Literals are rendered in the engine's Python/Z3 language, so strings arrive
# both as 'x' (SymbolicString#==) and as StringVal('x') (the != companion).
# Anything else is counted in unflippable_pcs and reported, never dropped
# silently.
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

  # Integer ordering: pick the value on the wanted side of the boundary.
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

  # For "!=", "taken" means the var must DIFFER from the literal.
  equal_wanted = (op == "==") ? want_taken : !want_taken
  value = equal_wanted ? parsed : other_value(parsed)
  return nil if value.nil?

  { var => value }
end

# ---------------------------------------------------------------------------
# Entrypoints. One canonical request scenario each (see header note).
# ---------------------------------------------------------------------------
SCENARIOS = {
  # GET /people?q=... — authenticated. The html/mobile branch is the one that
  # reaches app logic (diaspora_id? -> Person.where(...).empty? -> paginate ->
  # hashes_for_people); the json branch just limits + renders.
  "people_index" => [
    { name: "html_handle", action: :index, params: { q: "bob@example.org" },
      format: :html, signed_in: true }
  ],
  # GET /people/:id — anonymous. The diaspora-handle username form drives the
  # real Person.where(...).first finder; anonymous avoids the signed-in
  # mark_corresponding_notifications_read SymbolicList#each wall, which would
  # otherwise truncate every path after 2 PCs.
  "people_show" => [
    { name: "anon_handle", action: :show, params: { username: "bob@example.org" },
      format: nil, signed_in: false }
  ],
  # GET /people/:id/stream — anonymous, default (html) format: format.all ->
  # redirect_to person_path(@person), which additionally exercises
  # Person#to_param -> guid. (The json branch is a strict PC-subset that walls
  # on SymbolicList#map — reported in REPORT.md.)
  "people_stream" => [
    { name: "anon_html", action: :stream, params: { person_id: 1, username: "bob@example.org" },
      format: nil, signed_in: false }
  ],
  # GET /people/:id/hovercard — anonymous json: reaches PersonPresenter#hovercard
  # (base_hash_with_contact -> has_contact? -> Relation#present?), the richest
  # hovercard path. The html branch is just a redirect.
  "people_hovercard" => [
    { name: "anon_json", action: :hovercard, params: { person_id: 1, username: "bob@example.org" },
      format: :json, signed_in: false }
  ],
  # GET /people/refresh_search — authenticated.
  "people_refresh_search" => [
    { name: "auth_handle", action: :refresh_search, params: { q: "bob@example.org" },
      format: nil, signed_in: true }
  ],
  # POST /people/by_handle — both request shapes (they record 0 PCs each, so
  # there is no var namespace to mix).
  "people_retrieve_remote" => [
    { name: "handle",   action: :retrieve_remote, params: { diaspora_handle: "bob@example.org" },
      format: nil, signed_in: true, method: "POST" },
    { name: "nohandle", action: :retrieve_remote, params: {},
      format: nil, signed_in: true, method: "POST" }
  ]
}.freeze

overall = {}
t_all = Time.now

SCENARIOS.each do |entrypoint, scens|
  dir = File.join(RESULTS, entrypoint)
  FileUtils.mkdir_p(dir)
  Dir.glob(File.join(dir, "dump_*.json")).each { |f| File.delete(f) }

  started     = Time.now
  seen_paths  = Set.new
  seen_seeds  = Set.new
  unflippable = Hash.new(0)
  errors      = Hash.new(0)
  runs        = 0
  written     = 0
  capped      = nil

  puts "\n=== #{entrypoint} :: prefix-directed DSE ==="

  scens.each do |scen|
    # Work items are [seeds, min_k]. min_k is the generational bound of classic
    # DSE (SAGE-style): a child produced by flipping condition k only expands
    # conditions at index > k. Conditions before k were already expanded by an
    # ancestor (the prefix replays identically), so re-flipping them would only
    # re-derive paths already in seen_paths — that is exactly the seed-dict
    # blow-up that made the unbounded version hit MAX_RUNS without draining.
    stack = [[{}, 0]]
    first_of_scenario = true

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
      # Digest-keyed dedup sets: keep the worklist memory flat even for a
      # multi-thousand-run exploration (never retain the JSON/expr strings).
      key = Digest::SHA1.hexdigest("#{scen[:name]}|#{JSON.generate(seeds.sort.to_h)}|#{min_k}")
      next if seen_seeds.include?(key)
      seen_seeds << key

      runs += 1
      label = format("%s_%04d", scen[:name], runs)

      begin
        dump = run_one(scen, label, seeds)
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "  [#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 140]}"
        errors["harness:#{e.class}"] += 1
        next
      end

      errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

      pcs = path_conditions(dump)
      sig = Digest::SHA1.hexdigest("#{scen[:name]}|#{sig_of(pcs)}")

      # Persist genuinely new paths only. The first run of each scenario is
      # always persisted, so a 0-PC entrypoint still leaves evidence on disk.
      if first_of_scenario || !seen_paths.include?(sig)
        seen_paths << sig
        first_of_scenario = false
        written += 1
        File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
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
        ckey = Digest::SHA1.hexdigest("#{scen[:name]}|#{JSON.generate(child.sort.to_h)}|#{k + 1}")
        stack.push([child, k + 1]) unless seen_seeds.include?(ckey)
      end
    end

    break if capped
  end

  elapsed = Time.now - started
  summary = {
    "entrypoint"         => entrypoint,
    "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
    "scenarios"          => scens.map { |s| { "name" => s[:name], "action" => s[:action].to_s,
                                              "params" => s[:params], "format" => s[:format].to_s,
                                              "signed_in" => s[:signed_in],
                                              "method" => s[:method] || "GET" } },
    "runs_executed"      => runs,
    "distinct_paths"     => written,
    "seed_sets_tried"    => seen_seeds.size,
    "worklist_exhausted" => capped.nil?,
    "capped_by"          => capped,
    "max_runs"           => MAX_RUNS,
    "time_budget"        => TIME_BUDGET,
    "elapsed_seconds"    => elapsed.round(1),
    "run_errors"         => errors,
    "unflippable_pcs"    => unflippable
  }
  File.write(File.join(dir, "exploration_summary.json"), JSON.pretty_generate(summary))
  overall[entrypoint] = summary
  puts format("  -> runs=%d paths=%d drained=%s elapsed=%.1fs errors=%s",
              runs, written, capped.nil?, elapsed, errors.inspect)
end

File.write(File.join(RESULTS, "exploration_summary.json"), JSON.pretty_generate(overall))
File.write(File.join(RESULTS, "elapsed_seconds.txt"), format("%.1f\n", Time.now - t_all))
puts "\n== people batch DSE done (#{(Time.now - t_all).round(1)}s) =="
