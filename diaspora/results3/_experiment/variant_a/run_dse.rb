#!/usr/bin/env jruby
# frozen_string_literal: true
#
# notifications_index — results3 DISCIPLINE-CLEAN rerun. Ported from
# results2/notifications_index/run_dse.rb (which itself fixed symbolic
# entrypoint arguments — see the numbered list below, unchanged from
# results2) with TWO further changes per results3/README.md +
# ../concolic_targets.rb's header MOCK LEDGER:
#
#   (a) `ctrl.request.format` is now `:html`, not `:json` — this rerun's
#       whole point is to drive the real `format.html` -> `default_render`
#       -> `index.html.haml` -> N x `render partial: "notifications/
#       notification"` pipeline (see `run_one` below for the full note).
#   (b) `NotificationsController.layout(false)` is set once at load (below)
#       so the real per-row partial pipeline runs without the unrelated
#       site-chrome layout wall surface — see that line's comment.
#
# Both changes are downstream of ../concolic_targets.rb REMOVING the
# render-boundary/`default_render` no-ops (Section Z / Y2) that results2 (and
# every prior batch) used to short-circuit rendering entirely — see that
# file's header for the full discipline argument. ./targets.rb adds the
# leaf shims the now-real render pipeline needs (STI type-dispatch
# representative rows, `text`/`to_param` identity shims, the federation
# network-I/O wall) — see that file's header.
#
# Ported from ../../results/notifications_tags/run_dse.rb (+ its
# ../../results/notifications_tags/targets.rb wall-closing infrastructure,
# trimmed here to notifications_index-only in ./targets.rb).
#
# THE POINT OF THIS RERUN (results2/README.md + task brief) — what the
# SOURCE batch got wrong for this entrypoint:
#   1. `symbolic_user` PINNED `user.id = 1` and `person.id = 1`
#      (results/notifications_tags/run_dse.rb:66-68). notifications#index's
#      OWN query is `Notification.where(recipient_id: current_user.id)` — a
#      pinned id means this NEVER records a symbolic recipient_id bind, no
#      matter how much of the wall-fixing work in targets.rb happens
#      downstream. This rerun REMOVES that pin: `current_user.id` is now
#      SYM_USER_NI_id, and recipient_id renders `$$(SYM_USER_NI_id)`.
#   2. `symbolic_user` wired `user.unread_notifications` to `Notification.all`
#      (UNSCOPED — results/notifications_tags/run_dse.rb:82). Every
#      `current_user.unread_notifications.count`/`.group_by` query in the
#      source batch's dumps lost its recipient_id filter entirely. Rescoped
#      here to `Notification.where(recipient_id: user.id, unread: true)` per
#      results2/README.md §5 (manual mock scoping — the same technique
#      posts_show used for aspects/photos/contacts/blocks, chosen over
#      relying on the real `has_many` association reader on a `klass.allocate`
#      instance for reliability; see REPORT.md).
#   3. Request params (`type`, `show`, `page`, `per_page`) were all concrete
#      Ruby values. `params[:show] == "unread"` is a genuine `SymbolicString#==`
#      compare with NO framework wall — made symbolic here (`SYM_PARAM_show`).
#      `params[:type]` and `page`/`per_page` hit REAL framework walls when
#      made symbolic (Hash#eql? for `type` via `types.has_key?`; WillPaginate's
#      `Integer()`/`#to_i` coercion chain for `page`/`per_page`) — verified
#      offline (see REPORT.md) and kept concrete, documented per
#      results2/README.md item 4 ("attempt symbolic, pin only where a wall
#      forces it").
#
# WHY PREFIX-DIRECTED DSE (unchanged rationale — BATCH_BRIEFING.md / main
# README.md): SYM_RESULT_<func>_<idx> names carry a per-run call ordinal
# (call_interceptor.rb:140); flipping an early branch renumbers every later
# var, so feeding CoverageChecker's concrete_values back wholesale is unsound.
# Instead: from an observed path [c0..cn], emit one child per k that INHERITS
# the parent's seeds (prefix c0..c_{k-1} replays identically) and adds exactly
# one flip for c_k. Dedup on path signature; expand until the worklist drains
# or a cap is hit.
#
# Touches neither src/, the shared concolic_targets.rb, nor the diaspora app
# source — this directory carries PRIVATE copies of concolic_targets.rb
# (copied from results2/conversations_index/, carrying the collect_binds
# bind-ordering fix) and targets.rb (results2/README.md layout).
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
#       /home/dev/project/reports/diaspora/results3/notifications_index/run_dse.rb
#
# Env: MAX_RUNS (default 300), TIME_BUDGET seconds (default 1200)

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
NotificationsIndexTargets.install!($interceptor)

