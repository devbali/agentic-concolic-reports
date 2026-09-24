#!/usr/bin/env jruby
# frozen_string_literal: true
#
# people_stream — results3 DISCIPLINE-CLEAN rerun. Ported from
# results2/people_stream/run_dse.rb (fully symbolic entrypoint args, prefix-
# directed DSE, dispatch-based harness — all UNCHANGED and still correct,
# see that file's own header) with ../concolic_targets.rb's discipline
# rebuild underneath it (results3/README.md + ../PHASE_A_PATCH.md +
# ../results2/MOCK_AUDIT.md):
#
#   - Section Z (render/render_to_string/render_to_body) + Y2
#     (default_render) REMOVED — `format.json`'s `render json:
#     person_stream.stream_posts.map { LastThreeCommentsDecorator.new(
#     PostPresenter.new(p, current_user)) }` now runs the real JSON
#     serialization pipeline instead of stopping at a terminal marker.
#     `format.all`'s `redirect_to person_path(@person)` was ALREADY real in
#     results2 (redirect_to is a CLEAN LEAF, never mocked) — unaffected.
#   - `Post.blocked_people` / `Stream::Base#post_ids` / `#attach_user_likes`
#     DESCENDED (concolic_targets.rb DESCENDED, both undeclared) — the
#     signed-in scenario's `like_posts_for_stream!` now runs for real down to
#     `Like.where(author_id: @user.person_id, target_id: post_ids(posts),
#     target_type: "Post")`'s real materialization — recovering the
#     viewer-likes query results2 documented as swallowed (its "Secondary
#     finding"). `IterableSymbolicList#inject`/`#reduce` added in targets.rb
#     §5b for attach_user_likes' real `likes.inject({...})` body.
#   - PHASE_A_PATCH.md Patch 4 (CollectionProxy) ported into targets.rb §5b
#     per that patch's applicability table ("people_stream — yes").
#
# Ported from ../../results/people/run_dse.rb (+ the pre-DSE run_concolic.rb,
# whose "people_stream_default" scenario is the literal source for the
# anon_json scenario below), restricted to PeopleController#stream ONLY.
#
# THE POINT OF THIS RERUN (results2/README.md + task brief):
#   1. params[:person_id] -> SYM_PARAM_person_id, a SymbolicSTRING seeded
#      "1". find_person builds `{id: params[:id] || params[:person_id], ...}`
#      and hands it to Person.find_from_guid_or_username, whose `params[:id]`
#      branch is `Person.find_by(guid: params[:id])` — a GUID/string lookup,
#      so (per the task brief's own posts_show precedent) a symbolic STRING
#      exercises more than a symbolic int would.
#   2. params[:username] -> symstr("SYM_PARAM_username", "bob@example.org").
#   3. Signed-in variant (auth_json): symbolic_user with user.id/person.id
#      pins removed, associations rescoped to real FKs — see targets.rb §4.
#
# THE WALL A SYMBOLIC USERNAME HITS, AND HOW IT'S CLOSED (see targets.rb §7
# for the full rationale): PeopleController#find_person's private predicate
#   diaspora_id?(query) = !(query.nil? || query.lstrip.empty?) &&
#     Validation::Rule::DiasporaId.new.valid_value?(query.downcase).present?
# calls SymbolicString#lstrip, which is on the UNSUPPORTED list
# (src/ruby_runtime/string.rb) — a symbolic username crashes on the FIRST
# call, 0 PCs, every run. `diaspora_id?` has no SQL and calls no declared
# target, so it is mocked as a boundary decision (targets.rb §7) — this is
# also what makes find_person's TWO finder paths (diaspora-handle lookup vs
# find_from_guid_or_username) DSE-explorable instead of permanently stuck on
# whichever branch the crash happened not to prevent.
#
# `username.downcase` is ALSO called directly in find_person (outside
# diaspora_id?, in the diaspora-handle TRUE branch) — closed with a
# PER-INSTANCE identity override (see build_params below), not a targets.rb
# subclass, because it is specific to this one entrypoint argument.
#
# WHY ctrl.dispatch INSTEAD OF ctrl.send(action) DIRECTLY (unlike
# results2/posts_show, results2/comments_index): people#stream's @person is
# set by the `find_person` BEFORE_ACTION, not by the action body. Calling
# the action method directly (ctrl.send(:stream)) skips the entire
# before_action chain and @person would never be assigned. `ctrl.dispatch`
# (== what ActionController::TestCase#process eventually calls) runs the
# FULL AbstractController::Callbacks / Rescue chain — before_actions,
# rescue_from, the action body — while still letting us set `ctrl.params=`
# directly (bypasses route/query-string generation, which is NOT proven safe
# for symbolic params: `escape_segment` is a mocked SQL-free leaf for PATH
# segments, per concolic_targets.rb §X8d, but query-string building for a
# non-segment param like `username` is unverified and risks calling
# SymbolicString#b, also UNSUPPORTED).
#
# WHY PREFIX-DIRECTED DSE (unchanged rationale — see BATCH_BRIEFING.md /
# main README.md): SYM_RESULT_<func>_<idx> names carry a per-run call
# ordinal; flipping an early branch renumbers every later var, so feeding
# CoverageChecker's concrete_values back wholesale is unsound. Instead: from
# an observed path [c0..cn], emit one child per k that INHERITS the parent's
# seeds (prefix c0..c_{k-1} replays identically) and adds exactly one flip
# for c_k. Dedup on path signature; expand until the worklist drains or a
# cap is hit.
#
# Touches neither src/, the shared concolic_targets.rb, nor the diaspora app
# source — this directory carries PRIVATE copies of concolic_targets.rb and
# targets.rb (results2/README.md layout).
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
#       /home/dev/project/reports/diaspora/results3/people_stream/run_dse.rb
#
# Env: MAX_RUNS (default 300 per scenario), TIME_BUDGET seconds (default
# 1200 per scenario) — capped deliberately per the task brief.

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
PeopleStreamTargets.install!($interceptor)

