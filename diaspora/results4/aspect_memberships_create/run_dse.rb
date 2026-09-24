#!/usr/bin/env jruby
# frozen_string_literal: true
#
# aspect_memberships_create — prefix-directed DSE over the REAL
# `AspectMembershipsController#create` (action :create, signed_in: true,
# format :json).
#
# THE FIRST INSERT ENDPOINT IN THE CORPUS. Every batch in
# reports/diaspora/{results2,results3,results4} before this one drives a
# read-only action. This one's whole body is a write:
#
#   @person  = Person.find(params[:person_id])                       # SELECT
#   @aspect  = current_user.aspects.where(id: params[:aspect_id]).first # SELECT
#   @contact = current_user.share_with(@person, @aspect)             # SELECT + INSERT/UPDATE
#   if @contact.present?
#     render json: AspectMembershipPresenter.new(
#       AspectMembership.where(contact_id:, aspect_id:).first).base_hash # SELECT
#   else
#     render plain: I18n.t("aspects.add_to_aspect.failure"), status: 409
#   end
#
# `User#share_with` is NOT mocked (D7 — see ./targets.rb's header): its body
# IS the write, and every line of it either issues SQL or calls an
# already-declared target.
#
# RUNNER MECHANICS are ported UNCHANGED from
# ../comments_index/run_dse.rb (itself ported from
# ../../results3/comments_index/run_dse.rb): prefix-directed DSE with seed
# inheritance and single-branch flips, the same flip helpers, the same
# per-run interceptor history clear. Only the entrypoint wiring differs:
#
#   * TWO symbolic entrypoint params (`person_id`, `aspect_id`) instead of
#     one, both `symstr` so the ids reach the WHERE clauses as genuine binds.
#   * NO anonymous variant. `before_action :authenticate_user!` is
#     unconditional on this controller (no `except:`), so every run has a
#     principal, resolved through REAL Devise `serialize_from_session`.
#   * require paths point at src_new/runtimes/ruby_runtime (moved there this
#     session from src_new/ruby_runtime).
#
# Nothing in src/, src_new/, the shared reports/diaspora/concolic_targets.rb,
# or the diaspora app source is modified. This directory carries PRIVATE
# copies of concolic_targets.rb (from ../comments_index, the kind:-annotated
# one) and targets.rb.
#
# Usage:
#   /home/dev/project/scripts/diaspora-concolic \
#     /home/dev/project/reports/diaspora/results4/aspect_memberships_create/run_dse.rb
#
# Env: MAX_RUNS (default 6), TIME_BUDGET seconds (default 600)

require "./config/environment"
require "/home/dev/project/src_new/runtimes/ruby_runtime/call_interceptor"
require "/home/dev/project/src_new/runtimes/ruby_runtime/base"
require "/home/dev/project/src_new/runtimes/ruby_runtime/int"
require "/home/dev/project/src_new/runtimes/ruby_runtime/string"
require "/home/dev/project/src_new/runtimes/ruby_runtime/bool"
require "/home/dev/project/src_new/runtimes/ruby_runtime/list"
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
AspectMembershipsTargets.install!($interceptor)
AmDeviseUserNaming.install!($interceptor)

HERE        = File.dirname(File.expand_path(__FILE__))
ENTRY       = "aspect_memberships_create"
MAX_RUNS    = (ENV["MAX_RUNS"] || 6).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 600).to_i

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
  ctrl.response = tc.instance_variable_get(:@response)
  [ctrl, tc]
end

CFG = {
  action: :create,
  format: :json,
  params: {
    person_id: { sym: "SYM_PARAM_person_id", default: "5" },
    aspect_id: { sym: "SYM_PARAM_aspect_id", default: "7" }
  }
}.freeze

VARIANT = "auth_json"