# results3 item 5/§Runtime scope decision (see concolic_targets.rb header):
# disable the layout so the real per-row `render partial:` pipeline
# (index.html.haml -> _notification.haml) runs, but the site-chrome layout
# (header/footer/sidebar-nav partials — unrelated to this endpoint's query
# shape, a large orthogonal wall surface) does not. Runtime reconfiguration
# in OUR runner script, not an app-source edit — same category as the
# `current_user`/`user_signed_in?` singleton-method overrides below.
NotificationsController.layout(false)

HERE        = File.dirname(File.expand_path(__FILE__))
ENTRY       = "notifications_index"
MAX_RUNS    = (ENV["MAX_RUNS"]    || 500).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 1800).to_i

# ---------------------------------------------------------------------------
# Symbolic user. Rebuilt PER RUN (after ConcolicTargets.seed_overrides is
# set), same discipline as the source batch: column vars are content-named
# (SYM_USER_NI_*), stable across runs, so rebuilding per run just lets each
# run's seeds take effect — it does not renumber anything.
# ---------------------------------------------------------------------------
def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user's person)")
  user   = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:person) { person }

  # results2 item 2 — PIN REMOVED. Feeds notifications_controller.rb:27/34/71's
  # `Notification.where(recipient_id: current_user.id)`.
  # (no define_singleton_method(:id) override here — symbolic_instance's own
  # SymbolicInt for the `id` column flows straight through.)

  # NOT identity data — plumbing pins to keep ApplicationController's
  # before_action chain (which runs before notifications#index's OWN code)
  # from crashing on framework walls orthogonal to this entrypoint:
  #   * `language`: `set_locale` does `I18n.locale = current_user.language`;
  #     a symbolic column value that happened to be an unrecognized locale
  #     string would raise I18n::InvalidLocale — noise unrelated to what
  #     we're testing. Pinned "en" (matches the source batch).
  #   * `gender`: `set_grammatical_gender` does
  #     `current_user.gender.to_s.tr(...)` — `SymbolicString#tr` is in the
  #     UNSUPPORTED stub list (src/ruby_runtime/string.rb:325-328, raises
  #     NotImplementedError unconditionally). Pinned "" (matches the source
  #     batch) so this before_action's early-return (`gender.empty?`) fires
  #     for real without reaching `.tr`.
  user.define_singleton_method(:language) { "en" }
  user.define_singleton_method(:gender)   { "" }

  # results2 item 5 — ASSOCIATION SCOPING. Source batch wired this to
  # `Notification.all` (unscoped — every recipient's notifications). Rescoped
  # to the real FK with the symbolic id, mirroring the real
  # `User#unread_notifications` body (`notifications.where(unread: true)`,
  # user.rb:109-111, where `notifications` is `has_many foreign_key:
  # recipient_id`, user.rb:87). Chosen as a manual mock over letting the real
  # `has_many` association reader fire on this klass.allocate'd instance —
  # same choice posts_show made for aspects/photos/contacts/blocks — for
  # reliability (untested whether AssociationScope's internals hit an
  # unrelated wall on a symbolic owner id; the manual form is verified by the
  # dumps below and semantically identical).
  user.define_singleton_method(:unread_notifications) do
    Notification.where(recipient_id: user.id, unread: true)
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
  ctrl = tc.instance_variable_get(:@controller)
  # results3 FIX (found while smoke-testing this rerun once the render family
  # was live — differs from results2, which never needed a real response
  # object since render was mocked terminal): `setup_controller_request_and_
  # response` (test_case.rb:560-586) wires `@controller.request` but NOT
  # `@controller.response` — that assignment only happens inside `ActionController
  # ::TestCase#process`'s `@controller.dispatch(action, @request, @response)`
  # call (test_case.rb:517), which this runner deliberately does NOT use (Rack
  # param-serialization concern, see the header note above). Without it,
  # `@_response` is nil and `performed?`/any real `render` call crashes on it.
  # Wire the already-built `@response` (test_case.rb:579,
  # `@response = build_response @response_klass`) directly — pure test-harness
  # plumbing, not a mock, not an app-source change.
  ctrl.response = tc.instance_variable_get(:@response)
  [ctrl, tc]
