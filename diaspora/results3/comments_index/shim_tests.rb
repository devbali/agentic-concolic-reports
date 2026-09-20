# Agent-provided shim test bodies for comments_index — keys ENUMERATED BY THE
# ENGINE (shim_extractor output). Rule S (DISCIPLINE §9, 2026-08-27): a shim
# must be RUN. There are no waivers; the only non-blocking verdicts are PASS
# (real body, zero targets, 100% executable lines) and PROTOCOL (runtime rep
# machinery, decided by the runner from the real class — those keys are
# DELETED from this file, never waived).
#
# Deleted here on purpose (they come back PROTOCOL): obj.read_attribute,
# obj._read_attribute, obj.attributes, obj.write_attribute, obj._write_attribute,
# obj.inspect, obj.concolic_attrs, obj.concolic_note, obj.persisted?,
# obj.new_record?, obj.post_location (base Post defines no such method — only
# Reshare does), ActiveRecord::Base.singleton_class.DYNAMIC and
# ActiveRecord::Relation.DYNAMIC (the runtime's ConcolicKwargsToPositional
# re-pack).

AR_TARGETS = [
  [ActiveRecord::FinderMethods, :find_by],
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::Calculations, :count],
  [ActiveRecord::Relation, :records],
  [ActiveRecord::Associations::CollectionProxy, :records],
  [ActiveRecord::Associations::SingularAssociation, :find_target],
  [ActiveRecord::Associations::BelongsToPolymorphicAssociation, :find_target],
]

