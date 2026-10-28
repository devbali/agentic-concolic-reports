# frozen_string_literal: true
#
# Per-entrypoint concolic targets — results3/notifications_index ONLY.
#
# Base infrastructure (§5a/§5b/§5c: ConcolicIntValue, IterableSymbolicList,
# SampledRowsArray, ConcolicDate + column-typing wrapper) ported UNCHANGED
# from results2/notifications_index/targets.rb — that machinery is orthogonal
# to the discipline rebuild (it fixes VALUE SHAPES for WillPaginate/group_by,
# not query coverage) and results3/README.md's own layout doc names it as
# the porting base.
#
# NEW for results3 (closing walls the render-family REMOVAL in
# ../concolic_targets.rb now exposes — see that file's header MOCK LEDGER,
# and results2/MOCK_AUDIT.md as the authority for which walls are genuine
# leaves vs. which would be violations):
#
#   §5b-CP  CollectionProxy#records/#load_target — MOCK_AUDIT's documented
#           gap: CollectionProxy (has_many :through, e.g. `note.actors`)
#           overrides `records` itself (collection_proxy.rb:1003ff ->
#           load_target), shadowing the shared Relation-level §5b mock.
#           notifications_index's OWN controller code never hit this
#           (verified in the audit — its only collection reads are
#           class-level/AssociationRelation), but with the render family
#           now live, the VIEW layer's `note.actors`/`note.notification_actors`
#           (has_many :through) DO read a true CollectionProxy — so the gap
#           the audit fixed for comments_index/people_show applies here too
#           now that this endpoint reaches the view. `to_a`/`to_ary` are NOT
#           re-declared here: CollectionProxy does not override them itself
#           (verified against activerecord-5.2.4.3 collection_proxy.rb), so
#           they already inherit the inherited Relation-level §5b mock.
#
#   §5f  Notification type-dispatch representative (mission item 3). The
#        list/unread-count queries return `Notification` relations; a bare
#        `symbolic_instance(Notification, ...)` allocates a base `Notification`
#        instance, so `note.is_a?(Notifications::Liked)`-style STI dispatch in
#        `app/helpers/notifications_helper.rb#object_link` can NEVER take any
#        typed branch (always false) — the represented row can't even reach
#        the per-type target-fetch queries the reference's 71-query trace
#        spans. Fix: when the relation's model is `Notification`, allocate a
#        REAL STI subclass instance (still via the (a)-upgraded, SQL-noted
#        `symbolic_instance`) chosen by a SEEDED symint decision recorded as
#        a genuine PC (`SYM_NOTE_TYPE_PROFILE == <idx>`) — exactly the
#        "genuine branch on query results" the mission calls for, not a
#        fabricated one. `type`/`target_type` are then pinned to the CONCRETE
#        literal string matching the chosen profile (identity shim, mission
#        item 2) so (i) `note.is_a?`/`Array#include?(note.type)`/
#        `Hash#key(note.type)` compare correctly — SymbolicString has no
#        `to_str` coercion, so a concrete-vs-symbolic compare here is the
#        documented Ruby-coercion gap, not a fixable wall — and (ii) the
#        polymorphic `target` association's `compute_type(owner[:target_type])`
#        (real AR internals, not a mock) can `constantize` successfully.
#        `target_id`/`recipient_id`/`id` etc. all stay genuinely symbolic —
#        this is why acceptance test (i) still shows a real `$$()` bind.
#
#        Profiles driven: "liked" (target=Post, via `Notifications::Liked`)
#        and "reshared" (target=Post, via `Notifications::Reshared`) — both
#        route through `notifications_helper.rb`'s `opts_for_post` branch,
#        giving 2 distinct notification rows against the SAME target-fetch
#        query family (posts) plus the actors (people) fetch every row does
#        regardless of type. A 3rd profile, "started_sharing" (target=Person),
#        was investigated and DELIBERATELY NOT driven: its partial branch
#        (`_notification.haml`'s aspect-dropdown block) additionally reaches
#        `gon_load_contact` -> `ContactPresenter#full_hash_with_person` ->
#        `PersonPresenter#as_json` -> `ActsAsApi::Collection#as_api_response`
#        — MOCK_AUDIT's OTHER named deep descent, explicitly out of scope
#        this stage ("not fixed this stage — the brief's other named deep
#        descent"). Documented here as a known, bounded gap rather than
#        silently attempted and left half-working.
#
#   §5g  `text` column identity shim (mission item 2). ANY Post-family
#        instance built via `symbolic_instance` (the target-fetch above, or
#        any other call site) gets its `text` column pinned to a CONCRETE
#        string instead of the generic `SymbolicString` — `text` is message
#        BODY content, not a query-shape-relevant column, and leaving it
#        symbolic crashes at `Diaspora::MentionsContainer#message` ->
#        `msg_text.to_s.scan(...)` (`SymbolicString#to_s` is in the
#        unsupported-op list by design, src/TODO.txt / main README "Strict
#        runtime"). The pin is a SEEDED boolean (`_text_has_mention`) so DSE
#        can additionally explore a message that DOES contain `@{...}`
#        mention markup, exercising `Diaspora::Mentionable.people_from_string`
#        -> `find_or_fetch_person_by_identifier` -> `Person.find_or_fetch_by_identifier`
#        FOR REAL (MOCK_AUDIT's descent plan: "let the local Person lookup
#        run for real through the existing finder mock") — see §5h for the
#        one thing that chain must not be allowed to do.
#
#   §5h  `DiasporaFederation::Discovery::Discovery#fetch_and_save` — network-
#        I/O wall (coordinator directive: "network I/O must never fire").
#        `Person.find_or_fetch_by_identifier` only reaches this when the
#        local `find_by(diaspora_handle: ...)` (already a kept, real-SQL-
#        noted target) comes back not-found; by default it's found (seed
#        default `false`), so this is dormant unless prefix-directed DSE
#        flips that PC — at which point, without this wall, the real gem
#        body would attempt an actual webfinger HTTP fetch. The mock's body
#        is a single gem-boundary no-op (no SQL, no other declared target —
#        same classification as the already-kept `DiasporaFederation::
#        Entity#validate`/`#normalize_property` leaves), so this is not a
#        new kind of violation, just a new instance of an established one.
#
#   §5i  `to_param` leaf shim (mission item 2 — "to_param/id.to_s in URL
#        helpers"). `notifications_helper.rb#opts_for_post`'s `post_path(post)`
#        and `people_helper.rb`'s `person_path(person)` both resolve through
#        `ActiveRecord::Integration#to_param` (`id && id.to_s`), and
#        `SymbolicInt#to_s` is unsupported by design. Pure URL formatting, no
#        SQL, no other target — the textbook leaf.
#
# Installs AFTER `ConcolicTargets.install!` (see run_dse.rb).
# Wall-fixing discipline (main README): every mock here wraps the SMALLEST
# enclosing method whose real body contains NO SQL and calls NO other
# declared target. Producing queries still run for real.

