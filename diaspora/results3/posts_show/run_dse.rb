#!/usr/bin/env jruby
# frozen_string_literal: true
#
# posts_show — results2 rerun with FULLY SYMBOLIC entrypoint arguments.
#
# Ported from ../../results/posts/run_dse.rb (+ the verified reference runner
# ../../results/posts/posts_show/run_proper.rb), restricted to posts#show
# ONLY, keeping BOTH request scenarios the source batch ran for it: the
# signed-in one and the anonymous one (`PostService#find!`'s `if user` is a
# bare-truthiness branch — Ruby truthiness gap, src/TODO.txt — so it cannot
# be flipped by DSE; the two scenarios are how the source batch covered both
# sides). Both write into THIS single directory with distinct label prefixes
# ("auth"/"anon") per the results2/README.md layout.
#
# THE POINT OF THIS RERUN (results2/README.md + task brief):
#   1. params[:id]: concrete `1` -> symbolic SYM_PARAM_id, a SymbolicSTRING
#      seeded "1". PostService#post_key does
#      `id_or_guid.to_s.length < 16 ? :id : :guid` — a concrete Integer records
#      no PC here (concrete `.to_s.length` compare), but a SymbolicString's
#      `.length` returns a SymbolicInt `Length(SYM_PARAM_id)` (string.rb:194)
#      and the compare DOES record a PC. `.to_s`/`.to_str` on SymbolicString
#      are identity (string.rb:70-76), so the chain survives.
#   2. Signed-in scenario's symbolic_user: the `user.id = 1` pin is REMOVED —
#      SYM_USER_<tag>_id now flows into share_visibilities/people queries as a
#      genuine $$() bind. person.id, person_id and guid pins are also
#      attempted symbolic (see symbolic_user below for what stuck vs what
#      would need documenting as a forced pin).
#   3. Association scoping: aspects/photos/participations/contacts/blocks were
#      wired to `Klass.all` in the source batch's symbolic_user. Rescoped here
#      to the real foreign key (`user_id`/`author_id`) using the symbolic
#      user/person id, so the id lands in the SQL as a $$() bind instead of
#      being dropped by an unscoped relation.
#
# WHY PREFIX-DIRECTED DSE (unchanged rationale — see BATCH_BRIEFING.md /
# main README.md): SYM_RESULT_<func>_<idx> names carry a per-run call
# ordinal (call_interceptor.rb:140); flipping an early branch renumbers every
# later var, so feeding CoverageChecker's concrete_values back wholesale is
# unsound. Instead: from an observed path [c0..cn], emit one child per k that
# INHERITS the parent's seeds (prefix c0..c_{k-1} replays identically) and
# adds exactly one flip for c_k. Dedup on path signature; expand until the
# worklist drains or a cap is hit.
#
# Touches neither src/, the shared concolic_targets.rb, nor the diaspora app
# source — this directory carries PRIVATE copies of concolic_targets.rb and
# targets.rb (results2/README.md layout).
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
#       /home/dev/project/reports/diaspora/results2/posts_show/run_dse.rb
#
# Env: MAX_RUNS (default 300 per scenario), TIME_BUDGET seconds (default 1200
# per scenario) — capped deliberately per the task brief; the source batch's
# posts_show ran 14541 executions / 2113 paths over ~156s WITHOUT symbolic
# params/user, so full convergence here is not assumed. Report says whether
# each scenario's worklist drained or hit the cap.

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
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
PostsTargets.install!($interceptor)
PostsShowFinderNaming.install!($interceptor)
PostsShowMentionLookupNaming.install!($interceptor)

# results3: render family removed (concolic_targets.rb header MOCK LEDGER) —
# the real render pipeline now runs. Disable the layout so the real
# per-endpoint content (show.html.haml's content_for blocks + the JSON
# presenter chain) executes, but the site-chrome layout (header/nav/asset
# tags — orthogonal to this endpoint's query shape, its own large wall
# surface per people_show's REPORT.md) does not. Same move
# notifications_index/people_show made.
PostsController.layout(false)

HERE        = File.dirname(File.expand_path(__FILE__))
MAX_RUNS    = (ENV["MAX_RUNS"]    || 300).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 1200).to_i
STACK_LIMIT = (ENV["STACK_LIMIT"] || 50_000).to_i

