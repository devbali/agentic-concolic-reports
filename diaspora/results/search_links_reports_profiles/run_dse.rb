# frozen_string_literal: true
#
# run_dse.rb — "search_links_reports_profiles" batch, prefix-directed DSE.
#
# WHY THIS REPLACES THE OLD run_concolic.rb COVERAGE LOOP
# -------------------------------------------------------
# The interceptor names symbolic results with a PER-RUN CALL ORDINAL
# (SYM_RESULT_<func>_<idx>, src/ruby_runtime/call_interceptor.rb:140).
# Flipping an early branch changes how many intercepted calls happen before a
# later one, renumbering every later var. So feeding CoverageChecker's
# `concrete_values` (harvested across DIFFERENT runs) back as seed_overrides
# wholesale is unsound — the same name means different queries in different
# runs.
#
# Instead: classic DSE prefix extension. From an observed path [c0..cn], emit
# one child per k that INHERITS the parent's seeds (so the prefix c0..c_{k-1}
# replays identically and those ordinals stay valid) and adds EXACTLY ONE flip
# for c_k. Ordinals are assigned in execution order, so a flip at k can only
# renumber vars AFTER k. Dedup on path signature; expand until the worklist
# drains.
#
# Neither src/ nor the shared concolic_targets.rb is modified. Everything
# below the harness line is runner-local.
#
# Usage (ONE entrypoint per process — see PROCESS ISOLATION below):
#   ENTRYPOINTS=report_update \
#     /home/dev/.claude/jobs/302ac302/tmp/concolic-slot /abs/path/run_dse.rb
#
# Env:
#   MAX_RUNS     per-entrypoint execution cap    (default 400)
#   TIME_BUDGET  per-entrypoint seconds          (default 300)
#   ENTRYPOINTS  comma-separated subset to run   (default all)
#
# PROCESS ISOLATION: links_resolve's not-found branch reaches the real
# federation fetcher, which calls libcurl through FFI and SIGSEGVs the JVM
# (hs_err: `C [libcurl.so.4+0x6e3af] curl_easy_setopt`). A JVM abort takes the
# whole process down, so each entrypoint is driven in its OWN process by
# drive_all.sh; a crash then costs one entrypoint, not the batch.

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "/home/dev/project/reports/diaspora/results/search_links_reports_profiles/targets"
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
# Batch-local overlay (targets.rb). MUST come second: declare_target uses
# define_method, so the later declaration wins.
SearchLinksReportsProfilesTargets.install!($interceptor)

RESULTS     = File.dirname(File.expand_path(__FILE__))
MAX_RUNS    = (ENV["MAX_RUNS"] || 400).to_i
TIME_BUDGET = (ENV["TIME_BUDGET"] || 300).to_i
ONLY        = (ENV["ENTRYPOINTS"] || "").split(",").map(&:strip).reject(&:empty?)

# ---------------------------------------------------------------------------
# Harness (behaviourally the run_concolic.rb harness, with two changes)
#
#  1. The symbolic user is rebuilt PER RUN under the run's seeds. The old
#     runner built it once at load time, freezing every SYM_USER_* var at its
#     default — which made user-attribute branches (profiles#update's
#     `current_user.getting_started?`) permanently unflippable.
#  2. admin?/moderator? are NOT stubbed. The real User#moderator? runs
#     (Role.moderators.exists? -> intercepted -> SymbolicBool), so the
#     authorization query is visible in the dump instead of being modelled
#     away. (The guard itself is still unrecordable — see REPORT.md, Ruby
#     truthiness gap.)
# ---------------------------------------------------------------------------
def symbolic_user(tag, reports_stub: false)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user)")
  person.define_singleton_method(:id) { 1 }
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:id) { 1 }
  user.define_singleton_method(:guid) { "abc123" }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:diaspora_handle) { "alice@example.org" }
  user.define_singleton_method(:language) { "en" }
  user.define_singleton_method(:gender) { "" }
  user.define_singleton_method(:contacts) { Contact.all }
  user.define_singleton_method(:blocks) { Block.all }
  user.define_singleton_method(:aspects) { Aspect.all }
  user.define_singleton_method(:invited_by) { nil }
  # report#create only: `current_user.reports.new(...)` builds through the real
  # has_many, whose belongs_to inverse reads the owner's `id` attribute and
  # type-casts it -> SymbolicInt#to_i -> NotImplementedError before the action
  # body runs. Relation#new off the same model is the SQL-equivalent build
  # without the inverse write. The unmocked wall is preserved as evidence in
  # report_create/wall_evidence_reports_association.json.
  user.define_singleton_method(:reports) { Report.all } if reports_stub
  user
