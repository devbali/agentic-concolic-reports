# C7 RENDER-DOUBLING TRACE (2026-09-01) — a COPY of run_dse.rb with two
# diagnostic wrappers and nothing else changed. It answers one question with a
# measurement instead of a hypothesis: the corpus emits the `roles` existence
# reads EXACTLY twice as often as a real request does (html corpus 4 vs real 2;
# mobile corpus 8 vs real 4 — whole-corpus census, 4 954 dumps), while
# `services` and `COUNT(*) contacts` are exactly 1x because those are answered
# from a loaded association and cannot show a second serialisation.
# `_set_rendered_content_type` fires twice per dump, and did so BEFORE the C7
# layout change too, so this is pre-existing rig behaviour that only became
# visible once an uncached per-request read entered the corpus.
#!/usr/bin/env jruby
# frozen_string_literal: true
#
# notifications_index — results3 COMPLETION DRIVE runner (2026-08-27).
# Rebuilt for the completion engine, porting the conversations_index port:
#
#   - REAL Devise current_user resolution with a SYMBOLIC session key
#     (SYM_USER_NI_id + User.serialize_from_session -> devise_user_first
#     declared target; NotifDeviseUserNaming in targets.rb). The old runner
#     built a hand-symbolic user and overrode current_user / unread_
#     notifications, swallowing the two session-resolution statements (D1).
#   - Every RENDERABLE format of the action as a VARIANT: html / json /
#     mobile / xml (format_coverage_audit.py enforces this).
#   - Replay knobs SEEDS_ONLY / EXTRA_SEEDS_JSON / LABEL_SUFFIX; seeds +
#     scenario (incl. format) recorded into every dump.
#   - FIFO prefix-directed DSE with var-vs-var flip support (the principal
#     person-id compares in person_link_class are var-vs-var now that the
#     principal comes from the real Devise resolution).
#
# The 8-violation repair chain (preload emission, pluck projection, owner-
# qualified assoc names, find_by thread-local, TypeLinkedString STI pins)
# lives UNCHANGED in concolic_targets.rb + targets.rb §5f/§5g and is kept.
#
# Env: MAX_RUNS (default 8000), TIME_BUDGET seconds (default 3000),
#      VARIANTS (comma list), SEEDS_ONLY, EXTRA_SEEDS_JSON, LABEL_SUFFIX.

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
# Environment provisioning (not an app edit): `format.xml { render :xml =>
# @notifications.to_xml }` reaches Array#to_xml -> Builder::XmlMarkup, which
# the concolic RAILS_ENV does not autoload (a real server loads it via the
# builder gem). Require it so the xml variant renders honestly.
begin
  require "builder"
rescue LoadError => e
  warn "[notifications_index] could not require builder: #{e.class}"
end

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
NotificationsIndexTargets.install!($interceptor)
NotifDeviseUserNaming.install!($interceptor) # real Devise current_user resolution

# ---- C7 diagnostic wrappers (this file only) ----
module C7RenderTrace
  def self.hits; @hits ||= Hash.new(0); end
  def self.bt;   @bt   ||= Hash.new { |h, k| h[k] = [] }; end
  def self.note(kind)
    hits[kind] += 1
    bt[kind] << caller.reject { |l| l.include?("call_interceptor") || l.include?("_c7_render_trace") }.first(10)
  end
