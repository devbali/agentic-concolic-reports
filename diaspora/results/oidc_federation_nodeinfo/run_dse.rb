# frozen_string_literal: true
#
# run_dse.rb — "oidc_federation_nodeinfo" batch, prefix-directed DSE.
#
# Replaces the old run_concolic.rb "one default run per entrypoint" +
# suggestion-feedback loop. Rationale (see BATCH_BRIEFING / run_proper.rb):
# symbolic var names carry a PER-RUN call ordinal minted in
# src/ruby_runtime/call_interceptor.rb:140 (SYM_RESULT_<func>_<idx>).
# Flipping an early branch changes how many intercepted calls happen before a
# later one, renumbering every later var — so feeding CoverageChecker's
# concrete_values back wholesale as seed_overrides mixes names harvested under
# DIFFERENT prefixes and is UNSOUND.
#
# Instead: classic DSE prefix extension. From an observed path [c0..cn] emit
# one child per k that INHERITS the parent's seed dict (prefix c0..c_{k-1}
# replays identically, so those ordinals stay valid) and adds EXACTLY ONE flip
# for c_k. Dedup on path signature; expand until the worklist drains.
#
# Touches neither src/ nor the shared concolic_targets.rb. Batch-local
# behaviour lives in ./targets.rb, installed after the shared targets — for
# this batch that is a single item: a MarkerFreeSymbolicString subclass that
# stops SymbolicString#split pushing its unobservable Contains/IndexOf
# markers as PathConditions. No wall mocks: this batch hits zero walls.
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot <abs path to this file>
#
# Env:
#   MAX_RUNS    per-entrypoint execution cap   (default 400)
#   TIME_BUDGET per-entrypoint seconds         (default 420)
#   ONLY        comma-separated entrypoint names to run (default: all)

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "/home/dev/project/reports/diaspora/results/oidc_federation_nodeinfo/targets"
require "json"
require "set"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
# Batch-local overlay (installed AFTER the shared targets — last declaration
# wins). See targets.rb: its sole entry removes the src/ruby_runtime split
# markers from Person#username. No wall mocks: this batch hits zero walls.
OidcFederationNodeinfoTargets.install!($interceptor)

RESULTS     = File.dirname(File.expand_path(__FILE__))
MAX_RUNS    = (ENV["MAX_RUNS"] || 400).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 420).to_i
ONLY        = (ENV["ONLY"] || "").split(",").map(&:strip).reject(&:empty?)

# ---------------------------------------------------------------------------
# Harness (reused from run_concolic.rb)
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
  user.define_singleton_method(:contacts) { Contact.all }
  user.define_singleton_method(:blocks) { Block.all }
  user.define_singleton_method(:aspects) { Aspect.all }
  user.define_singleton_method(:current_sign_in_at) { Time.now - 3600 }
  user
end

$user = symbolic_user("OFC")

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
  tc.instance_variable_set(:@routes, controller_class.to_s.start_with?("DiasporaFederation") ?
                                       DiasporaFederation::Engine.routes : Rails.application.routes)
  ctrl = tc.instance_variable_get(:@controller)
  [ctrl, tc]
end

# One real controller execution under a seed assignment.
def drive(controller_class, action, params, label, seeds,
          signed_in: true, method: "GET", format: nil, content_type: nil, session: nil)
  ConcolicTargets.seed_overrides = seeds
  ctrl, tc = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user)    { signed_in ? $user : nil }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  req = tc.instance_variable_get(:@request)
  req.env["warden"] = StubWarden.new($user)
  req.env["CONTENT_TYPE"] = content_type if content_type
  dump = $interceptor.run(
    -> { tc.process(action, method: method, params: params, format: format, session: session); :ok },
    {}, label: label, script: "run_dse.rb"
  )
  # RUNNER-LOCAL WORKAROUND for a src/ leak (reported, not patched):
  # CallInterceptor keeps an unbounded @all_calls history across runs
  # (src/ruby_runtime/call_interceptor.rb:69/127); `run` only slices
  # @all_calls[old_count..] for the dump, so nothing is ever released and a
  # long DSE loop grows the heap until the JVM OOMs. Clearing it between runs
  # is safe: `run` re-reads @all_calls.size as its base offset each time.
  $interceptor.instance_variable_set(:@all_calls, [])
  dump
end

# ---------------------------------------------------------------------------
# DSE machinery (flip_seed copied from the reference runner)
# ---------------------------------------------------------------------------
def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

# Parse a Z3 literal as rendered by src/ruby_runtime (base/int/string/bool).
def parse_literal(lit)
  lit = lit.to_s.strip
  case lit
  when "True"  then [true]
  when "False" then [false]
  when /\AStringVal\('(.*)'\)\z/m then [Regexp.last_match(1)]
  when /\AStringVal\("(.*)"\)\z/m then [Regexp.last_match(1)]
  when /\A'(.*)'\z/m then [Regexp.last_match(1)]
  when /\A"(.*)"\z/m then [Regexp.last_match(1)]
  when /\A-?\d+\z/   then [lit.to_i]
  end