end

class StubWarden
  def initialize(user); @user = user; end
  def authenticate!(*_); @user; end
  def authenticated?(*_); true; end
  def user(*_); @user; end
end

def make_harness(controller_class)
  cname = controller_class.to_s.gsub("::", "__").sub(/Controller\z/, "ControllerTest")
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

# One execution of a REAL controller action under a seed assignment.
#
# sym_params: { "q" => <SymbolicString> } — inject a symbolic value at the
# REAL program input. ActionController::TestCase#process serialises params
# through `to_query` and re-parses them, so a symbolic value can never survive
# into params on its own; without this, an action whose every branch is on a
# request string (search#search) can only ever be vacuous. The override wraps
# the live Parameters object's #[] and leaves every other key — and the whole
# routing / filter / respond_to pipeline — untouched.
def drive(controller_class, action, params, label, seeds,
          signed_in: true, method: "GET", format: nil, reports_stub: false,
          sym_params: nil)
  ConcolicTargets.seed_overrides = seeds
  the_user = signed_in ? symbolic_user("SLR", reports_stub: reports_stub) : nil
  ctrl, tc = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user)    { the_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { !the_user.nil? }
  if sym_params && !sym_params.empty?
    # Values are built LAZILY, by a thunk called on first read inside the
    # action. CallInterceptor#run starts with SymbolicFunc.reset!, which
    # clears registered_vars — a symbolic string constructed before run()
    # would vanish from the dump's symbolic_vars and leave the DSE flip
    # machinery without a witness value for it.
    built = {}
    ctrl.singleton_class.define_method(:params) do
      pp = super()
      unless pp.instance_variable_get(:@__slr_sym_params)
        pp.instance_variable_set(:@__slr_sym_params, true)
        orig_get = pp.method(:[])
        pp.define_singleton_method(:[]) do |k|
          ks = k.to_s
          sym_params.key?(ks) ? (built[ks] ||= sym_params[ks].call) : orig_get.call(k)
        end
      end
      pp
    end
  end
  tc.instance_variable_get(:@request).env["warden"] = StubWarden.new(the_user)
  dump = $interceptor.run(
    -> { tc.process(action, method: method, params: params, format: format); :ok },
    {}, label: label, script: "run_dse.rb"
  )
  # MEMORY: CallInterceptor#@all_calls is never trimmed (it grows for the whole
  # process lifetime, src/ruby_runtime/call_interceptor.rb). `run` only reads
  # @all_calls[old_count..], so clearing it between runs is safe and keeps a
  # few-hundred-run exploration flat in memory. src/ fix belongs to Bali.
  $interceptor.instance_variable_set(:@all_calls, [])
  dump
end

# ---------------------------------------------------------------------------
# DSE machinery (flip_seed copied from the reference runner)
# ---------------------------------------------------------------------------
def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

# Concrete value of every named symbolic var this run produced. Needed by the
# string-theory flips below, which MUTATE the current witness rather than
# invent one from scratch (mutation is what preserves the constraints already
# accumulated on the same variable earlier in the path).
def witness_values(dump)
  vals = {}
  (dump["symbolic_vars"] || []).each { |v| vals[v["name"]] = v["value"] }
  (dump["symbolic_results"] || []).each { |v| vals[v["name"]] = v["value"] }
  vals
end

# Return a length in 0..(n+2) for which `len <=> n` matches `want`, choosing
# the candidate CLOSEST to the current length. "Closest" is not cosmetic: on
# `(Length(q) > 1)` with q = "#ruby", the smallest satisfying length is 0 ("")
# which silently also flips the *unrecorded-until-now* `starts_with?('#')`
# guard and lands in a different arm entirely; the closest is 1 ("#"), which
# keeps the prefix and actually reaches the branch being flipped.
def length_target(op, n, want, cur_len)
  cands = (0..(n + 2)).select { |l| l.send(op, n) == want }
  cands.min_by { |l| [(l - cur_len).abs, l] }
end

def resize_to(str, len)
  str.length > len ? str[0, len] : str + ("x" * (len - str.length))
end

# expr -> a seed dict that drives the next run down the other side, or nil if
# this runner cannot invert the expression (counted in unflippable_pcs).
#
# Three expression shapes occur in this batch; all three come straight out of
# src/ruby_runtime (SymbolicString#==/empty?, #start_with?, #length):
#   (VAR == LIT)          — equality on a scalar var        [reference runner]
#   PrefixOf('p', VAR)    — SymbolicString#start_with?      [this batch]
#   (Length(VAR) op N)    — SymbolicInt over #length        [this batch]
# The latter two only became reachable once targets.rb §4/§5 put a real
# symbolic string in front of search#search.
def flip_seed(expr, want_taken, witness = {})
  e = expr.to_s.strip

  if (m = /\A\(([A-Za-z_][A-Za-z0-9_]*) == (.+)\)\z/m.match(e))
    var, lit = m[1], m[2].strip

    parsed =
      case lit
      when "True"  then true
      when "False" then false
      when /\A'(.*)'\z/m then Regexp.last_match(1)
      when /\A"(.*)"\z/m then Regexp.last_match(1)
      when /\A-?\d+\z/   then lit.to_i
      else return nil
      end

    value =
      if want_taken
        parsed
      else
        case parsed
        when true, false then !parsed
        when Integer     then parsed + 1
        when String      then parsed.empty? ? "concolic_other" : ""
        else return nil
        end
      end

    return { var => value }
  end

  if (m = /\APrefixOf\(StringVal\('(.*)'\), ([A-Za-z_][A-Za-z0-9_]*)\)\z/m.match(e))
    prefix, var = m[1], m[2]
    cur = witness[var].to_s
    value =
      if want_taken
        cur.start_with?(prefix) ? cur : prefix + cur
      else
        return nil if prefix.empty? # every string has the empty prefix
        cur.sub(/\A(?:#{Regexp.escape(prefix)})+/, "")
      end
    return { var => value }
  end

  if (m = %r{\A\(Length\(([A-Za-z_][A-Za-z0-9_]*)\) (==|!=|<|<=|>|>=) (-?\d+)\)\z}m.match(e))
    var, op, n = m[1], m[2].to_sym, m[3].to_i
    cur = witness[var].to_s
    len = length_target(op, n, want_taken, cur.length)
    return nil if len.nil?
    return { var => resize_to(cur, len) }
  end

  nil
end

def sig_of(pcs)
  pcs.map { |e, t| "#{e}:#{t}" }.join("|")
end

# suppress: ->(expr) { reason_string_or_nil }. A suppressed flip is NOT
#           attempted and is recorded in the summary — never silently dropped.
#           (Unused since targets.rb §1 removed the JVM-crashing flip; the
#           mechanism is kept so any future suppression stays auditable.)
# enrich:   ->(pcs, seeds) { [extra_seed_dict, ...] }. Extra ROOTS, for values
#           the recorded constraints cannot express. Every use is named in the
#           summary under `enriched_seeds` and called out in REPORT.md — these
#           are hand-supplied inputs, not solver-derived ones.
def explore(ep, suppress: nil, enrich: nil, &driver)
  dir = File.join(RESULTS, ep)
  FileUtils.rm_rf(dir)
  FileUtils.mkdir_p(dir)

  puts "\n== #{ep} :: prefix-directed DSE (MAX_RUNS=#{MAX_RUNS}, TIME_BUDGET=#{TIME_BUDGET}s) =="
  started     = Time.now
  stack       = [{}]
  seen_seeds  = Set.new
  seen_paths  = Set.new
  unflippable = Hash.new(0)
  suppressed  = {}
  enriched    = []
  errors      = Hash.new(0)
  samples     = {}
  runs        = 0
  written     = 0
  stop_reason = "worklist drained (fixpoint)"

  until stack.empty?
    if runs >= MAX_RUNS
      stop_reason = "MAX_RUNS cap (#{MAX_RUNS})"
      puts "[stop] #{stop_reason}"
      break
    end
    if Time.now - started > TIME_BUDGET
      stop_reason = "time budget (#{TIME_BUDGET}s)"
      puts "[stop] #{stop_reason}"
      break
    end

    seeds = stack.pop
    key = Digest::SHA1.hexdigest(JSON.generate(seeds.sort.to_h))
    next if seen_seeds.include?(key)
    seen_seeds << key

    runs += 1
    label = format("dse%04d", runs)

    begin
      dump = driver.call(label, seeds)
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "[#{label}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0, 160]}"
      errors["harness:#{e.class}"] += 1
      next
    end

    if dump["error"]
      errors["run:#{dump['error']['type']}"] += 1
      # Keep one sample message per error type even for runs whose path
      # signature duplicates an already-written dump — otherwise a wall that
      # only shows up on a deduped path is invisible in the summary.
      samples["run:#{dump['error']['type']}"] ||=
        "#{dump['error']['message'].to_s[0, 200]} @ " \
        "#{dump['error']['traceback'].to_s.lines[0..1].map(&:strip).join(' <- ')[0, 240]}"
    end

    pcs = path_conditions(dump)
    # Dedup key = path signature AND terminal outcome. Two runs can record the
    # SAME conditions and still end differently — report#destroy's
    # `(item_type == '') False` is reached both by the junk default (which then
    # dies in constantize with NameError) and by a domain value like "Post"
    # (which resolves and runs on). Keying on the PC sequence alone let the
    # crashing run shadow the working one and hid the arm entirely.
    sig = Digest::SHA1.hexdigest("#{sig_of(pcs)}##{dump.dig('error', 'type')}")

    unless seen_paths.include?(sig)
      seen_paths << sig
      written += 1
      File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
      puts format("  [%s] paths=%d runs=%d pcs=%d stack=%d %s",
                  label, written, runs, pcs.size, stack.size,
                  dump["error"] ? "error=#{dump['error']['type']}" : "")
    end

    # Seeds first, dump second: the dump is authoritative for any var it
    # actually recorded; the seed dict fills in vars that never made it into
    # symbolic_vars (belt and braces for the lazily-built request params).
    witness = seeds.merge(witness_values(dump))

    pcs.each do |(expr, taken)|
      if suppress && (reason = suppress.call(expr))
        suppressed[expr] = reason
        next
      end
      fl = flip_seed(expr, !taken, witness)
      if fl.nil?
        unflippable[expr] += 1
        next
      end
      child = seeds.merge(fl)
      ckey = Digest::SHA1.hexdigest(JSON.generate(child.sort.to_h))
      stack.push(child) unless seen_seeds.include?(ckey)
    end

    next unless enrich

    enrich.call(pcs, seeds).each do |extra|
      child = seeds.merge(extra)
      ckey = Digest::SHA1.hexdigest(JSON.generate(child.sort.to_h))
      next if seen_seeds.include?(ckey)
      enriched << extra
      stack.push(child)
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
    "worklist_exhausted" => stack.empty?,
    "stop_reason"        => stop_reason,
    "max_runs"           => MAX_RUNS,
    "time_budget"        => TIME_BUDGET,
    "elapsed_seconds"    => elapsed.round(1),
    "run_errors"         => errors,
    "run_error_samples"  => samples,
    "unflippable_pcs"    => unflippable,
    "suppressed_flips"   => suppressed,
    "enriched_seeds"     => enriched.uniq
  }
  File.write(File.join(dir, "exploration_summary.json"), JSON.pretty_generate(summary))
  puts format("== %s done: runs=%d paths=%d drained=%s elapsed=%.1fs errors=%s ==",
              ep, runs, written, stack.empty?, elapsed, errors.inspect)
end

def want?(ep)
  ONLY.empty? || ONLY.include?(ep)
end

batch_started = Time.now

# ---------------------------------------------------------------------------
# 1) GET /search — search#search
#
# Every branch in this action is on params[:q]. Rails stringifies params, and
# `search_query` does `.strip` (SymbolicString UNSUPPORTED), so no symbolic
# value could ever reach the branches — the entrypoint was VACUOUS.
#
# `search_query` is left REAL. Instead the symbolic value is injected at the
# actual program input (params[:q]) and targets.rb §3 supplies the two
# operations that used to wall or leak:
#   ConcolicString#strip         — search_query's own `.strip`
#   ConcolicString#starts_with?  — ActiveSupport's alias_method silently
#                                  bypassed SymbolicString#start_with?, so the
#                                  action's OUTERMOST branch recorded nothing.
# The action is now fully symbolic and closed by ordinary DSE over
# PrefixOf(...) / Length(...); no hand-picked inputs.
# ---------------------------------------------------------------------------
if want?("search_search")
  explore("search_search") do |label, seeds|
    qv = seeds.fetch("SYM_SEARCH_QUERY", "#ruby")
    q = lambda do
      SearchLinksReportsProfilesTargets.constr(
        "SYM_SEARCH_QUERY", qv, note: "params[:q] (GET /search)"
      )
    end
    drive(SearchController, :search, { q: qv }, label, seeds,
          format: :json, sym_params: { "q" => q })
  end
end

# ---------------------------------------------------------------------------
# 2) GET /link — links#resolve
#
# Input is a well-formed diaspora:// entity URL (the guid must satisfy
# Validation::Rule::Guid::VALID_CHARS, >=16 chars, or the parser yields
# type=nil and the action returns 404 without ever querying). This reaches
# Diaspora::EntityFinder#find -> StatusMessage.find_by(guid:) -> intercepted.
#
# PREVIOUSLY SUPPRESSED, NOW EXPLORED: the not-found side calls
# DiasporaFederation::Federation::Fetcher.fetch_public — a real HTTP fetch
# through typhoeus/libcurl that SIGSEGVs the JVM (hs_err frame
# `C [libcurl.so.4+0x6e3af] curl_easy_setopt`, reproduced twice). The last
# round had to suppress that flip and ship the entrypoint incomplete.
# targets.rb §1 mocks the fetcher to nil, so fetch_entity now falls through to
# the REAL second entity_finder.find and the flip is safe to take.
# ---------------------------------------------------------------------------
if want?("links_resolve")
  explore("links_resolve") do |label, seeds|
    drive(LinksController, :resolve,
          { q: "diaspora://alice@example.org/post/abcdef0123456789abcdef" },
          label, seeds, signed_in: false)
  end

  # Evidence, not a dump: the OTHER input shape (a bare diaspora handle) takes
  # the `elsif author` arm -> Person.find_or_fetch_by_identifier ->
  # Discovery#fetch_and_save, which crashed the JVM the same way. Written under
  # a non-dump_ name so the coverage checker does not merge two different
  # concrete inputs into one execution tree.
  handle = drive(LinksController, :resolve, { q: "alice@example.org" },
                 "handle_input", {}, signed_in: false)
  File.write(File.join(RESULTS, "links_resolve", "handle_input_evidence.json"),
             JSON.pretty_generate(handle))
  puts "  [links_resolve] bare-handle input: #{handle['error'] ? handle['error']['type'] : 'no error'}"
end

# ---------------------------------------------------------------------------
# 3) GET /report — report#index
# ---------------------------------------------------------------------------
if want?("report_index")
  explore("report_index") do |label, seeds|
    drive(ReportController, :index, {}, label, seeds)
  end
end

# ---------------------------------------------------------------------------
# 4) POST /report — report#create
# ---------------------------------------------------------------------------
#
# The previous round could not run this action through the REAL has_many:
# `current_user.reports.new(...)` -> belongs_to inverse -> stale_state ->
# _read_attribute("user_id") -> Type::Integer#cast_value -> SymbolicInt#to_i
# -> NotImplementedError, before the action body. It substituted Report.all.
# targets.rb ConcolicInt#to_i (the identity, still symbolic) removes that, so
# the action now runs through its own association. The BEFORE state is
# reproduced as evidence by toggling the subclass off for one run.
# ---------------------------------------------------------------------------
if want?("report_create")
  FileUtils.mkdir_p(File.join(RESULTS, "report_create"))
  SearchLinksReportsProfilesTargets.int_upgrade = false
  wall = drive(ReportController, :create,
               { report: { item_id: "1", item_type: "Post", text: "spam" } },
               "wall_no_int_upgrade", {}, method: "POST")
  SearchLinksReportsProfilesTargets.int_upgrade =
    ENV.fetch("SLR_INT_UPGRADE", "1") != "0"
  puts "  [report_create] SymbolicInt#to_i wall (subclass off): " \
       "#{wall['error'] ? wall['error']['type'] : 'none'}"

  explore("report_create") do |label, seeds|
    drive(ReportController, :create,
          { report: { item_id: "1", item_type: "Post", text: "spam" } },
          label, seeds, method: "POST")
  end
  # explore() wipes the directory, so write the evidence afterwards. Non-dump_
  # name so the coverage checker does not consume it.
  File.write(File.join(RESULTS, "report_create", "wall_evidence_symbolic_int_to_i.json"),
             JSON.pretty_generate(wall))
end

# ---------------------------------------------------------------------------
# 5) PUT /report/:id — report#update
# ---------------------------------------------------------------------------
if want?("report_update")
  explore("report_update") do |label, seeds|
    drive(ReportController, :update, { id: 1 }, label, seeds, method: "PUT")
  end
end

# ---------------------------------------------------------------------------
# 6) DELETE /report/:id — report#destroy
# ---------------------------------------------------------------------------
#
# DOMAIN-VALUE ROOTS (declared, not solver-derived). `report.item` is a
# polymorphic belongs_to, so the arm taken by `case item when Post / when
# Comment` is decided by the item_type STRING. All the runtime can record
# about that string is `(item_type == '')` (from `type.presence` inside
# BelongsToPolymorphicAssociation#klass), so DSE can only ever choose between
# "" and "not empty" — and "not empty" is the default junk value, which
# constantize rightly rejects with NameError. Report itself declares the
# domain:
#     validates :item_type, inclusion: { in: %w(Post Comment) }
# so those two values are pushed as extra roots. They are hand-supplied inputs
# and are recorded as such in exploration_summary.json -> enriched_seeds.
# ---------------------------------------------------------------------------
if want?("report_destroy")
  item_type_domain = lambda do |pcs, _seeds|
    vars = pcs.map { |expr, _| expr[/\A\((\w*_item_type) == ''\)\z/, 1] }.compact.uniq
    vars.flat_map { |v| %w[Post Comment].map { |t| { v => t } } }
  end
  explore("report_destroy", enrich: item_type_domain) do |label, seeds|
    drive(ReportController, :destroy, { id: 1 }, label, seeds, method: "DELETE")
  end
end

# ---------------------------------------------------------------------------
# 7) GET /profile — profiles#edit
# ---------------------------------------------------------------------------
#
# THE SILENT GAP, shipped both ways. concolic_targets.rb:317 leaves every
# symbolic record with @new_record = true, and AR's
# CollectionAssociation#find_target? is
#     !loaded? && (!owner.new_record? || foreign_key_present?) && klass
# (foreign_key_present? is false for a collection), so `@profile.tags` returns
# [] with NO query, NO interception and NO path condition. targets.rb §6 flips
# it. The unfixed run is written as evidence under a non-dump_ name.
# ---------------------------------------------------------------------------
if want?("profiles_edit")
  FileUtils.mkdir_p(File.join(RESULTS, "profiles_edit"))
  SearchLinksReportsProfilesTargets.new_record_fix = false
  silent = drive(ProfilesController, :edit, {}, "new_record_true", {})
  SearchLinksReportsProfilesTargets.new_record_fix =
    ENV.fetch("SLR_NEW_RECORD_FIX", "1") != "0"

  explore("profiles_edit") do |label, seeds|
    drive(ProfilesController, :edit, {}, label, seeds)
  end

  # explore() wipes the directory, so write the evidence afterwards.
  File.write(File.join(RESULTS, "profiles_edit", "silent_gap_evidence_new_record_true.json"),
             JSON.pretty_generate(silent))
  puts "  [profiles_edit] @new_record=true evidence: " \
       "#{silent['error'] ? silent['error']['type'] : 'no error (tags silently [])'}"
end

# ---------------------------------------------------------------------------
# 8) PUT /profile — profiles#update
# ---------------------------------------------------------------------------
if want?("profiles_update")
  explore("profiles_update") do |label, seeds|
    drive(ProfilesController, :update,
          { profile: { first_name: "Alice", last_name: "User", bio: "test",
                       location: "US", searchable: true, nsfw: false,
                       public_details: true } },
          label, seeds, method: "PUT")
  end
end

# ---------------------------------------------------------------------------
# 9) GET /profiles/:id — profiles#show
# ---------------------------------------------------------------------------
if want?("profiles_show")
  explore("profiles_show") do |label, seeds|
    drive(ProfilesController, :show, { id: "abc123" }, label, seeds,
          signed_in: false, format: :json)
  end
end

elapsed = Time.now - batch_started
File.open(File.join(RESULTS, "elapsed_seconds.txt"), "a") do |f|
  f.puts format("%s %.1f", (ONLY.empty? ? "all" : ONLY.join("+")), elapsed)
end
puts format("\n== batch done in %.1fs ==", elapsed)
