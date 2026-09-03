#!/usr/bin/env jruby
# frozen_string_literal: true
#
# people_show — results3 DISCIPLINE-CLEAN rerun. Ported from
# results2/people_show/run_dse.rb (fully symbolic params[:username], prefix-
# directed DSE, dispatch-based harness via tc.process — all UNCHANGED and
# still correct, see that file's own header) with ../concolic_targets.rb's
# discipline rebuild underneath it (results3/README.md + ../PHASE_A_PATCH.md
# + ../results2/MOCK_AUDIT.md):
#
#   - Section Z (render/render_to_string/render_to_body) + Y2
#     (default_render) REMOVED — `format.all`'s `gon.preloads[:person] =
#     @presenter.as_json` + `respond_with @presenter, layout: "with_header"`
#     and `format.json`'s `render json: @presenter.as_json` now run the real
#     PersonPresenter/ProfilePresenter#as_json chain and the real
#     show.html.haml/with_header layout instead of stopping at a terminal
#     marker.
#   - `Post.blocked_people` DESCENDED (undeclared) per Patch 3's note —
#     verified DEAD on this entrypoint (people#show never builds a
#     Post.for_a_stream), kept removed for discipline consistency.
#   - PHASE_A_PATCH.md Patches 1/2/3 (association/class-finder/User#blocks
#     real SQL notes) and Patch 4 (CollectionProxy) applied — the latter
#     recovers `profile.tags` as a real collection-association read.
#   - `Person#name` DESCENDED to `Person.name_from_attrs` (see
#     concolic_targets.rb's ConcreteSymbolicString section) — `self.profile`
#     now loads for real via Patch 1 instead of being skipped by an outer
#     Person#name mock; the page renders @person.name in the title, meta
#     tags, and PersonPresenter#base_hash.
#   - NEW: `Calculations#pluck` batch-local override (targets.rb) recovers
#     `ProfilePresenter#public_hash`'s `tags.pluck(:name)` — the "profile
#     section" query family results2 never saw — ported from
#     results2/conversations_index's identical descent.
#
# THE POINT OF THIS RERUN (results2/README.md + task brief):
#   params[:username] goes from a concrete Ruby String to a genuine
#   SymbolicString (SYM_PARAM_username, seeded "bob@example.org"), so the
#   people lookup's WHERE clause carries a $$(SYM_PARAM_username) bind
#   instead of the literal. See targets.rb §B for the two walls this
#   exposed (diaspora_id?'s lstrip/downcase, and the finder's own downcase)
#   and how each was closed WITHOUT touching src/, concolic_targets.rb, or
#   the app source.
#
# SCENARIOS: "anon_handle" (format.all/html — the mission's named target,
# richest single run: exercises the presenter-as_json chain feeding
# gon.preloads AND the real show.html.haml/with_header layout render AND
# Photo.visible(...).count) plus "anon_json" (format.json — the SAME
# presenter chain via `render json: @presenter.as_json`, without the
# template/count steps, useful for isolating which walls are template-layout-
# specific vs presenter-chain-specific). Both anonymous — the source people
# batch never explored signed-in `show` (mark_corresponding_notifications_read's
# SymbolicList#each wall), and results2 kept it anonymous-only; unchanged
# here, reported honestly as a known scope limit, not silently expanded.
#
# WHY PREFIX-DIRECTED DSE (see BATCH_BRIEFING.md / main README.md): the
# interceptor names symbolic results with a PER-RUN call ordinal
# (SYM_RESULT_<func>_<idx>, call_interceptor.rb:140) — NOT stable across
# runs. Feeding CoverageChecker.concrete_values back wholesale is unsound.
# Instead: from an observed path [c0..cn], emit one child per k that
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
#       /home/dev/project/reports/diaspora/results3/people_show/run_dse.rb
#
# Env: MAX_RUNS (default 300 per scenario), TIME_BUDGET seconds (default
# 1200 per scenario).

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
require "fileutils"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
PeopleTargets.install!($interceptor)          # ported §1-§6, unchanged
PeopleShowSymParams.install!($interceptor)    # NEW: diaspora_id? boundary mock + User#person