# ---------------------------------------------------------------------------
# Symbolic user (signed-in scenario only). Ported from
# ../../results/posts/run_dse.rb's symbolic_user, with the pins removed per
# results2/README.md items 2-5.
# ---------------------------------------------------------------------------
def symbolic_user(tag)
  # person.id: results2 item 3 — TRY SYMBOLIC FIRST (no pin). Feeds
  # querent_is_author's `:author_id => @querent.person.id` in evil_query.rb
  # and PostInteractionPresenter#participations' `where(author: current_user.person)`.
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user's person)")

  # user.id: results2 item 2 — PIN REMOVED. Feeds evil_query.rb's
  # `querent_has_visibility` -> `where(share_visibilities: {user_id: @querent.id})`.
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:person) { person }

  # NOTE what's intentionally NOT pinned (results2 item 4, "attempt symbolic,
  # document forced pins"): `guid` is delegated to person on the real User
  # model (`delegate :guid, ..., to: :person`, user.rb:57) — with no
  # singleton override it now resolves through the real delegate to
  # `person.guid`, i.e. SYM_PERSON_#{tag}_guid, symbolically. `person_id` is a
  # real `users` column, so symbolic_instance already gives it its own
  # SymbolicInt (SYM_USER_#{tag}_person_id) — independent of SYM_PERSON_#{tag}_id
  # (the mock does not enforce person_id == person.id; this was already true
  # when both were pinned to the coincidentally-equal concrete `1`, so it is
  # not a regression, just now visible as two independent symbols. See
  # REPORT.md.)

  # Association scoping (results2 item 5): the source batch wired these to
  # `Klass.all` (unscoped). Rescoped to the real FK, symbolic id included, so
  # the query's WHERE clause carries a genuine $$() bind instead of being
  # dropped. `Aspect`/`Contact`/`Block` belong_to :user (user_id FK);
  # `Photo`/`Participation` belong_to :author (Person, author_id FK) per
  # Diaspora::Fields::Author.
  user.define_singleton_method(:aspects)        { Aspect.where(user_id: user.id) }
  user.define_singleton_method(:photos)         { Photo.where(author_id: person.id) }
  user.define_singleton_method(:participations) { Participation.where(author_id: person.id) }
  user.define_singleton_method(:contacts)       { Contact.where(user_id: user.id) }
  user.define_singleton_method(:blocks)         { Block.where(user_id: user.id) }
  user
end

$posts_user = symbolic_user("PO")

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
  # results3 FIX (render family removed — differs from results2, which never
  # needed a real response object since render was mocked terminal; same fix
  # notifications_index/people_show needed): setup_controller_request_and_
  # response wires @controller.request but NOT @controller.response — that
  # assignment only happens inside ActionController::TestCase#process's
  # dispatch call, which this runner deliberately does NOT use (it calls the
  # action method directly to keep params[:id] symbolic — Rack param
  # serialization would concretize it). Without this, @_response is nil and
  # performed?/any real render call crashes on it.
  ctrl.response = tc.instance_variable_get(:@response)
  [ctrl, tc]
end

# ---------------------------------------------------------------------------
# Both scenarios for posts#show, same as the source batch's CONFIG entries
# "posts_show" / "posts_show_anon" (results/posts/run_dse.rb:129-133,169-172).
# `signed_in: false` in BOTH is intentional and reproduced verbatim: the
# controller-level devise singleton `user_signed_in?` is never invoked on
# this action's code path (verified by reading posts_controller.rb — #show
# calls neither `authenticate_user!` nor `user_signed_in?`; the ONLY
# `user_signed_in?` on this path is PostPresenter's OWN private method,
# `current_user.present?`, independent of the controller singleton).
# ---------------------------------------------------------------------------
PARAM_SYM_NAME    = "SYM_PARAM_id"
PARAM_DEFAULT     = "1"

# results3: format is now a live dimension (render family removed — the
# html/json branches genuinely diverge: html's format.html renders the
# (layout-disabled) show.html.haml + gon.post via with_initial_interactions;
# json's format.json renders `presenter.with_interactions`, on-path for
# ActsAsApi::Collection#as_api_response and PostInteractionPresenter). Four
# scenarios cover auth/anon x html/json — mobile format (shared/
# _stream_element's much larger comments/likes/photos partial tree) is
# OUT OF SCOPE for this pass (see REPORT.md); not central to the mission's
# four named descents and disproportionate to add on top of them.
SCENARIOS = {
  "auth_html" => { anon: false, format: :html, desc: "authenticated, format.html (gon.post via with_initial_interactions)" },
  "anon_html" => { anon: true,  format: :html, desc: "anonymous, format.html" },
  "auth_json" => { anon: false, format: :json, desc: "authenticated, format.json (presenter.with_interactions)" },
  "anon_json" => { anon: true,  format: :json, desc: "anonymous, format.json" },
}.freeze

