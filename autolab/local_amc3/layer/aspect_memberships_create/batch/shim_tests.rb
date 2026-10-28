# frozen_string_literal: false
#
# shim_tests.rb -- aspect_memberships_create (local_amc3 / drive 10, batch-1).
# PROVENANCE: carried over with bodies unchanged from drive 9's
# local_amc2/boxes/aspect_memberships_create-batch-1-dfb2bc19/out/packet/shim_tests.rb
# (sha256 93b9555f251a1db18c1fa35d4d8aac2dfaed1897d0f1d6b293063ff92dfd351f), which was
# drive 8's file (sha256 af94ef76...), itself local_tags1's file, each with only its
# header changed. Only this header changed here. The extract_cmd names ONLY the shared
# library, so the key set is the same 22 keys (re-extracted in this box, 2026-10-14).
# Re-run in THIS box before submission; the verdicts recorded in NOTES.md are this run's.
# Keys are EXACTLY the engine's: shim_extractor.rb over targets/core.rb +
# targets/shared_shims.rb (22 keys). Format authority:
# src/ruby_runtime/completion_checker/shim_test_runner.rb.
#
# KEYS DELIBERATELY ABSENT -- PROTOCOL BY RUNTIME (shim_test_runner.rb
# `machinery?`, lines 93-117: kind rep_plumbing + method in PROTOCOL_API or
# matching /\A(concolic_\w+|\w*_dirty)\z/ => verdict PROTOCOL with no entry):
#   obj.read_attribute obj._read_attribute obj.write_attribute
#   obj._write_attribute obj.attributes obj.inspect obj.persisted?
#   obj.new_record? obj.concolic_attrs obj.concolic_note obj.concolic_dirty
#
# NOT protocol by runtime (owner "obj" does not resolve and the method is not
# on PROTOCOL_API), so they carry entries below: obj.image_url,
# obj.hidden_shareables, obj.post_location.
#
# LOAD MODEL. The runner `load`s this file AFTER `require "./config/environment"`
# (cwd = the diaspora app). `targets:` / `coverage_of:` are read by the runner
# as live Modules, so they cannot be deferred into lambdas; everything that
# needs the app therefore sits inside the `if` below. Outside a booted app
# (plain `ruby -e load`) SHIM_TESTS is defined EMPTY -- that load is only a
# syntax/definition check, never a verdict.
#
# RULES FOLLOWED: every body RUNS the real code; no application method is
# stubbed. The only non-data interventions are (a) a throwaway interceptor
# handed to ConcolicTargets.install! so that its two anonymous prepends and the
# escape_segment prepend get installed while NOTHING is declared (install!
# reaches classes only via `interceptor.declare_target`, verified by grep over
# core.rb:1288-2560), and (b) the prepend-detach described at SHIM_DETACHED
# (an instrument limit of TargetCallProbe, not a behaviour change).

