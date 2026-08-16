# frozen_string_literal: true
#
# run_dse.rb — "users_sessions" batch (22 entrypoints), prefix-directed DSE.
#
# WHY PREFIX-DIRECTED DSE (and not the old seed-suggestion loop)
# --------------------------------------------------------------
# The interceptor names every mocked result with a PER-RUN call ordinal
# (SYM_RESULT_<func>_<idx>, src/ruby_runtime/call_interceptor.rb:140). Flipping
# an early branch changes how many intercepted calls happen before a later one,
# which RENUMBERS every later var. So feeding CoverageChecker.concrete_values
# back wholesale as seed_overrides mixes var names harvested under different
# execution prefixes — unsound, and empirically non-convergent.
#
# Instead: from an observed path [c0..cn] emit one child per k that INHERITS the
# parent's seeds (so the prefix c0..c_{k-1} replays identically and those
# ordinals stay valid) and adds EXACTLY ONE flip for c_k. Dedup on the path
# signature; expand until the worklist drains or a cap is hit.
#
# Neither src/ nor the shared concolic_targets.rb is modified — everything here
# is runner-local.
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot <abs path to this file>
# Env:
#   ONLY=ep1,ep2       run only these entrypoints (default: all)
#   MAX_RUNS=200       per-entrypoint execution cap
#   TIME_BUDGET=180    per-entrypoint wall-clock cap (seconds)
#   TOTAL_BUDGET=5400  batch wall-clock cap (seconds)

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "/home/dev/project/reports/diaspora/results/users_sessions/targets"
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
# Batch-local overlay — every wall fix, mock override and subclass this batch
# needs now lives in results/users_sessions/targets.rb, installed AFTER the
# shared file so `declare_target`'s last-one-wins semantics apply.
UsersSessionsTargets.install!($interceptor)

RESULTS      = File.dirname(File.expand_path(__FILE__))
MAX_RUNS     = (ENV["MAX_RUNS"]     || 200).to_i
TIME_BUDGET  = (ENV["TIME_BUDGET"]  || 180).to_i
TOTAL_BUDGET = (ENV["TOTAL_BUDGET"] || 5400).to_i

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

# The symbolic current_user. REBUILT PER RUN so that seed_overrides on its
# column vars (SYM_USER_<col>) actually take effect — symbolic_instance reads
# seed_for at construction time.
#
# Runner-local workaround, reported in REPORT.md: devise's real `current_user`
# goes through Warden -> User.serialize_from_session -> a query whose result the
# devise internals index/iterate, which the strict runtime cannot serve. Every
# batch in this experiment (including the reference posts runner) stubs
# `current_user` with a symbolic model instance instead. Only `current_user` is
# stubbed; the controller action itself runs FOR REAL.
def symbolic_user
  u = ConcolicTargets.symbolic_instance(User, "SYM_USER", "User (current_user)")
  # Per-INSTANCE wall fixes (language / gender / mounted uploaders). They must
  # be singleton methods because symbolic_instance already installed singleton
  # column readers that beat any class-level declare_target. Every other fix
  # this batch needs — User#blocks, the reset_authentication_token! OOM guard,
  # devise_mapping, valid_password?, confirm_email, update_attributes, sign_up,
  # the missing unconfirmed_email column — is a declared target installed once
  # by UsersSessionsTargets.install!.
  UsersSessionsTargets.decorate_user!(u)
end

class StubWarden
  attr_accessor :env
  # `signed_in` matters: Devise's `require_no_authentication`
  # (prepend_before_action on sessions#new/#create and registrations#new/#create)
  # asks `warden.authenticated?` / `warden.authenticate?`. The previous rig
  # answered TRUE unconditionally, so the signed-OUT entrypoints were treated as
  # already-authenticated and redirected. `authenticate!` still returns the user
  # — Devise's sessions#create calls it to obtain `resource`, and the strategy
  # (not the stub) is what we want to exercise.
  def initialize(user, env = {}, signed_in: true)
    @user = user
    @env = env
    @signed_in = signed_in
  end
  def authenticate!(*_); @user; end
  def authenticated?(*_); @signed_in; end
  def authenticate?(*_); @signed_in; end
  def authenticate(*_); @signed_in ? @user : nil; end
  def user(*_); @signed_in ? @user : nil; end
  def raw_session; {}; end
  def session(*_); {}; end
  def logout(*_); true; end
  def clear_strategies_cache!(*_); true; end
  # devise sign_out_all_scopes (sessions#destroy) calls warden.lock!
  def lock!(*_); true; end
  def unlock!(*_); true; end
  def set_user(*_); @user; end
  def session_serializer; self; end
  def delete(*_); nil; end
  def config; self; end
  def no_input_strategies; []; end