HERE        = File.dirname(File.expand_path(__FILE__))
MAX_RUNS    = (ENV["MAX_RUNS"] || 300).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 1200).to_i

# Devise/warden plumbing substitute (no warden env in the controller-test rig).
# Ported verbatim from results/people/run_dse.rb; unused on this scenario's
# anonymous path (current_user is nil) but kept for parity with the source
# harness in case a signed-in variant is added later.
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
  def test_class.determine_default_controller_class(_name); @concolic_ctrl; end
  tc = test_class.new("noop")
  tc.setup_controller_request_and_response
  tc.instance_variable_set(:@routes, Rails.application.routes)
  [tc.instance_variable_get(:@controller), tc]
end

PARAM_SYM_NAME = "SYM_PARAM_username"
PARAM_DEFAULT  = "bob@example.org"

SCENARIOS = {
  # The mission's named target: format.all (html) -> gon.preloads[:person] =
  # @presenter.as_json, Photo.visible(...).count(:all), then the real
  # show.html.haml/with_header layout render (title/meta_data content_for
  # blocks call @presenter.name / @presenter.metas_attributes).
  "anon_handle" => {
    format: nil,
    desc: "anonymous, default/html format -> gon.preloads presenter chain + " \
          "Photo.visible(...).count + real show.html.haml/with_header render",
  },
  # format.json -> render json: @presenter.as_json. Same presenter chain as
  # above, without the Photo.count/template-layout steps — isolates which
  # walls are layout-specific vs presenter-chain-specific.
  "anon_json" => {
    format: :json,
    desc: "anonymous, json format -> render json: @presenter.as_json " \
          "(PersonPresenter/ProfilePresenter#as_json chain, no html layout)",
  },
  # format.mobile (H1 hardening-lint find): `show` DECLARES :mobile
  # (people_controller.rb:76-79: @post_type = :all; person_stream;
  # respond_with @presenter) and show.mobile.haml EXISTS — the real app
  # reaches it via mobile_switch (session[:mobile_view]/device header) or
  # explicit format: :mobile, exactly as conversations_index cycle 3
  # (W1-W3) proved format dispatch works in this rig. The block is LAZY:
  # Stream::Person is built but its queries fire only when show.mobile.haml
  # renders `@stream.stream_posts.length > 0` -> Stream::Person#stream_posts
  # -> posts.for_a_stream -> for_visible_shareable_sql (+ like_posts_for_stream!).
  # The stream family is ALREADY declared in this endpoint's concolic_targets.rb
  # (excluding_blocks/tag_ids/decorated_stream_posts/like_posts_for_stream!,
  # lines ~673-785) — ported from people_stream — so mobile_show runs under
  # the current boundary with no new boundary targets. Anonymous: the stream
  # branch decision (user.present? ? user.posts_from : @person.posts.where
  # public: true, lib/stream/person.rb:16-18) takes the else arm, and
  # @post_type == :all selects the .stream branch of show.mobile.haml.
  "anon_mobile" => {
    format: :mobile,
    desc: "anonymous, mobile format -> show.mobile.haml: Stream::Person#stream_posts " \
          "(for_a_stream + like_posts_for_stream! chain) + mobile layout render",
  },
}.freeze

