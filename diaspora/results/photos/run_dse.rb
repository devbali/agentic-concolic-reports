# frozen_string_literal: true
# ============================================================================
# run_dse.rb — "photos" batch, prefix-directed dynamic symbolic execution.
#
# WHY THIS REPLACES THE SEED-SUGGESTION LOOP IN run_concolic.rb
# -------------------------------------------------------------
# The interceptor names each intercepted result with a PER-RUN call ordinal
# (SYM_RESULT_<func>_<idx>, src/ruby_runtime/call_interceptor.rb:140). Those
# names are NOT stable across runs: flipping an early branch changes how many
# intercepted calls happen before a later one and renumbers every later var.
# So feeding CoverageChecker's `concrete_values` (a cross-product over vars
# harvested from DIFFERENT runs) back as seed_overrides is unsound.
#
# Instead: classic prefix-directed DSE. From an observed path [c0..cn], emit
# one child per k that INHERITS the parent's seeds (so the prefix c0..c_{k-1}
# replays identically and those ordinals stay valid) and adds EXACTLY ONE
# flip for c_k. Ordinals are assigned in execution order, so a flip at k can
# only renumber vars after k. Dedup on (config, path signature); expand until
# the worklist drains or a cap is hit.
#
# Every PC this app emits has the shape "(VAR == LITERAL)", so flipping is
# just assigning VAR the literal (taken) or a different value (not taken).
#
# The runner drives the REAL controller actions through Rails' own
# ActionController::TestCase machinery. No app logic is replicated here: the
# harness only supplies request / params / current_user plumbing, then invokes
# the real action method. It edits neither src/ nor concolic_targets.rb.
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
#       /home/dev/project/reports/diaspora/results/photos/run_dse.rb
#
# Env:
#   ONLY          comma-separated entrypoint names (default: all)
#   MAX_RUNS      per-entrypoint execution cap        (default 1500)
#   TIME_BUDGET   per-entrypoint seconds              (default 420)
#   TOTAL_BUDGET  whole-batch seconds                 (default 3300)
# ============================================================================
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
# Batch-local wall-fix mocks (see targets.rb). Loaded after the shared
# targets so its declare_target calls override them (last-one-wins).
require "/home/dev/project/reports/diaspora/results/photos/targets"
require "json"
require "set"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
PhotosTargets.install!($interceptor)

RESULTS      = File.dirname(File.expand_path(__FILE__))
MAX_RUNS     = (ENV["MAX_RUNS"] || 1500).to_i
TIME_BUDGET  = (ENV["TIME_BUDGET"] || 420).to_i
TOTAL_BUDGET = (ENV["TOTAL_BUDGET"] || 3300).to_i
ONLY         = (ENV["ONLY"] || "").split(",").map(&:strip).reject(&:empty?)

require "action_controller/test_case"

