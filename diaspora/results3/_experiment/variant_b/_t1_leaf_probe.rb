#!/usr/bin/env jruby
# frozen_string_literal: true
#
# _t1_leaf_probe.rb — variant_b T1 mock leaf-probe harness (DISCIPLINE_TESTS.md).
#
# For each candidate (klass, method):
#   1. Capture the ORIGINAL UnboundMethod BEFORE ConcolicTargets/NotificationsIndexTargets
#      install (so we can invoke the pristine real body directly, bypassing ONLY this
#      target's own patch -- every OTHER declared target stays patched, exactly as
#      "all targets declared except the method under test").
#   2. For a fixture matrix, bind+call the original on concrete Ruby fixtures inside a
#      rolled-back transaction.
#   3. Record: TargetCall delta (@all_calls, with target names), connection-adapter
#      touches (hooked execute/exec_query/exec_insert/exec_update/exec_delete -> raise
#      ConcolicLeafProbeViolation, rescued here), exceptions raised, and Ruby Coverage
#      line-hit deltas scoped to the method's computed source range.
#
# Writes LEAF_PROBES.json (machine-readable) + prints a summary to stdout/log.
# Does NOT touch concolic_targets.rb/targets.rb. Read/probe only.

require "coverage"
Coverage.start(lines: true)

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require_relative "concolic_targets"
require_relative "targets"
require "action_controller/test_case"
require "json"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false

class ConcolicLeafProbeViolation < StandardError; end

# ---------------------------------------------------------------------------
# 1. Capture ORIGINAL unbound methods for every candidate, BEFORE install!.
# ---------------------------------------------------------------------------
CANDIDATES = [
  [ActionController::Metal, :status=, :Y1],
  [ActionController::Redirecting, :redirect_to, :Y3a],
  [ActionDispatch::Routing::UrlFor, :url_for, :Y3b],
  [DeviseController, :assert_is_devise_resource!, :Y4],
  [ActiveRecord::Associations::SingularAssociation, :writer, :W1],
  [ActiveRecord::Associations::SingularAssociation, :find_target, :W3],
  [ActiveRecord::Associations::BelongsToPolymorphicAssociation, :find_target, :W3b],
  [ActionController::Rendering, :_set_rendered_content_type, :W4],
  [DeviseController, :devise_mapping, :W7],
  [ActiveRecord::Base, :to_param, :"5i"],
  [ActionController::Instrumentation, :redirect_to, :X6g],
]
# ActionController::Head#head resolved correctly (Metal doesn't define it in
# this Rails version -- W2's guard on ActionController::Metal never fires;
# the module actually patched is ActionController::Head, declared later at
# concolic_targets.rb:1242). Added under its real class.
CANDIDATES << [ActionController::Head, :head, :W2_actual] if defined?(ActionController::Head) && ActionController::Head.instance_methods.include?(:head)

# X8d: ActionDispatch::Journey::Router::Utils.escape_segment -- the file's
# OWN comment says "CONFIRMED reached on this endpoint" (post_path/
# person_path route generation in notifications_helper.rb/people_helper.rb)
# -- missed in the first T1 sweep pass, added here.
if defined?(ActionDispatch::Journey::Router::Utils) && ActionDispatch::Journey::Router::Utils.respond_to?(:escape_segment)
  CANDIDATES << [ActionDispatch::Journey::Router::Utils.singleton_class, :escape_segment, :X8d]
end

