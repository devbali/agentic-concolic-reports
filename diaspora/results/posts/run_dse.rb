#!/usr/bin/env jruby
# frozen_string_literal: true
# ============================================================================
# run_dse.rb — "posts" batch: prefix-directed DSE for every entrypoint.
#
# WHY THIS REPLACES run_concolic.rb / run_phase4.rb / run_phase5.rb
# -----------------------------------------------------------------
# Those runners fed CoverageChecker's `concrete_values` dicts back as
# seed_overrides wholesale. Symbolic result names carry the interceptor's
# PER-RUN call ordinal (SYM_RESULT_<func>_<idx>, minted in
# src/ruby_runtime/call_interceptor.rb:140). Flipping an EARLY branch changes
# how many intercepted calls happen before a later one, which RENUMBERS every
# later var — so a suggestion naming `first_3_*` is meaningless unless the run
# it is applied to has the same execution prefix. Cross-run seed mixing chases
# a moving target (on posts#show: 100 rounds, 296 nodes / 289 missing, never
# converged).
#
# THE FIX (classic DSE prefix extension, identical to the verified
# posts_show/run_proper.rb): from an observed path [c0..cn], emit one child per
# k that INHERITS the parent's seeds (so prefix c0..c_{k-1} replays
# identically, keeping those ordinals valid) and adds EXACTLY ONE flip for c_k.
# Ordinals are assigned in execution order, so a flip at k can only renumber
# vars AFTER k. Dedup on the path signature; expand until the worklist drains.
#
# Touches neither src/ (source discipline) nor the shared concolic_targets.rb
# (13 agents run concurrently against it) nor the diaspora app source. It is
# purely a runner-local exploration strategy over the SAME controller
# invocation harness the previous runners used.
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot <abs path to this file>
#
# Env:
#   EPS         comma-separated entrypoint names (default: all except posts_show,
#               which has its own restored runner posts_show/run_proper.rb)
#   MAX_RUNS    per-entrypoint execution cap (default 1500)
#   TIME_BUDGET per-entrypoint seconds     (default 600)
# ============================================================================

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
# The LIVE framework target declarations, shared by all 13 batches (read-only).
require "/home/dev/project/reports/diaspora/concolic_targets"
# Batch-local wall fixes (addendum): iterable collection lists + Calculations#pluck.
# MUST load after the shared file — declare_target is last-one-wins.
require "/home/dev/project/reports/diaspora/results/posts/targets"
require "json"
require "set"
require "digest"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
PostsTargets.install!($interceptor)

RESULTS    = File.dirname(File.expand_path(__FILE__))
MAX_RUNS    = (ENV["MAX_RUNS"]    || 1500).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 600).to_i

# ---------------------------------------------------------------------------
# Symbolic user — same harness as the verified run_concolic.rb / run_proper.rb.
# id stays SYMBOLIC (README "Symbolic entrypoint variables"); person.id stays
# concrete because it is only ever fed into WHERE-clause construction.
# ---------------------------------------------------------------------------
def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user)")
  person.define_singleton_method(:id) { 1 }
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:guid) { "abc123" }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:aspects)       { Aspect.all }
  user.define_singleton_method(:aspect_ids)    { [1] }
  user.define_singleton_method(:photos)        { Photo.all }
  user.define_singleton_method(:participations){ Participation.all }
  user.define_singleton_method(:contacts)      { Contact.all }
  user.define_singleton_method(:blocks)        { Block.all }
  user
end

$posts_user = symbolic_user("PO")

def make_harness(controller_class)
  cname = controller_class.to_s.sub(/Controller\z/, "ControllerTest")
  Object.const_set(cname, Class.new(ActionController::TestCase)) unless Object.const_defined?(cname)
  test_class = Object.const_get(cname)
  test_class.instance_variable_set(:@concolic_ctrl, controller_class)
  def test_class.determine_default_controller_class(name)
    @concolic_ctrl
  end
  tc = test_class.new("noop")
  tc.setup_controller_request_and_response
  tc.instance_variable_set(:@routes, Rails.application.routes)
  ctrl = tc.instance_variable_get(:@controller)
  [ctrl, tc]
end