# ---------------------------------------------------------------------------
# Symbolic current_user.
#
# Built INSIDE each run (see run_one) so that (a) its column vars are declared
# in that run's dump and (b) seed_overrides actually reach them — a user built
# once at load time is frozen and its vars are unflippable.
#
# Identity (id / person_id) is kept CONCRETE: those values only appear inside
# AR WHERE clauses, never branched on, and a symbolic value there crashes
# Arel's quoting (SymbolicInt#hash). Branch-relevant values (query results,
# boolean columns) stay symbolic, so every PC still comes from real app code.
# ---------------------------------------------------------------------------
def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user)")
  person.define_singleton_method(:id) { 1 }
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:id) { 1 }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:photos)         { Photo.all }
  user.define_singleton_method(:participations) { Participation.all }
  user.define_singleton_method(:aspects)        { Aspect.all }
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
# Entrypoint configurations.
#
# Each entrypoint gets one or more "configs". A config is a request shape the
# harness controls concretely (signed-in vs anonymous, params). Those are real
# request inputs, not modeled app behaviour — and they are the only way to
# reach branches the runtime cannot make symbolic (`if user_signed_in?` is a
# plain Ruby bool). DSE then explores seeds INDEPENDENTLY within each config.
# ---------------------------------------------------------------------------
ENTRYPOINTS = {
  "photos_show" => [
    { name: "anon",     ctrl: -> { PhotosController }, action: :show,
      signed_in: false, user: :none, params: { id: 1, person_id: "abc" } },
    { name: "signedin", ctrl: -> { PhotosController }, action: :show,
      signed_in: true,  user: :sym,  params: { id: 1, person_id: "abc" } },
  ],
  "photos_index" => [
    { name: "signedin", ctrl: -> { PhotosController }, action: :index,
      signed_in: true,  user: :sym,  params: { person_id: "abc" } },
    { name: "anon",     ctrl: -> { PhotosController }, action: :index,
      signed_in: false, user: :none, params: { person_id: "abc" } },
  ],
  "photos_create" => [
    { name: "plain",   ctrl: -> { PhotosController }, action: :create, signed_in: true, user: :sym,
      params: { photo: { aspect_ids: ["1"], pending: false, set_profile_photo: false } } },
    { name: "pending", ctrl: -> { PhotosController }, action: :create, signed_in: true, user: :sym,
      params: { photo: { aspect_ids: ["1"], pending: true, set_profile_photo: false } } },
    { name: "setprof", ctrl: -> { PhotosController }, action: :create, signed_in: true, user: :sym,
      params: { photo: { aspect_ids: ["1"], pending: false, set_profile_photo: true } } },
  ],
  "photos_destroy" => [
    { name: "html", ctrl: -> { PhotosController }, action: :destroy,
      signed_in: true, user: :sym, params: { id: 1 } },
  ],
  "photos_make_profile_photo" => [
    { name: "default", ctrl: -> { PhotosController }, action: :make_profile_photo,
      signed_in: true, user: :sym, params: { photo_id: 1 }, format: :js },
  ],
  "participations_create" => [
    { name: "default", ctrl: -> { ParticipationsController }, action: :create,
      signed_in: true, user: :sym, params: { post_id: 1 } },
  ],
  "participations_destroy" => [
    { name: "default", ctrl: -> { ParticipationsController }, action: :destroy,
      signed_in: true, user: :sym, params: { post_id: 1 } },
  ],
  "poll_participations_create" => [
    { name: "default", ctrl: -> { PollParticipationsController }, action: :create,
      signed_in: true, user: :sym, params: { post_id: 1, poll_answer_id: 1 } },
  ],
}.freeze

# ---------------------------------------------------------------------------
# One execution of a real controller action under a seed assignment.
# ---------------------------------------------------------------------------
def run_one(cfg, seeds, label)
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(cfg[:ctrl].call)
  signed_in = cfg[:signed_in]
  want_user = cfg[:user] == :sym
  ctrl.params = cfg[:params].with_indifferent_access
  # HARNESS DECISION (not app modeling), same call the posts batch documented
  # for posts#mentionable / status_messages#create: drive an action with a
  # format its `respond_to` actually handles. photos#make_profile_photo's block
  # has ONLY `format.js` (photos_controller.rb:61), so under the rig's default
  # :html every path raises ActionController::UnknownFormat at the responder —
  # measured 64 of 65 dumps — before the render it is supposed to reach.
  ctrl.request.format = cfg[:format] if cfg[:format]
  $interceptor.run(lambda { |**_kw|
    # Built inside the run so its vars are declared in THIS dump and the
    # current seed assignment reaches its columns.
    u = want_user ? symbolic_user("PH") : nil
    ctrl.singleton_class.define_method(:current_user) { u }
    ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
    ctrl.send(cfg[:action])
    :ok
  }, {}, label: label, script: "run_dse.rb")
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

# Flip a single "(VAR == LITERAL)" path condition to the desired outcome.
# Returns nil for shapes we cannot invert (e.g. len(...) on a SymbolicList);
# those are counted and reported rather than silently dropped.
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