end

# ---------------------------------------------------------------------------
# One request scenario per concrete request shape (params[:type]/[:page]/
# [:per_page] are NOT symbolic — see the top-of-file note and REPORT.md for
# why). `show` rides along as ONE symbolic param (SYM_PARAM_show) present in
# every scenario, seeded from that scenario's original concrete value, so DSE
# can flip it to explore both `params[:show] == "unread"` outcomes from any
# scenario root.
# ---------------------------------------------------------------------------
SCENARIOS = [
  { name: "plain",       type: nil,      show_default: "",       page: nil, per_page: nil },
  { name: "typed",       type: "liked",  show_default: "",       page: nil, per_page: nil },
  { name: "unread_only", type: nil,      show_default: "unread", page: 2,   per_page: 5 },
].freeze

SHOW_PARAM = "SYM_PARAM_show"

# IMPORTANT (found while smoke-testing this runner, differs from the source
# batch): `ActionController::TestCase#process` round-trips params through a
# Rack query-string/body — that SERIALIZES any SymbolicString into a plain
# concrete String before the controller ever sees it, silently defeating
# `SYM_PARAM_show`. posts_show / comments_index avoid this by assigning
# `ctrl.params` directly and calling the action method (`ctrl.send(:show)`)
# instead of `tc.process`; ported here for the same reason. A side effect
# (verified, not just theoretical): calling the action method directly skips
# `process_action`'s before_action chain entirely, so `authenticate_user!`,
# `set_locale`, `set_grammatical_gender`, `gon_set_current_user` etc. never
# run — no StubWarden/devise plumbing is needed, and the `language`/`gender`
# pins on the symbolic user (kept below for documentation/robustness) are
# actually unreached on this call path.
def run_one(spec, seeds, label)
  ConcolicTargets.seed_overrides = seeds
  # gen2b: the class-level Gon.preloads shim (targets.rb) memoizes on the
  # Gon singleton, which outlives a run — stale contact hashes from a prior
  # run crashed gon_load_contact's dedupe block (8 gen3b runs). Reset per run.
  if defined?(::Gon) && ::Gon.instance_variable_defined?(:@concolic_preloads)
    ::Gon.instance_variable_set(:@concolic_preloads, {})
  end
  ctrl, = make_harness(NotificationsController)

  # results3 FIX #2 (same root cause as the SYM_PARAM_show bugfix documented
  # below, found independently against `symbolic_user`): `symbolic_user`
  # itself calls `ConcolicTargets.symbolic_instance` for `person`/`user`,
  # which registers `SYM_PERSON_NI_id`/`SYM_USER_NI_id` (+ every other
  # column) via `symint`/`symstr`'s `SymbolicFunc.register_var`. The
  # ORIGINAL code (still true of results2) called `symbolic_user("NI")` HERE
  # — before `$interceptor.run` — so `SymbolicFunc.reset!` (call_interceptor
  # .rb:262, start of `run`) wiped those registrations before
  # `save_and_clear_registered_vars` ever captured them. Consequence,
  # CONFIRMED live (coverage_report.py run): `person_link_class`'s real
  # `person.id == current_user.person.id` compare records a PC referencing
  # `SYM_PERSON_NI_id`, but that name was never in the dump's
  # `symbolic_vars` — the checker reports `Failed to parse constraint ...:
  # name 'SYM_PERSON_NI_id' is not defined` and drops the expr into
  # `unevaluable_exprs`. Fix: build the symbolic user INSIDE `body`, same
  # move as the SYM_PARAM_show fix (see `user = symbolic_user("NI")` inside
  # `body` below).

  # results3 item 2: drive :html (not results2's :json) — notifications#index's
  # `format.html` branch (no block -> default_render -> the real
  # index.html.haml -> N x `render partial: "notifications/notification"`)
  # is the entire point of this rerun; `format.json`'s `render_as_json` path
  # goes through `NotificationSerializer#note_html` -> `render_to_string`
  # instead, a DIFFERENT (and, per MOCK_AUDIT, equally real now) pipeline
  # this rerun is not driving.
  begin
    ctrl.request.format = :html
  rescue StandardError => e
    warn "[warn] could not set request format: #{e.class}"
  end

  # results3 FIX (companion to the make_harness response-wiring fix above):
  # `action_name` (`AbstractController::Base`, `attr_internal :action_name`)
  # is normally set by `process(action_name)` (base.rb:126,
  # `@_action_name = action.to_s`) — which, like `@controller.response=`,
  # only runs inside `dispatch`/`process`, not when calling the action method
  # directly. Left unset, `default_render`'s `template_exists?(action_name.to_s,
  # ...)` does `"".split("/")` -> `[]` -> `[].first.empty?` -> NoMethodError
  # on nil (found live; not an app bug, a test-harness-bypass gap).
  ctrl.send(:action_name=, "index")

  # BUGFIX (found while completing results2/notifications_index per
  # COMPLETION_BRIEF.md): `CallInterceptor#run` calls `SymbolicFunc.reset!`
  # (call_interceptor.rb:262) at the START of the run, which clears
  # `@registered_vars` — including anything `symstr`/`symint`/`symbool`
  # registered via `SymbolicFunc.register_var` (string.rb:460-462) BEFORE
  # `$interceptor.run` was invoked. The original code built `sym_show` and
  # assigned `ctrl.params` here, outside `body` — so `register_var`'s
  # registration for SYM_PARAM_show was wiped by `reset!` before
  # `save_and_clear_registered_vars` ever captured it, and the dump's
  # `symbolic_vars` never carried SYM_PARAM_show (checker's universe was
  # empty for it — the expr became unparseable/excluded, producing a HOLLOW
  # complete=true). Fix: build `sym_show` and assign `ctrl.params` INSIDE
  # `body`, so the `symstr` call — and its `register_var` — executes AFTER
  # `reset!`, during the window `run` actually snapshots
  # (`SymbolicFunc.save_and_clear_registered_vars`, call_interceptor.rb
  # ~L380). Verified: same root cause independently confirmed against
  # results2/comments_index's `symstr(CFG[:param_sym_name], ...)` call,
  # which sits in the same pre-`run` position and suffers the identical
  # loss (SYM_PARAM_post_id never appears in comments_index's dumps'
  # symbolic_vars either) — that directory is read-only for this task so
  # it is reported, not patched, here.
  body = lambda do
    user = symbolic_user("NI") # results3 FIX #2 — see comment above run_one's body
    ctrl.singleton_class.define_method(:current_user)    { user }
    ctrl.singleton_class.define_method(:user_signed_in?) { true }

    show_seed = ConcolicTargets.seed_for(SHOW_PARAM, spec[:show_default])
    sym_show  = symstr(SHOW_PARAM, show_seed)
    params = { show: sym_show }
    params[:type]     = spec[:type]     if spec[:type]
    params[:page]     = spec[:page]     if spec[:page]
    params[:per_page] = spec[:per_page] if spec[:per_page]
    ctrl.params = params.with_indifferent_access

    begin
      ctrl.send(:index)
      # results3 FIX (found while smoke-testing this rerun, differs from
      # results2): calling the action method directly — deliberately, to
      # dodge `tc.process`'s Rack param-serialization (see the note above) —
      # ALSO skips `ActionController::ImplicitRender#send_action`'s wrapper
      # (`ret = super; default_render unless performed?`), which is the ONLY
      # thing that invokes `default_render` for a bare `format.html` (no
      # block) response — `respond_to`'s own `Collector#response` returns a
      # `VariantCollector` whose `#variant` is nil when no `.none`/`.any`
      # variant was declared (mime_responds.rb `Collector#response`/
      # `VariantCollector#variant`), so `response.call if response` is a
      # no-op for bare `format.html`. Net effect verified via a standalone
      # debug probe (scratch, not committed): with render family REMOVED
      # (../concolic_targets.rb's header MOCK LEDGER) but `process_action`
      # bypassed, `ctrl.send(:index)` returns cleanly, `@notifications`/
      # `@group_days` are correctly populated, `_set_rendered_content_type`
      # fires (that one DOES get called from inside `respond_to` itself,
      # mime_responds.rb:201) — but `render`/`render_to_body`/`default_render`
      # are NEVER invoked, so the whole per-row partial pipeline this rerun
      # exists to exercise silently never ran, with NO error to show for it
      # (a "hollow complete" of a different shape than results2's). Fix:
      # replicate `ImplicitRender#send_action`'s own postcondition explicitly
      # — call `default_render` ourselves iff the action didn't already
      # perform a response (xml/json branches DO call `render` for real
      # inside their `respond_to` blocks, so `performed?` is already true
      # there and this is correctly a no-op on those paths).
      ctrl.send(:default_render) unless ctrl.performed?
    rescue Exception => e # rubocop:disable Lint/RescueException
      handled = begin
        ctrl.send(:rescue_with_handler, e)
      rescue Exception # a handler that itself raises -> let the original stand
        nil
      end
      raise e unless handled
      handled
    end
    :ok
  end

  dump = $interceptor.run(body, {}, label: label, script: "run_dse.rb")

  # RUNNER-LOCAL LEAK WORKAROUND (reported, not patched in src/):
  # CallInterceptor keeps an unbounded @all_calls history across runs.
  # `run` only ever slices @all_calls[old_count..], so clearing between runs
  # is behaviour-preserving.
  hist = $interceptor.instance_variable_get(:@all_calls)
  hist.clear if hist.respond_to?(:clear)
  dump
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

