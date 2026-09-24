# Agent-provided shim test bodies for people_stream — keys ENUMERATED BY THE
# ENGINE (shim_extractor output over this batch's targets.rb +
# concolic_targets.rb). A key missing here is a NO-TEST red, EXCEPT for the
# runtime rep machinery (kind `rep_plumbing` / `value_class`), which the
# RUNNER itself resolves to PROTOCOL from the real class.
#
# RULE S (DISCIPLINE §9, 2026-08-27): every shim RUNS. There are no waivers;
# PASS and PROTOCOL are the only non-blocking verdicts. Where a shim could not
# run as-is, the MINIMAL mocks it needs are named and justified in its entry:
# fixture ROWS in a real sqlite DB (data, not code-under-test) and a
# throwaway interceptor (below). No application logic is stubbed in this file.
#
# Keys deliberately absent (they come back PROTOCOL from the runner, which
# decides it against the REAL class, not from this prose):
#   obj.read_attribute, obj._read_attribute, obj.attributes,
#   obj.write_attribute, obj._write_attribute, obj.inspect,
#   obj.concolic_attrs, obj.concolic_note   — the AR attribute / Ruby object
#   protocol and the runtime's own bookkeeping accessors.
#
# 2026-09-11: `PostPresenter.build_mentioned_people_json` is no longer a target
# (it is DESCENDED — concolic_targets.rb's `_descend` list), so it is neither a
# target nor a shim and has no entry here; the real body runs.

# ---------------------------------------------------------------------------
# MINIMAL FIXTURE DB (Rule S rule 2). Real sqlite + the app schema through the
# project's own concrete_env helper, then ROWS by raw INSERT. Data only.
# ---------------------------------------------------------------------------
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
CompletionChecker::ConcreteEnv.setup!(
  db: "/home/dev/project/reports/diaspora/results3/people_stream/shim_tests.sqlite3")
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
# X7 (2026-09-11) — rows for the StatusMessage read set targets.rb §2b makes
# visible. Data only: the bodies under test build `Photo.where(
# status_message_guid:)` / `Poll.where(status_message_id:)` /
# `Location.where(status_message_id:)`, and without rows the `.first` arms
# would return nil and the claim would be about an empty table.
CompletionChecker::ConcreteEnv.insert("photos", id: 500, author_id: 2,
  guid: "photoguid100000001", status_message_guid: "postguid1000000001",
  public: true, pending: false, random_string: "r1", processed_image: "p.jpg")
CompletionChecker::ConcreteEnv.insert("polls", id: 600, status_message_id: 100,
  question: "shim?", guid: "pollguid1000000001", status: true)
CompletionChecker::ConcreteEnv.insert("poll_answers", id: 610, poll_id: 600,
  answer: "yes", guid: "pansguid1000000001", vote_count: 3)
CompletionChecker::ConcreteEnv.insert("locations", id: 700, status_message_id: 100,
  address: "Somewhere", lat: "1.0", lng: "2.0")
CompletionChecker::ConcreteEnv.insert("aspects", id: 950, user_id: 9, name: "Friends", order_id: 1)
CompletionChecker::ConcreteEnv.insert("contacts", id: 800, user_id: 9, person_id: 2, sharing: true, receiving: true)

Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

SHIM_DB_USER   = User.find(9)
SHIM_DB_PERSON = Person.find(2)

# ---------------------------------------------------------------------------
# The batch's own code, loaded exactly as run_dse.rb loads it.
# ---------------------------------------------------------------------------
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/results3/people_stream/concolic_targets.rb"
require "/home/dev/project/reports/diaspora/results3/people_stream/targets.rb"