module NotificationsIndexTargets
  module_function

  # ===================================================================
  # cycle 2 (ADVERSARY_REPORT.md W1) — concrete-text -> symbolic-var map.
  # A post/comment `text` is a concrete String (the renderer's gsub pipes
  # need one), but a value the app EXTRACTS from it and feeds to a query —
  # the `diaspora://<id>/post/<guid>` guid that MessageRenderer#diaspora_links
  # hands to `Post.exists?(guid:)` — IS a query argument. Register the
  # embedded literal here; the query boundary maps it back so the note binds
  # `$$(<rep>_text_dlink_guid)` instead of a fabricated literal. (Same
  # pattern as conversations_index cycle 4 / comments_index cycle 3.)
  # ===================================================================
  # ===================================================================
  # ONE FACT, ONE VARIABLE (coordinator, 2026-08-28; ADVERSARY_WINS §7).
  # The list model repeats ONE representative row N times, so rendering N rows
  # calls the SAME association load / the SAME finder on the SAME receiver N
  # times — and each call minted its own variable (`records_2` / `records_4` /
  # `records_6`), i.e. one FACT modelled as three. The checker then demanded
  # every pairwise combination BETWEEN them (4 825 of 20 914 tier-2
  # declarations were pairs of the same query family at different ordinals),
  # and those combinations are unobservable by construction: the second call
  # returns what the first returned. Memoize per RUN on (target, receiver
  # identity, rendered SQL): the same query on the same receiver is one
  # variable, exactly as the count unification does.
  # ===================================================================
  def fact_cache
    Thread.current[:notifidx_fact_cache] ||= {}
  end

  def reset_fact_cache!
    Thread.current[:notifidx_fact_cache] = {}
  end

  # CYCLE 6 (2026-08-28): keyed on the RENDERED SQL, not on receiver identity.
  # Receiver-identity keying collapsed repeated ASSOCIATION loads (the same
  # association object answers twice) but NOT repeated FINDER calls:
  # `Contact.where(...).find_by(...)` builds a FRESH relation per call, so
  # rendering the ONE representative row three times minted find_by_1/_4/_7 —
  # three variables for one query with byte-identical binds. The checker then
  # demanded their pairwise identity combinations (13 of 44 blocking misses;
  # 4 of the 8 assumption-gate FAILs), i.e. states in which three copies of the
  # SAME row have different contacts — unobservable by construction. The
  # rendered SQL carries every bind BY VARIABLE NAME, so identical SQL in one
  # run IS the same query and therefore one fact (ADVERSARY_WINS §7).
  # Only SELECT-shaped notes are memoised: a junk/fallback note is not evidence
  # that two calls are the same query.
  def one_fact(kind, receiver, sql)
    s = sql.to_s
    return [nil, false, nil] unless s.lstrip.upcase.start_with?("SELECT")
    key = [kind, s]
    hit = fact_cache.key?(key)
    [key, hit, fact_cache[key]]
  end

  def remember_fact(key, value)
    fact_cache[key] = value if key
    value
  end

  def text_binds
    Thread.current[:notifidx_text_binds] ||= {}
  end

  def reset_text_binds!
    Thread.current[:notifidx_text_binds] = {}
  end

  def rebind_note_literals(sql)
    return sql if !sql.is_a?(::String) || text_binds.empty?
    sql.gsub(/'((?:[^']|'')*)'/) do |m|
      lit = Regexp.last_match(1).gsub("''", "'")
      sv = text_binds[lit] || text_binds[lit.strip.downcase]
      sv ? "$$(#{sv.sym_name})" : m
    end
  rescue StandardError
    sql
  end

  # cycle 2 (W1): the REAL `exists?` statement. finder_methods.rb#exists?
  # builds `relation.except(:select, :distinct, :order).select("1 AS one")
  # .limit(1)` — an existence BIT, never a whole-row read (the shared
  # design-#3 declaration in concolic_targets.rb notes `SELECT "posts".*`,
  # a STAR-OVER mis-shape; this batch-local re-declaration replaces it).
  def exists_sql_for(ct, receiver, args)
    sql = ct.sql_for(receiver, args)
    sql = sql.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT 1 AS one FROM ")
    sql = sql.sub(/\s+ORDER BY\s.*\z/m, "")
    sql = sql =~ /\sLIMIT\s/ ? sql : "#{sql} LIMIT 1"
    rebind_note_literals(sql)
  rescue StandardError
    "existence probe"
  end

  # results3 §5f — STI type-dispatch profiles for the notification list
  # representative. `sti` must be a real, loaded Notifications:: subclass;
  # `target_type` must name a real top-level model class (concrete, plain
  # Ruby String — see §5f header comment for why).
  NOTE_TYPE_PROFILES = [
    {key: "liked",    sti: "Notifications::Liked",    target_type: "Post"},
    {key: "reshared", sti: "Notifications::Reshared", target_type: "Post"},
    # gen2 (2026-08-19, Bali: close the STI-scope residue): the remaining
    # types, each with its VERIFIED polymorphic target class (read from the
    # model's own notify/target usage — app/models/notifications/*.rb):
    # AlsoCommented/CommentOnPost notify(comment) -> Comment target;
    # Mentioned/MentionedInComment target the Mention row itself
    # (mentioned.rb:8 `target.mentions_container`); StartedSharing
    # notify(contact) -> sharer Person (started_sharing.rb:19
    # `recipient.contact_for(target)`); ContactsBirthday -> Person.
    # Notifications::PrivateMessage is DELIBERATELY not driven: its
    # target class could not be verified from the model source
    # (notify(object) with a private notify_message indirection) and a
    # guessed target_type would fabricate a query family — documented
    # residue instead.
    # cycle 2 (ADVERSARY W2 / N6): BOTH notify implementations pass the
    # COMMENTABLE, never the comment — `also_commented.rb:23` and
    # `comment_on_post.rb:22` both call
    # `concatenate_or_create(…, comment.commentable, actor)`. The old
    # `target_type: "Comment"` pin modelled an access the app never makes and
    # hid the accesses it does. `commentable: true` marks the two types whose
    # target_type is a RECORDED DECISION over the real set {Post, Photo}
    # (Photo includes Diaspora::Commentable — lib/diaspora/commentable.rb:11 —
    # so a comment on a photo produces target_type "Photo").
    {key: "also_commented",       sti: "Notifications::AlsoCommented",      target_type: "Post", commentable: true},
    {key: "comment_on_post",      sti: "Notifications::CommentOnPost",      target_type: "Post", commentable: true},
    # (Notifications::Mentioned is a CONCERN module, not an STI class —
    # found live via `allocate` NoMethodError; the concrete class is
    # MentionedInPost.)
    {key: "mentioned",            sti: "Notifications::MentionedInPost",    target_type: "Mention"},
    {key: "mentioned_in_comment", sti: "Notifications::MentionedInComment", target_type: "Mention"},
    {key: "started_sharing",      sti: "Notifications::StartedSharing",     target_type: "Person"},
    {key: "contacts_birthday",    sti: "Notifications::ContactsBirthday",   target_type: "Person"}
  ].freeze

  # ===================================================================
  # NAMED SHIM MODULES (Rule S, 2026-08-27). These were anonymous
  # `Module.new` objects created inside `install!`, which made their bodies
  # unreachable to a shim test: the test may not invoke a target, and
  # `install!` declares them. Same bodies, same install sites — just
  # addressable, so `shim_tests.rb` can install and exercise them.
  # ===================================================================
  AssetPathShim = Module.new do
    def compute_asset_path(source, _options = {})
      "/assets/#{source}"
    end
  end

  GonPreloadsShim = Module.new do
    def preloads
      @concolic_preloads ||= {}
    end
  end

  # ===================================================================
  # C7 (2026-09-01) — REAL `gon`, withdrawing the X6b stub ON THIS ENDPOINT.
  #
  # The shared boundary (concolic_targets.rb X6b) declares
  # `Gon::ControllerHelpers#gon` as a target returning a stub whose `push` is a
  # NO-OP, and its own comment states the reason:
  #
  #     "gon.push(user: UserPresenter.new(...)) stores a presenter whose
  #      #to_json — the code that issues the roles/admin, own-profile
  #      (as_api_response), services and counts queries — only runs when the
  #      layout's include_gon serializes it. Swallowing push therefore covered
  #      those queries up. ... Outside auth-chain mode the old no-op behavior
  #      stands (gon is out of scope there by the standing layout(false)
  #      decision)."
  #
  # That standing decision is WITHDRAWN (see run_dse.rb), so the stub is now
  # suppressing reads that a real request makes. Measured: with the layout
  # un-pinned and the whole before_action chain dispatched, `SELECT
  # "services".*` and `SELECT COUNT(*) FROM "contacts"` were STILL 0 events
  # over 114 dumps — the no-op `push` was the remaining cause.
  #
  # The real body (gon-6.3.2 helpers.rb:29-37) is four lines and issues no SQL:
  # it builds a `Gon::Request` from `request.env`, stores it in
  # `RequestStore.store[:gon]` and returns `Gon`. Nothing about it needs a
  # mock; the X6b comment's stated blocker ("needs a RequestStore dump missing
  # in the rig") is a `request.uuid` that `ActionController::TestCase` does
  # supply. Restoring it lets `gon.push` really store the presenter and lets
  # `_head.haml`'s `include_gon` really serialise it — so the presenter's reads
  # happen AT RENDER TIME, where the application makes them, rather than being
  # relocated to push time as the boundary's `AUTH_CHAIN` branch does.
  #
  # PREPEND, not declare_target: a second `declare_target` on the same method
  # captures the FIRST wrapper as its "original" and nests it. Prepending to
  # the CONTROLLER wins over the included `Gon::ControllerHelpers` while
  # leaving the shared boundary file untouched (Rule T3 — the boundary defect
  # is REPORTED, not patched).
  # ===================================================================
  # ===================================================================
  # C7 (2026-09-01) — T-z / C-13 EXTENDED TO SINGULAR ASSOCIATIONS.
  #
  # `AR::Associations::SingularAssociation#find_target` runs only when the
  # association has no loaded target; a has_one read TWICE in one request loads
  # ONCE. The shared boundary's find_target mock has no such memo, so a second
  # `current_user.person` re-issued `SELECT "people".* WHERE owner_id = ? LIMIT 1`.
  # Measured over the whole 4 954-dump corpus: 86 dumps carry that read twice,
  # and — checked the way DISCIPLINE 14 requires, comparing notes by EXACT text
  # with BIND IDENTITY INCLUDED — **all 86 are the same statement with the same
  # bind variable, 0 are two different owners**. So it is a real over-emission,
  # not two owners fused by a normaliser. (This is the check that killed the
  # convenient explanation; the convenient explanation was mine.)
  #
  # PREPEND, not a second declare_target (which would capture the boundary's
  # wrapper as its "original" and nest it). `SingularAssociation` is a CLASS,
  # so a prepended module wins over the method declare_target defined on it.
  # Memo is per RUN and per (owner, reflection) — the same fact, one variable.
  # BOUNDARY NOTE (Rule T3, reported not patched): the fix belongs in the
  # shared find_target mock; every endpoint reading a has_one twice has it.
  # ===================================================================
  SingularLoadedTargetShim = Module.new do
    def find_target(*args)
      cache = (Thread.current[:notifidx_singular_targets] ||= {})
      key = [owner.object_id, reflection.name]
      return cache[key] if cache.key?(key)
      cache[key] = super
    end
  end

  def reset_singular_target_cache!
    Thread.current[:notifidx_singular_targets] = {}
  end

  RealGonShim = Module.new do
    def gon
      req = request
      store = defined?(::RequestStore) ? ::RequestStore.store : nil
      return super unless store && req.respond_to?(:env) && req.respond_to?(:uuid)
      cur = store[:gon]
      if cur.nil? || cur.id != req.uuid
        gr = ::Gon::Request.new(req.env)
        gr.id = req.uuid
        store[:gon] = gr
      end
      ::Gon
    end
  end

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    # -----------------------------------------------------------------
    # gen2d: AvatarPresenter loads cleanly. Its CLASS BODY computes
    # `DEFAULT_IMAGE = ActionController::Base.helpers.image_path(...)` —
    # the Sprockets wall that forced targeted-require over eager_load. In
    # this rig the autoload died mid-body, leaving an EMPTY AvatarPresenter
    # whose missing #base_hash fell through BasePresenter#method_missing to
    # the wrapped Profile (3 type-6 runs). Shim asset resolution ONLY on
    # the ActionController helpers proxy (view-time rendering already
    # resolves; pure URL formatting, no SQL), then reference the class so
    # it autoloads completely before any presenter descent needs it.
    # -----------------------------------------------------------------
    # C7: answer a repeated has_one read from the loaded target (T-z extended).
    if defined?(ActiveRecord::Associations::SingularAssociation) &&
       !(defined?(@singular_loaded_shim) && @singular_loaded_shim)
      ActiveRecord::Associations::SingularAssociation.prepend(SingularLoadedTargetShim)
      @singular_loaded_shim = true
      warn "[notifications_index] C7: SingularAssociation loaded-target memo installed"
    end

    # C7: install the real gon helper on THIS controller (see RealGonShim).
    if defined?(::Gon) && defined?(::Gon::Request) && defined?(NotificationsController) &&
       !(defined?(@real_gon_shim) && @real_gon_shim)
      NotificationsController.prepend(RealGonShim)
      @real_gon_shim = true
      warn "[notifications_index] C7: real Gon::ControllerHelpers#gon restored (X6b stub bypassed)"
    end

    helper_proxy = ActionController::Base.helpers
    asset_shim = AssetPathShim
    helper_proxy.singleton_class.prepend(asset_shim)
    # gen3 auth-chain (2026-08-20): the site-chrome layout (enabled only in
    # the AUTH_CHAIN scenario) calls javascript_include_tag/
    # stylesheet_link_tag in its <head>; Sprockets resolution fails in the
    # rig ("couldn't find file 'underscore'") — 80/80 auth-chain smoke runs
    # died in the asset helper AFTER the before_action chain had already
    # recorded its queries. Same pure-URL-formatting leaf class as the
    # proxy shim above, applied to the VIEW lookup chain (prepend to
    # ActionView::Base wins over the included Sprockets::Rails::Helper).
    ActionView::Base.prepend(asset_shim)

    begin
      AvatarPresenter.instance_method(:base_hash)
    rescue NameError => e
      warn "[notifications_index] AvatarPresenter clean-load FAILED: #{e.class}: #{e.message[0, 120]}"
    end

    # -----------------------------------------------------------------
    # 5a. Coercible + quotable symbolic integer.
    #
    # Closes the WillPaginate wall: `will_paginate/collection.rb:109
    # total_entries=` does `number.to_i`, and src/ruby_runtime/int.rb:30
    # raises NotImplementedError on `SymbolicInt#to_i` by design (it is an
    # implicit-concretization channel). `#to_i` here is EXPLICIT and returns
    # the concrete `value`; `#to_int` is deliberately left raising, so
    # implicit coercion (Array#[], string *, etc.) is still caught.
    # -----------------------------------------------------------------
    unless defined?(ConcolicIntValue)
      ::Object.const_set(:ConcolicIntValue, Class.new(SymbolicInt) do
        def to_i
          value
        end

        def value_for_database
          value
        end

        def quoted_id
          value
        end

        # §gen2 (2026-08-19, ../BUGFIXES_20260819.md): display-leaf
        # arithmetic. notifications_helper.rb:70 interpolates
        # `number_of_actors - 3` into the "and N others" translation once
        # the (gen2-new, persisted-side) `number_of_actors < 4` branch goes
        # >=4 -- SymbolicInt arithmetic raises by design and 120/2520
        # probe-2 runs died there, truncating every later row's queries.
        # +/- with a CONCRETE Integer operand concretizes (the symbolic
        # identity is genuinely spent in display text); comparisons still
        # record PCs via the inherited operators; any other operand still
        # raises via super. Same concretize-at-the-display-leaf category as
        # #to_i above.
        def -(other)
          other.is_a?(Integer) ? value - other : super
        end

        def +(other)
          other.is_a?(Integer) ? value + other : super
        end

        def next
          ConcolicIntValue.new(value + 1,
                               name: (sym_name ? "(#{sym_name} + 1)" : nil),
                               note: note)
        end
        alias_method :succ, :next
      end)
    end

    # -----------------------------------------------------------------
    # 5b. Iterable symbolic list.
    #
    # notifications#index needs `each`/`map`/`group_by` on query results:
    #   `types.each_with_object(current_user.unread_notifications.group_by(&:type))`
    #   the notification-list template's `notes.each {|note| render partial ...}`
    # The shared collection mock already attaches `representative:` and
    # #first/#last/#[0] honour it — yielding that same representative once is
    # the Gate 1b "one sampled row" semantics those readers already implement.
    #
    # DO NOT `include Enumerable` HERE (measured regression in the source
    # batch: shadows the PC-recording SymbolicList#any?/#empty?/#first).
    # -----------------------------------------------------------------
    unless defined?(IterableSymbolicList)
      ::Object.const_set(:IterableSymbolicList, Class.new(SymbolicList) do
        # cycle 2 (ADVERSARY W1 fallout): `Diaspora::Mentionable.format`
        # (mentionable.rb:31) splats the mentioned-people list (`[*people]`),
        # and a splat calls #to_a — SymbolicList#to_a raises by design
        # ("contents out of scope"). The sampled-content model DOES have
        # contents: `length` copies of the representative, which is exactly
        # what every other iteration path over this list already sees
        # (#each/#map/#first). Real Array, no new information invented.
        def to_a
          n = concrete_length
          n = (n.respond_to?(:value) ? n.value : n).to_i
          ::Array.new([[n, 0].max, 8].min) { representative }
        end

        # gen2b: `find_by` on a mocked list (User#blocks returns this type;
        # user/querying.rb:33 `block_for` does `blocks.find_by(person_id:)` —
        # 32 gen3b runs died with NoMethodError). Honest finder semantics:
        # a seeded not_found decision (recorded PC) picks representative-or-
        # nil, and the note carries the list's own SQL plus the condition
        # with $$-binds — the query the real relation would have issued.
        def find_by(cond = {})
          fb_idx = SymbolicFunc.next_call_idx("#{self.sym_name || 'symlist'}_find_by")
          vn = "SYM_RESULT_#{(sym_name || 'symlist')}_find_by_#{fb_idx}_not_found".gsub(/[^A-Za-z0-9_]/, "_")
          rendered = cond.map { |k, v|
            vv = (v.respond_to?(:sym_name) && v.sym_name) ? "$$(#{v.sym_name})" : v.inspect
            "#{k} = #{vv}"
          }.join(" AND ")
          nf = symbool(vn, ConcolicTargets.seed_for(vn, false),
                       note: "#{note} AND #{rendered}")
          (nf == true) ? nil : representative
        end
        def each
          return to_enum(:each) unless block_given?
          yield @representative if @representative && concrete_length != 0
          self
        end

        def map
          return to_enum(:map) unless block_given?
          (@representative && concrete_length != 0) ? [yield(@representative)] : []
        end
        alias_method :collect, :map
      end)
    end

    rel = ActiveRecord::Relation

    # Build the representative row for a Relation/CollectionProxy materialize
    # call. §5f: Notification queries get a real STI subclass instance
    # (type-dispatch); everything else gets the plain (a)-upgraded
    # `symbolic_instance` unchanged.
    # C7 (2026-09-01) — RENDER-SAFE DISPLAY COLUMNS for the un-pinned layout.
    #
    # With `layout(false)` withdrawn the app renders `_drawer.mobile.haml`,
    # which puts `aspect.name` / `tag.name` straight into `link_to`, i.e. into
    # `content_tag_string` -> `unwrapped_html_escape` -> `tidy_bytes` ->
    # `String#scrub`. `SymbolicString#scrub` is (correctly) unsupported in the
    # shared runtime, so the run dies with NotImplementedError — a RIG-class
    # terminal, which `rig_crash_census` rightly fails on: the run would have
    # recorded its decisions and then lost every statement after the drawer.
    # (Measured on the first un-pinned smoke round: 1 of 6 runs,
    # `_drawer.mobile.haml:20`.)
    #
    # This is the SAME class the batch already solved for `notifications.type`
    # (X6i / ConcreteSymbolicString): a real `::String` subclass that also
    # `include`s SymbolicVar is render-safe for every string op while staying
    # recognisable to the interceptor. We reuse `TypeLinkedString`, the
    # subclass that ALSO records `==` / `!=` — so these columns stay PC-VISIBLE
    # and this is NOT a new pin: Rule G's gate/pin partition is unchanged, and
    # `pc_visibility_audit --gate` can still see any compare the app makes.
    # src/ is untouched (the runtime gap is REPORTED, not patched).
    # (a METHOD, not a constant: this sits inside an enclosing method body,
    # where Ruby forbids constant assignment.)
    def render_safe_display_columns
      {
        # keyed by BOTH the full and the demodulized class name: the tag model
        # is `ActsAsTaggableOn::Tag`, and `tag_link(tag)` reaches its `name`
        # through the gem's `Tag#to_s`.
        "Aspect"                 => %w[name],   # _drawer.mobile.haml:20 link_to aspect.name
        "Tag"                    => %w[name],   # _drawer.mobile.haml:27 tag_link(tag)
        "ActsAsTaggableOn::Tag"  => %w[name],   #   -> Tag#to_s -> Tag.normalize (=~, gsub)
        "Service"                => %w[type nickname],  # gon services (_head.haml)
      }
    end

    def make_display_render_safe!(rep, klass)
      map  = render_safe_display_columns
      cols = map[klass.to_s] || map[klass.to_s.split("::").last]
      return rep unless cols && rep.respond_to?(:concolic_attrs)
      attrs = rep.concolic_attrs
      cols.each do |col|
        sym = attrs[col]
        next unless sym.respond_to?(:sym_name) && sym.sym_name
        attrs[col] = TypeLinkedString.build(
          (sym.respond_to?(:value) ? sym.value.to_s : sym.to_s),
          name: sym.sym_name,
          note: (sym.respond_to?(:note) ? sym.note : nil))
        rep.define_singleton_method(col) { attrs[col] }
      end
      rep
    end

    def build_representative(ct, receiver, base_name, sql)
      klass = ct.model_class(receiver)
      return build_notification_representative(ct, base_name, sql) if klass == Notification
      make_display_render_safe!(ct.symbolic_instance(klass, base_name, sql), klass)
    end

    # T1b repair #2 (2026-08-21, note/statement-set equivalence; witness =
    # the 6 tried_unknown profiles-via-mentions reference queries):
    # `mentions.includes(person: :profile)` (mentions_container.rb:18) — the
    # real Preloader issues one SELECT per preload step (people by
    # mention.person_id, profiles by person.id), which the materialize mocks'
    # single-note return swallowed entirely. Walk includes_values via
    # reflections and emit each step through ConcolicThroughLoadProbe. Binds
    # use the value identity person.id == mention.person_id, so both preload
    # queries key on the rep's person_id var and the fold reconstructs the
    # join chain to the mentions producer. Called from ALL materialize mocks
    # (Relation to_a/records, to_ary, CollectionProxy records/load_target).
    def emit_includes_preloads(ct, receiver, rep, owner_count = 1)
      iv = receiver.respond_to?(:includes_values) ? Array(receiver.includes_values) : []
      return if iv.empty?
      owner_klass = ct.model_class(receiver)
      rep_attrs   = rep.respond_to?(:concolic_attrs) ? rep.concolic_attrs : {}
      # CYCLE 6 (Rule T4, note_fidelity PRED-OP-DIFF/LIMIT-DIFF): the real
      # Preloader keys on the OWNER SET. With one owner key ActiveRecord's
      # ArrayHandler builds an EQUALITY (`predicate_builder.build` for a
      # 1-element array); with several it builds `IN (…)`. The corpus must
      # carry BOTH shapes, because the endpoint really issues both
      # (`notification_actors.notification_id = ?` 4x and `IN (…)` 22x across
      # this batch's own concrete runs). The owner count is the modelled ROW
      # COUNT of the relation being materialized, which is already a recorded
      # decision — so the shape follows the decision instead of being frozen.
      # M-7 (coordinator, 2026-08-29): the preloader's predicate follows the
      # DISTINCT FOREIGN-KEY COUNT, not the owner list length — two rows by the
      # same author give `= ?`. A sampled list of N copies of ONE representative
      # therefore has exactly ONE distinct key, so `= $$(key)` is the faithful
      # shape and `IN ($$(one_bind))` is a shape ActiveRecord never emits (its
      # ArrayHandler builds an equality for a one-element key set). The
      # multi-key `IN (…)` family is UNREACHABLE in the sampled model — one
      # representative row, one key — and is reported as a MODEL limitation
      # rather than faked here (cycle 6; an `IN`-by-cardinality rendering was
      # built and then withdrawn on this finding).
      # DISCIPLINE §13 Rule D (coordinator, 2026-08-29) — DERIVE what is
      # determined. The preloader's predicate follows its KEY SET, and the key
      # set is determined by the rows actually loaded: N physical rows have N
      # distinct keys (M-7's "two rows by the same author" case is the one
      # where the FK VALUE repeats, not the row count). So a run that decided
      # `len > 1` must emit `IN (…)` over >= 2 binds, and a one-row state must
      # emit `= …` — `cardinality_consistency_audit` reads exactly that, from
      # the run's OWN decisions. Rule D(c): one physical row, ONE variable —
      # so row j's key is its own variable `<list>_row<j>_<pk>`, minted with
      # the producing query as its note so the fold still resolves it to the
      # same column of the same producer.
      pred = lambda do |tbl, col, bindv, n, keynote = nil|
        raw = (bindv.is_a?(::String) && bindv.start_with?("$$(")) ? bindv : ct.render_arg_value(bindv)
        cnt = n.to_i
        if cnt <= 1
          next %("#{tbl}"."#{col}" = #{raw})
        end
        vals = [raw]
        nm0 = raw[/\A\$\$\((.+)\)\z/, 1]
        if nm0
          (2..[cnt, 4].min).each do |j|
            nmj = nm0.include?("_row_") ? nm0.sub(/_row_/, "_row#{j}_") : "#{nm0}_row#{j}"
            begin
              symint(nmj, (1_000 * j) + 7, note: keynote)
            rescue StandardError
              nil
            end
            vals << "$$(#{nmj})"
          end
        end
        %("#{tbl}"."#{col}" IN (#{vals.join(', ')}))
      end
      emit = nil
      emit = lambda do |k, spec, bind_of, owner_obj = nil, base = nil, ocount = 1, keynote = nil|
        pairs = spec.is_a?(Hash) ? spec.to_a : [[spec, nil]]
        pairs.each do |aname, nested|
          r2 = (k.reflect_on_association(aname.to_sym) rescue nil)
          next unless r2
          # ---- resolve the target class (polymorphic-aware) --------------
          k2 = begin
            if r2.polymorphic?
              tt = owner_obj && (owner_obj[r2.foreign_type] rescue nil)
              tt.nil? ? nil : (tt.to_s.constantize rescue nil)
            else
              r2.klass
            end
          rescue StandardError
            nil
          end
          next unless k2 && k2.respond_to?(:table_name)
          t2  = k2.table_name
          pk2 = (k2.primary_key || "id")
          child_count = ocount
          if r2.belongs_to?
            bindv = bind_of.call(r2.foreign_key.to_s)
            next if bindv.nil?
            # ONE FACT, ONE VARIABLE: the belongs_to target's rep carries the
            # SAME base name `find_target` would give it
            # (`assoc_base_name`), so a load performed by the preloader and a
            # load performed lazily are one variable, not two — and the
            # target's own `id` var IS the owner's FK var (same value).
            abase = owner_obj ? ct.assoc_base_name(owner_obj, aname) \
                              : "#{base || 'SYM_PRELOAD'}_#{ct.assoc_alias(aname)}"
            # B-4 (2026-08-28) — ONE LOAD, ONE PREDICATE. A belongs_to over an
            # FK-LESS column can dangle (`mentions.person_id`, NOT NULL with no
            # foreign key, schema.rb:202-209; `notifications.target_id`, both
            # nullable). Mint the SAME decision `find_target` mints for this
            # association on this owner; on its closing arm attach nil, emit NO
            # read and skip the nested step — a dead decision plus a phantom
            # nested read is exactly what comments_index regression M-3 was.
            unless ct.fk_backed?(r2)
              nfn = "#{abase}_not_found"
              if symbool(nfn, ct.seed_for(nfn, false),
                         note: "belongs_to :#{aname} row missing (no FK on " \
                               "#{(r2.active_record.table_name rescue '?')}.#{r2.foreign_key})") == true
                # B-8: the preloader ISSUED the read and got nothing back — the
                # statement happens on this arm too, so emit it before skipping
                # the attach and the nested step.
                begin
                  ConcolicThroughLoadProbe.load_intermediate(
                    %(SELECT "#{t2}".* FROM "#{t2}" WHERE #{pred.call(t2, pk2, bindv, ocount, keynote)}))
                rescue StandardError
                  nil
                end
                begin
                  if owner_obj
                    unless owner_obj.instance_variable_defined?(:@association_cache)
                      owner_obj.instance_variable_set(:@association_cache, {})
                    end
                    a0 = owner_obj.association(aname.to_sym)
                    a0.target = nil
                    a0.loaded!
                  end
                rescue StandardError
                  nil
                end
                next
              end
            end
            # The PRELOADER's read carries NO `LIMIT` (it is a set read, not
            # `scope.take`) and no STI type condition — verified against this
            # batch's concrete runs: `SELECT "posts".* … "posts"."id" = ?`
            # (26x, the polymorphic `includes(:target)` step) beside
            # `… "posts"."id" = ? LIMIT ?` (10x, the genuinely lazy
            # `mentions_container` / `commentable` find_target).
            psql = %(SELECT "#{t2}".* FROM "#{t2}" WHERE #{pred.call(t2, pk2, bindv, ocount, keynote)})
            child_bind = lambda { |col| col == pk2 ? bindv : nil }
            nested_base = abase
            collection = false
          else
            bindv = bind_of.call("id")
            next if bindv.nil?
            abase = "#{base || 'SYM_PRELOAD'}_#{ct.assoc_alias(aname)}_row"
            thr = (r2.respond_to?(:through_reflection) && r2.through_reflection) || nil
            if thr
              # has_many/has_one :through — the real Preloader's FIRST query
              # is the through-table fetch keyed on the owner; later steps key
              # on through-row columns we hold no vars for.
              psql = %(SELECT "#{thr.table_name}".* FROM "#{thr.table_name}" WHERE #{pred.call(thr.table_name, thr.foreign_key, bindv, ocount, keynote)})
            else
              psql = %(SELECT "#{t2}".* FROM "#{t2}" WHERE #{pred.call(t2, r2.foreign_key, bindv, ocount, keynote)})
            end
            child_bind = lambda { |_col| nil } # child ids unknown — stop chain honestly
            nested_base = abase
            collection = r2.collection?
          end
          ConcolicThroughLoadProbe.load_intermediate(psql)
          # cycle 2 (ADVERSARY near-miss N3): the Preloader LOADS the rows —
          # after it the association answers `first`/`size`/`each` from its
          # target with NO further statement. Build the representative row this
          # preload fetched and leave the association loaded on the owner.
          arep = nil
          an = 1
          begin
            # Rule D: the COLLECTION's own cardinality is decided FIRST, because
            # every key count below it is DERIVED from it — the through-target
            # read and the nested steps key on the rows this decision creates.
            # Domain {0, 1, 4}: empty / one / the `number_of_actors < 4` arm
            # (notifications_helper.rb:63), with `> 1` recorded so the
            # cardinality-consistency check can read the decision back.
            if collection
              # NAME BOUNDARY (2026-09-14): mint through the runtime's one
              # naming function. `len(X)` is legal Z3 but not a legal PYTHON
              # identifier, and solver.py exec/evals its declarations — a
              # direct mint here would still need the batch-local rename
              # this change exists to retire. `seed_for` accepts both
              # spellings, so pre-existing seed files are unaffected.
              aln = SymbolicVar.len_var_name("#{abase}_rows")
              an_seed = ct.seed_for(aln, 1)
              an = (an_seed.respond_to?(:value) ? an_seed.value : an_seed).to_i
              an = 0 if an.negative?
              an = 4 if an > 1
              anv = symint(aln, an, note: psql)
              anv == 0
              anv > 1
              anv > 3
            end
            if !r2.belongs_to? && (r2.respond_to?(:through_reflection) && r2.through_reflection)
              # a has_many :through issues TWO statements: the join-table fetch
              # above, then the target-table read keyed by the target's own pk —
              # over the rows the join table actually produced (ocount * an),
              # never over the outer cardinality (M-8 / Rule D(a)).
              tsql = %(SELECT "#{t2}".* FROM "#{t2}" WHERE #{pred.call(t2, pk2, "$$(#{abase}_#{pk2})", ocount * an, psql)})
              ConcolicThroughLoadProbe.load_intermediate(tsql) if an > 0
              arep = an > 0 ? ct.symbolic_instance(k2, abase, tsql) : nil
            else
              arep = ct.symbolic_instance(k2, abase, psql)
            end
            if owner_obj && arep
              # an allocated AR object has no @association_cache — `association`
              # would NoMethodError on nil (silently, into the rescue below).
              unless owner_obj.instance_variable_defined?(:@association_cache)
                owner_obj.instance_variable_set(:@association_cache, {})
              end
              a3 = owner_obj.association(aname.to_sym)
              if collection
                a3.target = ::Array.new(an) { arep }
              else
                a3.target = arep
              end
              a3.loaded!
              warn "[notifications_index] preloaded #{aname} loaded=#{a3.loaded?} target=#{a3.target.class}" if ENV["CONCOLIC_DEBUG"]
            end
          rescue StandardError => e
            warn "[notifications_index] preload-load #{aname}: #{e.class}: #{e.message[0, 90]}" if ENV["CONCOLIC_DEBUG"]
            arep = nil
          end
          if collection && an == 0 && owner_obj
            # B-5: an EMPTY preloaded collection is loaded and empty — no rep,
            # no target-table read, and no nested step below it.
            begin
              unless owner_obj.instance_variable_defined?(:@association_cache)
                owner_obj.instance_variable_set(:@association_cache, {})
              end
              a4 = owner_obj.association(aname.to_sym)
              a4.target = []
              a4.loaded!
            rescue StandardError
              nil
            end
          end
          child_count = collection ? (ocount * an) : ocount
          if nested && arep
            nb = arep.respond_to?(:concolic_attrs) ? arep.concolic_attrs : {}
            emit.call(k2, nested, lambda { |col| nb[col] }, arep, nested_base, child_count,
                      (arep.respond_to?(:concolic_note) ? arep.concolic_note : psql))
          end
        end
      end
      # cycle 2 (ADVERSARY near-miss N3): remember WHICH associations the
      # parent relation preloaded, so a later collection read answers from the
      # loaded target instead of minting the scope query.
      begin
        names = []
        iv.each do |spec|
          (spec.is_a?(Hash) ? spec.keys : [spec]).each { |n| names << n.to_s }
        end
        rep.instance_variable_set(:@concolic_preloaded, names) if rep
      rescue StandardError
        nil
      end
      # symbolic_instance does not store its base name; every column var is
      # named "<base>_<col>", so recover it from one.
      rep_base = begin
        col, v = rep_attrs.find { |c, x| x.respond_to?(:sym_name) && x.sym_name.to_s.end_with?("_#{c}") }
        col ? v.sym_name.to_s.sub(/_#{Regexp.escape(col)}\z/, "") : "SYM_PRELOAD"
      rescue StandardError
        "SYM_PRELOAD"
      end
      owner_note = (rep.respond_to?(:concolic_note) ? rep.concolic_note : nil)
      iv.each do |spec|
        emit.call(owner_klass, spec, lambda { |col| rep_attrs[col] }, rep, rep_base,
                  owner_count, owner_note)
      end
    rescue StandardError
      nil # note-side extra must never crash the mock (M-family rule)
    end

    # gen10 (2026-08-21): STI type column with a CONCRETE value — so
    # `constantize`/`Hash#key`/`Array#include?`/`is_a?` behave exactly as
    # with the plain-String pin — whose OWN `==`/`!=` record the linking PC
    # on the row's `_type` var. The app genuinely branches on the column
    # (`note.type == "Notifications::StartedSharing"`, _notification.haml:5)
    # before the contact/tags reads, and with the pin silent that predicate
    # vanished from every downstream view: the (finally correctly-chained)
    # taggings view stayed type-unscoped and could not determine the
    # type-scoped reference query. transform.py's atom relevance filter
    # (producers ⊆ alias_for, idx ordering) scopes the fold to queries
    # actually chained through the note row, after the compare. Flip
    # attempts on this PC re-record identically (the value derives from the
    # already-seeded SYM_NOTE_TYPE_PROFILE dimension) — honest unflippable.
    unless defined?(TypeLinkedString)
      ::Object.const_set(:TypeLinkedString, Class.new(::ConcreteSymbolicString) do
        def ==(other)
          return super unless sym_name && other.is_a?(::String) && !other.respond_to?(:sym_name)
          result = to_s == other.to_s
          record!("(#{sym_name} == #{z3_str_val(other.to_s)})", "==", taken: result)
          result
        end

        def !=(other)
          return super unless sym_name && other.is_a?(::String) && !other.respond_to?(:sym_name)
          result = to_s != other.to_s
          record!("(#{sym_name} != #{z3_str_val(other.to_s)})", "!=", taken: result)
          result
        end
      end)
    end

    # results3 §5f. See file-header comment for the full rationale.
    def build_notification_representative(ct, base_name, sql)
      idx_name = "SYM_NOTE_TYPE_PROFILE"
      idx = symint(idx_name, ct.seed_for(idx_name, 0),
                  note: "notification type-dispatch seed (0=liked,1=reshared)")
      profile = NOTE_TYPE_PROFILES.first # defensive default (idx out of range)
      # NO early `break` (found while closing the completion loop): the
      # checker's combination-coverage requires every clique node the SAME
      # variable connects to be OBSERVED (taken or not-taken) within a
      # single run, not merely implied by Z3 arithmetic on a shared int.
      # Breaking out after the first match left `(idx == 1)` UNRECORDED on
      # every idx==0 run, so a combo demanding `idx==0 AND NOT(idx==1)`
      # could never be satisfied by any run even though it's trivially true
      # — the run simply never evaluated the second comparison. Evaluating
      # every index unconditionally (all but one comparison come back
      # False, harmlessly) records the full picture the checker needs.
      NOTE_TYPE_PROFILES.each_with_index do |p, i|
        # Explicit `==` compare (not bare truthiness) — SymbolicInt#== records
        # the PC itself and returns a concrete Ruby bool, same pattern as the
        # shared finder_mock's `if not_found == true` (main README, Ruby
        # truthiness gap section).
        profile = p if idx == i
      end
      # gen2b: stash the ACTIVE profile so polymorphic-type pins deeper in
      # the row render (the Mention container pin in the symbolic_instance
      # wrapper) can DERIVE their concrete class from the already-decided
      # note type instead of minting an independent decision — an
      # independent SYM_MENTION_CONTAINER seed produced infeasible
      # type-x-container crossings (mentioned_in_comment x Post container:
      # 294 i18n missing-:comment_path crashes in the first gen3b corpus).
      NotificationsIndexTargets.instance_variable_set(:@active_note_profile, profile[:key])

      sti_klass = profile[:sti].split("::").inject(Object) { |m, c| m.const_get(c) }
      obj = ct.symbolic_instance(sti_klass, base_name, sql) # (a)-upgraded, real SQL note
      attrs = obj.concolic_attrs
      # Identity shim (mission item 2): pin type/target_type CONCRETE so
      # `note.is_a?`/`Array#include?(note.type)`/`Hash#key(note.type)` (all
      # real, unmocked app/helper code) compare correctly, and the polymorphic
      # `target` association's `compute_type` can `constantize` the string.
      # `target_id`/`id`/`recipient_id` etc. are untouched — stay symbolic.
      attrs["type"]        = TypeLinkedString.build(profile[:sti],
                                                    name: "#{base_name}_type", note: sql)
      # cycle 2 (ADVERSARY W2): target_type is a DECISION, not a pin, for the
      # commentable-target types. On the Photo side the polymorphic preload
      # reads `SELECT "photos".* … WHERE "photos"."id" = $$(…_target_id)`
      # (W3b find_target, klass = owner[target_type].constantize) and
      # `posts_helper.rb:9`'s `post.is_a?(Photo)` branch runs for real,
      # reaching `Photo#status_message` (photo.rb:43 belongs_to
      # :status_message, foreign_key: :status_message_guid, primary_key: :guid).
      tt = profile[:target_type]
      if profile[:commentable]
        ph_name = "#{base_name}_target_is_photo"
        is_photo = symbool(ph_name, ct.seed_for(ph_name, false), note: sql)
        tt = (is_photo == true ? "Photo" : "Post")
      end
      attrs["target_type"] = tt
      obj
    end

    %i[to_a records].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        vn  = "#{name}_rows"
        sql = ct.sql_for(receiver, args)
        fkey, fhit, fval = NotificationsIndexTargets.one_fact(:rel_records, receiver, sql)
        next(fval) if fhit
        # B-5 (coordinator, 2026-08-28): NOTHING EXISTS FOR AN EMPTY RELATION.
        # Read the length FIRST: at 0 there is no row, so no representative is
        # built (its column vars would otherwise carry decisions over a row
        # that does not exist) and no preload step is emitted.
        # B-7 / T-i (coordinator 2026-08-28): a sampled list's length domain is
        # 0 / 1 / MANY, never {0,1} — the STATEMENT SHAPE depends on cardinality
        # (`= ?` for one owner key, `IN (…)` for several) even though the row
        # CONTENT stays one representative. "Many" is 3, not 2
        # (src/call_interceptor.rb:152 reads a 2-element Array return as the
        # legacy [value, sort] tuple). Both edges are recorded as decisions here
        # rather than left to whatever the app happens to compare.
        len_raw = ct.seed_for("len(#{vn})", 1)
        len_i = (len_raw.respond_to?(:value) ? len_raw.value : len_raw).to_i
        len_i = 0 if len_i.negative?
        len_i = 3 if len_i > 1
        rep = nil
        if len_i > 0
          rep = build_representative(ct, receiver, "#{name}_row", sql)
          emit_includes_preloads(ct, receiver, rep, len_i) # T1b repair #2, see §helper
        end
        lst = IterableSymbolicList.new(len_i, name: vn, note: sql, representative: rep)
        lst.length == 0
        lst.length > 1
        NotificationsIndexTargets.remember_fact(fkey, lst)
        lst
      end)
    end

    # 5b-ii. `to_ary` must return a TRUE Array — `pager.replace(result)`
    # (notifications_controller.rb:41) reaches `Array#replace`
    # (WillPaginate::Collection < Array); `to_ary` is Ruby's IMPLICIT
    # conversion protocol and the interpreter type-checks the result, so a
    # SymbolicList (or even a bare Array, which `to_symbolic` would re-wrap)
    # fails. `SampledRowsArray` is a real `::Array` subclass that also
    # includes `SymbolicVar` so it survives the interceptor's post-processing
    # AND satisfies `to_ary`'s type check.
    unless defined?(SampledRowsArray)
      ::Object.const_set(:SampledRowsArray, Class.new(::Array) do
        include SymbolicVar
        attr_reader :note, :representative

        def self.build(len, rep, name:, note:)
          a = new(len) { rep }
          a.instance_variable_set(:@sym_name, name)
          a.instance_variable_set(:@note, note)
          a.instance_variable_set(:@representative, rep)
          a
        end
      end)
    end

    interceptor.declare_target(rel, :to_ary, returns: lambda do |receiver, args, name|
      vn  = "#{name}_rows"
      sql = ct.sql_for(receiver, args)
      # cycle 2 (ADVERSARY near-miss N1): the LENGTH of `@notifications` was a
      # concrete Integer 1 in all 14 951 runs, so `index.html.haml:56`
      # `@group_days.length > 0` was a concrete compare and the EMPTY state
      # (`.no-notifications`, index.html.haml:76-79; the empty
      # `@group_days.each` on mobile) plus every multi-row state were
      # unreachable corpus-wide — including the real `count > 0 AND rows = []`
      # that a page beyond the last one produces (will_paginate strips
      # LIMIT/OFFSET from its count). The length is now a SEEDED decision
      # recorded at this boundary over {0, 1, many}; the array really is built
      # with that many rows, so the branches execute for real.
      len_seed = ct.seed_for("len(#{vn})", 1)
      len_n = (len_seed.respond_to?(:value) ? len_seed.value : len_seed).to_i
      len_n = 0 if len_n.negative?
      # ENGINE LIMITATION (src/call_interceptor.rb:152 — cannot be edited):
      # a mock returning a 2-ELEMENT Array is read as the legacy
      # `[value, sort]` tuple, so a 2-row SampledRowsArray came back as the
      # bare representative (`Relation#to_ary gives Notifications::Liked`,
      # TypeError in will_paginate's `pager.replace`). "Many" is therefore 3
      # rows, not 2 — the domain is {0, 1, 3} and `len > 1` is the decision.
      len_n = 3 if len_n > 1
      # NAME BOUNDARY (2026-09-14): see the note at `aln` above — mint via
      # the runtime's naming function, not a hand-built `len(...)` string.
      len_v = symint(SymbolicVar.len_var_name(vn), len_n, note: sql)
      # (B-5: the representative below is built only when len_n > 0.)
      # explicit compares (bare truthiness records no PC) — both polarities
      # observable in one run, as the type-dispatch idx loop does.
      len_v == 0
      len_v > 1
      len = len_n
      rep = nil
      if len_n > 0
        rep = build_representative(ct, receiver, "#{name}_row", sql)
        emit_includes_preloads(ct, receiver, rep, len_n) # T1b repair #2, see §helper
      end
      SampledRowsArray.build(len, rep, name: vn, note: sql)
    end)

    # -----------------------------------------------------------------
    # results3 §5b-CP. CollectionProxy#records/#load_target — see file-header
    # comment. `to_a`/`to_ary` deliberately NOT re-declared: CollectionProxy
    # does not override them (verified against activerecord-5.2.4.3), so they
    # already inherit the §5b Relation-level mock above unchanged.
    # -----------------------------------------------------------------
    # T1b helper: a declared no-op target whose sole purpose is generating
    # a symbolic_call EVENT carrying the through-load intermediate SQL as
    # its note (extraction emits queries from events, transform.py:225).
    unless defined?(::ConcolicThroughLoadProbe)
      ::Object.const_set(:ConcolicThroughLoadProbe, Module.new do
        def self.load_intermediate(sql)
          sql
        end
      end)
      interceptor.declare_target(
        ::ConcolicThroughLoadProbe.singleton_class, :load_intermediate,
        returns: lambda do |_r, args, name|
          symint("#{name}_row_count", 1, note: args["sql"].to_s)
        end
      )
    end

    if defined?(ActiveRecord::Associations::CollectionProxy)
      cp = ActiveRecord::Associations::CollectionProxy
      %i[records load_target].each do |m|
        interceptor.declare_target(cp, m, returns: lambda do |receiver, args, name|
          # =============================================================
          # CYCLE 6 — D1 (one read, one note) + §7 (one fact, one variable).
          # If the association is ALREADY LOADED, the preloader fetched these
          # rows and `CollectionProxy#records` issues NOTHING: Rails returns
          # `@association.target` (collection_association.rb `load_target`
          # returns early when `loaded?`). The old mock re-described the load
          # anyway and so minted, per preloaded association and per run:
          #   * a SECOND `SELECT "notification_actors".* … = ?` probe event for
          #     the join-table fetch `emit_includes_preloads` had already
          #     emitted (2 events per dump for 1 real statement), and
          #   * a SECOND REPRESENTATIVE for the same row
          #     (`…_CollectionProxy_records_1_row_*` alongside the preloader's
          #     `…_to_ary_1_row_actors_row_*`) — one fact, two variables, and
          #     the whole cross-rep clique the checker then demanded between
          #     them.
          # Return the loaded rows instead: same representative, same length
          # variable the preload step already recorded its {0,1,4} decision on,
          # and NO note (no statement).
          # =============================================================
          begin
            a0 = receiver.instance_variable_get(:@association)
            if a0 && a0.respond_to?(:loaded?) && a0.loaded?
              tgt = a0.target
              tgt = tgt.nil? ? [] : (tgt.is_a?(::Array) ? tgt : [tgt])
              ob = begin
                oat = a0.owner.respond_to?(:concolic_attrs) ? a0.owner.concolic_attrs : {}
                c0, v0 = oat.find { |c, x| x.respond_to?(:sym_name) && x.sym_name.to_s.end_with?("_#{c}") }
                c0 ? v0.sym_name.to_s.sub(/_#{Regexp.escape(c0)}\z/, "") : nil
              rescue StandardError
                nil
              end
              if ob
                abase0 = "#{ob}_#{a0.reflection.name}_row"
                next(IterableSymbolicList.new(
                  tgt.length, name: "#{abase0}_rows",
                  note: "preloaded association ##{a0.reflection.name}: answered from the loaded " \
                        "target, no statement (collection_association.rb `load_target` returns " \
                        "early when loaded?; the preloader's reads are their own events)",
                  representative: tgt.first))
              end
            end
          rescue StandardError
            nil
          end
          vn  = "#{name}_rows"
          sql = ct.sql_for(receiver, args)
          # ONE FACT, ONE VARIABLE: the same association load on the same
          # receiver, repeated while rendering the repeated representative row,
          # is ONE query — return the list the first call minted.
          fkey, fhit, fval = NotificationsIndexTargets.one_fact(:cp_records, receiver, sql)
          next(fval) if fhit
          # T1b repair (2026-08-21, note/statement-set equivalence; witness
          # = the reference diff's proven-rejected bare notification_actors
          # row fetch): a has_many :through load's real statement set
          # includes the JOIN-TABLE fetch, which the folded people-join
          # note alone under-reports. Mint the intermediate as its own
          # noted producer var so extraction emits it as a query.
          begin
            assoc = receiver.instance_variable_get(:@association)
            refl  = assoc && assoc.reflection
            if refl && refl.respond_to?(:through_reflection) && refl.through_reflection
              tr = refl.through_reflection
              owner = assoc.owner
              oid = owner.respond_to?(:[]) ? owner[:id] : owner.id
              isql = %(SELECT "#{tr.table_name}".* FROM "#{tr.table_name}" WHERE "#{tr.table_name}"."#{tr.foreign_key}" = #{ct.render_arg_value(oid)})
              # extraction collects queries from symbolic_call EVENTS only
              # (transform.py:225), so route through the declared helper
              # target below — its invocation generates the event whose
              # note carries the intermediate SQL.
              ConcolicThroughLoadProbe.load_intermediate(isql)
            end
          rescue StandardError
            nil # note-side extra must never crash the mock (M-family rule)
          end
          # cycle 2 (ADVERSARY near-miss N3): if the OWNER was loaded through a
          # relation that PRELOADED this association (`notifications_controller
          # .rb:36 .includes(:target, :actors => :profile)`), the real access
          # issues NO scope query — the Preloader already fetched the rows, and
          # `note.actors.first` / `.size` answer from the loaded target. What
          # the Preloader DID issue for the has_many :through is the join-table
          # fetch (emitted above) and a plain by-primary-key read of the
          # association's own table (`SELECT "people".* … WHERE "people"."id"
          # IN (…)`, rendered per-representative as the corpus's other preload
          # notes are). The `people INNER JOIN notification_actors` scope query
          # the mock used to note is a statement the endpoint cannot perform.
          preloaded = begin
            assoc2 = receiver.instance_variable_get(:@association)
            oname  = assoc2 && assoc2.reflection && assoc2.reflection.name.to_s
            owner2 = assoc2 && assoc2.owner
            pre    = owner2 && owner2.instance_variable_get(:@concolic_preloaded)
            !!(pre && oname && pre.include?(oname))
          rescue StandardError
            false
          end
          # B-5: length FIRST — an empty collection has no row to model, and
          # (this is the residue the first B-5 pass left) NO NOTE MAY BIND ONE.
          len_raw = ct.seed_for("len(#{vn})", 1)
          len_i = (len_raw.respond_to?(:value) ? len_raw.value : len_raw).to_i
          len_i = 0 if len_i.negative?
          len_i = 3 if len_i > 1   # B-7: 0 / 1 / MANY, never {0,1}
          if preloaded
            begin
              k2 = ct.model_class(receiver)
              t2 = k2.table_name
              pk2 = (k2.primary_key || "id")
              # The note stands in for the PRELOADER's target-table read. With
              # zero rows the preloader issues no such read at all (the
              # join-table fetch emitted above is the whole statement set), so
              # emitting the per-representative form anyway asserts a read of a
              # row that does not exist — 6 517 note events across 1 483 dumps,
              # caught by empty_relation_emission_audit.
              sql = if len_i > 1
                      # Rule D: many rows, many keys.
                      ks = ([%($$(#{name}_row_#{pk2}))] +
                            (2..[len_i, 4].min).map { |j| %($$(#{name}_row#{j}_#{pk2})) })
                      (2..[len_i, 4].min).each do |j|
                        begin
                          symint("#{name}_row#{j}_#{pk2}", (1_000 * j) + 7, note: sql)
                        rescue StandardError
                          nil
                        end
                      end
                      %(SELECT "#{t2}".* FROM "#{t2}" WHERE "#{t2}"."#{pk2}" IN (#{ks.join(', ')}))
                    elsif len_i > 0
                      %(SELECT "#{t2}".* FROM "#{t2}" WHERE "#{t2}"."#{pk2}" = $$(#{name}_row_#{pk2}))
                    else
                      # B-5 + B-8: with zero rows the preloader issues no
                      # target-table read at all; say so rather than leaving the
                      # event note-less (which reads as a SWALLOWED statement).
                      "preloaded association is EMPTY: the preloader issued the join-table fetch " \
                      "and no target-table read; no statement here"
                    end
            rescue StandardError
              nil
            end
          end
          rep = nil
          if len_i > 0
            rep = build_representative(ct, receiver, "#{name}_row", sql)
            emit_includes_preloads(ct, receiver, rep, len_i) # T1b repair #2, see §helper
          end
          lst = IterableSymbolicList.new(len_i, name: vn, note: sql, representative: rep)
          lst.length == 0   # B-7: cardinality is a DECISION, both edges recorded
          lst.length > 1
          # cycle 2 (ADVERSARY near-miss N4): leave the association in the state
          # the REAL load leaves it — loaded, with its target populated. A later
          # `.size` is then answered in memory exactly as Rails answers it
          # (`collection_association.rb:216` `loaded? -> target.size`), instead
          # of minting a `SELECT COUNT(*)` the endpoint never issues
          # (`post.photos.present?` then `post.photos.size`,
          # `posts_helper.rb:16-17`: 2 332 corpus COUNT notes, 0 real ones).
          begin
            assoc3 = receiver.instance_variable_get(:@association)
            if assoc3 && assoc3.respond_to?(:loaded!)
              n3 = lst.respond_to?(:length) ? lst.length : 1
              n3 = (n3.respond_to?(:value) ? n3.value : n3).to_i
              assoc3.target = ::Array.new([n3, 0].max) { rep }
              assoc3.loaded!
            end
          rescue StandardError
            nil
          end
          NotificationsIndexTargets.remember_fact(fkey, lst)
          lst
        end)
      end
    end

    # 5b-iii. Relation#count -> ConcolicIntValue (the WillPaginate producer).
    # completion drive (2026-08-27, note_fidelity AGG-COLLAPSE): real count
    # statements project COUNT(*), never the row columns sql_for's default
    # `SELECT "t".*` rendering shows. Rewrite the projection (tables / joins /
    # predicates untouched; will_paginate strips LIMIT/OFFSET from its count
    # and the checks ignore them). Feeds notifications_controller.rb:38
    # `Notification.where(conditions).count`, :48/:51
    # `current_user.unread_notifications.count` / `.group_by(&:type)...count`.
    # -----------------------------------------------------------------
    # BOUNDARY HARVEST B-1 (coordinator, 2026-08-28): `ActiveRecord::Base#reload`
    # is a TARGET, not a shim. Its real body is
    # `self.class.unscoped { self.class.find(id) }` — a single-row read — and
    # this endpoint reaches it through `Person#name` -> `fix_profile` ->
    # (Discovery wall) -> `reload`. It mints ONE note, the real statement,
    # bound to the RECEIVER'S OWN id var (never a literal), and returns the
    # receiver (reload returns self).
    # NOT-FOUND: pinned found. PIN LEDGER — `fix_profile` only reloads after
    # `Discovery#fetch_and_save`, which either saved the profile or raised
    # `DiscoveryError` (a 500); a row that reached `reload` therefore exists,
    # and the row was read by id moments earlier in the same request.
    # The note is emitted through the declared no-op probe because `reload`'s
    # RETURN is the receiver, whose own note is its original producing query —
    # attaching the reload statement to the returned rep would overwrite it.
    # -----------------------------------------------------------------
    interceptor.declare_target(ActiveRecord::Base, :reload, returns: lambda do |receiver, _args, name|
      begin
        klass = receiver.class
        table = klass.table_name
        pk    = (klass.primary_key || "id")
        idv   = if receiver.respond_to?(:concolic_attrs)
                  receiver.concolic_attrs[pk] || receiver.concolic_attrs["id"]
                elsif receiver.respond_to?(:id)
                  receiver.id
                end
        unless idv.nil?
          sql = %(SELECT "#{table}".* FROM "#{table}" WHERE "#{table}"."#{pk}" = #{ct.render_arg_value(idv)} LIMIT 1)
          ConcolicThroughLoadProbe.load_intermediate(sql)
        end
      rescue StandardError
        nil # note-side extra must never crash the mock (M-family rule)
      end
      # AR clears the association cache on reload; mirror that so a later
      # association read goes through its own target again.
      begin
        receiver.instance_variable_set(:@association_cache, {})
        # PIN LEDGER (B-1 not-found semantics): after a reload the row's
        # has_one associations are pinned FOUND. `Person#name` -> `fix_profile`
        # reloads only after `Discovery#fetch_and_save`, which either SAVED the
        # profile or raised DiscoveryError (a real 500) — a reloaded person
        # whose render continues therefore has a profile. Without this the
        # not-found decision would persist across the reload and every such run
        # would die in the view on a nil profile (measured: 50/60 runs).
        receiver.instance_variable_set(:@concolic_reloaded, true)
      rescue StandardError
        nil
      end
      receiver
    end)

    # -----------------------------------------------------------------
    # cycle 2 (ADVERSARY W1). `ActiveRecord::FinderMethods#exists?` —
    # re-declared batch-locally over the shared design-#3 declaration
    # (concolic_targets.rb:697-710) for TWO reasons:
    #   (1) NOTE: the shared note is `sql_for` = a whole-row `SELECT "posts".*`
    #       read. The real statement is an existence BIT
    #       (`SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT 1`,
    #       finder_methods.rb#exists?) — a STAR-OVER mis-shape, and the guid
    #       literal is rebound to its text-derived var.
    #   (2) RETURN: the app consumes it in TRUTHINESS position
    #       (`… && Post.exists?(guid: guid) ? … : …`, message_renderer.rb:103),
    #       which Ruby decides at C level — a SymbolicBool is ALWAYS truthy,
    #       so the "does not exist" side could never be taken and no PC was
    #       recorded. Record the decision here and return a value whose
    #       truthiness matches it (the note-bearing SymbolicBool on the true
    #       side, nil on the false side).
    # -----------------------------------------------------------------
    # -----------------------------------------------------------------
    # cycle 2 (ADVERSARY near-miss N3, Rule T4). `first`/`last`/`take` on a
    # LOADED relation issue NO statement: `FinderMethods#first` -> `find_nth`
    # -> `@records[0]` when `loaded?` (finder_methods.rb), and a preloaded
    # association is loaded — `_notification.haml:12`'s `note.actors.first`
    # reads the preloaded rows. The shared design-#2 finder mock renders the
    # relation's SCOPE SQL unconditionally, which is how the corpus acquired
    # 494 850 `people INNER JOIN notification_actors` notes for a statement
    # the endpoint never issues. Answer from the loaded target instead, with
    # NO note (no statement) — the preload's own notes are already emitted.
    # -----------------------------------------------------------------
    %i[first last take].each do |fmeth|
      interceptor.declare_target(ActiveRecord::FinderMethods, fmeth,
                                 returns: lambda do |receiver, args, name|
        loaded = begin
          receiver.respond_to?(:loaded?) && receiver.loaded?
        rescue StandardError
          false
        end
        if loaded
          rows = begin
            receiver.respond_to?(:target) ? Array(receiver.target) : Array(receiver.to_a)
          rescue StandardError
            []
          end
          # B-8: the call issues NO statement (finder_methods.rb `find_nth`
          # reads `@records` when `loaded?`), but a note-less event is
          # indistinguishable from a swallowed one — say which it is.
          Thread.current[:concolic_pending_note] =
            "loaded relation: ##{fmeth} answers from the in-memory target; no statement " \
            "(the preloader's reads are their own events)"
          next(fmeth == :last ? rows.last : rows.first)
        end
        ct.finder_mock(raise_on_missing: false, kind: fmeth).call(receiver, args, name)
      end)
    end

    interceptor.declare_target(ActiveRecord::FinderMethods, :exists?,
                               returns: lambda do |receiver, args, name|
      vn = "#{name}_exists"
      esql = NotificationsIndexTargets.exists_sql_for(ct, receiver, args)
      v = symbool(vn, ct.seed_for(vn, false), note: esql)
      if v == true
        v
      else
        # The statement is issued whatever the ANSWER is, so the note must be
        # emitted on both sides — `nil` carries none (the engine reads notes
        # off the returned value, src/call_interceptor.rb:167). Route the
        # false side's statement through the declared no-op probe, whose
        # event carries it (same device as the through-load intermediates).
        # B-8 (2026-08-29): publish the note out of band as well, so the
        # `exists?` EVENT ITSELF carries the statement instead of relying on
        # the probe event alone — a note-less target call is a statement the
        # extracted policy loses (noteless_call_audit).
        ConcolicThroughLoadProbe.load_intermediate(esql)
        Thread.current[:concolic_pending_note] = esql
        nil
      end
    end)

    calc = ActiveRecord::Calculations
    interceptor.declare_target(calc, :count, returns: lambda do |receiver, args, name|
      vn = "#{name}_count"
      note = ct.sql_for(receiver, args)
      begin
        note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT COUNT(*) FROM ")
      rescue StandardError
        nil
      end
      ConcolicIntValue.new(ct.seed_for(vn, 1), name: vn, note: note)
    end)

    # 5b-iii(c). Relation#size -> ConcolicIntValue, C7 (2026-09-01).
    # THE THIRD AGG-COLLAPSE in the shared calculations family, and the one that
    # explains two of this cycle's unexplained multiplicity rows.
    # `ActiveRecord::Relation#size` on an UNLOADED relation issues
    # `SELECT COUNT(*) …`; the shared boundary's mock notes it with
    # `sql_for(receiver, args)`, i.e. the ROW projection. On mobile,
    # `_header.mobile.haml` reads `current_user.unread_notifications.size`
    # twice, so the corpus recorded `SELECT "notifications".* … unread = ?`
    # THREE times per mobile dump (754 of 800) where a real request issues it
    # ONCE, and correspondingly recorded only 3 of the real 4
    # `SELECT COUNT(*) … unread` statements. Both the OVER and the UNDER in the
    # count matrix are this one bug.
    # Same batch-local remedy as `count` and `sum`: rewrite the PROJECTION only.
    # BOUNDARY NOTE (Rule T3, reported not patched): `size` is 0-invoked on
    # comments_index and conversations_index, so this endpoint is the first to
    # exercise it and the first that could see it.
    interceptor.declare_target(rel, :size, returns: lambda do |receiver, args, name|
      vn = "#{name}_size"
      note = ct.sql_for(receiver, args)
      begin
        note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT COUNT(*) FROM ")
      rescue StandardError
        nil
      end
      ConcolicIntValue.new(ct.seed_for(vn, 1), name: vn, note: note)
    end)

    # 5b-iii(b). Relation#sum -> ConcolicIntValue, C7 (2026-09-01).
    # Found only once the layout pin was withdrawn: `Calculations#sum` had
    # never been invoked in 879 248 symbolic_call events, and the moment it
    # was, its note came out of the SHARED generic calculations mock as
    # `SELECT "conversation_visibilities".* FROM ...` — the row projection —
    # against the real statement
    # `SELECT SUM("conversation_visibilities"."unread") FROM ...`
    # (measured, `_c7_layout_probe2_run.json`, both html and mobile).
    # Same AGG-COLLAPSE class the `count` repair above fixes, and the same
    # batch-local remedy: rewrite the PROJECTION only, leaving tables, joins
    # and predicates untouched. The aggregated COLUMN comes from the call's
    # own argument (`user.rb:114`
    # `ConversationVisibility.where(person_id: self.person_id).sum(:unread)`).
    # NOTE FOR THE BOUNDARY (Rule T3, reported not patched): the generic
    # `%i[count sum]` mock in concolic_targets.rb renders a row projection for
    # BOTH, and `count` is only correct here because this batch overrides it.
    # Any endpoint that calls `sum` without a local override emits a wrong
    # note; conversations_index invokes `sum` 18 306 times.
    interceptor.declare_target(calc, :sum, returns: lambda do |receiver, args, name|
      vn = "#{name}_sum"
      note = ct.sql_for(receiver, args)
      begin
        # `args` is the interceptor's call_args HASH — parameter NAME => value,
        # e.g. {"splat_args" => "unread", "kwargs" => nil, "block" => nil}.
        # The first version flattened it and took the first String, which is the
        # KEY: the corpus emitted `SUM("conversation_visibilities"."splat_args")`
        # 4 612 times before `_c7_count_matrix.py` compared it against the real
        # statement and reported the aggregate shape MISSING. Take the VALUE.
        vals = args.is_a?(::Hash) ? args.values : Array(args)
        col = vals.flatten.compact.find { |a| a.is_a?(::Symbol) || a.is_a?(::String) }
        if col
          tbl = (receiver.respond_to?(:table_name) && receiver.table_name) ||
                (receiver.respond_to?(:klass) && receiver.klass.table_name)
          proj = tbl ? %(SUM("#{tbl}"."#{col}")) : %(SUM("#{col}"))
          note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT #{proj} FROM ")
        end
      rescue StandardError
        nil
      end
      ConcolicIntValue.new(ct.seed_for(vn, 0), name: vn, note: note)
    end)

    # -----------------------------------------------------------------
    # 5c. Date-shaped symbolic value + column wiring.
    #
    # `symbolic_instance` maps every non-integer/boolean column to
    # SymbolicString, so the `datetime` column `notifications.updated_at` has
    # no #strftime and notifications#index dies at
    #   `@group_days = @notifications.group_by {|note| note.updated_at.strftime(..) }`
    # -----------------------------------------------------------------
    unless defined?(ConcolicDate)
      ::Object.const_set(:ConcolicDate, Class.new(::Date) do
        attr_writer :sym_year
        def year
          @sym_year || super
        end
      end)
    end

    # 5c-wiring + 5a-wiring + results3 §5g: batch-local WRAPPER around the
    # shared `symbolic_instance`. After the generic build, rewrite the attrs
    # hash the singleton readers close over: date/datetime -> ConcolicDate;
    # integer/bigint -> ConcolicIntValue (same var name/seed/note, now
    # quotable); §5g: `text`, if present, -> concrete String (identity shim).
    unless ConcolicTargets.respond_to?(:symbolic_instance_without_ni_values)
      class << ConcolicTargets
        alias_method :symbolic_instance_without_ni_values, :symbolic_instance
        def symbolic_instance(klass, base_name, sql)
          # T1c repair, layer 2 (2026-08-21): a bare base-`Post` rep is a
          # branch-foreclosing concretization — real posts rows always
          # carry a concrete STI type, and `post.respond_to?(:photos)` is
          # FALSE on base Post (has_many :photos lives on StatusMessage),
          # which kept the photos branch dead even after `_text_nil`
          # opened `message.present? == false`. §5f idiom: seeded,
          # PC-recorded STI dispatch BEFORE the build so every downstream
          # pin/typing applies to the STI-classed instance; `type` pinned
          # concrete below (post-build) for is_a?/compute_type dispatch.
          post_sti = nil
          if klass.name == "Post"
            sti_types = %w[StatusMessage Reshare]
            pidx = symint("SYM_POST_STI", seed_for("SYM_POST_STI", 0),
                          note: "posts STI dispatch (0=StatusMessage,1=Reshare)")
            pchosen = 0
            sti_types.each_index { |i| pchosen = i if pidx == i }
            post_sti = sti_types[pchosen]
            klass = (Object.const_get(post_sti) rescue klass)
          end
          obj = symbolic_instance_without_ni_values(klass, base_name, sql)
          if post_sti && obj.respond_to?(:concolic_attrs)
            obj.concolic_attrs["type"] = post_sti
            obj.define_singleton_method(:type) { post_sti }
          end
          return obj unless obj.respond_to?(:concolic_attrs)
          attrs = obj.concolic_attrs
          klass.columns_hash.each do |col, meta|
            case meta.type
            when :date, :datetime
              vn = "#{base_name}_#{col}_year"
              d = ConcolicDate.new(1990, 1, 1)
              d.sym_year = symint(vn, seed_for(vn, 1990), note: sql)
              attrs[col] = d
              obj.define_singleton_method(col) { d }
            when :integer, :bigint
              old = attrs[col]
              next unless old.is_a?(SymbolicInt)
              nv = ConcolicIntValue.new(old.value, name: old.sym_name, note: old.note)
              attrs[col] = nv
              obj.define_singleton_method(col) { nv }
            end
          end

          # gen2 (2026-08-19): Mention representatives — pin the polymorphic
          # `mentions_container_type` to a CONCRETE class string chosen by a
          # seeded, PC-recorded decision (the §5f idiom, same rationale as
          # the Notification type/target_type pins: `compute_type`/
          # constantize does multi-char `.split` on the type string — the
          # SymbolicString wall that killed 310 type-4/5 first-corpus runs
          # at mentioned.rb:8 — and concrete-vs-symbolic class dispatch
          # cannot compare). Containers driven: Post (default) and Comment,
          # the two classes the driven STI types really produce.
          # `mentions_container_id` stays genuinely symbolic — the container
          # fetch still renders a real `$$()`-bind SQL note.
          if klass.name == "Mention"
            # gen2b REVISION: derive the container class from the ACTIVE
            # note-type profile (mentioned -> Post, mentioned_in_comment ->
            # Comment) instead of an independent seeded decision — the
            # container class is structurally DETERMINED by the STI type in
            # the app (MentionedInPost/MentionedInComment), so an extra
            # decision axis fabricated infeasible crossings (see §5f stash
            # comment). No PC is recorded here because there is no free
            # branch: the type decision (SYM_NOTE_TYPE_PROFILE) already
            # carries it.
            akey = NotificationsIndexTargets.instance_variable_get(:@active_note_profile)
            mc_ctype = (akey == "mentioned_in_comment") ? "Comment" : "Post"
            attrs["mentions_container_type"] = mc_ctype
            obj.define_singleton_method(:mentions_container_type) { mc_ctype }
            # gen2c: the Mention rep's `guid` feeds ONLY the comment anchor
            # (`post_path(post, anchor: mentioned.guid)`, helper:45) — route
            # generation gsub's it, a SymbolicString wall (378+48 type-5
            # runs). Same §5i display-leaf class as to_param: pin it to a
            # render-safe ConcreteSymbolicString (sampled content; no
            # branchable compare on mention guids exists on this endpoint).
            mg = ConcreteSymbolicString.build("concolicmentionguid",
                   name: nil, note: "Mention#guid anchor leaf")
            attrs["guid"] = mg
            obj.define_singleton_method(:guid) { mg }
          end

          # gen3 auth-chain (2026-08-20): plumbing pins for ANY User
          # representative — the Devise-resolved user (auth_chain scenario:
          # serialize_from_session -> finder mock -> symbolic_instance)
          # doesn't pass through run_dse's symbolic_user(), so the
          # framework-plumbing pins documented there (language -> I18n
          # locale wall, gender -> SymbolicString#tr wall) must live here,
          # on the class, not on the one hand-built instance. Identity
          # pins, not query columns — same argument as run_dse.rb's.
          if klass.name == "User"
            # T-f (M-5, coordinator harvest 2026-08-28) — MODELLED, not pinned.
            # `set_locale` is an ApplicationController before_action, so it runs
            # on THIS endpoint too: `I18n.locale = current_user.language`
            # (application_controller.rb:100-107). `users.language` is NOT NULL
            # with no CHECK and no validation against the shipped locale set, so
            # a value dropped by an upgrade survives in the column and
            # `I18n.locale=` raises `I18n::InvalidLocale` BEFORE the action body
            # — one statement (the Devise principal load), then 500. That state
            # cannot be argued away, so it is a DECISION here and `run_dse.rb`
            # dispatches the REAL `set_locale`: the raise is the app's own, not
            # a fabricated one.
            # LAZY: the decision is minted only when the column is actually
            # READ. `set_locale` reads it on the DEVISE PRINCIPAL; every other
            # User representative this endpoint builds (a notification's
            # `recipient`) is never asked for its language, and minting the PC
            # there anyway would put a decision with no consequence into every
            # clique the checker enumerates.
            # Rule G: the decision must be PC-VISIBLE UNDER ITS COLUMN NAME —
            # `pc_visibility_audit --gate language` matches a variable whose name
            # ENDS with `_language`, so the decision is named for the column it
            # is about (`<rep>_stale_language`, true = the stored value is no
            # longer a shipped locale), not for its own predicate.
            lang_stale_name = "#{base_name}_stale_language"
            lang_note = sql
            lang_read = lambda do
              stale = symbool(lang_stale_name, ConcolicTargets.seed_for(lang_stale_name, false),
                              note: lang_note)
              (stale == true) ? "zz-dropped-locale" : "en"
            end
            attrs["language"] = "en" # AR attribute protocol (`user[:language]`);
                                     # nothing on this endpoint reads it that way.
            obj.define_singleton_method(:language) do
              @concolic_language ||= lang_read.call
            end
            # RULE S / T4 (2026-08-28): the `gender` pin is WITHDRAWN. `User#gender`
            # is not a users column — user.rb:59 DELEGATES it to `person`, which
            # delegates on to the profile, so pinning it stood over TWO real
            # association loads (both declared targets): a Class-S swallow of
            # exactly the kind `MessageRenderer#title` was. It was also inert
            # here: `set_grammatical_gender` is a before_action, and this runner
            # dispatches the action directly, so nothing in the corpus reads it.
            # (`language` IS a users column and stays — AR attribute protocol.)
          end

          # gen2b: Comment representatives — pin the polymorphic
          # `commentable_type` CONCRETE ("Post"): `comment.parent` ->
          # `commentable` -> belongs_to_polymorphic_association#klass ->
          # `constantize` -> multi-char split on a SymbolicString (the wall
          # that killed 120 type-4/5 gen3b runs). In this endpoint's shapes
          # a mention-bearing comment's commentable is a Post; the id stays
          # genuinely symbolic so the parent fetch renders a real $$-bind
          # SQL note.
          if klass.name == "Comment"
            attrs["commentable_type"] = "Post"
            obj.define_singleton_method(:commentable_type) { "Post" }
            # gen2d: the ANCHOR in `post_path(post, anchor: mentioned.guid)`
            # (helper:45) is the CONTAINER Comment's guid, not the Mention's
            # (the gen2c pin missed the receiver — 426 type-5 runs still
            # died in route-generation gsub). Same §5i display-leaf class:
            # render-safe concrete content; no branchable compare on comment
            # guids exists on this endpoint.
            cg = ConcreteSymbolicString.build("concoliccommentguid",
                   name: nil, note: "Comment#guid anchor leaf")
            attrs["guid"] = cg
            obj.define_singleton_method(:guid) { cg }
          end

          # cycle 2 (ADVERSARY W1 fallout / same class as W1): a PROFILE's
          # `bio` and `location` are message-rendered too —
          # `profile_presenter.rb:29 private_hash` -> `bio_message
          # .plain_text_for_json` (message_renderer.rb:188-192) runs
          # `normalize` + `diaspora_links` on them, so they are (a) never
          # symbolic strings at the renderer boundary and (b) able to carry a
          # `diaspora://…/post/<guid>` link that issues `Post.exists?`
          # exactly as a post's text does. Reached on this endpoint through
          # `_notification.haml:7` `gon_load_contact(note.contact)`. Same
          # decision family as `text`, minted ONCE per representative and
          # shared by both columns (they are one display surface, and a
          # second independent guid would only duplicate the same statement).
          disp_cols = %w[bio location] & attrs.keys
          unless disp_cols.empty?
            bd_name = "#{base_name}_disp_has_dlink"
            bio_dlink = symbool(bd_name, seed_for(bd_name, false), note: sql)
            suffix = ""
            if bio_dlink == true
              bp_name = "#{base_name}_disp_dlink_is_post"
              bis_post = symbool(bp_name, seed_for(bp_name, true), note: sql)
              # RULE V: same class — the guid parsed out of a bio/location body.
              bg_name = "SYM_PARAM_disp_dlink_guid_#{base_name}"
              bguid = symstr(bg_name, seed_for(bg_name, "concolicbioguid0000001"), note: sql)
              NotificationsIndexTargets.text_binds[bguid.value.to_s] = bguid
              suffix = " diaspora://concolic_link@example.org/" \
                       "#{bis_post == true ? 'post' : 'comment'}/#{bguid.value}"
            end
            disp_cols.each { |c| attrs[c] = "concolic #{c}#{suffix}" }
          end

          # results3 §5g — `text` identity shim (see file-header comment).
          # Mutating `attrs["text"]` is enough: the generic loop above already
          # defined `col` readers as `{ attrs[col] }` (live hash lookup), so
          # this flows through `.text`/`[]`/`read_attribute` with no further
          # singleton redefinition needed.
          if attrs.key?("text")
            # T1c repair (2026-08-21, DISCIPLINE_TESTS.md pin
            # branch-neutrality; witness = the reference diff's 10-query
            # photos family, all carrying `posts.text IS NULL`): the pin
            # seeded has_mention but NOT nil-ness, silently foreclosing
            # `message.present? == false` -> post_page_title's photos
            # branch across the whole corpus. `_text_nil` is the missing
            # branch-relevant dimension, seeded + PC-recorded like every
            # boundary decision; on its true side text is nil and the
            # photos association executes for real.
            tn_name = "#{base_name}_text_nil"
            text_nil = symbool(tn_name, seed_for(tn_name, false), note: sql)
            if text_nil == true
              attrs["text"] = nil
            else
              hm_name = "#{base_name}_text_has_mention"
              has_mention = symbool(hm_name, seed_for(hm_name, false), note: sql)
              # cycle 2 (ADVERSARY W1): the DIASPORA-LINK dimension. The pin
              # "text is never a query argument" was FALSE: a
              # `diaspora://<id>/post/<guid>` link in the text makes
              # MessageRenderer#diaspora_links (message_renderer.rb:100-105)
              # issue `Post.exists?(guid:)` — the guid parsed OUT of the text
              # IS the query argument. Seed the family as recorded decisions:
              #   _text_has_dlink     -> the text carries a diaspora:// link
              #   _text_dlink_is_post -> its entity is "post" (the renderer's
              #                          `Regexp.last_match(2) == "post"`
              #                          compare is on a concrete String, so
              #                          the decision is recorded HERE, at the
              #                          boundary that chooses the text)
              #   _text_dlink_guid    -> the guid, a SYMBOLIC var whose value
              #                          is embedded in the text and mapped
              #                          back at the query boundary
              #                          (text_binds / rebind_note_literals)
              dl_name = "#{base_name}_text_has_dlink"
              has_dlink = symbool(dl_name, seed_for(dl_name, false), note: sql)
              dlink = ""
              if has_dlink == true
                ip_name = "#{base_name}_text_dlink_is_post"
                is_post = symbool(ip_name, seed_for(ip_name, true), note: sql)
                # RULE V (DISCIPLINE §10, 2026-08-28): a value PARSED OUT OF a
                # column has no producing column. Named `<rep>_text_dlink_guid`
                # the fold binds it by its longest column-suffix — the row's OWN
                # `guid` — and the extracted view asserts a join the app never
                # performs. It is a POLICY PARAMETER: mint it in the
                # `SYM_PARAM_*` family (transform.py `_PARAM_BIND_RE`).
                gv_name = "SYM_PARAM_dlink_guid_#{base_name}"
                guid_v  = symstr(gv_name, seed_for(gv_name, "concolicdlinkguid000001"), note: sql)
                NotificationsIndexTargets.text_binds[guid_v.value.to_s] = guid_v
                dlink = " diaspora://concolic_link@example.org/" \
                        "#{is_post == true ? 'post' : 'comment'}/#{guid_v.value}"
              end
              attrs["text"] =
                if has_mention == true
                  # T1c dimension 3 (2026-08-21; witness = the 6 remaining
                  # mentioned-person-profiles reference queries): the
                  # two-part mention format carries the display name INLINE,
                  # so rendering never resolves the person's profile. Real
                  # data is full of handle-only mentions, whose rendering
                  # falls back to Person#name -> profile read. Seed the
                  # FORMAT dimension too.
                  in_name = "#{base_name}_mention_inline_name"
                  inline = symbool(in_name, seed_for(in_name, true), note: sql)
                  if inline == true
                    "hello @{Concolic Mention; concolic_mention@example.org} welcome#{dlink}"
                  else
                    "hello @{concolic_mention@example.org} welcome#{dlink}"
                  end
                else
                  "hello world, a concolic message with no mentions#{dlink}"
                end
            end
          end

          obj
        end
      end
    end

    # -----------------------------------------------------------------
    # -----------------------------------------------------------------
    # results3 §5h, REBUILT C7 (2026-09-01) — THE WALL MOVES TO
    # `Person#fix_profile`, AND THE SILENT-SUCCESS ARM IS DELETED.
    #
    # WHAT WAS HERE, AND WHY IT WAS WRONG (T-ac / M-15, T-ad / M-17).
    # The old wall sat on `Discovery.new` + `#fetch_and_save`, returning nil,
    # on the argument that "the real path aborts the JVM natively on this
    # JRuby (SIGSEGV in __libc_free)". That is the sentence DISCIPLINE §12's
    # amendment says is NOT an unreachability argument, and it is false as
    # written here — measured on this batch, not inherited:
    #   `_c7_discovery_probe.rb` / `_c7_fixprofile_probe.rb`: a
    #   `people.diaspora_handle` whose DOMAIN is not a legal URI host
    #   (`wraith@ba[d.example`) makes Faraday's `URI.parse` raise in PURE RUBY
    #   before the typhoeus adapter. `fix_profile` is ENTERED for real,
    #   `fetch_and_save` is ENTERED for real, it raises `DiscoveryError`,
    #   53 target calls, 12 statements, **0 JVM aborts**.
    # Worse than the wrong reason was the wrong SHAPE: returning nil modelled a
    # SUCCESS the app has no path to, and the corpus then explored everything
    # downstream of it. Census over the pre-C7 corpus (39 956 dumps, whole
    # population): 1 916 dumps record `*_profile_not_found == True`; **all
    # 1 916 end with a clean 200**, 1 906 of them emit `reload`'s single-row
    # re-read, and **0** carry the DiscoveryError terminal the app always
    # produces there. The real arm has exactly two outcomes — raise (no
    # `reload`, truncated) or succeed (13 statements incl. 3 writes) — and the
    # corpus asserted a third that does not exist.
    #
    # WHY THE WALL MOVES UP RATHER THAN AWAY.
    #  * Letting the real gem raise would require the SAMPLED handle to stay
    #    URI-hostile, and DSE flips string values freely; a flip to a parseable
    #    handle reaches the FFI and aborts the JVM mid-launch. That trades a
    #    deterministic model for a non-deterministic crash.
    #  * A wall that RAISES inside its `returns` lambda loses its note: the
    #    interceptor calls `SymbolicFunc.push_record` AFTER `value_fn.call`
    #    (src/ruby_runtime/call_interceptor.rb), so a raise means no event, no
    #    note, no statement — T-k / B-6 in the source.
    # Declaring `Person#fix_profile` skips its WHOLE body — `Discovery.new`,
    # `fetch_and_save` AND `reload` — so `Person#name` continues to
    # `self.profile.first_name` on a nil profile and the render raises. Same
    # statement set as the real failure arm, deterministically, with the note
    # preserved.
    #
    # THE ONE THING THIS DOES NOT REPRODUCE, stated rather than glossed: the
    # exception CLASS. The corpus carries the nil-profile `NoMethodError` where
    # the app raises `DiscoveryError`. Statement sets are identical and the
    # request 500s either way, but a consumer reading TERMINALS must be told
    # the substitution was made and why. It is declared in POLICY_HEADER.txt.
    #
    # MEASURED PRECONDITION for "same statement set" (coordinator condition 1,
    # 2026-09-01) — not inferred: `_c7_fixprofile_probe.rb` brackets the REAL
    # method with an `sql.active_record` subscriber and prints
    #   "[F1] EXIT  Person#fix_profile; statements issued INSIDE it: 0"
    # So the walled body issues NO SQL before it raises, and walling it drops
    # no real read.
    # -----------------------------------------------------------------
    begin
      require "diaspora_federation/discovery"
    rescue LoadError, StandardError => e
      warn "[notifications_index] diaspora_federation/discovery: #{e.class}"
    end
    if defined?(Person) && Person.instance_methods(false).include?(:fix_profile) ||
       (defined?(Person) && Person.private_instance_methods(false).include?(:fix_profile))
      interceptor.declare_target(Person, :fix_profile, returns: lambda do |receiver, _a, _n|
        # B-8: a declared wall still needs a note, or it reads as a SWALLOWED
        # statement. This body issues none (measured, above).
        handle = begin
          h = receiver.respond_to?(:diaspora_handle) ? receiver.diaspora_handle : nil
          h.respond_to?(:value) ? h.value.to_s : h.to_s
        rescue StandardError
          "<unavailable>"
        end
        Thread.current[:concolic_pending_note] =
          "WALL Person#fix_profile — federation discovery boundary " \
          "(person.rb:371-375: Discovery.new(#{handle}).fetch_and_save, then reload). " \
          "The RAISING arm is modelled: fetch_and_save raises DiscoveryError in pure Ruby " \
          "(URI::InvalidURIError before the adapter), reload is NEVER reached, and no SQL is " \
          "issued inside this body. The SUCCESS arm is DECLARED UNMODELLED (POLICY_HEADER.txt). " \
          "The render then raises on the nil profile: same statement set, substituted terminal."
        nil
      end)
      warn "[notifications_index] C7: Person#fix_profile wall declared (Discovery walls withdrawn)"
    else
      warn "[notifications_index] WARNING: Person#fix_profile wall NOT declared"
    end

    # -----------------------------------------------------------------
    # results3 §5h-bis, C8 (2026-09-10) — THE `fetch_and_save` WALL COMES
    # BACK, IN ITS RAISING FORM. COORDINATOR-AUTHORISED.
    #
    # READ THIS NEXT TO THE 2026-09-01 WITHDRAWAL NOTE ABOVE. That note is
    # still correct about the wall it withdrew: the OLD wall returned `nil`,
    # which modelled a SUCCESS the application has no path to, and the corpus
    # then explored everything downstream of a state that cannot exist (1 916
    # dumps ending in a clean 200 where the app always raises, 1 906 of them
    # emitting a `reload` the raising arm never reaches). Returning nil was
    # the defect. RAISING is not.
    #
    # WHY IT IS BACK. `Person#fix_profile` is not the only route into
    # discovery. `Person.find_or_fetch_by_identifier` (app/models/person.rb:
    # 318-329), reached from `lib/diaspora/mentionable.rb:89` whenever a
    # notification's text carries a mention, calls the SAME
    # `Discovery.new(id).fetch_and_save`:
    #
    #     person = by_account_identifier(diaspora_id)                  # find_by_1
    #     return person if person.present? && person.profile.present?
    #     DiasporaFederation::Discovery::Discovery.new(diaspora_id).fetch_and_save
    #
    # Walling `fix_profile` does not cover that call, so the two decisions on
    # line 321 — `<...>_find_by_1_not_found` and `<...>_find_by_1_profile_not_found`
    # — could only ever be observed on their FALSE side: taking either TRUE
    # entered the real `fetch_and_save`, which on this JRuby SIGSEGVs in
    # libcurl (`curl_easy_setopt` -> `__libc_free`, through com.kenai.jffi)
    # BEFORE the dump is written. Measured 2026-09-10: control-vs-flip on one
    # seed, base rc=0/1 path vs base+flip rc=134/0 paths; and 37 of 37 toxic
    # seeds in the C32A bulk drive set one of the two, against 0 of the 25.6 %
    # that set neither. Both outcomes stood in `tree_missing`, which refuses
    # the combination claim outright.
    #
    # THE SHAPE, AND WHY IT IS FAITHFUL. `fetch_and_save`'s RAISING arm is
    # what a real pod takes when discovery fails, and it is the arm this
    # environment can actually model: it raises before ANY data access, and
    # `Mentionable.find_or_fetch_person_by_identifier` (mentionable.rb:88-91)
    # RESCUES `DiscoveryError` to nil — the mention then renders as its raw
    # match string, the request does NOT 500, and no statement is invented.
    # The note is published BEFORE the raise, because the interceptor pushes
    # its record AFTER the `returns` lambda returns and a raise would
    # otherwise lose the wall entirely (B-8 / T-k / T-n).
    #
    # PRECEDENT: this is verbatim the form `results3/comments_index/targets.rb`
    # §8e ships, on a CLOSED endpoint. The SUCCESS arm stays DECLARED
    # UNMODELLED in POLICY_HEADER.txt (M-17) — walling it does not claim the
    # arm reads nothing, it declines to describe it, and the statements it
    # would gain are recorded in `_c7_discovery_gap_evidence.json`.
    #
    # RULE T: this is PER-BATCH material (Rule T1: shim mocks and this batch's
    # walls live in `targets.rb`; the shared query boundary is
    # `concolic_targets.rb`, which is NOT touched here). No closed endpoint is
    # voided by it. Authorised by the coordinator, 2026-09-10, in response to
    # the BOUNDARY CHANGES filing in AGENT_RUN.md.
    # -----------------------------------------------------------------
    if defined?(DiasporaFederation::Discovery::Discovery)
      discovery_returns = lambda do |_receiver, _args, _name|
        # B-8 / T-n: a mock that RAISES must still publish its note, or the
        # wall it stands for disappears from the corpus entirely.
        Thread.current[:concolic_pending_note] =
          "WALL DiasporaFederation::Discovery#fetch_and_save — webfinger network " \
          "boundary (person.rb:325, reached from mentionable.rb:89). Raises before " \
          "ANY data access; `Mentionable.find_or_fetch_person_by_identifier` rescues " \
          "DiscoveryError to nil and the mention renders as its raw text. The SUCCESS " \
          "arm is DECLARED UNMODELLED (POLICY_HEADER.txt, M-17); its statements are " \
          "recorded in _c7_discovery_gap_evidence.json."
        raise DiasporaFederation::Discovery::DiscoveryError,
              "concolic: webfinger discovery failed (wall: no HTTP adapter in this " \
              "environment; the success arm and its :save_person_after_webfinger " \
              "statements are NOT MODELLED)"
      end
      interceptor.declare_target(DiasporaFederation::Discovery::Discovery,
                                 :fetch_and_save, returns: discovery_returns)
      warn "[notifications_index] C8: Discovery#fetch_and_save RAISING wall declared " \
           "(coordinator-authorised 2026-09-10; the withdrawn wall returned nil, this one raises)"
    else
      warn "[notifications_index] WARNING: Discovery#fetch_and_save wall NOT declared " \
           "(DiasporaFederation::Discovery::Discovery undefined)"
    end

    # -----------------------------------------------------------------
    # results3 §5i. `to_param` leaf shim — see file-header comment.
    # `ConcreteSymbolicString`-wrapped (../concolic_targets.rb's X6i comment):
    # a bare String return from ANY declare_target mock gets silently
    # re-wrapped into a SymbolicString by the interceptor (only `nil` and
    # already-SymbolicVar-tagged values are exempt) — `to_param`'s return
    # feeds straight into `post_path`/`person_path`'s real URL-interpolation
    # code, which needs a genuine `.scrub`-capable string. CONFIRMED reached
    # (the URL helpers in notifications_helper.rb/people_helper.rb are on
    # every rendered notification row).
    # -----------------------------------------------------------------
    base = ActiveRecord::Base
    if base.instance_methods.include?(:to_param)
      interceptor.declare_target(base, :to_param, returns: lambda do |receiver, _args, name|
        id = receiver.respond_to?(:id) ? receiver.id : nil
        v = id.respond_to?(:value) ? id.value.to_s : id.to_s
        ConcreteSymbolicString.build(v, name: name, note: "ActiveRecord::Integration#to_param")
      end)
    end

    # -----------------------------------------------------------------
    # §gen2 class-level Gon.preloads (2026-08-19). gon_load_contact
    # (gon_helper.rb:5, reached by the started_sharing aspect-dropdown
    # branch) uses `Gon.preloads` — the CLASS-level accessor, which routes
    # through Gon's request env (nil in the direct-action rig; X6b stubbed
    # only the instance `gon` accessor). Same classification as X6b: pure
    # JS-var accumulation, no SQL, not branchable. The ContactPresenter
    # descent it guards still runs for real (that descent is the point —
    # rule-(b) enforcement, see BUGFIXES_20260819.md).
    # -----------------------------------------------------------------
    if defined?(::Gon) && !(defined?(@gon_class_shim) && @gon_class_shim)
      gon_shim = GonPreloadsShim
      ::Gon.singleton_class.prepend(gon_shim)
      @gon_class_shim = true
    end

    # -----------------------------------------------------------------
    # §gen2 CollectionAssociation#size coerce leaf-shim (2026-08-19, see
    # ../BUGFIXES_20260819.md). The persisted-decision exploration reaches
    # collection_association.rb:216-217 (`unsaved_records.size +
    # count_records`) — with the unloaded association's in-memory target
    # EMPTY the sum is `0 + count_records`, but Integer#+ on the mocked
    # SymbolicInt count hits SymbolicInt#coerce (reflected arithmetic is
    # unsupported by DESIGN; 86/400 first-corpus runs died here). Return
    # count_records directly in exactly that case — arithmetically identical
    # (0 + x == x), the COUNT SQL still flows through the declared
    # Calculations#count mock, and every other branch falls through to the
    # real body (a non-empty target would honestly crash again). Prepend,
    # not declare_target: the real body issues SQL via count_records, so the
    # discipline forbids mocking the whole method.
    # -----------------------------------------------------------------
    unless defined?(@size_coerce_shim_installed) && @size_coerce_shim_installed
      shim = Module.new do
        def size
          if !find_target? || loaded?
            super
          elsif !association_scope.group_values.empty?
            super
          elsif !association_scope.distinct_value && target.is_a?(Array) && target.empty?
            count_records
          else
            super
          end
        end
      end
      ActiveRecord::Associations::CollectionAssociation.prepend(shim)
      @size_coerce_shim_installed = true
    end

    # -----------------------------------------------------------------
    # completion drive (2026-08-27, note_check RED): User#blocks re-declared
    # to return a REAL SCOPED RELATION `Block.where(user_id: id)` instead of
    # an IterableSymbolicList. On THIS endpoint blocks is read ONLY via
    # `block_for(person)` -> `blocks.find_by(person_id: person.id)`
    # (user/querying.rb:33, reached from PersonPresenter#is_blocked? in the
    # StartedSharing gon_load_contact descent). The old IterableSymbolicList
    # answered find_by with its OWN method, which emitted the person_id
    # predicate as a SYMBOLIC_VAR note, invisible to the note check /
    # extraction (D1 gap: the real statement's person_id predicate had no
    # target-EVENT note). A real scoped Relation routes `.find_by(person_id:)`
    # through the declared FinderMethods#find_by target, which emits a
    # symbolic_call event whose note carries the full
    # `WHERE user_id = $$ AND person_id = $$` shape (the ConcolicKwargsTo-
    # Positional thread-local captures the person_id kwarg). No length-only
    # list is needed here (nothing on this endpoint iterates blocks; the
    # index only find_by's it). The memory note's "blocks must stay a
    # length-only list for streams/posts" does not apply — this is the
    # photos/users_sessions case (find_by), scoped to this batch.
    # -----------------------------------------------------------------
    if defined?(User) && defined?(Block)
      interceptor.declare_target(User, :blocks, returns: lambda do |receiver, _args, _name|
        owner_id = receiver.respond_to?(:[]) ? receiver[:id] : receiver.id
        # B-8: the reader itself issues NOTHING — it returns a Relation, and the
        # statement is issued at materialization by the collection target with
        # its own note. Say so rather than leaving the event note-less.
        Thread.current[:concolic_pending_note] =
          "User#blocks returns the Block.where(user_id: …) RELATION; the statement is issued at " \
          "materialization by the collection target, with its own note"
        Block.where(user_id: owner_id)
      end)
    end

    # -----------------------------------------------------------------
    # gen2e: Calculations#pluck -> sampled-contents list (ported from the
    # conversations_index batch, simplified). The LAST gen3e wall (1 run):
    # ProfilePresenter#public_hash `tags.pluck(:name)` in the
    # started_sharing descent. Shared file declares pluck UNSUPPORTED, but
    # pluck IS the query boundary (same role as records/to_a) — the tags
    # join is REAL SQL this endpoint should capture. Thread-local stash for
    # the column names because the interceptor's *rest binding drops them
    # (same class as BUGFIXES_20260819 bug 2a).
    # -----------------------------------------------------------------
    pluck_args = Module.new do
      def pluck(*column_names)
        prev = Thread.current[:ni_pluck_cols]
        Thread.current[:ni_pluck_cols] = column_names.flatten.map(&:to_s)
        super
      ensure
        Thread.current[:ni_pluck_cols] = prev
      end
    end
    ActiveRecord::Relation.prepend(pluck_args)

    interceptor.declare_target(ActiveRecord::Calculations, :pluck, returns: lambda do |receiver, args, name|
      note = ConcolicTargets.sql_for(receiver, args)
      cols = Thread.current[:ni_pluck_cols] || []
      # Statement-shape fidelity (2026-08-21, the taggings.id residue): the
      # real pluck statement projects EXACTLY the requested columns
      # (`SELECT tags.name, taggings.id FROM ...`), while sql_for renders the
      # receiver's default select list (`SELECT "tags".* ...`). The broadened
      # note lost the joined-table column from the view's output set, so the
      # reference query projecting taggings.id could never be covered.
      # Rewrite the note's SELECT list with the captured pluck columns.
      unless cols.empty?
        # CYCLE 6 (hardening_lint H6, 2026-08-29): the order columns are NO
        # LONGER appended to the projection. The 2026-08-21 claim that "real
        # pluck projects order columns alongside the requested ones" cited a
        # REFERENCE trace; this batch's own 13 REAL runs contradict it —
        # `SELECT "tags"."name" FROM "tags" INNER JOIN "taggings" … ORDER BY
        # taggings.id` projects the requested column ONLY, with the order
        # column in ORDER BY where it belongs (Rule T4: pluck ⇒ its real
        # projection + ORDER). Bare columns are still qualified with the
        # relation's table (real pluck renders "tags"."name").
        own_table = begin
          ConcolicTargets.model_class(receiver).table_name
        rescue StandardError
          nil
        end
        qualified = cols.map { |c| c.include?(".") || own_table.nil? ? c : "#{own_table}.#{c}" }
        proj = qualified.map { |c|
          if c.include?(".")
            t, col = c.split(".", 2)
            %("#{t}"."#{col}")
          else
            %("#{c}")
          end
        }.join(", ")
        note = note.sub(/\ASELECT .*? FROM /m, "SELECT #{proj} FROM ")
      end
      cols = ["value"] if cols.empty?
      vals = cols.each_with_index.map do |c, i|
        var = cols.size == 1 ? "#{name}_pluck_#{c.split('.').last}" : "#{name}_pluck#{i}_#{c.split('.').last}"
        symstr(var, ConcolicTargets.seed_for(var, "#{var}_v"), note: note)
      end
      rep = cols.size == 1 ? vals.first : vals
      IterableSymbolicList.new(ConcolicTargets.seed_for("len(#{name}_plucked)", 1),
                               name: "#{name}_plucked", note: note, representative: rep)
    end)

    warn "[notifications_index] NotificationsIndexTargets installed"
  end
end

# =============================================================================
# NotifDeviseUserNaming — REAL current_user resolution (ported from
# conversations_index's ConvDeviseUserNaming, cycle 1 of the completion
# drive). D1 (evidence equivalence): a runner that OVERRIDES current_user
# with a hand-built symbolic user and OVERRIDES its associations SWALLOWS the
# two statements the REAL signed-in endpoint issues to resolve the session —
# `SELECT users.* WHERE id = ?` (Devise serialize_from_session ->
# OrmAdapter::ActiveRecord#get) and `SELECT people.* WHERE owner_id = ?`
# (the real has_one :person, notifications_helper reaches current_user.person
# in person_link_class). The old notifications runner did exactly that.
#
# FIX: resolve current_user through the REAL User.serialize_from_session with
# a SYMBOLIC session key (SYM_USER_NI_id — identity_symbolicity: a literal key
# folds every signed-in view as users.id = 1), and DO NOT override
# user.person (the real has_one association fires). Runner-local plumbing:
#   (a) authenticatable_salt leaf shim — pure encrypted_password[0,29] slice.
#   (b) devise_user_first — a CALL-SITE-STABLE alias of FinderMethods#first
#       for the ONE `.first` inside OrmAdapter::ActiveRecord#get, so the Devise
#       users lookup does not take the shared first_1 ordinal.
# =============================================================================
module NotifDeviseUserNaming
  module OrmAdapterGetNaming
    def get(id)
      klass.where(klass.primary_key => wrap_key(id)).devise_user_first
    end
  end

  # (a2) The session-user decorations live in a NAMED method (Rule S,
  # 2026-08-27): defined inside the target's return lambda they could only
  # be reached by INVOKING that target, which no shim test may do. Same
  # bodies, same call site — just addressable.
  def self.decorate_session_user!(u)
    if u.respond_to?(:define_singleton_method)
      u.define_singleton_method(:persisted?)  { true }
      u.define_singleton_method(:new_record?) { false }
      # unread_notifications — manual scoping of the has_many :notifications
      # (foreign_key recipient_id) + .where(unread: true), mirroring the real
      # User#unread_notifications body (user.rb:109-111). Same SQL SHAPE the
      # real association issues; the real reader cannot build a scope off a
      # symbolic owner id on an allocated instance (the ConvoSymAssociations
      # rationale). Pin ledger: manual scoping, D1-equivalent statement.
      u.define_singleton_method(:unread_notifications) do
        Notification.where(recipient_id: u.id, unread: true)
      end
      # before_action plumbing pins (set_locale / set_grammatical_gender):
      # these run in the auth chain, not the action; language/gender are not
      # identity or query columns. symbolic_instance's User branch already
      # pins language/gender, so nothing extra needed here.
    end
    u
  end

  def self.install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets
    return unless defined?(User) && defined?(OrmAdapter::ActiveRecord)

    fm = ActiveRecord::FinderMethods
    unless fm.method_defined?(:devise_user_first)
      fm.send(:alias_method, :devise_user_first, :first)
    end
    interceptor.declare_target(fm, :devise_user_first, returns: lambda do |receiver, args, name|
      u = ct.symbolic_instance(ct.model_class(receiver), name,
                               ct.finder_note(receiver, args, :devise_user_first))
      decorate_session_user!(u)
      u
    end)


    # (a) salt leaf shim (idempotent)
    unless User.instance_variable_get(:@notif_salt_shim)
      salt_shim = Module.new do
        def authenticatable_salt
          if defined?(ConcreteSymbolicString)
            ConcreteSymbolicString.build("concolicsalt", name: nil,
              note: "User#authenticatable_salt leaf (encrypted_password[0,29] slice)")
          else
            "concolicsalt"
          end
        end
      end
      User.prepend(salt_shim)
      User.instance_variable_set(:@notif_salt_shim, true)
    end

    # (b) route the ONE .first inside OrmAdapter::ActiveRecord#get to the alias
    OrmAdapter::ActiveRecord.prepend(OrmAdapterGetNaming) unless
      OrmAdapter::ActiveRecord < OrmAdapterGetNaming

    warn "[notifications devise] NotifDeviseUserNaming installed"
  end
end