HERE        = File.dirname(File.expand_path(__FILE__))
MAX_RUNS    = (ENV["MAX_RUNS"]    || 300).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 1200).to_i
STACK_LIMIT = (ENV["STACK_LIMIT"] || 50_000).to_i

# Devise/warden plumbing substitute (no warden env in the controller-test
# rig) — ported from results/people/run_dse.rb. Defensive: people#stream's
# only devise touch point is `authenticate_if_remote_profile!`, which is
# gated on `@person.remote?` == `owner_id.nil?`, and a SymbolicInt is never
# actually nil (Object#nil? is untracked, always false for a non-nil
# wrapper) — so this path is structurally unreachable via DSE. Kept for
# parity/safety in case that changes.
class StubWarden
  def initialize(user)
    @user = user
  end
  def authenticate!(*_a); @user; end
  def authenticated?(*_a); true; end
  def user(*_a); @user; end
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
  ctrl = tc.instance_variable_get(:@controller)
  [ctrl, tc]
end

# ---------------------------------------------------------------------------
# Symbolic entrypoint params, built fresh each run from current seed state.
# ---------------------------------------------------------------------------
PID_SYM_NAME = "SYM_PARAM_person_id"
PID_DEFAULT  = "1"
UN_SYM_NAME  = "SYM_PARAM_username"
UN_DEFAULT   = "bob@example.org"

