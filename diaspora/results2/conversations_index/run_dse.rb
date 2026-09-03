#!/usr/bin/env jruby
# frozen_string_literal: true
#
# conversations_index — prefix-directed DSE over the REAL
# ConversationsController#index, results2 rerun with FULLY SYMBOLIC identity
# (current_user.id / person.id) and SCOPED associations.
#
# Ported from ../../results/conversations/run_dse.rb, restricted to the
# single conversations_index entrypoint (action :index, signed_in: true —
# `before_action :authenticate_user!` with no `except:`).
#
# THE POINT OF THIS RERUN (results2/README.md), two changes from the source
# batch's symbolic_user / ConvoSymAssociations:
#
# 1. SYMBOLIC IDENTITY. The source batch's symbolic_user pinned
#      person.define_singleton_method(:id) { 1 }
#      user.define_singleton_method(:id) { 1 }
#      user.define_singleton_method(:person_id) { 1 }
#      user.define_singleton_method(:guid) { "abc123" }
#      user.define_singleton_method(:diaspora_handle) { "alice@example.org" }
#    All FIVE pins are removed here. `symbolic_instance` already returns a
#    SymbolicInt for every column (id included), so `user.id` and
#    `person.id` flow as SYM_USER_CONV_id / SYM_PERSON_CONV_id without any
#    override. `person_id`/`guid`/`diaspora_handle` are not DB columns on
#    `users` at all — they are `delegate ... to: :person` methods defined on
#    the User class itself (see User#person_id -> person.id, User#guid ->
#    person.guid, User#diaspora_handle -> person.diaspora_handle), so leaving
#    them un-overridden makes them resolve to the symbolic Person's own
#    symbolic string/int columns for free. Only `user.person` is still
#    overridden (needed because AR's real `has_one :person` reader cannot
#    resolve against a symbolic `owner_id` — the same generic association-
#    reader gap `concolic_targets.rb`'s @association_cache fix works around
#    for every OTHER association, but a has_one whose owner is itself
#    allocated has no association machinery to lean on at all).
#
# 2. ASSOCIATION SCOPING. `user.contacts` / `user.conversations` and the
#    ConvoSymAssociations module (conversation_visibilities / messages /
#    conversation / participants, in targets.rb) are REWORKED here to build
#    scoped relations off the symbolic owner id (`Contact.where(user_id:
#    user.id)`, `ConversationVisibility.where(conversation_id: self.id)`, ...)
#    instead of the source batch's unscoped `Model.all`. See targets.rb for
#    the full rationale and REPORT.md for the acceptance-test bind lines this
#    produces.
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
#       /home/dev/project/reports/diaspora/results2/conversations_index/run_dse.rb
#
# Env: MAX_RUNS (default 4000), TIME_BUDGET seconds (default 1500)

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
ConversationsIndexTargets.install!($interceptor)

HERE        = File.dirname(File.expand_path(__FILE__))
ENTRY       = "conversations_index"
MAX_RUNS    = (ENV["MAX_RUNS"] || 4000).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 1500).to_i

# ---------------------------------------------------------------------------
# Symbolic current_user — see header comment (1). No id/person_id/guid/
# diaspora_handle pins.
# ---------------------------------------------------------------------------
def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user)")
  user   = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:person) { person }
  # Scoped associations (header comment (2)) — the symbolic owner id (user.id
  # / person.id) lands in the WHERE clause as a $$() bind instead of the
  # source batch's unscoped `Contact.all` / `Conversation.all`.
  user.define_singleton_method(:contacts) { Contact.where(user_id: user.id) }
  user.define_singleton_method(:conversations) do
    Conversation.joins(:conversation_visibilities)
                .where(conversation_visibilities: { person_id: person.id })
  end
  [user, person]
end

$convo_user, $convo_person = symbolic_user("CONV")

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

# CallInterceptor keeps an UNBOUNDED @all_calls history across runs
# (src/ruby_runtime/call_interceptor.rb — `run` only slices
# @all_calls[old_count..]). A DSE loop does hundreds of runs in one process,
# so that history is a leak; src/ is read-only for a batch runner, so trim it
# runner-locally before every run (REPORTED, not patched — see
# results/conversations/run_dse.rb for the identical workaround).
def trim_interceptor_history!
  h = $interceptor.instance_variable_get(:@all_calls)
  h.clear if h.respond_to?(:clear)
