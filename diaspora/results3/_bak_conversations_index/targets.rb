# frozen_string_literal: true
#
# Per-entrypoint concolic targets — results2/conversations_index ONLY.
#
# Ported from ../../results/conversations/targets.rb (ConversationsTargets),
# trimmed to what conversations_index actually exercises, and CHANGED in one
# important way from the source batch: the association shims that used to
# return unscoped `Model.all` now build a real scoped relation off the
# symbolic owner id, so the recorded SQL keeps its WHERE clause with a
# genuine `$$(SYM_...)` bind instead of silently dropping it. See
# `ConvoSymAssociations` below and REPORT.md for the acceptance-test bind
# lines this produces.
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

    # results3 ADDITION: `.last` — needed now that the render family is
    # REMOVED (../concolic_targets.rb header MOCK LEDGER) and the real view
    # layer reaches `Conversation#last_author` (app/models/conversation.rb:53
    # `messages.pluck(:author_id).last`) — pluck's return is a SampledList
    # (targets.rb `install!` #pluck below), `.last` was never previously
    # exercised since `#[]` only handled index 0/-1 and this is a NEW call
    # shape, not indexing. Same one-representative-row semantics as `#[]`'s
    # -1 case.
    def last
      concrete_length.zero? ? nil : @representative
    end
  end

  # ===========================================================================
  # SampledString — same batch-local SymbolicString subclass as the source
  # batch (targets.rb §1c). `contacts_data` -> `Person.name_from_attrs` calls
  # `#strip` on plucked name columns and `ERB::Util.h` calls `#scrub`; both are
  # whitespace/encoding normalisers, identity for the seeds this entrypoint
  # produces. Neither result is ever compared (no branch is swallowed); the
  # `blank?` PCs that precede them are untouched, genuine branches.
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
  # PluckArgs — recover pluck's real column list (targets.rb §1b, unchanged
  # rationale: CallInterceptor's call_args zip is lossy/mislabelled for splat
  # methods; reported as a src/ gap, worked around runner-locally here).
  # ===========================================================================
  module PluckArgs
    def pluck(*column_names)
      prev = Thread.current[:convidx_pluck_cols]
      Thread.current[:convidx_pluck_cols] = column_names.flatten.map(&:to_s)
      super
    ensure
      Thread.current[:convidx_pluck_cols] = prev
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
  # association would build, constructed by hand so the FK reaches the SQL.
  #
  # Only the three readers conversations_index actually exercises are
  # rescoped: `conversation_visibilities` / `messages` (both called from
  # `Conversation#first_unread_message` / `#set_read`, reached via the
  # `params[:conversation_id]` branch) and `conversation` (called from
  # `@visibilities.map(&:conversation)` in the JSON format branch).
  # `participants` is rescoped too for parity (declared on the same models in
  # the source batch) though conversations_index does not reach it.
  # ===========================================================================
  module ConvoSymAssociations
    def conversation_visibilities
      return super unless respond_to?(:concolic_attrs)

      ConversationVisibility.where(conversation_id: id)
    end

    def messages
      return super unless respond_to?(:concolic_attrs)

      Message.where(conversation_id: id)
    end

    # belongs_to :conversation (on ConversationVisibility). Scoped by the
    # receiver's own conversation_id FK. Routed through #convidx_conv_lookup
    # (declared below), NOT the shared FinderMethods#first mock -- see the
    # "per-run ordinal caveat" fix in install! for why: .first's counter is
    # shared by EVERY `.first` call in the process (the action's own
    # conversation lookup, the visibility lookup, ...), so this call's
    # SYM_RESULT name silently collided with theirs depending on which of
    # those had already fired earlier in the SAME run -- a different decision
    # wearing another decision's name. #convidx_conv_lookup is its own
    # declared target with its own dedicated per-run counter (always called
    # >=0 times, <=1 time here), so it gets one stable name in every run.
    def conversation
      return super unless respond_to?(:concolic_attrs)

      Conversation.where(id: conversation_id).convidx_conv_lookup
    end

    def participants
      return super unless respond_to?(:concolic_attrs)

      Person.joins(:conversation_visibilities)
            .where(conversation_visibilities: { conversation_id: id })
    end
  end

  module_function

  def install!(interceptor = CallInterceptor.instance)
    ct  = ConcolicTargets
    calc = ActiveRecord::Calculations
    rel  = ActiveRecord::Relation

    [Conversation, ConversationVisibility, Message].each do |k|
      k.prepend(ConvoSymAssociations) unless k < ConvoSymAssociations
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

    # -------------------------------------------------------------------
    # Calculations#pluck -> length-only SampledList with a representative.
    # Needed by ConversationsController#contacts_data:
    #   current_user.contacts.mutual.joins(person: :profile)
    #     .pluck(*%w(contacts.id profiles.first_name profiles.last_name people.diaspora_handle))
    # Shared file declares pluck UNSUPPORTED (concolic_targets.rb §D) — same
    # rationale as the source batch (targets.rb §2): pluck IS the query
    # boundary, same role as records/to_a, not a new hole in the "contents
    # ops raise" policy.
    # -------------------------------------------------------------------
    rel.prepend(PluckArgs) unless rel < PluckArgs

    interceptor.declare_target(calc, :pluck, returns: lambda do |receiver, args, name|
      note = ct.sql_for(receiver, args)
      vn   = "#{name}_plucked"
      cols = Thread.current[:convidx_pluck_cols] || []
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
    # every observable way except it is iterable and accepts index -1).
    # Needed for:
    #   @visibilities.map(&:conversation)          (index json)
    #   Conversation#first_unread_message           messages.to_a[-unread]
    # -------------------------------------------------------------------
    %i[to_a records].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        vn   = "#{name}_rows"
        note = ct.sql_for(receiver, args)
        rep  = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", note)
        SampledList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: note, representative: rep)
      end)
    end

    # results3 FIX (found live via a crash: "can't convert Person::
    # ActiveRecord_Relation to Array (...#to_ary gives ConversationsIndex
    # Targets::SampledList)"). `to_ary` is Ruby's IMPLICIT conversion
    # protocol and the interpreter/JRuby TYPE-CHECKS the result — a
    # SampledList (a SymbolicList, not a real ::Array) fails that check.
    # CONFIRMED reached: `Conversation#ordered_participants` (conversation.rb
    # :61) does `(messages.map(&:author).reverse + participants).uniq` —
    # `participants` is an unmateralized Relation (`ConvoSymAssociations#
    # participants`), and `Array#+` calls `to_ary` on it. Was previously
    # unreachable: results2 mocked `render` terminal, so this real-view-layer
    # `+` never ran. Same class of bug as results3/notifications_index's
    # `SampledRowsArray` fix (ported here) — `to_ary` must return a TRUE
    # `::Array` subclass, not merely something with a `to_a`/`to_ary` METHOD.
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
      vn   = "#{name}_rows"
      note = ct.sql_for(receiver, args)
      len  = ct.seed_for("len(#{vn})", 1).to_i
      rep  = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", note)
      SampledRowsArray.build(len, rep, name: vn, note: note)
    end)

    # -------------------------------------------------------------------
    # DELIBERATELY NOT MOCKED (same reasoning as source batch §4):
    #  - ConversationsController#contacts_data — its body issues the query
    #    itself (not a SQL-free leaf); §pluck above is what unblocks it.
    #  - Conversation#first_unread_message / #set_read — both branch AND
    #    query; mocking either would swallow the read/unread PC.
    # -------------------------------------------------------------------

    # =====================================================================
    # results3 ADDITIONS — closing walls the render-family REMOVAL in
    # ../concolic_targets.rb now exposes (see that file's header MOCK
    # LEDGER). Ported verbatim from results3/notifications_index/targets.rb
    # §5a/§5c (ConcolicIntValue/ConcolicDate + symbolic_instance column
    # wrapper) and §5i (to_param leaf shim) — that machinery is generic
    # (fixes VALUE SHAPES for date/datetime columns and URL-param
    # formatting, not conversations-specific query coverage).
    # =====================================================================

    # §5a. Coercible + quotable symbolic integer (parity port; not currently
    # known-reached on this endpoint but cheap defensive infrastructure —
    # WillPaginate's `will_paginate(@visibilities, ...)` call in index.haml
    # is the same total_entries=/to_i path notifications_index hit).
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

        # results3 ADDITION (found live, differs from the notifications_index
        # port): will_paginate-3.3.0's `WillPaginate::ActiveRecord#
        # total_entries` (active_record.rb:75) does `result = count; result =
        # result.size if result.respond_to?(:size) and !result.is_a?(Integer)`
        # — `Calculations#count`'s plain SymbolicInt is not an Integer, so
        # `.size` (SymbolicInt's own blanket-unsupported list, int.rb:67) gets
        # called and raises. CONFIRMED reached: index.haml's `will_paginate
        # @visibilities, ...`. `#size` here means "the count value itself",
        # not collection size — returning `value` is the coercible/quotable
        # rationale this class already exists for.
        def size
          value
        end
      end)
    end

    # results3 ADDITION: `Relation#count -> ConcolicIntValue` (batch-local
    # override of the shared design-#5 `Calculations#count` mock, which
    # returns a plain SymbolicInt). Needed for the will_paginate `#size` fix
    # above to actually apply — same pattern as results3/notifications_index
    # §5b-iii ("the WillPaginate producer").
    interceptor.declare_target(calc, :count, returns: lambda do |receiver, args, name|
      vn = "#{name}_count"
      ConcolicIntValue.new(ct.seed_for(vn, 1), name: vn, note: ct.sql_for(receiver, args))
    end)

    # §5c. Date-shaped symbolic value. `symbolic_instance` maps every
    # non-integer/boolean column to SymbolicString, so `conversations.
    # updated_at`/`messages.created_at` (datetime columns) have no #strftime
    # — CONFIRMED reached: `_conversation.haml`'s `timeago(conversation.
    # updated_at)` -> `timeago_tag` needs `#iso8601`/date arithmetic.
    unless defined?(ConcolicDate)
      ::Object.const_set(:ConcolicDate, Class.new(::Date) do
        attr_writer :sym_year
        def year
          @sym_year || super
        end
      end)
    end

    # §5c-wiring + §5a-wiring + results3 TEXT shim: batch-local WRAPPER
    # around the shared `symbolic_instance`. After the generic build,
    # rewrite the attrs hash the singleton readers close over: date/datetime
    # -> ConcolicDate; integer/bigint -> ConcolicIntValue (same var name/
    # seed/note, now quotable); `text` (Message#text, message BODY content,
    # not query-shape-relevant) -> a CONCRETE string identity shim, same
    # rationale as results3/notifications_index §5g: `Message#message` ->
    # `Diaspora::MessageRenderer.new(text).plain_text_without_markdown`
    # (_conversation.haml's `.last_message` block) is real, unmocked string-
    # processing code that needs `.to_s`/regex ops SymbolicString does not
    # support by design (src/TODO.txt "Strict runtime"). Seeded so DSE can
    # additionally explore mention-bearing text.
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

          # results3 TEXT identity shim (see comment above). Mutating
          # attrs["text"] is enough: the generic loop above already defined
          # `col` readers as `{ attrs[col] }` (live hash lookup) for the
          # date/int cases; for text we define the singleton reader
          # ourselves since the generic loop never touches string columns.
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

    # §5i. `to_param` leaf shim (same rationale as results3/notifications_
    # index). `conversation_path(conversation)`/`person_path(person)` (both
    # in _conversation.haml, via `person_link_class`/route helpers) resolve
    # through `ActiveRecord::Integration#to_param` (`id && id.to_s`), and
    # `SymbolicInt#to_s` is unsupported by design. ConcreteSymbolicString-
    # wrapped (../concolic_targets.rb's X6i comment) since the return feeds
    # straight into real URL-interpolation code.
    base = ActiveRecord::Base
    if base.instance_methods.include?(:to_param)
      interceptor.declare_target(base, :to_param, returns: lambda do |receiver, _args, name|
        id = receiver.respond_to?(:id) ? receiver.id : nil
        v = id.respond_to?(:value) ? id.value.to_s : id.to_s
        ConcreteSymbolicString.build(v, name: name, note: "ActiveRecord::Integration#to_param")
      end)
    end

    # Asset-path stub (defensive parity with the source batch §5 — kept in
    # case anything under this action's real code path touches
    # AvatarPresenter/image_path; render is now REAL for this endpoint, see
    # ../concolic_targets.rb header — kept defensively in case a partial
    # touches it).
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
      # BUG FIX (results2 completion pass, 2026-08-18): SampledString.new
      # bypasses src/ruby_runtime/string.rb's `symstr` factory, which is the
      # ONLY thing that calls SymbolicFunc.register_var — so every pluck'd
      # string column (profiles.first_name/last_name, people.diaspora_handle)
      # recorded genuine `blank?` PCs (blank.rb:126, both taken) but never
      # appeared in the dump's `symbolic_vars`, making the expr Z3-unparseable
      # ("name ... is not defined") and excluded from the combination-coverage
      # universe as `unevaluable_exprs`. Fix: register exactly like `symstr`
      # does, then build the SampledString subclass by hand (SampledString.new
      # cannot be swapped for symstr() itself — symstr hardcodes SymbolicString,
      # not the subclass — so we replicate its registration side effect here).
      val = ConcolicTargets.seed_for(var, "sym_#{bare}")
      if defined?(SymbolicFunc) && SymbolicFunc.respond_to?(:register_var)
        SymbolicFunc.register_var(name: var, sort: "String", value: val.to_s, note: note)
      end
      SampledString.new(val, name: var, note: note)
    end
  end
end