def run_one(prefix, label, seeds)
  PostsShowFinderNaming.reset_ctx! if defined?(PostsShowFinderNaming)
  PostsShowMentionLookupNaming.reset_ctx! if defined?(PostsShowMentionLookupNaming)
  ConcolicTargets.seed_overrides = seeds
  # boundary fix 2 (2026-09-03): per-run reset of the GonPreloadsShim ivar
  # (concolic_targets.rb X6b-preloads) so gon.preloads data cannot leak
  # across runs. Same contract as notifications run_dse.rb:156.
  if defined?(::Gon) && ::Gon.instance_variable_defined?(:@concolic_preloads)
    ::Gon.instance_variable_set(:@concolic_preloads, {})
  end
  ctrl, = make_harness(PostsController)
  scen = SCENARIOS.fetch(prefix)
  anon = scen[:anon]
  user = anon ? nil : $posts_user
  ctrl.singleton_class.define_method(:current_user) { user }
  ctrl.singleton_class.define_method(:user_signed_in?) { false }
  ctrl.request.format = scen[:format]
  # results3 FIX (companion to the response-wiring fix above): action_name is
  # normally set by process(action_name) inside dispatch, which this runner
  # bypasses. Left unset, default_render's template_exists? crashes on nil.
  ctrl.send(:action_name=, "show")

  # BUGFIX (results2 completion pass, coordinator finding shared across
  # endpoints 2026-08-18 — see comments_index/run_dse.rb's identical fix):
  # this MUST run INSIDE the $interceptor.run(body, ...) block, not before
  # it. CallInterceptor#run calls SymbolicFunc.reset! at its very start
  # (src/ruby_runtime/call_interceptor.rb:261-262), which clears
  # @registered_vars — including any symstr/symint/symbool call made
  # *before* `run` starts. The original version of this runner built
  # `sym_id = symstr(PARAM_SYM_NAME, ...)` here, outside the body lambda, so
  # the registration was wiped before the dump snapshot ran and
  # SYM_PARAM_id NEVER appeared in any dump's `symbolic_vars` list — even
  # though the var was used correctly everywhere else (SQL binds, the
  # `Length(SYM_PARAM_id) < 16` PC in post_key). Z3 then couldn't parse that
  # PC (undeclared free variable) and CoverageChecker silently dropped it
  # into `unevaluable_exprs`, excluding the length-dispatch expression (and
  # everything downstream of it) from the combination-coverage universe.
  # Moving the declaration inside the body lambda (after `run` resets state)
  # fixes this.
  body = lambda do
    id_seed = ConcolicTargets.seed_for(PARAM_SYM_NAME, PARAM_DEFAULT)
    sym_id  = symstr(PARAM_SYM_NAME, id_seed)
    ctrl.params = { id: sym_id }.with_indifferent_access
    ctrl.send(:show)
    :ok
  end

  dump = $interceptor.run(body, {}, label: label, script: "run_dse.rb")

  # RUNNER-LOCAL LEAK WORKAROUND (reported, not patched in src/):
  # CallInterceptor keeps an unbounded @all_calls history across runs
  # (src/ruby_runtime/call_interceptor.rb — `run` only slices
  # @all_calls[old_count..]). Clearing between runs is behaviour-preserving:
  # `run` recomputes old_count from the (now empty) array on the next call.
  $interceptor.instance_variable_get(:@all_calls).clear
  dump
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

# ---------------------------------------------------------------------------
# Flip a single "(VAR == LITERAL)" / "(VAR != LITERAL)" / "(len(NAME) != 0)"
# path condition — ported verbatim from results/posts/run_dse.rb.
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

# NAME BOUNDARY (2026-09-14) — keep length decisions FLIPPABLE.
#
# The runtimes used to mint a list's cardinality variable as `len(X)`; they now
# mint `SYM_LEN_X`, because `len(X)` is not a legal Python identifier and
# `concolic_engine/solver.py` exec/evals its declarations. The flip matchers
# below are written in the OLD spelling, so a new dump's `(SYM_LEN_X != 0)`
# would MISS the dedicated length branch — and the generic `(VAR op LIT)`
# matcher would catch it instead, producing a seed that IGNORES `want_taken`.
# That is a silently WRONG flip, not a clean miss: DSE would stop exploring
# list-cardinality decisions and never say so.
#
# Normalise to the matchers' spelling on the way in. Seed keys stay
# `len(...)`-spelled, which `concolic_targets.rb`'s `seed_for` accepts in both
# spellings, so pre-existing seed files and snapshots are unaffected.
# See reports/diaspora/docs/NAME_BOUNDARY_PLAN_20260914.md.
def canon_len(expr)
  expr.to_s.strip.gsub(/SYM_LEN_([A-Za-z0-9_]+)/, 'len(\1)')