# ---------------------------------------------------------------------------
# Prefix-directed exploration of ONE entrypoint (over all of its configs).
# ---------------------------------------------------------------------------
def explore(ep, configs, deadline_total)
  dir = File.join(RESULTS, ep)
  Dir.mkdir(dir) unless Dir.exist?(dir)
  Dir.glob(File.join(dir, "dump_*.json")).each { |f| File.delete(f) }
  fc = File.join(dir, "coverage_summary.json")
  File.delete(fc) if File.exist?(fc)

  started = Time.now
  # worklist entries: [config index, seed hash]
  stack       = configs.each_index.map { |i| [i, {}] }
  seen_seeds  = Set.new
  seen_paths  = Set.new
  unflippable = Hash.new(0)
  errors      = Hash.new(0)
  per_config  = Hash.new { |h, k| h[k] = { "runs" => 0, "paths" => 0 } }
  runs        = 0
  written     = 0
  stop_reason = "worklist_drained"

  until stack.empty?
    if runs >= MAX_RUNS
      stop_reason = "max_runs"
      break
    end
    if Time.now - started > TIME_BUDGET
      stop_reason = "entrypoint_time_budget"
      break
    end
    if Time.now > deadline_total
      stop_reason = "batch_time_budget"
      break
    end

    ci, seeds = stack.pop
    cfg = configs[ci]
    key = "#{ci}|#{JSON.generate(seeds.sort.to_h)}"
    next if seen_seeds.include?(key)
    seen_seeds << key

    runs += 1
    per_config[cfg[:name]]["runs"] += 1
    label = format("%s_%04d", cfg[:name], runs)

    begin
      dump = run_one(cfg, seeds, label)
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "[#{ep}/#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 140]}"
      errors["harness:#{e.class}"] += 1
      next
    end

    errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

    pcs = path_conditions(dump)
    sig = "#{cfg[:name]}||#{sig_of(pcs)}"
    next if seen_paths.include?(sig)
    seen_paths << sig

    written += 1
    per_config[cfg[:name]]["paths"] += 1
    dump["concolic_seeds"] = seeds
    dump["concolic_config"] = cfg[:name]
    File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))

    if written <= 6 || written % 25 == 0
      puts format("  [%s] path#%d run#%d pcs=%d stack=%d %s",
                  label, written, runs, pcs.size, stack.size,
                  dump["error"] ? "error=#{dump['error']['type']}" : "")
    end

    pcs.each do |(expr, taken)|
      fl = flip_seed(expr, !taken)
      if fl.nil?
        unflippable[expr] += 1
        next
      end
      child = seeds.merge(fl)
      ckey = "#{ci}|#{JSON.generate(child.sort.to_h)}"
      stack.push([ci, child]) unless seen_seeds.include?(ckey)
    end
  end

  elapsed = Time.now - started
  summary = {
    "endpoint"           => ep,
    "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
    "configs"            => configs.map { |c| c[:name] },
    "runs_executed"      => runs,
    "distinct_paths"     => written,
    "seed_sets_tried"    => seen_seeds.size,
    "stack_remaining"    => stack.size,
    "worklist_exhausted" => stack.empty?,
    "stop_reason"        => stop_reason,
    "max_runs"           => MAX_RUNS,
    "time_budget"        => TIME_BUDGET,
    "elapsed_seconds"    => elapsed.round(1),
    "run_errors"         => errors,
    "unflippable_pcs"    => unflippable,
    "per_config"         => per_config,
  }
  File.write(File.join(dir, "exploration_summary.json"), JSON.pretty_generate(summary))
  puts format("== %-28s runs=%-5d paths=%-4d drained=%-5s stop=%-22s %.1fs errors=%s",
              ep, runs, written, stack.empty?, stop_reason, elapsed, errors.inspect)
  summary
end

# ---------------------------------------------------------------------------
batch_started = Time.now
deadline_total = batch_started + TOTAL_BUDGET
puts "== photos batch :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}/ep, " \
     "TIME_BUDGET=#{TIME_BUDGET}s/ep, TOTAL_BUDGET=#{TOTAL_BUDGET}s) =="

all = {}
ENTRYPOINTS.each do |ep, configs|
  next unless ONLY.empty? || ONLY.include?(ep)
  puts "\n-- #{ep} --"
  all[ep] = explore(ep, configs, deadline_total)
end

File.write(File.join(RESULTS, "exploration_summary.json"),
           JSON.pretty_generate({ "batch" => "photos",
                                  "elapsed_seconds" => (Time.now - batch_started).round(1),
                                  "entrypoints" => all }))
File.write(File.join(RESULTS, "elapsed_seconds.txt"), "#{(Time.now - batch_started).round(1)}\n")
puts "\n== photos batch DSE done in #{(Time.now - batch_started).round(1)}s =="
