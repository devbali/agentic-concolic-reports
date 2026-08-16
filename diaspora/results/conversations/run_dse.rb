# frozen_string_literal: true
# ============================================================================
# run_dse.rb — "conversations" batch, prefix-directed DSE (proper exploration).
#
# WHY THIS REPLACES run_concolic.rb + run_phase2.rb + run_phase3.rb
# -----------------------------------------------------------------
# Those runners fed CoverageChecker's `concrete_values` back as
# seed_overrides wholesale. Symbolic var names carry the interceptor's
# PER-RUN call ordinal (SYM_RESULT_<func>_<idx>, minted in
# src/ruby_runtime/call_interceptor.rb). Flipping an EARLY branch changes how
# many intercepted calls happen before a later one, which RENUMBERS every
# later var — so a suggestion naming `first_2_*` only means the same query if
# the run it is applied to has the same execution PREFIX. Mixing names
# harvested from different runs is unsound.
#
# THE FIX (classic DSE prefix extension): from an observed path
# [c0 … cn], emit one child per k that INHERITS the parent's seed dict (so
# prefix c0…c_{k-1} replays identically and those ordinals stay valid) and
# adds EXACTLY ONE flip for c_k. Ordinals are assigned in execution order, so
# a flip at k can only renumber vars AFTER k. Dedup on the path signature;
# expand until the worklist drains.
#
# This modifies neither src/ nor the shared concolic_targets.rb — it is purely
# a runner-local exploration strategy. The harness (symbolic user, association
# readers, controller-test plumbing) is carried over verbatim from
# run_concolic.rb; no app logic is replicated here.
#
# Usage (via the memory-slot wrapper, never diaspora-concolic directly):
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot <abs path to this file>
#
# Env: MAX_RUNS_PER_EP (default 400), TIME_BUDGET (total seconds, default 1500)
# ============================================================================
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "/home/dev/project/reports/diaspora/results/conversations/targets"
require "json"
require "set"
require "digest"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
# Batch-local wall fixes — MUST install after the shared targets (last-one-wins).
ConversationsTargets.install!($interceptor)

RESULTS = File.dirname(File.expand_path(__FILE__))
# 8000: with the batch-local targets.rb overlay installed, conversations_index
# reaches contacts_data and grows a 7-deep branch tree, needing 1230 runs to
# DRAIN its worklist (400 was not enough and left it truncated).
MAX_RUNS_PER_EP = (ENV["MAX_RUNS_PER_EP"] || 8000).to_i
TIME_BUDGET     = (ENV["TIME_BUDGET"] || 1500).to_i

require "action_controller/test_case"

# ---------------------------------------------------------------------------
# Symbolic current_user (identity concrete so WHERE clauses build; query
# results symbolic).  Verbatim from run_concolic.rb.
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
  user.define_singleton_method(:contacts)      { Contact.all }
  user.define_singleton_method(:conversations) { Conversation.all }
  user
end

# ---------------------------------------------------------------------------
# Association readers on finder-symbolic records (harness plumbing, not app
# logic): symbolic_instance builds records via klass.allocate, so AR's
# association machinery has no target to load. Supplying `.all` relations
# routes the app's own `.where(...).first` / `.count` into the DECLARED
# finder/calculation targets, so real PCs are recorded. Guarded by
# concolic_attrs => real records are untouched. Verbatim from run_concolic.rb.
# ---------------------------------------------------------------------------
module ConvoSymAssociations
  def conversation_visibilities
    respond_to?(:concolic_attrs) ? ConversationVisibility.all : super
  end

  def messages
    respond_to?(:concolic_attrs) ? Message.all : super
  end

  def conversation
    if respond_to?(:concolic_attrs)
      ConcolicTargets.symbolic_instance(Conversation, "SYM_CV_BELONGS_CONVERSATION",
                                        "ConversationVisibility#conversation (belongs_to)")
    else
      super
    end
  end

  def participants
    respond_to?(:concolic_attrs) ? Person.all : super
  end
end
[Conversation, ConversationVisibility, Message].each { |k| k.prepend(ConvoSymAssociations) }

$convo_user = symbolic_user("CONV")

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
# (src/ruby_runtime/call_interceptor.rb:69 — `run` only slices
# @all_calls[old_count..]). A DSE loop does hundreds of runs in one process, so
# that history is a leak. src/ is read-only for a batch runner, so trim it
# runner-locally before every run: `run` recomputes old_count = size, so an
# empty history is equivalent and keeps the per-run slice exact.
# REPORTED, not patched.
def trim_interceptor_history!
  h = $interceptor.instance_variable_get(:@all_calls)
  h.clear if h.respond_to?(:clear)
end

