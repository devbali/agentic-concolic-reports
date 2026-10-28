#!/usr/bin/env jruby
# frozen_string_literal: true
#
# conversations_index — results3 DISCIPLINE-CLEAN rerun. Ported from
# results2/conversations_index/run_dse.rb (fully symbolic identity, scoped
# associations, prefix-directed DSE, dispatch-based four-variant harness —
# all UNCHANGED and still correct, see the numbered list below) with
# ../concolic_targets.rb's discipline rebuild underneath it (results3/
# README.md + ../PHASE_A_PATCH.md + ../results2/MOCK_AUDIT.md):
#
#   - Section Z (render/render_to_string/render_to_body) + Y2
#     (ImplicitRender#default_render, verified not on this endpoint's call
#     path anyway) REMOVED — `respond_with do |format| format.html { render
#     "index", locals: {no_contacts: ...} }; format.json { render json:
#     @visibilities.map(&:conversation) } end` now runs the real per-
#     conversation-row partial pipeline (index.haml -> N x `render partial:
#     "conversations/conversation"`) instead of stopping at a terminal
#     marker.
#   - make_harness now wires `ctrl.response=` (real @_response object) and
#     run_one sets `ctrl.send(:action_name=, "index")` — both ported from
#     results3/notifications_index, needed now that real `render`/helper
#     code touches the response/action_name this harness never wires (it
#     deliberately bypasses `tc.process`/`dispatch`, see below).
#   - ./targets.rb adds ConcolicDate/ConcolicIntValue column wrapping (the
#     `timeago(conversation.updated_at)` wall), a `text` column identity
#     shim (`Message#message.plain_text_without_markdown`), SampledList#last
#     (`messages.pluck(:author_id).last`), and a `to_param` leaf shim
#     (`conversation_path`/`person_path` route helpers) — all closing walls
#     the render-family removal exposes. See that file's header.
#   - conversations#index's `respond_with` ALWAYS explicitly calls `render`
#     from inside the collector block for BOTH format.html and format.json
#     (verified against responders-2.4.1 gem source: `Responder#to_html` ->
#     `default_render` -> `@default_response.call(options)`, a DIFFERENT
#     `default_render` than `ImplicitRender`'s) — so unlike notifications_
#     index this runner does NOT need an explicit `default_render unless
#     performed?` call after `ctrl.send(:index)`.
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
#       /home/dev/project/reports/diaspora/results3/conversations_index/run_dse.rb
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
ConvDeviseUserNaming.install!($interceptor) # 2026-08-26: real Devise current_user resolution (targets.rb)

# results3 FIX (ported from results3/notifications_index's identical
# "Runtime scope decision"): disable the layout so the real per-row `render
# partial:` pipeline (index.haml -> _conversation.haml) runs, but the
# site-chrome layout (application.haml's `javascript_include_tag`/asset
# pipeline requires — sprockets can't resolve "underscore"/main.js in this
# stripped-down ActionController::TestCase rig, a pure test-harness asset-
# pipeline gap, unrelated to this endpoint's query shape) does not. CONFIRMED
# reached (first smoke run crashed here before this fix, "couldn't find file
# 'underscore' with type 'application/javascript'", sprockets resolving
# app/assets/javascripts/main.js from the layout). Runtime reconfiguration in
# OUR runner script, not an app-source edit — same category as the
# current_user/user_signed_in? singleton-method overrides below.
ConversationsController.layout(false)

HERE        = File.dirname(File.expand_path(__FILE__))
ENTRY       = "conversations_index"
MAX_RUNS    = (ENV["MAX_RUNS"] || 4000).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 1500).to_i

