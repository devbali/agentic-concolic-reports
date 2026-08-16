# frozen_string_literal: true
# ============================================================================
# run_dse.rb — "contacts_aspects_blocks" batch, prefix-directed DSE.
#
# WHY THIS REPLACES run_concolic.rb / run_phase2.rb / run_phase3.rb
# -----------------------------------------------------------------
# Those runners fed CoverageChecker's `concrete_values` suggestions back as
# seed_overrides wholesale. Symbolic var names carry the interceptor's
# PER-RUN call ordinal (SYM_RESULT_<func>_<idx>, minted in
# src/ruby_runtime/call_interceptor.rb:140), so flipping an early branch
# renumbers every later var: a suggestion naming `first_3_*` harvested from
# run A is meaningless when applied to run B with a different prefix. That
# workflow chases a moving target.
#
# This runner does classic prefix-directed DSE instead. From an observed
# path [c0..cn] it emits one child per k that INHERITS the parent's seed
# dict (so the prefix c0..c_{k-1} replays identically and those ordinals
# stay valid) and adds EXACTLY ONE flip for c_k. Ordinals are assigned in
# execution order, so a flip at k can only renumber vars AFTER k. Paths are
# deduped on their signature; the worklist is expanded until it drains or a
# per-entrypoint cap (MAX_RUNS / TIME_BUDGET) is hit.
#
# The harness (symbolic user + ActionController::TestCase plumbing) is the
# one from run_concolic.rb, with one change: the symbolic current_user is
# rebuilt FRESH PER RUN so that (a) seed_overrides apply to its column vars
# and (b) mutable state (hidden_shareables) does not leak between runs.
#
# Neither src/ nor the shared concolic_targets.rb is modified — this is
# purely a runner-local exploration strategy.
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot <abs path to this file>
# Env:
#   EPS         comma-separated entrypoint names (default: all 13)
#   MAX_RUNS    per-entrypoint execution cap        (default 1500)
#   TIME_BUDGET per-entrypoint seconds              (default 300)
# ============================================================================
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "/home/dev/project/reports/diaspora/results/contacts_aspects_blocks/targets"
require "json"
require "set"
require "digest"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
# Batch-local wall fixes — MUST install after the shared targets (last-one-wins).
ContactsAspectsBlocksTargets.install!($interceptor)

RESULTS     = File.dirname(File.expand_path(__FILE__))
MAX_RUNS    = (ENV["MAX_RUNS"] || 1500).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 300).to_i

# ---------------------------------------------------------------------------
# Symbolic current_user — rebuilt per run so seeds apply to its columns.
# Identity (id / person_id) stays concrete: it is only used to BUILD where
# clauses, and a symbolic id there makes Arel quote a symbolic value.
# ---------------------------------------------------------------------------
def build_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user)")
  person.define_singleton_method(:id) { 1 }
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:id) { 1 }
  user.define_singleton_method(:guid) { "abc123" }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:aspects)  { Aspect.all }
  user.define_singleton_method(:contacts) { Contact.all }
  user.define_singleton_method(:blocks)   { Block.all }
  # auto_follow_back_aspect is an association reader, not a column: supply a
  # symbolic Aspect so `aspect.id == current_user.auto_follow_back_aspect.id`
  # stays a symbolic compare (mirrors what the real association returns).
  user.define_singleton_method(:auto_follow_back_aspect) do
    ConcolicTargets.symbolic_instance(Aspect, "SYM_AUTO_FOLLOW_ASPECT", "auto_follow_back_aspect")
  end
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
# Entrypoints. One params configuration per entrypoint (the primary request
# shape); exploration happens over SEEDS, not over params.
# ---------------------------------------------------------------------------
EPS = {
  "contacts_index"                 => { ctrl: "ContactsController",           action: :index,                 params: { a_id: 1 },                                    format: :html },
  "community_spotlight"            => { ctrl: "ContactsController",           action: :spotlight,             params: {},                                             format: :html },
  "aspects_create"                 => { ctrl: "AspectsController",            action: :create,                params: { aspect: { name: "Family" }, person_id: 2 },   format: nil },
  "aspects_show"                   => { ctrl: "AspectsController",            action: :show,                  params: { id: 1 },                                      format: nil },
  "aspects_update"                 => { ctrl: "AspectsController",            action: :update,                params: { id: 1, aspect: { name: "New" } },             format: nil },
  "aspects_destroy"                => { ctrl: "AspectsController",            action: :destroy,               params: { id: 1 },                                      format: nil },
  "aspects_update_order"           => { ctrl: "AspectsController",            action: :update_order,          params: { ordered_aspect_ids: [1, 2] },                 format: nil },
  "aspects_toggle_chat_privilege"  => { ctrl: "AspectsController",            action: :toggle_chat_privilege, params: { id: 1 },                                      format: nil },
  "aspect_memberships_create"      => { ctrl: "AspectMembershipsController",  action: :create,                params: { person_id: 2, aspect_id: 1 },                 format: :json },
  "aspect_memberships_destroy"     => { ctrl: "AspectMembershipsController",  action: :destroy,               params: { id: 1 },                                      format: :json },
  "blocks_create"                  => { ctrl: "BlocksController",             action: :create,                params: { block: { person_id: 2 } },                    format: nil },
  "blocks_destroy"                 => { ctrl: "BlocksController",             action: :destroy,               params: { id: 1 },                                      format: nil },
  "share_visibilities_update"      => { ctrl: "ShareVisibilitiesController",  action: :update,                params: { post_id: 1 },                                 format: nil },
}.freeze