end

def flip_seed(expr, want_taken)
  s = canon_len(expr)

  if (m = /\A\(len\((.+)\) != 0\)\z/m.match(s))
    return { "len(#{m[1]})" => (want_taken ? 1 : 0) }
  end

  m = /\A\(([A-Za-z_][A-Za-z0-9_]*) (==|!=) (.+)\)\z/m.match(s)
  return nil unless m
  var, op, lit = m[1], m[2], m[3]

  parsed = parse_literal(lit)
  return nil if parsed.nil?

  want_equal = (op == "==") ? want_taken : !want_taken
  value = want_equal ? parsed : other_value(parsed)
  return nil if value.nil?

  { var => value }
end

# NEW for results2: SymbolicString#length on the symbolic params[:id] is a
# SymbolicInt named "Length(VAR)" (string.rb:194); PostService#post_key
# branches on it (`id_or_guid.to_s.length < 16 ? :id : :guid`) — this branch
# did not exist with a concrete Integer id (concrete compares record no PC).
# Flip by reseeding VAR with a string of the length needed to invert the
# inequality (ported from results2/comments_index/run_dse.rb's flip_length_seed).
def flip_length_seed(expr, want_taken)
  m = /\A\(Length\(([A-Za-z_][A-Za-z0-9_]*)\) (<=|>=|==|!=|<|>) (-?\d+)\)\z/m.match(expr.to_s.strip)
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

def flip_any(expr, want_taken)
  flip_seed(expr, want_taken) || flip_length_seed(expr, want_taken)
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

def digest(str)
  Digest::SHA256.hexdigest(str)[0, 16]
end

# ---------------------------------------------------------------------------
# Prefix-directed exploration of one scenario. Same memory discipline as
# results/posts/run_dse.rb: seen_seeds/seen_paths hold digests only, parents
# hold one JSON string per EXPANDED path (not per worklist entry), STACK_LIMIT
# bounds the frontier with the truncation reported (never silently dropped).
# ---------------------------------------------------------------------------
def explore(prefix)
  puts "\n== posts_show/#{prefix} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
  started = Time.now

  parents     = ["{}"]
  stack       = [[0, nil]]
  # DEMAND-ROUND HOOK + LABEL_SUFFIX (ported from notifications_index, 2026-09-09).
  # Without LABEL_SUFFIX every round regenerates IDENTICAL filenames, so base
  # round 2 silently OVERWRITES round 1 (observed: corpus frozen at 12 052 for
  # 20 minutes while dumps were actively rewritten). Without EXTRA_SEEDS_JSON
  # and recorded `concolic_seeds` no demand round is possible at all.
  if ENV["EXTRA_SEEDS_JSON"] && File.exist?(ENV["EXTRA_SEEDS_JSON"])
    _extra = JSON.parse(File.read(ENV["EXTRA_SEEDS_JSON"]))
    _roots = _extra.map { |h| [0, JSON.generate(h)] }
    stack  = ENV["SEEDS_ONLY"] ? _roots : (_roots + stack)
    puts format("[seeds] %d extra roots from %s (SEEDS_ONLY=%s)",
                _roots.size, ENV["EXTRA_SEEDS_JSON"], ENV["SEEDS_ONLY"] ? "1" : "0")
  end

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
    # SEEDS_ONLY REPLAY (drift fix, 2026-09-10 — mirrors
    # notifications_index/run_dse.rb:400-412 verbatim). STATE- and PATH-dedup
    # are for FRONTIER exploration. In SEEDS_ONLY replay EVERY root must
    # produce its own dump: a rooted/demand/tree seed is matched back by the
    # recorded `concolic_seeds`, so a root skipped here leaves the caller
    # unable to tell whether its seed was honoured, contradicted, or never
    # evaluated — which is exactly the evidence a demand round is FOR. Both
    # notifications drive scripts (_chunk_drive.sh, _tree_drive.sh,
    # _diverse_drive.sh) run with SEEDS_ONLY=1, so a port of them against an
    # unconditional dedup silently under-produces.
    # UNTESTED against JRuby at the time of writing (preflight ran no runner):
    # smoke it with a 2-seed SEEDS_ONLY replay before any bulk drive.
    unless ENV["SEEDS_ONLY"]
      next if seen_seeds.include?(key)
      seen_seeds << key
    end

    runs += 1
    label = format("%s%04d%s", prefix, runs, ENV["LABEL_SUFFIX"].to_s)

    begin
      dump = run_one(prefix, label, seeds)
      dump["concolic_seeds"] = seeds if dump.is_a?(Hash)
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "[posts_show/#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 200]}"
      errors["harness:#{e.class}"] += 1
      next
    end

    errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

    pcs = path_conditions(dump)
    sig = digest(sig_of(pcs))

    next if !ENV["SEEDS_ONLY"] && seen_paths.include?(sig)

    seen_paths << sig
    written += 1
    File.write(File.join(HERE, "dump_#{label}.json"), JSON.pretty_generate(dump))
    dump = nil

    if written <= 5 || written % 25 == 0
      puts format("[%s] paths=%d runs=%d pcs=%d stack=%d parents=%d",
                  label, written, runs, pcs.size, stack.size, parents.size)
    end

    my_id = parents.size
    parents << JSON.generate(seeds)
    pcs.each do |(expr, taken)|
      fl = flip_any(expr, !taken)
      if fl.nil?
        unflippable[expr] += 1
        next
      end
      # SEEDS_ONLY REPLAY, second half of the drift fix (2026-09-10, ported from
      # people_stream's _COMPLETION_20260910.md §1, which found the preflight had
      # repaired only HALF the drift). notifications_index/run_dse.rb:455 carries
      # `next if ENV["SEEDS_ONLY"]` HERE. Without it SEEDS_ONLY only changes which
      # roots START the worklist: every replayed root still pushes its whole flip
      # frontier, so the replay becomes a full DSE exploration and a hit cannot be
      # attributed to the seed that was replayed — the entire point of the round.
      next if ENV["SEEDS_ONLY"]
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
  {
    "scenario"           => prefix,
    "description"        => SCENARIOS.fetch(prefix)[:desc],
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
  }