# ---------------------------------------------------------------------------
# current_user — 2026-08-26 (results3 completion drive, AGENT_RUN.md): the
# pre-built symbolic user (+ overridden `person`/`contacts`/`conversations`)
# of the earlier port is GONE. conversations#index is signed-in only
# (`before_action :authenticate_user!`, no `except:`), so the principal is
# ALWAYS the Devise session user — and the real endpoint issues two
# statements to resolve it (`SELECT users.* WHERE id = ?` via
# serialize_from_session -> OrmAdapter#get, then `SELECT people.* WHERE
# owner_id = ?` via the real has_one :person). Overriding current_user
# swallowed both (D1). Now: current_user is resolved through the REAL
# `User.serialize_from_session` with a SYMBOLIC session key
# (`SYM_USER_CONV_id` — the principal must be symbolic, identity_symbolicity
# audit: a literal key folds every signed-in view as `users.id = 1`), lazily
# inside the interceptor window (see run_one). `user.person` is the real
# has_one; `user.contacts` is the real has_many (CollectionProxy, Patch 4 in
# targets.rb). There is NO anonymous scenario on this endpoint by
# construction — Devise 401s an anonymous request before the action.
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
  # results3 FIX (ported from results3/notifications_index — found while
  # smoke-testing that rerun once the render family was live; differs from
  # results2, which never needed a real response object since render was
  # mocked terminal): `setup_controller_request_and_response`
  # (test_case.rb:560-586) wires `@controller.request` but NOT
  # `@controller.response` — that assignment only happens inside
  # `ActionController::TestCase#process`'s `@controller.dispatch(action,
  # @request, @response)` call (test_case.rb:517), which this runner
  # deliberately does NOT use (Rack param-serialization concern — see the
  # header). Without it, `@_response` is nil and `performed?`/any real
  # `render` call crashes on it. Wire the already-built `@response`
  # (test_case.rb:579, `@response = build_response @response_klass`)
  # directly — pure test-harness plumbing, not a mock, not an app-source
  # change.
  ctrl.response = tc.instance_variable_get(:@response)
  [ctrl, tc]
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
# cycle 3 (2026-08-26, adversary W1-W3): `:mobile` is a DECLARED response
# format of this action (`respond_to :html, :mobile, :json, :js`; reached in
# the real app by ApplicationController#mobile_switch on
# `session[:mobile_view]`, by mobile-fu's device header, or by an explicit
# `format: :mobile`) rendering `index.mobile.haml` / `_conversation.mobile.
# haml` / `_conversation_subject.haml` — a different read order through the
# same associations (unloaded `messages.size` COUNT, `messages.pluck(
# :author_id)` on an unloaded relation, `conversation.author`). Direct
# dispatch skips the before_action, so the variant sets `request.format =
# :mobile` — exactly what mobile_switch does. `.js` is declared but
# templateless (responders' to_js -> default_render -> Template::Error, a
# real 500 with no data access beyond the html prefix) — not a corpus
# scenario (format_coverage_audit.py records it as templateless).
VARIANTS = {
  "html_plain"     => { format: :html },
  "html_withcid"   => { format: :html, with_cid: true },
  "json_plain"     => { format: :json },
  "json_withcid"   => { format: :json, with_cid: true },
  "mobile_plain"   => { format: :mobile },
  "mobile_withcid" => { format: :mobile, with_cid: true },
}.freeze

