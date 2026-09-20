# Agent-provided shim test bodies for people_show — keys ENUMERATED BY THE
# ENGINE (shim_extractor over this batch's targets.rb + concolic_targets.rb).
# A key missing here is a NO-TEST red, EXCEPT for the runtime rep machinery
# (kind `rep_plumbing` / `value_class`), which the RUNNER itself resolves to
# PROTOCOL against the REAL class.
#
# Built 2026-09-19 (completion-gate build). people_show had no shim tests at
# all before this file; the structure follows results3/people_stream's, but
# every body here was derived from people_show's OWN targets.rb /
# concolic_targets.rb, and the shim set differs (people_show has the
# kwargs-recovery and pluck-args prepends and the diaspora_id? boundary mock,
# which people_stream does not; it has no status-message read set, no
# MessageRenderer process shim and no declaration filter, which people_stream
# does).
#
# RULE S (DISCIPLINE §9): every shim RUNS. There are no waivers; PASS and
# PROTOCOL are the only non-blocking verdicts. Where a shim could not run
# as-is, the MINIMAL mocks it needs are named and justified: fixture ROWS in a
# real sqlite DB (data, not code-under-test) and one throwaway interceptor
# (below). No application logic is stubbed in this file.
#
# Keys deliberately absent — the runner returns PROTOCOL for them, decided
# against the REAL class, not from this prose (verified by running the runner
# with an empty SHIM_TESTS before this file was written):
#   user.id, person.id, obj.read_attribute, obj._read_attribute,
#   obj.concolic_attrs, obj.concolic_note, obj.attributes, obj.write_attribute,
#   obj._write_attribute, obj.inspect, ActiveRecord::Relation.DYNAMIC
#
# DUPLICATE KEYS — stated, because the engine's key model cannot express it.
# `user.diaspora_handle`, `user.language`, `user.gender` and `user.blocks` are
# each extracted TWICE: once from `apply_user_overrides!` (targets.rb:641-658,
# the anon `symbolic_user` principal) and once from `signed_in_user`
# (targets.rb:727-741, the auth_* principal, rewritten by the F6 repair).
# SHIM_TESTS is keyed by "<owner>.<method>", so ONE entry answers both rows and
# `coverage_of` can name only one body. Each such fixture therefore RUNS AND
# ASSERTS BOTH bodies, and points `coverage_of` at the `signed_in_user` one —
# the body the auth_* half of the live corpus actually executes. The assertions
# are the evidence for both; the coverage instrument measures one.

# ---------------------------------------------------------------------------
# MINIMAL FIXTURE DB (Rule S rule 2). Real sqlite + the app schema through the
# project's own concrete_env helper, then ROWS by raw INSERT. Data only — raw
# seeding deliberately avoids running app callbacks, which belong to WRITE
# paths, not this read endpoint.
# ---------------------------------------------------------------------------
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
CompletionChecker::ConcreteEnv.setup!(
  db: "/home/dev/project/reports/diaspora/results3/people_show/shim_tests.sqlite3")