end

puts "[probe] Devise.mappings=#{(defined?(Devise) ? Devise.mappings.keys : []).inspect}"

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
  [tc.instance_variable_get(:@controller), tc]
end

def drive(controller_class, action, params, user, method: "GET", format: nil, signed_in: true, session: {})
  ctrl, tc = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user)    { signed_in ? user : nil }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  # devise_mapping is no longer patched here — UsersSessionsTargets §8 declares
  # DeviseController#devise_mapping -> the REAL Devise.mappings[:user], which
  # also gives resource_class / resource_name / scope_name their real values.
  req = tc.instance_variable_get(:@request)
  req.env["warden"] = StubWarden.new(user, req.env, signed_in: signed_in)
  tc.process(action, method: method, params: params, format: format, session: session)
  :ok
end

# ---------------------------------------------------------------------------
# Entrypoints — the real controller actions of this batch.
#
# Three of the 22 entrypoints named in the README's batch table do not exist in
# this Diaspora revision (users#token, users#remove_avatar, invitations#edit) —
# see ABSENT below and REPORT.md. invitations#new is covered in their place as
# the InvitationsController action that does exist.
# ---------------------------------------------------------------------------

EP = {}

EP["users_edit"] = ->(u) { drive(UsersController, :edit, {}, u) }

EP["users_update"] = lambda { |u|
  drive(UsersController, :update, {user: {email: "a@b.com", language: "en"}}, u, method: "PUT")
}

EP["users_privacy_settings"] = ->(u) { drive(UsersController, :privacy_settings, {}, u) }

EP["users_update_privacy_settings"] = lambda { |u|
  drive(UsersController, :update_privacy_settings, {user: {strip_exif: "1"}}, u, method: "PUT")
}

EP["users_getting_started"] = ->(u) { drive(UsersController, :getting_started, {}, u) }

EP["users_getting_started_completed"] = lambda { |u|
  drive(UsersController, :getting_started_completed, {}, u)
}

EP["users_export"] = ->(u) { drive(UsersController, :export_profile, {}, u, method: "POST") }

EP["users_export_photos"] = ->(u) { drive(UsersController, :export_photos, {}, u, method: "POST") }

EP["users_download_profile"] = ->(u) { drive(UsersController, :download_profile, {}, u) }

EP["users_confirm_email"] = lambda { |u|
  drive(UsersController, :confirm_email, {token: "tok123"}, u)
}

EP["users_public"] = lambda { |u|
  drive(UsersController, :public, {username: "alice"}, u, signed_in: false)
}

EP["users_destroy"] = lambda { |u|
  drive(UsersController, :destroy, {user: {current_password: "pw"}}, u, method: "DELETE")
}

EP["users_auth_token"] = ->(u) { drive(UsersController, :auth_token, {}, u, method: "POST") }

EP["sessions_create"] = lambda { |u|
  drive(SessionsController, :create, {user: {username: "alice", password: "pw"}}, u,
        method: "POST", signed_in: false)
}

EP["sessions_destroy"] = ->(u) { drive(SessionsController, :destroy, {}, u, method: "DELETE") }

EP["sessions_new"] = ->(u) { drive(SessionsController, :new, {}, u, signed_in: false) }

EP["registrations_new"] = ->(u) { drive(RegistrationsController, :new, {}, u, signed_in: false) }

EP["invitations_new"] = ->(u) { drive(InvitationsController, :new, {}, u) }

EP["invitations_create"] = lambda { |u|
  drive(InvitationsController, :create,
        {email_inviter: {emails: "friend@example.com,bad-address", message: "hi"}},
        u, method: "POST")
}

# registrations#create is deliberately LAST and capped — see RUNS_CAP below.
EP["registrations_create"] = lambda { |u|
  drive(RegistrationsController, :create,
        {user: {username: "newuser", email: "new@example.com",
                password: "pw123456", password_confirmation: "pw123456"}},
        u, method: "POST", signed_in: false)
}