# ---------------------------------------------------------------------------
# THE ONE NON-DATA MOCK IN THIS FILE, named and justified.
#
# Two of the shims the engine enumerates — the SingularAssociation loaded-target
# memo (concolic_targets.rb W3-memo) and the `Gon.preloads` accessor
# (X6b-preloads) — are ANONYMOUS `Module.new` bodies created INSIDE
# `ConcolicTargets.install!`, and so are the `interceptor.__descend_filter__` /
# `interceptor.declare_target` declaration-filter singletons (Rule T re-sync).
# There is no way to reach those bodies without running `install!`, and a shim
# test may never declare a target (it would replace the very app code the tests
# must run).
#
# `install!` reaches the real classes through EXACTLY ONE channel —
# `interceptor.declare_target(...)`, which is `klass.define_method(method)`
# (call_interceptor.rb:103-111). Everything else it does to a real class is the
# two prepends above. So handing `install!` a THROWAWAY interceptor whose
# `declare_target` records and returns nil installs the two real shim bodies
# (and the real declaration filter on the throwaway) and declares NOTHING: no
# app method is replaced, and every body these tests exercise is the real one.
# Verified in the file, not assumed: `grep -n "\.prepend(\|define_method"` over
# concolic_targets.rb finds only those two prepends outside declare_target.
#
# NOT used for the asset-path shims: `PeopleStreamTargets.install!` DOES stub
# `ActionController::Base.helpers.image_path`, so it is never called here —
# `h.image_path` / `h.path_to_image` are tested against the REAL
# ActionView::Helpers::AssetUrlHelper bodies below (the stronger claim: what
# the mock stands in for reaches no target), which requires the real helper to
# be un-stubbed for the whole run.
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
# INSTRUMENT LIMIT, MEASURED AND WORKED AROUND (not waived).
#
# `TargetCallProbe.capture` wraps a target by `home.instance_method(meth)` +
# `home.send(:define_method, meth)` on the OWNER module. When the boundary has
# PREPENDED a module that also defines that method — which is exactly what the
# W3-memo does to `SingularAssociation#find_target` — `instance_method` resolves
# THROUGH the prepend, so the probe's captured "original" IS the memo, while
# the memo's own `super` now lands on the probe wrapper: an infinite recursion
# that dies as a JVM StackOverflowError (measured: 8M, 16M and 64M stacks all
# blow, trace in concolic_targets.rb:1033 <-> :1042). Every other batch avoids
# it only by never running `install!` in the shim rig.
#
# The fix is to make the ancestry the probe sees the REAL one: detach the memo
# body from the module (keeping the UnboundMethod, so nothing is lost) and let
# the ONE test that is about the memo re-attach it from INSIDE its own fixture
# — i.e. AFTER `capture` has already captured the real `find_target` as its
# original. The memo then runs for real, its `super` reaches the real body
# through the probe (which records the call), and there is no cycle.
# ---------------------------------------------------------------------------
SHIM_MEMO_BODY = SHIM_SINGULAR_MEMO.instance_method(:find_target)
SHIM_SINGULAR_MEMO.send(:remove_method, :find_target)

# The two association prepends `PeopleStreamTargets.install!` performs (§1/§8).
# Prepending the NAMED modules here is byte-identically what install! does; on
# a real record both bodies fall through to `super` (their guard is
# `respond_to?(:concolic_attrs)`), so nothing else in this process changes.
Person.prepend(PersonSymAssociations) unless Person.ancestors.include?(PersonSymAssociations)
User.prepend(UserSymPersonAssociation) unless User.ancestors.include?(UserSymPersonAssociation)

# A symbolic representative of each kind the batch builds, for the arms of the
# shim bodies that only a rep can reach (`respond_to?(:concolic_attrs)` true).
SHIM_SYM_PERSON = ConcolicTargets.symbolic_instance(Person, "SHIMTEST_person", "shim test")
SHIM_SYM_USER   = ConcolicTargets.symbolic_instance(User, "SHIMTEST_user", "shim test")

# The §4 current-user overrides, applied to a REAL User and a REAL Person.
# `apply_user_overrides!` is the batch's own module_function and the singleton
# bodies it installs are the shims under test, byte-for-byte; giving it real
# records (rather than a rep) is what makes them RUNNABLE — a rep's `id` is a
# SymbolicInt and Arel calls `#to_i` on it, a ScriptError the runner cannot
# catch (notifications_index, 2026-09-01). The bodies are identical either way:
# none of them branches on the receiver.
SHIM_OVR_PERSON = Person.find(1)
SHIM_OVR_USER   = PeopleStreamTargets.apply_user_overrides!(User.find(9), SHIM_OVR_PERSON)

