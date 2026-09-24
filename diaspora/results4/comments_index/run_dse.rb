#!/usr/bin/env jruby
# frozen_string_literal: true
#
# comments_index — results3 discipline-clean rerun over the REAL
# CommentsController#index (action :index, signed_in: false, format :json —
# index is the one anonymous-reachable action on this controller:
# `before_action :authenticate_user!, except: :index`).
#
# Ported from ../../results2/comments_index/run_dse.rb (itself ported from
# ../../results/comments/run_dse.rb) UNCHANGED at the runner-mechanics level
# (symbolic params[:post_id], prefix-directed DSE, flip helpers) — the
# results3 upgrade lives entirely in ./concolic_targets.rb + ./targets.rb
# (see their header MOCK LEDGERs): `ActsAsApi::Collection#as_api_response`
# and `Diaspora::Mentionable.people_from_string` are no longer mocked, so
# this SAME runner now drives CommentPresenter#as_json's real body
# (author.as_api_response(:backbone) -> Person/Profile field walks;
# mentioned_people -> Mentionable.people_from_string -> a REAL local Person
# lookup with a genuine $$() bind) instead of stopping at the presenter
# boundary.
#
# THE POINT OF THE ORIGINAL results2 RERUN (still true here): entrypoint
# arguments must be symbolic. The source `comments` batch pinned
# params[:post_id] = "5" as a concrete Ruby String, so PostService#find_public!
# -> Post.where(id: "5") rendered a concrete literal bind, never a
# $$(SYM_PARAM_post_id) one. Here params[:post_id] is
# `symstr("SYM_PARAM_post_id", ...)`, seeded "5" so the default run
# reproduces the original behavior, but the id now flows into the WHERE
# clause as a genuine symbolic bind (verified in the dumps' `note` fields on
# the ActiveRecord::FinderMethods.first symbolic_call event, e.g.
# `SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(SYM_PARAM_post_id)`).
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
#       /home/dev/project/reports/diaspora/results3/comments_index/run_dse.rb
#
# Env: MAX_RUNS (default 3000), TIME_BUDGET seconds (default 1800)

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
CommentsTargets.install!($interceptor)
CommentsMentionLookupNaming.install!($interceptor)
CommentsVisibleShareableNaming.install!($interceptor) # cycle 1: AUTH-chain finder naming
CommentsDeviseUserNaming.install!($interceptor)        # cycle 1: real current_user resolution

HERE        = File.dirname(File.expand_path(__FILE__))
ENTRY       = "comments_index"
MAX_RUNS    = (ENV["MAX_RUNS"] || 3000).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 1800).to_i

# ---------------------------------------------------------------------------
# comments_index is anonymous (before_action :authenticate_user!, except:
# :index) — current_user is nil, no symbolic_user harness is needed here.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Signed-in scenario harness: the auth corpus resolves current_user through
# REAL Devise (`User.serialize_from_session`, below), so the hand-built
# `symbolic_user_ci` helper that used to live here was never called by any
# run. It carried explicit `language` / `gender` PINS in its body, which the
# adversary correctly read as a licence that did not apply (round 3, N3-1) —
# dead code that documented a decision the live path does not make. Deleted
# 2026-08-28; `users.language` is now a recorded decision on the real rep and
# `profiles.gender` is a PIN LEDGER entry (see targets.rb's identity shim).
# ---------------------------------------------------------------------------

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
  ctrl.response = tc.instance_variable_get(:@response) # real render needs the response wired (cycle 3)
  [ctrl, tc]
end

CFG = {
  action: :index, signed_in: false, format: :json,
  param_key: :post_id, param_sym_name: "SYM_PARAM_post_id", param_default: "5"
}.freeze