end

def other_than(parsed)
  case parsed
  when true, false then !parsed
  when Integer     then parsed + 1
  when String      then parsed.empty? ? "concolic_other" : ""
  end
end

# ---------------------------------------------------------------------------
# Flip a single path condition to its other outcome by assigning ONE seed.
#
# Shapes this batch's runtime emits (verified against the dumps):
#   (VAR == True|False)                      SymbolicBool / finder not_found
#   (VAR == StringVal('x')) / (VAR == 'x')   SymbolicString#==
#   (VAR != StringVal('x'))                  SymbolicString#!=
#   (VAR == 3) / (VAR != 3) / (VAR > 3) ...  SymbolicInt compares
#   Contains(StringVal('x'), VAR)            SymbolicString#include?
#   Not(Contains(StringVal('x'), VAR))       String#split structural marker
#   PrefixOf/SuffixOf(StringVal('x'), VAR)   start_with? / end_with?
#
# Anything else (IndexOf(...)==n split markers, len(...) on SymbolicList,
# expressions over SubString(...)) returns nil and is COUNTED as unflippable
# rather than silently dropped.
# ---------------------------------------------------------------------------
def flip_seed(expr, want_taken)
  s = expr.to_s.strip

  # Not(<inner>) — flip the inner condition to the opposite polarity.
  if (m = /\ANot\((.*)\)\z/m.match(s))
    return flip_seed(m[1], !want_taken)
  end

  # Contains(<lit>, VAR) / PrefixOf(<lit>, VAR) / SuffixOf(<lit>, VAR)
  if (m = /\A(Contains|PrefixOf|SuffixOf)\((.+), ([A-Za-z_][A-Za-z0-9_]*)\)\z/m.match(s))
    lit = parse_literal(m[2])
    return nil unless lit && lit[0].is_a?(String)
    needle = lit[0]
    var = m[3]
    value =
      if want_taken
        needle
      else
        needle.empty? ? nil : (needle == "concolic_other" ? "" : "concolic_other")
      end
    return nil if value.nil?
    return { var => value }
  end

  # (VAR <op> <lit>)
  m = /\A\(([A-Za-z_][A-Za-z0-9_]*) (==|!=|<=|>=|<|>) (.+)\)\z/m.match(s)
  return nil unless m
  var, op, lit = m[1], m[2], m[3].strip
  p = parse_literal(lit)
  return nil unless p
  parsed = p[0]

  # Value that makes `<parsed_var> op parsed` evaluate to want_taken.
  value =
    case op
    when "==" then want_taken ? parsed : other_than(parsed)
    when "!=" then want_taken ? other_than(parsed) : parsed
    when "<"  then parsed.is_a?(Integer) ? (want_taken ? parsed - 1 : parsed) : nil
    when ">"  then parsed.is_a?(Integer) ? (want_taken ? parsed + 1 : parsed) : nil
    when "<=" then parsed.is_a?(Integer) ? (want_taken ? parsed : parsed + 1) : nil
    when ">=" then parsed.is_a?(Integer) ? (want_taken ? parsed : parsed - 1) : nil
    end
  return nil if value.nil?

  { var => value }
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

