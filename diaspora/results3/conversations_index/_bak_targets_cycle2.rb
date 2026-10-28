# frozen_string_literal: true
#
# Per-entrypoint concolic targets — results3/conversations_index ONLY.
#
# Ported from ../../results/conversations/targets.rb (ConversationsTargets),
# trimmed to what conversations_index actually exercises, and CHANGED in one
# important way from the source batch: the association shims that used to
# return unscoped `Model.all` now build a real scoped relation off the
# symbolic owner id, so the recorded SQL keeps its WHERE clause with a
# genuine `$$(SYM_...)` bind instead of silently dropping it. See
# `ConvoSymAssociations` below.
#
# 2026-08-26 (results3 completion drive, AGENT_RUN.md): ported the portable
# repair toolkit from results3/comments_index + notifications_index:
#   - `emit_includes_preloads` + ConcolicThroughLoadProbe (violation 3 / T1b):
#     every materialize mock AND every finder with `includes_values` emits one
#     note per real Preloader step (skipped when the relation eager-loads —
#     real AR then JOINs instead, and sql_for's to_sql already renders the
#     join). Reached here by `Person.includes(:profile).find_by(id:)`
#     (Conversation#last_author).
#   - pluck projection rewrite (violation 4): the pluck note projects EXACTLY
#     the requested columns (+ order columns), not the relation's `*`.
#   - a COUNT(*) projection for the `Calculations#count` note (real count
#     statements project COUNT, never the row columns).
#   - LOADED-RELATION READS (`ConvLoadedRelation`): the old batch's "THIRD
#     FINDING" — `conversation.messages` was rebuilt as a FRESH relation on
#     every call, so `.map`/`.size`/`.pluck`/`.present?`/`.last` were FIVE
#     independently seeded mocks over ONE real association (real AR loads the
#     CollectionProxy once and answers every later read from memory) — 120
#     crashed runs where `present?` said non-empty and `.last` said nil, plus
#     four over-emitted statements per row (D1). Fix: ConvoSymAssociations
#     memoizes the relation per owner (as the real association cache does) and
#     the materialize mock stashes its rows on the relation; a Relation
#     prepend then answers size/last/pluck/blank?/records/to_a from those rows
#     exactly as Rails' own `loaded?` branches do. Zero seeds added; one
#     statement per association load, as real execution issues.
#   - Person#name TARGET mock removed (its real body reads `self.profile`, a
#     declared association target — D1); the SymbolicString#strip wall it
#     cleared is closed at the SQL-free leaf `Person.name_from_attrs` (shim).
#   - DiasporaFederation discovery network wall (dormant here; parity).
#   - ConvDeviseUserNaming: REAL Devise `serialize_from_session` resolution
#     of current_user with a call-site-stable finder alias + salt leaf shim
#     (D1: the users lookup and the has_one :person read are minted as
#     evidence, exactly as the concrete signed-in run issues them).
#
# Installs AFTER `ConcolicTargets.install!`. Nothing here edits src/, the
# shared concolic_targets.rb, or the app source. This file is a PRIVATE copy
# for this entrypoint directory only (results2/README.md layout).