# ---------------------------------------------------------------------------
# Design-mock family spot checks (#1-#11 query-boundary mocks) -- these are
# EXEMPT from removal regardless of probe outcome (they ARE the SQL
# interception layer), but T1/DISCIPLINE_TESTS.md still calls for them to be
# "probed and recorded". Informational only: no 100%-coverage gate, no
# PASS/FAIL admissibility consequence -- the expected/correct outcome is
# "reaches SQL" (confirms the boundary is genuinely there, not vestigial).
# ---------------------------------------------------------------------------
INFORMATIONAL = {}
design_candidates = [
  [ActiveRecord::FinderMethods, :find_by, :"design#1"],
  [ActiveRecord::Calculations, :count, :"design#5"],
  [ActiveRecord::Relation, :update_all, :"design#7"],
  [ActiveRecord::Querying, :find_by_sql, :"design#9"],
  [User, :blocks, :"design#User_blocks"],
  [ActiveRecord::Calculations, :pluck, :"design#pluck"],
]
design_candidates.each { |k, m, t| INFORMATIONAL[[k, m]] = true }
CANDIDATES.concat(design_candidates)

ORIGINALS = {}
CANDIDATES.each do |klass, meth, _tag|
  begin
    ORIGINALS[[klass, meth]] = klass.instance_method(meth)
  rescue NameError => e
    ORIGINALS[[klass, meth]] = e
  end
end

# ---------------------------------------------------------------------------
# 2. Boot the normal target-declared environment (matches run_dse.rb).
# ---------------------------------------------------------------------------
$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
NotificationsIndexTargets.install!($interceptor)
NotificationsController.layout(false)

# ---------------------------------------------------------------------------
# 3. Connection-adapter touch hook.
# ---------------------------------------------------------------------------
# Warm ActiveRecord's schema cache (PRAGMA table_info / sqlite_master
# lookups) for every loaded model BEFORE installing the connection-touch
# hook. Rails lazily loads column metadata the FIRST time any code touches
# a model's attributes; without this warm-up the leaf-probe's connection
# hook produces FALSE POSITIVES from ActiveRecord's OWN one-time internal
# metadata SQL (PRAGMA table_info(...), sqlite_master lookups), which has
# nothing to do with whether the PROBED METHOD's body issues an
# application data query. Empirically discovered: W1/W3/W3b/§5i all showed
# spurious "connection touch" on their FIRST fixture until this warm-up was
# added (see _t1_probe_run5/6.log).
begin
  ActiveRecord::Base.connection.data_sources
  ActiveRecord::Base.connection.tables
rescue StandardError
  nil
end
[Person, Comment, Notification, User, Block, Post].each do |m|
  begin
    m.columns_hash
  rescue StandardError
    nil
  end
end
# Also force-load whatever's already autoloaded, for good measure.
ActiveRecord::Base.descendants.each do |m|
  begin
    m.columns_hash unless m.abstract_class?
  rescue StandardError
    nil
  end
end

$conn_touch_log = []
# ActiveRecord's OWN schema/metadata introspection (PRAGMA table_info,
# sqlite_master table listings) is NOT the "SQL potential" T1 cares about --
# it is framework bootstrapping that fires regardless of which method is
# under test (see the warm-up comment above; empirically it can still recur
# per-fixture even after warm-up, likely a query-cache interaction with the
# rolled-back probe transactions -- documented rather than fully chased
# down, honesty over false confidence). Let metadata SQL through so the
# fixture can complete (accurate coverage measurement); still LOG it (raw
# signal preserved) but only RAISE for genuine application-data SQL.
METADATA_SQL_RE = /\A\s*PRAGMA |sqlite_master|sqlite_temp_master/i
conn_hook = Module.new do
  %i[execute exec_query exec_insert exec_update exec_delete raw_execute].each do |m|
    define_method(m) do |*args, &blk|
      sql = (args.first.to_s rescue "?")[0, 200]
      $conn_touch_log << { method: m, sql: sql }
      if sql =~ METADATA_SQL_RE
        super(*args, &blk)
      else
        raise ConcolicLeafProbeViolation, "connection##{m} touched: #{sql}"
      end
    end
  end