# Real-app terminals: exceptions the REAL endpoint raises on reachable data
# states. The controller declares three rescue_from handlers
# (StatementInvalid -> 400, RecordNotFound -> 404, Diaspora::NotMine -> 403);
# those are DISPATCHED FOR REAL below via `rescue_with_handler`, so they are
# normal outcomes, not terminals. What is left is the unrescued 500s:
#
#   (a) `@aspect` nil (the aspect finder missed, or the aspect belongs to a
#       different user) -> `share_with(person, nil)` -> `contact.aspects <<
#       nil` -> ActiveRecord::AssociationTypeMismatch / NoMethodError on nil.
#       This is a REAL reachable state of the real app: the action never
#       checks @aspect before passing it, and `aspects.where(id:).first`
#       returns nil for any aspect_id the signed-in user does not own.
#   (b) a nil-receiver NoMethodError from a missing associated row (same
#       class the read endpoints record).
# Both are recorded as run OUTCOMES, never swallowed as harness failures.
#   (c) I18n::InvalidLocale — `set_locale` on a non-nil unavailable
#       `users.language` (the "xx" arm of ./targets.rb §4). The whole data
#       access is the users SELECT; the action body never runs.
def app_error_terminal?(e)
  return true if defined?(I18n::InvalidLocale) && e.is_a?(I18n::InvalidLocale)
  if defined?(ActiveRecord::AssociationTypeMismatch) &&
     e.is_a?(ActiveRecord::AssociationTypeMismatch)
    return true
  end
  return true if e.is_a?(NoMethodError) && e.message.to_s.include?("nil:NilClass")
  if defined?(Module::DelegationError) && e.is_a?(Module::DelegationError)
    return e.message.to_s.include?("is nil")
  end
  false
end

OUT = ENV["DUMP_OUT"] || HERE
require "fileutils"
FileUtils.mkdir_p(OUT)

def run_one(label, seeds)
  ConcolicTargets.seed_overrides = seeds
  $am_terminal = nil
  ctrl, = make_harness(AspectMembershipsController)

  # PRINCIPAL MUST BE SYMBOLIC (identity_symbolicity_audit): a concrete key
  # here would fold every signed-in view as `users.id = 1` instead of
  # `_MY_UID`. LAZY/memoized so the resolution's queries fire INSIDE
  # $interceptor.run (at the action's first current_user call), not before it.
  ctrl.singleton_class.define_method(:current_user) do
    ci_uid = symint("SYM_USER_CI_id", ConcolicTargets.seed_for("SYM_USER_CI_id", 1))
    @ci_user ||= User.serialize_from_session(ci_uid, "concolicsalt")
  end
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  # devise's authenticate_user! -> warden, which the controller-test rig has
  # no middleware for. It is a guard, not concolic logic: Devise's middleware
  # guarantees a signed-in principal reaches this action (the alternative is
  # a 401 that never enters the controller).
  ctrl.singleton_class.define_method(:authenticate_user!) { :authenticate_user_called }

  begin
    ctrl.request.format = CFG[:format]
  rescue StandardError => e
    warn "[warn] could not set request format: #{e.class}"
  end
  ctrl.send(:action_name=, CFG[:action].to_s)

  body = lambda do
    # THE SYMBOLIC ENTRYPOINT ARGUMENTS. Declared INSIDE the `run` block:
    # CallInterceptor#run calls SymbolicFunc.reset! at its very start, which
    # clears @registered_vars — a symstr made before `run` would never appear
    # in the dump's symbolic_vars and Z3 would drop every PC over it.
    params = {}
    CFG[:params].each do |key, spec|
      params[key] = symstr(spec[:sym], ConcolicTargets.seed_for(spec[:sym], spec[:default]))
    end
    ctrl.params = params.with_indifferent_access

    begin
      # The real dispatch runs ApplicationController's before_action chain
      # before the action body, and on a signed-in request two of those
      # callbacks READ DATA (set_locale -> current_user.language;
      # set_grammatical_gender -> current_user.gender -> person -> profile).
      # Same ground truth as comments_index; invoked explicitly because
      # direct dispatch skips the chain.
      I18n.locale = "en"
      ctrl.send(:set_locale)
      ctrl.send(:set_grammatical_gender)
      ctrl.send(CFG[:action])
    rescue Exception => e # rubocop:disable Lint/RescueException
      handled = begin
        ctrl.send(:rescue_with_handler, e)
      rescue Exception
        nil
      end
      unless handled
        if app_error_terminal?(e)
          $am_terminal = { "type" => e.class.name, "cause" => (e.cause && e.cause.class.name),
                           "message" => e.message.to_s[0, 160] }
          next :app_error_500
        end
        raise e
      end
      handled
    end
    :ok
  end

  dump = $interceptor.run(body, {}, label: label, script: "run_dse.rb")
  dump["concolic_seeds"]    = seeds
  dump["concolic_scenario"] = { "name" => VARIANT, "format" => CFG[:format].to_s,
                                "signed_in" => true }
  dump["concolic_terminal"] = $am_terminal if $am_terminal

  # RUNNER-LOCAL LEAK WORKAROUND (reported, not patched in src_new/):
  # CallInterceptor keeps an unbounded @all_calls history ACROSS runs
  # (`run` only slices @all_calls[old_count..]). `run` recomputes old_count at
  # entry, so clearing the array between runs is safe.
  $interceptor.instance_variable_set(:@all_calls, [])

  dump