def parse_literal(lit)
  lit = lit.strip
  # SymbolicString comparisons (string.rb#==, e.g. SYM_PARAM_show) render the
  # RHS as `StringVal('...')` (z3_str_val), not a bare quoted literal like
  # SymbolicInt's op_cmp does — unwrap it first (source-batch flip_seed never
  # needed this since it never saw a SymbolicString PC).
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

# Flip a single path condition to the desired outcome — handles every PC
# shape this runtime emits on this entrypoint: (VAR == LIT), (VAR != LIT),
# (len(X) != 0), and SymbolicInt ordering (<, <=, >, >=). Ported verbatim
# from results/notifications_tags/run_dse.rb's flip_seed.
def flip_seed(expr, want_taken)
  m = /\A\((\S+) (==|!=|<=|>=|<|>) (.+)\)\z/m.match(expr.to_s.strip)
  return nil unless m
  var, op, lit = m[1], m[2], m[3].strip
  parsed = parse_literal(lit)
  return nil if parsed.nil? && !%w[True False].include?(lit)

  other = lambda do |v|
    case v
    when true, false then !v
    when Integer     then v + 1
    when String      then v.empty? ? "concolic_other" : ""
    end
  end

  value =
    case op
    when "==" then want_taken ? parsed : other.call(parsed)
    when "!=" then want_taken ? other.call(parsed) : parsed
    when "<"  then parsed.is_a?(Integer) ? (want_taken ? parsed - 1 : parsed + 1) : nil
    when "<=" then parsed.is_a?(Integer) ? (want_taken ? parsed : parsed + 1) : nil
    when ">"  then parsed.is_a?(Integer) ? (want_taken ? parsed + 1 : parsed - 1) : nil
    when ">=" then parsed.is_a?(Integer) ? (want_taken ? parsed : parsed - 1) : nil
    end
  return nil if value.nil?

  { var => value }