def run_one(ep, label, seeds)
  cfg  = EPS.fetch(ep)
  ConcolicTargets.seed_overrides = seeds
  user = build_user("CAB")
  ctrl, = make_harness(Object.const_get(cfg[:ctrl]))
  ctrl.singleton_class.define_method(:current_user) { user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  ctrl.request.format = cfg[:format] if cfg[:format]
  # Referer so `request.referer.include?(...)` / redirect_back have a value
  # (aspects#destroy, blocks#create/destroy). Plumbing, never branched
  # symbolically.
  ctrl.request.headers["HTTP_REFERER"] = "http://example.com/contacts"
  ctrl.params = Marshal.load(Marshal.dump(cfg[:params])).with_indifferent_access
  action = cfg[:action]
  dump = $interceptor.run(-> { ctrl.send(action); :ok }, {}, label: label, script: "run_dse.rb")
  # RUNNER-LOCAL WORKAROUND (reported, not patched): CallInterceptor keeps an
  # unbounded @all_calls history across runs (src/ruby_runtime/call_interceptor.rb
  # — `run` slices `@all_calls[old_count..]` but never trims). Over thousands of
  # DSE executions that retains every CallEvent of the whole session and blows
  # the 1000m JVM heap. `run` has already sliced out this run's calls by now, so
  # emptying the array here is safe and keeps the next run's old_count at 0.
  $interceptor.instance_variable_get(:@all_calls)&.clear
  dump
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

# Dedup keys are DIGESTS, not the full expression/seed strings: the sets live
# for the whole exploration and retaining raw PC text for thousands of paths is
# a needless heap cost under the 1000m JVM cap.
def sig_of(pcs)
  Digest::SHA256.hexdigest(pcs.map { |e, t| "#{e}:#{t}" }.join("|"))
end

def seed_key(seeds)
  Digest::SHA256.hexdigest(JSON.generate(seeds.sort_by { |k, _| k.to_s }.to_h))
end

INT_ISH = /(_id|_ids|_count|_size|_order_id|_number)\z/.freeze

# Parse the RHS of a recorded comparison.
#   -> [:lit, value] | [:var, name] | nil
def parse_operand(tok)
  t = tok.strip
  case t
  when "True"                 then [:lit, true]
  when "False"                then [:lit, false]
  when /\A-?\d+\z/            then [:lit, t.to_i]
  when /\A'(.*)'\z/m          then [:lit, Regexp.last_match(1)]
  when /\A"(.*)"\z/m          then [:lit, Regexp.last_match(1)]
  when /\Alen\([^()]+\)\z/    then [:var, t]      # SymbolicList length var
  when /\A[A-Za-z_][A-Za-z0-9_]*\z/ then [:var, t]
  end
end

# Choose an int v with `v OP lit` == want.
def int_value_for(op, lit, want)
  case op
  when "==" then want ? lit : lit + 1
  when "!=" then want ? lit + 1 : lit
  when "<"  then want ? lit - 1 : lit
  when "<=" then want ? lit : lit + 1
  when ">"  then want ? lit + 1 : lit
  when ">=" then want ? lit : lit - 1
  end
end

# ---------------------------------------------------------------------------
# flip_seed — return a seed fragment that forces `expr` to `want_taken`.
#
# Every PC this app emits is a comparison of a symbolic var against a literal
# or against another symbolic var (SymbolicInt#op_cmp, SymbolicBool#==/!=/!,
# SymbolicString#==/!=/empty?, SymbolicList#empty?/any?). Both sides are
# seedable: finder mocks seed `<name>_not_found`, symbolic_instance seeds
# `<base>_<column>`, collection mocks seed `len(<name>)` — all through
# ConcolicTargets.seed_for. Returns nil for shapes we cannot invert; those
# are counted and reported rather than silently dropped.
# ---------------------------------------------------------------------------
def flip_seed(expr, want_taken)
  m = /\A\((.+?) (==|!=|<=|>=|<|>) (.+)\)\z/m.match(expr.to_s.strip)
  return nil unless m
  lhs = parse_operand(m[1])
  op  = m[2]
  rhs = parse_operand(m[3])
  return nil if lhs.nil? || rhs.nil? || lhs[0] != :var

  lname = lhs[1]

  if rhs[0] == :lit
    lit = rhs[1]
    case lit
    when true, false
      v = (op == "==") == want_taken ? lit : !lit
      return { lname => v }
    when Integer
      v = int_value_for(op, lit, want_taken)
      return v.nil? ? nil : { lname => v }
    when String
      return nil unless %w[== !=].include?(op)
      eq = (op == "==") == want_taken
      return { lname => eq ? lit : (lit.empty? ? "concolic_other" : "") }
    else
      return nil
    end
  end

  # var OP var — seed BOTH sides. Type is not recoverable from the expr, so
  # use the name shape: *_id / *_count / len(...) are integers, anything else
  # is treated as a string (only ==/!= are tracked for strings).
  rname = rhs[1]
  intish = [lname, rname].all? { |n| n.start_with?("len(") || n =~ INT_ISH }
  if intish
    base = 7
    other = int_value_for(op, base, want_taken)
    return nil if other.nil?
    { lname => other, rname => base }
  else
    return nil unless %w[== !=].include?(op)
    eq = (op == "==") == want_taken
    { lname => "concolic_a", rname => eq ? "concolic_a" : "concolic_b" }
  end
end

# ---------------------------------------------------------------------------
# Per-entrypoint exploration
# ---------------------------------------------------------------------------
def explore(ep)
  dir = File.join(RESULTS, ep)
  Dir.mkdir(dir) unless Dir.exist?(dir)

  puts "\n== #{ep} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
  started     = Time.now
  stack       = [{}]
  seen_seeds  = Set.new
  seen_paths  = Set.new
  unflippable = Hash.new(0)
  errors      = Hash.new(0)
  runs        = 0
  dup_paths   = 0
  written     = 0
  stop_reason = "worklist_drained"

  until stack.empty?
    if runs >= MAX_RUNS
      stop_reason = "max_runs"
      puts "[stop] MAX_RUNS reached"
      break
    end
    if Time.now - started > TIME_BUDGET
      stop_reason = "time_budget"
      puts "[stop] time budget exhausted"
      break
    end

    seeds = stack.pop
    key = seed_key(seeds)
    next if seen_seeds.include?(key)
    seen_seeds << key

    runs += 1
    label = format("dse%04d", runs)

    begin
      dump = run_one(ep, label, seeds)
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "[#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 140]}"
      errors["harness:#{e.class}"] += 1
      next
    end

    errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

    pcs = path_conditions(dump)
    sig = sig_of(pcs)

    if seen_paths.include?(sig)
      # Same path as an earlier run — nothing new for the execution tree, and
      # nothing new to expand: the flips of THIS path were already queued when
      # it was first observed (only the inherited seed dict differs, and the
      # prefix it replays is identical). Re-expanding duplicates makes the
      # frontier grow as O(branching^depth) with no new coverage — with the
      # deeper trees the batch-local predicate mocks open up, that alone took
      # aspect_memberships_destroy from "drains in 27 runs" to "400 runs, 8
      # paths, not drained".
      dup_paths += 1
      next
    else
      seen_paths << sig
      written += 1
      File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
      if written <= 3 || written % 25 == 0
        puts format("  [%s] paths=%d runs=%d pcs=%d stack=%d %s",
                    label, written, runs, pcs.size, stack.size,
                    dump["error"] ? "error=#{dump['error']['type']}" : "")
      end
    end

    # Expand: one child per branch point, flipping exactly that branch and
    # inheriting the parent's seeds so the prefix replays identically.
    pcs.each do |(expr, taken)|
      fl = flip_seed(expr, !taken)
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
    "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
    "runs_executed"      => runs,
    "distinct_paths"     => written,
    "duplicate_path_runs" => dup_paths,
    "seed_sets_tried"    => seen_seeds.size,
    "stack_remaining"    => stack.size,
    "worklist_exhausted" => stack.empty?,
    "stop_reason"        => stop_reason,
    "max_runs"           => MAX_RUNS,
    "time_budget"        => TIME_BUDGET,
    "elapsed_seconds"    => elapsed.round(1),
    "run_errors"         => errors,
    "unflippable_pcs"    => unflippable,
  }
  File.write(File.join(dir, "exploration_summary.json"), JSON.pretty_generate(summary))
  puts format("== %s done: runs=%d paths=%d drained=%s (%s) %.1fs errors=%s unflippable=%d",
              ep, runs, written, stack.empty?, stop_reason, elapsed, errors.inspect,
              unflippable.keys.size)
  summary
end

selected = (ENV["EPS"] || EPS.keys.join(",")).split(",").map(&:strip).reject(&:empty?)
bad = selected - EPS.keys
raise "unknown entrypoints: #{bad.inspect}" unless bad.empty?

puts "== contacts_aspects_blocks :: exploring #{selected.size} entrypoint(s) =="
all = selected.map do |ep|
  begin
    explore(ep)
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts "!! #{ep} ABORTED #{e.class}: #{e.message.to_s[0, 200]}"
    puts (e.backtrace || []).first(8).join("\n")
    { "entrypoint" => ep, "aborted" => "#{e.class}: #{e.message.to_s[0, 200]}" }
  end
end

File.write(File.join(RESULTS, "exploration_#{selected.first}.json"), JSON.pretty_generate(all))
puts "\n== batch group done =="