end

# ---------------------------------------------------------------------------
# Request variants: format (html/json) x conversation_id presence. Presence
# of the :conversation_id key (not its value) selects the `if
# params[:conversation_id]` branch — a symbolic value there would ALWAYS be
# truthy (Ruby truthiness gap on a real, non-nil symbolic object), so
# variant selection is done by omitting the key entirely for "plain".
# Once inside the branch, the id VALUE is symbolic (SYM_PARAM_conversation_id)
# so the Conversation join lookup gets a genuine $$() bind too.
# ---------------------------------------------------------------------------
VARIANTS = {
  "html_plain"   => { format: :html },
  "html_withcid" => { format: :html, with_cid: true },
  "json_plain"   => { format: :json },
  "json_withcid" => { format: :json, with_cid: true },
}.freeze

def run_one(label, variant, seeds)
  trim_interceptor_history!
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(ConversationsController)
  ctrl.singleton_class.define_method(:current_user)    { $convo_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }

  cfg = VARIANTS.fetch(variant)
  params = {}
  if cfg[:with_cid]
    cid_seed = ConcolicTargets.seed_for("SYM_PARAM_conversation_id", 1)
    params[:conversation_id] = symint("SYM_PARAM_conversation_id", cid_seed)
  end
  ctrl.params = params.with_indifferent_access
  ctrl.request.format = cfg[:format]

  body = lambda do
    begin
      ctrl.send(:index)
    rescue Exception => e # rubocop:disable Lint/RescueException
      handled = begin
        ctrl.send(:rescue_with_handler, e)
      rescue Exception
        nil
      end
      raise e unless handled
      handled
    end
    :ok
  end

  $interceptor.run(body, {}, label: label, script: "run_dse.rb")
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"].to_s, e["taken"] ? true : false] }
end

# ---------------------------------------------------------------------------
# flip_seed — same shape-matching as the source batch's run_dse.rb (handles
# scalar equality, negated-int `((- VAR) == 0)` from SymbolicList#[]'s index
# check, and `len(VAR)` SymbolicList length PCs).
# ---------------------------------------------------------------------------
def parse_literal(lit)
  case lit
  when "True"  then [true, true]
  when "False" then [false, true]
  when /\A-?\d+\z/ then [lit.to_i, true]
  when /\A'(.*)'\z/m then [Regexp.last_match(1), true]
  when /\A"(.*)"\z/m then [Regexp.last_match(1), true]
  else [nil, false]
  end
end

def other_value(v, negated)
  case v
  when true, false then !v
  when Integer     then negated ? v - 1 : v + 1
  when String      then v.empty? ? "concolic_other" : ""
  end
end

def flip_seed(expr, want_taken)
  s = expr.to_s.strip
  return nil unless s.start_with?("(") && s.end_with?(")")
  m = /\A(.+?) (==|!=|<=|>=|<|>) (.+)\z/m.match(s[1..-2].strip)
  return nil unless m
  lhs, op, rhs_s = m[1].strip, m[2], m[3].strip

  rhs, ok = parse_literal(rhs_s)
  return nil unless ok

  negated = false
  key = nil
  if (mm = /\A\(-\s*([A-Za-z_][A-Za-z0-9_]*)\)\z/.match(lhs))
    negated = true
    key = mm[1]
  elsif /\Alen\([A-Za-z_][A-Za-z0-9_]*\)\z/.match?(lhs)
    key = lhs # seed key is the literal "len(name)" string
  elsif /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(lhs)
    key = lhs
  else
    return nil
  end

  desired =
    case op
    when "==" then want_taken ? rhs : other_value(rhs, negated)
    when "!=" then want_taken ? other_value(rhs, negated) : rhs
    when "<"  then return nil unless rhs.is_a?(Integer); want_taken ? rhs - 1 : rhs
    when "<=" then return nil unless rhs.is_a?(Integer); want_taken ? rhs : rhs + 1
    when ">"  then return nil unless rhs.is_a?(Integer); want_taken ? rhs + 1 : rhs
    when ">=" then return nil unless rhs.is_a?(Integer); want_taken ? rhs : rhs - 1
    end
  return nil if desired.nil?

  value = negated ? -desired : desired
  return nil if negated && !value.is_a?(Integer)
  return nil if key.start_with?("len(") && (!value.is_a?(Integer) || value.negative?)

  { key => value }
