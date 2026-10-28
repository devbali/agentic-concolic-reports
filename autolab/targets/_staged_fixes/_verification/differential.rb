# frozen_string_literal: true
#
# differential.rb — THE NO-LOST-SQL STATEMENT-SET DIFFERENTIAL.
#
# For each scenario (one AR operation on one model), this runs the SAME
# operation TWICE in one process:
#
#   PHASE REAL — no mock installed, real ActiveRecord, private copy of
#                db/concolic.sqlite3, every statement captured from
#                `sql.active_record`.               -> the GROUND-TRUTH set.
#   PHASE MOCK — `core.rb` (and optionally an endpoint layer) installed,
#                the same operation on an equivalent receiver, every note
#                the mocks produce collected.        -> the RECORDED set.
#
# The comparison is a SET difference in BOTH directions:
#   LOST       real statement carried by no note      (the hole)
#   FABRICATED note statement the real run never issued
#
# Receivers for the MOCK phase are built BEFORE `install!` (finders are
# themselves mocked, so a post-install `find` would hand back a symbolic
# instance) and stashed; the mock phase issues no SQL, so re-using an
# equivalent row is sound.
#
# ENV:
#   TARGETS=core|override    which target stack to install (default core)
#   MODELS=A,B,C             restrict to these model names
#   ONLY=scenario_id         restrict to one scenario
#   OUT=/path/out.json
#
# Writes nothing outside its own private DB copy and OUT.

require "./config/environment"
%w[call_interceptor base int string bool list].each do |f|
  require "/home/dev/project/src_new/runtimes/ruby_runtime/#{f}"
end
require "json"
require "fileutils"

HERE  = File.dirname(File.expand_path(__FILE__))
STACK = ENV["TARGETS"] || "core"
OUT   = ENV["OUT"] || File.join(HERE, "out", "differential_#{STACK}.json")
FileUtils.mkdir_p(File.dirname(OUT))

# ---------------------------------------------------------------- private DB
SRC_DB = File.join(Rails.root, "db", "concolic.sqlite3")
DB     = File.join(HERE, "out", "diff_#{STACK}_#{Process.pid}.sqlite3")
FileUtils.cp(SRC_DB, DB)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB, pool: 1)
CONN = ActiveRecord::Base.connection

# ------------------------------------------------------------ sql capture
$sql = []
$capture = false
ActiveSupport::Notifications.subscribe("sql.active_record") do |_n, _s, _f, _i, p|
  next unless $capture
  name = p[:name].to_s
  next if name =~ /SCHEMA/
  s = p[:sql].to_s
  next if s =~ /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|PRAGMA)/i
  $sql << s
end

def capture
  $sql = []
  $capture = true
  begin
    yield
    ["ok", $sql.dup]
  rescue Exception => e # rubocop:disable Lint/RescueException
    ["raised #{e.class}: #{e.message[0, 120]}", $sql.dup]
  ensure
    $capture = false
  end
end

# ------------------------------------------------------- note capture (mock)
# Every mock hangs its statement on the returned SymbolicVar's `note`, or (for
# a falsy/plain return) on Thread.current[:concolic_pending_note], which the
# interceptor drains into the symbolic_call event. Capture BOTH by listening on
# the interceptor's event stream where available, and by reading the return.
$notes = []
def note_of(v)
  return v.note if v.respond_to?(:note) && v.note
  return v.concolic_note if v.respond_to?(:concolic_note)
  nil
end

def mock_capture
  # `SymbolicFunc.get_call_records` is the non-destructive snapshot of exactly
  # the records `CallInterceptor#symbolic_call_event` turns into dump events —
  # so `rec.note` here IS the note the extraction reads. Comparing anything
  # else would be comparing a convenience, not the corpus.
  before = begin
    SymbolicFunc.get_call_records.size
  rescue StandardError
    0
  end
  status = "ok"
  r = nil
  begin
    r = yield
  rescue Exception => e # rubocop:disable Lint/RescueException
    status = "raised #{e.class}: #{e.message[0, 120]}"
  end
  notes = []
  begin
    recs = SymbolicFunc.get_call_records
    recs[before..-1].to_a.each do |rec|
      notes << [rec.target_name.to_s, rec.note.to_s] if rec.respond_to?(:note) && rec.note
    end
  rescue StandardError
    nil
  end
  n = note_of(r)
  notes << ["(return value)", n.to_s] if n && notes.none? { |_t, x| x == n.to_s }
  [status, notes]
end

# ------------------------------------------------------------------ fixtures
# Build a persisted row for a model by RAW SQL, filling every NOT NULL column
# with a type-appropriate value. Bypasses validations and callbacks on purpose:
# the question under test is WHICH STATEMENT an operation renders, not whether
# the app's validations pass.
def junk_for(meta, i)
  case meta.type
  when :integer, :bigint then i
  when :boolean          then 0
  when :datetime, :timestamp, :date then Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
  when :float, :decimal  then 0
  else "cx#{i}"
  end
