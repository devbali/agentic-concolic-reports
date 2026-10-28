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
    {key: "also_commented",       sti: "Notifications::AlsoCommented",      target_type: "Comment"},
    {key: "comment_on_post",      sti: "Notifications::CommentOnPost",      target_type: "Comment"},
    # (Notifications::Mentioned is a CONCERN module, not an STI class —
    # found live via `allocate` NoMethodError; the concrete class is
    # MentionedInPost.)
    {key: "mentioned",            sti: "Notifications::MentionedInPost",    target_type: "Mention"},
    {key: "mentioned_in_comment", sti: "Notifications::MentionedInComment", target_type: "Mention"},
    {key: "started_sharing",      sti: "Notifications::StartedSharing",     target_type: "Person"},
    {key: "contacts_birthday",    sti: "Notifications::ContactsBirthday",   target_type: "Person"}
  ].freeze

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
    helper_proxy = ActionController::Base.helpers
    asset_shim = Module.new do
      def compute_asset_path(source, _options = {})
        "/assets/#{source}"
      end
    end
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
    def build_representative(ct, receiver, base_name, sql)
      klass = ct.model_class(receiver)
      return build_notification_representative(ct, base_name, sql) if klass == Notification
      ct.symbolic_instance(klass, base_name, sql)
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
    def emit_includes_preloads(ct, receiver, rep)
      iv = receiver.respond_to?(:includes_values) ? Array(receiver.includes_values) : []
      return if iv.empty?
      owner_klass = ct.model_class(receiver)
      rep_attrs   = rep.respond_to?(:concolic_attrs) ? rep.concolic_attrs : {}
      emit = nil
      emit = lambda do |k, spec, bind_of|
        pairs = spec.is_a?(Hash) ? spec.to_a : [[spec, nil]]
        pairs.each do |aname, nested|
          r2 = (k.reflect_on_association(aname.to_sym) rescue nil)
          next unless r2 && !r2.polymorphic?
          if r2.belongs_to?
            bindv = bind_of.call(r2.foreign_key.to_s)
            next if bindv.nil?
            psql = %(SELECT "#{r2.table_name}".* FROM "#{r2.table_name}" WHERE "#{r2.table_name}"."id" = #{ct.render_arg_value(bindv)})
            # child row id has the SAME value as the fk we bound on
            child_bind = lambda { |col| col == "id" ? bindv : nil }
          else
            bindv = bind_of.call("id")
            next if bindv.nil?
            thr = (r2.respond_to?(:through_reflection) && r2.through_reflection) || nil
            if thr
              # has_many/has_one :through — the real Preloader's FIRST query
              # is the through-table fetch keyed on the owner; later steps key
              # on through-row columns we hold no vars for (rendering them as
              # direct columns fabricates non-existent columns, e.g.
              # people.person_id). Emit step 1, stop the chain honestly.
              psql = %(SELECT "#{thr.table_name}".* FROM "#{thr.table_name}" WHERE "#{thr.table_name}"."#{thr.foreign_key}" = #{ct.render_arg_value(bindv)})
            else
              psql = %(SELECT "#{r2.table_name}".* FROM "#{r2.table_name}" WHERE "#{r2.table_name}"."#{r2.foreign_key}" = #{ct.render_arg_value(bindv)})
            end
            child_bind = lambda { |_col| nil } # child ids unknown — stop chain honestly
          end
          ConcolicThroughLoadProbe.load_intermediate(psql)
          emit.call(r2.klass, nested, child_bind) if nested
        end
      end
      iv.each { |spec| emit.call(owner_klass, spec, lambda { |col| rep_attrs[col] }) }
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
      attrs["target_type"] = profile[:target_type]
      obj
    end

    %i[to_a records].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        vn  = "#{name}_rows"
        sql = ct.sql_for(receiver, args)
        rep = build_representative(ct, receiver, "#{name}_row", sql)
        emit_includes_preloads(ct, receiver, rep) # T1b repair #2, see §helper
        IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn,
                                 note: sql, representative: rep)
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
      len = ct.seed_for("len(#{vn})", 1).to_i
      rep = build_representative(ct, receiver, "#{name}_row", sql)
      emit_includes_preloads(ct, receiver, rep) # T1b repair #2, see §helper
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
          vn  = "#{name}_rows"
          sql = ct.sql_for(receiver, args)
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
          rep = build_representative(ct, receiver, "#{name}_row", sql)
          emit_includes_preloads(ct, receiver, rep) # T1b repair #2, see §helper
          IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn,
                                   note: sql, representative: rep)
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
            attrs["language"] = "en"
            obj.define_singleton_method(:language) { "en" }
            ug = ConcreteSymbolicString.build("", name: nil, note: "User#gender plumbing pin")
            attrs["gender"] = ug
            obj.define_singleton_method(:gender) { ug }
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
                    "hello @{Concolic Mention; concolic_mention@example.org} welcome"
                  else
                    "hello @{concolic_mention@example.org} welcome"
                  end
                else
                  "hello world, a concolic message with no mentions"
                end
            end
          end

          obj
        end
      end
    end

    # -----------------------------------------------------------------
    # results3 §5h. DiasporaFederation::Discovery::Discovery#fetch_and_save
    # -> nil. Network-I/O wall (coordinator directive: never let it fire).
    # See file-header comment for the full call chain / why it's dormant by
    # default and only reachable via a DSE-driven not-found flip.
    # -----------------------------------------------------------------
    if defined?(DiasporaFederation::Discovery::Discovery) &&
       DiasporaFederation::Discovery::Discovery.instance_methods.include?(:fetch_and_save)
      interceptor.declare_target(DiasporaFederation::Discovery::Discovery, :fetch_and_save,
                                 returns: ->(_r, _a, _n) { nil })
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
      gon_shim = Module.new do
        def preloads
          @concolic_preloads ||= {}
        end
      end
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
        # Ground-truth (probe _probe_tags_sql.rb, 2026-08-21): the tags
        # association scope carries `ORDER BY taggings.id`, and real pluck
        # projects order columns alongside the requested ones — the
        # reference trace's `SELECT tags.name, taggings.id`. Append any
        # order columns not already requested, and qualify bare columns
        # with the relation's table (real pluck renders "tags"."name").
        own_table = begin
          ConcolicTargets.model_class(receiver).table_name
        rescue StandardError
          nil
        end
        qualified = cols.map { |c| c.include?(".") || own_table.nil? ? c : "#{own_table}.#{c}" }
        begin
          Array(receiver.order_values).each do |ov|
            s = ov.is_a?(String) ? ov : (ov.respond_to?(:expr) ? ov.expr.to_s : ov.to_s)
            s.split(",").map(&:strip).each do |c0|
              c = c0.sub(/\s+(ASC|DESC)\z/i, "")
              next unless c =~ /\A[\w.]+\z/
              qualified << c unless qualified.include?(c)
            end
          end
        rescue StandardError
          nil
        end
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

  def self.install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets
    return unless defined?(User) && defined?(OrmAdapter::ActiveRecord)

    fm = ActiveRecord::FinderMethods
    unless fm.method_defined?(:devise_user_first)
      fm.send(:alias_method, :devise_user_first, :first)
    end
    interceptor.declare_target(fm, :devise_user_first, returns: lambda do |receiver, args, name|
      u = ct.symbolic_instance(ct.model_class(receiver), name, ct.sql_for(receiver, args))
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