# cycle 3 (2026-08-27, ADVERSARY_REPORT.md W2): `:mobile` is a DECLARED
# response format of this action (`respond_to :html, :mobile, :json`; reached
# in the real app by ApplicationController#mobile_switch on
# `session[:mobile_view]`, by mobile-fu's device header, or by an explicit
# format) rendering `index.mobile.haml` / `_comment.mobile.haml` — a
# different read order (`Relation#to_a` via the partial collection renderer,
# `markdownified` with render_mentions/render_tags, PeopleHelper compares,
# the delete-link author == current person compare). Direct dispatch skips
# the before_action, so the variant sets `request.format = :mobile` — exactly
# what mobile_switch does. `:html` is declared but templateless on index
# (responders -> default_render -> MissingTemplate, a real 500 with no data
# access beyond the post finder) — format_coverage_audit reports it
# TEMPLATELESS, not required. Variant = (signed-in?, format).
VARIANTS = {
  "anon_json"   => { auth: false, format: :json },
  "auth_json"   => { auth: true,  format: :json },
  "anon_mobile" => { auth: false, format: :mobile },
  "auth_mobile" => { auth: true,  format: :mobile },
}.freeze
VARIANT = ENV["VARIANT"] ||
          "#{ENV['AUTH'] == '1' ? 'auth' : 'anon'}_#{ENV['FORMAT'] == 'mobile' ? 'mobile' : 'json'}"
raise "unknown VARIANT #{VARIANT}" unless VARIANTS.key?(VARIANT)
VCFG = VARIANTS.fetch(VARIANT)

# Real-app 500 terminals (cycle 3): exceptions the REAL endpoint raises on
# reachable data states — recorded as a run OUTCOME, never swallowed as a
# harness failure and never a wall: (a) `ActionView::Template::Error` whose
# cause is a nil-receiver NoMethodError (mobile: `Mentionable.format` on a
# dangling mention's nil person, adversary N3) or a DiscoveryError; (b) a bare
# `DiasporaFederation::Discovery::DiscoveryError` (json: Person#fix_profile
# propagates a failed webfinger, adversary N6/"Unreachable"). Any other
# escaping exception is still a run error.
def app_error_terminal?(e)
  if defined?(DiasporaFederation::Discovery::DiscoveryError) &&
     e.is_a?(DiasporaFederation::Discovery::DiscoveryError)
    return true
  end
  return false unless defined?(ActionView::Template::Error) && e.is_a?(ActionView::Template::Error)
  c = e.cause
  return true if defined?(DiasporaFederation::Discovery::DiscoveryError) &&
                 c.is_a?(DiasporaFederation::Discovery::DiscoveryError)
  c.is_a?(NoMethodError) && c.message.to_s.include?("nil:NilClass")
end

# D5 (adversary round 2): a SIGNED-IN user whose `people` row is missing is a
# real database state (`people.owner_id` carries no FK to users, and
# Person#destroy does not destroy its owner). `EvilQuery::VisibleShareableById
# #querent_is_author` (evil_query.rb:116-118) then raises
# `NoMethodError: undefined method 'id' for nil:NilClass` AFTER the
# share-visibility SELECT has been issued and BEFORE the author/public ones —
# a real 500, recorded as a run OUTCOME so the corpus stops asserting that a
# vis miss is always followed by the author and public SELECTs. Scoped to the
# signed-in variants and to the nil-receiver message, so a harness bug cannot
# hide here.
#
# N3-1 (adversary round 3): the same class of real 500 now also reachable
# from the before_action chain. `set_grammatical_gender` reads
# `current_user.gender`, which is `delegate :gender, to: :person` (user.rb:59)
# then `delegate :gender, to: :profile` (person.rb:27-28) — NEITHER with
# `allow_nil`. So a signed-in user with no `people` row, or a person with no
# `profiles` row, raises `Module::DelegationError` (a NoMethodError subclass)
# in the callback, BEFORE the action body issues anything. Both states are
# already modelled decisions (`devise_user_first_1_person_not_found`,
# `<person>_profile_not_found`); this records their real outcome instead of
# letting it escape as a harness failure.
# W4-1 / M-5 and W4-2 / M-6 (adversary round 4): two more real, unrescued
# 500s on schema-legal rows, each with a SHORTER statement set than any path
# the corpus used to contain.
#   I18n::InvalidLocale        — `set_locale` on a non-nil unavailable
#                                `users.language`; the whole data access is
#                                the `users` SELECT (signed-in only, because
#                                the anon arm of set_locale reads the
#                                Accept-Language header, never the column).
#   ActiveRecord::SubclassNotFound — an out-of-tree `posts.type`, raised while
#                                instantiating the row the finder returned;
#                                the post finder is the last statement.
# Neither is rescued by CommentsController (`rescue_from` covers
# RecordNotFound and Diaspora::NonPublic only, and SubclassNotFound descends
# from ActiveRecordError, not RecordNotFound), so both are run OUTCOMES.
def locale_or_sti_terminal?(e)
  if defined?(I18n::InvalidLocale) && e.is_a?(I18n::InvalidLocale)
    return VCFG[:auth]
  end
  defined?(ActiveRecord::SubclassNotFound) && e.is_a?(ActiveRecord::SubclassNotFound)