end
# Hooking ActiveRecord::ConnectionAdapters::AbstractAdapter alone is NOT
# sufficient: the JDBC adapter stack (vendor/jdbc-adapter,
# activerecord-jdbcsqlite3-adapter) defines execute/exec_query/etc DIRECTLY
# on the concrete adapter class, which sits BELOW AbstractAdapter in the
# receiver's own ancestor chain -- a module prepended only to the ancestor
# ends up shadowed by the subclass's own method (verified empirically: a
# real UPDATE reached SQLite with the AbstractAdapter-only hook installed).
# Prepend to every class in the actual connection object's ancestry instead.
ActiveRecord::ConnectionAdapters::AbstractAdapter.prepend(conn_hook)
begin
  live_conn = ActiveRecord::Base.connection
  live_conn.singleton_class.prepend(conn_hook)
  live_conn.class.prepend(conn_hook)
  live_conn.class.ancestors.each do |anc|
    next unless anc.name.to_s.include?("Jdbc") || anc.name.to_s.include?("SQLite") || anc.name.to_s.include?("Sqlite")
    anc.prepend(conn_hook) if anc.is_a?(Class)
  end
rescue StandardError => e
  warn "[t1] WARNING: could not fully hook the live connection class: #{e.class}: #{e.message}"
end

# ---------------------------------------------------------------------------
# 4. Body line-range finder (same heuristic as _t1_inspect.rb).
# ---------------------------------------------------------------------------
def find_end_line(lines, start_idx)
  depth = 0
  opens = /\b(def|do|if|unless|case|begin|class|module|while|until)\b/
  i = start_idx
  while i < lines.length
    stripped = lines[i].strip
    is_modifier = stripped =~ /\S.*\s(if|unless|while|until)\s+\S.*[^;]$/ && !(stripped =~ /^(if|unless|while|until|case|def|class|module|begin)\b/)
    opens_here = 0
    ends_here = 0
    stripped.scan(opens) { opens_here += 1 } unless is_modifier && i != start_idx
    stripped.scan(/\bend\b/) { ends_here += 1 }
    depth += opens_here
    depth -= ends_here
    return i if i > start_idx && depth <= 0
    i += 1
  end
  start_idx
end

def cov_slice(file, sline, eline)
  res = Coverage.peek_result
  arr = res[file]
  return nil unless arr
  arr[(sline - 1)..(eline - 1)]
end

# ---------------------------------------------------------------------------
# 5. Fixture builders (per-method, hand-built from _t1_inspect.log source dump).
# ---------------------------------------------------------------------------
def fake_response
  # A REAL ActionDispatch::Response (not a hand stub) so every accessor the
  # real bodies touch (status=, content_type=, location=, reset_body!,
  # filtered_location, ...) behaves exactly as production code expects.
  ActionDispatch::Response.new
end

def fake_request
  req = ActionDispatch::TestRequest.create
  req
end

def probe_controller(klass = NotificationsController)
  ctrl = klass.new
  ctrl.instance_variable_set(:@_response, fake_response)
  ctrl.instance_variable_set(:@_request, fake_request)
  ctrl
end

def probe_devise_controller(klass)
  ctrl = probe_controller(klass)
  ctrl
end

