# frozen_string_literal: true
#
# Per-batch concolic targets — `streams` (StreamsController, 8 entrypoints).
#
# WHY THIS FILE EXISTS
# --------------------
# `reports/diaspora/concolic_targets.rb` is shared by all 13 batches, and several
# of the fixes below are only correct HERE:
#
#   * `Post.blocked_people` must be a length-SEEDABLE SymbolicList for streams
#     (every streams entrypoint branches on `people.any?`), while other batches
#     depend on `User#blocks` being a real Relation (photos) or a length-only
#     list (posts).
#   * `Stream::Aspect#aspect_ids` -> nil only makes sense for a batch that
#     actually drives the aspect stream's real `visible_shareables` query.
#
# Installed AFTER `ConcolicTargets.install!`; `declare_target` uses
# `define_method`, so a later declaration replaces an earlier one (last wins):
#
#   ConcolicTargets.install!(interceptor)   # shared generic AR interception
#   StreamsTargets.install!(interceptor)    # this file — batch-local wall fixes
#
# DISCIPLINE NOTES
# ----------------
# * Every mock here wraps a method whose real body contains NO SQL. The queries
#   they feed (`where("posts.author_id NOT IN (?)", people)`,
#   `visible_shareable_sql`, `Person.in_aspects`) still run for real.
# * NONE of them swallows the branch it guards: the `if` for #1 lives in
#   `Post.excluding_blocks` and the `if` for #3 lives in
#   `Post.excluding_hidden_shareables` — both are CALL SITES, not the mocked
#   bodies. Mocking the body would be the photos/`build_image_url` regression.
# * `User#visible_shareables` / `#visible_shareable_ids` are deliberately NOT
#   here: their bodies ARE the SQL. The runner's optional
#   SUBSTITUTE_USER_VISIBLE_QUERIES knob replaces them, and precisely because
#   that replaces real app SQL it stays an explicit non-default scenario in
#   run_dse.rb rather than being promoted into this file.