def run_one(label, variant, seeds)
  trim_interceptor_history!
  ConcolicTargets.seed_overrides = seeds
  ConcolicTargets.reset_seeds_used! # per-run consumed-seed set (concolic_targets.rb)
  ConversationsIndexTargets.reset_counts! # per-run count/rows cardinality map (targets.rb)
  ConversationsIndexTargets.reset_text_binds! # per-run text-derived query binds (targets.rb, cycle 4)
  ConversationsIndexTargets.reset_second_keys! # Rule D: per-run second-row key vars (one physical row, one variable)
  ctrl, = make_harness(ConversationsController)
  # LAZY/memoized so the resolution's queries fire INSIDE $interceptor.run
  # (the action's first current_user call), not before it.
  ctrl.singleton_class.define_method(:current_user) do
    conv_uid = symint("SYM_USER_CONV_id", ConcolicTargets.seed_for("SYM_USER_CONV_id", 1))
    @conv_user ||= User.serialize_from_session(conv_uid, "concolicsalt")
  end
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  # devise's authenticate_user! -> warden, which the controller-test rig has
  # no middleware for. Guard only (not on the direct-dispatch path anyway).
  ctrl.singleton_class.define_method(:authenticate_user!) { :authenticate_user_called }

  cfg = VARIANTS.fetch(variant)
  params = {}
  # cycle 4 (adversary round 2, NM-2): `params[:page]` is a recorded DECISION
  # — within range (nil -> page 1) or beyond the last page (will_paginate's
  # count still counts every row, the page query returns none:
  # `@visibilities.count > 0` with an empty collection, N05/R06). The concrete
  # page number only moves the wildcarded OFFSET; the decision is what the
  # rows mock reads (targets.rb rows_list).
  # The concrete page value is fixed here from the seed (it only moves the
  # wildcarded OFFSET); the DECISION itself is recorded INSIDE the
  # interceptor window (body below) — a symbool minted before
  # `$interceptor.run` is wiped by its reset (comments_index BUGFIX note).
  page_beyond_seed = ConcolicTargets.seed_for("SYM_PARAM_page_beyond", false) == true
  Thread.current[:convidx_page_beyond] = page_beyond_seed
  params[:page] = "2" if page_beyond_seed
  if cfg[:with_cid]
    cid_seed = ConcolicTargets.seed_for("SYM_PARAM_conversation_id", 1)
    params[:conversation_id] = symint("SYM_PARAM_conversation_id", cid_seed)
  end
  ctrl.params = params.with_indifferent_access
  ctrl.request.format = cfg[:format]

  # results3 FIX (companion to the make_harness response-wiring fix above,
  # ported from results3/notifications_index): `action_name`
  # (`AbstractController::Base`, `attr_internal :action_name`) is normally
  # set by `process(action_name)` (base.rb:126) — which, like
  # `@controller.response=`, only runs inside `dispatch`/`process`, not when
  # calling the action method directly. Cheap, general test-harness
  # plumbing; left unset it can NoMethodError deep in helper code that reads
  # `action_name` (e.g. `current_page?`/nav helpers real render now reaches).
  ctrl.send(:action_name=, "index")

  body = lambda do
    # ---------------------------------------------------------------------
    # T-f / M-5 (coordinator propagation matrix, 2026-08-28) — `set_locale`
    # runs BEFORE this action on every request.
    #
    # `ApplicationController#set_locale` (application_controller.rb:100-107) is
    # an ApplicationController before_action, so it runs on this signed-in
    # endpoint too:
    #     if user_signed_in?            # -> warden deserialize -> the users SELECT
    #       I18n.locale = current_user.language
    # `I18n.locale=` calls `enforce_available_locales!`, which raises
    # `I18n::InvalidLocale` for a NON-NIL value that is not an available locale.
    # `users.language` is a plain nullable string column: NOT NULL is not
    # declared and no DB constraint restricts it, so that state is reachable on
    # a real row. In it the request issues EXACTLY ONE statement — the Devise
    # users lookup — and 500s: no visibility join, no conversations read.
    #
    # Modelled here as a DECISION with its terminal, not as a pin:
    #  * touching `current_user` first reproduces the real order (the users
    #    lookup happens INSIDE set_locale, through `user_signed_in?`);
    #  * `<principal>_language_available` is the seeded, PC-recorded property of
    #    the pinned placeholder language string — the same pin+decision shape
    #    the batch already uses for `text` (`_text_has_dlink` & co.);
    #  * the false arm raises the REAL exception class, so the run terminates
    #    exactly where the real request does. `language = NULL` is NOT this arm
    #    (nil leaves I18n at its default and renders 200) — it is the true arm.
    # ---------------------------------------------------------------------
    u = ctrl.send(:current_user)
    lang = (u.respond_to?(:concolic_attrs) ? u.concolic_attrs["language"] : nil)
    lang_var = (lang.respond_to?(:sym_name) ? lang.sym_name : nil)
    av_name = "#{lang_var || 'SYM_PARAM_user'}_available"
    av_note = (u.respond_to?(:concolic_note) ? u.concolic_note.to_s : nil)
    lang_available = symbool(av_name, ConcolicTargets.seed_for(av_name, true), note: av_note)
    raise I18n::InvalidLocale, "concolic: users.language is not an available locale" unless
      lang_available == true

    # cycle 4: the page decision, recorded as a PC in the interceptor window
    page_beyond = symbool("SYM_PARAM_page_beyond", page_beyond_seed)
    Thread.current[:convidx_page_beyond] = (page_beyond == true)
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

  dump = $interceptor.run(body, {}, label: label, script: "run_dse.rb")
  # Seeds + scenario recorded into every dump: the assumption checker's flip
  # probes replay a snapshot's ENTIRE seed dict in the SAME scenario.
  # cycle 5: record the seeds this run actually CONSUMED (concolic_targets.rb
  # `seeds_used`), not the whole inherited dict — an unread entry is not a
  # fact about this run, and recorded as one it makes the corpus claim list
  # lengths and seeded dimensions the run never had (see the seed_for
  # comment). A SEEDS_ONLY replay records the dict VERBATIM: there the dict
  # is the probe's identity key (assumption_checker's ProbeCache matches its
  # replay dumps back by `concolic_seeds == <the dict it sent>`).
  used = ConcolicTargets.seeds_used
  dump["concolic_seeds"]    = ENV["SEEDS_ONLY"] ? seeds : seeds.select { |k, _| used.key?(k.to_s) }
  dump["concolic_scenario"] = { "name" => variant, "format" => VARIANTS.fetch(variant)[:format].to_s,
                                "conversation_id" => VARIANTS.fetch(variant)[:with_cid] ? true : false }
  dump
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