# ---------------------------------------------------------------------------
# Entrypoints — each drives the REAL controller action for its route.
# ---------------------------------------------------------------------------
ENTRYPOINTS = [
  {
    name:  "access_tokens_create",
    route: "POST /api/openid_connect/access_tokens -> api/openid_connect/token_endpoint#create",
    run:   lambda do |label, seeds|
      drive(Api::OpenidConnect::TokenEndpointController, :create,
            {grant_type:   "authorization_code",
             code:         "concolic_code",
             client_id:    "concolic_client",
             client_secret: "concolic_secret",
             redirect_uri: "http://localhost:3000/cb"},
            label, seeds, method: "POST", signed_in: false)
    end
  },
  {
    name:  "authorizations_create",
    route: "POST /api/openid_connect/authorization -> api/openid_connect/authorizations#create",
    # #create begins with restore_request_parameters, which OVERWRITES every
    # OAuth request param from the session written earlier by #new. Driving it
    # with an empty session therefore forces response_type="" and the endpoint
    # short-circuits at unsupported_response_type! before any of the consent
    # logic runs. The session below is exactly what #new's
    # save_request_parameters would have stored — harness setup, not app logic.
    run:   lambda do |label, seeds|
      drive(Api::OpenidConnect::AuthorizationsController, :create,
            {approve: "true", client_id: "concolic_client",
             redirect_uri: "http://localhost:3000/cb",
             response_type: "code", scope: "openid", state: "s", nonce: "n"},
            label, seeds, method: "POST", signed_in: true,
            session: {client_id:     "concolic_client",
                      response_type: "code",
                      redirect_uri:  "http://localhost:3000/cb",
                      scopes:        "openid",
                      state:         "concolic_state",
                      nonce:         "concolic_nonce"})
    end
  },
  {
    name:  "webfinger",
    route: "GET /.well-known/webfinger -> DiasporaFederation::WebfingerController#webfinger",
    run:   lambda do |label, seeds|
      drive(DiasporaFederation::WebfingerController, :webfinger,
            {resource: "acct:alice@example.org"},
            label, seeds, signed_in: false)
    end
  },
  {
    name:  "host_meta",
    route: "GET /.well-known/host-meta -> DiasporaFederation::WebfingerController#host_meta",
    run:   lambda do |label, seeds|
      drive(DiasporaFederation::WebfingerController, :host_meta, {},
            label, seeds, signed_in: false)
    end
  },
  {
    name:  "node_info_show",
    route: "GET /nodeinfo/:version -> node_info#document",
    run:   lambda do |label, seeds|
      drive(NodeInfoController, :document, {version: "1.0"},
            label, seeds, signed_in: false)
    end
  },
  {
    name:  "federation_receive_public",
    route: "POST /receive/public -> DiasporaFederation::ReceiveController#public",
    run:   lambda do |label, seeds|
      drive(DiasporaFederation::ReceiveController, :public,
            {xml: "%3Cxml%3Etest%3C%2Fxml%3E"},
            label, seeds, method: "POST", signed_in: false)
    end
  },
  {
    name:  "federation_receive_private",
    route: "POST /receive/users/:guid -> DiasporaFederation::ReceiveController#private",
    run:   lambda do |label, seeds|
      drive(DiasporaFederation::ReceiveController, :private,
            {guid: "abc123", xml: "%3Cxml%3Etest%3C%2Fxml%3E"},
            label, seeds, method: "POST", signed_in: false)
    end
  }
].freeze

# ---------------------------------------------------------------------------
# Prefix-directed exploration, per entrypoint
# ---------------------------------------------------------------------------
batch_started = Time.now
overall = {}

ENTRYPOINTS.each do |ep|
  next if ONLY.any? && !ONLY.include?(ep[:name])

  dir = File.join(RESULTS, ep[:name])
  Dir.mkdir(dir) unless Dir.exist?(dir)
  Dir.glob(File.join(dir, "dump_*.json")).each { |f| File.delete(f) }

  puts "\n=== #{ep[:name]} :: #{ep[:route]} ==="
  started = Time.now

  stack       = [{}]
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

    seeds = stack.pop
    key = JSON.generate(seeds.sort.to_h)
    next if seen_seeds.include?(key)
    seen_seeds << key

    runs += 1
    label = format("dse%04d", runs)

    begin
      dump = ep[:run].call(label, seeds)
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "[#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 160]}"
      errors["harness:#{e.class}"] += 1
      next
    end

    errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

    pcs = path_conditions(dump)
    max_pcs = pcs.size if pcs.size > max_pcs
    sig = sig_of(pcs)

    unless seen_paths.include?(sig)
      seen_paths << sig
      written += 1
      File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
      if written <= 6 || written % 20 == 0
        puts format("  [%s] paths=%d runs=%d pcs=%d stack=%d %s",
                    label, written, runs, pcs.size, stack.size,
                    dump["error"] ? "error=#{dump['error']['type']}: #{dump['error']['message'].to_s[0, 90]}" : "")
      end
    end

    pcs.each do |(expr, taken)|
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
    "entrypoint"         => ep[:name],
    "route"              => ep[:route],
    "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
    "runs_executed"      => runs,
    "distinct_paths"     => written,
    "max_pcs_in_a_run"   => max_pcs,
    "seed_sets_tried"    => seen_seeds.size,
    "stack_remaining"    => stack.size,
    "worklist_exhausted" => stack.empty?,
    "max_runs"           => MAX_RUNS,
    "time_budget"        => TIME_BUDGET,
    "elapsed_seconds"    => elapsed.round(1),
    "run_errors"         => errors,
    "unflippable_pcs"    => unflippable
  }
  File.write(File.join(dir, "exploration_summary.json"), JSON.pretty_generate(summary))
  overall[ep[:name]] = summary

  puts format("--- %s: runs=%d paths=%d maxpcs=%d drained=%s elapsed=%.1fs errors=%s",
              ep[:name], runs, written, max_pcs, stack.empty?, elapsed, errors.inspect)
end

total = Time.now - batch_started
File.write(File.join(RESULTS, "exploration_summary.json"), JSON.pretty_generate(overall))
File.write(File.join(RESULTS, "elapsed_seconds.txt"), "#{total.round(1)}\n")
puts "\n== batch done in #{total.round(1)}s =="