module ConversationsIndexTargets
  # ===========================================================================
  # SampledList — same batch-local SymbolicList subclass as the source batch
  # (results/conversations/targets.rb §1/§1a), unchanged rationale:
  #  - index -1 is honoured (== #last, already modeled by src/list.rb) because
  #    `Conversation#first_unread_message` does `messages.to_a[-visibility.unread]`
  #    and DSE's flip of `((- unread) == 0)` produces unread=1 => index -1.
  #  - each/map/to_a iterate the ONE representative row, exactly
  #    `concrete_length.zero? ? 0 : 1` times (sampled-content approximation;
  #    src/ leaves collection iteration unimplemented by design).
  # ===========================================================================
  class SampledList < SymbolicList
    def [](*args)
      return super unless @representative && args.length == 1

      idx = args[0]
      return @representative if idx == 0 # unchanged src/ semantics: records ((- VAR) == 0)

      raw = idx.respond_to?(:value) ? idx.value : idx
      return @representative if raw == -1 # == #last, already modeled

      raise NotImplementedError,
            "SampledList#[] supports index 0 and -1 (one representative row); " \
            "got #{raw.inspect} — distinct-row access is out of scope."
    end

    def sampled_rows
      concrete_length.zero? ? [] : [@representative]
    end

    def each(&block)
      return sampled_rows.each unless block

      sampled_rows.each(&block)
      self
    end

    def map(&block)
      return sampled_rows.map unless block

      sampled_rows.map(&block)
    end

    def to_a
      sampled_rows
    end
    alias to_ary to_a

    # CARDINALITY LINK (2026-08-26): a relation whose `.count` the app has
    # already evaluated (`@visibilities.count > 0`, `participants.count > 1`)
    # is later materialized from the SAME relation object; real AR's rows
    # are non-empty iff that count is > 0 (page 1 — params[:page] is nil on
    # every variant, pin ledger in AGENT_RUN.md). Two independent seeds for
    # ONE cardinality let DSE reach `count > 0` with an EMPTY row list — a
    # state no database produces, whose only effect was to shift every later
    # shared-counter ordinal (records_1 became the right column's participant
    # loop) and to fake a "sidebar rendered nothing" path. The list's length
    # decisions are therefore recorded on the COUNT's own variable: no
    # `len(...)` var is minted for a count-linked list.
    def self.linked_to_count(count_var, name:, note:, representative:)
      list = new(count_var.value > 0 ? 1 : 0, name: nil, note: note, representative: representative)
      list.instance_variable_set(:@sym_name, name)
      list.instance_variable_set(:@symbolic_len, count_var)
      list
    end

    # `.last` — `Conversation#last_author` (`messages.pluck(:author_id).last`)
    # and `_conversation.haml`'s `messages.last`. Same one-representative-row
    # semantics as `#[]`'s -1 case. `nil` on the empty side, so the app's own
    # nil-handling (`.try`, `present?`) runs for real.
    def last
      concrete_length.zero? ? nil : @representative
    end
  end

  # ===========================================================================
  # SampledString — same batch-local SymbolicString subclass as the source
  # batch (targets.rb §1c). `ERB::Util.h` calls `#scrub` on plucked columns;
  # whitespace/encoding normalisers, identity for the seeds this entrypoint
  # produces. Neither result is ever compared (no branch is swallowed).
  # ===========================================================================
  class SampledString < SymbolicString
    PLAIN = ::String.instance_method(:to_s)

    def self.identity_op(*names)
      names.each do |m|
        native = ::String.instance_method(m)
        define_method(m) do |*args|
          out = PLAIN.bind(native.bind(self).call(*args)).call
          out == value ? self : self.class.new(out, name: sym_name, note: note)
        end
      end
    end

    identity_op :strip, :lstrip, :rstrip, :scrub
  end

  # ===========================================================================
  # ConvLoadedRelation — pluck-column capture (targets.rb §1b, unchanged
  # rationale: CallInterceptor's call_args zip is lossy/mislabelled for splat
  # methods; reported as a src/ gap, worked around runner-locally here) PLUS
  # the loaded-relation reads (file header). Every method below delegates to
  # `super` unless THIS relation object has already been materialized by the
  # rows mock (`@convidx_rows` set) — in which case it answers from the rows
  # exactly as ActiveRecord::Relation's own `loaded?` branches do:
  #   size    -> records.length           (relation.rb `size`)
  #   last    -> records.last             (finder_methods.rb `find_last`)
  #   pluck   -> records.pluck(*cols)     (calculations.rb `pluck`, loaded?)
  #   blank?  -> records.blank?           (relation.rb `blank?`)
  #   records/to_a/to_ary -> the cached rows (relation.rb `load` memo)
  # ===========================================================================
  module ConvLoadedRelation
    def pluck(*column_names)
      rows = instance_variable_get(:@convidx_rows)
      if rows
        cols = column_names.flatten.map(&:to_s)
        return rows.sampled_rows.map { |r|
          vals = cols.map { |c| r.public_send(c.split(".").last) }
          cols.size == 1 ? vals.first : vals
        }
      end
      prev = Thread.current[:convidx_pluck_cols]
      Thread.current[:convidx_pluck_cols] = column_names.flatten.map(&:to_s)
      super
    ensure
      Thread.current[:convidx_pluck_cols] = prev
    end

    def size
      rows = instance_variable_get(:@convidx_rows)
      rows ? rows.length : super
    end

    def last(*args)
      rows = instance_variable_get(:@convidx_rows)
      rows && args.empty? ? rows.last : super
    end

    def blank?
      rows = instance_variable_get(:@convidx_rows)
      rows ? rows.blank? : super
    end

    def records
      instance_variable_get(:@convidx_rows) || super
    end

    def to_a
      instance_variable_get(:@convidx_rows) || super
    end

    def to_ary
      rows = instance_variable_get(:@convidx_rows)
      rows ? rows.to_ary : super
    end
  end

  # ===========================================================================
  # ConvoSymAssociations — REWORKED from the source batch.
  #
  # THE POINT OF THIS FILE (results2 rerun): the source batch's version
  # returned UNSCOPED relations (`ConversationVisibility.all`, `Message.all`,
  # `Person.all`) whenever the receiver was a symbolic instance (klass.allocate
  # has no @association_cache/backing row, so the REAL has_many/belongs_to
  # readers crash trying to build a scope off a symbolic foreign key). That
  # dropped the owner scoping entirely — recorded SQL lost its `conversation_id`/
  # `person_id` WHERE clause.
  #
  # Fix: build the scoped relation MANUALLY off the symbolic receiver's own
  # attribute (still a SymbolicInt/SymbolicString — `self.id` / `self.conversation_id`
  # are the receiver's own column readers from `symbolic_instance`), so the
  # `.where(...)` clause carries a genuine `$$(SYM_...)` bind when the query
  # eventually renders (via `ct.sql_for` inside the finder/collection mocks).
  # This is NOT the real has_many/belongs_to machinery (that still can't run
  # against an allocated instance) — it is the SAME relation the real
  # association would build (scope included: `messages` carries the
  # association's `order("created_at ASC")`), constructed by hand so the FK
  # reaches the SQL. MEMOIZED per owner (2026-08-26, file header) exactly as
  # the real association cache is — one load per association, later reads
  # from memory.
  # ===========================================================================
  module ConvoSymAssociations
    def conversation_visibilities
      return super unless respond_to?(:concolic_attrs)

      @convidx_conversation_visibilities ||= ConversationVisibility.where(conversation_id: id)
    end

    def messages
      return super unless respond_to?(:concolic_attrs)

      @convidx_messages ||= Message.where(conversation_id: id).order("created_at ASC")
    end

    # belongs_to :conversation (on ConversationVisibility).
    #
    # LOADED-ASSOCIATION CASE (2026-08-26; the old batch's "No route matches
    # ... id=>nil" crash family, 1062 run errors in the first FIFO round):
    # `@visibilities` is `ConversationVisibility.includes(:conversation)`, so
    # on every visibility row real AR serves `visibility.conversation` from
    # the association it ALREADY loaded (the LEFT OUTER JOIN / preload) — no
    # statement, and no nil: `conversation_visibilities.conversation_id` is
    # NOT NULL with a foreign key to conversations (schema.rb:626), so the
    # joined row always carries the conversation. A finder mock here minted
    # a statement real execution never issues (D1) and a `not_found` decision
    # real execution never takes — whose nil side crashed the partial at
    # `conversation_path(conversation)`. Now: a rep whose `id` IS the owner's
    # `conversation_id` var (the join condition), no decision, no note; the
    # rows mock tags reps it built from an includes/eager-load relation.
    #
    # UNLOADED CASE (a visibility rep not built through includes): the
    # scoped lookup, routed through #convidx_conv_lookup (declared below),
    # NOT the shared FinderMethods#first mock -- .first's counter is shared
    # by EVERY `.first` call in the process, so this call's SYM_RESULT name
    # would collide with the action's own lookup depending on ordering.
    # #convidx_conv_lookup has its own dedicated per-run counter.
    # Memoized like the real belongs_to reader.
    def conversation
      return super unless respond_to?(:concolic_attrs)

      return @convidx_conversation if defined?(@convidx_conversation)

      loaded = instance_variable_get(:@convidx_loaded_assocs) || []
      if loaded.include?(:conversation)
        cid = concolic_attrs["conversation_id"]
        base = ConcolicTargets.assoc_base_name(self, :conversation)
        conv = ConcolicTargets.symbolic_instance(Conversation, base, concolic_note.to_s)
        conv.concolic_attrs["id"] = cid
        conv.define_singleton_method(:id) { cid }
        return @convidx_conversation = conv
      end

      @convidx_conversation = Conversation.where(id: conversation_id).convidx_conv_lookup
    end

    def participants
      return super unless respond_to?(:concolic_attrs)

      @convidx_participants ||= Person.joins(:conversation_visibilities)
                                      .where(conversation_visibilities: { conversation_id: id })
    end
  end

  module_function

  # T1b repair #2 (ported from results3/comments_index, 2026-08-21 origin):
  # `.includes(...)` — the real Preloader issues one SELECT per preload step,
  # which a single-note mock return swallows entirely. Walk includes_values
  # via reflections and emit each step through ConcolicThroughLoadProbe.
  # SKIPPED when the relation eager-loads (`references`/`eager_load`): real
  # AR then issues ONE joined statement, which sql_for's `to_sql` already
  # renders with the join (conversations_controller.rb:8-11's
  # `includes(:conversation).order("conversations.updated_at DESC")` — the
  # table-qualified order string makes Rails 5.2 `references(:conversations)`,
  # so @visibilities is a LEFT OUTER JOIN, not a preload).
  def emit_includes_preloads(ct, receiver, rep)
    iv = receiver.respond_to?(:includes_values) ? Array(receiver.includes_values) : []
    return if iv.empty?
    return if receiver.respond_to?(:eager_loading?) && receiver.eager_loading?
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
          child_bind = lambda { |col| col == "id" ? bindv : nil }
        else
          bindv = bind_of.call("id")
          next if bindv.nil?
          thr = (r2.respond_to?(:through_reflection) && r2.through_reflection) || nil
          if thr
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

  # EAGER-LOAD RENDERING (2026-08-26, found by mock_note_check on the first
  # concrete run: NOTE-MISMATCH on `@visibilities`' real statement). When a
  # relation `eager_loading?` (conversations_controller.rb:8-11's
  # `includes(:conversation).order("conversations.updated_at DESC")` — the
  # table-qualified order string makes Rails 5.2 `references(:conversations)`),
  # real AR issues ONE LEFT OUTER JOIN statement projecting every column of
  # both tables (`t0_r0 ...` aliases, JoinDependency#apply_column_aliases) —
  # not the relation's own arel, which is what render_relation_sql walks.
  # Rebuild exactly what Relation#exec_queries builds (apply_join_dependency +
  # apply_column_aliases) and render THAT, symbolic binds intact.
  def eager_relation(receiver, aliases: true)
    return receiver unless receiver.respond_to?(:eager_loading?) && receiver.eager_loading?
    jd = receiver.send(:construct_join_dependency)
    r2 = receiver.except(:includes, :eager_load, :preload).joins!(jd)
    r2 = jd.apply_column_aliases(r2) if aliases && jd.respond_to?(:apply_column_aliases)
    r2
  rescue StandardError
    receiver
  end

  # CARDINALITY LINK (see SampledList.linked_to_count): the count and the
  # rows of the SAME query must agree. "Same query" is keyed on the query's
  # FROM/JOIN/WHERE text (symbolic binds included) — will_paginate's `count`
  # and `render collection:` reach the Calculations/Relation targets through
  # DIFFERENT relation objects (`except(:order, :limit, :offset)` copies), so
  # object identity is not the key; the real database keys on the query.
  # Per-run map, reset by run_dse.rb's run_one.
  def counts
    Thread.current[:convidx_counts] ||= {}
  end

  def reset_counts!
    Thread.current[:convidx_counts] = {}
  end

  def cardinality_key(ct, receiver)
    sql = ct.sql_for(ConversationsIndexTargets.eager_relation(receiver, aliases: false), {})
    key = sql.sub(/\ASELECT\s.*?\sFROM\s/m, "FROM ")
    key = key.sub(/\s+ORDER BY\s.*\z/m, "").sub(/\s+LIMIT\s.*\z/m, "").sub(/\s+OFFSET\s.*\z/m, "")
    key.strip
  rescue StandardError
    nil
  end

  # Reps built from a relation carrying `includes_values` have those
  # associations LOADED in real AR (preload or eager-load join) — the
  # association readers must answer from the loaded target, not query
  # (see ConvoSymAssociations#conversation).
  def tag_loaded_assocs(receiver, rep)
    iv = receiver.respond_to?(:includes_values) ? Array(receiver.includes_values) : []
    return if iv.empty? || !rep.respond_to?(:instance_variable_set)
    names = iv.flat_map { |spec| spec.is_a?(Hash) ? spec.keys : [spec] }.map(&:to_sym)
    rep.instance_variable_set(:@convidx_loaded_assocs, names)
  rescue StandardError
    nil
  end

  # Real `count` statements project COUNT(...) — never the row columns that
  # sql_for's default `SELECT "t".*` rendering shows. Rewrite the projection
  # (tables/joins/predicates untouched; will_paginate strips LIMIT/OFFSET from
  # its count, and the note check ignores them anyway). An eager-loading
  # relation counts over its LEFT OUTER JOIN (`COUNT(*) FROM (SELECT DISTINCT
  # id ... LEFT OUTER JOIN ...)` — same tables/predicates as the join form).
  def count_sql_for(ct, receiver, args)
    sql = ct.sql_for(ConversationsIndexTargets.eager_relation(receiver, aliases: false), args)
    sql.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT COUNT(*) FROM ")
  rescue StandardError
    sql
  end

  # Finder mock that ALSO emits the preload steps of a finder carrying
  # `includes_values` (Conversation#last_author's
  # `Person.includes(:profile).find_by(id: ...)`: the real path issues the
  # people lookup THEN `SELECT profiles.* WHERE person_id IN (?)`). Wraps the
  # shared finder_mock — note fidelity and the not_found decision unchanged.
  def finder_mock_with_preloads(ct, raise_on_missing:)
    inner = ct.finder_mock(raise_on_missing: raise_on_missing)
    lambda do |receiver, args, name|
      rep = inner.call(receiver, args, name)
      ConversationsIndexTargets.emit_includes_preloads(ct, receiver, rep) if rep
      rep
    end
  end

  def install!(interceptor = CallInterceptor.instance)
    ct  = ConcolicTargets
    calc = ActiveRecord::Calculations
    rel  = ActiveRecord::Relation
    fm   = ActiveRecord::FinderMethods
    null_rel = defined?(ActiveRecord::NullRelation) ? ActiveRecord::NullRelation : nil

    [Conversation, ConversationVisibility, Message].each do |k|
      k.prepend(ConvoSymAssociations) unless k < ConvoSymAssociations
    end

    # T1b helper: a declared no-op target whose sole purpose is generating
    # a symbolic_call EVENT carrying the preload-step SQL as its note.
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

    # -------------------------------------------------------------------
    # #convidx_conv_lookup -- dedicated target for ConvoSymAssociations
    # #conversation's `.first`-equivalent (see its comment above). Alias the
    # real behaviour onto a NEW method name first (declare_target needs
    # `klass.instance_method(method)` to exist; body-skip mode never runs it),
    # then declare it as its own target reusing the shared finder_mock logic
    # -- same not_found/found semantics as every other single-record finder,
    # just counted separately so its SYM_RESULT ordinal never collides with
    # ActiveRecord::FinderMethods#first's.
    # -------------------------------------------------------------------
    rel.send(:alias_method, :convidx_conv_lookup, :first) unless rel.method_defined?(:convidx_conv_lookup)
    interceptor.declare_target(rel, :convidx_conv_lookup, returns: ct.finder_mock(raise_on_missing: false))

    # Finders that may carry includes_values -> preload-emitting finder mock
    # (same returns as the shared design-#2 declarations otherwise).
    %i[find_by first last take].each do |m|
      interceptor.declare_target(fm, m, returns: finder_mock_with_preloads(ct, raise_on_missing: false))
    end
    interceptor.declare_target(fm, :find, returns: finder_mock_with_preloads(ct, raise_on_missing: true))

    # -------------------------------------------------------------------
    # Calculations#pluck -> length-only SampledList with a representative.
    # Needed by ConversationsController#contacts_data:
    #   current_user.contacts.mutual.joins(person: :profile)
    #     .pluck(*%w(contacts.id profiles.first_name profiles.last_name people.diaspora_handle))
    # Shared file declares pluck UNSUPPORTED (concolic_targets.rb §D) — same
    # rationale as the source batch (targets.rb §2): pluck IS the query
    # boundary, same role as records/to_a. The note projects EXACTLY the
    # requested columns (+ order columns), as the real pluck statement does
    # (violation 4; ported from results3/notifications_index).
    # -------------------------------------------------------------------
    rel.prepend(ConvLoadedRelation) unless rel < ConvLoadedRelation

    interceptor.declare_target(calc, :pluck, returns: lambda do |receiver, args, name|
      note = ct.sql_for(receiver, args)
      vn   = "#{name}_plucked"
      cols = Thread.current[:convidx_pluck_cols] || []
      unless cols.empty?
        own_table = begin
          ct.model_class(receiver).table_name
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
              c = "#{own_table}.#{c}" if !c.include?(".") && own_table
              qualified << c unless qualified.include?(c)
            end
          end
        rescue StandardError
          nil
        end
        proj = qualified.map { |c|
          t, col = c.split(".", 2)
          col ? %("#{t}"."#{col}") : %("#{t}")
        }.join(", ")
        note = note.sub(/\ASELECT .*? FROM /m, "SELECT #{proj} FROM ")
      end
      cols = ["value"] if cols.empty?
      vals = cols.each_with_index.map do |c, i|
        var = cols.size == 1 ? "#{name}_pluck_#{c.split('.').last}" : "#{name}_pluck#{i}_#{c.split('.').last}"
        ConversationsIndexTargets.sym_for_column(receiver, c, var, note)
      end
      rep = cols.size == 1 ? vals.first : vals
      SampledList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: note, representative: rep)
    end)

    # -------------------------------------------------------------------
    # Collection materialization -> SampledList (identical to shared §C in
    # every observable way except it is iterable and accepts index -1), with
    # the preload-step emission and the loaded-rows stash (file header).
    # Needed for:
    #   @visibilities.map(&:conversation)          (index json)
    #   render partial: ..., collection: @visibilities  (index html)
    #   Conversation#first_unread_message           messages.to_a[-unread]
    #   Conversation#ordered_participants           messages.map(&:author)
    # -------------------------------------------------------------------
    rows_mock = lambda do |receiver, args, name|
      # A NullRelation (`Model.none`) is DEFINED to be empty and issues no
      # SQL — there is no query to preserve, so the concrete empty result is
      # a sound over-approximation rather than a hidden query.
      next [] if null_rel && receiver.is_a?(null_rel)

      vn   = "#{name}_rows"
      note = ct.sql_for(ConversationsIndexTargets.eager_relation(receiver), args)
      rep  = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", note)
      ConversationsIndexTargets.emit_includes_preloads(ct, receiver, rep)
      ConversationsIndexTargets.tag_loaded_assocs(receiver, rep)
      ck  = receiver.is_a?(rel) ? ConversationsIndexTargets.cardinality_key(ct, receiver) : nil
      cnt = ck && ConversationsIndexTargets.counts[ck]
      list = if cnt.is_a?(SymbolicInt)
               SampledList.linked_to_count(cnt, name: vn, note: note, representative: rep)
             else
               SampledList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: note, representative: rep)
             end
      receiver.instance_variable_set(:@convidx_rows, list) if receiver.is_a?(rel)
      list
    end

    %i[to_a records].each do |m|
      interceptor.declare_target(rel, m, returns: rows_mock)
    end

    # `to_ary` is Ruby's IMPLICIT conversion protocol and the interpreter
    # TYPE-CHECKS the result — a SampledList (not a real ::Array) fails that
    # check. CONFIRMED reached: `Conversation#ordered_participants`
    # (conversation.rb:61) does `(messages.map(&:author).reverse +
    # participants).uniq` — `participants` is an unmaterialized Relation and
    # `Array#+` calls `to_ary` on it. `to_ary` must return a TRUE `::Array`
    # subclass (results3/notifications_index's `SampledRowsArray` fix).
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
      next [] if null_rel && receiver.is_a?(null_rel)

      vn   = "#{name}_rows"
      note = ct.sql_for(ConversationsIndexTargets.eager_relation(receiver), args)
      rep  = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", note)
      ConversationsIndexTargets.emit_includes_preloads(ct, receiver, rep)
      ConversationsIndexTargets.tag_loaded_assocs(receiver, rep)
      ck  = receiver.is_a?(rel) ? ConversationsIndexTargets.cardinality_key(ct, receiver) : nil
      cnt = ck && ConversationsIndexTargets.counts[ck]
      list = if cnt.is_a?(SymbolicInt)
               SampledList.linked_to_count(cnt, name: vn, note: note, representative: rep)
             else
               SampledList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: note, representative: rep)
             end
      receiver.instance_variable_set(:@convidx_rows, list) if receiver.is_a?(rel)
      SampledRowsArray.build(list.concrete_length, rep, name: vn, note: note)
    end)

    # results3 Phase A Patch 4 (../PHASE_A_PATCH.md): collection-ASSOCIATION
    # reads go through `CollectionProxy`, which OVERRIDES `Relation#records`
    # with its OWN (-> load_target). Reached here now that current_user is
    # the REAL Devise-resolved user: `current_user.contacts` (has_many) is a
    # bare CollectionProxy before `.mutual` scopes it.
    if defined?(ActiveRecord::Associations::CollectionProxy)
      cp = ActiveRecord::Associations::CollectionProxy
      %i[to_a to_ary records load_target].each do |m|
        next unless cp.method_defined?(m) || cp.private_method_defined?(m)
        interceptor.declare_target(cp, m, returns: rows_mock)
      end
    end

    # -------------------------------------------------------------------
    # DELIBERATELY NOT MOCKED (same reasoning as source batch §4):
    #  - ConversationsController#contacts_data — its body issues the query
    #    itself (not a SQL-free leaf); §pluck above is what unblocks it.
    #  - Conversation#first_unread_message / #set_read / #last_author /
    #    #ordered_participants — all branch AND query; mocking any would
    #    swallow a PC or a statement.
    # -------------------------------------------------------------------

    # =====================================================================
    # results3 ADDITIONS — closing walls the render-family REMOVAL in
    # ./concolic_targets.rb exposes. Ported verbatim from
    # results3/notifications_index/targets.rb §5a/§5c (ConcolicIntValue/
    # ConcolicDate + symbolic_instance column wrapper) and §5i (to_param
    # leaf shim).
    # =====================================================================

    # §5a. Coercible + quotable symbolic integer.
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

        def next
          ConcolicIntValue.new(value + 1,
                               name: (sym_name ? "(#{sym_name} + 1)" : nil),
                               note: note)
        end
        alias_method :succ, :next

        # will_paginate-3.3.0's `WillPaginate::ActiveRecord#total_entries`
        # (active_record.rb:75) does `result = count; result = result.size if
        # result.respond_to?(:size) and !result.is_a?(Integer)` —
        # `Calculations#count`'s plain SymbolicInt is not an Integer, so
        # `.size` gets called. CONFIRMED reached: index.haml's `will_paginate
        # @visibilities, ...`. `#size` here means "the count value itself".
        def size
          value
        end

        # TAUTOLOGY SUPPRESSION (2026-08-26): the class-constant `hash` above
        # routes Ruby's identity set ops (Array#uniq, Array#-) through AR's
        # `==`, which compares `id == id`. When a rep is compared to itself
        # (the SAME symbolic id var on both sides), that is `(VAR == VAR)` — a
        # constant-true tautology, not a data-dependent branch (parse_pc drops
        # it by design; recording it is noise the skipped_pcs audit flags).
        # Suppress the PC for the self-var case only; a genuine cross-rep
        # compare (different var names) still records on both sides.
        def ==(other)
          if other.is_a?(SymbolicInt) && other.sym_name && other.sym_name == sym_name
            return @value == (other.respond_to?(:value) ? other.value : other)
          end
          super
        end
        def !=(other)
          if other.is_a?(SymbolicInt) && other.sym_name && other.sym_name == sym_name
            return @value != (other.respond_to?(:value) ? other.value : other)
          end
          super
        end
      end)
    end

    # `Relation#count -> ConcolicIntValue` (batch-local override of the shared
    # design-#5 `Calculations#count` mock). Note projects COUNT(*) as the
    # real statement does (file header).
    interceptor.declare_target(calc, :count, returns: lambda do |receiver, args, name|
      vn = "#{name}_count"
      v = ConcolicIntValue.new(ct.seed_for(vn, 1), name: vn,
                               note: ConversationsIndexTargets.count_sql_for(ct, receiver, args))
      # cardinality link (SampledList.linked_to_count): the FIRST count of a
      # query is the cardinality its later materialization obeys
      if receiver.is_a?(rel)
        ck = ConversationsIndexTargets.cardinality_key(ct, receiver)
        ConversationsIndexTargets.counts[ck] ||= v if ck
      end
      v
    end)

    # §5c. Date-shaped symbolic value (`timeago(conversation.updated_at)`).
    unless defined?(ConcolicDate)
      ::Object.const_set(:ConcolicDate, Class.new(::Date) do
        attr_writer :sym_year
        def year
          @sym_year || super
        end
      end)
    end

    # §5c-wiring + §5a-wiring + TEXT shim: batch-local WRAPPER around the
    # shared `symbolic_instance`. After the generic build, rewrite the attrs
    # hash the singleton readers close over: date/datetime -> ConcolicDate;
    # integer/bigint -> ConcolicIntValue (same var name/seed/note, now
    # quotable); `text` (Message#text, message BODY content) -> a CONCRETE
    # string identity shim (results3/notifications_index §5g rationale):
    # `Message#message` -> `Diaspora::MessageRenderer.new(text)
    # .plain_text_without_markdown` is real, unmocked string-processing code
    # that needs `.to_s`/regex ops SymbolicString does not support by design.
    # Seeded so DSE can additionally explore mention-bearing text.
    unless ConcolicTargets.respond_to?(:symbolic_instance_without_ni_values)
      class << ConcolicTargets
        alias_method :symbolic_instance_without_ni_values, :symbolic_instance
        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_without_ni_values(klass, base_name, sql)
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

          # HASH-BASED SET OPS RECORD THEIR COMPARE (2026-08-26, D2): Ruby's
          # Array#- / #uniq (conversation.rb:61 `(... + participants).uniq`,
          # _conversation.haml:11 `- [current_user.person]`) look elements
          # up by `hash` and call `eql?` (AR: `other.id == id`) ONLY on a hash
          # hit. AR::Core#hash is `id.hash`, so two reps with DIFFERENT
          # seeded ids never reached `==` — the "not the same person"
          # side of that decision was a blind, concrete hash miss (only the
          # equal side ever recorded a PC). A class-constant hash makes every
          # candidate pair go through `eql?`/`==`, whose ConcolicIntValue
          # compare records the PC on BOTH sides. Semantics preserved:
          # equality is still decided by `==`.
          obj.define_singleton_method(:hash) { klass.hash }

          if attrs.key?("text")
            hm_name = "#{base_name}_text_has_mention"
            has_mention = symbool(hm_name, seed_for(hm_name, false), note: sql)
            txt =
              if has_mention == true
                "hello @{Concolic Mention; concolic_mention@example.org} welcome"
              else
                "hello world, a concolic message with no mentions"
              end
            attrs["text"] = txt
            obj.define_singleton_method(:text) { txt }
          end

          obj
        end
      end
    end

    # §5i. `to_param` leaf shim. `conversation_path(conversation)`/
    # `person_path(person)` resolve through `ActiveRecord::Integration#to_param`
    # (`id && id.to_s`), and `SymbolicInt#to_s` renders the var name, which
    # the journey formatter then escapes. ConcreteSymbolicString-wrapped
    # since the return feeds straight into real URL-interpolation code.
    base = ActiveRecord::Base
    if base.instance_methods.include?(:to_param)
      interceptor.declare_target(base, :to_param, returns: lambda do |receiver, _args, name|
        id = receiver.respond_to?(:id) ? receiver.id : nil
        v = id.respond_to?(:value) ? id.value.to_s : id.to_s
        ConcreteSymbolicString.build(v, name: name, note: "ActiveRecord::Integration#to_param")
      end)
    end

    # =====================================================================
    # §7. Person.name_from_attrs — SHIM MOCK (ported from results3/
    # comments_index cycle 1; replaces the removed Person#name TARGET mock,
    # see ./concolic_targets.rb X6i). Real body (person.rb:254-256) is pure
    # string logic reaching ZERO target functions; its output is display
    # data (`conversation.last_author.name`, `person_image_tag`'s alt/title,
    # contacts_data's gon name), never a query argument. The wall it clears
    # is SymbolicString#strip on the symbolic first/last name columns.
    # Person#name itself now runs for REAL, so its `self.profile` read mints
    # the profile-load evidence the mocked version swallowed.
    # =====================================================================
    if defined?(Person) && Person.respond_to?(:name_from_attrs)
      Person.define_singleton_method(:name_from_attrs) do |_first, _last, _handle|
        "Concolic Person Name"
      end
    end

    # §8. Network-I/O wall (parity with comments_index §4b; dormant on this
    # endpoint — MessageRenderer#plain_text_without_markdown formats mentions
    # with an EMPTY mentioned_people list and never resolves people). The
    # mock's body is a single gem-boundary no-op.
    if defined?(DiasporaFederation::Discovery::Discovery) &&
       DiasporaFederation::Discovery::Discovery.instance_methods.include?(:fetch_and_save)
      interceptor.declare_target(DiasporaFederation::Discovery::Discovery, :fetch_and_save,
                                 returns: ->(_r, _a, _n) { nil })
    end

    # Asset-path stub (ENVIRONMENT wall: AvatarPresenter's CLASS BODY
    # evaluates `image_path`, sprockets raises mid-class-body in this rig).
    begin
      h = ActionController::Base.helpers
      h.define_singleton_method(:image_path)    { |src, *| "/concolic/assets/#{src}" }
      h.define_singleton_method(:path_to_image) { |src, *| "/concolic/assets/#{src}" }
      require "app/presenters/avatar_presenter" if defined?(Rails)
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn "[conversations_index] asset stub: #{e.class}: #{e.message.to_s[0, 80]}"
    end

    warn "[conversations_index] ConversationsIndexTargets installed"
  end

  # Column -> symbolic scalar of the right sort, seeded through seed_for so
  # DSE can actually flip it.
  def sym_for_column(receiver, col, var, note)
    bare = col.to_s.split(".").last.to_s
    type =
      begin
        ConcolicTargets.model_class(receiver).columns_hash[bare]&.type
      rescue StandardError
        nil
      end
    type ||= (bare == "id" || bare.end_with?("_id")) ? :integer : :string

    case type
    when :integer, :bigint, :float, :decimal
      symint(var, ConcolicTargets.seed_for(var, 1), note: note)
    when :boolean
      symbool(var, ConcolicTargets.seed_for(var, false), note: note)
    else
      # SampledString.new bypasses src/ruby_runtime/string.rb's `symstr`
      # factory, which is the ONLY thing that calls SymbolicFunc.register_var
      # — register exactly like `symstr` does, then build the subclass.
      val = ConcolicTargets.seed_for(var, "sym_#{bare}")
      if defined?(SymbolicFunc) && SymbolicFunc.respond_to?(:register_var)
        SymbolicFunc.register_var(name: var, sort: "String", value: val.to_s, note: note)
      end
      SampledString.new(val, name: var, note: note)
    end
  end