# ---------------------------------------------------------------------------
# Entrypoint table. Params / signed_in are copied verbatim from the previously
# verified run_concolic.rb harness so the invocation is unchanged; only the
# exploration strategy differs.
#
# `format:` is a HARNESS fix, not app modeling: these actions are JSON routes
# and their `respond_to` blocks have no HTML branch, so without it the request
# format defaults to :html and the action returns 406 / raises UnknownFormat
# before reaching any symbolic branch (that is what made posts_mentionable
# report 0 PCs in the previous round).
#
# `anon: true` + `dir:`/`prefix:` add a SECOND SCENARIO for the three routes
# that are reachable without a session. `PostService#find!` branches on a bare
# `if user`, which the runtime cannot record (Ruby truthiness gap, src/TODO.txt)
# and the DSE cannot flip: it is a property of the request, not of a symbolic
# value. With the inherited harness (current_user always returns the symbolic
# user, only `user_signed_in?` false) the anonymous half — `find_public!`,
# `post.public?`, `raise Diaspora::NonPublic` — is unreachable. The anonymous
# scenario supplies `current_user = nil` and writes into the SAME entrypoint
# directory under a different label prefix, so the per-entrypoint coverage
# check sees both halves of that branch.
# ---------------------------------------------------------------------------
CONFIG = {
  "posts_show" => {
    ctrl: "PostsController", action: :show, signed_in: false,
    params: { id: 1 },
  },
  "posts_oembed" => {
    ctrl: "PostsController", action: :oembed, signed_in: false,
    params: { url: "http://example.com/posts/1" },
  },
  "posts_mentionable" => {
    ctrl: "PostsController", action: :mentionable, signed_in: true,
    params: { id: 1, q: "bob" }, format: :json,
  },
  "posts_destroy" => {
    ctrl: "PostsController", action: :destroy, signed_in: true,
    params: { id: 1 },
  },
  "reshares_create" => {
    ctrl: "ResharesController", action: :create, signed_in: true,
    params: { root_guid: "abc123" }, format: :json,
  },
  "reshares_index" => {
    ctrl: "ResharesController", action: :index, signed_in: false,
    params: { post_id: 1 },
  },
  "status_messages_new" => {
    ctrl: "StatusMessagesController", action: :new, signed_in: true,
    params: { person_id: 1 },
  },
  "status_messages_create" => {
    ctrl: "StatusMessagesController", action: :create, signed_in: true,
    params: { status_message: { text: "hello" }, aspect_ids: "all_aspects" },
    format: :json,
  },
  "status_messages_bookmarklet" => {
    ctrl: "StatusMessagesController", action: :bookmarklet, signed_in: true,
    params: { content: "x", title: "t", url: "http://e.com", notes: "n" },
  },

  # --- anonymous scenarios (same entrypoint dir, different label prefix) ----
  "posts_show_anon" => {
    ctrl: "PostsController", action: :show, signed_in: false, anon: true,
    params: { id: 1 }, dir: "posts_show", prefix: "anon",
  },
  "posts_oembed_anon" => {
    ctrl: "PostsController", action: :oembed, signed_in: false, anon: true,
    params: { url: "http://example.com/posts/1" },
    dir: "posts_oembed", prefix: "anon",
  },
  "reshares_index_anon" => {
    ctrl: "ResharesController", action: :index, signed_in: false, anon: true,
    params: { post_id: 1 }, dir: "reshares_index", prefix: "anon",
  },
}.freeze

ANON_EPS    = CONFIG.keys.select { |k| CONFIG[k][:anon] }
DEFAULT_EPS = CONFIG.keys - ["posts_show"] - ANON_EPS

def run_one(ep, label, seeds)
  cfg = CONFIG.fetch(ep)
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(Object.const_get(cfg[:ctrl]))
  signed_in = cfg[:signed_in]
  user = cfg[:anon] ? nil : $posts_user
  ctrl.singleton_class.define_method(:current_user) { user }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  ctrl.params = cfg[:params].with_indifferent_access
  if cfg[:format]
    ctrl.request.set_header("action_dispatch.request.formats", [Mime[cfg[:format]]])
  end
  action = cfg[:action]
  dump = $interceptor.run(-> { ctrl.send(action); :ok }, {}, label: label, script: "run_dse.rb")
  # RUNNER-LOCAL WORKAROUND for a src/ruby_runtime leak (reported, not patched):
  # CallInterceptor#run appends every TargetCall (with its full PC snapshot) to
  # @all_calls and NEVER trims it — it only slices @all_calls[old_count..] for
  # the current run. Over a 15k-execution DSE that array is the dominant heap
  # consumer and OOM-killed a posts_show run on this box. Dropping the history
  # after each run is behaviour-preserving: `run` recomputes old_count from the
  # (now empty) array on the next call.
  $interceptor.instance_variable_get(:@all_calls).clear
  dump
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