CompletionChecker::ConcreteEnv.insert("users", id: 9, username: "shimtester",
  email: "shim@example.org", encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
  language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
CompletionChecker::ConcreteEnv.insert("people", id: 1, guid: "shimguid000000001",
  diaspora_handle: "shim@localhost", serialized_public_key: "K1", owner_id: 9,
  closed_account: 0, fetch_status: 0)
CompletionChecker::ConcreteEnv.insert("people", id: 2, guid: "otherguid00000002",
  diaspora_handle: "other@remote.example", serialized_public_key: "K2", owner_id: nil,
  closed_account: 0, fetch_status: 0)
CompletionChecker::ConcreteEnv.insert("profiles", id: 11, person_id: 1,
  first_name: "Shim", last_name: "Tester", searchable: 1, nsfw: 0, public_details: 0)
CompletionChecker::ConcreteEnv.insert("profiles", id: 12, person_id: 2,
  first_name: "Other", last_name: "Person", searchable: 1, nsfw: 0, public_details: 0)
CompletionChecker::ConcreteEnv.insert("posts", id: 100, author_id: 2,
  guid: "postguid1000000001", type: "StatusMessage", text: "a public post",
  public: true, comments_count: 0)
CompletionChecker::ConcreteEnv.insert("aspects", id: 950, user_id: 9,
  name: "Friends", order_id: 1)
CompletionChecker::ConcreteEnv.insert("contacts", id: 800, user_id: 9, person_id: 2,
  sharing: true, receiving: true)
CompletionChecker::ConcreteEnv.insert("blocks", id: 810, user_id: 9, person_id: 2)
# `apply_user_overrides!`'s `contact_for` body pins `user_id: 1` literally
# (targets.rb:652-654). That literal is on the ANON `symbolic_user` principal,
# which is never wired as current_user, and is untouched by the F6 repair
# (which was about `signed_in_user`) — so the fixture must carry a row the
# body can actually find, rather than the body being changed to suit the test.
CompletionChecker::ConcreteEnv.insert("contacts", id: 801, user_id: 1, person_id: 2,
  sharing: true, receiving: true)
# `tags`/`taggings` back the profile-tag pluck the batch recovers (targets.rb
# §1b). Rows only; the pluck body under test builds its own relation.
CompletionChecker::ConcreteEnv.insert("tags", id: 900, name: "shimtag",
  taggings_count: 1)
CompletionChecker::ConcreteEnv.insert("taggings", id: 910, tag_id: 900,
  taggable_id: 11, taggable_type: "Profile", context: "tags")

Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

SHIM_DB_USER   = User.find(9)
SHIM_DB_PERSON = Person.find(2)
SHIM_DB_SELF   = Person.find(1)

# ---------------------------------------------------------------------------
# The batch's own code, loaded exactly as run_dse.rb loads it.
# ---------------------------------------------------------------------------
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/results3/people_show/concolic_targets.rb"
require "/home/dev/project/reports/diaspora/results3/people_show/targets.rb"

# ---------------------------------------------------------------------------
# THE ONE NON-DATA MOCK IN THIS FILE, named and justified.
#
# Two shims the engine enumerates — the SingularAssociation loaded-target memo
# (concolic_targets.rb W3-memo) and the `Gon.preloads` accessor (X6b-preloads)
# — are ANONYMOUS `Module.new` bodies created INSIDE
# `ConcolicTargets.install!`. There is no way to reach those bodies without
# running `install!`, and a shim test may never declare a target (that would
# replace the very app code these tests must run).
#
# `install!` reaches real classes through EXACTLY ONE channel —
# `interceptor.declare_target(...)`, which is `klass.define_method(method)`
# (call_interceptor.rb) — plus the two prepends above. So handing `install!` a
# THROWAWAY interceptor whose `declare_target` records and returns nil installs
# the two real shim bodies and declares NOTHING: no app method is replaced, and
# every body these tests exercise is the real one.
#
# Verified in the file rather than assumed: `grep -n "\.prepend(\|define_method"`
# over this batch's concolic_targets.rb finds only those two anonymous prepends
# outside declare_target (plus the named ConcolicKwargsToPositional prepends,
# which are themselves shims under test below).
# ---------------------------------------------------------------------------
SHIM_FAKE_INTERCEPTOR = Object.new
def SHIM_FAKE_INTERCEPTOR.declare_target(_klass, _method, **_kw)
  (@declared ||= []) << [_klass.to_s, _method]
  nil
end
def SHIM_FAKE_INTERCEPTOR.declared
  @declared ||= []
end
ConcolicTargets.install!(SHIM_FAKE_INTERCEPTOR)
raise "throwaway interceptor saw no declarations — install! did not run" if SHIM_FAKE_INTERCEPTOR.declared.empty?

SHIM_SINGULAR_MEMO = ActiveRecord::Associations::SingularAssociation.ancestors
                       .find { |m| m.instance_methods(false) == [:find_target] && m.name.nil? }
raise "W3-memo module not installed by install!" unless SHIM_SINGULAR_MEMO
SHIM_GON_MEMO = ::Gon.singleton_class.ancestors
                  .find { |m| m.instance_methods(false) == [:preloads] && m.name.nil? }
raise "GonPreloads shim not installed by install!" unless SHIM_GON_MEMO

# ---------------------------------------------------------------------------
# INSTRUMENT LIMIT, MEASURED AND WORKED AROUND (not waived) — identical to the
# one documented in people_stream/shim_tests.rb, because people_show carries
# the same W3-memo.
#
# `TargetCallProbe.capture` wraps a target by `home.instance_method(meth)` +
# `home.send(:define_method, meth)` on the OWNER module. When the boundary has
# PREPENDED a module that also defines that method — exactly what the W3-memo
# does to `SingularAssociation#find_target` — `instance_method` resolves
# THROUGH the prepend, so the probe's captured "original" IS the memo, while
# the memo's own `super` lands on the probe wrapper: infinite recursion, a JVM
# StackOverflowError.
#
# The fix is to make the ancestry the probe sees the REAL one: detach the memo
# body from the module (keeping the UnboundMethod, so nothing is lost) and let
# the ONE test that is about the memo re-attach it from INSIDE its own fixture,
# i.e. AFTER `capture` has captured the real `find_target`. The memo then runs
# for real, its `super` reaches the real body through the probe, and there is
# no cycle.
# ---------------------------------------------------------------------------
SHIM_MEMO_BODY = SHIM_SINGULAR_MEMO.instance_method(:find_target)
SHIM_SINGULAR_MEMO.send(:remove_method, :find_target)

# THE SAME INSTRUMENT LIMIT, SECOND INSTANCE — found by running this file
# (people_show only; people_stream has no kwargs-recovery prepend, which is
# why its copy documents the memo case alone).
#
# `PeopleShowFindByKwargs` is prepended onto ActiveRecord::Relation,
# ActiveRecord::Base.singleton_class AND ActiveRecord::FinderMethods, and
# AR_TARGETS contains `[ActiveRecord::FinderMethods, :find_by]`. So
# `capture` does `ActiveRecord::FinderMethods.instance_method(:find_by)`,
# which resolves THROUGH the prepend and captures PSFBK#find_by as the
# "original"; PSFBK#find_by's own `super` then lands on the probe wrapper,
# which calls the captured original — PSFBK#find_by again. Measured: a JVM
# StackOverflowError at 2 MB and again at 64 MB, whose trace is the two-frame
# cycle targets.rb:110 (`find_by`) <-> targets.rb:99 (`stash_finder_kwargs`).
#
# Same remedy as the memo: detach the three wrapper methods so the ancestry
# `capture` sees is the REAL one, keep the UnboundMethods so nothing is lost,
# and let the two tests that are ABOUT this module re-attach them from INSIDE
# their own fixtures — after `capture` has already taken the real
# `find_by`/`exists?` as its originals — then detach again so the remaining
# fixtures are unaffected. `stash_finder_kwargs` itself is NOT detached: it is
# the body under test and nothing probes it.
SHIM_PSFBK_METHODS = %i[find_by find_by! exists?].freeze
SHIM_PSFBK_BODIES = SHIM_PSFBK_METHODS.each_with_object({}) do |m, h|
  h[m] = PeopleShowFindByKwargs.instance_method(m)
  PeopleShowFindByKwargs.send(:remove_method, m)
end.freeze

# Re-attach for the duration of a block, then detach again. Used only by the
# two `stash_finder_kwargs` entries.
def shim_with_psfbk
  SHIM_PSFBK_METHODS.each do |m|
    PeopleShowFindByKwargs.send(:define_method, m, SHIM_PSFBK_BODIES[m])
  end
  yield
ensure
  SHIM_PSFBK_METHODS.each do |m|
    PeopleShowFindByKwargs.send(:remove_method, m) if
      PeopleShowFindByKwargs.instance_methods(false).include?(m)
  end
end

# ---------------------------------------------------------------------------
# The NAMED prepends. `PeopleTargets.install!` is deliberately NOT called: it
# also `define_singleton_method`s `image_path` / `path_to_image` on
# `ActionController::Base.helpers`, and those two stubs are themselves shims
# under test here — the claim being that the REAL Rails helper bodies they
# stand in for reach no target, which requires the real helpers to stay
# un-stubbed for the whole run. Prepending the named modules directly is
# byte-identically what install! does to those classes.
#
# `PeopleShowSymParams.install!` IS called: its entire body is the same three
# prepends and a warn (targets.rb:946-951) — it stubs nothing.
# ---------------------------------------------------------------------------
[ActiveRecord::Relation, ActiveRecord::Base.singleton_class].each do |k|
  k.prepend(PeopleShowFindByKwargs) unless k.ancestors.include?(PeopleShowFindByKwargs)
end
unless ActiveRecord::FinderMethods < PeopleShowFindByKwargs
  ActiveRecord::FinderMethods.prepend(PeopleShowFindByKwargs)
end
unless ActiveRecord::Relation < PeopleShowPluckArgs
  ActiveRecord::Relation.prepend(PeopleShowPluckArgs)
end
Person.prepend(PersonSymAssociations) unless Person.ancestors.include?(PersonSymAssociations)
PeopleShowSymParams.install!

# A symbolic representative of each kind the batch builds, for the arms of the
# shim bodies only a rep can reach (`respond_to?(:concolic_attrs)` true).
SHIM_SYM_PERSON = ConcolicTargets.symbolic_instance(Person, "SHIMTEST_person", "shim test")
SHIM_SYM_USER   = ConcolicTargets.symbolic_instance(User,   "SHIMTEST_user",   "shim test")
SHIM_SYM_POST   = ConcolicTargets.symbolic_instance(Post,   "SHIMTEST_post",   "shim test")

# targets.rb §4 `apply_user_overrides!`, applied to a REAL User and Person.
# Giving it real records rather than a rep is what makes the bodies RUNNABLE:
# a rep's `id` is a SymbolicInt and Arel calls `#to_i` on it — a ScriptError
# the runner cannot catch. The bodies are identical either way; none of them
# branches on the receiver.
SHIM_OVR_PERSON = Person.find(1)
SHIM_OVR_USER   = PeopleTargets.apply_user_overrides!(User.find(9), SHIM_OVR_PERSON)

# targets.rb `signed_in_user`, the F6-repaired auth_* principal. Built on the
# same real row for the same reason. Its `blocks` body binds the SYMBOLIC
# principal id, so the receiver must answer `id` — a real row does.
SHIM_SIGNED_USER = PeopleTargets.signed_in_user("SHIMTEST")

AR_TARGETS = [
  [ActiveRecord::FinderMethods, :find_by],
  [ActiveRecord::FinderMethods, :find],
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::FinderMethods, :last],
  [ActiveRecord::FinderMethods, :take],
  [ActiveRecord::FinderMethods, :exists?],
  [ActiveRecord::Calculations, :count],
  [ActiveRecord::Calculations, :sum],
  [ActiveRecord::Calculations, :pluck],
  [ActiveRecord::Relation, :records],
  [ActiveRecord::Relation, :to_a],
  [ActiveRecord::Relation, :to_ary],
  [ActiveRecord::Associations::CollectionProxy, :records],
  [ActiveRecord::Associations::CollectionProxy, :load_target],
  [ActiveRecord::Associations::SingularAssociation, :find_target],
]