def build_params
  # Both params are built as SymEntrypointString (targets.rb §8, ported from
  # people_show/targets.rb §B's SymUsernameString) rather than a bare
  # symstr(...): once §7's steering fix lets diaspora_id? genuinely flip
  # false, find_person's false branch (Person.find_from_guid_or_username,
  # person.rb:196-206) calls `.present?`/`.blank?` on BOTH params[:id]
  # (== params[:person_id] here, see build_params' `id:` note in the file
  # header) and params[:username] — UNSUPPORTED on plain SymbolicString
  # (String#blank? -> `=~`, string.rb's UNSUPPORTED list) — and the TRUE
  # branch still calls `username.downcase` directly. See targets.rb §8 for
  # the full wall-by-wall rationale (ported from people_show).
  pid_seed = ConcolicTargets.seed_for(PID_SYM_NAME, PID_DEFAULT)
  sym_pid  = SymEntrypointString.new(pid_seed, name: PID_SYM_NAME,
                                      note: "PeopleController params[:person_id]")

  un_seed = ConcolicTargets.seed_for(UN_SYM_NAME, UN_DEFAULT)
  sym_un  = SymEntrypointString.new(un_seed, name: UN_SYM_NAME,
                                     note: "PeopleController params[:username]")
  # `lstrip` is NOT on SymEntrypointString (people_show's SymUsernameString
  # doesn't override it either): the real diaspora_id? body that calls it is
  # never executed — §7's mock fully replaces the method (declare_target
  # "body-skip mode"). Kept as a defensive per-instance identity override
  # anyway (belt-and-suspenders, zero cost) in case that ever changes.
  sym_un.define_singleton_method(:lstrip) { self }
  [sym_pid, sym_un]
end

# ---------------------------------------------------------------------------
# Scenarios. person_id/username are symbolic in ALL of them (results2's
# point); signed_in/format vary.
# ---------------------------------------------------------------------------
SCENARIOS = {
  # Canonical DSE scenario from the source batch's run_dse.rb (default/html
  # format -> format.all { redirect_to person_path(@person) }). Richest
  # genuine-PC producer in the source batch (10 PCs / 4 dumps).
  "anon_all" => {
    action: :stream, format: nil, signed_in: false,
    desc: "anonymous, default/html format -> redirect_to person_path(@person)",
  },
  # Literal port of the PRE-DSE run_concolic.rb's "people_stream_default"
  # scenario (anon, format: :json, params person_id: 1, username:
  # "bob@example.org") — named in the task brief. That runner recorded this
  # as walling on `stream_posts.map` (SymbolicList#map, a contents-op).
  # targets.rb §5b's IterableSymbolicList may or may not clear it now —
  # tested here rather than assumed; see REPORT.md.
  "anon_json" => {
    action: :stream, format: :json, signed_in: false,
    desc: "anonymous, json format -> person_stream.stream_posts.map(...) " \
          "(literal port of source run_concolic.rb's people_stream_default)",
  },
  # NEW for results2: signed-in, json format. The source batch never ran
  # this shape for `stream` (its DSE run_dse.rb only explored anon_html,
  # and the html/all branch never touches current_user at all — stream's
  # `format.all` is a bare redirect, so an authenticated html variant would
  # be PC-identical to anon_all, not worth a separate dump). json is the
  # ONLY branch where current_user matters for this action
  # (Stream::Person.new(current_user, @person, ...) -> #posts ->
  # user.posts_from(@person) when user.present?) — directly on point for
  # results2's "does current_user identity reach the recorded SQL" mandate.
  "auth_json" => {
    action: :stream, format: :json, signed_in: true,
    desc: "signed-in (symbolic user, pins removed), json format -- " \
          "exercises Stream::Person#posts -> user.posts_from(person)",
  },
}.freeze