end
# Force the autoloads FIRST: `defined?(Role)` is false under Rails autoloading
# until the constant is referenced, so the previous version installed nothing.
::Role rescue nil
::UserPresenter rescue nil
::Role.singleton_class.prepend(Module.new do
  def is_admin?(p);  C7RenderTrace.note("Role.is_admin?");  super; end
  def moderator?(p); C7RenderTrace.note("Role.moderator?"); super; end
end)
::UserPresenter.prepend(Module.new do
  def as_json(*a); C7RenderTrace.note("UserPresenter#as_json"); super; end
  def to_json(*a); C7RenderTrace.note("UserPresenter#to_json"); super; end
end)
# ActionView::Base and the controller are CLASSES, so prepend really applies
# (module-prepend does not propagate to already-included classes on Ruby 2.6).
ActionView::Base.prepend(Module.new do
  def include_gon(*a); C7RenderTrace.note("include_gon"); super; end
end)
NotificationsController.prepend(Module.new do
  def default_render(*a); C7RenderTrace.note("default_render"); super; end
  def render(*a, &b);     C7RenderTrace.note("controller#render"); super; end
  def performed?;         r = super; C7RenderTrace.note("performed?=#{r ? 'true' : 'false'}"); r; end
  def gon_set_current_user; C7RenderTrace.note("gon_set_current_user"); super; end
end)
at_exit do
  puts "\n===== C7 RENDER TRACE ====="
  C7RenderTrace.hits.sort.each { |k, v| puts format("  %-28s %d", k, v) }
  %w[Role.is_admin? include_gon default_render controller#render].each do |k|
    next if C7RenderTrace.bt[k].empty?
    puts "\n  --- #{k} call sites ---"
    C7RenderTrace.bt[k].each_with_index do |b, i|
      puts "   ##{i + 1}"
      b.first(6).each { |l| puts "      #{l}" }
    end
  end
end

HERE        = File.dirname(File.expand_path(__FILE__))
ENTRY       = "notifications_index"
MAX_RUNS    = (ENV["MAX_RUNS"]    || 8000).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 3000).to_i
SHOW_PARAM  = "SYM_PARAM_show"

# ---------------------------------------------------------------------------
# Request variants: format x params[:type] presence. `show` rides symbolic
# in every variant (SYM_PARAM_show), seeded from "" so DSE can flip it to
# explore `params[:show] == "unread"`. `type` is a CONCRETE pin (Hash#eql?
# wall via types.has_key?(params[:type])); `page`/`per_page` are CONCRETE
# pins (WillPaginate Integer()/#to_i wall) — page 1 on every variant.
#   html/json/xml : the three explicit respond_to formats;
#   mobile        : mobile-fu registers :mobile as a text/html alias and
#                   ApplicationController#mobile_switch sets request.format
#                   = :mobile on session[:mobile_view]; index.mobile.haml /
#                   _notification.mobile.haml render a different read order.
# ---------------------------------------------------------------------------
VARIANTS = {
  "html_plain"  => { format: :html,   type: nil },
  "html_typed"  => { format: :html,   type: "liked" },
  "json_plain"  => { format: :json,   type: nil },
  "json_typed"  => { format: :json,   type: "liked" },
  "mobile_plain" => { format: :mobile, type: nil },
  "mobile_typed" => { format: :mobile, type: "liked" },
  "xml_plain"   => { format: :xml,    type: nil },
}.freeze

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
  # setup_controller_request_and_response wires request but not response;
  # wire the already-built @response so real render/performed? works.
  ctrl.response = tc.instance_variable_get(:@response)
  [ctrl, tc]
end

# CallInterceptor keeps an unbounded @all_calls history across runs; trim it
# runner-locally before every run (reported, not patched — src/ is read-only).
def trim_interceptor_history!
  h = $interceptor.instance_variable_get(:@all_calls)
  h.clear if h.respond_to?(:clear)
end

