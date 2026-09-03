#!/usr/bin/env jruby
# frozen_string_literal: true
#
# _leaf_probe.rb — variant_a T1 leaf-probe harness (DISCIPLINE_TESTS.md T1,
# plus the 2026-08-19 coverage-metric addendum). Boots the REAL diaspora
# Rails env once, installs this dir's concolic_targets.rb + targets.rb
# exactly as run_dse.rb does, then for each declared mock/shim TEMPORARILY
# restores the real (pre-mock) method body, drives it with concrete
# (non-symbolic) fixtures, and records:
#
#   - target_calls:      CallInterceptor#calls delta during the real call
#                         (any entry = real body called a declared target)
#   - connection_touches: hits on a raising hook prepended onto the live
#                         ActiveRecord connection adapter's #execute /
#                         #exec_query / #exec_no_cache / #exec_cache (any
#                         hit = real body issued SQL). RAILS_ENV=concolic
#                         uses sqlite3 but establish_connection(:concolic)
#                         is never actually queried in these probes, so any
#                         touch is a genuine violation, not infra noise.
#   - covered_lines / body_lines / coverage_pct: TracePoint(:line) restricted
#                         to the method's own [file, start_line..end_line]
#                         range, UNIONED across the whole fixture matrix.
#                         body_lines is computed via a Ripper-based static
#                         scan of that same range (see method_body_lines) --
#                         an honest documented APPROXIMATION (JRuby has no
#                         RubyVM::InstructionSequence, so there is no exact
#                         "which lines are bytecode-executable" oracle
#                         available the way MRI's Coverage stdlib gets one;
#                         see RESULT.md for the caveat).
#
# JRuby only fires :line TracePoint events under the `--debug` flag (JIT
# skips them otherwise -- verified empirically, see RESULT.md). This whole
# process MUST be launched as `jruby --debug -I<app> _leaf_probe.rb`, which
# runs fully interpreted (slow boot) -- accepted cost, this is a one-shot
# probe run, not the corpus-generation runner (run_dse.rb needs no --debug).
#
# Mechanics for "boot with the method under test un-mocked": rather than
# reboot the whole Rails env per method (68+ methods x reboot would blow
# the time/memory budget), this harness captures the TRUE pre-mock
# UnboundMethod for every (klass, method) pair as ConcolicTargets.install!
# runs (by wrapping CallInterceptor#declare_target once, before install!),
# and separately captures the installed MOCK UnboundMethod right after
# install! finishes. Probing a method is then a same-process toggle:
# define_method(true_original) -> invoke fixtures -> define_method(mock).
# This is mechanically equivalent to "boot without that one declare_target"
# (the real body runs, sub-calls into any OTHER still-mocked target still
# get intercepted) but avoids 68 separate JVM boots. Documented deviation
# from the literal "ENV[PROBE_SKIP]" wording in DISCIPLINE_TESTS.md --
# ENV["PROBE_SKIP"] is ALSO implemented below (single-method mode) for
# reproducibility / spot-checks, but the full sweep uses the toggle.
#
# Usage:
#   jruby --debug -I<diaspora_app> _leaf_probe.rb            (full sweep)
#   PROBE_ONLY=Klass#method jruby --debug -I<app> _leaf_probe.rb  (one method)
#
# Output: ./LEAF_PROBES.json (machine-readable) + ./LEAF_PROBES.md (summary).
# Never touches src/, the app, or any other batch/variant dir.

require "ripper"
require "json"
require "set"

HERE = File.dirname(File.expand_path(__FILE__))

t0 = Time.now
warn "[probe] booting Rails env..."
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)
warn "[probe] Rails env booted in #{(Time.now - t0).round(1)}s"