def run_one(prefix, label, seeds)
  ConcolicTargets.seed_overrides = seeds
  PeopleStreamTargets.begin_run!
  # boundary fix 2 (2026-09-03): per-run reset of the GonPreloadsShim ivar
  # (concolic_targets.rb X6b-preloads) so gon.preloads data cannot leak
  # across runs. Same contract as notifications run_dse.rb:156.
  if defined?(::Gon) && ::Gon.instance_variable_defined?(:@concolic_preloads)
    ::Gon.instance_variable_set(:@concolic_preloads, {})
  end
  ctrl, tc = make_harness(PeopleController)
  scen = SCENARIOS.fetch(prefix)
  signed_in = scen[:signed_in]
  user = signed_in ? PeopleStreamTargets.symbolic_user("PS") : nil
  ctrl.singleton_class.define_method(:current_user)    { user }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  tc.instance_variable_get(:@request).env["warden"] = StubWarden.new(user) if signed_in

  sym_pid, sym_un = build_params
  ctrl.params = { person_id: sym_pid, username: sym_un }.with_indifferent_access

  begin
    ctrl.request.format = scen[:format] if scen[:format]
  rescue StandardError => e
    warn "[warn] could not set request format: #{e.class}"
  end

  body = lambda do
    begin
      ctrl.dispatch(scen[:action].to_s, tc.request, tc.response)
    rescue Exception => e # rubocop:disable Lint/RescueException
      # rescue_from is normally applied by ActionController::Rescue wrapping
      # process_action, so ctrl.dispatch already routes RecordNotFound /
      # AccountClosed through the declared handlers. This is a defensive
      # fallback only (mirrors results2/comments_index's pattern) in case an
      # exception somehow escapes that wrapping.
      handled = begin
        ctrl.send(:rescue_with_handler, e)
      rescue Exception # rubocop:disable Lint/RescueException
        nil
      end
      raise e unless handled
      handled
    end
    :ok
  end

  dump = $interceptor.run(body, {}, label: label, script: "run_dse.rb")

  # RUNNER-LOCAL MEMORY TRIM (src/ gap, reported — do not patch src/):
  # CallInterceptor keeps an unbounded @all_calls history for the process
  # lifetime (src/ruby_runtime/call_interceptor.rb). #run only ever reads the
  # slice belonging to the current run, so clearing between runs is
  # behaviour-preserving.
  $interceptor.instance_variable_get(:@all_calls).clear
  dump
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

# ---------------------------------------------------------------------------
# Flip helpers — ported verbatim from results2/posts_show/run_dse.rb
# (itself ported from results/people/run_dse.rb, extended with
# flip_length_seed from results2/comments_index).
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
  if (m = /\A\(len\((.+)\) == 0\)\z/m.match(s))
    return { "len(#{m[1]})" => (want_taken ? 0 : 1) }
  end

  if (m = /\A\(([A-Za-z_][A-Za-z0-9_]*) (<=|>=|<|>) (-?\d+)\)\z/m.match(s))
    var, op, n = m[1], m[2], m[3].to_i
    value =
      case op
      when "<=" then want_taken ? n : n + 1
      when "<"  then want_taken ? n - 1 : n
      when ">=" then want_taken ? n : n - 1
      when ">"  then want_taken ? n + 1 : n
      end
    return { var => value }
  end

  m = /\A\(([A-Za-z_][A-Za-z0-9_]*) (==|!=) (.+)\)\z/m.match(s)
  return nil unless m
  var, op, lit = m[1], m[2], m[3].strip

  parsed = parse_literal(lit)
  return nil if parsed.nil?

  equal_wanted = (op == "==") ? want_taken : !want_taken
  value = equal_wanted ? parsed : other_value(parsed)
  return nil if value.nil?

  { var => value }
end

