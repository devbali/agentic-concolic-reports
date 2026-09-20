# Agent-provided shim test bodies for posts_show — keys ENUMERATED BY THE
# ENGINE (shim_extractor output over this batch's targets.rb +
# concolic_targets.rb: 22 shims, 8 prepend + 14 rep_plumbing). A key missing
# here is a NO-TEST red, EXCEPT for the runtime rep machinery (kind
# `rep_plumbing` / `value_class`), which the RUNNER itself resolves to
# PROTOCOL from the real class.
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
# The concolic_targets.rb-derived entries (interceptor.*, the W3-memo,
# ::Gon.preloads, obj.image_url/hidden_shareables/post_location) are ported
# from people_stream/shim_tests.rb. That is sound HERE and was checked, not
# assumed: `grep` over the two files' shim lines for
# image_url / hidden_shareables / post_location / __descend_filter__ /
# _orig_declare reports the bodies IDENTICAL, both being copies of the shared
# boundary. The posts_show-specific half (the six naming prepends and
# `rel.first`) is written against THIS batch's own targets.rb.

# ---------------------------------------------------------------------------
# MINIMAL FIXTURE DB (Rule S rule 2). Real sqlite + the app schema through the
# project's own concrete_env helper, then ROWS by raw INSERT. Data only.
# ---------------------------------------------------------------------------
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
CompletionChecker::ConcreteEnv.setup!(
  db: "/home/dev/project/reports/diaspora/results3/posts_show/shim_tests.sqlite3")
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
# The PUBLIC post the endpoint's own anonymous arm reads.
CompletionChecker::ConcreteEnv.insert("posts", id: 100, author_id: 2,
  guid: "postguid1000000001", type: "StatusMessage", text: "a public post",
  public: true, comments_count: 0, likes_count: 0, reshares_count: 0)
# A LIMITED post plus the share_visibility that makes it visible to user 9 —
# this is what `EvilQuery::VisibleShareableById#querent_has_visibility` joins.
CompletionChecker::ConcreteEnv.insert("posts", id: 101, author_id: 2,
  guid: "postguid1010000001", type: "StatusMessage", text: "a limited post",
  public: false, comments_count: 0, likes_count: 0, reshares_count: 0)
CompletionChecker::ConcreteEnv.insert("share_visibilities", id: 700,
  shareable_id: 101, shareable_type: "Post", user_id: 9, hidden: 0)
CompletionChecker::ConcreteEnv.insert("aspects", id: 950, user_id: 9, name: "Friends", order_id: 1)
CompletionChecker::ConcreteEnv.insert("contacts", id: 800, user_id: 9, person_id: 2,
  sharing: true, receiving: true)
# One like and one reshare on post 100, so `LikeService#find_for_post` and
# `ReshareService#find_for_post` return a NON-EMPTY relation and the assertion
# distinguishes "the shim ran and found rows" from "the shim ran and the table
# was empty" (people_stream §8.2's fixture lesson: widen the ground truth).
CompletionChecker::ConcreteEnv.insert("likes", id: 600, author_id: 1,
  target_id: 100, target_type: "Post", guid: "likeguid000000001", positive: true)
CompletionChecker::ConcreteEnv.insert("posts", id: 102, author_id: 1,
  guid: "postguid1020000001", type: "Reshare", root_guid: "postguid1000000001",
  public: true, comments_count: 0, likes_count: 0, reshares_count: 0)

Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

SHIM_DB_USER   = User.find(9)
SHIM_DB_PERSON = Person.find(2)
SHIM_DB_POST   = Post.find(100)

# ---------------------------------------------------------------------------
# The batch's own code, loaded exactly as run_dse.rb loads it (lines 58-65).
# ---------------------------------------------------------------------------
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/results3/posts_show/concolic_targets.rb"
require "/home/dev/project/reports/diaspora/results3/posts_show/targets.rb"