if defined?(Rails) && Rails.respond_to?(:application) && Rails.application &&
   defined?(ActiveRecord::Base)

  # A fresh temp dir, NOT __dir__: this file is read from a read-only packet
  # mount on the check box, so nothing may be written beside it.
  require "tmpdir"
  SHIM_WORK_DIR = Dir.mktmpdir("shim_tests_cvd_")

  # -------------------------------------------------------------------------
  # FIXTURE DB: real sqlite + the app schema, rows by raw INSERT (data only).
  # Written into SHIM_WORK_DIR (db + _concrete_schema.rb).
  # -------------------------------------------------------------------------
  require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
  CompletionChecker::ConcreteEnv.setup!(db: File.join(SHIM_WORK_DIR, "shim_tests.sqlite3"))
  CompletionChecker::ConcreteEnv.insert("users", id: 9, username: "shimtester",
    email: "shim@example.org", encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
    language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
  CompletionChecker::ConcreteEnv.insert("people", id: 1, guid: "shimguid000000001",
    diaspora_handle: "shim@localhost", serialized_public_key: "K1", owner_id: 9,
    closed_account: 0, fetch_status: 0)
  CompletionChecker::ConcreteEnv.insert("profiles", id: 11, person_id: 1,
    first_name: "Shim", last_name: "Tester", searchable: 1, nsfw: 0, public_details: 0)
  CompletionChecker::ConcreteEnv.insert("aspects", id: 950, user_id: 9, name: "Friends", order_id: 1)
  CompletionChecker::ConcreteEnv.insert("aspects", id: 951, user_id: 9, name: "Work", order_id: 2)

  Rails.application.config.assets.check_precompiled_asset = false
  ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

  SHIM_DB_USER = User.find(9)

  # -------------------------------------------------------------------------
  # The shared boundary, loaded as autolab_dse.rb loads it.
  # -------------------------------------------------------------------------
  %w[call_interceptor base int string bool list].each do |f|
    require File.join("/home/dev/project/src_new/runtimes/ruby_runtime", f)  # the runtime autolab_dse.rb loads (RUNTIME, :44)
  end
  require "/home/dev/project/reports/autolab/targets/core.rb"
  require "/home/dev/project/reports/autolab/targets/shared_shims.rb"

  SHIM_FAKE_INTERCEPTOR = Object.new
  def SHIM_FAKE_INTERCEPTOR.declare_target(klass, meth, **_kw)
    (@declared ||= []) << [klass.to_s, meth]
    nil
  end
  def SHIM_FAKE_INTERCEPTOR.declared
    @declared ||= []
  end
  ConcolicTargets.install!(SHIM_FAKE_INTERCEPTOR)
  raise "throwaway interceptor saw no declarations -- install! did not run" if SHIM_FAKE_INTERCEPTOR.declared.empty?
  # shared_shims.rb: default groups = none; it declares nothing and prepends
  # nothing, so the extractor found no key in it. Run it anyway for parity.
  AutolabSharedShims.install!(SHIM_FAKE_INTERCEPTOR)

  SHIM_SINGULAR_MEMO = ActiveRecord::Associations::SingularAssociation.ancestors
                         .find { |m| m.name.nil? && m.instance_methods(false) == [:find_target] }
  raise "W3-memo module not installed by install!" unless SHIM_SINGULAR_MEMO
  SHIM_GON_MEMO = ::Gon.singleton_class.ancestors
                    .find { |m| m.name.nil? && m.instance_methods(false) == [:preloads] }
  raise "Gon preloads shim not installed by install!" unless SHIM_GON_MEMO
  raise "escape_segment shim not prepended" unless
    ActionDispatch::Journey::Router::Utils.singleton_class.ancestors.include?(ConcolicEscapeSegmentShim)

  # -------------------------------------------------------------------------
  # SHIM_DETACHED -- INSTRUMENT LIMIT, worked around (not waived).
  # TargetCallProbe wraps a target via `owner.instance_method(m)` +
  # `owner.define_method(m)`. When a PREPENDED module defines the same method,
  # instance_method resolves THROUGH the prepend, so the probe's "original" is
  # the prepend body while the prepend's `super` lands on the probe wrapper:
  # infinite recursion. For each naming prepend whose wrapped method must be
  # observed as a target, the body is detached here (UnboundMethod kept) and
  # re-attached from INSIDE its own fixture, i.e. after `capture` has wrapped
  # the REAL method. Re-attachment is left in place (the runner reads the
  # coverage range from the module after the fixture), so later tests never
  # list that (owner, method) as a target.
  # The SingularAssociation memo is NOT detached: no test lists
  # SingularAssociation#find_target as a target; association loads are
  # observed one level down, at ActiveRecord::Querying#find_by_sql, which is
  # what the real find_target's StatementCache#execute calls (AR 5.2.4.3
  # statement_cache.rb:108).
  # -------------------------------------------------------------------------
  SHIM_DETACHED = {}
  [[ConcolicUpdateAllValueNaming, :update_all],
   [ConcolicWriteArgsNaming, :update],
   [ConcolicProxyCreateArgsNaming, :create]].each do |mod, m|
    SHIM_DETACHED[[mod, m]] = mod.instance_method(m)
    mod.send(:remove_method, m)
  end
  def shim_reattach!(mod, m)
    mod.send(:define_method, m, SHIM_DETACHED.fetch([mod, m]))
  end

  # SQL statements issued while the block runs (SCHEMA lookups excluded).
  # Each entry: [sql, value of the named thread-local at that moment].
  def shim_sql_during(tl_key = nil)
    seen = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*a|
      p = a[4]
      next if p[:name].to_s == "SCHEMA"
      seen << [p[:sql].to_s, (tl_key ? Thread.current[tl_key] : nil)]
    end
    begin
      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end
    seen
  end

  # Core-declared targets that no prepend shadows (safe for the probe).
  SHIM_BASE_TARGETS = [
    [ActiveRecord::FinderMethods, :find_by],
    [ActiveRecord::FinderMethods, :find],
    [ActiveRecord::FinderMethods, :first],
    [ActiveRecord::FinderMethods, :last],
    [ActiveRecord::FinderMethods, :take],
    [ActiveRecord::FinderMethods, :exists?],
    [ActiveRecord::Calculations, :count],
    [ActiveRecord::Calculations, :sum],
    [ActiveRecord::Relation, :records],
    [ActiveRecord::Relation, :to_a],
    [ActiveRecord::Relation, :to_ary],
    [ActiveRecord::Associations::CollectionProxy, :records],
    [ActiveRecord::Associations::CollectionProxy, :load_target],
    [ActiveRecord::Core::ClassMethods, :find],
    [ActiveRecord::Core::ClassMethods, :find_by],
    [ActiveRecord::Querying, :find_by_sql],
  ].freeze

  # Concrete fixtures built OUTSIDE any capture (schema lookups only).
  SHIM_PROFILE_FULL = Profile.new
  SHIM_PROFILE_FULL[:image_url]        = "http://remote.example/u/large.png"
  SHIM_PROFILE_FULL[:image_url_small]  = "http://remote.example/u/small.png"
  SHIM_PROFILE_FULL[:image_url_medium] = "http://remote.example/u/medium.png"
  SHIM_PROFILE_EMPTY = Profile.new
  SHIM_NEW_USER = User.new
  SHIM_SYM_PROFILE = ConcolicTargets.symbolic_instance(Profile, "SHIMTEST_profile", "shim test")
  SHIM_SYM_USER    = ConcolicTargets.symbolic_instance(User,    "SHIMTEST_user",    "shim test")
  SHIM_ASPECT = Aspect.find(950)

  SHIM_TESTS = {
    # =======================================================================
    # obj.image_url (core.rb:1110) -- shim on Profile reps returns a fixed
    # "/concolic/image.jpg" in place of the REAL Profile#image_url
    # (app/models/profile.rb:59-77). The claim the shim rests on: the real
    # body is pure display computation -- no target, no SQL. Run the REAL body
    # over every arm: medium / small / default column, the camo proxy arm
    # (AppConfig values set as config DATA and restored), and the nil ->
    # default-avatar arm. Then run the shim itself and check it answers the
    # same call shapes with the same type.
    # =======================================================================
    "obj.image_url" => {
      targets: SHIM_BASE_TARGETS,
      coverage_of: [Profile, :image_url, :instance],
      fixture: -> {
        camo = AppConfig.privacy.camo
        prev = camo.proxy_remote_pod_images?
        sql = shim_sql_during do
          p = SHIM_PROFILE_FULL
          raise "medium arm" unless p.image_url(:thumb_medium) == "http://remote.example/u/medium.png"
          raise "small arm"  unless p.image_url(:thumb_small)  == "http://remote.example/u/small.png"
          raise "default arm" unless p.image_url == "http://remote.example/u/large.png"
          fallback = SHIM_PROFILE_EMPTY.image_url(:thumb_small)
          raise "nil arm: #{fallback.inspect}" unless fallback.to_s.include?("default")
          begin
            # camo.root/key cannot be set here (Configurate::MissingSetting on
            # the nil-default keys, measured), so the REAL Diaspora::Camo
            # .image_url runs with the default (empty) root; its
            # url_eligible? then returns false and it hands the url back.
            AppConfig.privacy.camo.proxy_remote_pod_images = true
            raise "camo toggle did not take" unless AppConfig.privacy.camo.proxy_remote_pod_images?
            proxied = p.image_url
            raise "camo arm: #{proxied.inspect}" unless proxied == Diaspora::Camo.image_url("http://remote.example/u/large.png")
          ensure
            AppConfig.privacy.camo.proxy_remote_pod_images = prev
          end
          # the shim, same call shapes
          s0 = SHIM_SYM_PROFILE.image_url
          s1 = SHIM_SYM_PROFILE.image_url(:thumb_small)
          raise "shim shape" unless s0.is_a?(String) && s1.is_a?(String)
        end
        raise "real image_url issued SQL: #{sql.first.inspect}" unless sql.empty?
      } },

    # =======================================================================
    # obj.hidden_shareables (core.rb:1120) -- shim returns a memoised mutable
    # {} in place of the REAL User#hidden_shareables (app/models/user.rb:126,
    # `self[:hidden_shareables] ||= {}` over a serialized Hash column). Run the
    # real body on a concrete User: fresh -> {}, then the SAME Hash comes back
    # after mutation; the shim is held to the identical contract. No SQL.
    # =======================================================================
    "obj.hidden_shareables" => {
      targets: SHIM_BASE_TARGETS,
      coverage_of: [User, :hidden_shareables, :instance],
      fixture: -> {
        sql = shim_sql_during do
          [SHIM_NEW_USER, SHIM_SYM_USER].each do |u|
            h = u.hidden_shareables
            raise "#{u.class} hidden_shareables not an empty Hash: #{h.inspect}" unless h.is_a?(Hash) && h.empty?
            h["Post"] = ["100"]
            raise "#{u.class} hidden_shareables not memoised" unless u.hidden_shareables["Post"] == ["100"]
          end
        end
        raise "hidden_shareables issued SQL: #{sql.first.inspect}" unless sql.empty?
      } },

    # =======================================================================
    # obj.post_location (core.rb:1129) -- installed ONLY on reps whose class
    # is base `Post` (klass.name.split('::').last == "Post"). Base Post defines
    # no post_location at all (only StatusMessage:98 and Reshare:54 do), which
    # the runner CHECKS against the real class via machinery?.
    # CAVEAT (reported, not hidden): StatusMessage#post_location reads the
    # `location` association (a SQL load). If a base-Post rep ever stands for
    # a StatusMessage row, this shim elides that read.
    # =======================================================================
    "obj.post_location" => { real_class: "Post" },

    # =======================================================================
    # W3-memo (core.rb:1926-1940) -- SingularAssociation#find_target loaded-
    # target memo. A DISPATCH layer: its job is to reach the real find_target
    # (observed as its statement, Querying#find_by_sql) on a miss and NOT on a
    # hit. Arms: label change -> reset, miss -> super, hit -> cached.
    # =======================================================================
    "ActiveRecord::Associations::SingularAssociation.find_target" => {
      targets: SHIM_BASE_TARGETS,
      reaches: ["ActiveRecord::Querying#find_by_sql"],
      coverage_of: [SHIM_SINGULAR_MEMO, :find_target, :instance],
      fixture: -> {
        ci = CallInterceptor.instance
        prev_label = ci.instance_variable_get(:@current_run_label)
        begin
          Thread.current[:concolic_loaded_target_memo] = nil
          ci.instance_variable_set(:@current_run_label, "SHIMTEST_A")
          a = User.find_by_sql(["SELECT * FROM users WHERE id = ?", 9]).first.association(:person)
          miss = shim_sql_during { @shim_first = a.send(:find_target) }
          raise "miss: #{@shim_first.inspect}" unless @shim_first && @shim_first.id == 1
          raise "miss did not reach the real find_target (#{miss.size} stmts)" unless miss.size == 1
          hit = shim_sql_during { @shim_second = a.send(:find_target) }
          raise "hit re-issued the statement" unless hit.empty?
          raise "hit did not return the cached target" unless @shim_second.equal?(@shim_first)
          ci.instance_variable_set(:@current_run_label, "SHIMTEST_B")
          reset = shim_sql_during { @shim_third = a.send(:find_target) }
          raise "label reset lost the target" unless @shim_third && @shim_third.id == 1
          raise "label reset did not re-issue" unless reset.size == 1
        ensure
          ci.instance_variable_set(:@current_run_label, prev_label)
          Thread.current[:concolic_loaded_target_memo] = nil
        end
      } },

    # =======================================================================
    # X6b-preloads (core.rb:2223-2228) -- `Gon.preloads` accessor. Real gon
    # 6.3.2 has no `preloads` method; the fallback path is Gon.method_missing
    # -> the per-request gon hash. The shim's own body: fresh -> {}, memo
    # hit. Pure Hash bookkeeping, zero targets, zero SQL.
    # =======================================================================
    "::Gon.singleton_class.preloads" => {
      targets: SHIM_BASE_TARGETS,
      coverage_of: [SHIM_GON_MEMO, :preloads, :instance],
      fixture: -> {
        saved = ::Gon.instance_variable_get(:@concolic_preloads)
        sql = shim_sql_during do
          ::Gon.instance_variable_set(:@concolic_preloads, nil)
          first = ::Gon.preloads
          raise "preloads: #{first.inspect}" unless first == {}
          first[:post] = [1]
          raise "memo lost" unless ::Gon.preloads[:post] == [1]
        end
        ::Gon.instance_variable_set(:@concolic_preloads, saved)
        raise "preloads issued SQL" unless sql.empty?
      } },

    # =======================================================================
    # ConcolicEscapeSegmentShim (core.rb:65-69, prepended at 2556). Concretise
    # the segment, then the REAL escaper via super. Differential: for a real
    # SymbolicString and for a plain String, the shimmed result equals the real
    # escaper (reached via super_method) on the concrete value, and is a plain
    # String. Zero targets, zero SQL.
    # =======================================================================
    "ActionDispatch::Journey::Router::Utils.singleton_class.escape_segment" => {
      targets: SHIM_BASE_TARGETS,
      coverage_of: [ConcolicEscapeSegmentShim, :escape_segment, :instance],
      fixture: -> {
        utils = ActionDispatch::Journey::Router::Utils
        real = utils.method(:escape_segment).super_method
        raise "super_method is not the real escaper" if real.owner == ConcolicEscapeSegmentShim
        sql = shim_sql_during do
          seg = SymbolicString.new("a b/c?d%ü", name: "SHIMTEST_seg")
          raise "fixture is not symbolic" unless seg.respond_to?(:value)
          got = utils.escape_segment(seg)
          want = real.call("a b/c?d%ü")
          raise "symbolic arm: #{got.inspect} != #{want.inspect}" unless got == want && !got.is_a?(SymbolicString)
          got2 = utils.escape_segment("plain seg/1")
          raise "plain arm" unless got2 == real.call("plain seg/1")
          got3 = utils.escape_segment(42)
          raise "to_s arm" unless got3 == real.call("42")
        end
        raise "escape_segment issued SQL" unless sql.empty?
      } },

    # =======================================================================
    # ConcolicKwargsToPositional on ActiveRecord::Base.singleton_class
    # (core.rb:2575-2603; find_by / find_by! / exists? share ONE define_method
    # block, so one coverage range). A NAMING layer: stash the conditions in
    # Thread.current[:concolic_finder_conds] and continue unchanged. Checked:
    # (1) all three cond arms (kwargs / positional Hash / neither) run;
    # (2) at the moment the statement executes the stash holds exactly those
    #     conditions, and it is restored afterwards;
    # (3) differential: same record as the un-prepended method (super_method).
    # =======================================================================
    "ActiveRecord::Base.singleton_class.DYNAMIC" => {
      # INSTRUMENT LIMIT (measured, runs 1-2): with Core::ClassMethods#find_by
      # wrapped by TargetCallProbe, the real body's own `super` (its non-Hash
      # arm, active_record/core.rb) raises "super: no superclass method
      # find_by" under JRuby's bind/call. So that one target is left out of
      # this test's list; what it hands off to is still observed below it
      # (FinderMethods#find_by, Querying#find_by_sql, ...).
      targets: SHIM_BASE_TARGETS - [[ActiveRecord::Core::ClassMethods, :find_by]],
      reaches: ["ActiveRecord::FinderMethods#exists?",
                "ActiveRecord::FinderMethods#find_by",
                "ActiveRecord::FinderMethods#take",
                "ActiveRecord::Querying#find_by_sql",
                "ActiveRecord::Relation#records"],
      coverage_of: [ConcolicKwargsToPositional, :find_by, :instance],
      fixture: -> {
        k = :concolic_finder_conds
        prev = Thread.current[k]
        s1 = shim_sql_during(k) { @r1 = User.find_by(id: 9) }
        raise "kwargs arm lost the row" unless @r1 && @r1.id == 9
        raise "kwargs arm stash: #{s1.inspect}" unless s1.any? && s1.all? { |_, c| c == { id: 9 } }
        s2 = shim_sql_during(k) { @r2 = User.find_by("username" => "shimtester") }
        raise "hash arm lost the row" unless @r2 && @r2.id == 9
        raise "hash arm stash: #{s2.inspect}" unless s2.any? && s2.all? { |_, c| c == { "username" => "shimtester" } }
        s3 = shim_sql_during(k) { @r3 = User.find_by("id = 9") }
        raise "string arm lost the row" unless @r3 && @r3.id == 9
        raise "string arm stash: #{s3.inspect}" unless s3.any? && s3.all? { |_, c| c.nil? }
        raise "exists? lost" unless User.exists?(id: 9) == true
        raise "stash leaked" unless Thread.current[k] == prev
        # differential: the same row as a direct statement (super_method +
        # call is unusable here -- JRuby raised "super: no superclass method
        # find_by" from inside Core::ClassMethods#find_by, measured).
        raw = User.find_by_sql(["SELECT * FROM users WHERE id = ?", 9]).first
        raise "differential" unless [@r1, @r2, @r3].all? { |r| r == raw }
      } },

    # Same module, prepended on ActiveRecord::Relation (core.rb:2604). Same
    # three arms and checks, driven through a Relation receiver.
    "ActiveRecord::Relation.DYNAMIC" => {
      targets: SHIM_BASE_TARGETS,
      # MEASURED (run 1, shim_results.json): the layer's super plus the
      # targets the real finder bodies reach below it.
      reaches: ["ActiveRecord::FinderMethods#exists?",
                "ActiveRecord::FinderMethods#find_by",
                "ActiveRecord::FinderMethods#take",
                "ActiveRecord::Querying#find_by_sql",
                "ActiveRecord::Relation#records"],
      coverage_of: [ConcolicKwargsToPositional, :find_by, :instance],
      fixture: -> {
        k = :concolic_finder_conds
        prev = Thread.current[k]
        rel = User.where(email: "shim@example.org")
        s1 = shim_sql_during(k) { @q1 = rel.find_by(id: 9) }
        raise "kwargs arm lost the row" unless @q1 && @q1.id == 9
        raise "kwargs arm stash: #{s1.inspect}" unless s1.any? && s1.all? { |_, c| c == { id: 9 } }
        s2 = shim_sql_during(k) { @q2 = rel.find_by("username" => "shimtester") }
        raise "hash arm lost the row" unless @q2 && @q2.id == 9
        raise "hash arm stash: #{s2.inspect}" unless s2.any? && s2.all? { |_, c| c == { "username" => "shimtester" } }
        s3 = shim_sql_during(k) { @q3 = rel.find_by("id = 9") }
        raise "string arm lost the row" unless @q3 && @q3.id == 9
        raise "string arm stash: #{s3.inspect}" unless s3.any? && s3.all? { |_, c| c.nil? }
        raise "exists? lost" unless rel.exists?(id: 9) == true
        raise "stash leaked" unless Thread.current[k] == prev
        base = rel.method(:find_by).super_method
        raise "super_method still the prepend" if base.owner == ConcolicKwargsToPositional
        raise "differential" unless base.call(id: 9).id == @q1.id
      } },

    # =======================================================================
    # ConcolicUpdateAllValueNaming#update_all (core.rb:2621-2642). A NAMING
    # layer over the declared target Relation#update_all (core.rb:1507):
    # reaching it IS its job. Arms: kwargs, single positional Hash, neither
    # (SQL string). Checked: SET values stashed at statement time and
    # restored; rows really updated (read back through raw SQL).
    # =======================================================================
    "ActiveRecord::Relation.update_all" => {
      targets: SHIM_BASE_TARGETS + [[ActiveRecord::Relation, :update_all]],
      reaches: ["ActiveRecord::Relation#update_all"],
      coverage_of: [ConcolicUpdateAllValueNaming, :update_all, :instance],
      fixture: -> {
        shim_reattach!(ConcolicUpdateAllValueNaming, :update_all)
        k = :concolic_update_all_values
        prev = Thread.current[k]
        c = ActiveRecord::Base.connection
        rel = Aspect.where(id: 951)
        s1 = shim_sql_during(k) { @n1 = rel.update_all(order_id: 7) }
        raise "kwargs arm: #{@n1} #{s1.inspect}" unless @n1 == 1 && s1.size == 1 && s1[0][1] == { order_id: 7 }
        raise "kwargs arm did not write" unless c.select_value("SELECT order_id FROM aspects WHERE id = 951").to_i == 7
        s2 = shim_sql_during(k) { @n2 = rel.update_all("order_id" => 8) }
        raise "hash arm: #{@n2} #{s2.inspect}" unless @n2 == 1 && s2.size == 1 && s2[0][1] == { "order_id" => 8 }
        raise "hash arm did not write" unless c.select_value("SELECT order_id FROM aspects WHERE id = 951").to_i == 8
        s3 = shim_sql_during(k) { @n3 = rel.update_all("order_id = 9") }
        raise "string arm: #{@n3} #{s3.inspect}" unless @n3 == 1 && s3.size == 1 && s3[0][1] == prev
        raise "string arm did not write" unless c.select_value("SELECT order_id FROM aspects WHERE id = 951").to_i == 9
        raise "stash leaked" unless Thread.current[k] == prev
      } },

    # =======================================================================
    # ConcolicWriteArgsNaming#update (core.rb:2669-2695). A NAMING layer over
    # the declared persistence target Base#update (core.rb:1537-1541). Arms:
    # kwargs and positional Hash. Checked: at the UPDATE statement
    # Thread.current[:concolic_write_args] == ["update", args, kwargs] as the
    # caller passed them; restored after; the row really changed.
    # =======================================================================
    "ActiveRecord::Base.update" => {
      targets: SHIM_BASE_TARGETS + [[ActiveRecord::Base, :update], [ActiveRecord::Base, :save]],
      # MEASURED (run 1): Base#update, then inside its real body save, the
      # uniqueness validation's exists? and the belongs_to :user load.
      reaches: ["ActiveRecord::Base#save", "ActiveRecord::Base#update",
                "ActiveRecord::FinderMethods#exists?", "ActiveRecord::Querying#find_by_sql"],
      coverage_of: [ConcolicWriteArgsNaming, :update, :instance],
      fixture: -> {
        shim_reattach!(ConcolicWriteArgsNaming, :update)
        k = :concolic_write_args
        prev = Thread.current[k]
        c = ActiveRecord::Base.connection
        s1 = shim_sql_during(k) { @u1 = SHIM_ASPECT.update(name: "Family") }
        up1 = s1.select { |q, _| q =~ /\AUPDATE/i }
        raise "kwargs arm: #{@u1.inspect} #{s1.inspect}" unless @u1 == true && up1.size == 1 &&
          up1[0][1] == ["update", [], { name: "Family" }]
        raise "kwargs arm did not write" unless c.select_value("SELECT name FROM aspects WHERE id = 950") == "Family"
        s2 = shim_sql_during(k) { @u2 = SHIM_ASPECT.update("name" => "Kin") }
        up2 = s2.select { |q, _| q =~ /\AUPDATE/i }
        raise "hash arm: #{@u2.inspect} #{s2.inspect}" unless @u2 == true && up2.size == 1 &&
          up2[0][1] == ["update", [{ "name" => "Kin" }], {}]
        raise "hash arm did not write" unless c.select_value("SELECT name FROM aspects WHERE id = 950") == "Kin"
        raise "stash leaked" unless Thread.current[k] == prev
      } },

    # =======================================================================
    # ConcolicProxyCreateArgsNaming#create (core.rb:2701-2718). A NAMING layer
    # over the declared target CollectionProxy#create. Arms: kwargs and
    # positional Hash. Checked: at the INSERT the stash is
    # ["proxy_create", args, kwargs]; restored after; row really inserted with
    # the owner FK.
    # =======================================================================
    "ActiveRecord::Associations::CollectionProxy.create" => {
      targets: SHIM_BASE_TARGETS + [[ActiveRecord::Associations::CollectionProxy, :create],
                                    [ActiveRecord::Base, :save]],
      # MEASURED (run 1). "CollectionProxy.create" (the class-level home the
      # probe also wraps) is reached from inside the real create path, not by
      # the layer, whose only call is super.
      reaches: ["ActiveRecord::Associations::CollectionProxy#create",
                "ActiveRecord::Associations::CollectionProxy.create",
                "ActiveRecord::Base#save", "ActiveRecord::FinderMethods#exists?",
                "ActiveRecord::Querying#find_by_sql"],
      coverage_of: [ConcolicProxyCreateArgsNaming, :create, :instance],
      fixture: -> {
        shim_reattach!(ConcolicProxyCreateArgsNaming, :create)
        k = :concolic_write_args
        prev = Thread.current[k]
        c = ActiveRecord::Base.connection
        proxy = SHIM_DB_USER.aspects
        s1 = shim_sql_during(k) { @a1 = proxy.create(name: "Hobby") }
        in1 = s1.select { |q, _| q =~ /\AINSERT/i }
        raise "kwargs arm: #{@a1.inspect} #{s1.inspect}" unless @a1 && @a1.persisted? && in1.size == 1 &&
          in1[0][1] == ["proxy_create", [], { name: "Hobby" }]
        s2 = shim_sql_during(k) { @a2 = proxy.create("name" => "Club") }
        in2 = s2.select { |q, _| q =~ /\AINSERT/i }
        raise "hash arm: #{@a2.inspect} #{s2.inspect}" unless @a2 && @a2.persisted? && in2.size == 1 &&
          in2[0][1] == ["proxy_create", [{ "name" => "Club" }], {}]
        n = c.select_value("SELECT COUNT(*) FROM aspects WHERE user_id = 9 AND name IN ('Hobby','Club')").to_i
        raise "rows not inserted with owner FK (#{n})" unless n == 2
        raise "stash leaked" unless Thread.current[k] == prev
      } },
  }
else
  warn "[shim_tests] loaded outside a booted diaspora app: SHIM_TESTS is empty " \
       "(definition check only; the runner loads this after config/environment)"
  SHIM_TESTS = {}.freeze
end