# SymbolicString#length on a symbolic entrypoint param is a SymbolicInt named
# "Length(VAR)" (string.rb:194) — not currently branched on in this
# entrypoint's known code paths (person_id/username never have .length
# compared), kept for parity/safety since both params are symbolic strings.
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
# Prefix-directed exploration of one scenario.
# ---------------------------------------------------------------------------
def explore(prefix)
  puts "\n== people_stream/#{prefix} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
  started = Time.now

  parents     = ["{}"]
  # Two roots, not one: the default seed (PID_DEFAULT="1", non-blank) makes
  # find_from_guid_or_username's `params[:id].present?` ALWAYS concretely
  # true (person.rb:197) -- id/present?/blank? is a Ruby-truthiness bare
  # call, records NO PC (same documented pattern as every other blank?/
  # present? in this experiment), so the prefix-directed flip mechanism
  # below (which only flips RECORDED PCs) can never discover the `elsif
  # params[:username].present? && u = User.find_by_username(...)` arm on
  # its own -- it would stay permanently unreached. A second root, with
  # SYM_PARAM_person_id forced blank via seed_overrides, is a deliberate
  # "close by execution" probe (COMPLETION_BRIEF.md's preferred technique)
  # that lets the SAME worklist take over from there: whatever PCs THAT
  # run records (finder_mock's not_found/closed_account on the
  # User.find_by_username lookup) get flipped and explored exactly like
  # any other discovered branch.
  # The probe root must ALSO force diaspora_id? False (its own decision var,
  # stable across runs -- see coverage_assumptions.py's expr-identity note)
  # in the SAME seed set: person_id="" alone replays the default diaspora_
  # id?==True trace (person_id isn't read there at all), producing the
  # IDENTICAL path signature to the default root and getting silently
  # deduped before its own PCs are ever examined for further flips.
  diaspora_id_var = "SYM_RESULT_PeopleController_diaspora_id__1_result"
  # ORDER MATTERS: `stack` is a LIFO (Array#pop), so the LAST-pushed root
  # runs FIRST. The default root ([0, nil], person_id="1") must run (and
  # have its own subtree fully explored via the normal single-flip
  # mechanism) BEFORE the probe root, or the probe root's own diaspora_id?
  # ==True excursions (person_id="" doesn't affect that branch's PC trace
  # at all -- it never reads person_id) get path-deduped as "already seen"
  # ahead of the default root's identical-looking True-branch trace. Since
  # `next if seen_paths.include?(sig)` skips a deduped run's OWN pcs.each
  # flip loop entirely, that ordering would silently prevent the default
  # root from ever flipping diaspora_id? to False with person_id="1" held
  # -- permanently losing the id-guid sub-branch
  # (Person.find_by(guid: params[:id])) that must stay observable
  # alongside the person_id-blank probe's User.find_by_username
  # sub-branch. Pushing the probe SECOND (so it pops LAST) lets the
  # default root's subtree fully claim the True-branch and id-guid-branch
  # signatures first; the probe's own new territory (SYM_PERSON_via_user_*)
  # is untouched by that subtree and always gets explored either way.
  stack       = [[0, JSON.generate({ PID_SYM_NAME => "", diaspora_id_var => false })],
                 [0, nil]]
  # DEMAND-ROUND HOOK (ported from notifications_index/run_dse.rb, 2026-09-09).
  # EXTRA_SEEDS_JSON is a JSON array of seed hashes; each becomes a worklist
  # ROOT (parent 0), so a demanded outcome assignment can be reached IN
  # CONTEXT. SEEDS_ONLY replays just those roots without further flipping.
  # Without this the endpoint cannot run demand rounds at all — see
  # _NEXT_BLOCKER.md.
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
      puts "[people_stream/#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 200]}"
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
    dump_error = dump["error"]
    dump = nil

    puts format("[%s] paths=%d runs=%d pcs=%d stack=%d parents=%d %s",
                label, written, runs, pcs.size, stack.size, parents.size,
                dump_error ? "error=#{dump_error['type']}" : "")

    my_id = parents.size
    parents << JSON.generate(seeds)
    pcs.each do |(expr, taken)|
      fl = flip_any(expr, !taken)
      if fl.nil?
        unflippable[expr] += 1
        next
      end
      # SEEDS_ONLY REPLAY, second half of the drift fix (2026-09-10, found by
      # the smoke). notifications_index/run_dse.rb:455 has `next if
      # ENV["SEEDS_ONLY"]` HERE, and people_stream's port did not. Without it
      # SEEDS_ONLY only changed which roots start the worklist: every replayed
      # root still pushed its whole flip frontier, so a 2-seed replay ran 50
      # runs per scenario (MAX_RUNS cap) and wrote 150 dumps instead of 6 —
      # and with the path-dedup correctly disabled for replay, 144 of those
      # were duplicate paths. A rooted round must replay ITS ROOTS, nothing
      # else, or the caller cannot attribute a hit to a seed.
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
# CORPUS ACCUMULATION (2026-09-09). This runner originally WIPED the corpus on
# every invocation, which makes incremental corpus building impossible: a base
# round 2 deleted round 1 and rewrote it (net 0 dumps), and the first demand
# round REPLACED the 201-dump base corpus with its own 152. notifications_index
# never deletes — it accumulates, which is what the demand loop requires.
# Wipe only when explicitly asked (KEEP_DUMPS=0), never when seeding.
if ENV["KEEP_DUMPS"] == "0" && !ENV["EXTRA_SEEDS_JSON"]
  Dir.glob(File.join(HERE, "dump_*.json")).each { |f| File.delete(f) }
