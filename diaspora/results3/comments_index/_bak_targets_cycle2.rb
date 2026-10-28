# frozen_string_literal: true
#
# Per-batch concolic targets — `comments`.
#
# WHY THIS FILE EXISTS
# --------------------
# `reports/diaspora/concolic_targets.rb` is shared by all 13 batches, so wall
# fixes that are correct HERE can be wrong elsewhere. This overlay installs
# AFTER `ConcolicTargets.install!`; `declare_target` uses `define_method`, so a
# later declaration replaces an earlier one (last-one-wins, no registry needed).
#
#   ConcolicTargets.install!(interceptor)   # shared generic AR interception
#   CommentsTargets.install!(interceptor)   # this file — batch-local wall fixes
#
# TWO RULES EVERY MOCK BELOW OBEYS
# --------------------------------
# 1. Wrap the SMALLEST enclosing method whose real body contains NO SQL, and
#    NEVER one whose body contains the `if` that produces the path condition it
#    guards (README wall-fixing discipline + the addendum's most-important rule).
# 2. When a wall is "the runtime is missing method X on a symbolic VALUE", fix
#    the VALUE, not its consumer — §3 and §5 define batch-local SUBCLASSES of
#    the runtime's symbolic classes that add the missing method. Mocking the
#    consumer instead is what swallows branches.
#
# Nothing in `src/`, in the shared `concolic_targets.rb`, or in the diaspora app
# source is modified.