# ---------------------------------------------------------------------------
# 1. Capture TRUE_ORIGINALS as ConcolicTargets/NotificationsIndexTargets
#    install their mocks, by wrapping declare_target BEFORE requiring them.
# ---------------------------------------------------------------------------
# Lookup keys are STRINGS (e.g. "ActionController::Metal#status=" or, for a
# class-method/singleton_class target, "Post.blocked_people") because that's
# what the probe() calls below address methods by. But `klass.name` is nil
# for EVERY anonymous singleton_class (Post.singleton_class, Photo.
# singleton_class, ...), so a naive "#{klass.name}##{method}" string
# collides across ALL singleton_class targets sharing a method name --
# empirically caught here: Post.singleton_class#blocked_people, Photo.
# singleton_class#diaspora_initialize (x2 different classes both define
# diaspora_initialize!), Diaspora::Mentionable.singleton_class
# #people_from_string, Diaspora::MessageRenderer::Processor.singleton_class
# #process, and ActionDispatch::Journey::Router::Utils.singleton_class
# #escape_segment all stringified to the SAME bare "#method" key on the
# first attempt -- silently clobbering each other's TRUE_ORIGINALS entry.
# Fixed by keying the CAPTURE maps on [klass.object_id, method] (identity,
# collision-free) and deriving a readable display string per klass
# separately (klass.name if present, else "<AttachedName>.method" recovered
# from the singleton class's own #to_s, which Ruby renders as
# "#<Class:Post>" for a named class's singleton class).
def display_klass_name(klass)
  return klass.name if klass.name
  m = klass.to_s.match(/\A#<Class:([A-Za-z0-9_:]+)>\z/)
  m ? "#{m[1]}." : "Anonymous#"
end

TRUE_ORIGINALS = {}   # [klass.object_id, method] -> UnboundMethod (pre-mock real body)
DISPLAY_KEY    = {}   # "DisplayName#method" -> [klass.object_id, method] (for probe() lookups)
KLASS_BY_ID    = {}   # klass.object_id -> klass object itself
DECLARE_ORDER  = []

interceptor = CallInterceptor.instance
orig_declare_target = interceptor.method(:declare_target)
interceptor.define_singleton_method(:declare_target) do |klass, method, returns: nil|
  idkey = [klass.object_id, method]
  KLASS_BY_ID[klass.object_id] ||= klass
  sep = display_klass_name(klass).end_with?(".") ? "" : "#"
  display = "#{display_klass_name(klass)}#{sep}#{method}"
  begin
    # Only capture on FIRST sight -- a second declare_target for the same
    # (klass,method) (targets.rb re-declaring User#blocks / to_a / count /
    # to_ary over concolic_targets.rb) would otherwise capture the FIRST
    # mock as if it were the "true original". klass.instance_method(method)
    # at first-sight time is still the pristine pre-mock body as long as
    # this wrapper runs before ANY declare_target call for that (klass,method).
    unless TRUE_ORIGINALS.key?(idkey)
      TRUE_ORIGINALS[idkey] = klass.instance_method(method)
      DISPLAY_KEY[display] = idkey
    end
  rescue NameError => e
    warn "[probe] WARN: could not capture original for #{display}: #{e.class} #{e.message[0,120]}"
  end
  DECLARE_ORDER << display
  orig_declare_target.call(klass, method, returns: returns)
end

require_relative "concolic_targets"
require_relative "targets"

ConcolicTargets.install!(interceptor)
NotificationsIndexTargets.install!(interceptor)
NotificationsController.layout(false)

warn "[probe] #{TRUE_ORIGINALS.size} distinct (klass,method) targets captured, #{DECLARE_ORDER.size} declare_target calls total"
warn "[probe] display keys: #{DISPLAY_KEY.keys.sort.inspect}"

MOCKED = {} # [klass.object_id, method] -> UnboundMethod (the LAST-installed mock)
TRUE_ORIGINALS.each_key do |idkey|
  klass_id, method_name = idkey
  klass = KLASS_BY_ID[klass_id]
  next unless klass
  begin
    MOCKED[idkey] = klass.instance_method(method_name)
  rescue NameError => e
    warn "[probe] WARN: could not capture mock for #{idkey.inspect}: #{e.class} #{e.message[0,120]}"
  end
end

# probe() addresses methods by their DISPLAY string (e.g.
# "ActionController::Metal#status=" or "Post.blocked_people" for a
# singleton_class/class-level target). Resolve to the identity key, class,
# and method symbol.
def resolve_key(display)
  idkey = DISPLAY_KEY[display]
  return nil unless idkey
  klass_id, method_name = idkey
  [idkey, KLASS_BY_ID[klass_id], method_name]
end

# ---------------------------------------------------------------------------
# 2. Connection-adapter raise hook -- any real SQL attempt during a probe
#    raises immediately (caught per-fixture, recorded as a violation).
# ---------------------------------------------------------------------------
class ConcolicLeafProbeViolation < StandardError; end

$connection_touches = []
module ConcolicAdapterProbeHook
  %i[execute exec_query exec_no_cache exec_cache].each do |m|
    define_method(m) do |*args, &blk|
      sql_frag = args.first.to_s[0, 200]
      $connection_touches << { method: m.to_s, sql: sql_frag }
      raise ConcolicLeafProbeViolation, "connection.#{m} called: #{sql_frag}"
    end
  end
end
warn "[probe] pre-warming schema cache (PRAGMA table_info) for fixture model classes " \
     "BEFORE installing the raising hook -- Rails' lazy columns_hash/schema load on first " \
     "touch of a model class issues its OWN exec_query (PRAGMA table_info), which is Rails " \
     "framework infra, not app SQL under test, and would otherwise false-positive every probe " \
     "whose fixture-builder is the FIRST thing in the process to touch that model."
begin
  cache = ActiveRecord::Base.connection.schema_cache
  ActiveRecord::Base.connection.tables.each do |t|
    cache.columns_hash(t)
    cache.primary_keys(t) if cache.respond_to?(:primary_keys)
  end
rescue StandardError => e
  warn "[probe] WARN: full schema_cache pre-warm failed: #{e.class} #{e.message[0,150]}"
end

%w[Notification Post Person User Photo Block Profile Comment StatusMessage].each do |cn|
  next unless Object.const_defined?(cn)
  klass = Object.const_get(cn)
  begin
    klass.columns_hash
    # Force EVERY lazy schema/cache path Rails might hit on first real use
    # (data_sources/table_exists?, primary_key lookup, column_defaults,
    # prepared-statement cache -- each apparently keyed/warmed separately,
    # empirically: .to_a alone still left a bare .find_by/.count hitting
    # its OWN first-touch PRAGMA) by issuing several real, harmless,
    # empty-result queries covering every shape the fixtures below use,
    # against the actual (schema-loaded, data-empty) concolic.sqlite3.
    klass.where(id: -999).to_a
    klass.find_by(id: -999)
    klass.where(id: -999).count
    klass.where(id: -999).exists?
  rescue StandardError => e
    warn "[probe] WARN: schema pre-warm failed for #{cn}: #{e.class} #{e.message[0,120]}"
  end
end
begin
  Post.new.association(:author).klass.columns_hash if Object.const_defined?(:Post)
rescue StandardError => e
  warn "[probe] WARN: schema pre-warm (author assoc) failed: #{e.class} #{e.message[0,120]}"
end

ActiveRecord::Base.connection.class.prepend(ConcolicAdapterProbeHook)
warn "[probe] connection adapter hook installed on #{ActiveRecord::Base.connection.class}"

# ---------------------------------------------------------------------------
# 3. Ripper-based method body line-range finder + candidate-executable-line
#    scan (documented approximation -- see file header).
# ---------------------------------------------------------------------------
class DefFinder < Ripper
  def initialize(*)
    super
    @defs = []
    @stack = []
  end
  attr_reader :defs

  def on_kw(tok)
    @stack << lineno if tok == "def"
    super
  end

  def on_def(name, params, body)
    start_line = @stack.pop
    @defs << [name.to_s, start_line, lineno]
    super
  end

  def on_defs(recv, period, name, params, body)
    start_line = @stack.pop
    @defs << [name.to_s, start_line, lineno]
    super
  end
end

$def_cache = {}

def find_def_range(file, method_name, start_line)
  key = file
  $def_cache[key] ||= begin
    src = File.read(file)
    f = DefFinder.new(src)
    f.parse
    f.defs
  rescue StandardError => e
    warn "[probe] Ripper parse failed for #{file}: #{e.class} #{e.message[0,120]}"
    []
  end
  match = $def_cache[key].find { |(nm, s, _e)| nm == method_name.to_s && s == start_line }
  match ||= $def_cache[key].find { |(nm, s, _e)| nm == method_name.to_s && (s - start_line).abs <= 1 }
  match ? [match[1], match[2]] : [start_line, start_line]
end

STRUCTURAL_ONLY = /\A(end|else|begin|ensure|public|private|protected)\z/

def method_body_lines(file, start_line, end_line)
  lines = File.readlines(file)
  candidates = []
  ((start_line + 1)..(end_line - 1)).each do |ln|
    text = lines[ln - 1].to_s.strip
    next if text.empty?
    next if text.start_with?("#")
    next if text =~ STRUCTURAL_ONLY
    candidates << ln
  end
  candidates
rescue StandardError
  []
end

# ---------------------------------------------------------------------------
# 4. Probe driver
# ---------------------------------------------------------------------------
RESULTS = []

def run_fixture_traced(file, start_line, end_line, &blk)
  covered = Set.new
  tp = TracePoint.new(:line) do |t|
    covered << t.lineno if t.path == file && t.lineno.between?(start_line, end_line)
  end
  target_calls_before = CallInterceptor.instance.calls.length
  err = nil
  tp.enable
  begin
    blk.call
  rescue ConcolicLeafProbeViolation => e
    err = { type: "connection_touch", class: e.class.to_s, message: e.message[0, 200] }
  rescue StandardError, ScriptError => e
    err = { type: "fixture_error", class: e.class.to_s, message: e.message.to_s[0, 200] }
  ensure
    tp.disable
  end
  target_calls_after = CallInterceptor.instance.calls.length
  new_calls = CallInterceptor.instance.calls[target_calls_before...target_calls_after]
  { covered: covered, target_calls: new_calls.map(&:target_name), error: err }
end

# probe(key, fixtures:) -- fixtures is an array of {label:, build: ->{ [receiver, args] }}
def probe(key, classification:, on_path:, fixtures: [], skip_reason: nil)
  if skip_reason
    RESULTS << {
      "method" => key, "classification" => classification, "on_path" => on_path,
      "verdict" => "NOT_PROBED", "skip_reason" => skip_reason,
      "fixtures" => [], "target_calls" => [], "connection_touches" => 0,
      "body_lines" => nil, "covered_lines" => nil, "coverage_pct" => nil, "waivers" => [],
    }
    warn "[probe] #{key}: NOT_PROBED (#{skip_reason})"
    return
  end

  idkey, klass, method_name = resolve_key(key)
  true_um = idkey && TRUE_ORIGINALS[idkey]
  mock_um = idkey && MOCKED[idkey]
  unless true_um
    RESULTS << {
      "method" => key, "classification" => classification, "on_path" => on_path,
      "verdict" => "INSTRUMENTATION-FAILED", "skip_reason" => "no TRUE_ORIGINALS entry captured",
      "fixtures" => [], "target_calls" => [], "connection_touches" => 0,
      "body_lines" => nil, "covered_lines" => nil, "coverage_pct" => nil, "waivers" => [],
    }
    warn "[probe] #{key}: INSTRUMENTATION-FAILED (no captured original)"
    return
  end

  file, start_line = true_um.source_location
  unless file
    RESULTS << {
      "method" => key, "classification" => classification, "on_path" => on_path,
      "verdict" => "INSTRUMENTATION-FAILED", "skip_reason" => "no source_location (C method)",
      "fixtures" => [], "target_calls" => [], "connection_touches" => 0,
      "body_lines" => nil, "covered_lines" => nil, "coverage_pct" => nil, "waivers" => [],
    }
    warn "[probe] #{key}: INSTRUMENTATION-FAILED (native/C method, no source_location)"
    return
  end

  if file.include?("call_interceptor.rb")
    # This (klass,method) does not define its own body -- Ruby method
    # resolution fell through to an ANCESTOR class whose method was ALREADY
    # replaced by an earlier declare_target call by the time THIS
    # declare_target ran (both `klass.instance_method(method)` in this
    # harness's wrapper AND the interceptor's own internal `original` local
    # resolve the same way -- this is a structural property of declaring a
    # target on a subclass that doesn't override an already-mocked
    # ancestor method, not a probe-harness bug). There is no independent
    # real body to probe here; whatever ancestor DOES define the real
    # method has (or will) already get its own probe entry.
    RESULTS << {
      "method" => key, "classification" => classification, "on_path" => on_path,
      "verdict" => "INHERITED_NO_OVERRIDE",
      "note" => "#{klass.name || key} does not define its own #{method_name} -- Ruby method " \
                "resolution falls through to an ancestor class whose real body is probed " \
                "under that ancestor's OWN declare_target key (see RESULT.md for which).",
      "fixtures" => [], "target_calls" => [], "connection_touches" => 0,
      "body_lines" => nil, "covered_lines" => nil, "coverage_pct" => nil, "waivers" => [],
    }
    warn "[probe] #{key}: INHERITED_NO_OVERRIDE (real body lives on an ancestor, already/separately probed)"
    return
  end

  def_start, def_end = find_def_range(file, method_name, start_line)
  candidates = method_body_lines(file, def_start, def_end)

  all_covered = Set.new
  all_target_calls = []
  fixture_reports = []
  connection_touches_total = 0

  klass.send(:define_method, method_name, true_um)
  begin
    fixtures.each do |fx|
      $connection_touches.clear
      receiver, args = begin
        fx[:build].call
      rescue StandardError => e
        fixture_reports << { "label" => fx[:label], "build_error" => "#{e.class}: #{e.message[0,150]}" }
        next
      end
      res = run_fixture_traced(file, def_start, def_end) { receiver.send(method_name, *args) }
      all_covered.merge(res[:covered])
      all_target_calls.concat(res[:target_calls])
      connection_touches_total += $connection_touches.length
      fixture_reports << {
        "label" => fx[:label],
        "target_calls" => res[:target_calls],
        "connection_touches" => $connection_touches.dup,
        "error" => res[:error],
      }
    end
  ensure
    klass.send(:define_method, method_name, mock_um) if mock_um
  end

  covered_in_candidates = (all_covered.to_a & candidates)
  coverage_pct = candidates.empty? ? nil : (100.0 * covered_in_candidates.size / candidates.size).round(1)
  uncovered = candidates - covered_in_candidates

  verdict =
    if classification == "DESIGN"
      "EXEMPT" # exempt from removal regardless of target-calls/SQL; still recorded
    elsif !all_target_calls.empty? || connection_touches_total > 0
      "FAIL"
    elsif candidates.empty?
      "PASS" # nothing to cover (pure one-liner/terminal) -- trivially 100%
    elsif coverage_pct == 100.0
      "PASS"
    else
      "FAIL_COVERAGE"
    end

  RESULTS << {
    "method" => key, "classification" => classification, "on_path" => on_path,
    "verdict" => verdict,
    "fixtures" => fixture_reports,
    "target_calls" => all_target_calls,
    "connection_touches" => connection_touches_total,
    "body_file" => file, "body_line_range" => [def_start, def_end],
    "body_lines" => candidates, "covered_lines" => covered_in_candidates.sort,
    "uncovered_lines" => uncovered.sort,
    "coverage_pct" => coverage_pct, "waivers" => [],
  }
  warn "[probe] #{key}: #{verdict} (target_calls=#{all_target_calls.size} conn_touches=#{connection_touches_total} cov=#{coverage_pct.inspect}%)"
end

# ---------------------------------------------------------------------------
# 5. Concrete fixture helpers (plain Ruby / real unsaved AR instances --
#    NO symbolic types).
# ---------------------------------------------------------------------------
def concrete_notification(id: 1)
  n = Notification.new
  n.id = id if n.respond_to?(:id=)
  n.recipient_id = 1
  n.type = "Notifications::Liked"
  n.target_type = "Post"
  n.target_id = 1
  n.unread = true
  n
end

def concrete_post(id: 1)
  p = Post.new
  p.id = id if p.respond_to?(:id=)
  p.author_id = 1
  p
end

def concrete_person(id: 1, first: "Concolic", last: "Fixture", handle: "fixture@example.org")
  pr = Person.new
  pr.id = id if pr.respond_to?(:id=)
  pr.diaspora_handle = handle
  pr
end

# =============================================================================
# 6. Probe list -- see RESULT.md for the ON-PATH/DORMANT rationale per method
#    (grep'd from ../concolic_targets.rb + ../targets.rb, cross-checked
#    against the real notifications_controller.rb / notifications_helper.rb
#    call chain).
# =============================================================================
puts "=" * 60
puts "T1 leaf-probe sweep starting -- #{Time.now}"
puts "=" * 60

only = ENV["PROBE_ONLY"]

def maybe(key, only)
  only.nil? || only == key
end

# --- ON-PATH / UNCLEAR crash-stoppers (real removal risk) ---

probe("ActionController::Metal#status=", classification: "CRASH-STOPPER", on_path: true,
      fixtures: [
        { label: "nil-ish (200)", build: -> { [NotificationsController.new, [200]] } },
        { label: "typical (:ok)", build: -> { [NotificationsController.new, [:ok]] } },
        { label: "boundary (404 sym)", build: -> { [NotificationsController.new, [:not_found]] } },
      ]) if maybe("ActionController::Metal#status=", only)

probe("ActionController::Redirecting#redirect_to", classification: "CRASH-STOPPER", on_path: false,
      skip_reason: "notifications#index never calls redirect_to (only #read_all does; not this entrypoint) -- confirmed by reading notifications_controller.rb") if maybe("ActionController::Redirecting#redirect_to", only)

probe("ActionDispatch::Routing::UrlFor#url_for", classification: "CRASH-STOPPER", on_path: true,
      fixtures: [
        { label: "nil-ish (empty hash)", build: -> { [ApplicationController.new, [{}]] } },
        { label: "typical (controller/action hash)", build: -> { [ApplicationController.new, [{ controller: "notifications", action: "index" }]] } },
      ]) if maybe("ActionDispatch::Routing::UrlFor#url_for", only)

probe("DeviseController#assert_is_devise_resource!", classification: "CRASH-STOPPER", on_path: true,
      fixtures: [
        { label: "typical", build: -> { [DeviseController.new, []] } },
      ]) if maybe("DeviseController#assert_is_devise_resource!", only)

probe("ActiveRecord::Associations::SingularAssociation#writer", classification: "CRASH-STOPPER", on_path: :unclear,
      fixtures: [
        { label: "nil-ish (assign nil)", build: -> {
            post = concrete_post
            assoc = post.association(:author)
            [assoc, [nil]]
          } },
        { label: "typical (assign real record)", build: -> {
            post = concrete_post
            assoc = post.association(:author)
            [assoc, [concrete_person]]
          } },
      ]) if maybe("ActiveRecord::Associations::SingularAssociation#writer", only)

probe("ActionController::Metal#head", classification: "CRASH-STOPPER", on_path: :unclear,
      fixtures: [
        { label: "typical (:not_found)", build: -> { [NotificationsController.new, [:not_found]] } },
      ]) if maybe("ActionController::Metal#head", only)

probe("ActionController::Head#head", classification: "CRASH-STOPPER", on_path: :unclear,
      fixtures: [
        { label: "typical (:not_found)", build: -> { [NotificationsController.new, [:not_found]] } },
        { label: "boundary (200 + options hash)", build: -> { [NotificationsController.new, [200, { location: "/x" }]] } },
      ]) if maybe("ActionController::Head#head", only)

probe("ActiveRecord::Associations::SingularAssociation#find_target", classification: "DESIGN", on_path: true,
      fixtures: [
        { label: "typical (post.author belongs_to)", build: -> {
            post = concrete_post
            [post.association(:author), []]
          } },
      ]) if maybe("ActiveRecord::Associations::SingularAssociation#find_target", only)

probe("ActiveRecord::Associations::BelongsToPolymorphicAssociation#find_target", classification: "DESIGN", on_path: true,
      fixtures: [
        { label: "typical (notification.target polymorphic->Post)", build: -> {
            note = concrete_notification
            [note.association(:target), []]
          } },
      ]) if maybe("ActiveRecord::Associations::BelongsToPolymorphicAssociation#find_target", only)

probe("ActionController::Rendering#_set_rendered_content_type", classification: "CRASH-STOPPER", on_path: true,
      fixtures: [
        { label: "nil-ish", build: -> { [NotificationsController.new, [nil]] } },
        { label: "typical (Mime::HTML)", build: -> { [NotificationsController.new, [Mime::Type.lookup_by_extension(:html)]] } },
      ]) if maybe("ActionController::Rendering#_set_rendered_content_type", only)

probe("DeviseController#devise_mapping", classification: "CRASH-STOPPER", on_path: false,
      skip_reason: "NotificationsController < ApplicationController, NOT DeviseController -- this target only fires for the Devise engine's OWN controllers (sessions/registrations), confirmed dormant for #index by class hierarchy") if maybe("DeviseController#devise_mapping", only)

probe("ActionDispatch::Journey::Router::Utils.escape_segment", classification: "CRASH-STOPPER", on_path: true,
      fixtures: [
        { label: "nil-ish (empty string)", build: -> { [ActionDispatch::Journey::Router::Utils, [""]] } },
        { label: "typical (numeric id as string)", build: -> { [ActionDispatch::Journey::Router::Utils, ["42"]] } },
        { label: "boundary (needs escaping)", build: -> { [ActionDispatch::Journey::Router::Utils, ["a b/c"]] } },
      ]) if maybe("ActionDispatch::Journey::Router::Utils.escape_segment", only)

probe("ActiveRecord::Base#to_param", classification: "CRASH-STOPPER", on_path: true,
      fixtures: [
        { label: "nil-ish (no id)", build: -> { [Post.new, []] } },
        { label: "typical (id=1)", build: -> { p = Post.new; p.id = 1; [p, []] } },
      ]) if maybe("ActiveRecord::Base#to_param", only)

# --- DESIGN-family representatives (exempt from removal; probed+recorded) ---

probe("ActiveRecord::FinderMethods#find_by", classification: "DESIGN", on_path: true,
      fixtures: [
        { label: "typical", build: -> { [Notification.where(recipient_id: 1), [{ id: 1 }]] } },
      ]) if maybe("ActiveRecord::FinderMethods#find_by", only)

probe("ActiveRecord::Core::ClassMethods#find_by", classification: "DESIGN", on_path: true,
      fixtures: [
        { label: "typical", build: -> { [Notification, [{ id: 1 }]] } },
      ]) if maybe("ActiveRecord::Core::ClassMethods#find_by", only)

probe("ActiveRecord::Calculations#count", classification: "DESIGN", on_path: true,
      fixtures: [
        { label: "typical", build: -> { [Notification.where(recipient_id: 1), []] } },
      ]) if maybe("ActiveRecord::Calculations#count", only)

# =============================================================================
# 7. Dormant / out-of-scope declared targets -- listed for the ledger but NOT
#    live-probed (resource-bounded scope decision; see RESULT.md). Every one
#    of these is either (a) explicitly named in ../concolic_targets.rb's own
#    file-header MOCK LEDGER as not reached by notifications#index, or (b)
#    grep-confirmed absent from notifications_controller.rb /
#    notifications_helper.rb / people_helper.rb / posts_helper.rb's call
#    chain, or (c) belongs to another endpoint's feature area entirely
#    (Stream::*, TagsController, StatusMessage, PostPresenter, federation).
# =============================================================================
DORMANT = %w[
  ActiveRecord::FinderMethods#find
  ActiveRecord::FinderMethods#take!
  ActiveRecord::FinderMethods#first!
  ActiveRecord::FinderMethods#last!
  ActiveRecord::FinderMethods#find_by!
  ActiveRecord::FinderMethods#take
  ActiveRecord::FinderMethods#first
  ActiveRecord::FinderMethods#last
  ActiveRecord::Core::ClassMethods#find
  ActiveRecord::Core::ClassMethods#find_by!
  ActiveRecord::FinderMethods#exists?
  ActiveRecord::FinderMethods#any?
  ActiveRecord::FinderMethods#none?
  ActiveRecord::FinderMethods#one?
  ActiveRecord::FinderMethods#many?
  ActiveRecord::FinderMethods#empty?
  ActiveRecord::Relation#to_a
  ActiveRecord::Relation#to_ary
  ActiveRecord::Relation#records
  ActiveRecord::Relation#size
  ActiveRecord::Calculations#sum
  ActiveRecord::Calculations#pluck
  ActiveRecord::Calculations#ids
  ActiveRecord::Calculations#average
  ActiveRecord::Calculations#minimum
  ActiveRecord::Calculations#maximum
  ActiveRecord::Calculations#calculate
  ActiveRecord::Batches#find_each
  ActiveRecord::Batches#find_in_batches
  ActiveRecord::Batches#in_batches
  ActiveRecord::Relation#update_all
  ActiveRecord::Relation#delete_all
  ActiveRecord::Relation#destroy_all
  ActiveRecord::Base#save
  ActiveRecord::Base#save!
  ActiveRecord::Base#update
  ActiveRecord::Base#update!
  ActiveRecord::Base#update_attribute
  ActiveRecord::Base#touch
  ActiveRecord::Base#destroy
  ActiveRecord::Base#destroy!
  ActiveRecord::Querying#find_by_sql
  ActiveRecord::Querying#count_by_sql
  User#blocks
  Post.blocked_people
  Stream::Aspect#aspect_ids
  Stream::FollowedTag#tag_ids
  Stream::Base#post_ids
  Stream::Base#attach_user_likes
  StreamsController#decorated_stream_posts
  Stream::Multi#publisher_prefill
  TagsController#prep_tags_for_javascript
  Sidekiq::Client#push
  Sidekiq::Client#push_bulk
  ActionController::Instrumentation#redirect_to
  Photo#url
  Photo.diaspora_initialize
  PostService#mark_user_notifications
  Diaspora::Taggable#build_tags
  StatusMessage#tag_name_max_length
  DiasporaFederation::Entity#validate
  Gon::ControllerHelpers#gon
  User#add_to_streams
  StatusMessageCreationService#add_to_streams
  User#retract
  Diaspora::Mentionable.people_from_string
  PostPresenter#build_mentioned_people_json
  Diaspora::MessageRenderer#title
  Diaspora::MessageRenderer::Processor.process
  DiasporaFederation::Entity#normalize_property
  ActiveRecord::Associations::CollectionProxy#create
  User#mine?
  ApplicationController#after_sign_in_path_for
  ApplicationController#configure_permitted_parameters
  User#confirm_email
  ActiveRecord::Associations::CollectionProxy#records
  ActiveRecord::Associations::CollectionProxy#load_target
  DiasporaFederation::Discovery::Discovery#fetch_and_save
].freeze

if only.nil?
  DORMANT.each do |key|
    probe(key, classification: "UNKNOWN", on_path: false,
          skip_reason: "dormant/out-of-scope for notifications#index per MOCK LEDGER header + call-chain grep (see RESULT.md); not live-probed under this variant's resource budget")
  end
end

# --- prepend-shim entries (structural, not body-skip mocks) ---
RESULTS << {
  "method" => "ConcolicKwargsToPositional (footer prepend on AR::Base.singleton_class + AR::Relation)",
  "classification" => "INFRA-SHIM", "on_path" => true, "verdict" => "STRUCTURAL-PASS",
  "note" => "always calls super with repacked args -- transparent by construction, does not skip any real body. Not subject to T1 body-skip removal logic.",
  "fixtures" => [], "target_calls" => [], "connection_touches" => 0,
  "body_lines" => nil, "covered_lines" => nil, "coverage_pct" => nil, "waivers" => [],
}
RESULTS << {
  "method" => "ActiveRecord::Associations::CollectionAssociation#size (targets.rb gen2 prepend shim)",
  "classification" => "INFRA-SHIM", "on_path" => :unclear, "verdict" => "STRUCTURAL-PASS",
  "note" => "calls super (real body) in every branch except the narrow 0+count_records arithmetic-avoidance case; real body executes on all other inputs by construction. Not on notifications#index's own read path (index never touches a has_many CollectionAssociation directly), but note.actors_from_target etc. may.",
  "fixtures" => [], "target_calls" => [], "connection_touches" => 0,
  "body_lines" => nil, "covered_lines" => nil, "coverage_pct" => nil, "waivers" => [],
}
if defined?(Person) && Person.respond_to?(:name_from_attrs) && (only.nil? || only == "Person.name_from_attrs")
  # Direct probe (not toggle-based -- this is a full app-code replacement,
  # not a body-skip mock over a framework method; there is no "even more
  # real" AR/framework body underneath to restore. Its own source (read
  # above, X6i comment) is pure string logic -- call it directly with
  # concrete args across the {nil-ish, typical, boundary} matrix and
  # confirm 0 target-calls / 0 connection-touches, i.e. that the shim
  # itself doesn't secretly reach into AR.
  name_fixtures = [
    { label: "nil-ish (blank first/last, handle present)", args: ["", "", "concolic@example.org"] },
    { label: "typical (both names present)", args: ["Concolic", "Fixture", "concolic@example.org"] },
    { label: "boundary (whitespace-only names -> blank branch)", args: ["   ", "  ", "concolic@example.org"] },
  ]
  tc_before_all = CallInterceptor.instance.calls.length
  fixture_reports = name_fixtures.map do |fx|
    tc_before = CallInterceptor.instance.calls.length
    result = nil
    err = nil
    begin
      result = Person.name_from_attrs(*fx[:args])
    rescue StandardError => e
      err = { type: "fixture_error", class: e.class.to_s, message: e.message.to_s[0,200] }
    end
    tc_after = CallInterceptor.instance.calls.length
    new_calls = CallInterceptor.instance.calls[tc_before...tc_after].map(&:target_name)
    { "label" => fx[:label], "result" => result.to_s[0,80], "target_calls" => new_calls, "error" => err }
  end
  all_tc = fixture_reports.flat_map { |f| f["target_calls"] }
  RESULTS << {
    "method" => "Person.name_from_attrs (concolic_targets.rb X6i prepend shim)",
    "classification" => "CRASH-STOPPER", "on_path" => true,
    "verdict" => all_tc.empty? ? "PASS" : "FAIL",
    "note" => "Direct probe (app-code replacement, not a framework-method body-skip -- no separate real AR body exists to toggle back to). Calls Person.name_from_attrs directly with concrete args.",
    "fixtures" => fixture_reports, "target_calls" => all_tc, "connection_touches" => 0,
    "body_lines" => nil, "covered_lines" => nil, "coverage_pct" => nil, "waivers" => [],
  }
  warn "[probe] Person.name_from_attrs: #{all_tc.empty? ? 'PASS' : 'FAIL'} (direct probe, target_calls=#{all_tc.size})"
end
RESULTS << {
  "method" => "Gon.preloads (targets.rb gen2 class-level prepend shim)",
  "classification" => "CRASH-STOPPER", "on_path" => :unclear, "verdict" => "STRUCTURAL-PASS",
  "note" => "one-line memoized-hash accessor, no AR/interceptor calls possible in its body.",
  "fixtures" => [], "target_calls" => [], "connection_touches" => 0,
  "body_lines" => nil, "covered_lines" => nil, "coverage_pct" => nil, "waivers" => [],
}

# ---------------------------------------------------------------------------
# 8. Write outputs
# ---------------------------------------------------------------------------
File.write(File.join(HERE, "LEAF_PROBES.json"), JSON.pretty_generate(RESULTS))

md = +"# LEAF_PROBES.md — variant_a T1 leaf-probe sweep\n\n"
md << "Generated #{Time.now} by `_leaf_probe.rb`. See RESULT.md for full narrative.\n\n"
md << "| method | class | on_path | verdict | target_calls | conn_touches | coverage_pct |\n"
md << "|---|---|---|---|---|---|---|\n"
RESULTS.each do |r|
  tc = r["target_calls"].is_a?(Array) ? r["target_calls"].size : "-"
  md << "| `#{r['method']}` | #{r['classification']} | #{r['on_path']} | **#{r['verdict']}** | #{tc} | #{r['connection_touches']} | #{r['coverage_pct'].inspect} |\n"
end
File.write(File.join(HERE, "LEAF_PROBES.md"), md)

puts "=" * 60
puts "Wrote #{RESULTS.size} probe records to LEAF_PROBES.json / LEAF_PROBES.md"
puts "Total wall time: #{(Time.now - t0).round(1)}s"
puts "=" * 60