def drive(controller_class, action, params, label, seeds)
  trim_interceptor_history!
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user) { $convo_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  p = params.dup
  ctrl.request.format = p.delete(:format).to_sym if p.key?(:format)
  ctrl.params = p.with_indifferent_access
  $interceptor.run(-> { ctrl.send(action); :ok }, {}, label: label, script: "run_dse.rb")
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"].to_s, e["taken"] ? true : false] }
end

# Dedup keys are DIGESTS, not the raw JSON/expression strings: a DSE worklist
# retains one key per state/path for the whole run, and the box caps JRuby at
# ~1GB. A 16-byte digest keeps those sets flat.
def sig_of(pcs)
  Digest::MD5.hexdigest(pcs.map { |e, t| "#{e}:#{t}" }.join("|"))
end

def state_key(variant, seeds)
  Digest::MD5.hexdigest("#{variant}|#{JSON.generate(seeds.sort.to_h)}")
end

# ---------------------------------------------------------------------------
# flip_seed — turn one observed path condition into a seed override that
# forces the OPPOSITE outcome.
#
# PC shapes this batch's runtime actually emits:
#   (VAR == True)                 symbool  (finder *_not_found, predicates)
#   (VAR == 1) / (VAR != 0) / …   symint   (Calculations#count, sizes)
#   ((- VAR) == 0)                symint negated (Conversation#first_unread_message:
#                                 messages.to_a[-visibility.unread] -> SymbolicList#[])
#   (len(VAR_rows) != 0)          SymbolicList#empty?/any? — the seed key IS
#                                 the literal string "len(VAR_rows)" (see
#                                 concolic_targets.rb §C: seed_for("len(#{vn})", 1))
#
# Anything else is counted in `unflippable` and reported, never silently
# dropped.
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

  # Desired value of the LHS expression so that (LHS op RHS) == want_taken.
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
  # SymbolicList lengths are non-negative by construction.
  return nil if key.start_with?("len(") && (!value.is_a?(Integer) || value.negative?)

  { key => value }
end

# ---------------------------------------------------------------------------
# Entrypoints. `variants` are distinct REQUEST shapes (different params the
# real route accepts) — not different app logic. Each variant seeds its own
# DSE root; all runs of an entrypoint land in the same per-entrypoint dir and
# are coverage-checked together.
# ---------------------------------------------------------------------------
ENTRYPOINTS = [
  { ep: "conversations_index", controller: ConversationsController, action: :index,
    variants: {
      "plain"   => { format: :html },
      "withcid" => { format: :html, conversation_id: 1 },
    } },
  { ep: "conversations_create", controller: ConversationsController, action: :create,
    variants: {
      "contactids" => { contact_ids: "1,2", conversation: { subject: "Hi", text: "Hello" } },
      "personids"  => { person_ids: "7",   conversation: { subject: "Hi", text: "Hello" } },
      "norecip"    => { conversation: { subject: "Hi", text: "Hello" } },
    } },
  { ep: "conversations_show", controller: ConversationsController, action: :show,
    variants: {
      "json" => { id: 1, format: :json },
      "html" => { id: 1, format: :html },
    } },
  { ep: "conversations_raw", controller: ConversationsController, action: :raw,
    variants: {
      "html" => { conversation_id: 1, format: :html },
    } },
  { ep: "messages_create", controller: MessagesController, action: :create,
    variants: {
      "post" => { conversation_id: 1, message: { text: "Hello" } },
    } },
  { ep: "conversation_visibilities_destroy", controller: ConversationVisibilitiesController,
    action: :destroy,
    variants: {
      "delete" => { conversation_id: 1 },
    } },
].freeze

started = Time.now
overall = {}

ENTRYPOINTS.each do |cfg|
  ep = cfg[:ep]
  dir = File.join(RESULTS, ep)
  Dir.mkdir(dir) unless Dir.exist?(dir)

  puts "\n== #{ep} :: prefix-directed DSE =="
  ep_started  = Time.now
  stack       = cfg[:variants].keys.map { |v| [v, {}] }
  seen_states = Set.new
  seen_paths  = Set.new
  unflippable = Hash.new(0)
  errors      = Hash.new(0)
  runs        = 0
  written     = 0
  pc_total    = 0

  until stack.empty?
    if runs >= MAX_RUNS_PER_EP
      puts "[stop] MAX_RUNS_PER_EP reached for #{ep}"
      break
    end
    if Time.now - started > TIME_BUDGET
      puts "[stop] global time budget exhausted during #{ep}"
      break
    end

    variant, seeds = stack.pop
    skey = state_key(variant, seeds)
    next if seen_states.include?(skey)
    seen_states << skey

    runs += 1
    label = format("%s_%s_dse%03d", ep, variant, runs)

    begin
      dump = drive(cfg[:controller], cfg[:action], cfg[:variants][variant], label, seeds)
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "  [#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 140]}"
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
      File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
      puts format("  [%s] new path #%d pcs=%d stack=%d %s",
                  label, written, pcs.size, stack.size,
                  dump["error"] ? "error=#{dump['error']['type']}" : "")
    end

    # Expand: one child per branch point, inheriting the parent's seeds.
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

  summary = {
    "entrypoint"         => ep,
    "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
    "request_variants"   => cfg[:variants].keys,
    "runs_executed"      => runs,
    "distinct_paths"     => written,
    "path_conditions_written" => pc_total,
    "states_tried"       => seen_states.size,
    "stack_remaining"    => stack.size,
    "worklist_drained"   => stack.empty?,
    "max_runs_per_ep"    => MAX_RUNS_PER_EP,
    "elapsed_seconds"    => (Time.now - ep_started).round(1),
    "run_errors"         => errors,
    "unflippable_pcs"    => unflippable,
  }
  File.write(File.join(dir, "exploration_summary.json"), JSON.pretty_generate(summary))
  overall[ep] = summary
  puts "  -> runs=#{runs} paths=#{written} pcs=#{pc_total} drained=#{stack.empty?} errors=#{errors.inspect}"
end

elapsed = Time.now - started
File.write(File.join(RESULTS, "elapsed_seconds.txt"), "#{elapsed.round(1)}\n")
File.write(File.join(RESULTS, "exploration_summary.json"),
           JSON.pretty_generate({ "elapsed_seconds" => elapsed.round(1), "entrypoints" => overall }))
puts "\n== conversations DSE done in #{elapsed.round(1)}s =="