end
# SCENARIO_ONLY (2026-09-18, note-refresh re-drive). Runner-local knob, same
# shape as people_show/run_dse.rb's. Needed for a FAITHFUL SEEDS_ONLY replay:
# a seed set belongs to exactly ONE scenario (the one that produced it), but
# this loop otherwise replays every seed under all three, which would both
# triple the corpus and evaluate seeds in scenarios they were never explored
# in. Exploration itself is unchanged — omit the variable and all scenarios
# run exactly as before.
scenario_keys = SCENARIOS.keys
if ENV["SCENARIO_ONLY"] && !ENV["SCENARIO_ONLY"].empty?
  scenario_keys = ENV["SCENARIO_ONLY"].split(",").map(&:strip).reject(&:empty?)
  missing = scenario_keys - SCENARIOS.keys
  raise "SCENARIO_ONLY names unknown scenario(s): #{missing.inspect}" unless missing.empty?
end
scenario_summaries = scenario_keys.map { |p| explore(p) }

overall = {
  "entrypoint" => "people_stream",
  "params" => {
    "person_id" => { "symbolic_name" => PID_SYM_NAME, "seed" => PID_DEFAULT, "type" => "SymbolicString" },
    "username"  => { "symbolic_name" => UN_SYM_NAME, "seed" => UN_DEFAULT, "type" => "SymbolicString",
                      "note" => "per-instance identity #downcase/#lstrip override — see build_params" },
  },
  "user" => {
    "SYM_USER_PS_id"        => "current_user.id (auth_json only) — PIN REMOVED, flows symbolic",
    "SYM_PERSON_PS_id"      => "current_user.person.id (auth_json only) — PIN REMOVED, flows symbolic",
    "SYM_USER_PS_guid"      => "current_user.guid (delegated to person) — PIN REMOVED, flows via person.guid",
    "SYM_USER_PS_diaspora_handle" => "current_user.diaspora_handle (delegated to person) — PIN REMOVED",
    "SYM_USER_PS_person_id" => "current_user.person_id (real users column) — PIN REMOVED, independent symbol from SYM_PERSON_PS_id",
    "SYM_USER_PS_language"  => "FORCED pin \"en\" — i18n set_locale wall, not an identity attribute",
    "SYM_USER_PS_gender"    => "FORCED pin \"\" — cosmetic, never branched on",
  },
  "scenarios" => scenario_summaries,
  "total_elapsed_seconds" => (Time.now - t0).round(1),
}
File.write(File.join(HERE, "exploration_summary.json"), JSON.pretty_generate(overall))

puts "\n== people_stream run_dse.rb done (#{(Time.now - t0).round(1)}s) =="
scenario_summaries.each do |s|
  puts format("  %-10s runs=%-6d paths=%-6d drained=%-6s %s",
              s["scenario"], s["runs_executed"], s["distinct_paths"],
              s["worklist_exhausted"], s["stop_reason"])
end