# 2026-08-26: VAR-vs-VAR compares (`(convidx_conv_lookup_1_id == first_1_id)`,
# `(to_ary_1_row_id == records_1_row_author_id)`, ... — the app's own
# `conversation.id == selected_id` / `Array#uniq` / `- [current_user.person]`
# identity compares) were UNFLIPPABLE, so only the seeded-equal polarity was
# ever explored and the checker demanded the other side. Flip them by seeding
# the LHS var to the RHS var's CURRENT concrete value (taken) or to a value
# one off it (not taken); `vals` is the run's symbolic_vars name->value map.
def flip_seed(expr, want_taken, vals = {})
  s = expr.to_s.strip
  return nil unless s.start_with?("(") && s.end_with?(")")
  m = /\A(.+?) (==|!=|<=|>=|<|>) (.+)\z/m.match(s[1..-2].strip)
  return nil unless m
  lhs, op, rhs_s = m[1].strip, m[2], m[3].strip

  rhs, ok = parse_literal(rhs_s)
  if !ok && %w[== !=].include?(op) && /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(rhs_s) &&
     /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(lhs) && lhs != rhs_s
    # var-vs-var compare: seed the FREE operand to the other's value. The
    # principal person id (SYM_..._person_id, derived from the Devise session
    # user) must never be reseeded (identity_symbolicity + it is a computed
    # column) — when one side is the principal, seed the OTHER side. Otherwise
    # seed whichever side has a recorded value.
    principal = ->(v) { v.include?("person_id") || v.include?("devise_user_first") }
    if principal.call(lhs) && !principal.call(rhs_s) && vals.key?(lhs)
      free, anchor_v = rhs_s, vals[lhs]
    elsif principal.call(rhs_s) && !principal.call(lhs) && vals.key?(rhs_s)
      free, anchor_v = lhs, vals[rhs_s]
    elsif vals.key?(rhs_s)
      free, anchor_v = lhs, vals[rhs_s]
    elsif vals.key?(lhs)
      free, anchor_v = rhs_s, vals[lhs]
    else
      return nil
    end
    av = anchor_v
    av = av.to_i if av.is_a?(String) && av =~ /\A-?\d+\z/
    return nil unless av.is_a?(Integer) || av.is_a?(String) || av == true || av == false
    equal_wanted = (op == "==") == want_taken
    return { free => (equal_wanted ? av : other_value(av, false)) }
  end
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