end

# PC EXPRESSION SHAPE (src_new, DESIGN_IR §4.1.1c TERMS) — WITHOUT THIS THE
# DSE IS A SINGLE RUN.
#
# The runtimes now record a path condition's `expr` as a structured TERM
# (a Hash: {"op" => "==", "args" => [{"sym" => …}, {"lit" => {"sort", "value"}}]}),
# where they used to record the rendered string "(VAR == StringVal('pl'))".
# Every flip matcher below is a REGEX over that old spelling, so a Hash expr
# matches nothing: `flip_any` returns nil, the PC is booked "unflippable",
# no child seed is pushed, and the worklist drains after run 1 reporting
# `worklist_exhausted: true` — a FALSE completion signal, not a visible
# failure. Measured: the second trial of this batch recorded 5 path
# conditions, called all 5 unflippable, and stopped after ONE run.
#
# Hand-built PCs still arrive as strings: `ConcolicTargets.symbolic_instance`
# records its boolean-predicate readers with a literal
# `"(#{sym.sym_name} == True)"`. So a dump mixes both spellings, and a
# runner that only handles strings silently explores the hand-built
# decisions and forecloses every operator-recorded one.
#
# Render the term back to the matchers' spelling. Pure translation — no
# matcher below is changed, so seed keys and snapshots stay compatible.
def pc_expr_to_s(expr)
  return expr.to_s unless expr.is_a?(::Hash)
  return expr["sym"].to_s if expr.key?("sym")
  if expr.key?("lit")
    lit  = expr["lit"] || {}
    sort = lit["sort"]
    v    = lit["value"]
    return case sort
           when "str"  then "StringVal('#{v}')"
           when "bool" then (v ? "True" : "False")
           when "int"  then v.to_s
           when "null" then "None"
           else v.inspect
           end
  end
  op   = expr["op"].to_s
  args = expr["args"] || []
  rend = args.map { |a| pc_expr_to_s(a) }
  case op
  when "length" then "len(#{rend[0]})"
  when "not"    then "Not(#{rend[0]})"
  else
    rend.size == 2 ? "(#{rend[0]} #{op} #{rend[1]})" : "#{op}(#{rend.join(', ')})"
  end
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [pc_expr_to_s(e["expr"]), e["taken"] ? true : false] }
end

# NAME BOUNDARY (2026-09-14): the runtimes mint a list's cardinality var as
# `SYM_LEN_X`; the flip matchers below are written in the old `len(X)`
# spelling. Normalise on the way in so a length decision reaches its
# dedicated matcher and not the generic one (which would ignore want_taken).
def canon_len(expr)
  expr.to_s.strip.gsub(/SYM_LEN_([A-Za-z0-9_]+)/, 'len(\1)')
end

def flip_seed(expr, want_taken, vals = {})
  m = /\A\(([A-Za-z_][A-Za-z0-9_]*) (==|!=) (.+)\)\z/m.match(canon_len(expr))
  return nil unless m
  var, op, lit = m[1], m[2], m[3].strip
  want_taken = !want_taken if op == "!="

  if /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(lit) && lit != var && !%w[True False].include?(lit)
    principal = ->(v) { v.include?("devise_user_first") || v.start_with?("SYM_USER_CI") }
    free, anchor = if principal.call(var) && !principal.call(lit) && vals.key?(var)
                     [lit, vals[var]]
                   elsif principal.call(lit) && !principal.call(var) && vals.key?(lit)
                     [var, vals[lit]]
                   elsif vals.key?(lit) then [var, vals[lit]]
                   elsif vals.key?(var) then [lit, vals[var]]
                   end
    return nil if free.nil?
    av = anchor
    av = av.to_i if av.is_a?(String) && av =~ /\A-?\d+\z/
    return nil unless av.is_a?(Integer) || av.is_a?(String) || av == true || av == false
    other = case av
            when true, false then !av
            when Integer     then av + 1
            when String      then av.empty? ? "concolic_other" : ""
            end
    return { free => (want_taken ? av : other) }
  end

  parsed =
    case lit
    when "True"  then true
    when "False" then false
    when /\AStringVal\('(.*)'\)\z/m then Regexp.last_match(1)
    when /\A'(.*)'\z/m then Regexp.last_match(1)
    when /\A"(.*)"\z/m then Regexp.last_match(1)
    when /\A-?\d+\z/   then lit.to_i
    else return nil
    end

  alt = nil
  alt = "en" if var.end_with?("_language")

  value =
    if want_taken
      parsed
    else
      case parsed
      when true, false then !parsed
      when Integer     then parsed + 1
      when String      then alt || (parsed.empty? ? "concolic_other" : "")
      else return nil
      end
    end

  { var => value }