# ---------------------------------------------------------------------------
# Flip a single path condition into a seed override.
#
# PC shapes this app emits:
#   (VAR == LITERAL)      scalar equality / boolean predicate reader.
#   (VAR != LITERAL)      the negated form (e.g. AR's json formatter emits
#                         `(guid != StringVal(''))`).
#   (len(NAME) != 0)      SymbolicList emptiness. The collection mock builds
#                         its length via seed_for("len(NAME)", 1)
#                         (concolic_targets.rb:452), so "len(NAME)" is itself a
#                         seedable key: 1 => non-empty, 0 => empty.
# Literals appear either Ruby-side ('x', 42, True/False) or already rendered as
# Z3 terms (StringVal('x'), IntVal(3), BoolVal(True)) — both are accepted.
#
# Anything else is counted in `unflippable` and reported, never silently
# dropped. (Some symlists are constructed with a hardcoded length, so seeding
# their len(...) has no effect — that run simply replays a known path and is
# deduped, it does not loop.)
# ---------------------------------------------------------------------------
def parse_literal(lit)
  lit = lit.strip
  if (m = /\A(?:StringVal|IntVal|BoolVal|RealVal)\((.*)\)\z/m.match(lit))
    lit = m[1].strip
  end
  case lit
  when "True"  then true
  when "False" then false
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

  m = /\A\(([A-Za-z_][A-Za-z0-9_]*) (==|!=) (.+)\)\z/m.match(s)
  return nil unless m
  var, op, lit = m[1], m[2], m[3]

  parsed = parse_literal(lit)
  return nil if parsed.nil?

  # Truth of the PC is (VAR == LIT) for "==" and its negation for "!=".
  want_equal = (op == "==") ? want_taken : !want_taken
  value = want_equal ? parsed : other_value(parsed)
  return nil if value.nil?

  { var => value }
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

# 16 hex chars of SHA-256. Collision probability over the ~10^4-10^5 keys this
# explores is ~10^-10, and the sets are only used for dedup (a collision would
# skip one redundant execution, never corrupt a recorded path).
def digest(str)
  Digest::SHA256.hexdigest(str)[0, 16]
end

# ---------------------------------------------------------------------------
# Prefix-directed exploration of one entrypoint.
#
# MEMORY DISCIPLINE (this box runs up to 2 JRuby+Rails VMs under a hard
# -J-Xmx1000m cap, and an earlier posts_show exploration reached 1.8GB RSS and
# was killed):
#   * seen_seeds / seen_paths hold 16-char digests, not the full JSON seed
#     dicts / path signatures.
#   * the worklist does NOT store a materialised seed Hash per entry. A child
#     is (parent_id, one flip) — the parent seed dict is kept once, as a JSON
#     string, in `parents`, and children are rebuilt on pop. `parents` grows
#     with the number of EXPANDED paths (thousands), not with the worklist
#     (tens of thousands).
#   * STACK_LIMIT bounds the frontier; a truncation is counted and reported so
#     a capped result is never presented as a fixpoint.
# ---------------------------------------------------------------------------
STACK_LIMIT = (ENV["STACK_LIMIT"] || 200_000).to_i