# ---------------------------------------------------------------------------
# Real fixture DB (the concrete checker's own rig: real sqlite via JDBC, the
# app schema, rows by raw INSERT). This is the MINIMAL justified mock for the
# dispatch/naming tests below: they must reach their declared targets FOR REAL,
# and a target that issues SQL needs a database. Data only — no code-under-test
# is stubbed. Set up once, lazily.
# ---------------------------------------------------------------------------
def shim_env!
  return if $shim_env_ready
  require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
  ce = CompletionChecker::ConcreteEnv
  ce.setup!(db: "/home/dev/project/reports/diaspora/results3/comments_index/shim_fixture.sqlite3")
  Rails.application.config.assets.check_precompiled_asset = false
  ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)
  ce.insert("users", id: 9, username: "alice", email: "alice@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
  ce.insert("people", id: 1, guid: "aliceguid000000001", diaspora_handle: "alice@localhost",
            serialized_public_key: "K1", owner_id: 9, closed_account: 0, fetch_status: 0)
  ce.insert("people", id: 2, guid: "bobguid0000000002", diaspora_handle: "bob@remote.example",
            serialized_public_key: "K2", owner_id: nil, closed_account: 0, fetch_status: 0)
  # dave has NO profiles row: the no-profile branch of find_or_fetch_by_identifier
  ce.insert("people", id: 4, guid: "daveguid000000004", diaspora_handle: "dave@remote.example",
            serialized_public_key: "K4", owner_id: nil, closed_account: 0, fetch_status: 0)
  ce.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A", searchable: 1, nsfw: 0)
  ce.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B", searchable: 1, nsfw: 0)
  # a PUBLIC post by bob, neither shared with alice nor authored by her: post!
  # then evaluates all THREE branches of its `||` chain (vis miss, author miss,
  # public hit) — the only way to cover every line of the real body.
  ce.insert("posts", id: 100, author_id: 2, guid: "postguid1000000001", type: "StatusMessage",
            text: "a public post", public: true, comments_count: 1)
  ce.insert("comments", id: 300, commentable_id: 100, commentable_type: "Post",
            author_id: 2, guid: "cguid300", text: "plain comment")
  $shim_env_ready = true
end

# ---------------------------------------------------------------------------
# BYTE-FAITHFULNESS (DISCIPLINE §9 rule 5): a naming/dispatch prepend claims to
# be the shadowed body with only a rename. Only the test can check that, so it
# is checked HERE, from source: both method bodies are extracted textually,
# comments and blank lines dropped, whitespace collapsed, the declared renames
# applied to the ORIGINAL, and the two compared. `extra_allowed` lists lines the
# prepend may ADD (the context tagging a naming layer exists for); anything else
# differing raises.
# ---------------------------------------------------------------------------
def method_source(file, name, after: nil)
  src = File.readlines(file)
  start = nil
  src.each_with_index do |l, i|
    next unless l =~ /^\s*def (self\.)?#{Regexp.escape(name)}(?![\w!?])/
    next if after && i < after
    start = i
    break
  end
  raise "method_source: no `def #{name}` in #{file}" unless start
  indent = src[start][/\A\s*/].size
  fin = start
  ((start + 1)...src.size).each do |i|
    if src[i] =~ /\A\s*end\b/ && src[i][/\A\s*/].size == indent
      fin = i
      break
    end
  end
  src[start..fin].map { |l| l.sub(/#.*$/, "").strip }.reject(&:empty?)
end

def assert_byte_faithful!(orig_file:, orig_name:, shim_file:, shim_name:, shim_after: nil,
                          renames: [], extra_allowed: [], drop_from_shim: [])
  a = method_source(orig_file, orig_name)
  b = method_source(shim_file, shim_name, after: shim_after)
  renames.each do |from, to|
    idx = a.index { |l| l.include?(from) }
    raise "byte-faithful: rename source #{from.inspect} not found in #{orig_name}" unless idx
    a[idx] = a[idx].sub(from, to)
  end
  b = b.reject { |l| drop_from_shim.any? { |p| l.include?(p) } }
  b = b.reject { |l| extra_allowed.any? { |p| l.include?(p) } }
  a = a.map { |l| l.gsub(/\s+/, " ") }
  b = b.map { |l| l.gsub(/\s+/, " ") }
  return true if a == b
  raise "BYTE-FAITHFULNESS FAILED for #{shim_name}\n  original: #{a.inspect}\n  prepend : #{b.inspect}"
end

# ===========================================================================
# PORTED 2026-09-13 from `people_stream/shim_tests.rb` (its lines 84-150 and
# 543-583) so that the TWO shims this batch's `concolic_targets.rb` gained on
# 2026-09-03 — the SingularAssociation loaded-target memo (W3-memo,
# concolic_targets.rb:1048-1065) and the `Gon.preloads` accessor
# (X6b-preloads, :1286-1293) — are RUN instead of scoring NO-TEST. Both were
# added to this file (the shared base `docs/TARGET_FUNCTIONS.md` names) for
# the endpoints that came AFTER comments_index closed on 2026-09-01; this
# file predates them (2026-08-28) and had no key for either.
#
# The borrowed test is the right test because the borrowed BODY is the same
# body, checked byte-for-byte before the port (2026-09-13):
#   concolic_targets.rb 1048-1065 == people_stream 1184-1201
#       md5 b45537f282e23e0931e9eaa63d35172c
#   concolic_targets.rb 1286-1293 == people_stream 1423-1430
#       md5 8eab7f5856b7b82683195d7ebec5a33e
# (only the surrounding PROSE differs, in the X6b-preloads comment.)
#
# THE ONE NON-DATA MOCK IN THIS FILE, named and justified.
#
# The two shim bodies are ANONYMOUS `Module.new` bodies created INSIDE
# `ConcolicTargets.install!`. There is no way to reach them without running
# `install!`, and a shim test may never declare a target (it would replace the
# very app code the tests must run).
#
# `install!` reaches the real classes through EXACTLY ONE channel —
# `interceptor.declare_target(...)`, which is `klass.define_method(method)`
# (call_interceptor.rb:103-111). So handing `install!` a THROWAWAY interceptor
# whose `declare_target` records and returns nil installs the real shim bodies
# and declares NOTHING: no app method is replaced, and every body these tests
# exercise is the real one.
#
# Verified in THIS file, not assumed. `grep -n "\.prepend(\|define_method\|
# const_set" concolic_targets.rb` finds, outside `declare_target`, exactly
# four direct mutations of a real class or of the global namespace:
#   :1063  SingularAssociation.prepend(<anon W3-memo>)   <- under test below
#   :1291  ::Gon.singleton_class.prepend(<anon X6b>)     <- under test below
#   :1412  ::Object.const_set(:ConcreteSymbolicString, …) — a NEW constant,
#          it shadows nothing and no test in this file names it;
#   :1565  ActionDispatch::Journey::Router::Utils.singleton_class
#          .prepend(ConcolicEscapeSegmentShim)           <- SUPPRESSED, below
# plus, at REQUIRE time (not in install!), :1612-1613
#   ActiveRecord::Base.singleton_class.prepend(ConcolicKwargsToPositional)
#   ActiveRecord::Relation.prepend(ConcolicKwargsToPositional)
# which is the very dispatch layer the two `…DYNAMIC` tests below already
# describe and test through (`reaches:` equality over the REAL shadowed
# `find_by` / `find_by!`, whose owners — FinderMethods, Core::ClassMethods —
# are untouched by those prepends, so both bodies and both probes are
# unchanged).
#
# LOCAL DEVIATION from people_stream's copy, named because it is a deviation.
# people_stream's `install!` has no escape_segment overlay; THIS one does
# (:1565, BOUNDARY HARVEST B-2), and the
# `ActionDispatch::Journey::Router::Utils.singleton_class.escape_segment` test
# at the end of this file measures the REAL escaper's body — its own comment
# says so, and it passes today precisely because the shim rig does not install
# that overlay. Letting the prepend land would silently re-point that test's
# `coverage_of` at the wrapper's two lines instead of the body it claims to
# measure: a green over a different quantity. The overlay's guard is
# `Utils.respond_to?(:escape_segment)`, so the real singleton method is
# DETACHED across the `install!` call (its UnboundMethod kept — the same
# "detach, keep, re-attach" pattern as SHIM_MEMO_BODY below, and an
# UnboundMethod carries its original source_location, so the test measures
# exactly what it measured before this port) and re-attached immediately
# after, under `ensure`. Asserted, not assumed, three lines down.
#
# NOT ported from people_stream: its `interceptor.__descend_filter__` /
# `interceptor.declare_target` declaration-filter tests. This batch's
# `concolic_targets.rb` has no descend filter (`grep -c __descend_filter__` ==
# 0), so the engine does not enumerate those keys here.
# `CommentsTargets.install!` (targets.rb) is NOT run and targets.rb is NOT
# required: nothing in `ConcolicTargets.install!` needs it, and the tests
# above read targets.rb as TEXT (byte-faithfulness), never as code.
# ===========================================================================
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/results3/comments_index/concolic_targets.rb"

SHIM_FAKE_INTERCEPTOR = Object.new
def SHIM_FAKE_INTERCEPTOR.declare_target(_klass, _method, **_kw)
  (@declared ||= []) << [_klass.to_s, _method]
  nil
end
def SHIM_FAKE_INTERCEPTOR.declared
  @declared ||= []
end

SHIM_ESCAPE_SEGMENT_BODY =
  ActionDispatch::Journey::Router::Utils.singleton_class.instance_method(:escape_segment)
ActionDispatch::Journey::Router::Utils.singleton_class.send(:remove_method, :escape_segment)
begin
  ConcolicTargets.install!(SHIM_FAKE_INTERCEPTOR)
ensure
  ActionDispatch::Journey::Router::Utils.singleton_class
    .send(:define_method, :escape_segment, SHIM_ESCAPE_SEGMENT_BODY)
end
raise "throwaway interceptor saw no declarations — install! did not run" if SHIM_FAKE_INTERCEPTOR.declared.empty?
if ActionDispatch::Journey::Router::Utils.singleton_class.ancestors.include?(ConcolicEscapeSegmentShim)
  raise "escape_segment overlay leaked into the shim rig"
end
unless ActionDispatch::Journey::Router::Utils.method(:escape_segment)
         .source_location.to_a.first.to_s.include?("actionpack")
  raise "escape_segment is no longer the real body: " \
        "#{ActionDispatch::Journey::Router::Utils.method(:escape_segment).source_location.inspect}"
end

SHIM_SINGULAR_MEMO = ActiveRecord::Associations::SingularAssociation.ancestors
                       .find { |m| m.instance_methods(false) == [:find_target] && m.name.nil? }
raise "W3-memo module not installed by install!" unless SHIM_SINGULAR_MEMO
SHIM_GON_MEMO = ::Gon.singleton_class.ancestors
                  .find { |m| m.instance_methods(false) == [:preloads] && m.name.nil? }
raise "GonPreloads shim not installed by install!" unless SHIM_GON_MEMO

# ---------------------------------------------------------------------------
# INSTRUMENT LIMIT, MEASURED AND WORKED AROUND (not waived) — verbatim from
# people_stream/shim_tests.rb, and it applies here identically because
# `AR_TARGETS` above also carries
# `[ActiveRecord::Associations::SingularAssociation, :find_target]`.
#
# `TargetCallProbe.capture` wraps a target by `home.instance_method(meth)` +
# `home.send(:define_method, meth)` on the OWNER module. When the boundary has
# PREPENDED a module that also defines that method — which is exactly what the
# W3-memo does to `SingularAssociation#find_target` — `instance_method` resolves
# THROUGH the prepend, so the probe's captured "original" IS the memo, while
# the memo's own `super` now lands on the probe wrapper: an infinite recursion
# that dies as a JVM StackOverflowError. Every other batch avoids it only by
# never running `install!` in the shim rig.
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

SHIM_TESTS = {
  # --- asset display-URL stubs: the real bodies are one-line framework
  #     delegations; with the precompile-allowlist check provisioned (a config
  #     VALUE, not a stand-in for logic) they run and cover 100%.
  "h.image_path" => {
    targets: AR_TARGETS,
    coverage_of: [ActionView::Helpers::AssetUrlHelper, :image_path, :instance],
    fixture: -> {
      Rails.application.config.assets.check_precompiled_asset = false
      ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)
      ActionController::Base.helpers.image_path("user/default.png")
    } },
  "h.path_to_image" => {
    targets: AR_TARGETS,
    coverage_of: [ActionView::Helpers::AssetUrlHelper, :path_to_image, :instance],
    fixture: -> { ActionController::Base.helpers.path_to_image("user/default.png") } },

  # --- Profile#image_url: a real shim over app code. Size-keyed column reads,
  #     the default-asset fallback and the camo branch (config toggle
  #     provisioned, then restored).
  "obj.image_url" => {
    targets: AR_TARGETS,
    coverage_of: [Profile, :image_url, :instance],
    fixture: -> {
      Rails.application.config.assets.check_precompiled_asset = false
      ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)
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

  # --- User#hidden_shareables: real body `self[:hidden_shareables] ||= {}`,
  #     both sides of the ||=.
  "obj.hidden_shareables" => {
    targets: AR_TARGETS,
    coverage_of: [User, :hidden_shareables, :instance],
    fixture: -> {
      u = User.new
      u.hidden_shareables
      u[:hidden_shareables] = {"Post" => ["1"]}
      u.hidden_shareables
    } },

  # --- pure leaves ---------------------------------------------------------
  "Person.name_from_attrs" => {
    targets: AR_TARGETS,
    coverage_of: [Person, :name_from_attrs, :singleton],
    fixture: -> {
      Person.name_from_attrs("Alice", " A ", "alice@localhost")
      Person.name_from_attrs("", nil, "alice@localhost")
    } },
  "User.authenticatable_salt" => {
    targets: AR_TARGETS,
    coverage_of: [Devise::Models::Authenticatable, :authenticatable_salt, :instance],
    fixture: -> {
      u = User.new
      u.encrypted_password = "$2a$11$" + ("x" * 53)
      u.authenticatable_salt
    } },
  "ActiveRecord::Base.to_param" => {
    targets: AR_TARGETS,
    coverage_of: [ActiveRecord::Integration, :to_param, :instance],
    fixture: -> {
      c = Comment.new
      c.id = 5
      c.to_param
      Comment.new.to_param
    } },

  # --- the session-user persistence pins: the real bodies are the AR
  #     persistence protocol; both outcomes exercised on a real User.
  "u.persisted?" => {
    targets: AR_TARGETS,
    coverage_of: [ActiveRecord::Persistence, :persisted?, :instance],
    fixture: -> {
      u = User.new
      u.persisted?
      u.instance_variable_set(:@new_record, false)
      u.persisted?
    } },
  "u.new_record?" => {
    targets: AR_TARGETS,
    coverage_of: [ActiveRecord::Persistence, :new_record?, :instance],
    fixture: -> {
      u = User.new
      u.new_record?
      u.instance_variable_set(:@new_record, false)
      u.new_record?
    } },

  # =========================================================================
  # DISPATCH / NAMING PREPENDS (DISCIPLINE §9 rules 4-5). Reaching the target
  # IS their job, so the claim tested is `reaches:` EQUALITY over the REAL
  # shadowed body, at 100% line coverage, plus a byte-faithfulness assertion
  # of the prepend against the original source.
  # =========================================================================

  # EvilQuery::VisibleShareableById#post! — `vis.first || author.first ||
  # public.first`. The fixture's post 100 is public, NOT shared with alice and
  # NOT hers, so all three branches evaluate (the only way to 100%).
  "EvilQuery::VisibleShareableById.post!" => {
    targets: [[ActiveRecord::FinderMethods, :first]],
    reaches: ["ActiveRecord::FinderMethods#first"],
    coverage_of: [EvilQuery::VisibleShareableById, :post!, :instance],
    fixture: -> {
      shim_env!
      assert_byte_faithful!(
        orig_file: "/home/dev/project/ruby_examples/dse-apps/apps/diaspora/lib/evil_query.rb",
        orig_name: "post!",
        shim_file: "/home/dev/project/reports/diaspora/results3/comments_index/targets.rb",
        shim_name: "post!",
        renames: [[".first", ".ci_vis_first"],      # applied to successive occurrences,
                  [".first", ".ci_author_first"],   # in the order the `||` chain calls them
                  [".first", ".ci_public_first"]])
      u = User.find(9)
      EvilQuery::VisibleShareableById.new(u, Post, :id, 100).post!
    } },

  # OrmAdapter::ActiveRecord#get — `klass.where(pk => wrap_key(id)).first`,
  # the ONE finder inside Devise's session resolution.
  "OrmAdapter::ActiveRecord.get" => {
    targets: [[ActiveRecord::FinderMethods, :first]],
    reaches: ["ActiveRecord::FinderMethods#first"],
    coverage_of: [OrmAdapter::ActiveRecord, :get, :instance],
    fixture: -> {
      shim_env!
      assert_byte_faithful!(
        orig_file: "/home/dev/.gem/jruby/2.6.0/gems/orm_adapter-0.5.0/lib/orm_adapter/adapters/active_record.rb",
        orig_name: "get",
        shim_file: "/home/dev/project/reports/diaspora/results3/comments_index/targets.rb",
        shim_name: "get",
        renames: [[".first", ".devise_user_first"]])
      User.to_adapter.get(9)
    } },

  # Person.find_or_fetch_by_identifier — first lookup, the
  # `person.profile.present?` guard, the discovery call, the retry lookup.
  # dave has no profiles row, so the guard fails and the discovery+retry lines
  # run; the federation gem is replaced by an inert double for the duration
  # (the ONE justified mock: a network boundary, which no test may cross).
  "Person.singleton_class.find_or_fetch_by_identifier" => {
    targets: [[ActiveRecord::Core::ClassMethods, :find_by],
              [ActiveRecord::FinderMethods, :find_by],
              [ActiveRecord::Associations::SingularAssociation, :find_target]],
    reaches: ["ActiveRecord::Associations::SingularAssociation#find_target",
              "ActiveRecord::Core::ClassMethods#find_by"],
    coverage_of: [Person.singleton_class, :find_or_fetch_by_identifier, :instance],
    fixture: -> {
      shim_env!
      real = DiasporaFederation::Discovery::Discovery
      inert = Class.new { def initialize(*); end; def fetch_and_save; nil; end }
      DiasporaFederation::Discovery.send(:remove_const, :Discovery)
      DiasporaFederation::Discovery.const_set(:Discovery, inert)
      begin
        Person.find_or_fetch_by_identifier("alice@localhost")   # found + profile -> early return
        Person.find_or_fetch_by_identifier("dave@remote.example") # no profile -> discovery + retry
      ensure
        DiasporaFederation::Discovery.send(:remove_const, :Discovery)
        DiasporaFederation::Discovery.const_set(:Discovery, real)
      end
    } },

  # CommentPresenter#as_json — the context-tagging prepend; the real body reads
  # the comment's message, author and mentioned people.
  "CommentPresenter.as_json" => {
    targets: [[ActiveRecord::FinderMethods, :find_by],
              [ActiveRecord::Associations::SingularAssociation, :find_target],
              [ActiveRecord::Relation, :records]],
    reaches: ["ActiveRecord::Associations::SingularAssociation#find_target",
              "ActiveRecord::Relation#records"],
    coverage_of: [CommentPresenter, :as_json, :instance],
    fixture: -> {
      shim_env!
      out = CommentPresenter.new(Comment.find(300)).as_json
      # The method RETURNS ALL SIX KEYS — i.e. every line of the hash literal
      # was evaluated. JRuby's Coverage nevertheless reports lines 11-15 as
      # never-hit (attribution inside a multi-line hash literal); this
      # assertion is the evidence that the 28.6% is a TOOLING artifact and not
      # an unexercised branch. Reported to the coordinator, not papered over.
      missing = %i[id guid text author created_at mentioned_people] - out.keys
      raise "as_json did not evaluate every element: missing #{missing.inspect}" unless missing.empty?
      f = "/home/dev/project/ruby_examples/dse-apps/apps/diaspora/app/presenters/comment_presenter.rb"
      warn "[shim-diag] as_json returned keys=#{out.keys.inspect} coverage counts 8..17=#{(Coverage.peek_result[f] || [])[7..16].inspect}"
    } },

  # Person.singleton_class kwargs-capture wrappers (violation-6 fix): they add
  # no body of their own — they re-pack kwargs and `super` into the aliased
  # finder. The SHADOWED body is FinderMethods#find_by, run here for real.
  "Person.singleton_class.DYNAMIC" => {
    targets: [[ActiveRecord::FinderMethods, :find_by]],
    reaches: ["ActiveRecord::FinderMethods#find_by"],
    coverage_of: [ActiveRecord::FinderMethods, :find_by, :instance],
    fixture: -> {
      shim_env!
      Person.all.find_by(diaspora_handle: "alice@localhost")  # the happy line
      Person.all.find_by(id: 10**20)                          # the `rescue ::RangeError` arm
    } },


  # --- the runtime's kwargs re-pack (ConcolicKwargsToPositional), prepended to
  #     ActiveRecord::Base.singleton_class and to ActiveRecord::Relation. It
  #     wraps find_by / find_by! / exists?, stashes the conditions in a
  #     thread-local (the documented call_interceptor.rb kwargs gap) and calls
  #     `super` — a DISPATCH layer, so the claim is `reaches:` equality over
  #     the REAL shadowed body (FinderMethods#find_by!: the happy line and its
  #     `rescue ::RangeError` arm), at 100% coverage, on each receiver kind.
  "ActiveRecord::Base.singleton_class.DYNAMIC" => {
    # CLASS receiver: `Model.find_by!` resolves to Core::ClassMethods#find_by!
    # (`find_by(*args) || raise(...)`), NOT to FinderMethods — measured, not
    # assumed: the first spec pointed at FinderMethods and the runner returned
    # FAIL-REACHES with that body never entered.
    targets: [[ActiveRecord::Core::ClassMethods, :find_by!]],
    reaches: ["ActiveRecord::Core::ClassMethods#find_by!"],
    coverage_of: [ActiveRecord::Core::ClassMethods, :find_by!, :instance],
    fixture: -> {
      shim_env!
      Comment.find_by!(guid: "cguid300")
    } },
  "ActiveRecord::Relation.DYNAMIC" => {
    # RELATION receiver: `relation.find_by` is FinderMethods#find_by
    # (`where(arg, *args).take` + `rescue ::RangeError; nil`) — both arms run.
    targets: [[ActiveRecord::FinderMethods, :find_by]],
    reaches: ["ActiveRecord::FinderMethods#find_by"],
    coverage_of: [ActiveRecord::FinderMethods, :find_by, :instance],
    fixture: -> {
      shim_env!
      Comment.all.find_by(guid: "cguid300")   # the happy line
      Comment.all.find_by(id: 10**20)         # the `rescue ::RangeError` arm
    } },

  # --- obj.post_location: my prose ("no real body") was REFUTED by the
  #     runner's check against the real class, so it gets a real test. Base
  #     `Post` indeed does not define it, but the method the rep stands in for
  #     is `StatusMessage#post_location` (status_message.rb:98-104) — the post
  #     class this endpoint's fixtures actually carry. Its body reads the
  #     `location` has_one, so it REACHES a target: `reaches:` equality, not
  #     zero-target. (Straight-line hash literal -> §9 rule 6 covers it.)
  "obj.post_location" => {
    targets: [[ActiveRecord::Associations::SingularAssociation, :find_target]],
    reaches: ["ActiveRecord::Associations::SingularAssociation#find_target"],
    coverage_of: [StatusMessage, :post_location, :instance],
    fixture: -> {
      shim_env!
      StatusMessage.find(100).post_location
    } },

  # --- H3 repair (hardening lint, 2026-08-28): `Discovery.new` is a SHIM, not
  #     a target (it is object construction, not data access; the wall that
  #     matters is `fetch_and_save`, still a declared target). The real
  #     shadowed body is the gem's constructor — `@diaspora_id =
  #     clean_diaspora_id(diaspora_id)`, pure string normalization that reaches
  #     no target. The shim rig does not install this overlay, so `new` here is
  #     the real one.
  "DiasporaFederation::Discovery::Discovery.singleton_class.DYNAMIC" => {
    targets: AR_TARGETS,
    reaches: [],
    coverage_of: [DiasporaFederation::Discovery::Discovery, :initialize, :instance],
    fixture: -> {
      require "diaspora_federation/discovery"
      DiasporaFederation::Discovery::Discovery.new("Alice@Localhost ")
      DiasporaFederation::Discovery::Discovery.new("bob@remote.example")
    } },

  # --- BOUNDARY HARVEST B-1 applied (2026-08-28): `reload` is now a declared
  #     TARGET (targets.rb §8d), so it is no longer a shim and has no entry
  #     here. Its note is the real single-row read; see BOUNDARY CHANGES.

  # --- BOUNDARY HARVEST B-2 applied (2026-08-28): escape_segment is no longer
  #     a target but a SHIM (concolic_targets.rb X8d). The prepend concretizes
  #     the segment and `super`s into the REAL escaper. The shim rig does not
  #     run ConcolicTargets.install!, so `Utils.escape_segment` here IS the
  #     original body (journey/router/utils.rb:84-86) — the same arrangement as
  #     the h.image_path shims. Pure string escaping: zero targets.
  #     2026-09-13 AMENDMENT (the shim-test port): the rig DOES run
  #     `ConcolicTargets.install!` now — with a throwaway interceptor, for the
  #     two anonymous shim bodies. The sentence above still holds, and is now
  #     ENFORCED rather than incidental: the preamble detaches this singleton
  #     method across the `install!` call (the overlay's guard is
  #     `respond_to?(:escape_segment)`) and re-attaches the same UnboundMethod
  #     after, then ASSERTS that `ConcolicEscapeSegmentShim` is absent from the
  #     ancestry and that `escape_segment`'s source_location is still
  #     actionpack's. Measured: this entry's verdict, coverage_pct (100.0) and
  #     missed_lines are byte-identical before and after the port.
  "ActionDispatch::Journey::Router::Utils.singleton_class.escape_segment" => {
    targets: AR_TARGETS,
    reaches: [],
    coverage_of: [ActionDispatch::Journey::Router::Utils, :escape_segment, :singleton],
    fixture: -> {
      ActionDispatch::Journey::Router::Utils.escape_segment("a b/c?d")
      ActionDispatch::Journey::Router::Utils.escape_segment("plain")
    } },

  # =========================================================================
  # PORTED 2026-09-13 from people_stream/shim_tests.rb:543-583 (both entries
  # verbatim; the ONE local edit is the leading `shim_env!` in the first
  # fixture, this batch's lazy equivalent of people_stream's eager fixture DB
  # — its rows are the same shape: users id 9, people id 1 with owner_id 9,
  # so `User.find(9).association(:person)` loads person 1 exactly as there).
  #
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
      shim_env!
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