end

t0 = Time.now
# VARIANTS (2026-09-10, drive) — ported from notifications_index/run_dse.rb,
# which has had it since results2. Without it EVERY invocation runs all four
# scenarios, so a rooted round aimed at a branch that only `anon_json`
# evaluates still pays for three other scenarios AND replays the same seed
# file under four labels. A comma list selects a subset; an unknown name is a
# HARD ERROR rather than a silent empty run (an empty scenario list is
# indistinguishable from a drained one in the log).
_want = (ENV["VARIANTS"] || "").split(",").map(&:strip).reject(&:empty?)
unless _want.empty?
  _bad = _want - SCENARIOS.keys
  raise "VARIANTS names unknown scenario(s): #{_bad.join(',')} (have: #{SCENARIOS.keys.join(',')})" unless _bad.empty?
end
_scen = _want.empty? ? SCENARIOS.keys : _want
puts "[variants] running: #{_scen.join(',')}"
scenario_summaries = _scen.map { |p| explore(p) }

overall = {
  "entrypoint" => "posts_show",
  "params" => {
    "id" => { "symbolic_name" => PARAM_SYM_NAME, "seed" => PARAM_DEFAULT, "type" => "SymbolicString" },
  },
  "user" => {
    "SYM_USER_PO_id"     => "current_user.id — PIN REMOVED, flows symbolic",
    "SYM_PERSON_PO_id"   => "current_user.person.id — PIN REMOVED, flows symbolic",
    "SYM_USER_PO_guid"   => "current_user.guid (delegated to person) — PIN REMOVED, flows symbolic via person.guid",
    "SYM_USER_PO_person_id" => "current_user.person_id (real users column) — PIN REMOVED, flows symbolic (independent symbol from SYM_PERSON_PO_id, see REPORT.md)",
  },
  "scenarios" => scenario_summaries,
  "total_elapsed_seconds" => (Time.now - t0).round(1),
}
File.write(File.join(HERE, "exploration_summary.json"), JSON.pretty_generate(overall))

puts "\n== posts_show run_dse.rb done (#{(Time.now - t0).round(1)}s) =="
scenario_summaries.each do |s|
  puts format("  %-6s runs=%-6d paths=%-6d drained=%-6s %s",
              s["scenario"], s["runs_executed"], s["distinct_paths"],
              s["worklist_exhausted"], s["stop_reason"])
end