module StreamsTargets
  module_function

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    # ---------------------------------------------------------------------
    # 0. BATCH-LOCAL SUBCLASSES OF THE RUNTIME'S SYMBOLIC TYPES.
    #
    # The runtime's symbolic classes are ordinary Ruby classes with public
    # readers, so a missing method is fixable HERE — subclass it and have the
    # batch-local mock return the subclass. `src/` stays untouched.
    # (Same pattern as photos/targets.rb §6.)
    #
    # 0a. IterableSymbolicList — adds #each/#map, yielding the representative
    #     once when the list is non-empty.
    #
    #     Clears the ×9 `NotImplementedError: SymbolicList#map` wall: Rails'
    #     `Sanitization#quote_bound_value` (activerecord-5.2.4.3
    #     sanitization.rb:202) sanitises `where("posts.author_id NOT IN (?)",
    #     people)` with `value.map { |v| c.quote(v) }`. The wall fired AFTER
    #     the `people.any?` PC, so the branch was covered — but the request
    #     died there and everything downstream of `excluding_blocks` was
    #     unreachable on the true side.
    #
    #     Yielding the representative once is the same "one sampled row"
    #     semantics SymbolicList#first/#last/#[0] already implement, so this is
    #     consistency with the existing design, not new modelling. The length
    #     stays symbolic and seedable, so the branch is untouched.
    # ---------------------------------------------------------------------
    unless defined?(IterableSymbolicList)
      ::Object.const_set(:IterableSymbolicList, Class.new(SymbolicList) do
        def each
          return to_enum(:each) unless block_given?
          yield @representative if @representative && concrete_length != 0
          self
        end
        # DELIBERATELY NOT `include Enumerable`. Enumerable would sit ABOVE
        # SymbolicList in the ancestor chain and its #any?/#none?/#count/#first
        # would shadow SymbolicList's PC-RECORDING versions — `people.any?` in
        # Post.excluding_blocks would silently iterate instead of recording
        # `(len(...) != 0)`, taking all eight entrypoints from genuine to
        # VACUOUS. Measured: 72 PCs -> 0 PCs. Only #each/#map are added.
        def map
          return to_enum(:map) unless block_given?
          (@representative && concrete_length != 0) ? [yield(@representative)] : []
        end
        alias_method :collect, :map
      end)
    end

    # ---------------------------------------------------------------------
    # 0b. Quotable symbolic scalars — clears `TypeError: can't quote
    #     SymbolicInt` / `SymbolicString`.
    #
    #     `ConnectionAdapters::Quoting#quote` (quoting.rb:11) is:
    #
    #         value = value.value_for_database if value.respond_to?(:value_for_database)
    #         _quote(value)
    #
    #     — a DUCK-TYPED hook, before the class-based `_quote` case/when that
    #     raises "can't quote X". A subclass that answers `value_for_database`
    #     with its concrete value is therefore quotable by both the adapter and
    #     Arel's visitor (`Arel::Visitors::ToSql#quoted -> connection.quote`),
    #     while staying fully symbolic upstream: every comparison operator,
    #     var name, seed and recorded PC is inherited unchanged.
    #
    #     This is the concolic contract exactly — the CONCRETE value goes to
    #     the database, the SYMBOLIC value keeps recording path conditions —
    #     and it is strictly better than substituting the app's SQL away.
    # ---------------------------------------------------------------------
    unless defined?(QuotableSymbolicInt)
      ::Object.const_set(:QuotableSymbolicInt, Class.new(SymbolicInt) do
        def value_for_database
          value
        end
      end)
    end
    unless defined?(QuotableSymbolicString)
      ::Object.const_set(:QuotableSymbolicString, Class.new(SymbolicString) do
        def value_for_database
          value
        end
      end)
    end

    # 0c. Adapter-level unwrap — the SECOND half of the quoting fix, needed
    #     because `value_for_database` on the VALUE is not always consulted.
    #
    #     Rails binds arrive at the adapter by two different routes:
    #
    #     (i)  raw value  — `Sanitization#quote_bound_value` calls
    #          `c.quote(v)` on each element, and `quote` DOES honour the
    #          value's own `value_for_database` (§0b). Fixed by the subclass.
    #
    #     (ii) QueryAttribute — `Shareable::QueryMethods#owned_or_visible_by_user`
    #          builds `predicate_builder.build_bind_attribute(:author_id,
    #          user.person_id)`, and Arel's `visit_Arel_Nodes_BindParam` calls
    #          `quote(THE ATTRIBUTE)`. The attribute answers
    #          `value_for_database` FIRST (`type.serialize(value)`), and
    #          `ActiveModel::Type::Value#serialize` is the identity — so the
    #          still-symbolic value is handed straight to `_quote`, which
    #          raises `TypeError: can't quote ...`. The value's own hook is
    #          never reached. That is the whole streams_multi TypeError (8
    #          dumps), reached via `EvilQuery::MultiStream#mentioned_posts ->
    #          StatusMessage.where_person_is_mentioned(person) ->
    #          owned_or_visible_by_user(person.owner)`, where `person.owner` is
    #          a §W3 symbolic User whose person_id is symbolic.
    #
    #     So unwrap at the adapter's own choke point: `_quote`/`_type_cast` get
    #     the CONCRETE half of the concolic pair. This is the concolic contract
    #     (concrete execution, symbolic tracking), not a query substitution:
    #     the app's SQL is unchanged and still executes. No branch is affected
    #     — `_quote` records nothing; every comparison happened upstream.
    #     Prepended to the live adapter CLASS (not the Quoting module, which is
    #     already included), so it wins over any adapter-specific override.
    unless defined?(StreamsSymbolicQuoting)
      ::Object.const_set(:StreamsSymbolicQuoting, Module.new do
        def self.unwrap(v)
          v.is_a?(SymbolicVar) && v.respond_to?(:value) ? v.value : v
        end
        def _quote(value)
          super(StreamsSymbolicQuoting.unwrap(value))
        end
        def _type_cast(value)
          super(StreamsSymbolicQuoting.unwrap(value))
        end
      end)
    end
    begin
      ActiveRecord::Base.connection.class.prepend(StreamsSymbolicQuoting)
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn "[streams] adapter quoting prepend failed: #{e.class}: #{e.message.to_s[0, 80]}"
    end

    # 0d. …and unwrap one step EARLIER for typed bind attributes.
    #
    #     With §0c alone the multi wall moves rather than closes: for a TYPED
    #     attribute `QueryAttribute#value_for_database` -> `Type::Integer#
    #     serialize` -> `Helpers::Numeric#cast` -> `cast_value` -> `value.to_i`,
    #     and the runtime deliberately raises `SymbolicInt#to_i is not
    #     supported` (int.rb:30) — before the adapter is ever reached.
    #     (Confirmed by measurement: TypeError x8 -> NotImplementedError x8,
    #     same call site.)
    #
    #     Unwrap the concolic pair's concrete half in the BIND attribute, then
    #     let Rails' real type serialization run on it. Deliberately narrower
    #     than teaching symbolic values `#to_i`: this affects query binds only,
    #     so app code that calls `.to_i` on a symbolic value still raises
    #     loudly instead of silently losing tracking.
    unless defined?(StreamsSymbolicBind)
      ::Object.const_set(:StreamsSymbolicBind, Module.new do
        def value_for_database
          raw = value_before_type_cast
          if raw.is_a?(SymbolicVar) && raw.respond_to?(:value)
            type.serialize(raw.value)
          else
            super
          end
        end
      end)
    end
    ActiveRecord::Relation::QueryAttribute.prepend(StreamsSymbolicBind)

    # ---------------------------------------------------------------------
    # 1. Post.blocked_people -> length-SEEDABLE SymbolicList.
    #    THE SINGLE CHANGE THAT TURNED THIS BATCH FROM 8x INCOMPLETE INTO
    #    8x COMPLETE.
    #
    # `Post.excluding_blocks` (post.rb:88) branches on `people.any?`, and that
    # is the ONE branch reached by all eight streams entrypoints (via
    # `Post.for_a_stream -> excluding_hidden_content`).
    #
    # The shared §I mock (concolic_targets.rb:560) returns a hard-coded `[]`,
    # which `call_interceptor.rb:181` (`to_symbolic`) re-wraps into a
    # SymbolicList of length 0 — and THAT wrap never consults `seed_for`. So
    # `len(...)` could not be moved: DSE generated the flip, ran the child, and
    # the mock ignored it. The `people.any? == true` side was structurally
    # unreachable and every entrypoint carried one permanently missing branch.
    # (Exactly the missing-`seed_for` anti-pattern `Photo#url` had.)
    #
    # SQL-free leaf: the real body is `user.blocks.map {|b| b.person_id}`. The
    # `where(... NOT IN (?))` it feeds stays inside `excluding_blocks`.
    # Default seed 0 keeps the shared mock's behaviour byte-for-byte (empty
    # list, same PC, same downstream SQL); only the length becomes seedable —
    # the same shape every other collection mock in §DESIGN-4 already uses.
    # ---------------------------------------------------------------------
    #
    # Returned as an IterableSymbolicList (§0a) whose representative is a
    # QUOTABLE symbolic person_id (§0b): on the `any? == true` side the real
    # `where("posts.author_id NOT IN (?)", people)` now sanitises and renders
    # as `NOT IN (1)` instead of dying in `quote_bound_value`.
    interceptor.declare_target(Post.singleton_class, :blocked_people, returns: lambda do |_r, _a, name|
      pid = "#{name}_person_id"
      IterableSymbolicList.new(
        ct.seed_for("len(#{name})", 0), name: name,
        note: "Post.blocked_people -> user.blocks.map(&:person_id) (seedable length)",
        representative: QuotableSymbolicInt.new(ct.seed_for(pid, 1), name: pid,
                                                note: "blocked person_id (representative row)")
      )
    end)

    # ---------------------------------------------------------------------
    # 2. Stream::Aspect#aspect_ids -> nil (shared §I row 4-5 returns [1]).
    #
    # The shared mock returns a concrete Array, but `to_symbolic` re-wraps ANY
    # Array return into a SymbolicList, and Arel cannot quote one: the value
    # lands as a bind in `Person.in_aspects(opts[:by_members_of])` inside the
    # real `visible_shareables`, raising `TypeError: can't quote SymbolicList`
    # (2 dumps in this batch). This is precisely why the sibling
    # `Stream::FollowedTag#tag_ids` was already changed to `nil` — `nil` is the
    # one value the interceptor passes through UNCHANGED.
    #
    # With nil, `Stream::Aspect#posts` passes `by_members_of: nil`, and
    # `User::Querying#visible_ids_from_sql`'s `opts[:by_members_of] ||=
    # aspect_ids` then falls back to the user's own ids (mock #4 below), so the
    # real query still gets a concrete, quotable id list.
    #
    # Pure transform (`aspects.map(&:id)`), no SQL of its own.
    # ---------------------------------------------------------------------
    if defined?(Stream::Aspect)
      interceptor.declare_target(Stream::Aspect, :aspect_ids, returns: ->(_r, _a, _n) { nil })
    end

    # ---------------------------------------------------------------------
    # 3 + 4. User-level fixes installed by PREPENDING a module, not by
    #        `declare_target`.
    #
    # WHY NOT declare_target: `to_symbolic` (symbolic_func.rb:149) converts a
    # mock's plain return value — `true`/`false` -> SymbolicBool, `Array` ->
    # SymbolicList. Both are wrong for these three methods:
    #   * a SymbolicBool at a BARE `if` call site is always truthy and records
    #     no path condition (the Ruby truthiness gap, src/TODO.txt), so the
    #     false side would become unreachable;
    #   * a SymbolicList reaching Arel is fix #2's bug all over again.
    # Prepending is the only way to return a genuinely concrete value. These
    # three are therefore NOT recorded as symbolic calls in the dumps — stated
    # plainly in REPORT.md rather than hidden.
    #
    # Every override is guarded by `respond_to?(:concolic_attrs)` (the marker
    # `ConcolicTargets.symbolic_instance` puts on the objects it builds), so a
    # real AR User anywhere else in the process keeps its real behaviour.
    # ---------------------------------------------------------------------
    begin
      ActsAsTaggableOn::Tag
    rescue NameError
      require "/home/dev/project/ruby_examples/dse-apps/apps/diaspora/app/models/acts_as_taggable_on-tag.rb"
    end

    unless defined?(StreamsUserOverrides)
      Object.const_set(:StreamsUserOverrides, Module.new do
        # 3. `if user.has_hidden_shareables_of_type?` (post.rb:111) is a BARE
        #    `if`, so the value must be a concrete Ruby bool. Real body is
        #    `self.hidden_shareables[t.base_class.to_s].present?` — a pure Hash
        #    read, no SQL, and NOT the branch itself (the `if` is at the call
        #    site in `Post.excluding_hidden_shareables`). Default false ==
        #    today's behaviour; seeding it true is what finally lets the true
        #    side of `excluding_hidden_shareables` execute, which it never did
        #    (symbolic_instance pins `hidden_shareables` to a plain `{}`, so
        #    the real predicate can only ever be false).
        #
        #    Caveat, reported honestly: the guarded `where('posts.id NOT IN
        #    (?)', user.hidden_shareables["Post"])` then binds nil -> NULL,
        #    because `hidden_shareables` is a singleton method installed by
        #    symbolic_instance and cannot be overridden from a prepended
        #    module. The true side EXECUTES; its bind value is degenerate.
        def has_hidden_shareables_of_type?(t = Post)
          return super unless respond_to?(:concolic_attrs)
          ConcolicTargets.seed_for("USER_HAS_HIDDEN_SHAREABLES", false) ? true : false
        end

        # 4. `user.aspect_ids` / `user.followed_tag_ids` are AR association
        #    ids_readers (`CollectionAssociation#ids_reader -> Calculations#
        #    pluck`), and `pluck` is deliberately unsupported by the runtime
        #    ("contents out of scope", concolic_targets.rb §DESIGN-5). They are
        #    hit by `User::Querying#visible_ids_from_sql`
        #    (`opts[:by_members_of] ||= aspect_ids`) and by
        #    `EvilQuery::MultiStream#followed_tags_posts!`, and crashed
        #    streams#multi before its first branch. A concrete [1] mirrors what
        #    the shared targets already do for the same shape and keeps the
        #    enclosing REAL SQL intact.
        def aspect_ids
          respond_to?(:concolic_attrs) ? [1] : super
        end

        def followed_tag_ids
          respond_to?(:concolic_attrs) ? [1] : super
        end

        # Association substitution for the symbolic user only: the real
        # `followed_tags` association cannot be loaded off an allocate-d
        # instance. Used by Stream::FollowedTag / Stream::Multi.
        def followed_tags
          respond_to?(:concolic_attrs) ? ActsAsTaggableOn::Tag.all : super
        end
      end)
    end
    User.prepend(StreamsUserOverrides)

    warn "[streams] StreamsTargets installed"
  end
end
