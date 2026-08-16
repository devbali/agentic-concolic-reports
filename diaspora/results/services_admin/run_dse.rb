#!/usr/bin/env jruby
# frozen_string_literal: true
#
# services_admin — prefix-directed DSE over the 9 batch entrypoints.
#
# WHY PREFIX-DIRECTED DSE (and not the old seed-feedback loop)
# ------------------------------------------------------------
# The interceptor names symbolic results with a PER-RUN call ordinal
# (SYM_RESULT_<func>_<idx>, src/ruby_runtime/call_interceptor.rb:140).
# Flipping an early branch changes how many intercepted calls happen before a
# later one, which RENUMBERS every later var. So feeding CoverageChecker's
# `concrete_values` back wholesale as seed_overrides mixes var names harvested
# under different execution prefixes and never converges.
#
# Instead: from an observed path [c0..cn], emit one child per k that INHERITS
# the parent's seed dict (so the prefix c0..c_{k-1} replays identically and
# those ordinals stay valid) and adds EXACTLY ONE flip for c_k. Ordinals are
# assigned in execution order, so a flip at k can only renumber vars after k.
# Dedup on (param-variant, path signature); expand until the worklist drains.
#
# Neither src/ nor the shared concolic_targets.rb is modified — this is purely
# a runner-local exploration strategy.
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot <abs path to this file>
#
# Env:
#   MAX_RUNS    per-entrypoint execution cap        (default 400)
#   TIME_BUDGET per-entrypoint seconds              (default 420)
#   ONLY        comma-separated entrypoint filter   (default all)

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
# The LIVE framework target declarations, shared by all 13 batches (read-only).
require "/home/dev/project/reports/diaspora/concolic_targets"
# Batch-local wall fixes / gate instrumentation (installed AFTER the shared
# targets so its declarations win — declare_target is last-one-wins).
require "/home/dev/project/reports/diaspora/results/services_admin/targets"
require "json"
require "set"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
ServicesAdminTargets.install!($interceptor)

RESULTS     = File.dirname(File.expand_path(__FILE__))
MAX_RUNS    = (ENV["MAX_RUNS"] || 400).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 420).to_i
ONLY        = (ENV["ONLY"] || "").split(",").map(&:strip).reject(&:empty?)

# ---------------------------------------------------------------------------
# Harness (reused from run_concolic.rb, the verified services_admin harness)
#
# The symbolic user is built INSIDE each run so that its column vars are
# subject to that run's seed_overrides (a user built once at load time would
# freeze its seeds for the whole exploration).
#
# NOTE: admin?/moderator? are deliberately NOT overridden here. run_concolic.rb
# stubbed them with concrete booleans, which hand-models the authorization
# gate. We let the REAL User#admin? run -> Role.is_admin?(person) ->
# Role.exists? (a declared target) so the gate is exercised for real.
# targets.rb §1 instruments Role.is_admin? so that query's answer becomes a
# recorded, seedable, ENFORCED branch instead of a truthiness no-op.
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
  cname = controller_class.to_s.gsub("::", "__").sub(/Controller\z/, "ControllerTest")
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

# The omniauth auth hash IS the request payload for services#create, so it is
# ordinary runner-supplied test input (like params), not modeled app behaviour.
# `extra.access_token` must quack like an OAuth::AccessToken because
# ServicesController#twitter_access_level reads
# `token.response.header["x-access-level"]`.
class StubOAuthToken
  Resp = Struct.new(:header)
  def initialize(level); @level = level; end
  def response; Resp.new({"x-access-level" => @level}); end
end

def omniauth_hash(provider: "twitter", access_level: "read-write")
  {
    "provider"    => provider,
    "uid"         => "concolic-uid-1",
    "info"        => {"nickname" => "alice", "name" => "Alice",
                      "image" => "http://example.org/a.jpg", "description" => "hi"},
    "credentials" => {"token" => "tok", "secret" => "sec"},
    "extra"       => {"access_token" => StubOAuthToken.new(access_level)}
  }
end