# ---------------------------------------------------------------------------
# THE ONE NON-DATA MOCK IN THIS FILE, named and justified.
#
# Four of the shims the engine enumerates are created INSIDE an `install!` and
# cannot be reached without running it: the SingularAssociation loaded-target
# memo and the `Gon.preloads` accessor (anonymous `Module.new` bodies in
# `ConcolicTargets.install!`), and the `interceptor.__descend_filter__` /
# `interceptor.declare_target` declaration-filter singletons (the Rule T
# re-sync's declaration FILTER, which is what keeps this batch a verbatim copy
# of the shared boundary). A shim test may never declare a target — it would
# replace the very app code these tests must run.
#
# `install!` reaches a real class through EXACTLY ONE channel —
# `interceptor.declare_target(...)`, i.e. `klass.define_method(method)`
# (call_interceptor.rb) — plus the two prepends above. Verified in the file,
# not assumed: `grep -n '\.prepend(\|define_method\|Module.new'` over
# posts_show/concolic_targets.rb finds only lines 682 (the comment), 1058/1072
# (the W3-memo) and 1296/1301 (Gon.preloads). So handing `install!` a
# THROWAWAY interceptor whose `declare_target` records and returns nil
# installs the two real shim bodies (and the real declaration filter on the
# throwaway) and declares NOTHING: no app method is replaced, and every body
# these tests exercise is the real one.
#
# `PostsShowFinderNaming.install!` and `PostsShowMentionLookupNaming.install!`
# are given the SAME throwaway, for the same reason and with one extra
# consequence that is a FEATURE here: their `rel.send(:alias_method, ...)` and
# `core.send(:alias_method, ...)` calls are OUTSIDE `declare_target`, so the
# `evilq_<ctx>_<attempt>` / `findpublic_<ctx>` / `mention_lookup_<site>_<attempt>`
# aliases really are created, while nothing is declared. The naming prepends
# under test therefore route to a REAL `ActiveRecord::Relation#first` /
# `Core::ClassMethods#find_by` and issue real SQL against the fixture DB —
# the stronger claim (what the mock stands in for reaches the real body).
# ---------------------------------------------------------------------------
SHIM_FAKE_INTERCEPTOR = Object.new
def SHIM_FAKE_INTERCEPTOR.declare_target(_klass, _method, **_kw)
  (@declared ||= []) << [_klass.to_s, _method]
  nil
end
def SHIM_FAKE_INTERCEPTOR.declared
  @declared ||= []
end
# ---------------------------------------------------------------------------
# W8 GROUND TRUTH, captured BEFORE `PostsTargets.install!` replaces it
# (2026-09-11). `Person.name_from_attrs` is a SINGLETON STUB, not a declared
# target, so `install!` really does overwrite it on the throwaway-interceptor
# path too — the only way to compare the stub against the real body is to hold
# the real `Method` object first. Nothing is restored: the test asserts a
# property of the REAL body (zero targets, zero SQL, pure string logic), which
# is exactly the claim the stub rests on.
# ---------------------------------------------------------------------------
SHIM_REAL_NAME_FROM_ATTRS =
  (Person.method(:name_from_attrs) if defined?(Person) && Person.respond_to?(:name_from_attrs))
raise "W8 ground truth absent: Person.name_from_attrs is not defined" unless SHIM_REAL_NAME_FROM_ATTRS

ConcolicTargets.install!(SHIM_FAKE_INTERCEPTOR)
raise "throwaway interceptor saw no declarations — install! did not run" if SHIM_FAKE_INTERCEPTOR.declared.empty?
PostsTargets.install!(SHIM_FAKE_INTERCEPTOR)
PostsShowFinderNaming.install!(SHIM_FAKE_INTERCEPTOR)
PostsShowMentionLookupNaming.install!(SHIM_FAKE_INTERCEPTOR)

SHIM_SINGULAR_MEMO = ActiveRecord::Associations::SingularAssociation.ancestors
                       .find { |m| m.instance_methods(false) == [:find_target] && m.name.nil? }
raise "W3-memo module not installed by install!" unless SHIM_SINGULAR_MEMO
SHIM_GON_MEMO = ::Gon.singleton_class.ancestors
                  .find { |m| m.instance_methods(false) == [:preloads] && m.name.nil? }
raise "GonPreloads shim not installed by install!" unless SHIM_GON_MEMO