# Per-entrypoint execution caps that OVERRIDE MAX_RUNS.
#
# registrations_create ABORTS THE WHOLE JVM on its second DSE path — a native
# SIGSEGV inside JRuby's FFI string marshalling
# (com.kenai.jffi.Foreign.getZeroTerminatedByteArray), i.e. outside the JVM, so
# it cannot be rescued. Its first path is clean and records 3 genuine PCs, so we
# keep that and stop, rather than either (a) losing the whole batch process to
# an abort or (b) reverting the fix and going back to a VACUOUS dump. Two
# candidate crypto leaves (OpenSSL::PKey::RSA.generate, Devise::Encryptor.digest)
# were mocked and measured; neither prevented the abort — see targets.rb §14.
#
# The consequence is reported, never hidden: the worklist does NOT drain,
# stop_reason is "max_runs", and the checker reports its unexplored siblings as
# missing branches with coverage_complete=false.
RUNS_CAP = {"registrations_create" => 1}.freeze

# Named in the README batch table but NOT present in this app revision.
ABSENT = {
  "users_token" => "No users#token action and no /users/token route in this Diaspora " \
                   "revision (config/routes.rb, app/controllers/users_controller.rb).",
  "users_remove_avatar" => "No users#remove_avatar action and no matching route in this " \
                           "Diaspora revision (grep -rn remove_avatar app/ config/ = 0 hits).",
  "invitations_edit" => "InvitationsController defines only #new and #create; there is no " \
                        "/users/invitation/accept route (routes.rb has users/invitations " \
                        "GET->new, POST->create). invitations_new is covered instead."
}

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

# Memory-frugal set keys: store 32-byte digests, never the full path/seed text.
def digest(str)
  Digest::MD5.hexdigest(str)
end

def parse_literal(lit)
  case lit
  when "True"  then true
  when "False" then false
  when /\A'(.*)'\z/m then Regexp.last_match(1)
  when /\A"(.*)"\z/m then Regexp.last_match(1)
  # SymbolicString#!= renders a plain-string RHS as Z3's StringVal('…')
  when /\AStringVal\('(.*)'\)\z/m then Regexp.last_match(1)
  when /\A-?\d+\z/   then lit.to_i
  end
end

def other_value(v)
  case v
  when true, false then !v
  when Integer     then v + 1
  when String      then v.empty? ? "concolic_other" : ""
  end
end

# Produce {seed_var => value} forcing `expr` to evaluate to `want`.
# Handles the PC shapes this runtime emits:
#   (VAR == LIT) (VAR != LIT)   scalars (SymbolicInt/String/Bool)
#   (VAR < LIT) etc              SymbolicInt comparisons
#   (len(NAME) != 0)             SymbolicList empty?/any?  -> seed key "len(NAME)"
# Anything else (PrefixOf/Contains/IndexOf/derived exprs) returns nil and is
# counted as unflippable rather than silently dropped.
def flip_seed(expr, want)
  m = %r{\A\((len\([A-Za-z_][A-Za-z0-9_]*\)|[A-Za-z_][A-Za-z0-9_]*) (==|!=|<|>|<=|>=) (.+)\)\z}m
       .match(expr.to_s.strip)
  return nil unless m
  var, op, lit = m[1], m[2], m[3].strip
  parsed = parse_literal(lit) # false for "False" — nil only when unparseable
  return nil if parsed.nil?

  value =
    case op
    when "==" then want ? parsed : other_value(parsed)
    when "!=" then want ? other_value(parsed) : parsed
    when "<"  then parsed.is_a?(Integer) ? (want ? parsed - 1 : parsed) : nil
    when ">"  then parsed.is_a?(Integer) ? (want ? parsed + 1 : parsed) : nil
    when "<=" then parsed.is_a?(Integer) ? (want ? parsed : parsed + 1) : nil
    when ">=" then parsed.is_a?(Integer) ? (want ? parsed : parsed - 1) : nil
    end
  return nil if value.nil? # false is a legitimate flip value; nil means "cannot invert"

  {var => value}
end

# ---------------------------------------------------------------------------
# Per-entrypoint prefix-directed DSE
# ---------------------------------------------------------------------------