def run_one(label, variant, seeds)
  trim_interceptor_history!
  ConcolicTargets.seed_overrides = seeds
  # cycle 2 (ADVERSARY W1): the per-run concrete-text -> symbolic-var map
  # (a text-embedded diaspora-link guid is a query argument; the query
  # boundary rebinds it). Must not leak across runs.
  NotificationsIndexTargets.reset_text_binds! if NotificationsIndexTargets.respond_to?(:reset_text_binds!)
  # one fact, one variable: the per-RUN memo of (target, receiver, statement)
  NotificationsIndexTargets.reset_fact_cache! if NotificationsIndexTargets.respond_to?(:reset_fact_cache!)
  # class-level Gon.preloads memoizes on the Gon singleton across runs; reset.
  if defined?(::Gon) && ::Gon.instance_variable_defined?(:@concolic_preloads)
    ::Gon.instance_variable_set(:@concolic_preloads, {})
  end
  cfg = VARIANTS.fetch(variant)
  ctrl, = make_harness(NotificationsController)

  # LAZY/memoized so the resolution's queries fire INSIDE $interceptor.run
  # (the action's first current_user call), not before it.
  ctrl.singleton_class.define_method(:current_user) do
    ni_uid = symint("SYM_USER_NI_id", ConcolicTargets.seed_for("SYM_USER_NI_id", 1))
    @ni_user ||= User.serialize_from_session(ni_uid, "concolicsalt")
  end
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  ctrl.singleton_class.define_method(:authenticate_user!) { :authenticate_user_called }

  begin
    # C7: the MOBILE variants now reach :mobile through the APP'S OWN
    # `mobile_switch` filter (application_controller.rb:144-148 —
    # `session[:mobile_view] == true && request.format.html?`), exactly as the
    # concrete mobile manifest drives it, instead of being set here. With the
    # whole before_action chain running, the rig and its ground truth agree by
    # taking the SAME code path rather than by being configured alike.
    if cfg[:format] == :mobile
      ctrl.request.format = :html
      ctrl.request.session[:mobile_view] = true
    else
      ctrl.request.format = cfg[:format]
    end
  rescue StandardError => e
    warn "[warn] could not set request format: #{e.class}"
  end
  ctrl.send(:action_name=, "index")

  body = lambda do
    show_seed = ConcolicTargets.seed_for(SHOW_PARAM, "")
    sym_show  = symstr(SHOW_PARAM, show_seed)
    params = { show: sym_show }
    params[:type] = cfg[:type] if cfg[:type]
    # C7 / C-12 / INSTR-8: the REAL layout reads params[:controller] and
    # params[:action] (layout_helper.rb:30, `Diaspora.Page =
    # "#{params[:controller].camelcase}#{params[:action].camelcase}"`), which a
    # real dispatch supplies from the route and this direct dispatch does not.
    # Route metadata, not a query value: concrete on every variant.
    params[:controller] = "notifications"
    params[:action]     = "index"
    ctrl.params = params.with_indifferent_access

    # -------------------------------------------------------------------
    # C7 (2026-09-01) — THE WHOLE before_action CHAIN, not just set_locale.
    #
    # The rig used to invoke exactly ONE filter (`set_locale`, added for T-f /
    # M-5) and go straight to the action. A real request runs the entire
    # ApplicationController chain first, and one of those filters ISSUES READS
    # THROUGH THE RENDER: `gon_set_current_user` builds
    # `UserPresenter.new(current_user, a_ids)` and `gon.push`es it, and
    # `_head.haml`'s `include_gon` then serialises it — which is where
    # `SELECT "services".* WHERE user_id = ?` and
    # `SELECT COUNT(*) FROM "contacts" WHERE user_id = ? AND receiving = ?`
    # come from. Both were absent from the entire 39 956-dump corpus, and
    # un-pinning the layout alone did NOT bring them back: measured on smoke 4,
    # 0 events each over 114 dumps, because no presenter had ever been pushed.
    # Same class as the layout pin — a rig scope decision removing real reads —
    # and it survives the layout repair, so it is recorded as its own finding.
    #
    # The chain is READ FROM THE CONTROLLER ITSELF, never from a list copied
    # into this file (DISCIPLINE 14: "a scenario list copied into consumers
    # goes stale silently"). `authenticate_user!` is a no-op singleton here
    # because authentication is the SHARED BOUNDARY's scope (DISCIPLINE 15),
    # not this endpoint's; every other filter runs for real, including
    # `set_locale`, whose `I18n.locale = current_user.language` raises
    # `I18n::InvalidLocale` on a dropped locale and ends the request after the
    # single Devise principal load (T-f / M-5, decision
    # `<rep>_language_available` in targets.rb).
    # -------------------------------------------------------------------
    # Run the chain through RAILS' OWN callback runner, not a hand-rolled loop.
    # The first version of this iterated `_process_action_callbacks` and
    # invoked each filter by name, which IGNORED the callbacks' own conditions
    # — it called `configure_permitted_parameters` (guarded by
    # `if: :devise_controller?`, false here) 113 times in a 116-dump smoke
    # round. `run_callbacks(:process_action)` evaluates every :if/:unless/
    # :only/:except exactly as a real dispatch does, runs the AFTER and AROUND
    # callbacks too, and honours a halted chain.
    ctrl.send(:run_callbacks, :process_action) do
      begin
        ctrl.send(:index)
        # bare `format.html` (html + mobile) needs default_render explicitly
        # because direct dispatch skips ImplicitRender#send_action's wrapper;
        # xml/json call render inside their respond_to block (performed? true).
        ctrl.send(:default_render) unless ctrl.performed?
      rescue Exception => e # rubocop:disable Lint/RescueException
        handled = begin
          ctrl.send(:rescue_with_handler, e)
        rescue Exception
          nil
        end
        raise e unless handled
        handled
      end
    end
    :ok
  end

  dump = $interceptor.run(body, {}, label: label, script: "run_dse.rb")
  dump["concolic_seeds"]    = seeds
  dump["concolic_scenario"] = { "name" => variant, "format" => cfg[:format].to_s,
                                "type" => cfg[:type] }
  dump
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"].to_s, e["taken"] ? true : false] }
end

