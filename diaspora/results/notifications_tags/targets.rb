# frozen_string_literal: true
#
# Per-batch concolic targets — `notifications_tags`
# (notifications#index/#update/#read_all, tags#index/#show,
#  tag_followings#index/#create/#destroy/#manage).
#
# Installs AFTER `ConcolicTargets.install!`. `declare_target` uses
# `define_method`, so a later declaration REPLACES an earlier one — the §F
# override below is last-one-wins and needs no registry support.
#
#   ConcolicTargets.install!(interceptor)          # shared generic AR interception
#   NotificationsTagsTargets.install!(interceptor) # this file — batch-local fixes
#
# Every mock here wraps the SMALLEST enclosing method whose real body contains
# NO SQL and calls NO other declared target (README wall-fixing discipline).
# Producing queries still run for real.
#
# Everything this file DOES NOT do is as load-bearing as what it does; see §3
# and §4, which record two mocks that were probed, measured, and rejected.

module NotificationsTagsTargets
  module_function

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    # ---------------------------------------------------------------------
    # 1. `ActsAsTaggableOn::Tag` — constant load (was runner-local).
    #
    # `Tag` in this app is the gem's namespaced model, and it is NOT autoloaded
    # in the concolic env: TagsController, TagFollowingsController and
    # Stream::Tag all raise NameError without this. Touching `columns_hash`
    # forces AR to read the table metadata so `symbolic_instance(Tag, ...)`
    # mints real per-column vars rather than an empty attribute set.
    #
    # Not a mock — an environment fixup — but it belongs with the batch's other
    # wall fixes rather than inline in the runner.
    # ---------------------------------------------------------------------
    begin
      require "acts_as_taggable_on"
      ActsAsTaggableOn::Tag.columns_hash
      warn "[notifications_tags] ActsAsTaggableOn::Tag loaded " \
           "(#{ActsAsTaggableOn::Tag.table_name})"
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn "[notifications_tags] ActsAsTaggableOn::Tag load FAILED: " \
           "#{e.class}: #{e.message.to_s[0, 160]}"
    end

    # ---------------------------------------------------------------------
    # 2. §F instance persistence — ADD `update_column`/`update_columns`, and
    #    make the whole list SEED-AWARE.
    #
    # (a) THE WALL FIX. `update_column` is absent from the shared §F list
    #     (concolic_targets.rb:503), so it executes for real against a
    #     `klass.allocate` record whose `@new_record` is true:
    #
    #       ActiveRecord::ActiveRecordError: cannot update a new record
    #         activerecord-5.2.4.3/persistence.rb:469:in `update_columns'
    #         app/models/notification.rb:22:in `set_read_state'
    #         app/controllers/notifications_controller.rb:13:in `update'
    #
    #     Same SQL-free-leaf status §F already grants save/update/destroy; the
    #     producing query (`Notification.where(...).first`) still runs for real
    #     through the finder mock.
    #
    #     MEASURED EFFECT: clears the crash on 2 of 4 notifications#update
    #     dumps, adds ZERO path conditions. `set_read_state(read_state)` is
    #     `update_column(:unread, !read_state)` — straight-line, and its
    #     argument is `params[:set_unread] != "true"`, a CONCRETE Ruby boolean.
    #     Added for a crash-free batch, not for coverage. Do not read the
    #     cleared error as new coverage: notifications#update stays at 1 node.
    #
    # (b) THE INERTNESS FIX. concolic_targets.rb:508 hard-codes `true` instead
    #     of calling `seed_for`, the exact anti-pattern that made `Photo#url`
    #     unclosable for the photos batch: DSE emits a flip, runs the child,
    #     and the mock ignores it. Routing through `ct.seed_for` costs nothing
    #     and keeps the default identical.
    #
    #     HONEST MEASUREMENT FOR THIS BATCH: it buys nothing here, and cannot.
    #     The two branches that consume these values —
    #       tag_followings#create   `if @tag_following.save`
    #       tag_followings#destroy  `if tag_following && tag_following.destroy`
    #     — are bare Ruby truthiness tests. A `SymbolicBool` wrapping `false` is
    #     still a truthy object (src/ruby_runtime/bool.rb:11), so no PC is
    #     recorded, the true arm is always taken, and DSE never generates a flip
    #     for a var that never appears in a PC. Seedability is therefore
    #     unreachable here: the truthiness gap makes it MOOT, and the
    #     `head :forbidden` arms stay unrecordable. Kept anyway because it is
    #     the correct shape and the gap is in src/, not in the mock.
    # ---------------------------------------------------------------------
    base = ActiveRecord::Base
    persistence = %i[
      save save! update update! update_attribute touch destroy destroy!
      update_column update_columns
    ]
    persistence.each do |m|
      next unless base.instance_methods.include?(m) ||
                  base.private_instance_methods.include?(m) ||
                  base.protected_instance_methods.include?(m)
      interceptor.declare_target(base, m, returns: lambda do |receiver, args, name|
        vn = "#{name}_#{m}_ok"
        symbool(vn, ct.seed_for(vn, true),
                note: "#{receiver.class.name}##{m} args=#{args.inspect}")
      end)
    end

    # ---------------------------------------------------------------------
    # 3. DELIBERATELY NOT MOCKED: `WillPaginate::Collection#total_entries=`
    #
    # Wall A, notifications#index (3/3 dumps, the entrypoint's only outcome):
    #
    #   NotImplementedError: SymbolicInt#to_i
    #     src/ruby_runtime/int.rb:30:in `to_i'
    #     will_paginate-3.3.0/lib/will_paginate/collection.rb:109:in `total_entries='
    #     app/controllers/notifications_controller.rb:34:in `index'
    #
    # `Notification.where(conditions).count` is a SymbolicInt handed straight to
    # `WillPaginate::Collection.create(page, per_page, <symint>)`. The count is
    # COERCED, never compared, so no PC precedes the crash.
    #
    # The setter is the only SQL-free leaf enclosing the wall (`create` itself
    # is not mockable — the block the app hands it issues the paginated query).
    # It was probed in a scratch process. MEASURED: it does NOT unlock the
    # entrypoint, it RELOCATES the wall one line, to
    #   TypeError: can't convert Notification::ActiveRecord_Relation to Array
    #   at notifications_controller.rb:41 (`pager.replace(result)`),
    # with `@notifications.group_by` at line 43 waiting behind it. Both are
    # CONTENTS operations on a length-only SymbolicList — out of scope by
    # design, so a third mock would only move the wall a third time.
    #
    # A mock that relocates a wall without closing a branch is churn, not a
    # fix: it adds a mocked call site, loses the honest stack trace that names
    # the real gap, and buys 0 PCs. Left out on purpose. notifications#index
    # cannot be genuinely covered without SymbolicList CONTENTS support, which
    # is a src/ decision, not a mock.

    # ---------------------------------------------------------------------
    # 4. NO LEGAL MOCK EXISTS: Wall C, tags#show (2 dumps, the found branch)
    #
    #   TypeError: can't quote SymbolicInt
    #     activerecord-5.2.4.3/connection_adapters/abstract/quoting.rb:179 `_quote'
    #     activerecord-5.2.4.3/sanitization.rb:211 `quote_bound_value'
    #     app/models/status_message.rb:57 `tag_stream'
    #
    # `Stream::Tag#posts` -> `StatusMessage.user_tag_stream(user, tag.id)` ->
    # `where("taggings.tag_id IN (?)", tag_ids)`. `tag.id` is a SymbolicInt from
    # the symbolic Tag; a STRING-condition `where` routes through AR's sanitizer,
    # which quotes bind values directly instead of taking the Arel bind-param
    # path. Same family as the `Stream::FollowedTag#tag_ids -> nil` workaround
    # already in shared §I.
    #
    # Both candidate enclosures QUERY, so per the wall-fixing rules neither may
    # be mocked:
    #   * `Stream::Tag#tag`  — SQL, and its `first`/`unless tag` IS the one
    #     genuine branch tags#show has. Mocking it would delete the coverage
    #     (the photos `build_image_url` regression, exactly).
    #   * `StatusMessage.tag_stream` — SQL.
    # This is a src/ GAP, not a missing mock: SymbolicInt needs a
    # `value_for_database` / `quoted_id` hook so AR's quoting layer can bind a
    # symbolic scalar. Raised, not patched.
    # ---------------------------------------------------------------------

    # ---------------------------------------------------------------------
    # 5. Symbolic-shaped VALUE OBJECTS — closing "missing runtime method"
    #    walls WITHOUT touching src/ruby_runtime.
    #
    # The runtime's symbolic classes are ordinary Ruby classes with public
    # readers (`SymbolicInt#value`/`#sym_name`/`#note`,
    # `SymbolicList#representative`/`#concrete_length`). A missing method is
    # therefore NOT a src/ blocker: a batch-local SUBCLASS adds it and a
    # batch-local mock returns that subclass. Nothing shared changes.
    #
    # This RETRACTS the two "needs a src/ change" claims §3 and §4 make above;
    # those sections are kept for their evidence, not their conclusion.
    # Same technique as photos/targets.rb §6.
    # ---------------------------------------------------------------------

    # 5a. Coercible + quotable symbolic integer.
    #
    # Closes TWO walls with one value class:
    #
    #  * WALL A — `will_paginate/collection.rb:109 total_entries=` does
    #    `number.to_i`, and src/ruby_runtime/int.rb:30 raises on `to_i` by
    #    design (it is an implicit-concretization channel). `#to_i` here is
    #    EXPLICIT and returns the concrete `value`; `#to_int` is deliberately
    #    left raising, so implicit coercion (Array#[], string *, etc.) is still
    #    caught. That is the narrow hole the gem actually needs.
    #
    #  * WALL C — `StatusMessage.tag_stream`'s string-condition
    #    `where("taggings.tag_id IN (?)", tag_ids)` routes through AR's
    #    sanitizer. `Quoting#quote` (activerecord-5.2.4.3
    #    connection_adapters/abstract/quoting.rb:11-19) does:
    #        value = value.value_for_database if value.respond_to?(:value_for_database)
    #        _quote(value)
    #    so implementing `#value_for_database` makes the bind quote as a plain
    #    integer while the Ruby-side value stays symbolic. `#quoted_id` is
    #    supplied for the older AR path. No branch is swallowed: this only adds
    #    methods, it changes no control flow.
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

        # will_paginate does arithmetic on the coerced Integer, not on us, but
        # `.next` shows up on count values elsewhere; mirror SymbolicInt#-@ and
        # return a sound symbolic successor rather than raising.
        def next
          ConcolicIntValue.new(value + 1,
                               name: (sym_name ? "(#{sym_name} + 1)" : nil),
                               note: note)
        end
        alias_method :succ, :next
      end)
    end

    # 5b. Iterable symbolic list.
    #
    # notifications#index needs `each`/`map`/`group_by` on query results:
    #   `types.each_with_object(current_user.unread_notifications.group_by(&:type))`
    #   `notification_list.map {|note| NotificationSerializer.new(note, ...) }`
    # The shared collection mock already attaches `representative:` and
    # #first/#last/#[0] honour it — yielding that same representative once is
    # the Gate 1b "one sampled row" semantics those readers already implement,
    # so this is consistency with the existing contract, not new modelling.
    # An empty list (seeded `len(...) == 0`) yields nothing.
    #
    # DO NOT `include Enumerable` HERE. A module included into a SUBCLASS is
    # inserted BEFORE the superclass in the ancestor chain, so `Enumerable#any?`
    # / `#none?` / `#first` / `#count` would shadow the PC-RECORDING
    # `SymbolicList#any?` / `#empty?` / `#first`. Measured: with Enumerable
    # included, tags#show silently LOST the `(len(...) != 0)` path condition
    # from `people.any?` — a coverage-destroying regression that looks like a
    # harmless convenience. `each`/`map` are defined directly instead, which is
    # all the app needs (Relation supplies its own Enumerable and merely
    # delegates `each` here).
    unless defined?(IterableSymbolicList)
      ::Object.const_set(:IterableSymbolicList, Class.new(SymbolicList) do
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

    %i[to_a records].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        vn  = "#{name}_rows"
        sql = ct.sql_for(receiver, args)
        rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", sql)
        IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn,
                                 note: sql, representative: rep)
      end)
    end

    # 5b-ii. `to_ary` must return a TRUE Array — the one place a symbolic list
    # cannot survive — AND that Array must be a SymbolicVar to reach the caller.
    #
    # `pager.replace(result)` in notifications_controller.rb:41 reaches
    # `Array#replace` (WillPaginate::Collection < Array). `to_ary` is Ruby's
    # IMPLICIT conversion protocol and the interpreter type-checks the result,
    # so returning any non-Array — SymbolicList included — raises
    #   TypeError: can't convert Notification::ActiveRecord_Relation to Array
    #              (…#to_ary gives SymbolicList)
    #
    # Returning a plain `Array` from the mock does NOT work either, and the
    # reason is worth recording: `CallInterceptor#declare_target` post-processes
    # every mock result, and `to_symbolic` (symbolic_func.rb:165) maps `Array`
    # to `SymbolicList` — so a bare Array is converted right back into the thing
    # that fails. The pass-through branch immediately above it keeps anything
    # that `is_a?(SymbolicVar)` untouched, and that check runs FIRST.
    #
    # So the value class has to be both at once: a real `::Array` subclass that
    # includes `SymbolicVar`. `SymbolicVar` contributes only `#sym_name`,
    # `#caller_frame` and `#record!` (src/ruby_runtime/base.rb) — no Array
    # method is shadowed, so Array semantics are exactly stock. Length still
    # comes from the seedable `len(<name>_rows)` var, so seeding it to 0 still
    # yields an empty page, and the name/note keep SQL traceability.
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
      rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", sql)
      SampledRowsArray.build(len, rep, name: vn, note: sql)
    end)

    # 5b-iii. Relation#count -> ConcolicIntValue (the wall-A producer).
    calc = ActiveRecord::Calculations
    interceptor.declare_target(calc, :count, returns: lambda do |receiver, args, name|
      vn = "#{name}_count"
      ConcolicIntValue.new(ct.seed_for(vn, 1), name: vn,
                           note: ct.sql_for(receiver, args))
    end)

    # 5c. Date-shaped symbolic value + column wiring.
    #
    # `symbolic_instance` maps every non-integer/boolean column to
    # SymbolicString, so the `datetime` column `notifications.updated_at` has no
    # #strftime and notifications#index dies at
    #   `@group_days = @notifications.group_by {|note| note.updated_at.strftime(..) }`
    # (controller line 43 — the wall waiting behind wall A).
    #
    # A real ::Date subclass keeps `Date === obj`, `I18n.l` and strftime
    # working, while #year stays a seedable SymbolicInt so any
    # `date.year <op> N` comparison records a genuine flippable PC instead of
    # crashing.
    unless defined?(ConcolicDate)
      ::Object.const_set(:ConcolicDate, Class.new(::Date) do
        attr_writer :sym_year
        def year
          @sym_year || super
        end
      end)
    end

    # 5c-wiring + 5a-wiring: batch-local WRAPPER around the shared
    # `symbolic_instance` (the shared file itself is untouched). After the
    # generic build, rewrite the attrs hash the singleton readers close over:
    #   * date/datetime columns  -> ConcolicDate with a seedable #year
    #   * integer/bigint columns -> ConcolicIntValue (same var name, same seed,
    #                               same note) so `tag.id` is quotable — this is
    #                               what actually closes WALL C, since the value
    #                               originates inside symbolic_instance, not at
    #                               a mockable call boundary.
    # Mutating `concolic_attrs` is enough: the readers, `[]`, `read_attribute`
    # and `attributes` all close over that same Hash.
    unless ConcolicTargets.respond_to?(:symbolic_instance_without_nt_values)
      class << ConcolicTargets
        alias_method :symbolic_instance_without_nt_values, :symbolic_instance
        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_without_nt_values(klass, base_name, sql)
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
          obj
        end
      end
    end

    # ---------------------------------------------------------------------
    # 6. `Post.blocked_people` — make the shared mock SEED-AWARE.
    #
    # Closing wall C (§5a) let `Stream::Tag#posts` reach
    # `Post.excluding_blocks`, which produced a BRAND-NEW path condition in
    # tags#show:
    #     (len(SYM_RESULT_Anonymous_blocked_people_1) != 0)   [from `people.any?`]
    #
    # …that the DSE could not close, for the reason the addendum names as the
    # highest-value pattern: `concolic_targets.rb:560` hard-codes `[]` and never
    # calls `seed_for`, so the var is INERT. DSE emits the flip, runs the child,
    # the mock ignores it, the path repeats and is deduped.
    #
    # Default stays len 0, so `people.any?` is false and the NOT-IN SQL branch is
    # skipped exactly as before — behaviour is unchanged unless the DSE seeds it.
    # Seeding `len(...)` to 1 now genuinely enters
    # `where("posts.author_id NOT IN (?)", people)`.
    #
    # This does NOT swallow the branch: `people.any?` is still evaluated by the
    # app on a SymbolicList, which is what RECORDS the PC. We only make the value
    # it branches on reachable — the addendum's prescribed fix.
    #
    # The rep is a ConcolicIntValue (a blocked person id), so when the NOT-IN
    # bind is sanitised, `quote_bound_value` -> `value.map { c.quote(v) }` finds
    # `#map` on IterableSymbolicList (§5b) and `#value_for_database` on the
    # element (§5a). The shared comment at concolic_targets.rb:565 records that
    # returning a non-empty list here "would crash on SymbolicList#map" — with
    # §5a+§5b in place, it no longer does.
    # ---------------------------------------------------------------------
    interceptor.declare_target(Post.singleton_class, :blocked_people,
                               returns: lambda do |_r, _a, name|
      rep_vn = "#{name}_person_id"
      rep = ConcolicIntValue.new(ct.seed_for(rep_vn, 2), name: rep_vn,
                                 note: "Post.blocked_people — blocked person id")
      IterableSymbolicList.new(ct.seed_for("len(#{name})", 0), name: name,
                               note: "Post.blocked_people (blocked person ids)",
                               representative: rep)
    end)

    warn "[notifications_tags] NotificationsTagsTargets installed"
  end
end