end

# =============================================================================
# ConvDeviseUserNaming — REAL current_user resolution (ported from results3/
# comments_index's CommentsDeviseUserNaming, cycle 1). D1 (evidence
# equivalence): a runner that OVERRIDES `current_user` with a pre-built
# symbolic user and OVERRIDES `user.person` SWALLOWS the two statements the
# REAL signed-in endpoint issues to resolve the session — `SELECT users.*
# WHERE id = ?` (Devise serialize_from_session -> OrmAdapter::ActiveRecord#get)
# and `SELECT people.* WHERE owner_id = ?` (has_one :person).
#
# FIX: the runner resolves current_user through the REAL
# `User.serialize_from_session` with a SYMBOLIC session key (the principal
# must be symbolic — identity_symbolicity audit), and does NOT override
# `user.person` (the real has_one association fires). Two pieces of
# runner-local plumbing:
#   (a) authenticatable_salt leaf shim — a pure `encrypted_password[0,29]`
#       string slice, no SQL, no other target.
#   (b) `devise_user_first` — a CALL-SITE-STABLE alias of FinderMethods#first
#       for the ONE `.first` inside OrmAdapter::ActiveRecord#get, so the
#       Devise users lookup does NOT take the shared `first_1` ordinal (that
#       name is the action's own @conversation lookup). get's body is
#       reproduced verbatim except the finder name. The users-lookup outcome
#       is auth PLUMBING, not endpoint logic — pinned resolved + persisted
#       with NO PC (Devise's middleware guarantees a persisted user reaches
#       the action; a failed session 401s upstream).
# =============================================================================
module ConvDeviseUserNaming
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

    warn "[conversations devise] ConvDeviseUserNaming installed"
  end

  module OrmAdapterGetNaming
    def get(id)
      klass.where(klass.primary_key => wrap_key(id)).devise_user_first
    end
  end
end