def parse_literal(lit)
  lit = lit.strip
  if (m = /\A(?:StringVal|IntVal|BoolVal|RealVal)\((.*)\)\z/m.match(lit))
    lit = m[1].strip
  end
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

# Flip a single PC. Handles scalar ==/!=/</<=/>/>=, negated int `((- VAR) == 0)`,
# `len(VAR)`/`SYM_LEN_VAR` list-length PCs, and VAR-vs-VAR compares (seed the
# free operand to the other's recorded value; never reseed the principal id).
def flip_seed(expr, want_taken, vals = {})
  s = expr.to_s.strip
  return nil unless s.start_with?("(") && s.end_with?(")")
  m = /\A(.+?) (==|!=|<=|>=|<|>) (.+)\z/m.match(s[1..-2].strip)
  return nil unless m
  lhs, op, rhs_s = m[1].strip, m[2], m[3].strip

  rhs, ok = parse_literal(rhs_s)
  if !ok && %w[== !=].include?(op) && /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(rhs_s) &&
     /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(lhs) && lhs != rhs_s
    principal = ->(v) { v.include?("person_id") || v.include?("devise_user_first") || v.include?("SYM_USER_NI") || v.include?("SYM_PERSON_NI") }
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
  elsif /\A(?:len\([A-Za-z_][A-Za-z0-9_]*\)|SYM_LEN_[A-Za-z_][A-Za-z0-9_]*)\z/.match?(lhs)
    key = lhs.start_with?("SYM_LEN_") ? "len(#{lhs[8..-1]})" : lhs
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

puts "== #{ENTRY} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
started = Time.now