module CommentsTargets
  module_function

  # ---------------------------------------------------------------------
  # Resolve the concrete class named by a polymorphic association's type
  # column. Shared by mocks 1 and 2 below.
  #
  # On a symbolic record `commentable_type` is a SymbolicString, so the real
  # `type.presence && type.constantize` walls (see §1). Here we read the
  # concrete value out of the wrapper and constantize THAT, falling back to
  # `Post` — every commentable in this app is a Post subclass.
  # ---------------------------------------------------------------------
  def poly_klass(receiver)
    raw = begin
      receiver.owner[receiver.reflection.foreign_type]
    rescue StandardError
      nil
    end
    s = raw.respond_to?(:value) ? raw.value : raw
    begin
      s.to_s.constantize
    rescue StandardError, NameError, LoadError
      Post
    end
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

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    # =====================================================================
    # 1. BelongsToPolymorphicAssociation#klass
    #
    # `CommentService#destroy` evaluates `user.owns?(comment.parent)`, and
    # `parent` is the POLYMORPHIC `belongs_to :commentable`. AR resolves the
    # target class through this method, whose real body is
    #
    #     type = owner[reflection.foreign_type]
    #     type.presence && type.constantize
    #
    # On a symbolic record `commentable_type` is a SymbolicString, so BOTH
    # sides of that framework check wall out:
    #
    #   type.presence non-blank -> String#constantize -> split("::")
    #        -> NotImplementedError: SymbolicString#split only supports
    #           single-character separators      (src/ruby_runtime/string.rb:231)
    #   type.presence blank     -> klass nil -> parent nil -> Person#owns?
    #        -> NoMethodError: undefined method `author_id' for nil:NilClass
    #           (app/models/person.rb:278)
    #
    # ...and the second half of `owns?(comment) || owns?(comment.parent)` is
    # unreachable.
    #
    # LEGAL MOCK UNIT: the real body contains NO SQL and calls no other
    # declared target — it is pure type-string -> Class resolution. It also
    # contains no app branch: the only conditional in it is AR's own
    # `type.presence` blank check (framework plumbing, not an app decision),
    # which is the one PC this mock costs. Returns a `Class`, which the
    # interceptor passes through unwrapped.
    # =====================================================================
    if defined?(ActiveRecord::Associations::BelongsToPolymorphicAssociation)
      btpa = ActiveRecord::Associations::BelongsToPolymorphicAssociation

      interceptor.declare_target(btpa, :klass, returns: lambda do |receiver, _args, _name|
        poly_klass(receiver)
      end)

      # =====================================================================
      # 2. BelongsToPolymorphicAssociation#find_target
      #
      # Mock 1 alone is not enough. The shared §W3 target
      # (`SingularAssociation#find_target`) resolves the association class via
      # `reflection.klass`, which RAISES for a polymorphic belongs_to — so W3
      # rescues to nil and `comment.parent` comes back nil anyway. Declaring
      # #find_target on the POLYMORPHIC SUBCLASS shadows W3 for exactly this
      # case and nothing else.
      #
      # LEGAL MOCK UNIT: the real body's only content is the association load
      # query — precisely what every finder mock in the shared file already
      # replaces. It contains no app branch. The returned instance's columns
      # are SEEDABLE (`symbolic_instance` routes through `seed_for`), which is
      # what turns `owns?(parent)` into the flippable
      # `(assoc_commentable_author_id == 1)` branch rather than an inert
      # constant — the addendum's "make the VALUE seedable" pattern.
      # =====================================================================
      # results3 Phase A Patch 1b (../PHASE_A_PATCH.md): render the real SQL
      # this stands in for (FK column lives on the OWNER for belongs_to;
      # target queried by its own PK) instead of the junk
      # "BelongsToPolymorphicAssociation#name" note. Never let note-building
      # crash the mock. DEAD on comments_index's :index action specifically
      # (verified: CommentsController#index never touches
      # Comment#commentable/#parent — only #destroy's `user.owns?` does) —
      # kept/patched anyway per the discipline (this file is shared across
      # this controller's actions even though only :index is DSE-driven
      # here) and to stay diff-auditable against the Phase A patch note.
      interceptor.declare_target(btpa, :find_target, returns: lambda do |receiver, _args, name|
        nm = receiver.reflection.name
        klass = poly_klass(receiver)
        sql = begin
          table = klass.table_name
          pk = klass.primary_key
          fk_raw = receiver.owner[receiver.reflection.foreign_key]
          %(SELECT "#{table}".* FROM "#{table}" WHERE "#{table}"."#{pk}" = #{ct.render_arg_value(fk_raw)})
        rescue StandardError
          "BelongsToPolymorphicAssociation##{nm} (polymorphic target load)"
        end
        ct.symbolic_instance(klass, "assoc_#{nm}", sql)
      end)
    end

    # =====================================================================
    # 3. Iterable symbolic list — VALUE fix for the `comments_index` wall.
    #
    # `CommentsController#index` ends in
    #     render json: CommentPresenter.as_collection(comments)
    # `comments` is a Relation; `BasePresenter.as_collection` calls
    # `collection.map`, which delegates to `records.map`, and the shared §4
    # target makes `records` a plain SymbolicList ->
    #     NotImplementedError: SymbolicList#each is not supported
    #                          (src/ruby_runtime/list.rb:221)
    #
    # The WRONG fix (tried first, then discarded) is mocking
    # `BasePresenter.as_collection`. It is a legal SQL-free leaf and it does
    # clear the wall, but it mocks the CONSUMER: the app's own `map` stops
    # running and every future branch inside it depends on the mock faithfully
    # re-implementing app code. Fix the VALUE instead.
    #
    # `SymbolicList` is an ordinary Ruby class with a public `#representative`
    # reader, and #first/#last/#[0] ALREADY return that representative. Making
    # #each/#map yield it once is the same Gate-1b "one sampled row" semantics
    # those readers implement — consistency, not new modelling — so the real
    # `as_collection` and the real `CommentPresenter#as_json` both execute.
    #
    # HONEST LIMIT (Gate-1b, DESIGN §5): one representative row is modeled, not
    # N distinct rows, so "two comments that differ" is not explored.
    # =====================================================================
    unless defined?(IterableSymbolicList)
      ::Object.const_set(:IterableSymbolicList, Class.new(SymbolicList) do
        # DO NOT `include Enumerable` HERE.
        #
        # A module included into a SUBCLASS is inserted BEFORE the superclass in
        # the ancestor chain, so `Enumerable#any?` / `#none?` / `#count` /
        # `#first` / `#include?` / `#to_a` would SHADOW `SymbolicList`'s
        # implementations — and SymbolicList's `#any?`/`#none?` are exactly the
        # methods that RECORD the `(len(X) != 0)` path condition
        # (src/ruby_runtime/list.rb:161-177). Enumerable's versions just iterate
        # `each` and return a plain bool, silently dropping the PC on a run that
        # still looks green and error-free. The `notifications_tags` batch
        # measured 8 PCs -> 4 from this alone.
        #
        # Enumerable would also silently re-enable `#include?` and `#to_a`,
        # which SymbolicList raises on BY DESIGN (membership has no sound Z3
        # encoding; contents are out of scope).
        #
        # `#each` and `#map` below are defined explicitly, so nothing needs it.
        # Measured on this batch: 50 PCs with Enumerable, 50 without — comments
        # never reaches `any?` on a relation — but it is removed as a guard.

        def each
          return to_enum(:each) unless block_given?
          yield @representative if @representative && concrete_length != 0
          self
        end

        def map
          return to_enum(:map) unless block_given?
          @representative && concrete_length != 0 ? [yield(@representative)] : []
        end
        alias_method :collect, :map
      end)
    end

    rel      = ActiveRecord::Relation
    null_rel = defined?(ActiveRecord::NullRelation) ? ActiveRecord::NullRelation : nil

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

    rows_mock = lambda do |receiver, args, name|
      # A NullRelation (`Model.none`) is DEFINED to be empty and issues no
      # SQL — there is no query to preserve, so the concrete empty result is
      # a sound over-approximation rather than a hidden query.
      next [] if null_rel && receiver.is_a?(null_rel)

      vn  = "#{name}_rows"
      sql = ct.sql_for(receiver, args)
      rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", sql)
      emit_includes_preloads(ct, receiver, rep) # T1b repair #2 (ported from notifications_index)
      # T1b repair #1 (ported): a has_many :through load's real statement set
      # includes the JOIN-TABLE fetch — emit it as its own noted producer.
      begin
        assoc = receiver.instance_variable_get(:@association)
        refl  = assoc && assoc.reflection
        if refl && refl.respond_to?(:through_reflection) && refl.through_reflection
          tr = refl.through_reflection
          owner = assoc.owner
          oid = owner.respond_to?(:[]) ? owner[:id] : owner.id
          isql = %(SELECT "#{tr.table_name}".* FROM "#{tr.table_name}" WHERE "#{tr.table_name}"."#{tr.foreign_key}" = #{ct.render_arg_value(oid)})
          ConcolicThroughLoadProbe.load_intermediate(isql)
        end
      rescue StandardError
        nil # note-side extra must never crash the mock (M-family rule)
      end
      IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn,
                               note: sql, representative: rep)
    end

    %i[to_a to_ary records].each do |m|
      interceptor.declare_target(rel, m, returns: rows_mock)
    end

    # results3 Phase A Patch 4 (../PHASE_A_PATCH.md): collection-ASSOCIATION
    # reads (`post.comments`, `comment.mentions`, ...) go through
    # `ActiveRecord::Associations::CollectionProxy`, which OVERRIDES
    # `Relation#records` with its OWN `records` (-> `load_target` ->
    # `@association.load_target`, collection_proxy.rb:1003) — a target
    # declared only on `ActiveRecord::Relation` never fires for a bare
    # collection-association load. Applicable here per PHASE_A_PATCH.md's
    # table ("comments_index: yes -- `CommentService#find_for_post` calls
    # `post_service.find!(post_id).comments.for_a_stream` -- `.comments` is a
    # bare `CollectionProxy`; `for_a_stream`'s `including_author.merge(order
    # (...))` chain preserves or downgrades it depending on path -- CONFIRMED
    # empirically both here and in results2's own smoke run: `for_a_stream`
    # resolves to a plain `Relation` on the exercised path, so this addition
    # is INERT-BUT-HARMLESS for the top-level comments list -- the existing
    # Relation-level mock above already covers it). `Comment#mentions` (has_
    # many, the OTHER CollectionProxy on this endpoint's model graph) is
    # likewise dormant: `MentionsContainer#mentioned_people`'s `mentions
    # .includes(...)` branch only fires when `persisted?` is true, and every
    # `symbolic_instance`-built record has `@new_record = true` (always
    # false persisted?) -- see the identity-shim note below. Kept anyway:
    # safe by `defined?`/`respond_to?` guard, per the patch's own "harmless
    # to keep" guidance, and to stay diff-auditable against PHASE_A_PATCH.md.
    if defined?(ActiveRecord::Associations::CollectionProxy)
      cp = ActiveRecord::Associations::CollectionProxy
      %i[to_a to_ary records load_target].each do |m|
        next unless cp.method_defined?(m) || cp.private_method_defined?(m)
        interceptor.declare_target(cp, m, returns: rows_mock)
      end
    end

    # =====================================================================
    # 4. results3 DESCENT: Diaspora::Mentionable.people_from_string runs for
    #    REAL (results2's shared §X6f mock -- return []/Person.none -- and
    #    this file's own former shape-only override are BOTH REMOVED; see
    #    ../concolic_targets.rb's header MOCK LEDGER and X6f comment, and
    #    ../../results2/MOCK_AUDIT.md's `Diaspora::Mentionable.
    #    people_from_string` row).
    #
    #    Real body (lib/diaspora/mentionable.rb:46-49):
    #      identifiers = msg_text.to_s.scan(REGEX).map {|m| m.second.strip }
    #      identifiers.compact.uniq.map {|id| find_or_fetch_person_by_identifier(id) }.compact
    #    -> find_or_fetch_person_by_identifier -> Person.find_or_fetch_by_identifier
    #      (app/models/person.rb:318-328):
    #        person = by_account_identifier(diaspora_id)      # find_by (kept target)
    #        return person if person.present? && person.profile.present?  # find_target (kept target)
    #        DiasporaFederation::Discovery::Discovery.new(diaspora_id).fetch_and_save  # NETWORK I/O
    #        by_account_identifier(diaspora_id)
    #
    #    This IS this endpoint's win-condition query family (task brief:
    #    "the mentions/profiles families are the win condition") -- a REAL
    #    local Person lookup with a genuine $$() bind, reached from a
    #    genuinely symbolic `text` column. Two things are needed that
    #    aren't already covered by the kept design mocks:
    #
    #    (a) TEXT IDENTITY SHIM. `msg_text.to_s.scan(REGEX)` -- `scan` is in
    #        SymbolicString's UNSUPPORTED stub list (src/ruby_runtime/
    #        string.rb, "Search / scan" section) even though `to_s` returns
    #        self (a real String subclass) -- so a bare symbolic `text`
    #        column crashes here. `Comment#mentioned_people` ALWAYS takes
    #        this branch on a `symbolic_instance`-built Comment whose
    #        seeded `_persisted` decision is False (cycle 1, 2026-08-25:
    #        persisted?/new_record? are now a PC-recorded boundary decision
    #        in ./concolic_targets.rb's symbolic_instance — default
    #        persisted, so the DEFAULT path is the real endpoint's
    #        `mentions.includes(person: :profile)` read; DSE flips the seed
    #        to reach this branch, labeled by `_persisted == True` False).
    #        Ported from results3/notifications_index/targets.rb §5g (same
    #        problem, same fix): pin `text` to a CONCRETE Ruby String via a
    #        SEEDED boolean (`_text_has_mention`) so DSE can explore both
    #        "no mention" (empty result, `.scan` finds nothing) and "has
    #        mention" (a real `@{Name; handle}` marker, driving the local
    #        lookup) shapes -- a genuine branch on the SHAPE of a query
    #        result's downstream string content, not a fabricated PC.
    #    (b) NETWORK-I/O WALL. `DiasporaFederation::Discovery::Discovery
    #        #fetch_and_save` -> nil. `find_or_fetch_by_identifier` only
    #        reaches this when the local `find_by(diaspora_handle: ...)`
    #        comes back not-found; by default the finder mock seeds
    #        not_found=false (found), so this is DORMANT unless
    #        prefix-directed DSE flips that PC -- at which point, without
    #        this wall, the real gem body would attempt an actual webfinger
    #        HTTP fetch. Coordinator directive: network I/O must never
    #        fire. The mock's body is a single gem-boundary no-op (no SQL,
    #        no other declared target) -- same classification as the
    #        already-kept `DiasporaFederation::Entity#validate`/
    #        `#normalize_property` leaves in ../concolic_targets.rb, not a
    #        new kind of violation. Ported from
    #        results3/notifications_index/targets.rb §5h.
    # =====================================================================

    # (a) text identity shim, wired as a batch-local wrapper around
    # `ConcolicTargets.symbolic_instance` (same aliasing technique already
    # used below for SuccIntValue -- chains cleanly regardless of order).
    unless ct.respond_to?(:symbolic_instance_without_comments_text_shim)
      class << ConcolicTargets
        alias_method :symbolic_instance_without_comments_text_shim, :symbolic_instance

        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_without_comments_text_shim(klass, base_name, sql)
          return obj unless obj.respond_to?(:concolic_attrs)
          attrs = obj.concolic_attrs
          next_obj = obj
          if attrs.key?("text")
            hm_name = "#{base_name}_text_has_mention"
            has_mention = symbool(hm_name, seed_for(hm_name, false), note: sql)
            attrs["text"] =
              if has_mention == true
                "hello @{Concolic Mention; concolic_mention@example.org} welcome"
              else
                "hello world, a concolic message with no mentions"
              end
          end
          next_obj
        end
      end
    end

    # (b) network-I/O wall.
    if defined?(DiasporaFederation::Discovery::Discovery) &&
       DiasporaFederation::Discovery::Discovery.instance_methods.include?(:fetch_and_save)
      interceptor.declare_target(DiasporaFederation::Discovery::Discovery, :fetch_and_save,
                                 returns: ->(_r, _a, _n) { nil })
    end

    # =====================================================================
    # 5. Successor-capable symbolic int — VALUE fix for the `comments_create`
    #    wall.
    #
    #   app/models/user/social_actions.rb:56  update_or_create_participation!
    #     participation.update!(count: participation.count.next)
    #       -> NotImplementedError: SymbolicInt#next   (src/ruby_runtime/int.rb:63)
    #
    # The enclosing method CANNOT be mocked: its body issues SQL
    # (`participations.find_by(target_id: target)`) and holds the
    # `if participation.present?` branch. Both rules forbid it. But the VALUE
    # can carry #next.
    #
    # `SuccIntValue` mirrors `SymbolicInt#-@`, which already returns a NEW
    # symbolic value named `(- x)` rather than raising: `#next` returns a new
    # SuccIntValue named `(x + 1)`. `(x + 1)` is a valid Z3/Python expression
    # on an Int, so the result stays tracked and stays flippable — this does
    # NOT concretize.
    #
    # WIRING: unlike photos (whose wall was `Calculations#count` on a Relation),
    # here `participation.count` is an INTEGER COLUMN on a symbolic record built
    # by `ConcolicTargets.symbolic_instance`. So the wrapper below re-wraps
    # every integer column reader as a SuccIntValue, reusing the SAME var name,
    # seed and note — identical symbolic identity, one extra method. The shared
    # file itself is untouched; this aliases its singleton method batch-locally
    # (same technique as photos/targets.rb §6a-wiring).
    #
    # Both `obj.<col>` and `obj[:<col>]`/`read_attribute` are updated, because
    # `symbolic_instance` backs them with the one `concolic_attrs` Hash.
    # =====================================================================
    unless defined?(SuccIntValue)
      ::Object.const_set(:SuccIntValue, Class.new(SymbolicInt) do
        def next
          SuccIntValue.new(value + 1,
                           name: (sym_name ? "(#{sym_name} + 1)" : nil),
                           note: note)
        end
        alias_method :succ, :next
      end)
    end

    unless ct.respond_to?(:symbolic_instance_without_succ_ints)
      class << ConcolicTargets
        alias_method :symbolic_instance_without_succ_ints, :symbolic_instance

        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_without_succ_ints(klass, base_name, sql)
          return obj unless obj.respond_to?(:concolic_attrs)

          klass.columns_hash.each do |col, meta|
            next unless %i[integer bigint].include?(meta.type)
            old = obj.concolic_attrs[col]
            next unless old.is_a?(SymbolicInt) && !old.is_a?(SuccIntValue)

            v = SuccIntValue.new(old.value, name: old.sym_name, note: old.note)
            obj.concolic_attrs[col] = v
            obj.define_singleton_method(col) { v }
          end
          obj
        end
      end
    end

    # =====================================================================
    # 6. Asset-path stub — ENVIRONMENT wall, not a symbolic-runtime one.
    #
    # Once §3 lets `CommentPresenter#as_json` run, it reaches
    # `Person#as_api_response(:backbone)` -> `AvatarPresenter`, whose CLASS
    # BODY evaluates `ActionController::Base.helpers.image_path(...)`. The
    # minimal rig has no compiled assets, Sprockets raises WHILE THE CLASS BODY
    # IS STILL EXECUTING, and the class is left half-defined — after which
    # every LATER run in the same process fails differently
    # (`NoMethodError: base_hash`). Order-dependent and misleading.
    #
    # Stubbing a pure display-URL builder makes the rig deterministic. Same fix
    # the `people` and `photos` batches adopted (photos/targets.rb §5).
    # =====================================================================
    begin
      h = ActionController::Base.helpers
      h.define_singleton_method(:image_path)    { |src, *| "/concolic/assets/#{src}" }
      h.define_singleton_method(:path_to_image) { |src, *| "/concolic/assets/#{src}" }
      require "app/presenters/avatar_presenter" if defined?(Rails)
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn "[comments] asset stub: #{e.class}: #{e.message.to_s[0, 60]}"
    end

    # =====================================================================
    # 7. Person.name_from_attrs — SHIM MOCK (cycle 1, 2026-08-25; replaces
    #    the removed X6i Person#name TARGET mock, see ./concolic_targets.rb).
    #
    # Real body (person.rb:254-256): pure string logic —
    #   first_name.blank? && last_name.blank? ? diaspora_handle
    #                                        : "#{first.strip} #{last.strip}".strip
    # It reaches ZERO target functions (mock_manifest.rb's `person-name_from_
    # attrs` probe is exactly this contract) and its output is display data
    # (the presenter's `name` field), never a query argument. The wall it
    # clears is SymbolicString#strip on the symbolic first/last name
    # columns. Person#name itself now runs for REAL, so its `self.profile`
    # read mints the profile-load evidence the mocked version swallowed.
    # Singleton stub on the class (no interceptor wrap, so the return is a
    # plain String — display only).
    # =====================================================================
    if defined?(Person) && Person.respond_to?(:name_from_attrs)
      Person.define_singleton_method(:name_from_attrs) do |_first, _last, _handle|
        "Concolic Person Name"
      end
    end

    warn "[comments] CommentsTargets installed"
  end
end

# =============================================================================
# CommentsVisibleShareableNaming — CALL-SITE-STABLE finder naming for the
# signed-in post lookup (cycle 1, 2026-08-25; same technique as
# CommentsMentionLookupNaming below / posts_show's PostsShowFinderNaming).
#
# THE PROBLEM: `EvilQuery::VisibleShareableById#post!` (lib/evil_query.rb:
# 102-105) is
#     querent_has_visibility.first || querent_is_author.first || public_post.first
# — three semantically different finders on the ONE shared
# `ActiveRecord::FinderMethods.first` counter, so in AUTH runs `first_1`
# meant the share-visibility lookup, `first_2` the author lookup and
# `first_3` the public lookup, while in ANON runs `first_1` is
# PostService#find_public!'s lookup. The batch's assumptions about
# `first_1_not_found` ("raises RecordNotFound -> 404 -> nothing downstream")
# are TRUE for the anon finder and FALSE for the auth chain (a not-found
# share-visibility lookup falls through to the author lookup, and the
# comments query then binds on `first_2_id` instead) — one expr name, two
# meanings, exactly the per-run-ordinal caveat assumptions.py documents.
# FIX: one dedicated declared target per call site (`ci_vis_first`,
# `ci_author_first`, `ci_public_first`, aliased off the shared
# FinderMethods#first with the identical finder_mock returns: lambda — note
# fidelity unchanged), so each is ALWAYS ordinal _1 by construction and the
# anon `first_1` names only the anon finder. The prepend below reproduces
# post!'s body verbatim; only the finder names differ.
# =============================================================================
module CommentsVisibleShareableNaming
  SITES = %w[vis author public].freeze

  def self.install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets
    unless defined?(EvilQuery::VisibleShareableById)
      warn "[comments vis naming] EvilQuery::VisibleShareableById undefined -- NOT installed"
      return
    end
    fm = ActiveRecord::FinderMethods
    SITES.each do |site|
      name = :"ci_#{site}_first"
      fm.send(:alias_method, name, :first) unless fm.method_defined?(name)
      interceptor.declare_target(fm, name, returns: ct.finder_mock(raise_on_missing: false))
    end
    EvilQuery::VisibleShareableById.prepend(PostBangNaming) unless
      EvilQuery::VisibleShareableById < PostBangNaming
    warn "[comments vis naming] CommentsVisibleShareableNaming installed"
  end

  module PostBangNaming
    # byte-faithful to lib/evil_query.rb:102-105 except the finder names
    def post!
      #small optimization - is this optimal order??
      querent_has_visibility.ci_vis_first || querent_is_author.ci_author_first || public_post.ci_public_first
    end
  end
end

# =============================================================================
# CommentsDeviseUserNaming — REAL current_user resolution for the signed-in
# scenario (cycle 1, 2026-08-25; ports notifications_index's AUTH_CHAIN
# real-Devise resolution). D1 (evidence equivalence): the previous auth
# runner OVERRODE `current_user` with a pre-built symbolic user and OVERRODE
# `user.person`, so the two statements the REAL signed-in endpoint issues to
# resolve the session — `SELECT users.* WHERE id = ?` (Devise
# serialize_from_session -> OrmAdapter::ActiveRecord#get) and
# `SELECT people.* WHERE owner_id = ?` (has_one :person) — were SWALLOWED:
# the concrete run issues them, the corpus had no note. (Found by
# mock_note_check on the cycle-1 auth concrete run: two NOTE-MISMATCH reds.)
#
# FIX: the runner resolves current_user through the REAL
# `User.serialize_from_session` (which calls the real `to_adapter.get`), and
# does NOT override `user.person` (the real has_one association fires). Two
# pieces of runner-local plumbing, no app-source edit and no new violation:
#   (a) authenticatable_salt leaf shim — a pure `encrypted_password[0,29]`
#       string slice, no SQL, no other target (same T1 leaf classification
#       as the ../concolic_targets.rb federation leaves; notifications_index
#       validated this exact shim). Without it the salt compare walls on a
#       symbolic encrypted_password column.
#   (b) `devise_user_first` — a CALL-SITE-STABLE alias of FinderMethods#first
#       for the ONE `.first` inside OrmAdapter::ActiveRecord#get, so the
#       Devise users lookup does NOT take the shared `first_1` ordinal (that
#       name is the anon post lookup). get's body is reproduced verbatim
#       except the finder name. The users-lookup outcome is auth PLUMBING,
#       not endpoint logic — its not_found/persisted/text decisions are
#       untracked in coverage_assumptions.py (a session that fails to resolve
#       is not a modeled endpoint state; Devise 404s in the middleware before
#       the action, a path this batch does not target).
# =============================================================================
module CommentsDeviseUserNaming
  def self.install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets
    return unless defined?(User) && defined?(OrmAdapter::ActiveRecord)

    fm = ActiveRecord::FinderMethods
    unless fm.method_defined?(:devise_user_first)
      fm.send(:alias_method, :devise_user_first, :first)
    end
    # Custom returns (NOT finder_mock): mint the users-lookup note but pin the
    # session user resolved + persisted WITHOUT recording a not_found/persisted
    # PC. Devise's middleware guarantees a persisted user reaches the action (a
    # missing/failed session 401s upstream, before the controller) — modeling a
    # nil or unpersisted session user would inject auth-middleware artifacts
    # into the coverage universe that this endpoint's logic never branches on.
    interceptor.declare_target(fm, :devise_user_first, returns: lambda do |receiver, args, name|
      u = ct.symbolic_instance(ct.model_class(receiver), name, ct.sql_for(receiver, args))
      if u.respond_to?(:define_singleton_method)
        u.define_singleton_method(:persisted?)  { true }
        u.define_singleton_method(:new_record?) { false }
      end
      u
    end)

    # (a) salt leaf shim (idempotent)
    unless User.instance_variable_get(:@concolic_salt_shim)
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
      User.instance_variable_set(:@concolic_salt_shim, true)
    end

    # (b) route the ONE .first inside OrmAdapter::ActiveRecord#get to the
    #     dedicated alias — byte-faithful to orm_adapter-0.5.0's #get.
    OrmAdapter::ActiveRecord.prepend(OrmAdapterGetNaming) unless
      OrmAdapter::ActiveRecord < OrmAdapterGetNaming

    warn "[comments devise] CommentsDeviseUserNaming installed"
  end

  module OrmAdapterGetNaming
    def get(id)
      klass.where(klass.primary_key => wrap_key(id)).devise_user_first
    end
  end
end

# =============================================================================
# CommentsMentionLookupNaming — CALL-SITE-STABLE finder naming for the local
# Person lookup inside Diaspora::Mentionable.people_from_string (results3
# completion pass, per coordinator directive). Ported technique from
# results2/posts_show/targets.rb's `PostsShowFinderNaming` (context x attempt
# dedicated `.first` aliases) / results2/conversations_index's single-site
# `convidx_conv_lookup` alias — same root cause, same cure.
#
# THE PROBLEM (see coverage_assumptions.py's prior residual, now removed):
# `CommentPresenter#as_json` (app/presenters/comment_presenter.rb) computes
# `@comment.mentioned_people` in TWO independent places --
#
#   text:             @comment.message.plain_text_for_json   # Comment#message (MentionsContainer)
#                        -> Diaspora::MessageRenderer.new(text, mentioned_people: mentioned_people)
#                        -> calls #mentioned_people INTERNALLY (call site "msg")
#   mentioned_people:  @comment.mentioned_people.as_api_response(:backbone)  # direct call (call site "json")
#
# -- and `MentionsContainer#mentioned_people` (on the seeded UNPERSISTED
# side of the comment rep's `_persisted` decision -- see ./targets.rb's §4
# header; cycle 1 made persisted the default) calls
# `Diaspora::Mentionable.people_from_string(text)`,
# which (lib/diaspora/mentionable.rb:88-90) calls
# `Person.find_or_fetch_by_identifier` (app/models/person.rb:318-328):
#
#   def self.find_or_fetch_by_identifier(diaspora_id)
#     person = by_account_identifier(diaspora_id)                      # ATTEMPT "first"
#     return person if person.present? && person.profile.present?
#     DiasporaFederation::Discovery::Discovery.new(diaspora_id).fetch_and_save  # WALLED
#     by_account_identifier(diaspora_id)                                # ATTEMPT "retry"
#   end
#   def self.by_account_identifier(diaspora_id)
#     find_by(diaspora_handle: diaspora_id.strip.downcase)
#   end
#
# Both call sites (msg, json) reach this SAME `find_by` on the SAME shared
# `ActiveRecord::Core::ClassMethods.find_by` counter (`SYM_RESULT_
# ActiveRecord__Core__ClassMethods_find_by_<idx>`, minted per-run in
# call_interceptor.rb:140) -- and each site can call it up to TWICE (first +
# retry). The counter therefore mixes up to 4 semantically DIFFERENT
# decisions under one moving-target ordinal set (find_by_1..4), whose
# IDENTITY shifts across runs depending on which sites retried -- the exact
# unsound-combination-checking failure mode the main README's "per-run call
# ordinal" caveat documents. Fix: one DEDICATED declared target per (site x
# attempt) combo, so each is ALWAYS "_1" when it fires, by construction (not
# by an argument about execution order).
#
# CALL SITES (tagged via Thread.current[:comments_mention_ctx], default
# "json" when unset -- matches PostsShowFinderNaming's "default when unset"
# convention):
#   msg  -- Comment#message's internal `mentioned_people:` kwarg build
#   json -- CommentPresenter#as_json's own `mentioned_people:` field
#
# ATTEMPTS inside Person.find_or_fetch_by_identifier, in this fixed order:
#   first -- the initial by_account_identifier(diaspora_id) call
#   retry -- the POST-fetch_and_save by_account_identifier(diaspora_id) call
#            (only reached when `first`'s result was not_found OR had no
#            profile -- see the reimplementation below, faithful to the
#            real body's `person.present? && person.profile.present?` guard)
#
# NEITHER CommentPresenter#as_json NOR Person.find_or_fetch_by_identifier's
# BODY changes -- both prepends below are FAITHFUL reimplementations of the
# real, unchanged bodies (same technique as posts_show's `FindPublicRouting`
# reproducing `find_public!` verbatim): the only change is which declared
# target boundary each `find_by` call is recorded under. This is a
# runner-local prepend (Module#prepend from OUR targets.rb), not an edit to
# app/presenters/comment_presenter.rb or app/models/person.rb.
# =============================================================================
module CommentsMentionLookupNaming
  SITES     = %w[msg json].freeze
  ATTEMPTS  = %w[first retry].freeze

  def self.install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    # ../concolic_targets.rb's eager_files list (install!'s GATE1B loop)
    # force-loads "person" (so Person.find_or_fetch_by_identifier is already
    # defined here) but NOT "comment_presenter" -- CommentPresenter is a
    # results3-only naming target, so load it explicitly here, same pattern
    # PostsShowFinderNaming uses for evil_query/like_service.
    unless defined?(CommentPresenter)
      path = File.join(Rails.root, "app/presenters/comment_presenter.rb")
      begin
        require_relative path if File.exist?(path)
      rescue LoadError, StandardError => e
        warn "[comments naming] could not load #{path}: #{e.class} #{e.message[0, 80]}"
      end
    end

    unless defined?(CommentPresenter) && defined?(Person) &&
           Person.respond_to?(:find_or_fetch_by_identifier)
      warn "[comments naming] CommentPresenter/Person.find_or_fetch_by_identifier " \
           "undefined -- naming layer NOT installed"
      return
    end

    core = ActiveRecord::Core::ClassMethods

    # -- 1. Dedicated (site x attempt) targets, aliased off the SAME
    #       Core::ClassMethods#find_by the shared design-#2 mock already
    #       declares (../concolic_targets.rb:456) -- identical returns:
    #       lambda (`finder_mock(raise_on_missing: false)`), so the note
    #       fidelity (Phase A Patch 2's class_finder_sql, honest fallback
    #       included) is unchanged; only the counter identity differs. -----
    SITES.each do |site|
      ATTEMPTS.each do |attempt|
        name = :"mention_lookup_#{site}_#{attempt}"
        core.send(:alias_method, name, :find_by) unless core.method_defined?(name)
        interceptor.declare_target(core, name, returns: ct.finder_mock(raise_on_missing: false))
      end
    end

    # Violation-6 port (2026-08-25, found by statement_note_lint on this
    # batch's first audited corpus: 48 mention_lookup_* events with the
    # "WHERE unavailable" junk note + 24 empty): the aliases receive
    # KEYWORD conditions but sit outside the shared
    # ConcolicKwargsToPositional name list, so the interceptor's param
    # binding drops them. Same cure as the shared module: stash the
    # conditions in the :concolic_finder_conds thread-local at this
    # boundary (values still symbolic); the ported class_finder_sql
    # fallback renders the WHERE into the note.
    kw_fix = Module.new do
      CommentsMentionLookupNaming::SITES.each do |site|
        CommentsMentionLookupNaming::ATTEMPTS.each do |attempt|
          define_method(:"mention_lookup_#{site}_#{attempt}") do |*args, **kwargs, &blk|
            cond = if !kwargs.empty?
                     kwargs
                   elsif args.first.is_a?(Hash) && !args.first.empty?
                     args.first
                   end
            prev = Thread.current[:concolic_finder_conds]
            Thread.current[:concolic_finder_conds] = cond
            begin
              args += [kwargs] unless kwargs.empty?
              super(*args, &blk)
            ensure
              Thread.current[:concolic_finder_conds] = prev
            end
          end
        end
      end
    end
    # NB: prepend to the CALLER'S singleton class, not to the ClassMethods
    # module — on this Ruby (2.6 semantics) module-ancestry changes do not
    # propagate to classes that already included the module.
    Person.singleton_class.prepend(kw_fix)

    # -- 2. Person.find_or_fetch_by_identifier -- context-routed replacement,
    #       faithful to app/models/person.rb:318-328. -----------------------
    Person.singleton_class.prepend(PersonFindOrFetchNaming) unless
      Person.singleton_class < PersonFindOrFetchNaming

    # -- 3. CommentPresenter#as_json -- tags "msg" around the text: field's
    #       Comment#message call (Comment#message internally invokes
    #       #mentioned_people); the mentioned_people: field's OWN call is
    #       left at the default context ("json", set via with_ctx below so
    #       it is explicit rather than relying on the unset-default). Body
    #       is byte-identical to app/presenters/comment_presenter.rb's
    #       current #as_json (verified against the file read for this pass).
    CommentPresenter.prepend(CommentPresenterContextTag) unless
      CommentPresenter < CommentPresenterContextTag

    warn "[comments naming] CommentsMentionLookupNaming installed"
  end

  def self.current_ctx
    Thread.current[:comments_mention_ctx] || "json"
  end

  # Runner calls this so a leaked context from a crashed prior run can never
  # bleed into the next run_one call (defense in depth; with_ctx already
  # restores via ensure on the happy path).
  def self.reset_ctx!
    Thread.current[:comments_mention_ctx] = nil
  end

  def self.with_ctx(tag)
    prev = Thread.current[:comments_mention_ctx]
    Thread.current[:comments_mention_ctx] = tag
    yield
  ensure
    Thread.current[:comments_mention_ctx] = prev
  end

  module PersonFindOrFetchNaming
    def find_or_fetch_by_identifier(diaspora_id)
      site = CommentsMentionLookupNaming.current_ctx
      handle = diaspora_id.strip.downcase

      first_target = :"mention_lookup_#{site}_first"
      person = public_send(first_target, diaspora_handle: handle)
      return person if person.present? && person.profile.present?

      logger.info "webfingering #{diaspora_id}, it is not known or needs updating"
      DiasporaFederation::Discovery::Discovery.new(diaspora_id).fetch_and_save

      retry_target = :"mention_lookup_#{site}_retry"
      public_send(retry_target, diaspora_handle: handle)
    end
  end

  module CommentPresenterContextTag
    def as_json(opts={})
      {
        id:               @comment.id,
        guid:             @comment.guid,
        text:             CommentsMentionLookupNaming.with_ctx("msg") { @comment.message.plain_text_for_json },
        author:           @comment.author.as_api_response(:backbone),
        created_at:       @comment.created_at,
        mentioned_people: CommentsMentionLookupNaming.with_ctx("json") { @comment.mentioned_people.as_api_response(:backbone) }
      }
    end
  end
end