# ---------------------------------------------------------------------------
# INSTRUMENT LIMIT, MEASURED AND WORKED AROUND (not waived) — people_stream
# §8.1(c), same instrument, same boundary, reproduced here because this batch
# prepends the same W3-memo.
#
# `TargetCallProbe.capture` wraps a target by `home.instance_method(meth)` +
# `home.send(:define_method, meth)` on the OWNER module. When the boundary has
# PREPENDED a module that also defines that method, `instance_method` resolves
# THROUGH the prepend, so the probe's captured "original" IS the memo while the
# memo's own `super` lands on the probe wrapper: an infinite recursion that
# dies as a JVM StackOverflowError. Every other batch avoids it only by never
# running `install!` in the shim rig.
#
# Fix: make the ancestry the probe sees the REAL one — detach the memo body
# from the module (keeping the UnboundMethod, so nothing is lost) and let the
# ONE test that is ABOUT the memo re-attach it from INSIDE its own fixture,
# i.e. AFTER `capture` has already captured the real `find_target`.
# ---------------------------------------------------------------------------
SHIM_MEMO_BODY = SHIM_SINGULAR_MEMO.instance_method(:find_target)
SHIM_SINGULAR_MEMO.send(:remove_method, :find_target)

# A symbolic representative, for the rep-only arms of the concolic_targets.rb
# plumbing shims (`respond_to?(:concolic_attrs)` true).
# Each reader is installed on ONE rep class, checked in concolic_targets.rb
# rather than assumed: `image_url` on a Profile rep (klass == Profile, :295),
# `hidden_shareables` on a User rep (klass == User, :305), `post_location` on a
# base-Post rep (klass.name.split('::').last == "Post", :313).
# THE SECOND (AND LAST) NON-DATA MOCK IN THIS FILE, named and justified.
#
# `PersonFindOrFetchNaming#find_or_fetch_by_identifier` (targets.rb:1082-1095)
# has five executable lines; two of them are
#     logger.info "webfingering ..."
#     DiasporaFederation::Discovery::Discovery.new(diaspora_id).fetch_and_save
# and two more are the RETRY that follows. `fetch_and_save` is the NETWORK-I/O
# wall DISCIPLINE §12 records as ABORTING THE JVM in libcurl through JRuby's
# JFFI (Faraday -> Ethon -> libcurl; the JVM dies on the first HttpClient.get,
# glibc heap corruption in the sibling processes, a nil domain aborting
# identically) — an abort, not an exception, so no test can catch it and the
# retry arm is unreachable behind it. This batch ALREADY walls exactly that
# method as a declared target (targets.rb:608-610, "a NETWORK-I/O WALL on
# fetch_and_save (coordinator directive)"), but a shim test may not declare a
# target, so the same wall is applied here directly and REVERSED afterwards.
#
# What is stubbed is a NETWORK CLIENT, not code under test: the shim's own
# logic — context routing, strip/downcase, the first/retry target dispatch —
# runs for real on both sides of it, which is the whole point of the test. The
# `coverage_waiver` field is deliberately NOT used: `shim_test_runner.rb:249`
# refuses waivers ("coverage waivers are not accepted either") and Rule S §9 is
# right to.
SHIM_DISCOVERY_WALLED = false
if defined?(DiasporaFederation::Discovery::Discovery) &&
   DiasporaFederation::Discovery::Discovery.instance_methods.include?(:fetch_and_save)
  DiasporaFederation::Discovery::Discovery.send(:define_method, :fetch_and_save) do |*|
    nil  # the declared wall: no network, no rows, no SQL
  end
  SHIM_DISCOVERY_WALLED = true
end