# ---------------------------------------------------------------------------
# One execution of a REAL PeopleController#show under a seed assignment.
# ---------------------------------------------------------------------------
def run_one(prefix, label, seeds)
  ConcolicTargets.seed_overrides = seeds
  PeopleTargets.begin_run!
  # boundary fix 2 (2026-09-03): per-run reset of the GonPreloadsShim ivar
  # (concolic_targets.rb X6b-preloads) so gon.preloads data cannot leak
  # across runs. Same contract as notifications run_dse.rb:156.
  if defined?(::Gon) && ::Gon.instance_variable_defined?(:@concolic_preloads)
    ::Gon.instance_variable_set(:@concolic_preloads, {})
  end
  user = PeopleTargets.symbolic_user("PE") # built fresh; unused as current_user (anon scenario)
  ctrl, tc = make_harness(PeopleController)
  ctrl.singleton_class.define_method(:current_user)    { nil }
  ctrl.singleton_class.define_method(:user_signed_in?) { false }
  tc.instance_variable_get(:@request).env["warden"] = StubWarden.new(user)

  sym_username = PeopleShowSymParams.symbolic_username(PARAM_DEFAULT)
  scen = SCENARIOS.fetch(prefix)

  dump = $interceptor.run(
    -> {
      begin
        tc.process(:show, method: "GET", params: { username: sym_username }, format: scen[:format])
      rescue Exception => e # rubocop:disable Lint/RescueException
        # tc.process/dispatch already routes RecordNotFound/AccountClosed
        # through the declared rescue_from handlers (ActionController::Rescue
        # wraps process_action). Defensive fallback only, mirroring
        # results3/people_stream's identical pattern, in case an exception
        # somehow escapes that wrapping now that render is real.
        handled = begin
          ctrl.send(:rescue_with_handler, e)
        rescue Exception # rubocop:disable Lint/RescueException
          nil
        end
        raise e unless handled
      end
      :ok
    },
    {}, label: label, script: "run_dse.rb"
  )
  # RUNNER-LOCAL MEMORY TRIM (src/ gap, reported — do not patch src/):
  # CallInterceptor keeps an unbounded @all_calls history across runs
  # (call_interceptor.rb — #run only ever reads the slice belonging to the
  # current run). Clearing between runs is behaviour-preserving.
  $interceptor.instance_variable_get(:@all_calls).clear
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