end

def seed_row!(klass, id)
  t = klass.table_name
  cols = []
  vals = []
  klass.columns_hash.each do |c, meta|
    next if c == klass.primary_key
    next unless !meta.null || %w[created_at updated_at].include?(c)
    cols << c
    vals << junk_for(meta, id)
  end
  cols.unshift(klass.primary_key)
  vals.unshift(id)
  q = vals.map { |v| v.is_a?(String) ? "'#{v.gsub("'", "''")}'" : v.to_s }.join(", ")
  CONN.execute(%(INSERT INTO "#{t}" (#{cols.map { |c| %("#{c}") }.join(", ")}) VALUES (#{q})))
  id
rescue StandardError => e
  raise "seed_row! #{klass.name}: #{e.class} #{e.message[0, 120]}"
end

# A writable non-pk, non-timestamp column to dirty. Prefer a boolean or int so
# no type cast surprises enter the picture.
def dirty_col(klass)
  pk = klass.primary_key
  pref = klass.columns_hash.find do |c, m|
    c != pk && !%w[created_at updated_at type guid].include?(c) &&
      !c.end_with?("_guid") && %i[boolean integer bigint].include?(m.type)
  end
  pref ||= klass.columns_hash.find do |c, m|
    c != pk && !%w[created_at updated_at type guid].include?(c) &&
      !c.end_with?("_guid") && m.type == :string
  end
  return nil unless pref
  col, meta = pref
  [col, meta.type == :boolean ? true : (meta.type == :string ? "cxnew" : 4242)]
end

# ------------------------------------------------------------------- models
def candidate_models
  if ENV["MODELS"]
    return ENV["MODELS"].split(",").map { |n| n.strip.constantize rescue nil }.compact
  end
  # eager_load is off in the concolic env, so ActiveRecord::Base.descendants
  # would be nearly empty. Load every model file explicitly — mechanical, no
  # hand-picked list.
  Dir[File.join(Rails.root, "app/models/**/*.rb")].sort.each do |f|
    begin
      require f
    rescue Exception # rubocop:disable Lint/RescueException
      nil
    end
  end
  Rails.application.eager_load! rescue nil
  ActiveRecord::Base.descendants.select do |k|
    begin
      next false if k.abstract_class?
      next false unless k.name
      next false if k.name.start_with?("ActiveRecord::", "ActiveStorage::", "ApplicationRecord")
      next false unless k == k.base_class          # STI subclasses share the table
      CONN.table_exists?(k.table_name)
    rescue StandardError
      false
    end
  end.sort_by(&:name)
end

# ------------------------------------------------------------------ scenarios
# Each scenario is [id, builder, runner]. The builder runs BEFORE install! and
# returns the receiver pair {real:, mock:}; the runner performs the operation.
SCENARIOS = %w[
  save_new save_changed save_unchanged update update_attribute touch destroy
  rel_update_all rel_delete_all rel_destroy_all proxy_create autosave_collection
].freeze

def build_pair(klass, scen, idbase)
  pk = klass.primary_key
  case scen
  when "save_new"
    dc = dirty_col(klass)
    mk = lambda do
      r = klass.new
      # fill NOT NULL non-default columns so the INSERT is realistic
      klass.columns_hash.each do |c, m|
        next if c == pk || %w[created_at updated_at].include?(c)
        next if m.null
        r[c] = junk_for(m, idbase)
      end
      r[dc[0]] = dc[1] if dc
      r
    end
    { real: mk.call, mock: mk.call, info: { dirty: dc && dc[0] } }
  when "save_changed", "update", "update_attribute", "touch", "destroy"
    dc = dirty_col(klass)
    a = seed_row!(klass, idbase)
    b = seed_row!(klass, idbase + 1)
    { real: klass.find(a), mock: klass.find(b), info: { dirty: dc && dc[0], val: dc && dc[1] } }
  when "save_unchanged"
    a = seed_row!(klass, idbase)
    b = seed_row!(klass, idbase + 1)
    { real: klass.find(a), mock: klass.find(b), info: {} }
  when "proxy_create", "autosave_collection"
    # D7 (CollectionProxy#create) and D8 (an association INSERT deferred to the
    # owner's save). Pick the association MECHANICALLY: the first has_many on
    # this model whose target class has a table and whose foreign key is a
    # plain column, so no model is special-cased.
    refl = klass.reflect_on_all_associations(:has_many).find do |r|
      begin
        next false if r.options[:as] || r.options[:polymorphic]
        next false unless r.klass && CONN.table_exists?(r.klass.table_name)
        scen == "autosave_collection" ? !r.through_reflection.nil? : r.through_reflection.nil?
      rescue StandardError
        false
      end
    end
    return nil unless refl
    child = refl.klass
    if scen == "proxy_create"
      a = seed_row!(klass, idbase)
      b = seed_row!(klass, idbase + 1)
      { real: klass.find(a), mock: klass.find(b),
        info: { assoc: refl.name, child: child.name } }
    else
      # a PERSISTED row of the through-target, appended to a NEW owner: the
      # join-row INSERT is then deferred to the owner's save (the D8 shape).
      src = refl.source_reflection.klass rescue child
      s1 = seed_row!(src, idbase + 2)
      s2 = seed_row!(src, idbase + 3)
      mk = lambda do
        r = klass.new
        klass.columns_hash.each do |c, m|
          next if c == pk || %w[created_at updated_at].include?(c)
          next if m.null
          r[c] = junk_for(m, idbase)
        end
        r
      end
      { real: mk.call, mock: mk.call,
        info: { assoc: refl.name, child: child.name, src: src.name,
                real_id: s1, mock_id: s2 } }
    end
  when "rel_update_all", "rel_delete_all", "rel_destroy_all"
    dc = dirty_col(klass)
    seed_row!(klass, idbase)
    seed_row!(klass, idbase + 1)
    cond = { pk => [idbase, idbase + 1] }
    { real: klass.where(cond), mock: klass.where(cond), info: { dirty: dc && dc[0], val: dc && dc[1] } }
  else
    nil
  end
end

def run_op(klass, scen, rec, info)
  case scen
  when "save_new"        then rec.save(validate: false)
  when "save_changed"    then (rec[info[:dirty]] = info[:val]; rec.save(validate: false))
  when "save_unchanged"  then rec.save(validate: false)
  when "update"          then rec.update(info[:dirty] => info[:val])
  when "update_attribute" then rec.update_attribute(info[:dirty], info[:val])
  when "touch"           then rec.touch
  when "destroy"         then rec.destroy
  when "rel_update_all"  then rec.update_all(info[:dirty] => info[:val])
  when "rel_delete_all"  then rec.delete_all
  when "rel_destroy_all" then rec.destroy_all
  when "proxy_create"
    rec.public_send(info[:assoc]).create
  when "autosave_collection"
    src = info[:src].constantize
    which = info[:which]
    rec.public_send(info[:assoc]) << src.find(which)
    rec.save(validate: false)
  end
end

# ================================================================== PHASE REAL
models = candidate_models
only   = ENV["ONLY"]
scens  = only ? only.split(",") : SCENARIOS

warn "[diff] #{models.size} models, #{scens.size} scenarios, stack=#{STACK}"

RESULT = { "stack" => STACK, "targets_dir" => (ENV["TARGETS_DIR"] || "live"), "rails_env" => Rails.env.to_s,
           "ar" => ActiveRecord::VERSION::STRING, "cases" => [] }
PENDING = []      # [case_hash, klass, scen, mock_receiver, info]

idc = 900_000
models.each do |k|
  scens.each do |s|
    idc += 10
    c = { "model" => k.name, "table" => (k.table_name rescue nil), "scenario" => s, "id" => idc }
    pair = begin
      build_pair(k, s, idc)
    rescue StandardError => e
      c["build_error"] = "#{e.class}: #{e.message[0, 160]}"
      RESULT["cases"] << c
      next
    end
    next unless pair
    if pair[:info][:dirty].nil? && %w[save_changed update update_attribute rel_update_all].include?(s)
      c["skip"] = "no dirtyable column"
      RESULT["cases"] << c
      next
    end
    rinfo = pair[:info].dup
    rinfo[:which] = rinfo[:real_id] if rinfo[:real_id]
    st, sql = capture { run_op(k, s, pair[:real], rinfo) }
    c["real_status"] = st
    c["real"] = sql
    c["info"] = pair[:info].map { |kk, vv| [kk.to_s, vv] }.to_h
    RESULT["cases"] << c
    minfo = pair[:info].dup
    minfo[:which] = minfo[:mock_id] if minfo[:mock_id]
    PENDING << [c, k, s, pair[:mock], minfo]
  end
end
warn "[diff] real phase done: #{RESULT['cases'].size} cases"

# ================================================================== INSTALL
TDIR = ENV["TARGETS_DIR"] || "/home/dev/project/reports/autolab/targets"
require File.join(TDIR, "core.rb")
IC = CallInterceptor.instance
ConcolicTargets.install!(IC)
if STACK == "override"
  require File.join(TDIR, "endpoints/aspect_memberships_create.rb")
  AspectMembershipsTargets.install!(IC)
  AmDeviseUserNaming.install!(IC) if defined?(AmDeviseUserNaming)
end
warn "[diff] installed stack=#{STACK}"

# ================================================================== PHASE MOCK
PENDING.each do |c, k, s, rec, info|
  st, notes = mock_capture { run_op(k, s, rec, info) }
  c["mock_status"] = st
  c["notes"] = notes
end
warn "[diff] mock phase done"

File.write(OUT, JSON.pretty_generate(RESULT))
warn "[diff] wrote #{OUT}"