SHIM_TESTS = {
  # =========================================================================
  # targets.rb §B-kwargs — PeopleShowFindByKwargs. A NAMING/RECOVERY layer:
  # it stashes the finder's conditions in a thread-local and calls `super`, so
  # reaching the finder IS its job -> `reaches:` equality, not zero targets.
  # Both extracted rows (`target_klass.` from the Relation /
  # Base.singleton_class loop, `fm_mod.` from the FinderMethods prepend) are
  # THE SAME MODULE BODY; each key gets its own entry so neither is a NO-TEST,
  # and both cover the same method, which is the honest description.
  #
  # Both arms of `stash_finder_kwargs` are exercised: (a) native kwargs, and
  # (b) the CK2P-converted trailing-Hash form that people_show runs actually
  # produce, plus (c) the no-conditions arm that yields without stashing.
  # =========================================================================
  "target_klass.stash_finder_kwargs" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::FinderMethods#find_by",
              "ActiveRecord::FinderMethods#take",
              "ActiveRecord::FinderMethods#exists?",
              "ActiveRecord::Relation#records"],
    coverage_of: [PeopleShowFindByKwargs, :stash_finder_kwargs, :instance],
    fixture: -> {
      shim_with_psfbk do
        Thread.current[:people_show_find_by_kwargs] = nil
        # (a) native kwargs form
        got = Person.find_by(guid: "otherguid00000002")
        raise "find_by lost the row" unless got && got.id == 2
        # (b) trailing positional Hash (the CK2P-converted form)
        got2 = Person.all.find_by({ "guid" => "otherguid00000002" })
        raise "positional-hash form lost the row" unless got2 && got2.id == 2
        # (c) the no-conditions arm: yields without stashing
        Person.all.exists?
        raise "thread-local leaked" unless Thread.current[:people_show_find_by_kwargs].nil?
      end
    } },
  "fm_mod.stash_finder_kwargs" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::FinderMethods#find_by",
              "ActiveRecord::FinderMethods#take",
              "ActiveRecord::Relation#records"],
    coverage_of: [PeopleShowFindByKwargs, :stash_finder_kwargs, :instance],
    fixture: -> {
      shim_with_psfbk do
        Thread.current[:people_show_find_by_kwargs] = nil
        # a STRING filter, deliberately: `where(closed_account: false)` hit
        # the documented JDBC boolean-quoting mismatch (concrete_env.rb's
        # `quote` note) and matched no row, which is a fixture artefact, not
        # anything about the body under test.
        rel = Person.where(diaspora_handle: "other@remote.example")
        got = rel.find_by(guid: "otherguid00000002")
        raise "FinderMethods arm lost the row" unless got && got.id == 2
        raise "thread-local leaked" unless Thread.current[:people_show_find_by_kwargs].nil?
      end
    } },

  # =========================================================================
  # targets.rb §1b — PeopleShowPluckArgs#pluck. Same shape: records the real
  # column list in a thread-local (the interceptor's call_args zip is lossy
  # for splat methods) and calls `super`, so `reaches:` equality over the real
  # pluck. The `ensure` arm restoring the previous value is exercised by the
  # nested call.
  # =========================================================================
  "rel.pluck" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::Calculations#pluck"],
    coverage_of: [PeopleShowPluckArgs, :pluck, :instance],
    fixture: -> {
      Thread.current[:people_show_pluck_cols] = nil
      names = ActsAsTaggableOn::Tag.all.pluck(:name)
      raise "pluck lost the row: #{names.inspect}" unless names.include?("shimtag")
      raise "ensure arm did not restore" unless Thread.current[:people_show_pluck_cols].nil?
      # multi-column + flatten arm
      ActsAsTaggableOn::Tag.all.pluck(:id, :name)
      raise "ensure arm did not restore (multi)" unless Thread.current[:people_show_pluck_cols].nil?
    } },

  # =========================================================================
  # targets.rb §1 — PersonSymAssociations#posts. A GUARDED DISPATCHER: the rep
  # arm builds a scoped relation (no statement), the real arm is `super`, the
  # real has_many reader. Both arms run.
  # =========================================================================
  "Person.posts" => {
    targets: AR_TARGETS,
    coverage_of: [PersonSymAssociations, :posts, :instance],
    fixture: -> {
      rel = SHIM_SYM_PERSON.posts                     # rep arm
      raise "not a relation: #{rel.class}" unless rel.is_a?(ActiveRecord::Relation)
      raise "wrong model: #{rel.klass}" unless rel.klass == Post
      proxy = SHIM_DB_PERSON.posts                    # real arm: `super`
      raise "super lost" unless proxy.respond_to?(:klass) && proxy.klass == Post
    } },

  # =========================================================================
  # targets.rb §3 — the asset-path stubs. They stand in for the REAL Rails
  # helpers, so what must be proven is that the REAL bodies reach no target.
  # (This is why PeopleTargets.install! is not called in this file.)
  # =========================================================================
  "h.image_path" => {
    targets: AR_TARGETS,
    coverage_of: [ActionView::Helpers::AssetUrlHelper, :image_path, :instance],
    fixture: -> { ActionController::Base.helpers.image_path("user/default.png") } },
  "h.path_to_image" => {
    targets: AR_TARGETS,
    coverage_of: [ActionView::Helpers::AssetUrlHelper, :path_to_image, :instance],
    fixture: -> { ActionController::Base.helpers.path_to_image("user/default.png") } },

  # =========================================================================
  # targets.rb §B — PeopleShowSymParams::DiasporaIdBoundaryMock#diaspora_id?.
  # A guarded dispatcher over a NON-AR boundary decision: the symbolic arm runs
  # the REAL Validation::Rule::DiasporaId logic against the concrete seed and
  # wraps the outcome as a seedable symbolic bool; the non-symbolic arm is
  # `super`. Both arms run, and both outcomes of the real validator are
  # exercised (a handle-shaped value and a non-handle-shaped one) so the
  # `real_result` conjunction is covered on both sides. Zero targets: the body
  # issues no query.
  # =========================================================================
  "PeopleController.diaspora_id?" => {
    targets: AR_TARGETS,
    coverage_of: [PeopleShowSymParams::DiasporaIdBoundaryMock, :diaspora_id?, :instance],
    fixture: -> {
      ctrl = PeopleController.new
      handle = PeopleShowSymParams.symbolic_username("alice@localhost")
      raise "handle-shaped value not recognised" unless ctrl.send(:diaspora_id?, handle) == true
      plain = PeopleShowSymParams.symbolic_username("notahandle")
      raise "non-handle should be false" if ctrl.send(:diaspora_id?, plain) == true
      blank = PeopleShowSymParams.symbolic_username("   ")
      ctrl.send(:diaspora_id?, blank)                 # the lstrip.empty? arm
      ctrl.send(:diaspora_id?, "alice@localhost")     # non-symbolic arm: `super`
    } },

  # =========================================================================
  # targets.rb §B — UserSymPersonAssociation#person. Guarded dispatcher: the
  # rep arm routes through the REAL has_one reader (P-10) so it DOES reach
  # SingularAssociation#find_target; the real arm is `super`.
  # =========================================================================
  "User.person" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::Associations::SingularAssociation#find_target"],
    coverage_of: [PeopleShowSymParams::UserSymPersonAssociation, :person, :instance],
    fixture: -> {
      # The rep arm is driven on a REAL User carrying only the rep MARKER
      # (`concolic_attrs`): the arm runs the real association reader, and a
      # rep's id is a SymbolicInt on which Arel calls `#to_i` — the
      # uncatchable ScriptError this file documents for SHIM_OVR_USER. The
      # body does not branch on the receiver beyond the marker.
      urep = User.find(9)
      urep.define_singleton_method(:concolic_attrs) { {} }
      p = urep.person
      raise "rep arm gave #{p.inspect}" unless p && p.id == 1
      u = User.find(9)                                # real arm: `super`
      raise "super lost person" unless u.person && u.person.id == 1
      # THE FALLBACK ARM (B-2 repair, targets.rb:886-927). Without it the body
      # measured 40%, missing exactly the fallback's own lines
      # (908/914/917/924/926/927).
      #
      # FAULT INJECTION, named and justified (Rule S rule 3). The arm is
      # `rescue StandardError` around `association(:person).reader`. In the
      # live runs the reader is answered by the W3 find_target DECLARED
      # TARGET, so it succeeds and this arm never runs; in this rig there is
      # no declared target, so the real AR reader runs — and on a full
      # symbolic rep it fails with NotImplementedError, which is a
      # ScriptError, NOT a StandardError, so it is not caught and escapes the
      # runner entirely (measured: it aborted the whole run). The only way to
      # reach a `rescue StandardError` is for the collaborator to raise a
      # StandardError, so that is what is injected — on the COLLABORATOR
      # (`#association`, ActiveRecord's), never on the body under test, which
      # runs for real from its first line to its last.
      mk_failing = lambda do |sym_id|
        u2 = User.find(9)
        u2.define_singleton_method(:concolic_attrs) { {} }
        u2.define_singleton_method(:association) { |*|
          raise StandardError, "shim: forced association-reader failure"
        }
        if sym_id
          # drive the INNER `rescue Exception -> nil` (line 924): a symbolic
          # owner id makes render_relation_sql raise, so the note falls back
          # to the prose form on line 926.
          sid = SymbolicInt.new(9, name: "SHIMTEST_owner_id", note: "shim test")
          u2.define_singleton_method(:[]) { |k| k.to_s == "id" ? sid : super(k) }
        end
        u2
      end
      fb = mk_failing.call(false).person        # fallback, note RENDERS
      raise "fallback arm produced nothing" if fb.nil?
      raise "fallback did not mint a rep" unless fb.respond_to?(:concolic_attrs)
      raise "fallback note not a SELECT: #{fb.concolic_note.inspect}" unless
        fb.concolic_note.to_s.start_with?("SELECT")
      # MEASURED CORRECTION: a symbolic owner id does NOT make the renderer
      # raise — rendering `$$(SYM...)` inline is exactly what this batch's
      # ConcolicSymbolicToSql visitor exists to do, so the B-2 note still
      # comes out as a SELECT. That is the repair working, and the assertion
      # says so.
      fb2 = mk_failing.call(true).person        # symbolic owner id, still renders
      raise "inner-rescue arm produced nothing" if fb2.nil?
      raise "symbolic-owner note should still render: #{fb2.concolic_note.inspect}" unless
        fb2.concolic_note.to_s.start_with?("SELECT")
      # THE INNER `rescue Exception -> nil` (line 924) and the prose branch of
      # line 926. The comment there names its cause: "a symbolic wall raises
      # NotImplementedError < ScriptError, which `rescue StandardError` would
      # let escape". Nothing reachable from a fixture makes the real renderer
      # fail that way any more, so the fault is injected into the COLLABORATOR
      # (`ConcolicTargets.render_relation_sql`) for exactly one call, and
      # restored in `ensure`. The body under test is untouched and runs whole.
      orig_rrs = ConcolicTargets.method(:render_relation_sql)
      ConcolicTargets.define_singleton_method(:render_relation_sql) do |*|
        raise NotImplementedError, "shim: forced renderer failure"
      end
      begin
        fb3 = mk_failing.call(false).person
        raise "renderer-failure arm produced nothing" if fb3.nil?
        raise "renderer-failure arm must fall back to the prose note: " \
              "#{fb3.concolic_note.inspect}" unless
          fb3.concolic_note.to_s == "User#person (has_one)"
      ensure
        ConcolicTargets.define_singleton_method(:render_relation_sql, orig_rrs)
      end
    } },

  # =========================================================================
  # targets.rb §B — PostSymLocation#location. Guarded dispatcher, rep arm
  # returns nil, real arm is `super` (base Post has no location column, so the
  # real arm is the AR association reader on a StatusMessage row).
  # =========================================================================
  "Post.location" => {
    targets: AR_TARGETS,
    # MEASURED (the first run reported FAIL-REACHES and named the other
    # three): `Post.find(100)` is itself a finder, and the real `location`
    # has_one reader materialises through records/take.
    reaches: ["ActiveRecord::Associations::SingularAssociation#find_target",
              "ActiveRecord::FinderMethods#find",
              "ActiveRecord::FinderMethods#take",
              "ActiveRecord::Relation#records"],
    coverage_of: [PeopleShowSymParams::PostSymLocation, :location, :instance],
    fixture: -> {
      raise "rep arm must be nil" unless SHIM_SYM_POST.location.nil?
      Post.find(100).location                         # real arm: `super`
    } },

  # =========================================================================
  # targets.rb §4 — apply_user_overrides!. Each singleton runs on a real User.
  # =========================================================================
  "user.guid" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :guid, :singleton],
    fixture: -> { raise "guid" unless SHIM_OVR_USER.guid == "abc123" } },
  "user.person" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :person, :singleton],
    fixture: -> {
      raise "person override lost" unless SHIM_OVR_USER.person.equal?(SHIM_OVR_PERSON)
    } },
  "user.person_id" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :person_id, :singleton],
    fixture: -> { raise "person_id" unless SHIM_OVR_USER.person_id == 1 } },
  "user.contacts" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :contacts, :singleton],
    fixture: -> {
      rel = SHIM_OVR_USER.contacts
      raise "not a Contact relation: #{rel.klass}" unless rel.klass == Contact
    } },
  "user.aspects" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :aspects, :singleton],
    fixture: -> {
      rel = SHIM_OVR_USER.aspects
      raise "not an Aspect relation: #{rel.klass}" unless rel.klass == Aspect
    } },
  "user.contact_for" => {
    targets: AR_TARGETS,
    # the `includes(person: :profile)` preload materializes through #to_ary
    reaches: ["ActiveRecord::FinderMethods#find_by",
              "ActiveRecord::FinderMethods#take",
              "ActiveRecord::Relation#records",
              "ActiveRecord::Relation#to_ary"],
    coverage_of: [SHIM_OVR_USER, :contact_for, :singleton],
    fixture: -> {
      got = SHIM_OVR_USER.contact_for(SHIM_DB_PERSON)
      # row 801 (user_id 1) is the one this body's pinned `user_id: 1` selects
      raise "contact_for missed the fixture row: #{got.inspect}" unless got && got.id == 801
    } },
  "user.block_for" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :block_for, :singleton],
    fixture: -> {
      rel = SHIM_OVR_USER.block_for(SHIM_DB_PERSON)
      raise "block_for is not a relation: #{rel.inspect}" unless rel.is_a?(ActiveRecord::Relation)
    } },
  "user.posts_from" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :posts_from, :singleton],
    fixture: -> {
      rel = SHIM_OVR_USER.posts_from(SHIM_DB_PERSON)
      raise "not a Post relation: #{rel.klass}" unless rel.klass == Post
    } },

  # =========================================================================
  # DUPLICATE-KEY ENTRIES (see the header). Each runs and asserts BOTH the
  # `apply_user_overrides!` body and the `signed_in_user` body; `coverage_of`
  # names the `signed_in_user` one, which the auth_* corpus executes.
  # =========================================================================
  # P-7 repair (targets.rb signed_in_user). NOT claimed as `real_class: "User"`
  # protocol: `post_default_public` IS a users column, so that claim would be
  # accepted by the runner — but this body is NOT a plain column reader. It
  # records a path condition and returns the CONCRETE bool, precisely so the
  # app's bare-truthiness `if post_default_public` (user.rb:272) branches on a
  # real boolean instead of on an always-truthy SymbolicBool. A body with
  # behaviour of its own gets a real test.
  "user.post_default_public" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_SIGNED_USER, :post_default_public, :singleton],
    fixture: -> {
      v = SHIM_SIGNED_USER.post_default_public
      # THE POINT OF THE REPAIR: a real Ruby boolean, so `if` works. A
      # SymbolicBool here is the defect this shim exists to remove.
      raise "not a concrete boolean: #{v.class}" unless v == true || v == false
      raise "must not leak a SymbolicVar" if v.is_a?(SymbolicVar)
      # the underlying var is still symbolic and still seedable/flippable
      pdp = SHIM_SIGNED_USER.concolic_attrs["post_default_public"]
      raise "underlying column var is not symbolic" unless pdp.is_a?(SymbolicVar)
      raise "reader disagrees with the symbolic value" unless v == pdp.value
      SHIM_SIGNED_USER.post_default_public   # second call: same answer, no drift
    } },

  "user.diaspora_handle" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_SIGNED_USER, :diaspora_handle, :singleton],
    fixture: -> {
      raise "signed_in body" unless SHIM_SIGNED_USER.diaspora_handle == "alice@localhost"
      raise "overrides body" unless SHIM_OVR_USER.diaspora_handle == "alice@example.org"
    } },
  "user.language" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_SIGNED_USER, :language, :singleton],
    fixture: -> {
      raise "signed_in body" unless SHIM_SIGNED_USER.language == "en"
      raise "overrides body" unless SHIM_OVR_USER.language == "en"
    } },
  "user.gender" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_SIGNED_USER, :gender, :singleton],
    fixture: -> {
      raise "signed_in body" unless SHIM_SIGNED_USER.gender == ""
      raise "overrides body" unless SHIM_OVR_USER.gender == ""
    } },
  # The F6 repair rewrote the signed_in body from `Block.where(user_id: 1)` to
  # `Block.where(user_id: id)`, so the claim tested here is precisely that the
  # bind follows the principal rather than a pinned literal.
  "user.blocks" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_SIGNED_USER, :blocks, :singleton],
    fixture: -> {
      rel = SHIM_SIGNED_USER.blocks
      raise "not a Block relation: #{rel.klass}" unless rel.klass == Block
      # NOT `rel.to_sql`: the principal's id is now a SymbolicInt (that IS the
      # F6 repair), and rendering drives Arel -> ActiveModel::Type::Integer
      # -> `SymbolicInt#to_i`, a NotImplementedError by design
      # (src/ruby_runtime/int.rb:34). Measured here on the first run of this
      # file. Read the where-clause PREDICATES instead — no rendering, and a
      # sharper claim than a substring match on SQL text.
      preds = rel.where_clause.send(:predicates)
      cols = preds.map { |pr|
        (pr.respond_to?(:left) && pr.left.respond_to?(:name)) ? pr.left.name.to_s : nil
      }.compact
      raise "signed_in blocks lost the user_id scope: #{cols.inspect}" unless cols.include?("user_id")
      # THE F6 CLAIM, tested directly: the value this body binds is the
      # principal's own id, and that id is SYMBOLIC — not the literal 1 the
      # pre-repair body used.
      pid = SHIM_SIGNED_USER.id
      raise "F6: the principal id is not symbolic (#{pid.class})" unless pid.is_a?(SymbolicVar)
      unwrap = lambda do |r|
        r = r.value if r.is_a?(Arel::Nodes::BindParam)          # -> QueryAttribute
        r = r.value_before_type_cast if r.respond_to?(:value_before_type_cast)
        r
      end
      bound = preds.map { |pr| pr.respond_to?(:right) ? pr.right : nil }.compact.map(&unwrap)
      # NOTE the check is on the TYPE, not the value: `SymbolicInt#==` compares
      # by value, so `bound.include?(1)` is TRUE for the symbolic principal
      # whose seed happens to be 1 (measured — this assertion failed that way
      # on the first run). What F6 is about is that the bind is a symbolic
      # variable rather than a baked-in Integer.
      raise "F6: blocks bound a plain Integer literal: #{bound.inspect}" if
        bound.any? { |b| b.is_a?(::Integer) }
      raise "blocks did not bind this principal: #{bound.inspect}" unless
        bound.any? { |b| b.equal?(pid) }
      rel2 = SHIM_OVR_USER.blocks                     # the overrides body
      raise "not a Block relation: #{rel2.klass}" unless rel2.klass == Block
    } },

  # =========================================================================
  # concolic_targets.rb symbolic_instance — the rep singletons that are NOT
  # protocol: each stands in for a REAL method with a body of its own, so the
  # REAL body is what runs here (Rule S rule 4).
  # =========================================================================
  "obj.image_url" => {
    targets: AR_TARGETS,
    coverage_of: [Profile, :image_url, :instance],
    fixture: -> {
      p1 = Profile.new
      p1.image_url(:thumb_small)
      p2 = Profile.new
      p2[:image_url] = "https://example.org/x.png"
      p2[:image_url_small] = "https://example.org/s.png"
      p2.image_url(:thumb_small)
      p2.image_url(:thumb_medium)
      p2[:image_url_medium] = "https://example.org/m.png"
      p2.image_url(:thumb_medium)
      p2.image_url
      camo = AppConfig.privacy.camo
      orig = camo.respond_to?(:proxy_remote_pod_images?) ? camo.proxy_remote_pod_images? : nil
      camo.define_singleton_method(:proxy_remote_pod_images?) { true }
      begin
        p2.image_url(:thumb_small)
      ensure
        camo.define_singleton_method(:proxy_remote_pod_images?) { orig }
      end
    } },
  "obj.hidden_shareables" => {
    targets: AR_TARGETS,
    coverage_of: [User, :hidden_shareables, :instance],
    fixture: -> {
      u = User.new
      u.hidden_shareables                       # the nil arm of `||=`
      u[:hidden_shareables] = { "Post" => ["1"] }
      u.hidden_shareables                       # the present arm
    } },
  # base `Post` defines no `post_location` at all (only Reshare /
  # StatusMessage do), and this reader is installed ONLY on base-Post reps
  # (`klass.name.split('::').last == "Post"`). A method the real class does not
  # define is the rep's own machinery — stated as a FACT the runner CHECKS
  # against the real class, not as prose.
  "obj.post_location" => { real_class: "Post" },

  # =========================================================================
  # concolic_targets.rb — ConcolicKwargsToPositional on
  # ActiveRecord::Base.singleton_class. A CLASS receiver: `Model.find_by!`
  # resolves to Core::ClassMethods#find_by! (`find_by(*args) || raise`), NOT
  # FinderMethods. The shim folds kwargs into a trailing positional Hash and
  # calls super, so the claim is that the REAL body it fronts reaches exactly
  # the declared target.
  # =========================================================================
  "ActiveRecord::Base.singleton_class.DYNAMIC" => {
    targets: [[ActiveRecord::Core::ClassMethods, :find_by!]],
    reaches: ["ActiveRecord::Core::ClassMethods#find_by!"],
    coverage_of: [ActiveRecord::Core::ClassMethods, :find_by!, :instance],
    fixture: -> { Person.find_by!(guid: "otherguid00000002") } },

  # =========================================================================
  # concolic_targets.rb W3-memo — SingularAssociation#find_target loaded-target
  # memo. A DISPATCH layer: reaching `find_target` IS its job, so the claim is
  # `reaches:` equality plus 100% of its own body — the label-reset arm, the
  # memo MISS (super) and the memo HIT (cached).
  # =========================================================================
  "ActiveRecord::Associations::SingularAssociation.find_target" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::Associations::SingularAssociation#find_target"],
    coverage_of: [SHIM_SINGULAR_MEMO, :find_target, :instance],
    fixture: -> {
      # re-attach the real memo body now that `capture` holds the REAL
      # find_target as its original (see INSTRUMENT LIMIT above)
      SHIM_SINGULAR_MEMO.send(:define_method, :find_target, SHIM_MEMO_BODY)
      Thread.current[:concolic_loaded_target_memo] = nil
      CallInterceptor.instance.instance_variable_set(:@current_run_label, "SHIMTEST_A")
      u = User.find(9)
      a = u.association(:person)
      a.reset
      first = a.send(:find_target)                    # label reset + memo MISS
      raise "find_target miss: #{first.inspect}" unless first && first.id == 1
      second = a.send(:find_target)                   # memo HIT (no super)
      raise "memo did not return the cached target" unless second.equal?(first)
      CallInterceptor.instance.instance_variable_set(:@current_run_label, "SHIMTEST_B")
      third = a.send(:find_target)                    # label CHANGED -> reset arm
      raise "label reset lost the target" unless third && third.id == 1
      CallInterceptor.instance.instance_variable_set(:@current_run_label, nil)
    } },

  # =========================================================================
  # concolic_targets.rb X6b-preloads — the class-level `Gon.preloads` accessor.
  # Both arms (fresh -> {}, memo hit). Pure Hash bookkeeping: zero targets.
  # =========================================================================
  "::Gon.singleton_class.preloads" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_GON_MEMO, :preloads, :instance],
    fixture: -> {
      ::Gon.instance_variable_set(:@concolic_preloads, nil)
      first = ::Gon.preloads
      raise "preloads: #{first.inspect}" unless first == {}
      first[:person] = [1]
      raise "memo lost" unless ::Gon.preloads[:person] == [1]
      ::Gon.instance_variable_set(:@concolic_preloads, {})
    } },
}