# ---------------------------------------------------------------------------
# Flip a single path condition — ported verbatim from
# results/people/run_dse.rb (handles ==, !=, len(...) != 0 / == 0, and
# integer ordering <=/</>=/> exactly, since every PC in this app compares a
# var to a literal — see that file's comment for why the boundary assignment
# is exact, not heuristic). This app's PCs include the ConcolicDate
# birthday_year <= 1004 ordering compare (dump_anon_handle_0002.json in the
# source batch), so the ordering branch is required here too.
# ---------------------------------------------------------------------------
def parse_literal(lit)
  case lit
  when "True"  then true
  when "False" then false
  when /\AStringVal\('(.*)'\)\z/m then Regexp.last_match(1)
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

  # `diaspora_handle.split('@')[0]` (Person#username -> #atom_url, reached
  # from layout_helper.rb's current_user_atom_tag on EVERY html render, now
  # real -- results3's render-boundary removal) records via
  # SymbolicString::SplitAccessor#[] (string.rb:279/288): idx=0 with no
  # separator match records `Not(Contains(StringVal(sep), VAR))` taken:true
  # (our default seed, no literal '@'); WITH a match it records the
  # DIFFERENT text `Contains(StringVal(sep), VAR)` taken:true instead (not
  # simply the same expr with taken:false -- string.rb's split_no_more vs
  # split_contains are separate record! call sites emitting separate expr
  # text). Only idx=0 (offset 0) is handled here -- `suffix_expr(0)` reduces
  # to the bare parent var, which is the only index this app's `[0]` calls
  # ever produce; a nonzero-offset SymbolicSubstring shape is out of scope
  # (never exercised on this endpoint).
  if (m = /\AContains\(StringVal\('(.*)'\), ([A-Za-z_][A-Za-z0-9_]*)\)\z/m.match(s))
    sep, var = m[1], m[2]
    return want_taken ? { var => "x#{sep}y" } : { var => "no-separator-here" }
  end
  if (m = /\ANot\(Contains\(StringVal\('(.*)'\), ([A-Za-z_][A-Za-z0-9_]*)\)\)\z/m.match(s))
    sep, var = m[1], m[2]
    return want_taken ? { var => "no-separator-here" } : { var => "x#{sep}y" }
  end

  # --- anon_mobile unflippables (results3/people_show, H1 mobile campaign) ---
  # The mobile render (show.mobile.haml -> stream -> people_helper
  # local_or_remote_person_path + ActiveSupport blank? checks) records FIVE
  # new PC shapes on the handle var(s) that the classic handlers above cannot
  # parse. All are concrete-value-derived (string.rb SubString/IndexOf), so
  # the only lever is SYNTHESIZING a parent-var seed that changes the derived
  # concrete value. Prefix-replay drift is accepted (path-signature dedup
  # bounds it):
  #
  #   1. `IndexOf(H, '@') == 1`  (219x taken:true, unflippable: the seed
  #      "x@y" always puts '@' at index 1) -> seed '@' at a DIFFERENT index.
  #   2. `Contains('.', H[0,1])` (72x false)  -> seed dot-leading H.
  #   3. `Contains('.', H[0,Len-0])` (72x false) -> seed H with/without dot.
  #   4. `(SubString(H,0,Len-0) == '')` / `(SubString(H,0,1) == '')` (blank?
  #      BLANK_RE) -> seed empty/non-empty.

  # 1. IndexOf(VAR, StringVal('sep')) == N
  if (m = /\AIndexOf\(([A-Za-z_][A-Za-z0-9_]*), StringVal\('(.*)'\)\) == (\d+)\z/m.match(s))
    var, sep, n = m[1], m[2], m[3].to_i
    if want_taken
      return { var => ("a" * n) + sep + "z" }
    else
      return { var => ("a" * (n + 1)) + sep + "z" }
    end
  end

  # 2. Contains(StringVal('.'), SubString(VAR, 0, 1)) -- username[0] == sep
  #    EMPIRICAL (734-run corpus): k in SubString(H,0,k) = length of
  #    split('@')[0] (username). k=1 -> '@' at position 1. T-side:
  #    username "." -> H = ".@b". F-side: username "a" -> H = "a@b".
  if (m = /\AContains\(StringVal\('(.*)'\), SubString\(([A-Za-z_][A-Za-z0-9_]*), 0, 1\)\)\z/m.match(s))
    var = m[2]
    return want_taken ? { var => ".@b" } : { var => "a@b" }
  end

  # 2b. Contains(StringVal('.'), SubString(VAR, 0, 2)) -- username[0..1]
  #    k=2 -> '@' at position 2. T-side: username ".a" -> H = ".a@b".
  #    F-side: username "aa" -> H = "aa@b".
  if (m = /\AContains\(StringVal\('(.*)'\), SubString\(([A-Za-z_][A-Za-z0-9_]*), 0, 2\)\)\z/m.match(s))
    var = m[2]
    return want_taken ? { var => ".a@b" } : { var => "aa@b" }
  end

  # 2c. Contains(StringVal('.'), SubString(VAR, 0, 3)) -- username[0..2]
  #    k=3 -> '@' at position 3. T-side: username "a.b" -> H = "a.b@c".
  #    F-side: username "abc" -> H = "abc@d".
  if (m = /\AContains\(StringVal\('(.*)'\), SubString\(([A-Za-z_][A-Za-z0-9_]*), 0, 3\)\)\z/m.match(s))
    var = m[2]
    return want_taken ? { var => "a.b@c" } : { var => "abc@d" }
  end

  # 3. Contains(StringVal('.'), SubString(VAR, 0, Length(VAR) - 0)) -- H.include?(sep)
  #    EMPIRICAL: the Length-0 form fires on the WHOLE handle as username
  #    (no-'@' / NOTC arm). ".a.b" (no @, dot) records T; the default
  #    "..._v" (no @, no dot) records F. Seeds: T -> ".a.b"; F -> "ab".
  if (m = /\AContains\(StringVal\('(.*)'\), SubString\(([A-Za-z_][A-Za-z0-9_]*), 0, Length\(\2\) - 0\)\)\z/m.match(s))
    var = m[2]
    return want_taken ? { var => ".a.b" } : { var => "ab" }
  end

  # 4a. (SubString(VAR, 0, Length(VAR) - 0) == '') -- H == ''
  if (m = /\A\(SubString\(([A-Za-z_][A-Za-z0-9_]*), 0, Length\(\1\) - 0\) == ''\)\z/m.match(s))
    var = m[1]
    return want_taken ? { var => "" } : { var => "x@y" }
  end

  # 4b. (SubString(VAR, 0, 1) == '') -- H[0] == ''
  if (m = /\A\(SubString\(([A-Za-z_][A-Za-z0-9_]*), 0, 1\) == ''\)\z/m.match(s))
    var = m[1]
    return want_taken ? { var => "" } : { var => "x@y" }
  end

  if (m = /\A\(len\((.+)\) (<=|>=|==|!=|<|>) (-?\d+)\)\z/m.match(s))
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
    return { "len(#{var})" => len }
  end

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