# X7 §2b — the StatusMessage read set, applied to a REAL post row for the same
# reason SHIM_OVR_USER uses a real User: a rep's `id`/`guid` are symbolic and
# Arel calls `#to_i`/`#to_s` on them inside `.first`, a ScriptError the runner
# cannot catch. `attach_status_message_read_set!` guards on
# `respond_to?(:concolic_attrs)` (the rep marker, not application logic), so the
# real row is given that one marker and then the batch's OWN module_function
# installs the four bodies under test, byte-for-byte. None of them branches on
# the receiver, so running them against real rows is the stronger claim.
SHIM_X7_POST = Post.find(100)
SHIM_X7_POST.define_singleton_method(:concolic_attrs) { {} }
PeopleStreamTargets.attach_status_message_read_set!(SHIM_X7_POST)

AR_TARGETS = [
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
  [ActiveRecord::Associations::SingularAssociation, :find_target],
]

SHIM_TESTS = {
  # =========================================================================
  # targets.rb §1 — PersonSymAssociations. A GUARDED DISPATCHER: the rep arm
  # builds a scoped relation (no statement), the real arm is `super`, the real
  # has_many reader. Both arms run; the body is one ternary line, so either
  # arm covers it — both are exercised anyway so the claim is about the whole
  # method, not one side of it.
  # =========================================================================
  "Person.posts" => {
    targets: AR_TARGETS,
    coverage_of: [PersonSymAssociations, :posts, :instance],
    fixture: -> {
      rel = SHIM_SYM_PERSON.posts                     # rep arm: scoped relation
      raise "not a relation: #{rel.class}" unless rel.is_a?(ActiveRecord::Relation)
      raise "wrong model: #{rel.klass}" unless rel.klass == Post
      cols = rel.where_clause.send(:predicates).map { |pr|
        (pr.respond_to?(:left) && pr.left.respond_to?(:name)) ? pr.left.name.to_s : nil
      }.compact
      raise "scope lost author_id: #{cols.inspect}" unless cols.include?("author_id")
      proxy = SHIM_DB_PERSON.posts                    # real arm: `super`
      raise "super lost: #{proxy.class}" unless proxy.respond_to?(:klass) && proxy.klass == Post
    } },

  # =========================================================================
  # targets.rb §3 — the asset-path stubs. They stand in for the REAL Rails
  # helpers, so what has to be proven is that the REAL bodies reach no target
  # (comments_index 2026-08-28, same shim, same claim). With the precompile
  # allowlist provisioned (a config VALUE, not a stand-in for logic) they run
  # and cover 100%.
  # =========================================================================
  "h.image_path" => {
    targets: AR_TARGETS,
    coverage_of: [ActionView::Helpers::AssetUrlHelper, :image_path, :instance],
    fixture: -> {
      ActionController::Base.helpers.image_path("user/default.png")
    } },
  "h.path_to_image" => {
    targets: AR_TARGETS,
    coverage_of: [ActionView::Helpers::AssetUrlHelper, :path_to_image, :instance],
    fixture: -> {
      ActionController::Base.helpers.path_to_image("user/default.png")
    } },

  # =========================================================================
  # targets.rb §8 — UserSymPersonAssociation#person. Same guarded-dispatcher
  # shape as §1: the rep arm mints a symbolic Person (no statement), the real
  # arm is `super`, the real has_one reader — which DOES reach
  # SingularAssociation#find_target, so the claim is `reaches:` EQUALITY.
  # =========================================================================
  "User.person" => {
    targets: AR_TARGETS,
    # X7 (2026-09-11): the rep arm now ALSO materialises
    # `Person.where(owner_id:).take` before minting SYM_PERSON_via_user — the
    # has_one statement it used to swallow (D1) — so the finder targets join
    # the real arm's find_target in the reaches set.
    reaches: ["ActiveRecord::Associations::SingularAssociation#find_target",
              "ActiveRecord::FinderMethods#take",
              "ActiveRecord::Relation#records"],
    coverage_of: [UserSymPersonAssociation, :person, :instance],
    fixture: -> {
      # The REP arm is driven on a REAL User carrying only the rep MARKER
      # (`concolic_attrs`), not on SHIM_SYM_USER: the arm now runs
      # `Person.where(owner_id: self[:id]).first` for real, and a rep's id is a
      # SymbolicInt on which Arel calls `#to_i` — the uncatchable ScriptError
      # this file documents for SHIM_OVR_USER. The body is identical either
      # way; it does not branch on the receiver beyond the marker.
      urep = User.find(9)
      urep.define_singleton_method(:concolic_attrs) { {} }
      p = urep.person                                 # rep arm, memo MISS
      raise "rep arm gave #{p.inspect}" unless p.respond_to?(:concolic_attrs)
      urep.person                                     # rep arm, memo HIT
      raise "memo not set" unless urep.instance_variable_get(:@__ps_via_user_noted)
      raise "note arm lost" unless urep.instance_variable_get(:@__ps_via_user_note)
                                        .to_s.start_with?("SELECT")
      # B-2 RESCUE ARM (added 2026-09-23). The X7/B-2 repair replaced this
      # body's one-line note with a RENDERED statement guarded by
      # `rescue Exception => nil`, and nothing drove that arm: shim coverage
      # fell 100% -> 90.9% with the bare `nil` as the only missed line, which
      # is the `User.person: FAIL-COVERAGE` that blocked completion from
      # 2026-09-11 onward. The arm's own documented trigger is a SYMBOLIC WALL
      # in the renderer (`NotImplementedError < ScriptError`, which
      # `rescue StandardError` would let escape) — so that is exactly what is
      # raised here, on the REAL `ConcolicTargets.render_relation_sql`, with
      # the original method restored in `ensure`. The claim tested is the one
      # targets.rb states verbatim: "if the renderer raises ... the OLD PROSE
      # NOTE is used verbatim, so the failure case is byte-identical to the
      # pre-repair boundary." No application logic is stubbed: the wall is
      # injected into the batch's OWN note renderer, not into diaspora.
      orig_render = ConcolicTargets.method(:render_relation_sql)
      begin
        ConcolicTargets.define_singleton_method(:render_relation_sql) do |_rel|
          raise NotImplementedError, "shim_tests: forced symbolic wall in the renderer"
        end
        wrep = User.find(9)                           # fresh receiver: memos unset
        wrep.define_singleton_method(:concolic_attrs) { {} }
        pw = wrep.person
        raise "rescue arm gave #{pw.inspect}" unless pw.respond_to?(:concolic_attrs)
        wnote = wrep.instance_variable_get(:@__ps_via_user_note)
        raise "rescue arm note #{wnote.inspect}" unless wnote == "User#person (has_one)"
      ensure
        ConcolicTargets.define_singleton_method(:render_relation_sql, orig_render)
      end
      raise "renderer not restored" unless ConcolicTargets.render_relation_sql(
        Person.where(owner_id: 9)).to_s.start_with?("SELECT")
      u = User.find(9)                                # real arm: `super`
      raise "super lost person" unless u.person && u.person.id == 1
    } },

  # =========================================================================
  # targets.rb §4 — apply_user_overrides!. Nine singleton bodies over REAL
  # User methods. Each runs here on a real User/Person (see SHIM_OVR_USER).
  # =========================================================================
  # X7 (2026-09-11): this override no longer returns the pinned person in
  # silence — it first BUILDS AND MATERIALISES `Person.where(owner_id:).first`,
  # the statement the real `User has_one :person, foreign_key: :owner_id`
  # issues, so the note exists (D1). It is therefore a dispatcher now:
  # `reaches:` equality over the real finder, and BOTH arms of the `||=` memo
  # (first call -> the query, later calls -> the memo) are exercised.
  "user.person" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::FinderMethods#take",
              "ActiveRecord::Relation#records"],
    coverage_of: [SHIM_OVR_USER, :person, :singleton],
    fixture: -> {
      SHIM_OVR_USER.instance_variable_set(:@__ps_person_noted, nil)
      raise "person override lost" unless SHIM_OVR_USER.person.equal?(SHIM_OVR_PERSON)
      raise "memo arm lost" unless SHIM_OVR_USER.person.equal?(SHIM_OVR_PERSON)
      raise "memo not set" unless SHIM_OVR_USER.instance_variable_get(:@__ps_person_noted)
    } },
  "user.language" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :language, :singleton],
    fixture: -> { raise "language" unless SHIM_OVR_USER.language == "en" } },
  "user.gender" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :gender, :singleton],
    fixture: -> { raise "gender" unless SHIM_OVR_USER.gender == "" } },
  "user.contacts" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :contacts, :singleton],
    fixture: -> {
      rel = SHIM_OVR_USER.contacts
      raise "not a Contact relation: #{rel.klass}" unless rel.klass == Contact
      raise "scope lost user_id" unless rel.to_sql.include?("user_id")
    } },
  "user.blocks" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :blocks, :singleton],
    fixture: -> {
      rel = SHIM_OVR_USER.blocks
      raise "not a Block relation: #{rel.klass}" unless rel.klass == Block
      raise "scope lost user_id" unless rel.to_sql.include?("user_id")
    } },
  "user.aspects" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :aspects, :singleton],
    fixture: -> {
      rel = SHIM_OVR_USER.aspects
      raise "not an Aspect relation: #{rel.klass}" unless rel.klass == Aspect
      raise "scope lost user_id" unless rel.to_sql.include?("user_id")
    } },
  # contact_for is the ONE override that materializes: its body ends in
  # `find_by`, the target it exists to feed, so the claim is `reaches:`
  # equality over the real finder (measured, not assumed — see REACHES note).
  "user.contact_for" => {
    targets: AR_TARGETS,
    # MEASURED (first run reported FAIL-REACHES and named the fourth): the
    # `includes(person: :profile)` preload materializes through `#to_ary`.
    reaches: ["ActiveRecord::FinderMethods#find_by",
              "ActiveRecord::FinderMethods#take",
              "ActiveRecord::Relation#records",
              "ActiveRecord::Relation#to_ary"],
    coverage_of: [SHIM_OVR_USER, :contact_for, :singleton],
    fixture: -> {
      got = SHIM_OVR_USER.contact_for(SHIM_DB_PERSON)
      raise "contact_for missed the fixture row: #{got.inspect}" unless got && got.id == 800
    } },
  "user.block_for" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_OVR_USER, :block_for, :singleton],
    fixture: -> {
      rel = SHIM_OVR_USER.block_for(SHIM_DB_PERSON)
      raise "block_for is not a null relation: #{rel.inspect}" unless rel.is_a?(ActiveRecord::Relation)
    } },
  # X7 (2026-09-11): `user.posts_from` is NO LONGER A SHIM and has no entry
  # here. The override was removed — the real `User#posts_from` runs — because
  # `Post.where(author_id:)` was not statement-preserving against
  # `Post.from_person_visible_by_user`'s DISTINCT share_visibilities join
  # (D1). See targets.rb §4 and _X7_DIFFERENTIAL_20260911.txt.

  # =========================================================================
  # concolic_targets.rb symbolic_instance — the three rep singletons that are
  # NOT protocol: each stands in for a REAL method with a body of its own, so
  # the REAL body is what runs here (Rule S rule 4).
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
      u[:hidden_shareables] = {"Post" => ["1"]}
      u.hidden_shareables                       # the present arm
    } },
  # base `Post` defines no `post_location` at all (only Reshare /
  # StatusMessage do), and this reader is installed ONLY on base-Post reps
  # (`klass.name.split('::').last == "Post"`). A method the real class does not
  # define is the rep's own machinery — stated as a FACT the runner CHECKS
  # against the real class, not as prose.
  "obj.post_location" => { real_class: "Post" },

  # =========================================================================
  # targets.rb §2b (X7, 2026-09-11) — THE STATUS-MESSAGE READ SET. Four
  # singletons installed on a Post representative by
  # `attach_status_message_read_set!`. Each stands in for the REAL
  # StatusMessage reader of the same name (status_message.rb:23-26, 98-104) and
  # each is a DISPATCHER into the query boundary — building or materialising
  # the association's own relation IS the point, so the claim is `reaches:`
  # equality, never zero-target. Run against the REAL row 100 (see SHIM_X7_POST
  # above for why a real row, not a rep).
  # =========================================================================
  "rep.photos" => {
    targets: AR_TARGETS,
    # MEASURED, not guessed (the runner returned FAIL-REACHES and named them):
    # the body builds the relation, and this fixture's own assertion —
    # `rel.to_a.map(&:id) == [500]`, which is what proves the scope really
    # selects the fixture row — materialises it through Relation#to_a/#records.
    reaches: ["ActiveRecord::Relation#records", "ActiveRecord::Relation#to_a"],
    coverage_of: [SHIM_X7_POST, :photos, :singleton],
    fixture: -> {
      rel = SHIM_X7_POST.photos
      raise "not a Photo relation: #{rel.class}" unless rel.klass == Photo
      raise "scope lost status_message_guid" unless rel.to_sql.include?("status_message_guid")
      raise "fixture row not visible" unless rel.to_a.map(&:id) == [500]
    } },
  "rep.poll" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::FinderMethods#take", "ActiveRecord::Relation#records"],
    coverage_of: [SHIM_X7_POST, :poll, :singleton],
    fixture: -> {
      got = SHIM_X7_POST.poll
      raise "poll missed the fixture row: #{got.inspect}" unless got && got.id == 600
    } },
  "rep.location" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::FinderMethods#take", "ActiveRecord::Relation#records"],
    coverage_of: [SHIM_X7_POST, :location, :singleton],
    fixture: -> {
      got = SHIM_X7_POST.location
      raise "location missed the fixture row: #{got.inspect}" unless got && got.id == 700
    } },
  # post_location REPLACES the shared boundary's `{address: nil, lat: nil,
  # lng: nil}` stub on a Post rep (a later singleton definition wins), because
  # that stub SWALLOWED the `locations` read StatusMessage#post_location really
  # performs. Two straight-line body lines, both run on every call.
  "rep.post_location" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::FinderMethods#take", "ActiveRecord::Relation#records"],
    coverage_of: [SHIM_X7_POST, :post_location, :singleton],
    fixture: -> {
      got = SHIM_X7_POST.post_location
      raise "post_location: #{got.inspect}" unless got[:address] == "Somewhere" &&
                                                   got[:lat] == "1.0" && got[:lng] == "2.0"
    } },

  # =========================================================================
  # concolic_targets.rb footer (bug 2a, re-synced 2026-09-11) —
  # ConcolicKwargsToPositional. It wraps find_by / find_by! / exists?, stashes
  # the conditions in a thread-local (the documented call_interceptor.rb kwargs
  # gap) and calls `super`: a DISPATCH layer, so the claim is `reaches:`
  # equality over the REAL shadowed body at 100% coverage, on each receiver
  # kind. Both entries ported verbatim in shape from comments_index, which
  # carries the identical footer.
  # =========================================================================
  # =========================================================================
  # concolic_targets.rb X6h REPLACED (2026-09-11) — `Processor.process` is a
  # SHIM now, not a target. The prepend CONCRETIZES the message and `super`s
  # into the REAL renderer pipe, so `diaspora_links`'s
  # `Post.exists?(guid:)` is issued for real instead of being swallowed
  # (Rule S §9.8). A DISPATCH layer: reaching the finder IS its job, so the
  # claim is `reaches:` equality over the real body plus 100 % of its own
  # three lines — the symbolic arm (a value-carrying wrapper), the plain-String
  # arm, and the non-String arm.
  # =========================================================================
  "Diaspora::MessageRenderer::Processor.singleton_class.process" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::FinderMethods#exists?"],
    coverage_of: [ConcolicProcessConcretizeShim, :process, :instance],
    fixture: -> {
      link = "see diaspora://alice@localhost/post/abcdef0123456789abcdef0123456789 end"
      # arm 1: a SymbolicString (value-carrying) — the arm the corpus takes
      sym = SymbolicString.new(link, name: "SHIMTEST_text", note: "shim test")
      got = Diaspora::MessageRenderer.new(sym).plain_text_for_json
      raise "symbolic arm lost the text: #{got.inspect}" unless got.is_a?(::String)
      # arm 2: a plain String — no concretization needed, straight to `super`
      Diaspora::MessageRenderer.new(link).plain_text_for_json
      # arm 3: a non-String, non-symbolic argument -> `to_s`
      Diaspora::MessageRenderer.new(12345).plain_text_for_json
    } },

  "ActiveRecord::Base.singleton_class.DYNAMIC" => {
    # CLASS receiver: `Model.find_by!` resolves to Core::ClassMethods#find_by!
    # (`find_by(*args) || raise(...)`), NOT FinderMethods.
    targets: [[ActiveRecord::Core::ClassMethods, :find_by!]],
    reaches: ["ActiveRecord::Core::ClassMethods#find_by!"],
    coverage_of: [ActiveRecord::Core::ClassMethods, :find_by!, :instance],
    fixture: -> {
      Person.find_by!(guid: "otherguid00000002")
    } },
  "ActiveRecord::Relation.DYNAMIC" => {
    # RELATION receiver: `relation.find_by` is FinderMethods#find_by
    # (`where(arg, *args).take` + `rescue ::RangeError; nil`) — both arms run.
    targets: [[ActiveRecord::FinderMethods, :find_by]],
    reaches: ["ActiveRecord::FinderMethods#find_by"],
    coverage_of: [ActiveRecord::FinderMethods, :find_by, :instance],
    fixture: -> {
      Person.all.find_by(guid: "otherguid00000002")   # the happy line
      Person.all.find_by(id: 10**20)                  # the `rescue ::RangeError` arm
    } },



  # =========================================================================
  # concolic_targets.rb install! — the Rule T declaration FILTER. Its two
  # singleton bodies are installed on the throwaway interceptor above, which
  # is the real body at concolic_targets.rb:399-403.
  # =========================================================================
  "interceptor.__descend_filter__" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_FAKE_INTERCEPTOR, :__descend_filter__, :singleton],
    fixture: -> {
      raise "descend filter" unless SHIM_FAKE_INTERCEPTOR.__descend_filter__ == true
    } },
  "interceptor.declare_target" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_FAKE_INTERCEPTOR, :declare_target, :singleton],
    fixture: -> {
      before = SHIM_FAKE_INTERCEPTOR.declared.size
      # the FILTERED arm: `render` is one of the batch's five DESCENTS, so the
      # wrapper must swallow the declaration and return nil
      got = SHIM_FAKE_INTERCEPTOR.declare_target(String, :render, returns: ->(*) { nil })
      raise "descended target was declared" unless got.nil?
      raise "descended target reached the original" unless SHIM_FAKE_INTERCEPTOR.declared.size == before
      # the PASS-THROUGH arm: any other method reaches `_orig_declare`
      SHIM_FAKE_INTERCEPTOR.declare_target(String, :shim_probe_method, returns: ->(*) { nil })
      raise "pass-through arm lost" unless SHIM_FAKE_INTERCEPTOR.declared.size == before + 1
    } },

  # =========================================================================
  # concolic_targets.rb W3-memo — SingularAssociation#find_target loaded-target
  # memo. A DISPATCH layer: reaching `find_target` IS its job (Rule S rule 5),
  # so the claim is `reaches:` equality plus 100% of its own body — the
  # label-reset arm, the memo MISS (super) and the memo HIT (cached).
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
      first[:contacts] = [1]
      raise "memo lost" unless ::Gon.preloads[:contacts] == [1]
      ::Gon.instance_variable_set(:@concolic_preloads, {})
    } },
}