end

def flip_len_seed(expr, want_taken)
  m = /\A\((len\(.+\)) != 0\)\z/m.match(canon_len(expr))
  return nil unless m
  { m[1] => (want_taken ? 1 : 0) }
end

def flip_len_many_seed(expr, want_taken)
  m = /\A\((len\(.+\)) > 1\)\z/m.match(canon_len(expr))
  return nil unless m
  { m[1] => (want_taken ? 2 : 1) }
end

def flip_length_seed(expr, want_taken)
  m = /\A\(Length\(([A-Za-z_][A-Za-z0-9_]*)\) (<=|>=|==|!=|<|>) (-?\d+)\)\z/m.match(canon_len(expr))
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

def flip_any(expr, want_taken, vals = {})
  flip_seed(expr, want_taken, vals) || flip_len_seed(expr, want_taken) ||
    flip_len_many_seed(expr, want_taken) || flip_length_seed(expr, want_taken)
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

def digest(str)
  Digest::MD5.digest(str)
end

# ---------------------------------------------------------------------------
# Prefix-directed exploration
# ---------------------------------------------------------------------------
puts "== #{ENTRY} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
started = Time.now

stack = [{}]
if ENV["EXTRA_SEEDS_JSON"] && File.exist?(ENV["EXTRA_SEEDS_JSON"])
  extra = JSON.parse(File.read(ENV["EXTRA_SEEDS_JSON"]))
  extra = [extra] if extra.is_a?(Hash)
  stack = ENV["SEEDS_ONLY"] ? extra : (extra + stack)
end
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

  seeds = stack.shift # FIFO: single flips of the root first, then pairs, …
  key = digest(JSON.generate(seeds.sort.to_h))
  next if !ENV["SEEDS_ONLY"] && seen_seeds.include?(key)
  seen_seeds << key

  runs += 1
  label = format("%s_dse%04d%s", VARIANT, runs, ENV["LABEL_SUFFIX"].to_s)

  begin
    dump = run_one(label, seeds)
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts "[#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 300]}"
    puts e.backtrace.take(25).join("\n") if ENV["TRACE"]
    errors["harness:#{e.class}"] += 1
    next
  end

  errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

  pcs = path_conditions(dump)
  sig = digest(sig_of(pcs))

  next if !ENV["SEEDS_ONLY"] && seen_paths.include?(sig)

  seen_paths << sig
  written += 1
  File.write(File.join(OUT, "dump_#{label}.json"), JSON.pretty_generate(dump))

  puts format("[%s] paths=%d runs=%d pcs=%d stack=%d %s",
              label, written, runs, pcs.size, stack.size,
              dump["error"] ? "error=#{dump['error']['type']}" : "")

  vals = {}
  (dump["symbolic_vars"] || []).each { |sv| vals[sv["name"].to_s] = sv["value"] }
  pcs.each do |(expr, taken)|
    fl = flip_any(expr, !taken, vals)
    if fl.nil?
      unflippable[expr] += 1
      next
    end
    child = seeds.merge(fl)
    ckey = digest(JSON.generate(child.sort.to_h))
    next if ENV["SEEDS_ONLY"]
    stack.push(child) unless seen_seeds.include?(ckey)
  end
end

elapsed = Time.now - started

summary = {
  "entrypoint"         => ENTRY,
  "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
  "signed_in"          => true,
  "variant"            => VARIANT,
  "format"             => CFG[:format].to_s,
  "action"             => CFG[:action].to_s,
  "write_endpoint"     => true,
  "app_error_terminals"=> "AssociationTypeMismatch (nil aspect), nil-receiver NoMethodError, DelegationError — recorded outcomes",
  "params"             => CFG[:params].map { |k, v|
    [k.to_s, { "symbolic_name" => v[:sym], "seed" => v[:default] }]
  }.to_h,
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