FIXTURES = {
  [ActionDispatch::Journey::Router::Utils.singleton_class, :escape_segment] => [
    { label: "nil-ish (empty string)", recv: -> { ActionDispatch::Journey::Router::Utils }, args: [""] },
    { label: "typical", recv: -> { ActionDispatch::Journey::Router::Utils }, args: ["hello-world"] },
    { label: "boundary (needs escaping)", recv: -> { ActionDispatch::Journey::Router::Utils }, args: ["a b/c?d"] },
  ],
  [ActionController::Metal, :status=] => [
    { label: "nil-ish",  recv: -> { probe_controller }, args: [nil] },
    { label: "typical",  recv: -> { probe_controller }, args: [200] },
    { label: "boundary", recv: -> { probe_controller }, args: [:not_found] },
  ],
  [ActionController::Redirecting, :redirect_to] => [
    { label: "nil-ish (options=nil, raise-branch 1)", recv: -> { probe_controller }, args: [nil] },
    { label: "boundary (response_body already set, raise-branch 2)",
      recv: -> { c = probe_controller; c.response_body = "already rendered"; c }, args: ["/foo"] },
    { label: "typical (clean state, full body)", recv: -> { probe_controller }, args: ["/foo"] },
  ],
  [ActionDispatch::Routing::UrlFor, :url_for] => [
    { label: "nil-ish", recv: -> { probe_controller }, args: [nil] },
    { label: "typical", recv: -> { probe_controller }, args: [{ controller: "notifications", action: "index" }] },
    { label: "boundary (string)", recv: -> { probe_controller }, args: ["/already/a/path"] },
  ],
  [DeviseController, :assert_is_devise_resource!] => [
    { label: "nil-ish (devise_mapping falsy -> raise branch)",
      recv: -> { c = probe_devise_controller(RegistrationsController); c.define_singleton_method(:devise_mapping) { nil }; c },
      args: [] },
    { label: "typical (devise_mapping truthy -> no raise)",
      recv: -> { c = probe_devise_controller(RegistrationsController); c.define_singleton_method(:devise_mapping) { :stub_mapping }; c },
      args: [] },
  ],
  [ActiveRecord::Associations::SingularAssociation, :writer] => [
    { label: "nil-ish (unset)", recv: -> { Comment.new.association(:author) }, args: [nil] },
    { label: "typical (new record)", recv: -> { Comment.new.association(:author) }, args: -> { [Person.new] } },
    { label: "boundary (same assoc replace-with-nil-again)", recv: -> { Comment.new.association(:author) }, args: [nil] },
  ],
  [ActiveRecord::Associations::SingularAssociation, :find_target] => [
    { label: "typical (unsaved owner, belongs_to)", recv: -> { Comment.new.association(:author) }, args: [] },
  ],
  [ActiveRecord::Associations::BelongsToPolymorphicAssociation, :find_target] => [
    { label: "typical (unsaved owner, polymorphic belongs_to, target_type set)",
      recv: -> { n = Notification.new; n.target_type = "Post"; n.association(:target) }, args: [] },
  ],
  [ActionController::Rendering, :_set_rendered_content_type] => [
    { label: "nil-ish (format nil)", recv: -> { probe_controller }, args: [nil] },
    { label: "typical (content_type unset)", recv: -> { probe_controller }, args: [Mime::Type.lookup("text/html")] },
    { label: "boundary (content_type already set)",
      recv: -> { c = probe_controller; c.response.content_type = "text/plain"; c },
      args: [Mime::Type.lookup("text/html")] },
  ],
  [DeviseController, :devise_mapping] => [
    { label: "nil-ish (env empty)", recv: -> { probe_devise_controller(RegistrationsController) }, args: [] },
    { label: "typical (env has mapping)", recv: -> { c = probe_devise_controller(RegistrationsController); c.request.env["devise.mapping"] = :user; c }, args: [] },
    { label: "boundary (memoized already set)", recv: -> { c = probe_devise_controller(RegistrationsController); c.instance_variable_set(:@devise_mapping, :already); c }, args: [] },
  ],
  [ActiveRecord::Base, :to_param] => [
    { label: "nil-ish (id nil)", recv: -> { p = Person.new; p.define_singleton_method(:id) { nil }; p }, args: [] },
    { label: "typical (id=5)", recv: -> { p = Person.new; p.define_singleton_method(:id) { 5 }; p }, args: [] },
    { label: "boundary (id=0)", recv: -> { p = Person.new; p.define_singleton_method(:id) { 0 }; p }, args: [] },
  ],
  [ActionController::Instrumentation, :redirect_to] => [
    { label: "typical", recv: -> { probe_controller }, args: ["/foo"] },
  ],
  [ActionController::Head, :head] => [
    { label: "nil-ish", recv: -> { probe_controller }, args: [nil] },
    { label: "typical (symbol)", recv: -> { probe_controller }, args: [:not_found] },
    { label: "boundary (integer)", recv: -> { probe_controller }, args: [204] },
  ],
  [ActiveRecord::FinderMethods, :find_by] => [
    { label: "typical (concrete id)", recv: -> { Person.where("1=1") }, args: [{ id: 999_999_999 }] },
  ],
  [ActiveRecord::Calculations, :count] => [
    { label: "typical", recv: -> { Person.where("1=1") }, args: [] },
  ],
  [ActiveRecord::Relation, :update_all] => [
    { label: "typical (0-row scope, still issues SQL)", recv: -> { Person.where("1=0") }, args: [{ updated_at: Time.now }] },
  ],
  [ActiveRecord::Querying, :find_by_sql] => [
    { label: "typical (literal SQL)", recv: -> { Person }, args: ["SELECT 1 AS one WHERE 1=0"] },
  ],
  [User, :blocks] => [
    { label: "typical (persisted-shaped receiver)", recv: -> { u = User.new; u.define_singleton_method(:id) { 999_999_999 }; u.define_singleton_method(:new_record?) { false }; u }, args: [] },
  ],
  [ActiveRecord::Calculations, :pluck] => [
    { label: "typical", recv: -> { Person.where("1=1") }, args: [:id] },
  ],
}