# SEEDS_ONLY / EXTRA_SEEDS_JSON / LABEL_SUFFIX (ported from comments_index):
# pure-replay knobs the assumption checker's flip probes drive. EXTRA seed
# dicts become worklist roots (in every wanted variant — the checker sets
# VARIANTS to the snapshot's scenario via env_by_scenario); SEEDS_ONLY
# suppresses flip expansion so each probe replays deterministically.
if ENV["EXTRA_SEEDS_JSON"] && File.exist?(ENV["EXTRA_SEEDS_JSON"])
  extra = JSON.parse(File.read(ENV["EXTRA_SEEDS_JSON"]))
  extra = [extra] if extra.is_a?(Hash)
  roots = wanted.flat_map { |v| extra.map { |sd| [v, sd] } }
  stack = ENV["SEEDS_ONLY"] ? roots : (roots + stack)
end
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

  # 2026-08-26: BREADTH-FIRST (FIFO). The LIFO order explored the most
  # recently pushed child first, i.e. it dove into the deepest branch's
  # suffix and enumerated that suffix's combinations for thousands of runs
  # while the EARLY gates (conversation not found, empty sidebar, ...) never
  # got their flip popped (first 8000 runs: 3611 html_withcid paths, every
  # `_not_found` still single-polarity). FIFO explores every single flip of
  # the root first, then pairs, ... — the low-order combinations the
  # coverage checker's cliques demand come first.
  variant, seeds = stack.shift
  skey = state_key(variant, seeds)
  # (replay mode: every root runs — see the SEEDS_ONLY note below)
  next if seen_states.include?(skey) && !ENV["SEEDS_ONLY"]
  seen_states << skey

  runs += 1
  label = format("%s_dse%04d%s", variant, runs, ENV["LABEL_SUFFIX"].to_s)

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

  # Same request shape, same path -> adds nothing to the execution tree, and
  # (2026-08-26, ported from comments_index) its flips are the SAME flips the
  # first run of this path already queued: expanding duplicates multiplied
  # the worklist by every seed that changes nothing (5000 runs -> 50 paths).
  #
  # REPLAY MODE (SEEDS_ONLY, 2026-08-27): the assumption gate's probes are
  # matched back by their recorded `concolic_seeds`, so it needs ONE DUMP PER
  # ROOT — a root whose path coincides with an earlier root must still produce
  # its dump. Skipping it made the gate fall back to one-JRuby-boot-per-root
  # singles (~75 s each: batch 1 was 40 roots -> 13 dumps + 27 singles).
  next if seen_paths.include?(sig) && !ENV["SEEDS_ONLY"]

  seen_paths << sig
  written += 1
  pc_total += pcs.size
  File.write(File.join(HERE, "dump_#{label}.json"), JSON.pretty_generate(dump))
  puts format("[%s] new path #%d pcs=%d stack=%d %s",
              label, written, pcs.size, stack.size,
              dump["error"] ? "error=#{dump['error']['type']}" : "")

  vals = {}
  (dump["symbolic_vars"] || []).each { |sv| vals[sv["name"].to_s] = sv["value"] }
  pcs.each do |expr, taken|
    fl = flip_seed(expr, !taken, vals)
    if fl.nil?
      unflippable[expr] += 1
      next
    end
    next if ENV["SEEDS_ONLY"] # pure replay: no flip expansion
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
      "present_in"    => %w[html_withcid json_withcid mobile_withcid]
    }
  },
  "user_identity"      => {
    "session key"        => "SYM_USER_CONV_id (symbolic; real Devise serialize_from_session -> devise_user_first)",
    "user.person"        => "real has_one :person (SingularAssociation#find_target, owner_id = $$(devise_user_first_1_id))",
    "anon scenario"      => "none — before_action :authenticate_user! with no except:"
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