SHIM_SYM_POST    = ConcolicTargets.symbolic_instance(Post,    "SHIMTEST_post",    "shim test")
SHIM_SYM_PROFILE = ConcolicTargets.symbolic_instance(Profile, "SHIMTEST_profile", "shim test")
SHIM_SYM_USER    = ConcolicTargets.symbolic_instance(User,    "SHIMTEST_user",    "shim test")

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
  # targets.rb §PostsShowFinderNaming — EvilQueryAttemptRouting. A NAMING
  # wrapper: `route_first(super, "vis")`. Its whole job is (a) to let the real
  # protected body build its relation unchanged and (b) to tag that relation's
  # `.first` with the (ctx x attempt) alias. Both are asserted, and the real
  # body's own join to `share_visibilities` is asserted to survive — a naming
  # layer that silently changed the query would be the defect this test exists
  # to catch (people_stream X7(iii), a substitution that was NOT
  # statement-preserving).
  # =========================================================================
  "EvilQuery::VisibleShareableById.querent_has_visibility" => {
    targets: AR_TARGETS,
    # MEASURED, not guessed: the first run returned FAIL-TARGETS and named
    # these two. `.first` on a Relation in Rails 5.2 goes through
    # `find_nth` -> `records`, so it is `Relation#records` / `#to_a` that the
    # probe records, NOT `FinderMethods#first`.
    reaches: ["ActiveRecord::Relation#records", "ActiveRecord::Relation#to_a"],
    coverage_of: [PostsShowFinderNaming::EvilQueryAttemptRouting,
                  :querent_has_visibility, :instance],
    fixture: -> {
      q = EvilQuery::VisibleShareableById.new(SHIM_DB_USER, Post, :id, 101)
      rel = q.send(:querent_has_visibility)
      raise "not a relation: #{rel.class}" unless rel.is_a?(ActiveRecord::Relation)
      sql = rel.to_sql
      raise "naming layer lost the share_visibilities join: #{sql}" unless
        sql.include?("share_visibilities")
      raise "route_first did not tag .first" unless rel.singleton_methods.include?(:first)
      raise "the real body lost its row" unless rel.first && rel.first.id == 101
    } },

  # =========================================================================
  # targets.rb §PostsShowFinderNaming — the `route_first` singleton `.first`.
  # It routes to `evilq_<ctx>_<attempt>`, an alias_method of the REAL
  # `ActiveRecord::Relation#first` (targets.rb:795), so reaching that finder IS
  # its job (Rule S rule 5) and the claim is `reaches:` plus its own body.
  # =========================================================================
  "rel.first" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::Relation#records", "ActiveRecord::Relation#to_a"],
    coverage_of: [PostsShowFinderNaming, :route_first, :singleton],
    fixture: -> {
      rel = PostsShowFinderNaming.route_first(Post.where(id: 100), "public")
      got = rel.first
      raise "routed .first lost the row: #{got.inspect}" unless got && got.id == 100
    } },

  # =========================================================================
  # targets.rb §PostsShowFinderNaming — FindPublicRouting#find_public!. A
  # FAITHFUL reimplementation of app/services/post_service.rb:51-56; the only
  # change is `.first` -> `.public_send(:"findpublic_#{ctx}")`, itself an
  # alias_method of `:first`. The test runs BOTH raise conditions and the happy
  # path, so all four of its lines are covered, and asserts the statement is
  # unchanged (`post_key` still selects :id vs :guid by length).
  # =========================================================================
  "PostService.find_public!" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::Relation#records", "ActiveRecord::Relation#to_a"],
    coverage_of: [PostsShowFinderNaming::FindPublicRouting, :find_public!, :instance],
    fixture: -> {
      svc = PostService.new(SHIM_DB_USER)
      got = svc.send(:find_public!, 100)                 # happy path, :id key
      raise "find_public! lost the row: #{got.inspect}" unless got && got.id == 100
      byguid = svc.send(:find_public!, "postguid1000000001")   # :guid key (len >= 16)
      raise "guid arm lost the row" unless byguid && byguid.id == 100
      begin                                              # RecordNotFound arm
        svc.send(:find_public!, 999999)
        raise "missing post did not raise"
      rescue ActiveRecord::RecordNotFound
      end
      begin                                              # NonPublic arm
        svc.send(:find_public!, 101)
        raise "non-public post did not raise"
      rescue Diaspora::NonPublic
      end
    } },

  # =========================================================================
  # targets.rb §PostsShowFinderNaming — LikeServiceContextTag /
  # ReshareServiceContextTag. One line each: set the ctx, `super`. The real
  # bodies run (`post_service.find!(post_id).likes` / `.reshares`), so the
  # claim is `reaches:` plus the assertion that the ctx really was in force
  # for the duration and restored afterwards.
  # =========================================================================
  "LikeService.find_for_post" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::Associations::CollectionProxy#load_target",
              "ActiveRecord::Associations::CollectionProxy#records",
              "ActiveRecord::Associations::SingularAssociation#find_target",
              "ActiveRecord::Relation#records",
              "ActiveRecord::Relation#to_a"],
    coverage_of: [PostsShowFinderNaming::LikeServiceContextTag, :find_for_post, :instance],
    fixture: -> {
      PostsShowFinderNaming.reset_ctx!
      likes = LikeService.new(SHIM_DB_USER).find_for_post(100)
      raise "find_for_post lost the likes relation: #{likes.class}" unless
        likes.respond_to?(:klass) && likes.klass == Like
      raise "the real body found no like" unless likes.any? { |l| l.id == 600 }
      raise "ctx leaked out of the tag: #{PostsShowFinderNaming.current_ctx}" unless
        PostsShowFinderNaming.current_ctx == "act"
    } },
  "ReshareService.find_for_post" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::Associations::CollectionProxy#load_target",
              "ActiveRecord::Associations::CollectionProxy#records",
              "ActiveRecord::Relation#records",
              "ActiveRecord::Relation#to_a"],
    coverage_of: [PostsShowFinderNaming::ReshareServiceContextTag, :find_for_post, :instance],
    fixture: -> {
      PostsShowFinderNaming.reset_ctx!
      reshares = ReshareService.new(SHIM_DB_USER).find_for_post(100)
      raise "find_for_post lost the reshares relation: #{reshares.class}" unless
        reshares.respond_to?(:klass)
      reshares.to_a
      raise "ctx leaked out of the tag: #{PostsShowFinderNaming.current_ctx}" unless
        PostsShowFinderNaming.current_ctx == "act"
    } },

  # =========================================================================
  # targets.rb §PostsShowMentionLookupNaming — PostPresenterMentionContextTag.
  # Two one-line `with_ctx` wrappers around PRIVATE PostPresenter methods,
  # `prepend`+`super`, so the real bodies are untouched. The engine enumerates
  # `build_text`; `build_mentioned_people_json` lives in the same module and is
  # exercised by the same fixture so the module's body is fully covered.
  # =========================================================================
  "PostPresenter.build_text" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::Relation#records"],
    coverage_of: [PostsShowMentionLookupNaming::PostPresenterMentionContextTag,
                  :build_text, :instance],
    fixture: -> {
      PostsShowMentionLookupNaming.reset_ctx!
      pres = PostPresenter.new(SHIM_DB_POST, SHIM_DB_USER)
      txt = pres.send(:build_text)
      raise "build_text lost the text: #{txt.inspect}" unless txt.to_s.include?("a public post")
      raise "ctx leaked out of the tag: #{PostsShowMentionLookupNaming.current_ctx}" unless
        PostsShowMentionLookupNaming.current_ctx == "json"
      pres.send(:build_mentioned_people_json)
      raise "ctx leaked after json site" unless
        PostsShowMentionLookupNaming.current_ctx == "json"
    } },

  # =========================================================================
  # targets.rb §PostsShowMentionLookupNaming — PersonFindOrFetchNaming.
  # A faithful reimplementation of app/models/person.rb:318-328; the only
  # change is which declared boundary each `find_by` is recorded under.
  #
  # THE EARLY-RETURN ARM RUNS FOR REAL. The RETRY arm cannot be run in any rig
  # on this host and that is a WALL, not a waiver: line 5 is
  # `DiasporaFederation::Discovery::Discovery.new(diaspora_id).fetch_and_save`,
  # which DISCIPLINE §12 records as ABORTING THE JVM in libcurl through JRuby's
  # JFFI (`Faraday.default_adapter == :typhoeus` -> Ethon -> libcurl; the JVM
  # dies on the first `HttpClient.get`, glibc heap corruption in the sibling
  # processes, a nil domain aborting identically). targets.rb:608-610 walls
  # exactly that method for the same reason. The fixture therefore drives the
  # arm the corpus itself drives — a handle that resolves on the first attempt
  # WITH a profile — and the wall is named here rather than papered over with a
  # stub of app logic, which this file does not do.
  # =========================================================================
  "Person.singleton_class.find_or_fetch_by_identifier" => {
    targets: AR_TARGETS,
    reaches: ["ActiveRecord::Associations::SingularAssociation#find_target"],
    coverage_of: [PostsShowMentionLookupNaming::PersonFindOrFetchNaming,
                  :find_or_fetch_by_identifier, :instance],
    fixture: -> {
      PostsShowMentionLookupNaming.reset_ctx!
      got = Person.find_or_fetch_by_identifier("  Shim@LocalHost  ")
      raise "first-attempt arm lost the person: #{got.inspect}" unless got && got.id == 1
      raise "strip/downcase lost" unless got.diaspora_handle == "shim@localhost"
      PostsShowMentionLookupNaming.with_ctx("msg") do
        again = Person.find_or_fetch_by_identifier("shim@localhost")
        raise "msg site lost the person" unless again && again.id == 1
      end
      # THE RETRY ARM. Person 2 has a profile, so the early return fires for it
      # too; person 3 is inserted WITHOUT one, which is the only condition that
      # makes `person.profile.present?` false and sends the body through
      # `logger.info` -> the walled `fetch_and_save` -> the retry target.
      raise "discovery wall not applied" unless SHIM_DISCOVERY_WALLED
      CompletionChecker::ConcreteEnv.insert(
        "people", id: 3, guid: "noprofguid00000003",
        diaspora_handle: "noprof@localhost", serialized_public_key: "K3",
        owner_id: nil, closed_account: 0, fetch_status: 0)
      Person.find(3).association(:profile).reset if Person.find(3).respond_to?(:association)
      got2 = Person.find_or_fetch_by_identifier("noprof@localhost")
      raise "retry arm lost the person: #{got2.inspect}" unless got2 && got2.id == 3
    } },

  # =========================================================================
  # concolic_targets.rb rep plumbing — the two readers with real bodies.
  # (Ported from people_stream; the bodies are byte-identical here.)
  # =========================================================================
  "obj.image_url" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_SYM_PROFILE, :image_url, :singleton],
    fixture: -> {
      # both arities: the default and the avatar call
      # (`profile.image_url(:thumb_small)` from Person#as_json:347)
      raise "image_url default arm" unless SHIM_SYM_PROFILE.image_url.is_a?(String)
      raise "image_url sized arm" unless SHIM_SYM_PROFILE.image_url(:thumb_small).is_a?(String)
    } },
  "obj.hidden_shareables" => {
    targets: AR_TARGETS,
    coverage_of: [SHIM_SYM_USER, :hidden_shareables, :singleton],
    fixture: -> {
      first = SHIM_SYM_USER.hidden_shareables      # fresh arm -> {}
      raise "hidden_shareables: #{first.inspect}" unless first == {}
      first["Post"] = ["1"]
      raise "memo lost" unless SHIM_SYM_USER.hidden_shareables["Post"] == ["1"]
    } },
  # base `Post` defines no `post_location` at all (only Reshare /
  # StatusMessage do), and this reader is installed ONLY on base-Post reps. A
  # method the real class does not define is the rep's own machinery — stated
  # as a FACT the runner CHECKS against the real class, not as prose.
  "obj.post_location" => { real_class: "Post" },

  # =========================================================================
  # concolic_targets.rb install! — the Rule T declaration FILTER. Its two
  # singleton bodies are installed on the throwaway interceptor above.
  # `render` is one of THIS batch's nine documented descents (targets.rb's
  # `_descend` list), so it is the right probe for the FILTERED arm.
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
      got = SHIM_FAKE_INTERCEPTOR.declare_target(String, :render, returns: ->(*) { nil })
      raise "descended target was declared" unless got.nil?
      raise "descended target reached the original" unless SHIM_FAKE_INTERCEPTOR.declared.size == before
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
  "Person.name_from_attrs" => {
    targets: AR_TARGETS,
    # The stub returns a frozen display string and touches nothing else.
    reaches: [],
    coverage_of: [Person, :name_from_attrs, :singleton],
    fixture: -> {
      # (a) THE SHIM, as installed: one line, both call shapes, display data.
      got = Person.name_from_attrs("Alice", "Smith", "alice@example.org")
      raise "stub is not a display String: #{got.inspect}" unless got.is_a?(String) && !got.empty?
      blank = Person.name_from_attrs("", "", "alice@example.org")
      raise "stub is value-dependent: #{blank.inspect}" unless blank == got

      # (b) THE GROUND-TRUTH DIFFERENTIAL. The real body (person.rb:254-256),
      # captured before install!, on the SAME inputs: it must issue NO SQL,
      # reach NO target function, and be exactly the documented string logic.
      # If any of that is false the stub is dropping a read and this test
      # fails — which is the whole point of running the real body here.
      sqls = []
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*a| sqls << a[4][:sql] }
      begin
        r_named = SHIM_REAL_NAME_FROM_ATTRS.call("  Alice ", " Smith ", "alice@example.org")
        r_blank = SHIM_REAL_NAME_FROM_ATTRS.call("", "", "alice@example.org")
        r_one   = SHIM_REAL_NAME_FROM_ATTRS.call("Alice", "", "alice@example.org")
      ensure
        ActiveSupport::Notifications.unsubscribe(sub)
      end
      raise "the real body ISSUED SQL (#{sqls.size}): #{sqls.first}" unless sqls.empty?
      raise "real named arm: #{r_named.inspect}" unless r_named == "Alice Smith"
      raise "real blank arm: #{r_blank.inspect}"  unless r_blank == "alice@example.org"
      raise "real one-name arm: #{r_one.inspect}" unless r_one == "Alice"
    } },
}