end

def digest(str)
  Digest::MD5.digest(str)
end

# ---------------------------------------------------------------------------
# Prefix-directed exploration — one DSE root per request scenario, the
# scenario index riding along on the worklist so a flip stays inside the
# scenario that produced it (matches results/notifications_tags/run_dse.rb).
# ---------------------------------------------------------------------------
puts "== #{ENTRY} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
started = Time.now

stack       = SCENARIOS.each_index.map { |i| [i, {}] }.reverse

# gen2 coverage loop (2026-08-19): EXTRA_SEEDS_JSON names a JSON file holding
# a LIST of {var => seed} dicts (the checker's missing[].concrete_values);
# each becomes a scenario-0 root pushed ON TOP of the default roots so the
# targeted demand runs before frontier exploration. LABEL_SUFFIX (e.g.
# "_seedloop1") keeps an append round's dump numbering collision-free
# against an existing corpus in this directory.
if ENV["EXTRA_SEEDS_JSON"] && File.exist?(ENV["EXTRA_SEEDS_JSON"])
  extra_seeds = JSON.parse(File.read(ENV["EXTRA_SEEDS_JSON"]))
  extra_seeds.reverse_each { |s| stack.push([0, s]) }
  puts "  [seeds] #{extra_seeds.length} targeted seed dicts loaded from EXTRA_SEEDS_JSON"