wanted = ENV["VARIANTS"] ? ENV["VARIANTS"].split(",") : VARIANTS.keys
stack  = wanted.map { |v| [v, {}] }

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
    puts "[stop] MAX_RUNS reached"; break
  end
  if Time.now - started > TIME_BUDGET
    puts "[stop] time budget exhausted"; break
  end

  variant, seeds = stack.shift # FIFO (breadth-first)
  skey = state_key(variant, seeds)
  # STATE-dedup is for FRONTIER exploration. In SEEDS_ONLY REPLAY mode (the
  # assumption gate's flip probes) EVERY root must produce its own dump —
  # the gate replays up to 40 roots per JRuby launch and matches them back by
  # the recorded `concolic_seeds`; a root that is skipped here (or by the
  # path dedup below) leaves the gate unable to match it, so it re-runs that
  # root alone in a fresh ~75 s JRuby boot. One dump per root is exactly what
  # the gate needs (coordinator, 2026-08-27).
  unless ENV["SEEDS_ONLY"]
    next if seen_states.include?(skey)
    seen_states << skey
  end

  runs += 1
  label = format("%s_dse%04d%s", variant, runs, ENV["LABEL_SUFFIX"].to_s)

  begin
    dump = run_one(label, variant, seeds)
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts "[#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 200]}"
    errors["harness:#{e.class}"] += 1
    next
  end

  errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

  pcs = path_conditions(dump)
  sig = "#{variant}||#{sig_of(pcs)}"
  # PATH-dedup is for FRONTIER exploration (avoid re-expanding a seen path).
  # In SEEDS_ONLY REPLAY mode (the assumption gate's flip probes) it must be
  # OFF: the gate matches each replayed root back by its recorded
  # `concolic_seeds`, so two roots that happen to follow the same path must
  # STILL each write their own (seed-tagged) dump — otherwise the gate cannot
  # match the deduped root and re-runs it in a fresh JRuby boot ("single"
  # replays), which is the dominant cost of the gate at this scale. The
  # checker deletes these transient probe dumps after matching (no --keep),
  # so this does not pollute the corpus. (state_key dedup above still skips
  # genuinely identical seed dicts.)
  next if !ENV["SEEDS_ONLY"] && seen_paths.include?(sig)

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
    next if ENV["SEEDS_ONLY"]
    child = seeds.merge(fl)
    stack.push([variant, child]) unless seen_states.include?(state_key(variant, child))
  end
end

elapsed = Time.now - started
summary = {
  "entrypoint"         => ENTRY,
  "strategy"           => "prefix-directed DSE (seed inheritance + single-branch flip), FIFO",
  "signed_in"          => true,
  "request_variants"   => VARIANTS,
  "params"             => {
    "show" => { "symbolic_name" => SHOW_PARAM, "type" => "SymbolicString" },
    "type" => { "symbolic" => false, "reason" => "Hash#eql? wall (types.has_key?)" },
    "page" => { "symbolic" => false, "reason" => "WillPaginate Integer()/#to_i wall; page 1 pin" },
    # cycle 2 (ADVERSARY near-miss N5): `per_page` was in NO ledger entry while
    # its value sat in every notifications note as the literal `LIMIT 25`.
    # Recorded as a pin: `notifications_controller.rb:33 per_page =
    # params[:per_page] || 25` feeds WillPaginate's `Integer()` wall exactly as
    # `page` does, and the LIMIT/OFFSET literals it produces are wildcarded by
    # both judges. What its VALUE actually varies — the number of rows the page
    # holds, including the empty page beyond the last — IS explored, as the
    # `len(SYM_RESULT_ActiveRecord__Relation_to_ary_1_rows)` decision {0,1,many}
    # (targets.rb "cycle 2 N1"), which is the branch-relevant dimension.
    "per_page" => { "symbolic" => false,
                    "reason" => "WillPaginate Integer() wall; 25 pin. Row-count effect explored " \
                                "as len(...to_ary_1_rows) in {0,1,many}" },
  },
  "user_identity" => {
    "session key" => "SYM_USER_NI_id (symbolic; real Devise serialize_from_session -> devise_user_first)",
    "anon scenario" => "none — before_action :authenticate_user! with no except:",
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
  "unflippable_pcs"    => unflippable,
}
File.write(File.join(HERE, "exploration_summary.json"), JSON.pretty_generate(summary))

puts "\n== #{ENTRY} exploration done =="
puts "  runs executed  : #{runs}"
puts "  distinct paths : #{written}"
puts "  worklist empty : #{stack.empty?}"
puts "  elapsed        : #{elapsed.round(1)}s"
puts "  run errors     : #{errors.inspect}"
puts "  unflippable    : #{unflippable.keys.size} distinct PC shapes"