def explore(ep)
  cfg    = CONFIG.fetch(ep)
  prefix = cfg[:prefix] || "dse"
  dir    = File.join(RESULTS, cfg[:dir] || ep)
  Dir.mkdir(dir) unless Dir.exist?(dir)

  puts "\n== #{ep} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
  started = Time.now

  parents     = ["{}"]          # id -> parent seed dict, as compact JSON
  stack       = [[0, nil]]      # [parent_id, flip-json or nil]
  seen_seeds  = Set.new
  seen_paths  = Set.new
  unflippable = Hash.new(0)
  errors      = Hash.new(0)
  runs        = 0
  written     = 0
  dropped     = 0
  stop_reason = "worklist drained"

  until stack.empty?
    if runs >= MAX_RUNS
      stop_reason = "MAX_RUNS cap (#{MAX_RUNS})"
      puts "[stop] #{stop_reason}"
      break
    end
    if Time.now - started > TIME_BUDGET
      stop_reason = "TIME_BUDGET cap (#{TIME_BUDGET}s)"
      puts "[stop] #{stop_reason}"
      break
    end

    pid, flip_json = stack.pop
    seeds = JSON.parse(parents[pid])
    seeds.merge!(JSON.parse(flip_json)) if flip_json

    key = digest(JSON.generate(seeds.sort.to_h))
    next if seen_seeds.include?(key)
    seen_seeds << key

    runs += 1
    label = format("%s%04d", prefix, runs)

    begin
      dump = run_one(ep, label, seeds)
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "[#{ep}/#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 140]}"
      errors["harness:#{e.class}"] += 1
      next
    end

    errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

    pcs = path_conditions(dump)
    sig = digest(sig_of(pcs))

    # Only persist genuinely NEW paths — a repeated path adds nothing to the
    # execution tree and would only inflate the dump count. It also means a
    # duplicate is never expanded, so ineffective flips cannot loop.
    next if seen_paths.include?(sig)

    seen_paths << sig
    written += 1
    File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
    dump = nil

    if written <= 5 || written % 100 == 0
      puts format("[%s/%s] paths=%d runs=%d pcs=%d stack=%d parents=%d",
                  ep, label, written, runs, pcs.size, stack.size, parents.size)
    end

    # Expand: one child per branch point, flipping exactly that branch and
    # inheriting the parent's seeds so the prefix replays identically.
    my_id = parents.size
    parents << JSON.generate(seeds)
    pcs.each do |(expr, taken)|
      fl = flip_seed(expr, !taken)
      if fl.nil?
        unflippable[expr] += 1
        next
      end
      ckey = digest(JSON.generate(seeds.merge(fl).sort.to_h))
      next if seen_seeds.include?(ckey)
      if stack.size >= STACK_LIMIT
        dropped += 1
        next
      end
      stack.push([my_id, JSON.generate(fl)])
    end
  end

  elapsed = Time.now - started
  summary = {
    "entrypoint"         => ep,
    "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
    "runs_executed"      => runs,
    "distinct_paths"     => written,
    "seed_sets_tried"    => seen_seeds.size,
    "stack_remaining"    => stack.size,
    "frontier_entries_dropped" => dropped,
    "worklist_exhausted" => stack.empty? && dropped.zero?,
    "stop_reason"        => dropped.positive? ? "#{stop_reason} + STACK_LIMIT truncation" : stop_reason,
    "max_runs"           => MAX_RUNS,
    "time_budget"        => TIME_BUDGET,
    "stack_limit"        => STACK_LIMIT,
    "elapsed_seconds"    => elapsed.round(1),
    "run_errors"         => errors,
    "unflippable_pcs"    => unflippable,
    "scenario"           => (cfg[:anon] ? "anonymous (current_user = nil)" : "authenticated (symbolic current_user)"),
  }
  sfile = prefix == "dse" ? "exploration_summary.json" : "exploration_summary_#{prefix}.json"
  File.write(File.join(dir, sfile), JSON.pretty_generate(summary))

  puts "-- #{ep}: runs=#{runs} paths=#{written} drained=#{summary['worklist_exhausted']} " \
       "stop=#{summary['stop_reason']} elapsed=#{elapsed.round(1)}s " \
       "errors=#{errors.inspect} unflippable=#{unflippable.keys.size}"
  summary
end

eps = (ENV["EPS"] && !ENV["EPS"].strip.empty?) ? ENV["EPS"].split(",").map(&:strip) : DEFAULT_EPS
bad = eps - CONFIG.keys
raise "unknown entrypoints: #{bad.inspect}" unless bad.empty?

t0 = Time.now
summaries = eps.map { |ep| explore(ep) }
File.write(File.join(RESULTS, "elapsed_seconds.txt"), "#{(Time.now - t0).round(1)}\n")

puts "\n== run_dse.rb done (#{(Time.now - t0).round(1)}s) =="
summaries.each do |s|
  puts format("  %-30s runs=%-6d paths=%-6d drained=%-6s %s",
              s["entrypoint"], s["runs_executed"], s["distinct_paths"],
              s["worklist_exhausted"], s["stop_reason"])
end