end
seen_seeds  = Set.new
seen_paths  = Set.new
unflippable = Hash.new(0)
errors      = Hash.new(0)
runs        = 0
written     = 0
max_pcs     = 0
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

  si, seeds = stack.pop
  spec = SCENARIOS[si]
  key = "#{si}|#{digest(JSON.generate(seeds.sort.to_h))}"
  next if seen_seeds.include?(key)
  seen_seeds << key

  runs += 1
  label = format("%s%s_dse%04d", spec[:name], ENV["LABEL_SUFFIX"].to_s, runs)

  begin
    dump = run_one(spec, seeds, label)
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts "[#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 160]}"
    errors["harness:#{e.class}"] += 1
    next
  end

  errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

  pcs = path_conditions(dump)
  max_pcs = pcs.size if pcs.size > max_pcs
  sig = "#{si}|#{digest(sig_of(pcs))}"
  next if seen_paths.include?(sig)

  seen_paths << sig
  written += 1
  dump["concolic_seeds"]    = seeds
  dump["concolic_scenario"] = { "name" => spec[:name], "type" => spec[:type],
                                 "show_default" => spec[:show_default],
                                 "page" => spec[:page], "per_page" => spec[:per_page] }
  File.write(File.join(HERE, "dump_#{label}.json"), JSON.pretty_generate(dump))

  puts format("  [%s] paths=%d runs=%d pcs=%d stack=%d %s",
              label, written, runs, pcs.size, stack.size,
              dump["error"] ? "error=#{dump['error']['type']}" : "")

  pcs.each do |expr, taken|
    fl = flip_seed(expr, !taken)
    if fl.nil?
      unflippable[expr] += 1
      next
    end
    # SEEDS_ONLY (gen2 coverage loop, 2026-08-19): pure targeted-replay mode.
    # The worklist is LIFO, so a root's flip-children preempt every
    # remaining root — in a 96-root seeded round with MAX_RUNS=250, roots
    # past ~#5 never ran (found empirically: no dump ever carried the
    # count_2=0 seed dicts at indexes 64+). With SEEDS_ONLY=1 no children
    # are pushed: every targeted root replays exactly once.
    next if ENV["SEEDS_ONLY"]
    child = seeds.merge(fl)
    ckey = "#{si}|#{digest(JSON.generate(child.sort.to_h))}"
    stack.push([si, child]) unless seen_seeds.include?(ckey)
  end
end

elapsed = Time.now - started

summary = {
  "entrypoint"         => ENTRY,
  "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip), one root per request scenario",
  "scenarios"          => SCENARIOS.map { |s| s.merge(show_param: SHOW_PARAM) },
  "params"             => {
    "show"     => { "symbolic_name" => SHOW_PARAM, "type" => "SymbolicString", "note" => "symbolic in all scenarios" },
    "type"     => { "symbolic" => false, "reason" => "Hash#eql? wall — types.has_key?(params[:type]); see REPORT.md" },
    "page"     => { "symbolic" => false, "reason" => "WillPaginate::PageNumber Integer()/#to_i wall; see REPORT.md" },
    "per_page" => { "symbolic" => false, "reason" => "WillPaginate::Collection#total_entries= .to_i wall; see REPORT.md" },
  },
  "user"               => {
    "SYM_USER_NI_id"   => "current_user.id — PIN REMOVED, flows symbolic into recipient_id",
    "SYM_PERSON_NI_id" => "current_user.person.id — PIN REMOVED, flows symbolic (unreached on this entrypoint)",
    "language"         => "pinned \"en\" — before_action plumbing, not identity (see symbolic_user comment)",
    "gender"           => "pinned \"\" — before_action plumbing, not identity (see symbolic_user comment)",
  },
  "runs_executed"      => runs,
  "distinct_paths"     => written,
  "seed_sets_tried"    => seen_seeds.size,
  "stack_remaining"    => stack.size,
  "worklist_exhausted" => stack.empty?,
  "stop_reason"        => stop_reason,
  "max_pcs_on_a_path"  => max_pcs,
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
puts "  stop reason    : #{stop_reason}"
puts "  elapsed        : #{elapsed.round(1)}s"
puts "  run errors     : #{errors.inspect}"
puts "  unflippable    : #{unflippable.keys.size} distinct PC shapes"