end

def person_less_user_terminal?(e)
  return false unless VCFG[:auth]
  if defined?(Module::DelegationError) && e.is_a?(Module::DelegationError)
    return e.message.to_s.include?("is nil")
  end
  e.is_a?(NoMethodError) && e.message.to_s.include?("nil:NilClass")
end

# ops (cycle 11): a smoke round must not write into the live corpus dir.
OUT = ENV["DUMP_OUT"] || HERE
require "fileutils"
FileUtils.mkdir_p(OUT)

# One execution of the REAL CommentsController#index under a seed assignment.
#
# rescue_from is part of the action's real behaviour (head :not_found /
# authenticate_user!), but it only fires inside AbstractController#process_action.
# We invoke the action body directly (as the verified reference runner does) and
# then dispatch escaping exceptions through the controller's OWN
# `rescue_with_handler`, so the declared rescue_from blocks still run for real.
def run_one(label, seeds)
  ConcolicTargets.seed_overrides = seeds
  CommentsMentionLookupNaming.reset_ctx! if defined?(CommentsMentionLookupNaming)
  CommentsTargets.reset_text_binds! if CommentsTargets.respond_to?(:reset_text_binds!)
  # boundary fix 2 (2026-09-03): per-run reset of the GonPreloadsShim ivar
  # (concolic_targets.rb X6b-preloads) so gon.preloads data cannot leak
  # across runs. Same contract as notifications run_dse.rb:156.
  if defined?(::Gon) && ::Gon.instance_variable_defined?(:@concolic_preloads)
    ::Gon.instance_variable_set(:@concolic_preloads, {})
  end
  # M-16b: the per-run relation-read memo (one relation read twice is one
  # fact) must not leak across runs in the same JRuby process.
  Thread.current[:comments_rows_memo] = nil
  ctrl, = make_harness(CommentsController)
  if VCFG[:auth]
    # cycle 1 (AGENT_RUN.md): resolve current_user through the REAL Devise
    # `serialize_from_session` so the session-resolution statements
    # (users lookup + user.person has_one) are issued for real and minted as
    # corpus notes, exactly as the concrete signed-in run issues them (D1).
    # serialize_from_session -> to_adapter.get -> devise_user_first (aliased,
    # symbolic User) -> authenticatable_salt leaf compare. `user.person` is
    # NOT overridden — the real has_one :person (owner_id) association fires.
    # LAZY/memoized so the resolution's queries fire INSIDE $interceptor.run
    # (the action's first current_user call), not before it — otherwise the
    # users-lookup + has_one :person target calls happen pre-interception and
    # are never captured (found live cycle 1: the notes were missing).
    ctrl.singleton_class.define_method(:current_user) do
      # PRINCIPAL MUST BE SYMBOLIC (identity_symbolicity_audit, 2026-08-26):
      # a concrete key here folded every signed-in view as `users.id = 1`
      # instead of `_MY_UID`. Seed the session key as the symbolic user id.
      ci_uid = symint("SYM_USER_CI_id", ConcolicTargets.seed_for("SYM_USER_CI_id", 1))
      @ci_user ||= User.serialize_from_session(ci_uid, "concolicsalt")
    end
    ctrl.singleton_class.define_method(:user_signed_in?) { true }
  else
    ctrl.singleton_class.define_method(:current_user)      { nil }
    ctrl.singleton_class.define_method(:user_signed_in?)   { false }
  end
  # devise's authenticate_user! -> warden, which the controller-test rig has
  # no middleware for. It is a guard, not concolic logic. (Not exercised on
  # the :index action anyway — before_action excepts it — kept for parity.)
  ctrl.singleton_class.define_method(:authenticate_user!) { :authenticate_user_called }

  begin
    ctrl.request.format = VCFG[:format]
  rescue StandardError => e
    warn "[warn] could not set request format: #{e.class}"
  end
  ctrl.send(:action_name=, "index") # set by process(); needed by helpers the real mobile template reaches
  $comments_terminal = nil

  action = CFG[:action]
  body = lambda do
    # THE SYMBOLIC ENTRYPOINT ARGUMENT: params[:post_id] is a fresh
    # SymbolicString each run, named SYM_PARAM_post_id, seeded from
    # ConcolicTargets.seed_overrides (falls back to the original "5"). This is
    # what makes the posts lookup's WHERE bind render $$(SYM_PARAM_post_id)
    # instead of a concrete literal.
    #
    # BUGFIX (results2 completion pass, coverage_report.py investigation):
    # this MUST run inside the $interceptor.run(body, ...) block, not before
    # it. CallInterceptor#run calls SymbolicFunc.reset! at its very start
    # (src/ruby_runtime/call_interceptor.rb:262), which clears
    # @registered_vars — including any symstr/symint/symbool call made
    # *before* `run` starts. The original version of this runner called
    # `symstr(CFG[:param_sym_name], ...)` above, outside `body`, so the
    # registration was wiped before the dump snapshot ran and
    # SYM_PARAM_post_id NEVER appeared in any dump's `symbolic_vars` list —
    # even though the var was used correctly everywhere else (SQL binds,
    # the `Length(SYM_PARAM_post_id) < 16` PC). Z3 then couldn't parse that
    # PC (undeclared free variable) and CoverageChecker silently dropped it
    # into `unevaluable_exprs`, excluding the length-dispatch expression
    # from the combination-coverage universe entirely. Moving the
    # declaration inside `body` (after `run` resets state) fixes this.
    post_id_seed = ConcolicTargets.seed_for(CFG[:param_sym_name], CFG[:param_default])
    sym_post_id  = symstr(CFG[:param_sym_name], post_id_seed)
    # D1 (adversary round 2, 2026-08-28): the array-`post_id` family is GONE.
    # `post_id` is a PATH parameter of `/posts/:post_id/comments` and Rails
    # merges path parameters LAST, so `?post_id[]=…` can never reach the
    # action as an Array — proven by a real ActionDispatch probe (A04:
    # recognize_path gives post_id=>"100" while query_parameters holds the
    # array). The family was also modelling the WRONG post_key branch (a
    # concolic Array renders `to_s` as inspect strings, always >= 16 chars, so
    # every array dump took the guid side while a real short array takes the
    # id side) and left `Length(post_id) < 16` unrecorded in all 3 639 of its
    # dumps. Modelling a shape the endpoint cannot receive is over-emission
    # (cross-endpoint rule 6), so the parameter is a scalar, as the route
    # guarantees.
    ctrl.params  = { CFG[:param_key] => sym_post_id }.with_indifferent_access

    begin
      # N3-1 (adversary round 3, Rule G): the REAL dispatch runs
      # ApplicationController's before_action chain before the action body,
      # and on the signed-in path one of those callbacks READS DATA:
      #   set_locale               (application_controller.rb:100-108)
      #     I18n.locale = current_user.language
      #   set_grammatical_gender   (application_controller.rb:118-122)
      #     if user_signed_in? && I18n.inflector.inflected_locale?
      #       current_user.gender -> user.person.profile.gender
      #         -> SELECT "profiles".* WHERE "person_id" = $$(<principal>) LIMIT 1
      # That statement — on the DEVISE PRINCIPAL, before anything the action
      # issues — was in no dump of any previous corpus, because `language`
      # was minted as a placeholder string and the locale was therefore never
      # an inflected one. GROUND TRUTH that these two callbacks, and no
      # others, touch data on this action: the adversary's full-dispatch runs
      # B09 (`users.language = "pl"`) and B11 (`"en"`, same user) differ by
      # EXACTLY that one statement; every other callback in the chain issues
      # nothing here (the `gon_*` ones store a presenter that neither
      # renderable format of #index ever serializes — both bypass the layout).
      I18n.locale = "en" # deterministic per run (I18n.locale is global state)
      if VCFG[:auth]
        ctrl.send(:set_locale)
        ctrl.send(:set_grammatical_gender)
      end
      ctrl.send(action)
    rescue Exception => e # rubocop:disable Lint/RescueException
      handled = begin
        ctrl.send(:rescue_with_handler, e)
      rescue Exception # a handler that itself raises -> let the original stand
        nil
      end
      unless handled
        if app_error_terminal?(e) || person_less_user_terminal?(e) || locale_or_sti_terminal?(e)
          $comments_terminal = { "type" => e.class.name, "cause" => (e.cause && e.cause.class.name),
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
  dump["concolic_scenario"] = { "name" => VARIANT, "format" => VCFG[:format].to_s,
                                "signed_in" => VCFG[:auth] }
  dump["concolic_terminal"] = $comments_terminal if $comments_terminal

  # RUNNER-LOCAL LEAK WORKAROUND (reported, not patched in src/):
  # CallInterceptor keeps an unbounded @all_calls history ACROSS runs
  # (src/ruby_runtime/call_interceptor.rb — `run` only slices
  # @all_calls[old_count..]). Over thousands of DSE executions that retains
  # every TargetCall (args + pc_snapshot) and OOMs the JVM. `run` recomputes
  # old_count at entry, so clearing the array between runs is safe.
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
# matches nothing: `flip_any` returns nil, the PC is booked "unflippable", no
# child seed is pushed, and the worklist drains early reporting
# `worklist_exhausted: true` — a FALSE completion signal, not a visible
# failure. Measured on this exact corpus before this fix: 5 path conditions
# recorded, all 5 called unflippable, exploration stopped after run 1.
#
# Hand-built PCs still arrive as strings: `ConcolicTargets.symbolic_instance`
# records its boolean-predicate readers with a literal
# `"(#{sym.sym_name} == True)"`. So a dump mixes both spellings, and a runner
# that only handles strings silently explores the hand-built decisions and
# forecloses every operator-recorded one — invisibly, since only the total
# unflippable count is reported, not which PCs it covers.
#
# Render the term back to the matchers' spelling. Pure translation — no
# matcher below is changed, so seed keys and snapshots stay compatible.
# Ported from ../aspect_memberships_create/run_dse.rb, where it was written
# and validated (5 unflippable / 1 run -> 0 unflippable / 32 distinct paths
# over 40 runs on the same root, before this fix vs. after).
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

# Flip a single "(VAR == LITERAL)" path condition — the shape emitted by
# scalar-equality comparisons and boolean predicate readers.
def flip_seed(expr, want_taken, vals = {})
  m = /\A\(([A-Za-z_][A-Za-z0-9_]*) (==|!=) (.+)\)\z/m.match(canon_len(expr))
  return nil unless m
  var, op, lit = m[1], m[2], m[3].strip
  want_taken = !want_taken if op == "!="

  # cycle 3: VAR-vs-VAR compares (`comment.author == current_user.person`,
  # `p.diaspora_handle == diaspora_id` against the rep's handle var, mobile
  # PeopleHelper identity compares) — seed the FREE operand to the other's
  # recorded value (taken) or one off it (not taken); the principal
  # (SYM_USER_CI / devise person id) is never reseeded (identity_symbolicity).
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
    when /\AStringVal\('(.*)'\)\z/m then Regexp.last_match(1) # the runtime's string-compare rendering
    when /\A'(.*)'\z/m then Regexp.last_match(1)
    when /\A"(.*)"\z/m then Regexp.last_match(1)
    when /\A-?\d+\z/   then lit.to_i
    else return nil
    end

  # Runner-local exploration detail (round 4): for the two columns whose
  # modelled domain is a small set of REAL values, the "not this literal"
  # seed is the SIBLING value, not "". An empty string is neither a locale
  # code nor an STI type, and seeding it would (a) put a value outside the
  # modelled domain into the corpus and (b) make the assumption gate's
  # directed flip non-deterministic, since it picks the richest snapshot and
  # auto-flips a non-empty string to "".
  alt = nil
  alt = "en" if var.end_with?("_language")
  alt = "StatusMessage" if var.end_with?("_type")

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

# SymbolicList length PCs "(len(X) != 0)" are flippable too — seed the length.
def flip_len_seed(expr, want_taken)
  m = /\A\((len\(.+\)) != 0\)\z/m.match(canon_len(expr))
  return nil unless m
  { m[1] => (want_taken ? 1 : 0) }
end

# N4-3 (round 4): the 1-vs-MANY half of the same length dimension, recorded by
# targets.rb's rows_mock as "(len(X) > 1)". 2 is the modelled "two or more".
def flip_len_many_seed(expr, want_taken)
  m = /\A\((len\(.+\)) > 1\)\z/m.match(canon_len(expr))
  return nil unless m
  { m[1] => (want_taken ? 2 : 1) }
end

# NEW for results2: SymbolicString#length on a symbolic entrypoint param is a
# SymbolicInt named "Length(VAR)" (src/ruby_runtime/string.rb:194), and
# PostService#post_key branches on it ("id_or_guid.to_s.length < 16 ? :id :
# :guid") — this branch did not exist when post_id was a concrete String
# (concrete comparisons record no PC). Flip it by seeding VAR with a string
# of the length needed to flip the inequality the OTHER way, so both the
# :id-lookup and :guid-lookup queries get explored.
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

# Memory-frugal dedup: the sets below hold 16-byte digests, never the full
# seed JSON / path-signature strings (the JVM heap is capped at 1000m).
def digest(str)
  Digest::MD5.digest(str)
end

# ---------------------------------------------------------------------------
# Prefix-directed exploration
# ---------------------------------------------------------------------------
puts "== #{ENTRY} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
started = Time.now

stack       = [{}]

# SEEDS_ONLY / EXTRA_SEEDS_JSON (ported from notifications_index, 2026-08-25):
# pure-replay knobs the assumption checker's flip probes drive. EXTRA seed
# dicts become worklist roots; SEEDS_ONLY suppresses flip expansion so each
# probe replays deterministically.
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

  seeds = stack.shift # FIFO: single flips of the root first, then pairs, … (the low-order combos the checker demands)
  key = digest(JSON.generate(seeds.sort.to_h))
  # SEEDS_ONLY (assumption-gate replay): write a dump for EVERY seed root.
  # The gate replays ~40 roots per JRuby launch and matches dumps back by
  # their recorded `concolic_seeds`; a root suppressed by the dedupe makes
  # the gate re-run it in its own ~75 s boot (coordinator, 2026-08-27).
  next if !ENV["SEEDS_ONLY"] && seen_seeds.include?(key)
  seen_seeds << key

  runs += 1
  label = format("%s_dse%04d%s", VARIANT, runs, ENV["LABEL_SUFFIX"].to_s)

  begin
    dump = run_one(label, seeds)
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts "[#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 160]}"
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
    next if ENV["SEEDS_ONLY"] # pure replay: no flip expansion
    stack.push(child) unless seen_seeds.include?(ckey)
  end
end

elapsed = Time.now - started

summary = {
  "entrypoint"         => ENTRY,
  "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip)",
  "signed_in"          => VCFG[:auth],
  "variant"            => VARIANT,
  "format"             => VCFG[:format].to_s,
  "app_error_terminals"=> "ActionView::Template::Error(nil NoMethodError|DiscoveryError), DiscoveryError — recorded outcomes",
  "params"             => {
    CFG[:param_key].to_s => {
      "symbolic_name" => CFG[:param_sym_name],
      "seed"          => CFG[:param_default]
    }
  },
  "request_format"     => CFG[:format].to_s,
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