# Build + invoke one real controller action. Everything (including the
# symbolic user) happens inside the interceptor run.
def drive(controller_class, action, params, method:, omniauth: nil)
  user = symbolic_user("SA")
  ctrl, tc = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user) { user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  req = tc.instance_variable_get(:@request)
  req.env["warden"] = StubWarden.new(user)
  if omniauth
    req.env["omniauth.auth"]   = omniauth
    req.env["omniauth.origin"] = nil
  end
  tc.process(action, method: method, params: params)
  :ok
end

# ---------------------------------------------------------------------------
# Entrypoints
#
# `variants` are CONCRETE request-parameter variants (real input-space points,
# e.g. the four `params[:range]` cases admins#stats switches on). They are
# separate DSE roots, not fabricated path conditions.
# ---------------------------------------------------------------------------
ENTRYPOINTS = [
  {
    name: "services_invite",
    # NOTE: this diaspora revision has NO services#invite / services#inviter
    # action and no POST /services/:provider/invite route (config/routes.rb
    # only declares `resources :services, only: [:index, :destroy]` plus
    # `get "/auth/:provider/callback" => services#create` and
    # `get "/auth/failure"`). services#create — the omniauth provider POST the
    # batch table points at — is driven instead. Reported in REPORT.md.
    run: lambda { |v|
      drive(ServicesController, :create, {provider: v[:provider]}, method: "GET",
            omniauth: omniauth_hash(provider: v[:provider], access_level: v[:level]))
    },
    variants: [
      {provider: "twitter", level: "read-write"},
      {provider: "twitter", level: "read"},      # abort_if_read_only_access
      {provider: "tumblr",  level: "read-write"} # non-twitter provider
    ]
  },
  {
    name: "services_failure",
    run: ->(v) { drive(ServicesController, :failure, v, method: "GET") },
    variants: [{provider: "twitter"}]
  },
  {
    name: "admin_user_search",
    run: ->(v) { drive(AdminsController, :user_search, v, method: "GET") },
    variants: [
      {},
      {admins_controller_user_search: {username: "alice"}},
      {admins_controller_user_search: {email: "a@b.c"}},
      {admins_controller_user_search: {guid: "abc"}},
      {admins_controller_user_search: {under13: "1"}},
      {admins_controller_user_search: {username: ""}} # invalid -> User.none
    ]
  },
  {
    name: "admin_dashboard",
    run: ->(v) { drive(AdminsController, :dashboard, v, method: "GET") },
    variants: [{}]
  },
  {
    name: "admin_stats",
    run: ->(v) { drive(AdminsController, :stats, v, method: "GET") },
    variants: [{}, {range: "week"}, {range: "2weeks"}, {range: "month"}]
  },
  {
    name: "admin_close_account",
    run: ->(v) { drive(Admin::UsersController, :close_account, v, method: "POST") },
    variants: [{id: 1}]
  },
  {
    name: "admin_lock_account",
    run: ->(v) { drive(Admin::UsersController, :lock_account, v, method: "POST") },
    variants: [{id: 1}]
  },
  {
    name: "admin_unlock_account",
    run: ->(v) { drive(Admin::UsersController, :unlock_account, v, method: "POST") },
    variants: [{id: 1}]
  },
  {
    name: "admin_add_invites",
    # Real route is GET "admins/add_invites/:invite_code_id" (the batch table
    # says POST; routes.rb declares GET). Driven with the real verb.
    run: ->(v) { drive(AdminsController, :add_invites, v, method: "GET") },
    variants: [{invite_code_id: "concolic-token"}]
  }
].freeze

# ---------------------------------------------------------------------------
# PC extraction + single-branch flipping
# ---------------------------------------------------------------------------
def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

# Every PC this app emits has the shape "(VAR == LITERAL)" or "(len(X) != N)".
# Return a {var => value} seed fragment that forces the desired outcome, or nil
# for shapes we cannot invert (counted + reported, never silently dropped).
PC_RE = /\A\((len\([A-Za-z0-9_]+\)|[A-Za-z_][A-Za-z0-9_]*) (==|!=) (.+)\)\z/m.freeze

def flip_seed(expr, want_taken)
  m = PC_RE.match(expr.to_s.strip)
  return nil unless m
  var, op, lit = m[1], m[2], m[3].strip

  parsed =
    case lit
    when "True"  then true
    when "False" then false
    when /\A'(.*)'\z/m then Regexp.last_match(1)
    when /\A"(.*)"\z/m then Regexp.last_match(1)
    when /\A-?\d+\z/   then lit.to_i
    else return nil
    end

  # For "==" the condition holds when var == lit; for "!=" when var != lit.
  want_equal = (op == "==") ? want_taken : !want_taken

  value =
    if want_equal
      parsed
    else
      case parsed
      when true, false then !parsed
      when Integer     then parsed + 1
      when String      then parsed.empty? ? "concolic_other" : ""
      else return nil
      end
    end

  {var => value}
end

# ---------------------------------------------------------------------------
# Per-entrypoint prefix-directed exploration
# ---------------------------------------------------------------------------
def explore(ep)
  name = ep[:name]
  dir  = File.join(RESULTS, name)
  Dir.mkdir(dir) unless Dir.exist?(dir)
  Dir.glob(File.join(dir, "dump_*.json")).each { |f| File.delete(f) }
  Dir.glob(File.join(dir, "coverage_summary.json")).each { |f| File.delete(f) }

  puts "\n=== #{name} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) ==="
  started = Time.now

  stack       = ep[:variants].each_index.map { |vi| [vi, {}] }.reverse
  seen_seeds  = Set.new
  seen_paths  = Set.new   # (variant, signature) — governs expansion
  written_sigs = Set.new  # signature only — governs what gets persisted
  unflippable = Hash.new(0)
  errors      = Hash.new(0)
  runs        = 0
  written     = 0
  total_pcs   = 0
  stopped     = nil

  until stack.empty?
    if runs >= MAX_RUNS
      stopped = "MAX_RUNS"
      break
    end
    if Time.now - started > TIME_BUDGET
      stopped = "TIME_BUDGET"
      break
    end

    vi, seeds = stack.pop
    key = JSON.generate([vi, seeds.sort.to_h])
    next if seen_seeds.include?(key)
    seen_seeds << key

    runs += 1
    label = format("v%d_dse%04d", vi, runs)
    ConcolicTargets.seed_overrides = seeds
    variant = ep[:variants][vi]

    begin
      dump = $interceptor.run(-> { ep[:run].call(variant) }, {},
                              label: label, script: "run_dse.rb")
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "  [#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 140]}"
      errors["harness:#{e.class}"] += 1
      next
    end

    errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

    pcs = path_conditions(dump)
    sig = sig_of(pcs)

    unless written_sigs.include?(sig)
      written_sigs << sig
      written += 1
      total_pcs += pcs.size
      dump["concolic_variant"] = variant.inspect
      dump["concolic_seeds"]   = seeds
      File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
      if written <= 4 || written % 20 == 0
        puts format("  [%s] paths=%d runs=%d pcs=%d stack=%d %s",
                    label, written, runs, pcs.size, stack.size,
                    dump["error"] ? "error=#{dump['error']['type']}" : "")
      end
    end

    vsig = "#{vi}|#{sig}"
    next if seen_paths.include?(vsig)
    seen_paths << vsig

    pcs.each do |expr, taken|
      fl = flip_seed(expr, !taken)
      if fl.nil?
        unflippable[expr] += 1
        next
      end
      child = seeds.merge(fl)
      ckey = JSON.generate([vi, child.sort.to_h])
      stack.push([vi, child]) unless seen_seeds.include?(ckey)
    end
  end

  elapsed = Time.now - started
  summary = {
    "entrypoint"         => name,
    "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
    "param_variants"     => ep[:variants].map(&:inspect),
    "runs_executed"      => runs,
    "distinct_paths"     => written,
    "total_path_conditions_in_written_dumps" => total_pcs,
    "seed_sets_tried"    => seen_seeds.size,
    "stack_remaining"    => stack.size,
    "worklist_exhausted" => stack.empty?,
    "stopped_by"         => stopped,
    "max_runs"           => MAX_RUNS,
    "time_budget"        => TIME_BUDGET,
    "elapsed_seconds"    => elapsed.round(1),
    "run_errors"         => errors,
    "unflippable_pcs"    => unflippable
  }
  File.write(File.join(dir, "exploration_summary.json"), JSON.pretty_generate(summary))

  puts format("  -> runs=%d paths=%d pcs=%d drained=%s stopped_by=%s elapsed=%.1fs errors=%s",
              runs, written, total_pcs, stack.empty?, stopped.inspect, elapsed, errors.inspect)
  summary
end

# ---------------------------------------------------------------------------
t0 = Time.now
all = []
ENTRYPOINTS.each do |ep|
  next if !ONLY.empty? && !ONLY.include?(ep[:name])
  begin
    all << explore(ep)
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts "!! #{ep[:name]} EXPLORATION ABORTED #{e.class}: #{e.message.to_s[0, 200]}"
    puts e.backtrace.first(8).join("\n")
    all << {"entrypoint" => ep[:name], "aborted" => "#{e.class}: #{e.message.to_s[0, 200]}"}
  end
end
elapsed = Time.now - t0
File.write(File.join(RESULTS, "exploration_summary.json"),
           JSON.pretty_generate({"batch" => "services_admin",
                                 "elapsed_seconds" => elapsed.round(1),
                                 "entrypoints" => all}))
File.write(File.join(RESULTS, "elapsed_seconds.txt"), "#{elapsed.round(1)}\n")
puts "\n== services_admin DSE done in #{elapsed.round(1)}s =="