end

def sig_of(pcs)
  Digest::MD5.hexdigest(pcs.map { |e, t| "#{e}:#{t}" }.join("|"))
end

def state_key(variant, seeds)
  Digest::MD5.hexdigest("#{variant}|#{JSON.generate(seeds.sort.to_h)}")
end

# ---------------------------------------------------------------------------
# Prefix-directed exploration — one worklist per variant (request shape),
# each variant seeding its own DSE root; all runs land in this same
# per-entrypoint dir and are coverage-checked together.
# ---------------------------------------------------------------------------
puts "== #{ENTRY} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
started = Time.now

wanted      = ENV["VARIANTS"] ? ENV["VARIANTS"].split(",") : VARIANTS.keys
stack       = wanted.map { |v| [v, {}] }
seen_states = Set.new
seen_paths  = Set.new
unflippable = Hash.new(0)
errors      = Hash.new(0)
runs        = 0
written     = 0
pc_total    = 0

until stack.empty?
  if runs >= MAX_RUNS
    puts "[stop] MAX_RUNS reached"
    break
  end
  if Time.now - started > TIME_BUDGET
    puts "[stop] time budget exhausted"
    break
  end

  variant, seeds = stack.pop
  skey = state_key(variant, seeds)
  next if seen_states.include?(skey)
  seen_states << skey

  runs += 1
  label = format("%s_dse%04d", variant, runs)

  begin
    dump = run_one(label, variant, seeds)
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts "[#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 160]}"
    errors["harness:#{e.class}"] += 1
    next
  end

  errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

  pcs = path_conditions(dump)
  sig = "#{variant}||#{sig_of(pcs)}"

  if seen_paths.include?(sig)
    # Same request shape, same path -> adds nothing to the execution tree.
  else
    seen_paths << sig
    written += 1
    pc_total += pcs.size
    File.write(File.join(HERE, "dump_#{label}.json"), JSON.pretty_generate(dump))
    puts format("[%s] new path #%d pcs=%d stack=%d %s",
                label, written, pcs.size, stack.size,
                dump["error"] ? "error=#{dump['error']['type']}" : "")
  end

  pcs.each do |expr, taken|
    fl = flip_seed(expr, !taken)
    if fl.nil?
      unflippable[expr] += 1
      next
    end
    child = seeds.merge(fl)
    stack.push([variant, child]) unless seen_states.include?(state_key(variant, child))
  end
end

elapsed = Time.now - started

summary = {
  "entrypoint"         => ENTRY,
  "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
  "signed_in"          => true,
  "request_variants"   => VARIANTS,
  "params"             => {
    "conversation_id" => {
      "symbolic_name" => "SYM_PARAM_conversation_id",
      "seed"          => 1,
      "present_in"    => %w[html_withcid json_withcid]
    }
  },
  "user_identity"      => {
    "user.id"            => "SYM_USER_CONV_id (symbolic, no pin)",
    "person.id"          => "SYM_PERSON_CONV_id (symbolic, no pin)",
    "user.person_id"     => "delegates to person.id (SYM_PERSON_CONV_id) — no pin",
    "user.guid"          => "delegates to person.guid (SYM_PERSON_CONV_guid) — no pin",
    "user.diaspora_handle" => "delegates to person.diaspora_handle (SYM_PERSON_CONV_diaspora_handle) — no pin"
  },
  "runs_executed"      => runs,
  "distinct_paths"     => written,
  "path_conditions_written" => pc_total,
  "states_tried"       => seen_states.size,
  "stack_remaining"    => stack.size,
  "worklist_exhausted" => stack.empty?,
  "max_runs"           => MAX_RUNS,
  "time_budget"        => TIME_BUDGET,
  "elapsed_seconds"    => elapsed.round(1),
  "run_errors"         => errors,
  "unflippable_pcs"    => unflippable
}
File.write(File.join(HERE, "exploration_summary.json"), JSON.pretty_generate(summary))

puts "\n== #{ENTRY} exploration done =="
puts "  runs executed  : #{runs}"
puts "  distinct paths : #{written}"
puts "  worklist empty : #{stack.empty?}"
puts "  elapsed        : #{elapsed.round(1)}s"
puts "  run errors     : #{errors.inspect}"
puts "  unflippable    : #{unflippable.keys.size} distinct PC shapes"
