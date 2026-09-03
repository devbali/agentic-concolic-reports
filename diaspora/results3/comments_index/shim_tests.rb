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
  require "/home/dev/project/src/ruby_runtime/completion_checker/concrete_env.rb"
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
  "ActionDispatch::Journey::Router::Utils.singleton_class.escape_segment" => {
    targets: AR_TARGETS,
    reaches: [],
    coverage_of: [ActionDispatch::Journey::Router::Utils, :escape_segment, :singleton],
    fixture: -> {
      ActionDispatch::Journey::Router::Utils.escape_segment("a b/c?d")
      ActionDispatch::Journey::Router::Utils.escape_segment("plain")
    } },
}