def explore(name, body, batch_deadline)
  max_runs = RUNS_CAP.fetch(name, MAX_RUNS)
  dir = File.join(RESULTS, name)
  FileUtils.mkdir_p(dir)
  Dir[File.join(dir, "dump_*.json")].each { |f| File.delete(f) }

  started     = Time.now
  stack       = [{}]
  seen_seeds  = Set.new
  seen_paths  = Set.new
  unflippable = Hash.new(0)
  errors      = Hash.new(0)
  runs        = 0
  written     = 0
  stop_reason = "worklist_drained"

  until stack.empty?
    if runs >= max_runs
      stop_reason = "max_runs"
      break
    end
    if Time.now - started > TIME_BUDGET
      stop_reason = "time_budget"
      break
    end
    if Time.now > batch_deadline
      stop_reason = "total_budget"
      break
    end

    seeds = stack.pop
    key = digest(JSON.generate(seeds.sort.to_h))
    next if seen_seeds.include?(key)
    seen_seeds << key

    runs += 1
    label = format("dse%04d", runs)

    begin
      # MEMORY (src/ gap, reported not patched): CallInterceptor keeps an
      # unbounded @all_calls history across runs. Hundreds of DSE executions in
      # one JVM would retain every TargetCall forever. Trim it before each run —
      # CallInterceptor#run only ever reads @all_calls[old_count..], so starting
      # from empty is equivalent and bounds the live set to one run.
      $interceptor.instance_variable_set(:@all_calls, [])
      ConcolicTargets.seed_overrides = seeds
      user = symbolic_user
      dump = $interceptor.run(-> { body.call(user) }, {}, label: label, script: "run_dse.rb")
    rescue Exception => e # rubocop:disable Lint/RescueException
      errors["harness:#{e.class}"] += 1
      puts "  [#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 140]}"
      next
    end

    errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

    pcs = path_conditions(dump)
    sig = digest(sig_of(pcs)) # digest-keyed: do not retain full path strings
    next if seen_paths.include?(sig)

    seen_paths << sig
    written += 1
    File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))

    if written <= 3 || (written % 25).zero?
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
      ckey = digest(JSON.generate(child.sort.to_h))
      stack.push(child) unless seen_seeds.include?(ckey)
    end
  end

  elapsed = Time.now - started
  summary = {
    "entrypoint"         => name,
    "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
    "runs_executed"      => runs,
    "distinct_paths"     => written,
    "seed_sets_tried"    => seen_seeds.size,
    "stack_remaining"    => stack.size,
    "worklist_exhausted" => stack.empty?,
    "stop_reason"        => stop_reason,
    "max_runs"           => max_runs,
    "runs_capped"        => RUNS_CAP.key?(name),
    "time_budget"        => TIME_BUDGET,
    "elapsed_seconds"    => elapsed.round(1),
    "run_errors"         => errors,
    "unflippable_pcs"    => unflippable
  }
  File.write(File.join(dir, "exploration_summary.json"), JSON.pretty_generate(summary))
  puts format("== %-34s paths=%-4d runs=%-4d %-16s %.1fs errors=%s",
              name, written, runs, stop_reason, elapsed, errors.inspect)
  summary
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

only = (ENV["ONLY"] || "").split(",").map(&:strip).reject(&:empty?)
targets = only.empty? ? EP.keys : only

batch_started  = Time.now
batch_deadline = batch_started + TOTAL_BUDGET
all = {}

targets.each do |name|
  body = EP[name]
  unless body
    puts "!! unknown entrypoint #{name}"
    next
  end
  if Time.now > batch_deadline
    puts "!! total budget exhausted before #{name}"
    all[name] = {"entrypoint" => name, "stop_reason" => "not_started_total_budget"}
    next
  end
  all[name] = explore(name, body, batch_deadline)
end

# Absent entrypoints: record a machine-readable marker instead of a fake dump.
ABSENT.each do |name, why|
  next unless only.empty? || only.include?(name)
  dir = File.join(RESULTS, name)
  FileUtils.mkdir_p(dir)
  File.write(File.join(dir, "coverage_summary.json"), JSON.pretty_generate(
    "endpoint" => name, "endpoint_absent_from_app" => true, "reason" => why,
    "coverage_complete" => false, "tree_nodes" => 0, "missing_branches" => 0,
    "dumps_loaded" => 0, "path_conditions" => 0, "genuine" => false
  ))
  all[name] = {"entrypoint" => name, "stop_reason" => "absent_from_app", "reason" => why}
end

elapsed = Time.now - batch_started
File.write(File.join(RESULTS, "elapsed_seconds.txt"), "#{elapsed.round(1)}\n")
File.write(File.join(RESULTS, "batch_exploration_summary.json"),
           JSON.pretty_generate("elapsed_seconds" => elapsed.round(1), "entrypoints" => all))
puts "\n== users_sessions DSE done in #{elapsed.round(1)}s =="