# ---------------------------------------------------------------------------
# 6. Run the probes.
# ---------------------------------------------------------------------------
results = []

CANDIDATES.each do |klass, meth, tag|
  key = [klass, meth]
  original = ORIGINALS[key]
  entry = { klass: klass.name, method: meth.to_s, tag: tag.to_s }

  if original.is_a?(Exception)
    entry[:verdict] = "INSTRUMENTATION-FAILED"
    entry[:error] = "#{original.class}: #{original.message}"
    results << entry
    next
  end

  loc = original.source_location
  entry[:source_location] = loc
  fixtures = FIXTURES[key] || []
  if fixtures.empty?
    entry[:verdict] = "NOT-PROBED"
    entry[:note] = "no fixture matrix authored for this method"
    results << entry
    next
  end

  sline = eline = nil
  body_text = nil
  if loc
    file, sl = loc
    begin
      lines = File.readlines(file)
      el = find_end_line(lines, sl - 1)
      sline, eline = sl, el + 1
      body_text = lines[(sl - 1)..el].join
    rescue StandardError => e
      entry[:range_error] = "#{e.class}: #{e.message}"
    end
  end

  before_cov = (loc && sline) ? cov_slice(loc[0], sline, eline) : nil

  fixture_results = []
  total_target_calls = []
  any_conn_touch = false

  fixtures.each do |fx|
    $conn_touch_log.clear
    exc = nil
    call_args = nil
    before_calls = $interceptor.instance_variable_get(:@all_calls).length
    ActiveRecord::Base.transaction(requires_new: true) do
      begin
        recv = fx[:recv].call
        # Snapshot AFTER receiver construction -- some fixtures (e.g. a bare
        # Person.new/Comment.new) trigger unrelated after_initialize-style
        # target calls of their OWN (diaspora model callbacks), which must
        # not be misattributed to the probed method's own body.
        before_calls = $interceptor.instance_variable_get(:@all_calls).length
        call_args = fx[:args].respond_to?(:call) ? fx[:args].call : fx[:args]
        original.bind(recv).call(*call_args)
      rescue ConcolicLeafProbeViolation => e
        exc = { class: "ConcolicLeafProbeViolation", message: e.message }
      rescue StandardError, ScriptError => e
        exc = { class: e.class.name, message: e.message.to_s[0, 300] }
      ensure
        raise ActiveRecord::Rollback
      end
    end
    after_calls = $interceptor.instance_variable_get(:@all_calls)
    delta = after_calls[before_calls..-1] || []
    delta_names = delta.map(&:target_name)
    total_target_calls.concat(delta_names)
    conn_touched = !$conn_touch_log.empty?
    any_conn_touch ||= conn_touched
    # Post-hoc classification: distinguish ActiveRecord's OWN schema/
    # metadata introspection SQL (PRAGMA table_info, sqlite_master
    # listings -- fires once per process/table regardless of which method
    # is being probed, an artifact of lazy schema-cache loading that
    # survives even after an explicit warm-up call, empirically -- see
    # _t1_probe_run5..8.log) from genuine APPLICATION data SQL (SELECT/
    # INSERT/UPDATE/DELETE against app tables the probed method's own body
    # issues). Both are recorded; only the latter drives the strict
    # admissibility verdict.
    app_data_touched = $conn_touch_log.any? { |c| !(c[:sql].to_s =~ METADATA_SQL_RE) }
    fixture_results << {
      label: fx[:label],
      args: (call_args || []).map { |a| a.inspect[0, 80] },
      exception: exc,
      target_calls: delta_names,
      connection_touch: conn_touched,
      connection_touch_detail: $conn_touch_log.dup,
      application_data_touch: app_data_touched,
    }
  end

  after_cov = (loc && sline) ? cov_slice(loc[0], sline, eline) : nil

  entry[:body_lines_range] = [sline, eline] if sline
  entry[:body_text] = body_text
  entry[:fixtures] = fixture_results
  entry[:target_calls_total] = total_target_calls.uniq
  entry[:connection_touch_any] = any_conn_touch
  entry[:application_data_touch_any] = fixture_results.any? { |f| f[:application_data_touch] }

  if before_cov && after_cov
    executable = after_cov.compact.length
    covered = after_cov.each_index.count { |i| after_cov[i] && after_cov[i] > 0 }
    entry[:body_lines] = executable
    entry[:covered_lines] = covered
    entry[:coverage_pct] = executable.zero? ? nil : (100.0 * covered / executable).round(1)
    uncovered_idx = after_cov.each_index.select { |i| after_cov[i] == 0 }
    entry[:uncovered_line_numbers] = uncovered_idx.map { |i| sline + i }
  else
    entry[:coverage_pct] = nil
    entry[:coverage_note] = "coverage unavailable (no source_location range)"
  end

  app_touch = entry[:application_data_touch_any]
  strict_pass = total_target_calls.empty? && !app_touch
  full_cov = entry[:coverage_pct].nil? || entry[:coverage_pct] >= 100.0

  if INFORMATIONAL[key]
    # Design-mock (#1-#11 query-boundary) spot check: EXEMPT from removal
    # regardless of outcome. Expected/correct result is "reaches SQL" --
    # that confirms the boundary is real, not vestigial. No coverage gate.
    entry[:verdict] =
      if app_touch || !total_target_calls.empty?
        "INFO-SQL-BOUNDARY-CONFIRMED (target_calls=#{total_target_calls.uniq.inspect} app_data_touch=#{app_touch})"
      else
        "INFO-UNEXPECTED-NO-SQL (design mock's real body reached neither app SQL nor another target -- worth a second look)"
      end
  else
    entry[:verdict] =
      if !strict_pass
        "FAIL (target_calls=#{total_target_calls.uniq.inspect} app_data_touch=#{app_touch} raw_conn_touch=#{any_conn_touch})"
      elsif !full_cov
        "FAIL-COVERAGE (#{entry[:coverage_pct]}% of body lines)"
      else
        "PASS"
      end
  end

  results << entry
end

File.write(
  "/home/dev/project/reports/diaspora/results3/_experiment/variant_b/LEAF_PROBES.json",
  JSON.pretty_generate(results)
)

results.each do |r|
  warn "[t1] #{r[:klass]}##{r[:method]} (#{r[:tag]}): #{r[:verdict]}"
end
warn "[t1_leaf_probe] wrote LEAF_PROBES.json (#{results.length} entries)"