# SymbolicString#length on a symbolic entrypoint param, or on a pluck'd
# string column, is a SymbolicInt named "Length(VAR)" (string.rb:194) — kept
# for parity/safety (ported from results3/people_stream) since this
# endpoint's new pluck/collection-load surface may produce length PCs.
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

def digest(str)
  Digest::SHA256.hexdigest(str)[0, 16]
end

# ---------------------------------------------------------------------------
# Prefix-directed exploration of one scenario.
# ---------------------------------------------------------------------------
def explore(prefix)
  puts "\n== people_show/#{prefix} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
  started = Time.now

  seen_paths  = Set.new
  seen_seeds  = Set.new
  unflippable = Hash.new(0)
  errors      = Hash.new(0)
  runs        = 0
  written     = 0
  capped      = nil

  stack = [[{}, 0]]
  first_run = true

  until stack.empty?
    if runs >= MAX_RUNS
      capped = "MAX_RUNS"
      puts "[stop] MAX_RUNS cap (#{MAX_RUNS})"
      break
    end
    if Time.now - started > TIME_BUDGET
      capped = "TIME_BUDGET"
      puts "[stop] TIME_BUDGET cap (#{TIME_BUDGET}s)"
      break
    end

    seeds, min_k = stack.pop
    key = digest(JSON.generate(seeds.sort.to_h) + "|#{min_k}")
    next if seen_seeds.include?(key)
    seen_seeds << key

    runs += 1
    label = format("%s_%04d", prefix, runs)

    begin
      dump = run_one(prefix, label, seeds)
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "  [#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 200]}"
      errors["harness:#{e.class}"] += 1
      next
    end

    errors["run:#{dump['error']['type']}"] += 1 if dump["error"]

    pcs = path_conditions(dump)
    sig = digest(sig_of(pcs))

    if first_run || !seen_paths.include?(sig)
      seen_paths << sig
      first_run = false
      written += 1
      File.write(File.join(HERE, "dump_#{label}.json"), JSON.pretty_generate(dump))
      puts format("  [%s] paths=%d runs=%d pcs=%d stack=%d %s",
                  label, written, runs, pcs.size, stack.size,
                  dump["error"] ? "error=#{dump['error']['type']}" : "")
    end

    pcs.each_with_index do |(expr, taken), k|
      next if k < min_k
      fl = flip_any(expr, !taken)
      if fl.nil?
        unflippable[expr] += 1
        next
      end
      child = seeds.merge(fl)
      ckey = digest(JSON.generate(child.sort.to_h) + "|#{k + 1}")
      stack.push([child, k + 1]) unless seen_seeds.include?(ckey)
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
    "worklist_exhausted" => capped.nil?,
    "capped_by"          => capped,
    "max_runs"           => MAX_RUNS,
    "time_budget"        => TIME_BUDGET,
    "elapsed_seconds"    => elapsed.round(1),
    "run_errors"         => errors,
    "unflippable_pcs"    => unflippable,
  }
end

DIR = HERE
FileUtils.mkdir_p(DIR)
Dir.glob(File.join(DIR, "dump_*.json")).each { |f| File.delete(f) }

t0 = Time.now
scenario_summaries = SCENARIOS.keys.map { |p| explore(p) }

summary = {
  "entrypoint"      => "people_show",
  "params" => {
    "username" => { "symbolic_name" => PARAM_SYM_NAME, "seed" => PARAM_DEFAULT, "type" => "SymbolicString (SymUsernameString)" },
  },
  "scenarios"       => scenario_summaries,
  "total_elapsed_seconds" => (Time.now - t0).round(1),
}
File.write(File.join(DIR, "exploration_summary.json"), JSON.pretty_generate(summary))

puts "\n== people_show run_dse.rb done (#{(Time.now - t0).round(1)}s) =="
scenario_summaries.each do |s|
  puts format("  %-14s runs=%-6d paths=%-6d drained=%-6s capped_by=%s",
              s["scenario"], s["runs_executed"], s["distinct_paths"],
              s["worklist_exhausted"], s["capped_by"].inspect)
end
