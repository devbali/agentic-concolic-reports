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
      return super unless args.length == 1
      # B-5 (2026-08-28): an empty relation has no row at ANY index. Before
      # this, `messages.to_a[-visibility.unread]` handed back the
      # representative even when `len(...) == 0`, i.e. a message the query did
      # not return. `empty?` records the length decision, so the nil is a
      # LABELLED outcome (D2), never a silent one.
      return nil if empty?
      return super unless @representative

      idx = args[0]
      return @representative if idx == 0 # unchanged src/ semantics: records ((- VAR) == 0)

      # cycle 4 (adversary round 2, NM-1): `messages.to_a[-visibility.unread]`
      # (conversation.rb:34) with unread >= 2 selects an INTERIOR message. In
      # the sampled model every row is the representative, so "which row" is
      # not the decision — WHETHER the index falls inside the list is:
      #   idx == -1            -> the last row (recorded: ((- unread) == -1))
      #   |idx| <= list length -> an interior/first row (rep)
      #   |idx| >  list length -> nil (Array#[] beyond the start)
      # The in-range side is a seeded, PC-recorded decision on this list
      # (`<list>_index_in_range`), never a crash and never a pin.
      return @representative if idx == -1 # SymbolicInt#== records the PC

      raw = idx.respond_to?(:value) ? idx.value : idx
      if raw.is_a?(Integer) && raw < -1
        ir_name = "#{@sym_name}_index_in_range"
        in_range = symbool(ir_name, ConcolicTargets.seed_for(ir_name, true), note: @note)
        return in_range == true ? @representative : nil
      end

      raise NotImplementedError,
            "SampledList#[] got #{raw.inspect} — positive distinct-row access is out of scope."
    end

    # B-7 (coordinator propagation matrix, 2026-08-28) — CARDINALITY IS
    # 0 / 1 / MANY, never {0, 1}. Row CONTENT stays one representative (the
    # sampled-content model); what the cardinality decides is (i) the
    # STATEMENT SHAPE of any preload over this list — `= ?` for one owner row,
    # `IN (…)` for many — and (ii) the app's own multi-row branches, which on
    # this endpoint were BLIND: `_conversation.haml:13`'s
    # `other_participants.count > 1` (the `.participants` block and the
    # `drop(1).take(15)` image loop) and its `count - 1` badge run only when
    # the list holds MORE THAN ONE row, and `(len(...) > 1)` occurred in 0 of
    # 1 500 sampled dumps before this. `#many?` records that decision on the
    # length var exactly as `#empty?` records `(len(X) != 0)`;
    # coverage_report.apply_len_bounds widens the declared domain to
    # low = 0, high = 2 (2 = "many"), and run_dse's flip_seed turns
    # `(len(X) > 1)` into the seed 2 by its generic integer rule.
    def many?
      length > 1
    end

    # cycle 4: iteration over a sampled list RECORDS the length decision
    # (`empty?` -> `(len(X) != 0)`): how many times a collection render /
    # `each` / `map` runs is a data-dependent branch. Found on the paginated
    # visibilities list once its length became its own variable again — the
    # collection render's `to_a` returned a plain Array and no PC named the
    # empty page (Class B).
    def sampled_rows
      empty? ? [] : [@representative]
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

    # CARDINALITY LINK (2026-08-26; NARROWED 2026-08-27, adversary round 2
    # NM-2/NM-4): when the app has already COUNTed a query and later
    # materializes the SAME query with NO LIMIT/OFFSET (the mobile
    # `messages.size` then `messages.pluck(:author_id)`; `participants.count`
    # then `participants.each`), the rows are the very set the count counted
    # — one fact, one variable; the list's length decisions are recorded on
    # the count's variable and no `len(...)` var is minted (NM-4: an
    # independent pluck length produced `find_by … id = nil`, a statement the
    # app never issues). A LIMITED/OFFSET relation (`@visibilities.paginate`)
    # is NOT linked: will_paginate's count strips LIMIT/OFFSET, so "count > 0
    # with zero rows" is the real beyond-the-last-page state (NM-2) — that
    # page is a recorded decision (run_dse.rb SYM_PARAM_page_beyond) and the
    # page-1 rows keep their own length variable.
    def self.linked_to_count(count_var, name:, note:, representative:)
      list = new(count_var.value > 0 ? 1 : 0, name: nil, note: note, representative: representative)
      list.instance_variable_set(:@sym_name, name)
      list.instance_variable_set(:@symbolic_len, count_var)
      list
    end

    # BEYOND-THE-LAST-PAGE LIST (2026-08-28, engine assumption gate + coverage):
    # this list is EMPTY BY CONSTRUCTION — its emptiness is a CONSEQUENCE of the
    # `SYM_PARAM_page_beyond` decision, not a decision of its own. Recording a
    # second PC for it created a phantom dimension: nothing seeds it, so no flip
    # probe can move it (the gate reported "a flip probe produced no dump"), and
    # once it was excluded from the assumption tiers the checker demanded 231
    # combinations over it. One fact, one decision: this subclass answers the
    # emptiness predicates CONCRETELY and records nothing.
    class BeyondPageList < SampledList
      def empty?
        true
      end

      def any?
        false
      end

      def none?
        true
      end

      def !
        true
      end

      def sampled_rows
        []
      end
    end

    # `.last` — `Conversation#last_author` (`messages.pluck(:author_id).last`)
    # and `_conversation.haml`'s `messages.last`. Same one-representative-row
    # semantics as `#[]`'s -1 case. `nil` on the empty side, so the app's own
    # nil-handling (`.try`, `present?`) runs for real.
    def last
      empty? ? nil : @representative
    end

    # B-5 (2026-08-28): `first` on an EMPTY relation is nil, not a raise —
    # `SymbolicList#first` raises without a representative, and after B-5 an
    # empty list has none. Same shape as `#last` and `#[]`: the emptiness is a
    # recorded decision, the nil is a labelled outcome.
    def first(*args)
      return super unless args.empty?

      empty? ? nil : @representative
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

    identity_op :strip, :lstrip, :rstrip, :scrub, :downcase
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

    # relation.rb `size`: `loaded? ? records.length : count(:all)` — an
    # UNLOADED `messages.size` (the mobile partials, conversation.rb:55 on
    # the mobile path) is a COUNT statement, not a row read (adversary W2).
    def size
      rows = instance_variable_get(:@convidx_rows)
      rows ? rows.length : count(:all)
    end

    # relation.rb `empty?`: `return records.empty? if loaded?; !exists?`
    def empty?
      rows = instance_variable_get(:@convidx_rows)
      rows ? rows.empty? : super
    end

    def any?(&blk)
      rows = instance_variable_get(:@convidx_rows)
      rows && !blk ? rows.any? : super
    end

    def last(*args)
      rows = instance_variable_get(:@convidx_rows)
      rows && args.empty? ? rows.last : super
    end

    def blank?
      rows = instance_variable_get(:@convidx_rows)
      rows ? rows.blank? : super
    end

    # relation.rb:511 `inspect`: `subject = loaded? ? records : self;
    # subject.take([limit_value, 11].compact.min)`. A relation this rig has
    # materialised IS loaded — without saying so, `inspect` took the UNLOADED
    # branch and issued a REAL `take` (a second visibilities read with a phantom
    # `take_N_not_found` decision, explored in both polarities). Reached only on
    # the `.js` path (C-8): `NameError#message` inspects its receiver, the view
    # context, whose ivars include `@visibilities`. The real request issues no
    # such read (adversary round 3, `.js` = 16 statements, none a re-read),
    # because by then the relation is loaded. `loaded?` is the fact the siblings
    # above already assume; stating it closes every `loaded?`-branching reader
    # at once (Rule P), not just `inspect`.
    def loaded?
      instance_variable_get(:@convidx_rows) ? true : super
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

  # will_paginate attaches `RelationMethods` with `rel.extending(...)`
  # (active_record.rb:170) — on the relation's SINGLETON, which sits ABOVE a
  # class-level prepend in the MRO. So this override must be prepended into
  # will_paginate's own module to be reached at all (a first attempt inside
  # ConvLoadedRelation was never dispatched: 794 NotImplementedErrors in the
  # very next run said so).
  module ConvPaginatedTotal
    # will_paginate-3.3.0 active_record.rb:68-78 `total_entries`:
    #   if loaded? and size < limit_value and (current_page == 1 or size > 0)
    #     offset_value + size            # <- NO statement
    #   else count                       # <- the COUNT statement
    # Saying `loaded?` (above) made the real shortcut reachable, and its
    # `Integer + SymbolicInt` hit SymbolicInt#coerce -> NotImplementedError
    # (2,591 js runs). Mirror the rule exactly: the partial-page compare stays
    # SYMBOLIC (it records `(len(rows) < 15)`, the fact that decides whether a
    # COUNT is issued); the total is DERIVED from the loaded length as a named
    # ConcolicIntValue (a rendering-only number for the pager, no statement),
    # and a full page falls through to `super` — the real COUNT.
    def total_entries
      rows = instance_variable_get(:@convidx_rows)
      return super unless rows && limit_value
      len = rows.length
      partial = ((len < limit_value) == true)
      first_or_nonempty = (current_page.to_i == 1) || ((len > 0) == true)
      if partial && first_or_nonempty
        @total_entries ||= ConcolicIntValue.new(offset_value.to_i + rows.concrete_length.to_i,
                                                name: (len.respond_to?(:sym_name) && len.sym_name ? "(#{offset_value.to_i} + #{len.sym_name})" : nil),
                                                note: (rows.respond_to?(:note) ? rows.note : nil))
      else
        super
      end
    end

  end

  # C-13 / T-z (adversary round 4): a `has_many` PROXY read twice in one request
  # loads ONCE — `user_presenter.rb:24-30` reads `user.services` twice and the
  # real CollectionProxy answers the second from its loaded target. The proxy
  # rows_mock re-materialised on every call (services SELECT emitted TWICE in
  # 13,137 of 13,160 html/mobile dumps; the app issues it once). CollectionProxy
  # OVERRIDES Relation#records, so the ConvLoadedRelation prepend on Relation is
  # bypassed for proxies; this is its exact sibling, prepended on the proxy class.
  # `association.reader` memoises ONE proxy per owner+association, so the memo on
  # the proxy object is the loaded target (relation.rb load / association loaded!).
  module ConvLoadedProxy
    def loaded?
      instance_variable_get(:@convidx_rows) ? true : super
    end

    def records
      instance_variable_get(:@convidx_rows) || super
    end

    def load_target
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

      @convidx_conversation_visibilities ||= begin
        r = ConversationVisibility.where(conversation_id: id)
        r.instance_variable_set(:@convidx_inverse_loaded, [:conversation]) # inverse_of (see tag_loaded_assocs)
        r
      end
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

      # cycle 6 (note_fidelity PRED-OP-DIFF, 2 real statements): the REAL
      # `Conversation#participants` is `has_many through: :conversation_visibilities,
      # source: :person`, whose join renders
      #   INNER JOIN "conversation_visibilities" ON "people"."id" = "conversation_visibilities"."person_id"
      # while `Person.joins(:conversation_visibilities)` (the belongs_to side of
      # the same edge) renders the operands the other way round. Same edge, but
      # the note is supposed to be the statement REAL execution issues, so give
      # the join verbatim; the `where` hash still renders
      # `"conversation_visibilities"."conversation_id" = $$(...)`.
      @convidx_participants ||=
        Person.joins(%(INNER JOIN "conversation_visibilities" ON "people"."id" = "conversation_visibilities"."person_id"))
              .where(conversation_visibilities: { conversation_id: id })
    end
  end

  module_function

  # B-4 (coordinator harvest, 2026-08-28) — ONE LOAD, ONE PREDICATE.
  # The rule that decides whether a singular association load carries a
  # not-found DECISION or is PINNED found. It lives here, in ONE place, and is
  # used by BOTH `SingularAssociation#find_target` (§8) and the preload attach
  # below — comments_index's M-3 regression happened because the preload-attach
  # repair and find_target each had their OWN copy of this rule, so the
  # decision went dead while the corpus kept emitting a read the real run does
  # not issue.
  #
  #  * belongs_to on this endpoint is PINNED found: every belongs_to FK column
  #    on this path is NOT NULL with an ON DELETE CASCADE foreign key
  #    (db/schema.rb: conversation_visibilities.conversation_id/person_id
  #    141-142 + FKs 626-627; messages.conversation_id/author_id 212-213 +
  #    FKs 632-633; conversations.author_id 154 + FK 628) — unlike
  #    comments_index's `mentions.person_id`, no dangling row is possible;
  #  * `User has_one :person` is pinned found (pin ledger);
  #  * a rep that went through `reload` after federation discovery has its
  #    profile pinned found (pin ledger);
  #  * every other has_one (profiles.person_id) is a DECISION.
  def assoc_decided?(owner, refl)
    !refl.belongs_to? &&
      !(owner.is_a?(User) && refl.name == :person) &&
      !(owner.respond_to?(:instance_variable_get) && owner.instance_variable_get(:@convidx_reloaded))
  rescue StandardError
    false
  end

  # B-4: attach the preloaded row to the owner exactly as
  # `Preloader::Association#associate_records_to_owner` does — the association
  # becomes LOADED, so the later reader is answered from memory and no SECOND
  # statement is minted for the same read. Before this, 20 870 of 38 588 dumps
  # carried BOTH the preload note and a `find_target` note for the SAME
  # association and the SAME bind (`Person.includes(:profile).find_by(id:)`,
  # conversation.rb:57) — one read, two notes, two producer edges for the fold
  # (D1 multiset). The not-found decision is minted HERE, with the SAME name
  # find_target would use (`<assoc_base_name>_not_found`); on that arm the
  # target is nil and the nested preload step is skipped.
  # Returns the attached child (nil on the not-found arm), or :not_attached
  # when this is not a singular association or the attach is not possible.
  def preload_attach(ct, owner, refl, psql)
    return :not_attached unless %i[belongs_to has_one].include?(refl.macro)
    return :not_attached unless owner.respond_to?(:association) && owner.respond_to?(:concolic_attrs)

    base  = ct.assoc_base_name(owner, refl.name)
    child = nil
    if assoc_decided?(owner, refl)
      nf_name   = "#{base}_not_found"
      not_found = symbool(nf_name, ct.seed_for(nf_name, false), note: psql)
      child = ct.symbolic_instance(refl.klass, base, psql) unless not_found == true
    else
      child = ct.symbolic_instance(refl.klass, base, psql)
    end
    assoc = owner.association(refl.name)
    assoc.target = child
    assoc.loaded!
    child
  rescue StandardError
    :not_attached
  end

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

  # B-7: `many:` is the OWNER LIST's cardinality decision. The real
  # `Preloader` issues ONE bulk statement per step whose predicate follows the
  # number of owner rows — `WHERE "t"."col" = ?` for a single owner,
  # `WHERE "t"."col" IN (?, ?, …)` for several. Rendering `=` unconditionally
  # asserts a one-row read in states where the app issues an IN-list (Rule T4:
  # "preload => one bulk IN (…), not per-row = $(…)"). The bind list stays the
  # ONE representative bind — the judges wildcard the list — because the model
  # has one representative row; only the SHAPE follows the cardinality.
  # B-8 / M-9 (coordinator, 2026-08-29) — A FALSY RETURN MUST STILL PUBLISH ITS
  # STATEMENT. The interceptor takes a target's note from the RETURNED value,
  # and nil/false can carry none, so every arm returning falsy silently DELETES
  # the statement it stands for from the corpus and hence from the extracted
  # policy. `CallInterceptor.extract_note` now also reads a one-shot
  # `Thread.current[:concolic_pending_note]`; publish through this ONE helper
  # immediately before returning the falsy value.
  # C-16: the app's column order for a table, from db/schema.rb (cached).
  def schema_column_order(table)
    @schema_orders ||= {}
    @schema_orders[table] ||= begin
      src = File.read(Rails.root.join("db", "schema.rb"))
      blk = src[/create_table "#{Regexp.escape(table)}".*?\n  end/m] || ""
      cols = blk.scan(/^\s+t\.\w+\s+"([^"]+)"/).flatten
      cols.empty? ? [] : ["id"] + cols
    rescue StandardError
      []
    end
  end

  def publish_note(sql)
    Thread.current[:concolic_pending_note] = sql
    nil
  end

  # M-7 (coordinator, 2026-08-29) — the preload predicate follows the DISTINCT
  # KEY COUNT, not the owner list length: two rows by the same author is `= ?`,
  # not `IN`. Ground truth, this app's own concrete runs: BOTH shapes occur for
  # the SAME step (comments_index/concrete_run_mobile.json carries
  # `people.id IN (?, ?)` AND `people.id = ?`; notifications_index likewise),
  # so neither operator may be hard-wired to the row count.
  #
  # Rule D (DISCIPLINE §13, coordinator 2026-08-29) — DERIVE WHAT IS
  # DETERMINED; DECIDE ONLY WHAT IS FREE. The key-set SIZE is often not free:
  #   (a) a step keyed on the OWNER's PRIMARY KEY (has_many, has_one and
  #       has_many-through all bind the owner's `id`) has exactly one key PER
  #       OWNER ROW, because distinct rows have distinct primary keys. N
  #       parents => N keys. A NESTED step follows the parents ACTUALLY
  #       LOADED, never the count of the level above it.
  #   (b) a step keyed on an owner column carrying a UNIQUE index is the same:
  #       one key per row. (`conversation_visibilities` is UNIQUE on
  #       (conversation_id, person_id), schema.rb:146.)
  #   (c) only a plain, non-unique belongs_to FK (`messages.author_id`) is
  #       genuinely free — several rows may share one author — so it becomes a
  #       RECORDED decision, never a constant.
  # Before this, every step rendered `= $(one bind)` unconditionally, so the
  # corpus could not express a bulk read at all and asserted a single-key read
  # in states where the schema DETERMINES two keys.
  def pred_for(ct, table, col, keys)
    rendered = keys.compact.map { |k| ct.render_arg_value(k) }
    op = rendered.length > 1 ? %(IN (#{rendered.join(', ')})) : %(= #{rendered.first})
    %("#{table}"."#{col}" #{op})
  end

  def second_key_memo
    Thread.current[:convidx_second_keys] ||= {}
  end

  def reset_second_keys!
    Thread.current[:convidx_second_keys] = {}
    Thread.current[:convidx_uniqcols] = {}
  end

  # Rule D(c): ONE physical row has ONE variable. The second owner row is
  # represented by the single column a given step binds, minted with the
  # OWNER's own producing query as its note (a real column value of a real
  # row, not a policy parameter — Rule V does not apply) and MEMOISED per run
  # per (row-prefix, column), so every step binding that row's column reuses
  # the SAME variable and the fold keeps that row's chain intact.
  def second_key(ct, owner_rep, col, note)
    return nil unless owner_rep.respond_to?(:concolic_attrs)
    idv = owner_rep.concolic_attrs["id"]
    return nil unless idv.respond_to?(:sym_name) && idv.sym_name
    vn = "#{idv.sym_name.sub(/_id\z/, '')}2_#{col}"
    second_key_memo[vn] ||= symint(vn, ct.seed_for(vn, 2), note: note)
  rescue StandardError
    nil
  end

  # Rule D(b): does this owner column hold one value per row?
  def unique_owner_column?(klass, col)
    return false unless klass && col
    c = col.to_s
    return true if (klass.primary_key.to_s == c rescue false)
    cache = (Thread.current[:convidx_uniqcols] ||= {})
    key = "#{klass.table_name}.#{c}"
    return cache[key] if cache.key?(key)
    cache[key] = begin
      klass.connection.indexes(klass.table_name).any? do |ix|
        ix.unique && Array(ix.columns).map(&:to_s) == [c]
      end
    rescue StandardError
      false
    end
  end

  # The modelled DISTINCT KEY SET for one preload step. 2 stands for "two or
  # more", the same convention the list length uses.
  def key_set_for(ct, owner, klass, col, bindv, n_owners, base, note)
    return [bindv] if n_owners.to_i <= 1
    if unique_owner_column?(klass, col)          # (a)/(b): DETERMINED
      k2 = second_key(ct, owner, col, note)
      return k2 ? [bindv, k2] : [bindv]
    end
    km = "#{base}_keys_many"                      # (c): FREE -> a decision
    if symbool(km, ct.seed_for(km, false), note: note) == true
      k2 = second_key(ct, owner, col, note)
      return k2 ? [bindv, k2] : [bindv]
    end
    [bindv]
  end

  # How many parents this step actually LOADED — what the nested step binds.
  def loaded_count(ct, owner, refl, keys, child, base, psql)
    return 0 if child.nil?
    return keys.length unless refl.macro == :has_one && assoc_decided?(owner, refl)
    return keys.length if child == :not_attached
    n = 1
    if keys.length > 1
      k2nf = "#{base}_k2_not_found"
      n += 1 unless symbool(k2nf, ct.seed_for(k2nf, false), note: psql) == true
    end
    n
  end

  def emit_includes_preloads(ct, receiver, rep, many: false)
    iv = receiver.respond_to?(:includes_values) ? Array(receiver.includes_values) : []
    return if iv.empty?
    return if receiver.respond_to?(:eager_loading?) && receiver.eager_loading?
    owner_klass = ct.model_class(receiver)
    rep_attrs   = rep.respond_to?(:concolic_attrs) ? rep.concolic_attrs : {}
    emit = nil
    emit = lambda do |owner, k, spec, bind_of, n_owners|
      pairs = spec.is_a?(Hash) ? spec.to_a : [[spec, nil]]
      pairs.each do |aname, nested|
        r2 = (k.reflect_on_association(aname.to_sym) rescue nil)
        next unless r2 && !r2.polymorphic?
        note = (owner.respond_to?(:concolic_note) ? owner.concolic_note : nil rescue nil)
        base = (ct.assoc_base_name(owner, r2.name) rescue "#{aname}")
        if r2.belongs_to?
          owner_col = r2.foreign_key.to_s
          bindv = bind_of.call(owner_col)
          next if bindv.nil?
          keys = key_set_for(ct, owner, k, owner_col, bindv, n_owners, base, note)
          psql = %(SELECT "#{r2.table_name}".* FROM "#{r2.table_name}" WHERE #{pred_for(ct, r2.table_name, "id", keys)})
          fallback_bind = lambda { |col| col == "id" ? bindv : nil }
        else
          bindv = bind_of.call("id")
          next if bindv.nil?
          # has_many / has_one / through all bind the OWNER's primary key
          keys = key_set_for(ct, owner, k, "id", bindv, n_owners, base, note)
          thr = (r2.respond_to?(:through_reflection) && r2.through_reflection) || nil
          t   = thr || r2
          psql = %(SELECT "#{t.table_name}".* FROM "#{t.table_name}" WHERE #{pred_for(ct, t.table_name, t.foreign_key, keys)})
          fallback_bind = lambda { |_col| nil } # child ids unknown — stop chain honestly
        end
        ConcolicThroughLoadProbe.load_intermediate(psql)
        child = preload_attach(ct, owner, r2, psql)
        n_loaded = loaded_count(ct, owner, r2, keys, child, base, psql)
        next if child.nil?   # B-4(b)/(c): not-found arm — nil attached, no nested step
        next unless nested
        next unless n_loaded.positive?

        if child == :not_attached
          emit.call(nil, r2.klass, nested, fallback_bind, n_loaded)
        else
          cattrs = child.respond_to?(:concolic_attrs) ? child.concolic_attrs : {}
          emit.call(child, r2.klass, nested, lambda { |col| cattrs[col] }, n_loaded)
        end
      end
    end
    iv.each { |spec| emit.call(rep, owner_klass, spec, lambda { |col| rep_attrs[col] }, many ? 2 : 1) }
  rescue StandardError
    nil # note-side extra must never crash the mock (M-family rule)
  end

  # cycle 4 (adversary round 2, W1): concrete-text -> symbolic-var map (per
  # run; run_dse.rb resets). A message's text is a concrete String (the
  # renderer's gsub/scan pipes need one) but the values the app EXTRACTS from
  # it and feeds into a query — the diaspora-link guid that
  # MessageRenderer#diaspora_links hands to Post.exists?(guid:) — are
  # symbolic vars whose concrete value is embedded in the text; the query
  # boundary maps the extracted literal back to its var so the note binds
  # `$$(<rep>_text_dlink_guid)` (same pattern as comments_index cycle 3).
  def text_binds
    Thread.current[:convidx_text_binds] ||= {}
  end

  def reset_text_binds!
    Thread.current[:convidx_text_binds] = {}
  end

  # Replace every quoted literal in a rendered note that is a registered
  # text-derived value with its `$$(var)` bind.
  def rebind_note_literals(sql)
    return sql if text_binds.empty?
    sql.gsub(/'((?:[^']|'')*)'/) do |m|
      lit = Regexp.last_match(1).gsub("''", "'")
      sv = text_binds[lit] || text_binds[lit.strip.downcase]
      sv ? "$$(#{sv.sym_name})" : m
    end
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
    names = iv.flat_map { |spec| spec.is_a?(Hash) ? spec.keys : [spec] }.map(&:to_sym)
    # inverse_of: rows read through an owner's has_many (ConvoSymAssociations
    # #conversation_visibilities) have the inverse belongs_to LOADED in real
    # AR (automatic inverse detection) — no validation SELECT for it on save.
    hint = receiver.respond_to?(:instance_variable_get) ? receiver.instance_variable_get(:@convidx_inverse_loaded) : nil
    names += Array(hint).map(&:to_sym)
    return if names.empty? || !rep.respond_to?(:instance_variable_set)
    rep.instance_variable_set(:@convidx_loaded_assocs, names.uniq)
  rescue StandardError
    nil
  end

  # The materialized row list for a relation (see the CARDINALITY LINK note
  # on SampledList.linked_to_count for the three cases).
  def rows_list(ct, receiver, vn, note, rep_builder)
    rel = ActiveRecord::Relation
    limited = receiver.is_a?(rel) && (receiver.limit_value || receiver.offset_value)
    # B-5 (coordinator harvest, 2026-08-28) — NOTHING EXISTS FOR AN EMPTY
    # RELATION. The length is read FIRST and the representative row is built
    # only when it is non-zero: a rep minted for a zero-row relation carries
    # `symbolic_instance`'s decisions (`_persisted`, `_text_has_mention`,
    # `_text_has_dlink`, `_subject`, ...) over a row that does not exist, which
    # inflates the coverage universe with states the app cannot reach
    # (ADVERSARY_WINS cross-endpoint pattern 8) — gating only the preload
    # emission leaves those decisions in place.
    mk = lambda do |len, name|
      SampledList.new(len, name: name, note: note,
                      representative: (len.to_i > 0 ? rep_builder.call : nil))
    end
    if limited
      if Thread.current[:convidx_page_beyond]
        # beyond the last page: the rows ARE empty (will_paginate OFFSET past
        # the end) — a list whose length domain is {0} (coverage_report
        # apply_len_bounds: *_rows_beyond -> low = high = 0), and therefore no
        # representative at all.
        return SampledList::BeyondPageList.new(0, name: "#{vn}_beyond", note: note, representative: nil)
      end
      return mk.call(ct.seed_for("len(#{vn})", 1), vn)
    end
    ck  = receiver.is_a?(rel) ? cardinality_key(ct, receiver) : nil
    cnt = ck && counts[ck]
    if cnt.is_a?(SymbolicInt)
      SampledList.linked_to_count(cnt, name: vn, note: note,
                                  representative: (cnt.value.to_i > 0 ? rep_builder.call : nil))
    else
      mk.call(ct.seed_for("len(#{vn})", 1), vn)
    end
  end

  # Real `count` statements project COUNT(...) — never the row columns that
  # sql_for's default `SELECT "t".*` rendering shows. Rewrite the projection
  # (tables/joins/predicates untouched; will_paginate strips LIMIT/OFFSET from
  # its count, and the note check ignores them anyway). An eager-loading
  # relation counts over its LEFT OUTER JOIN (`COUNT(*) FROM (SELECT DISTINCT
  # id ... LEFT OUTER JOIN ...)` — same tables/predicates as the join form).
  def count_sql_for(ct, receiver, args)
    eager = receiver.respond_to?(:eager_loading?) && receiver.eager_loading?
    sql = ct.sql_for(ConversationsIndexTargets.eager_relation(receiver, aliases: false), args)
    sql = sql.sub(/\s+ORDER BY\s.*\z/m, "").sub(/\s+LIMIT\s.*\z/m, "").sub(/\s+OFFSET\s.*\z/m, "")
    if eager
      # calculations.rb count over an eager-loading relation: `relation.distinct!`
      # on the pk, then `SELECT COUNT(*) FROM (<subquery>) subquery_for_count`
      # (will_paginate's total_entries takes the same route — adversary N2).
      table = ct.model_class(receiver).table_name
      pk = (ct.model_class(receiver).primary_key rescue "id")
      inner = sql.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, %(SELECT DISTINCT "#{table}"."#{pk}" FROM ))
      "SELECT COUNT(*) FROM (#{inner}) subquery_for_count"
    else
      sql.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT COUNT(*) FROM ")
    end
  rescue StandardError
    sql
  end

  # `exists?` statement: finder_methods.rb exists? builds
  # `relation.except(:select, :distinct, :order).select("1 AS one").limit(1)`.
  # NM-5 (adversary round 3) — `Calculations#sum` is in the SHARED target
  # boundary (`TARGET_FUNCTIONS.md` §1: "calculations | count sum | symbolic int
  # with COUNT/SUM note"). This batch never declared it because the ACTION never
  # calls it; the LAYOUT does — `User#unread_message_count` (user.rb:113-115) is
  # `ConversationVisibility.where(person_id:).sum(:unread)`, an AGGREGATE over the
  # very table this endpoint's access control is about. Undeclared, it issued no
  # statement at all (Class S).
  def sum_sql_for(ct, receiver, args, col)
    sql = ct.sql_for(ConversationsIndexTargets.eager_relation(receiver, aliases: false), args)
    sql = sql.sub(/\s+ORDER BY\s.*\z/m, "").sub(/\s+LIMIT\s.*\z/m, "").sub(/\s+OFFSET\s.*\z/m, "")
    table = (ct.model_class(receiver).table_name rescue nil)
    proj  = table ? %(SUM("#{table}"."#{col}")) : %(SUM("#{col}"))
    sql.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT #{proj} FROM ")
  rescue StandardError
    sql
  end

  def exists_sql_for(ct, receiver, args)
    sql = ct.sql_for(receiver, args)
    sql = sql.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT 1 AS one FROM ")
    sql = sql.sub(/\s+ORDER BY\s.*\z/m, "")
    sql = sql =~ /\sLIMIT\s/ ? sql : "#{sql} LIMIT 1"
    ConversationsIndexTargets.rebind_note_literals(sql)
  rescue StandardError
    sql
  end

  # Finder mock that ALSO emits the preload steps of a finder carrying
  # `includes_values` (Conversation#last_author's
  # `Person.includes(:profile).find_by(id: ...)`: the real path issues the
  # people lookup THEN `SELECT profiles.* WHERE person_id IN (?)`). Wraps the
  # shared finder_mock — note fidelity and the not_found decision unchanged.
  # Faithful single-row finder statement (cycle 3, CHECKS.md F7 — ordering
  # and limit are part of the note): Rails' `first`/`last` order by the
  # primary key when the relation carries no order (finder_methods.rb
  # ordered_relation) and every single-row finder appends LIMIT 1.
  def finder_note(ct, receiver, args, kind)
    # A3-15 (H6 evidence, adversary round 3): a finder on an EAGER-LOADING
    # relation issues the eager form — `@visibilities` is
    # `includes(:conversation).order("conversations.updated_at DESC")`, which
    # `references` conversations, so its `take(11)` (Relation#inspect on the
    # unloaded relation, the `.js` NameError path) is the aliased LEFT OUTER
    # JOIN with `LIMIT ? OFFSET ?` — shape-identical to the paginated read the
    # real run issues. Rendering the plain relation here produced a statement
    # the app never issues (H6: "2 note shapes never issued by any run").
    # Same routing `to_a`/`count` already use.
    sql = ct.sql_for(ConversationsIndexTargets.eager_relation(receiver), args)
    table = begin
      ct.model_class(receiver).table_name
    rescue StandardError
      nil
    end
    if %i[first last].include?(kind) && table && !sql.include?(" ORDER BY ")
      pk = (ct.model_class(receiver).primary_key rescue "id")
      sql = %(#{sql} ORDER BY "#{table}"."#{pk}" #{kind == :last ? 'DESC' : 'ASC'})
    end
    sql = "#{sql} LIMIT 1" unless sql =~ /\sLIMIT\s/
    ConversationsIndexTargets.rebind_note_literals(sql)
  end

  # B-6 (coordinator propagation matrix, 2026-08-28) — NEVER RAISE INSIDE A
  # `returns` LAMBDA. The interceptor records a target's `symbolic_call` event
  # AND ITS NOTE only after the lambda RETURNS, so a mock that raises swallows
  # the very statement it stands for: the real `find` DOES issue its SELECT and
  # only then raises RecordNotFound, so raising here fixes a Class-B gap by
  # opening a Class-S one. Instead return a POISONED value: the interceptor
  # reads `#concolic_note` off it (so the statement is recorded), and the FIRST
  # APP USE of it raises the real exception. Poisoned by `method_missing`, i.e.
  # EVERY app method, not an enumerated list of call sites — enumerating call
  # sites is the instance-shaped fix Rule P forbids. Only the RUNTIME's own
  # inspection protocol is answered (the same rep-plumbing / app-method line
  # Rule S §4 draws).
  unless defined?(PoisonedRecord)
    ::Object.const_set(:PoisonedRecord, Class.new do
      RUNTIME_PROTOCOL = %i[concolic_note class is_a? kind_of? instance_of? respond_to?
                            inspect to_s nil? hash eql? == != object_id frozen? freeze dup
                            instance_variable_get instance_variable_set instance_variables
                            method methods singleton_class define_singleton_method tap].freeze

      def initialize(err_class, message, note)
        @err_class = err_class
        @message   = message
        @note      = note
      end

      def concolic_note
        @note
      end

      def respond_to_missing?(_name, _priv = false)
        false
      end

      def method_missing(name, *_args, &_blk)
        return super if RUNTIME_PROTOCOL.include?(name)

        raise @err_class, @message
      end
    end)
  end

  def finder_mock_with_preloads(ct, raise_on_missing:, kind: :find_by)
    lambda do |receiver, args, name|
      sql = ConversationsIndexTargets.finder_note(ct, receiver, args, kind)
      # C-18 (adversary round 6): the real finder casts every bind through the
      # column type while the statement is built (`QueryAttribute#value_for_database`
      # -> `Type::Integer#ensure_in_range`), and an out-of-range integer raises
      # `ActiveModel::RangeError` AFTER the sql event has fired. The mock never
      # executed the statement, so the cast never ran. Run the relation's own
      # bound attributes through `value_for_database` here (the app's type code,
      # unmodified); on a raise return the POISON (B-6) carrying this statement
      # — the first app use of the result raises the real error.
      begin
        # AR 5.2 keeps the typed binds INSIDE the where AST (Arel::Nodes::BindParam
        # -> QueryAttribute); walk it — the same attributes the executor casts.
        binds = begin
          receiver.where_clause.ast.grep(Arel::Nodes::BindParam).map(&:value)
        rescue StandardError
          []
        end
        # Only CONCRETE binds are cast: a SYMBOLIC bind stands for a column value
        # and is in range by construction, and the runtime forbids `to_i` on it
        # by design — casting it raised NotImplementedError on every scalar and
        # non-empty-array cid run (A6-7: the corpus lost the `= ?` and `IN (?, ?)`
        # reads while coverage still read "complete" over the crashed runs).
        binds.each do |qa|
          next unless qa.respond_to?(:value_for_database)
          v = qa.respond_to?(:value_before_type_cast) ? qa.value_before_type_cast : nil
          next if v.respond_to?(:sym_name) || (v.is_a?(Array) && v.any? { |x| x.respond_to?(:sym_name) })
          qa.value_for_database
        end
      rescue ActiveModel::RangeError => e
        next PoisonedRecord.new(ActiveModel::RangeError, e.message, sql)
      end
      nf_name = "#{name}_not_found"
      # Rule D (DISCIPLINE §13): if this relation's CARDINALITY was already
      # decided (`count` memo, cardinality_key), a `first`/`take`/`last` on it
      # cannot decide "found" freely — an EMPTY relation returns no row. Found
      # 178/193 js dumps asserting `count > 0` FALSE beside `take` FOUND (the
      # `.js` NameError -> Relation#inspect -> take(11) path, index.haml:16/32).
      # Derived from the SAME count var: no new variable, no free decision.
      ck  = receiver.is_a?(ActiveRecord::Relation) ? ConversationsIndexTargets.cardinality_key(ct, receiver) : nil
      cnt = ck && ConversationsIndexTargets.counts[ck]
      not_found = if cnt.is_a?(SymbolicInt) && %i[first take last].include?(kind)
                    ((cnt > 0) == true) ? false : true
                  else
                    symbool(nf_name, ct.seed_for(nf_name, false), note: sql)
                  end
      if not_found == true # explicit compare — bare truthiness records no PC (TODO.txt)
        # B-6: return the poison, do NOT raise here — the interceptor has not
        # yet recorded this target's event/note, and the real `find` issues the
        # statement before it raises.
        next PoisonedRecord.new(ActiveRecord::RecordNotFound,
                                "concolic: empty result for: #{sql}", sql) if raise_on_missing

        # B-8: the real finder ISSUED this statement and got no row back.
        next ConversationsIndexTargets.publish_note(sql)
      end
      rep = ct.symbolic_instance(ct.model_class(receiver), name, sql)
      ConversationsIndexTargets.emit_includes_preloads(ct, receiver, rep)
      ConversationsIndexTargets.tag_loaded_assocs(receiver, rep)
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
    interceptor.declare_target(rel, :convidx_conv_lookup,
                               returns: finder_mock_with_preloads(ct, raise_on_missing: false, kind: :first))

    # Finders that may carry includes_values -> preload-emitting finder mock
    # (same returns as the shared design-#2 declarations otherwise).
    %i[find_by first last take].each do |m|
      interceptor.declare_target(fm, m, returns: finder_mock_with_preloads(ct, raise_on_missing: false, kind: m))
    end
    interceptor.declare_target(fm, :find, returns: finder_mock_with_preloads(ct, raise_on_missing: true, kind: :find))

    # EXISTENCE PROBES (cycle 3, adversary N1 STAR-OVER): `empty?`/`any?`/
    # `none?`/`exists?` on an unloaded relation are `SELECT 1 AS one FROM …
    # LIMIT 1` (relation.rb empty? -> !exists?; finder_methods.rb exists?
    # strips select/order/distinct) — an existence bit, never a whole-row
    # read. Note the real projection; the decision stays the shared design's
    # `<name>_<pred>` symbool.
    {
      exists?: [fm, false],
      any?:    [rel, true],
      none?:   [rel, false],
      empty?:  [rel, false],
    }.each do |m, (mod, seed)|
      interceptor.declare_target(mod, m, returns: lambda do |receiver, args, name|
        vn = "#{name}_#{m.to_s.delete('?')}"
        v = symbool(vn, ct.seed_for(vn, seed), note: ConversationsIndexTargets.exists_sql_for(ct, receiver, args))
        # cycle 4 (adversary round 2, W1/NM-5 — D2): the app consumes these
        # in TRUTHINESS position (`Post.exists?(guid) ? … : …`,
        # `- if no_contacts`), which Ruby decides at C level — a SymbolicBool
        # is always truthy, so the False side could never be taken and no PC
        # was recorded. Record the decision here (`vn == True`) and return a
        # value whose truthiness matches it: the SymbolicBool (note-bearing)
        # on the true side, nil on the false side (the decision var carries
        # the statement note).
        # B-8: the FALSE arm returns nil so the app's truthiness test decides
        # correctly, but the real relation STILL issued its existence probe —
        # publish it out of band or the statement leaves the corpus.
        v == true ? v : ConversationsIndexTargets.publish_note(
          ConversationsIndexTargets.exists_sql_for(ct, receiver, args))
      end)
    end

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
    if defined?(::WillPaginate::ActiveRecord::RelationMethods)
      wp = ::WillPaginate::ActiveRecord::RelationMethods
      wp.prepend(ConvPaginatedTotal) unless wp < ConvPaginatedTotal
    end

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
        # (No order-column append here: ground truth on this endpoint —
        # `SELECT "messages"."author_id" FROM "messages" … ORDER BY created_at ASC`,
        # adversary W1 — projects exactly the requested columns.)
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
      # CARDINALITY LINK for pluck (2026-08-28, over-emission scan: 135/1500
      # dumps carried `SELECT "people".* WHERE "people"."id" = nil LIMIT 1`, a
      # statement the app cannot issue). `pluck` returns ONE ROW PER ROW of the
      # same query — its length IS that query's count, so an independent seed
      # let `messages.size > 0` hold while `messages.pluck(:author_id)` was
      # empty, and `last_author`'s `Person.includes(:profile).find_by(id: nil)`
      # (conversation.rb:55-57) minted a note for a read that never happens.
      # Same rule as the materialization link: one fact, one variable.
      ck  = receiver.is_a?(rel) ? ConversationsIndexTargets.cardinality_key(ct, receiver) : nil
      cnt = ck && ConversationsIndexTargets.counts[ck]
      if cnt.is_a?(SymbolicInt)
        SampledList.linked_to_count(cnt, name: vn, note: note, representative: rep)
      else
        list = SampledList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: note, representative: rep)
        ConversationsIndexTargets.counts[ck] = list.symbolic_len if ck
        list
      end
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
      # B-5: the representative row (and everything it decides) exists only if
      # the relation returns a row. rows_list calls this builder at most once,
      # and only when the length it reads is non-zero.
      rep = nil
      builder = lambda do
        rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", note)
        ConversationsIndexTargets.tag_loaded_assocs(receiver, rep)
        rep
      end
      list = ConversationsIndexTargets.rows_list(ct, receiver, vn, note, builder)
      # ...and the real Preloader issues nothing for an empty record set.
      # B-7: the preload's PREDICATE follows the owner list's cardinality, and
      # `many?` is what RECORDS that 0/1/many decision on the length var.
      ConversationsIndexTargets.emit_includes_preloads(ct, receiver, rep, many: (list.many? == true)) if rep
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
      rep = nil # B-5: no row, no representative (see rows_list)
      builder = lambda do
        rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", note)
        ConversationsIndexTargets.tag_loaded_assocs(receiver, rep)
        rep
      end
      list = ConversationsIndexTargets.rows_list(ct, receiver, vn, note, builder)
      ConversationsIndexTargets.emit_includes_preloads(ct, receiver, rep, many: (list.many? == true)) if rep
      receiver.instance_variable_set(:@convidx_rows, list) if receiver.is_a?(rel)
      # cycle 4 (hardening_lint H4 / D2): `to_ary` hands the rows to REAL
      # Array code (`ordered_participants - [current_user.person]`, then
      # `other_participants.first.present?` at _conversation.haml:12) — a
      # ::Array's `first`/`present?` are concrete, so the emptiness of this
      # list decided a branch without recording anything (violation 0a's
      # class: the state was explored via the seed but carried no label).
      # Record the length decision here, exactly as SampledList#empty? does
      # for the iterated lists.
      list.empty?
      # ENGINE-PROTOCOL HAZARD (found by B-7, 2026-08-28): the interceptor
      # reads a `returns` lambda's value as the PAIR `[value, sort]` whenever
      # it is an Array OF LENGTH 2 (call_interceptor.rb:150-156). `to_ary` must
      # hand Ruby a REAL Array (Array#+ type-checks it), so the moment the
      # sampled list's cardinality domain became 0/1/MANY this mock started
      # returning a 2-element array and the interceptor silently took its FIRST
      # ELEMENT as the result — `Array#+` then raised "Person::ActiveRecord_Relation
      # #to_ary gives Person" (conversation.rb:61). Disambiguate by returning
      # the explicit pair, with the SAME sort the interceptor would compute for
      # an Array (`sort_of` -> "Int", symbolic_func.rb:158). Correct at every
      # length, not just at 2. Reported as an engine finding.
      [SampledRowsArray.build(list.concrete_length, rep, name: vn, note: note), "Int"]
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
      cp.prepend(ConvLoadedProxy) unless cp < ConvLoadedProxy # C-13: second read from memory
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

        # cycle 3: `conversation.participants.size - 1`
        # (_conversation.mobile.haml:21, the participant_count badge) —
        # arithmetic on a count keeps its symbolic identity as a named
        # expression (mirrors SymbolicInt#-@ / #next), never concretizes.
        def -(other)
          o = other.respond_to?(:value) ? other.value : other
          ConcolicIntValue.new(value - o, name: (sym_name ? "(#{sym_name} - #{o})" : nil), note: note)
        end

        def +(other)
          o = other.respond_to?(:value) ? other.value : other
          ConcolicIntValue.new(value + o, name: (sym_name ? "(#{sym_name} + #{o})" : nil), note: note)
        end

        # will_paginate collection.rb:16 `total_pages`:
        #   total_entries.zero? ? 1 : (total_entries / per_page.to_f).ceil
        # The pager total (ConvPaginatedTotal) is a DERIVED number whose only
        # consumer is the number of page links rendered — no statement, and
        # the emptiness fact it would re-ask (`(len > 0)`) was already recorded
        # on the real length var when it was derived. So these two answer
        # concretely rather than minting a PC on a derived expression name.
        def zero?
          value.zero?
        end

        def /(other)
          o = other.respond_to?(:value) ? other.value : other
          value.to_f / o.to_f
        end

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
      # cardinality link (SampledList.linked_to_count): the FIRST count of a
      # query is the cardinality its later materialization obeys — and a
      # SECOND count of the SAME query in the same request (the mobile
      # partials count `messages` twice, will_paginate re-counts the
      # visibilities) is the same number: one variable, one fact, two
      # statements (each call still records its own event + note).
      ck = receiver.is_a?(rel) ? ConversationsIndexTargets.cardinality_key(ct, receiver) : nil
      prior = ck && ConversationsIndexTargets.counts[ck]
      next prior if prior.is_a?(SymbolicInt)
      vn = "#{name}_count"
      v = ConcolicIntValue.new(ct.seed_for(vn, 1), name: vn,
                               note: ConversationsIndexTargets.count_sql_for(ct, receiver, args))
      ConversationsIndexTargets.counts[ck] = v if ck
      v
    end)

    # §5b-bis. `Calculations#sum` — shared boundary, reached only through the
    # LAYOUT on this endpoint (NM-5). Same shape as `count`: a symbolic int whose
    # note is the relation's own statement with a SUM projection. `unread` is an
    # `integer NOT NULL default 0` with no CHECK, so the sum is unconstrained in
    # sign (P12's negative legacy row) — seeded 0, left free.
    interceptor.declare_target(calc, :sum, returns: lambda do |receiver, args, name|
      col = begin
              a = args.is_a?(Hash) ? Array(args["splat_args"]).first : nil
              (a || :unread).to_s
            rescue StandardError
              "unread"
            end
      vn = "#{name}_sum_#{col}"
      ConcolicIntValue.new(ct.seed_for(vn, 0), name: vn,
                           note: ConversationsIndexTargets.sum_sql_for(ct, receiver, args, col))
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

          # APP-DEFINED COLUMN OVERRIDES RUN FOR REAL (cycle 3, adversary N8):
          # symbolic_instance defines a singleton reader per COLUMN, which
          # SHADOWS a model method of the same name — `Conversation#subject`
          # (conversation.rb:64 `self[:subject].blank? ? I18n.t(…) :
          # self[:subject]`) never ran, so its blank? decision was blind (D2).
          # Drop the singleton reader when the model class itself defines the
          # method; it then reads the column through `self[:col]` (the rep's
          # `[]`), whose SymbolicString#empty? records `(subject == '')`.
          klass.columns_hash.each_key do |col|
            next if col == "image_url" # Profile#image_url: deliberate per-instance override (shared file)
            next unless klass.instance_methods(false).include?(col.to_sym) ||
                        klass.private_instance_methods(false).include?(col.to_sym)
            obj.singleton_class.send(:remove_method, col) if obj.singleton_methods(false).include?(col.to_sym)
          end

          # DIRTY TRACKING for the save target's UPDATE note (cycle 3, adversary N4)
          dirty = []
          obj.define_singleton_method(:convidx_dirty) { dirty }
          # C-16 (adversary round 6): AR orders a record's FIRST UPDATE in a
          # request by column order, but after `changes_applied` the attribute
          # set is rebuilt from the MATERIALISED attributes in order of first
          # access (attribute_set.rb#map / LazyAttributeHash), so a LATER save's
          # SET list follows first-access order — `updated_at` (touched by the
          # first save) before `last_seen` (first read by stamp! afterwards).
          # Every column reader and writer on the rep records first access.
          access = []
          obj.define_singleton_method(:convidx_access) { access }
          # R6-NM-2: AR's own dirty API on a rep answers from the C-5 dirty set —
          # `Rememberable#remember_me!` does `save(validate: false) if changed?`,
          # and the rep's `changed?` said false, so the remember write never
          # happened (measured: a future cookie on a not-remembered principal
          # logged in with two writes, real: three).
          # AR's `changed?` iterates EVERY attribute (materialising all of them,
          # in column order) — which is why a record saved by `remember_me!`
          # (`save if changed?`) keeps column order on its next save (real NM-2),
          # while one saved by trackable (no `changed?`) does not (real C-16).
          obj.define_singleton_method(:changed?) { klass.column_names.each { |c| access << c unless access.include?(c) } rescue nil; !dirty.empty? }
          obj.define_singleton_method(:has_changes_to_save?) { klass.column_names.each { |c| access << c unless access.include?(c) } rescue nil; !dirty.empty? }
          obj.instance_variable_set(:@convidx_saved, false)
          klass.columns_hash.each_key do |col|
            next unless obj.singleton_methods(false).include?(col.to_sym)
            rd = obj.method(col)
            obj.define_singleton_method(col) do |*a, &blk| # transparent: Profile#image_url(:thumb_small) takes an argument
              access << col unless access.include?(col)
              rd.call(*a, &blk)
            end
          end
          # W1 / C-5 (adversary round 3) — DIRTY MEANS CHANGED. `ActiveModel::Dirty`
          # marks an attribute dirty only when the written value DIFFERS from the
          # one already there; Rails partial writes then send only the changed
          # columns, and for an unchanged record `_update_record` writes NOTHING
          # (no UPDATE, and the timestamp callback does not fire). Marking every
          # write dirty made the write UNCONDITIONAL, so the corpus asserted an
          # UPDATE in states where the real endpoint issues none.
          #
          # The comparison is SYMBOLIC and records its own PC, which is what makes
          # the write DERIVED rather than decided (Rule D): `set_read` assigns
          # `unread = 0`, so `(unread == 0)` is exactly the fact that decides it.
          # `(old == v) == true` is required — a bare `!(old == v)` would take the
          # Ruby truthiness of a SymbolicBool (always true) and record no PC.
          %i[write_attribute _write_attribute []=].each do |wm|
            obj.define_singleton_method(wm) do |k, v|
              key = k.to_s
              old = attrs[key]
              # Re-assigning the SAME value object is a no-op write (A5-8): the
              # Rule-D derivation under a first-ever login makes
              # last_sign_in_ip the very object current_sign_in_ip holds, and
              # trackable's `last := old current` then hands that object back.
              # Comparing an object with itself through `==` recorded the
              # tautology `(X == X)` — an undocumentable PC — so identity is
              # decided before any symbolic compare.
              same = begin
                       if old.equal?(v) then true
                       elsif old.nil? then v.nil?
                       elsif v.respond_to?(:sym_name) && old.respond_to?(:sym_name) && old.sym_name &&
                             v.sym_name.to_s =~ /\A\(#{Regexp.escape(old.sym_name.to_s)} [+-] (\d+)\)\z/ && Regexp.last_match(1).to_i != 0
                         # A5-9 (Rule D): a value DERIVED from the old one by a
                         # non-zero offset (`sign_in_count += 1` -> a
                         # ConcolicIntValue named `(X + 1)`) is a change BY
                         # CONSTRUCTION. Comparing it symbolically recorded
                         # `(X == (X + 1))` — a constant-false PC the engine's
                         # probe can never flip (107 NOT-TESTABLE pairs).
                         false
                       else ((old == v) == true)
                       end
                     rescue StandardError
                       false
                     end
              dirty << key unless same || dirty.include?(key)
              access << key unless access.include?(key)
              attrs[key] = v
            end
          end

          # GUID PIN (2026-08-28, the comments_index "impossible state" pattern).
          # Person / Message / Conversation all `include Diaspora::Fields::Guid`,
          # whose `after_initialize :set_guid` fills a blank guid on EVERY
          # instantiation — including a row loaded from the database — and the
          # column is NOT NULL with a unique index. So a query-returned row can
          # never have a blank guid: the `guid.blank?` decision that route
          # generation makes (blank.rb:126 via journey's missing_keys, and
          # formatter.rb:41) has exactly ONE realizable outcome. Keeping it as a
          # decision explored a state the app cannot be in (and its True side is
          # what used to raise "No route matches ... id=>nil"). PIN, ledger entry
          # here; verified first that NO note binds a rep guid (over-emission
          # scan, 2026-08-28: `rep-guid binds in notes: NONE`), so the pin costs
          # no bind. ConcreteSymbolicString => `blank?`/`==` are concrete and
          # record nothing.
          if attrs.key?("guid") && defined?(ConcreteSymbolicString)
            gv = ConcreteSymbolicString.build("concolicguid#{base_name.hash.abs.to_s(16)}",
                                              name: nil, note: "guid pin (Fields::Guid after_initialize)")
            attrs["guid"] = gv
            obj.define_singleton_method(:guid) { gv }
          end

          # DIASPORA HANDLE as a SampledString (cycle 3): Person#fix_profile's
          # `DiasporaFederation::Discovery::Discovery.new(diaspora_handle)`
          # (discovery.rb:43) does `.strip.downcase` on the handle BEFORE
          # the declared fetch_and_save wall is reached; SymbolicString
          # refuses strip by design. Same var name/seed/note, identity ops
          # only (targets.rb SampledString) — the handle is never compared
          # on this endpoint, so no decision is lost.
          if attrs.key?("diaspora_handle") && attrs["diaspora_handle"].is_a?(SymbolicString) &&
             !attrs["diaspora_handle"].is_a?(ConversationsIndexTargets::SampledString)
            old = attrs["diaspora_handle"]
            attrs["diaspora_handle"] = ConversationsIndexTargets::SampledString.new(old.value, name: old.sym_name, note: old.note)
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

          # cycle 4 (adversary round 2, W1 + NM-5): the text-content decision
          # family. The text stays a concrete String (the renderer's regex
          # pipes need one) but everything the app can EXTRACT from it and
          # branch/query on is a seeded, PC-recorded decision (D2), and every
          # extracted query argument is a symbolic var (its value embedded in
          # the text, mapped back at the query boundary — text_binds):
          #   _text_has_mention   -> "@{Name; handle}" markup (Mentionable.format
          #                          with an EMPTY mentioned_people list — no
          #                          lookup on this endpoint; adversary R08)
          #   _text_has_dlink     -> a `diaspora://<id>/<entity>/<guid>` link
          #                          (DiasporaUrlParser::DIASPORA_URL_REGEX):
          #                          MessageRenderer#diaspora_links runs for
          #                          real and, on the "post" entity, issues
          #                          Post.exists?(guid:) — the existence probe
          #                          the corpus lacked (W1)
          #   _text_dlink_is_post -> the link's entity is "post" (exists? fires)
          #                          vs "comment" (`Regexp.last_match(2) ==
          #                          "post"` false — no query); recorded here
          #                          because the renderer's compare is on a
          #                          concrete String
          #   _text_dlink_guid    -> the guid, a symbolic var; Post.exists?'s
          #                          note binds $$(<rep>_text_dlink_guid)
          if attrs.key?("text")
            hm_name = "#{base_name}_text_has_mention"
            has_mention = symbool(hm_name, seed_for(hm_name, false), note: sql)
            dl_name = "#{base_name}_text_has_dlink"
            has_dlink = symbool(dl_name, seed_for(dl_name, false), note: sql)
            parts = ["hello world, a concolic message"]
            parts << "@{Concolic Mention; concolic_mention@example.org}" if has_mention == true
            if has_dlink == true
              ip_name = "#{base_name}_text_dlink_is_post"
              is_post = symbool(ip_name, seed_for(ip_name, true), note: sql)
              # RULE V / B-3 (2026-08-28, found by the comments_index agent):
              # a value parsed OUT OF a column's CONTENT has NO producing
              # column, but the fold binds `$$(VAR)` by the longest
              # underscore-delimited suffix of the name that IS a column of the
              # producing row — and `..._text_dlink_guid` ends in `guid`, which
              # is a column of `messages`. The extracted view then asserted
              # `posts.guid = messages.guid`, a join the app never performs
              # (3 176 misbound occurrences; the audit had counted only
              # UNRESOLVABLE, so it read green). Mint it as a POLICY PARAMETER
              # (SYM_PARAM_* family, no SQL note) so the fold renders a
              # parameter instead of a column bind.
              gv = "SYM_PARAM_dlink_guid_#{base_name}"
              guid = symstr(gv, seed_for(gv, "concolicguid00000000001"))
              ConversationsIndexTargets.text_binds[guid.value.to_s] = guid
              parts << "diaspora://concolic_link@example.org/#{is_post == true ? 'post' : 'comment'}/#{guid.value}"
            end
            parts << "welcome"
            txt = parts.join(" ")
            attrs["text"] = txt
            obj.define_singleton_method(:text) { txt }
          end

          # C-12 (adversary round 4) — DISPLAY NAMES rendered by the REAL mobile
          # layout: `_drawer.mobile.haml:20 link_to aspect.name` (html_escape ->
          # `scrub`) and `:27 tag_link(tag)` (acts_as_taggable_on `normalize` ->
          # `=~`) are string walls a SymbolicString cannot pass (75/90 mobile
          # smoke runs raised). `aspects.name` / `tags.name` are display text —
          # no statement and no access decision depends on them — so they get
          # the `text`/`guid` treatment: a concrete String carrying the var name
          # and the row's own note, PINNED (pin ledger: `name`), stated-class
          # fact for Aspect and ActsAsTaggableOn::Tag only.
          if attrs.key?("name") && defined?(ConcreteSymbolicString) &&
             (klass.name == "Aspect" || klass.name == "ActsAsTaggableOn::Tag")
            nv = ConcreteSymbolicString.build("concolic#{klass.table_name}name",
                                              name: "#{base_name}_name", note: sql)
            attrs["name"] = nv
            obj.define_singleton_method(:name) { nv }
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

    # =====================================================================
    # §8. SingularAssociation#find_target — batch-local redeclaration of the
    # shared W3/Patch-1 mock (cycle 3): (a) `LIMIT 1` (the real load is
    # `… LIMIT ?`, F7 ordering/limit fidelity); (b) has_one loads carry a
    # `<base>_not_found` DECISION — `profiles.person_id` is an FK but nothing
    # forces a profile row to exist (adversary A03/A04: `person.profile.nil?`
    # at people_helper.rb:37/43 and Person#name's fix_profile were BLIND);
    # (c) belongs_to loads on this endpoint are PINNED found: every FK
    # column is NOT NULL with an ON DELETE CASCADE foreign key
    # (schema.rb: messages.author_id 633, conversations.author_id 628,
    # conversation_visibilities.person_id/conversation_id 626-627,
    # contacts.person_id 625) — no row can point at a missing parent;
    # (d) `User has_one :person` is pinned found: the sign-up transaction
    # creates both rows and a user without a person is not an app state
    # (pin ledger, AGENT_RUN.md); (e) a rep that went through `reload` after
    # federation discovery (Person#fix_profile) has its profile pinned found —
    # Discovery#fetch_and_save either saves the profile or raises
    # DiscoveryError (a 500); a nil profile after discovery is not an app
    # state (pin ledger).
    # =====================================================================
    sa = ActiveRecord::Associations::SingularAssociation
    interceptor.declare_target(sa, :find_target, returns: lambda do |receiver, _args, _name|
      begin
        refl  = receiver.reflection
        klass = refl.klass
        next nil unless klass && klass.respond_to?(:allocate)
        owner = receiver.owner
        base  = ct.assoc_base_name(owner, refl.name)
        sql = begin
          table = klass.table_name
          if refl.belongs_to?
            col = refl.association_primary_key(klass)
            fk_raw = owner[refl.foreign_key]
          else
            col = refl.foreign_key
            fk_raw = owner[refl.active_record_primary_key]
          end
          %(SELECT "#{table}".* FROM "#{table}" WHERE "#{table}"."#{col}" = #{ct.render_arg_value(fk_raw)} LIMIT 1)
        rescue StandardError
          "SingularAssociation##{refl.name}"
        end
        # B-4 (2026-08-28): ONE predicate, shared with the preload attach —
        # `ConversationsIndexTargets.assoc_decided?` is the single definition of
        # "does this singular load carry a not-found decision?" (see its comment
        # for the schema evidence). find_target is only reached for an
        # association that was NOT preloaded; a preloaded one is answered from
        # the association cache the attach filled, so it mints no second read.
        decided = ConversationsIndexTargets.assoc_decided?(owner, refl)
        if decided
          nf_name = "#{base}_not_found"
          not_found = symbool(nf_name, ct.seed_for(nf_name, false), note: sql)
          # B-8: the association load ran and returned nothing — the SELECT is
          # still a statement this request issued.
          next ConversationsIndexTargets.publish_note(sql) if not_found == true
        end
        ct.symbolic_instance(klass, base, sql)
      rescue StandardError
        nil
      end
    end)

    # §8b. Base#save on a symbolic rep (cycle 3, adversary N4): the real save
    # (conversation.rb:41 set_read) issues the `belongs_to` presence
    # validations' SELECTs for associations not already loaded
    # (`SELECT "people".* … WHERE id = ? LIMIT 1` for the visibility's person;
    # `conversation` is loaded through inverse_of) and then the UPDATE of the
    # dirty columns. Mint both: the SELECTs through the load probe, the UPDATE
    # as the save note. The decision (save ok) stays the shared symbool.
    %i[save save!].each do |m|
      interceptor.declare_target(ActiveRecord::Base, m, returns: lambda do |receiver, _args, name|
        note = "#{receiver.class.name}##{m}"
        if receiver.respond_to?(:concolic_attrs)
          begin
            klass  = receiver.class
            table  = klass.table_name
            loaded = Array(receiver.instance_variable_get(:@convidx_loaded_assocs)).map(&:to_sym)
            klass.reflect_on_all_associations(:belongs_to).each do |r2|
              next if r2.options[:optional] || r2.polymorphic? || loaded.include?(r2.name.to_sym)
              next unless klass.respond_to?(:belongs_to_required_by_default) && klass.belongs_to_required_by_default
              fk = receiver.concolic_attrs[r2.foreign_key.to_s]
              next if fk.nil?
              ConcolicThroughLoadProbe.load_intermediate(
                %(SELECT "#{r2.table_name}".* FROM "#{r2.table_name}" WHERE "#{r2.table_name}"."#{r2.association_primary_key}" = #{ct.render_arg_value(fk)} LIMIT 1))
            end
            dirty = receiver.respond_to?(:convidx_dirty) ? receiver.convidx_dirty : []
            if dirty.empty?
              # W1 / C-5: NO UPDATE. Measured (`P04_cid1_unread0_json`): a
              # visibility already at `unread = 0` gives BEGIN / the belongs_to
              # presence-validation SELECT / COMMIT and no write at all. The
              # validations above still ran and are still emitted; only the
              # UPDATE disappears. A declaration note (not SQL) keeps the call
              # from being note-less while asserting no statement.
              note = %(#{receiver.class.name}##{m} NO-WRITE (record unchanged; Rails partial writes issue no statement))
            else
              # AR lists the changed columns in the model's COLUMN order, the
              # timestamp last (measured on trackable's first-login write:
              # `sign_in_count, current_sign_in_at, last_sign_in_at,
              # current_sign_in_ip, last_sign_in_ip, updated_at`).
              # C-16 (adversary round 6) — AR orders a save's SET list by the
              # record's ATTRIBUTE-SET KEY ORDER (`changed_attribute_names_to_save`
              # iterates `attributes.keys`). Before the first save that is the
              # DB column order. `changes_applied` then rebuilds the set with
              # `AttributeSet#map` -> `LazyAttributeHash#materialize`, which keeps
              # the keys already MATERIALISED (accessed) in their positions and
              # appends the not-yet-materialised ones — so from the first save on,
              # the order is FROZEN as [materialised-before-that-save, column
              # order] + [the rest, column order]. `updated_at` is materialised by
              # the first save's timestamp touch; a column first read AFTER it
              # (`last_seen` by stamp!) lands after — `updated_at, last_seen`
              # (real C-16) — while a record whose `changed?` was asked before its
              # first save (`remember_me!`) has everything materialised and keeps
              # column order (real NM-2). Measured against all five real orders
              # on this rig; the rig's own column order (`column_names`) is the
              # order the real runs the judges compare against were written in.
              # C-16 (adversary round 6) — the rule that reproduces ALL FIVE real
              # write orders measured on this rig (session `last_seen, updated_at`;
              # trackable `sign_in_count … last_sign_in_ip, updated_at`;
              # post-trackable `updated_at, last_seen`; `remember_created_at,
              # updated_at`; trackable after remember_me! `…, updated_at`):
              #   * a record's FIRST save in the request lists the changed columns
              #     in column order with `updated_at` LAST (the timestamp touch is
              #     the last mutation the tracker sees);
              #   * every LATER save lists them in the model's SCHEMA order
              #     (db/schema.rb), `updated_at` at its own position — after
              #     `changes_applied` the attribute set is the model's definition
              #     order: `updated_at` (col 17) precedes `last_seen` (28) and
              #     follows the trackable columns (11-15).
              # A5-1's "timestamp last" was the first-save half of this rule.
              if receiver.instance_variable_get(:@convidx_saved)
                order = ConversationsIndexTargets.schema_column_order(table)
                order = (klass.column_names rescue []) if order.empty?
                cols = (dirty.uniq + ["updated_at"]).uniq.sort_by { |c| order.index(c) || 1_000 }
              else
                order = (klass.column_names rescue [])
                cols = dirty.uniq.sort_by { |c| order.index(c) || 1_000 } + ["updated_at"]
                cols = cols.uniq
              end
              sets = cols.map { |c| %("#{c}" = ?) }.join(", ")
              note = %(UPDATE "#{table}" SET #{sets} WHERE "#{table}"."id" = #{ct.render_arg_value(receiver.concolic_attrs['id'])})
              # C-14 (round 5): a record saved TWICE in one request (trackable's
              # save, then lastseenable's) — AR's `changes_applied` clears the
              # dirty set after a successful save, so the second UPDATE carries
              # only the columns changed since. Without this the second note
              # re-emitted the first save's columns (measured: `SET
              # current_sign_in_at, …, sign_in_count, last_seen`).
              dirty.clear
              if receiver.respond_to?(:convidx_access)
                receiver.convidx_access << "updated_at" unless receiver.convidx_access.include?("updated_at")
              end
              receiver.instance_variable_set(:@convidx_saved, true)
            end
          rescue StandardError
            note = "#{receiver.class.name}##{m} (note render failed)"
          end
        end
        symbool("#{name}_#{m}_ok", true, note: note)
      end)
    end

    # §8a-bis. Gon::ControllerHelpers#gon — C-12 (adversary round 4). The SHARED
    # boundary (reports/diaspora/concolic_targets.rb:978-990) replaces `gon` with
    # a stub on the premise "gon is pure JS-var accumulation — nothing branchable,
    # no SQL". False once the REAL layout renders: `_head.haml include_gon`
    # serialises `Gon`'s variables, i.e. the UserPresenter that
    # `gon_set_current_user` pushed — seven statement shapes over four tables.
    # With the stub the push lands nowhere and the layout issued NONE of them
    # (services x0 in 149/149 smoke runs). Re-declared here with the gem's OWN
    # four-line body (gon-6.3.2 helpers.rb `def gon`), byte-faithful: register
    # the per-request store, return the module. Still a wall (no SQL of its own).
    # BOUNDARY CHANGE reported (Rule T3): the shared gon stub hides the layout's
    # reads on every batch that renders the real layout.
    if defined?(Gon::ControllerHelpers) && defined?(RequestStore)
      interceptor.declare_target(Gon::ControllerHelpers, :gon, returns: lambda do |receiver, _args, _name|
        if receiver.send(:wrong_gon_request?)
          gon_request = Gon::Request.new(receiver.request.env)
          gon_request.id = receiver.send(:gon_request_uuid)
          RequestStore.store[:gon] = gon_request
        end
        Gon
      end)
    end

    # §8b-bis. Base#update_attribute — C-10 (adversary round 4). The SHARED write
    # family (reports/diaspora/concolic_targets.rb:503) mocks `update_attribute`
    # with a body-skipping declaration note, so the ONE write the authentication
    # boundary performs — devise_lastseenable's `update_attribute(:last_seen, now)`
    # — was swallowed (Class S): 84/86 stale-principal smoke runs carried the
    # `update_attribute` event and NO statement. Rails' body is two steps —
    # `public_send("#{name}=", value); save(validate: false)` — so the faithful
    # mock performs exactly those through the rep's dirty-tracking writer and the
    # intercepted `save` target, which DERIVES the UPDATE (C-5): the statement is
    # the save's, this event is the delegation. BOUNDARY CHANGE reported (Rule T3):
    # the shared `update_attribute` / `update` / `touch` mocks swallow their
    # statement on every batch.
    interceptor.declare_target(ActiveRecord::Base, :update_attribute, returns: lambda do |receiver, args, name|
      sa = Array(args["splat_args"])
      aname = (args["name"] || sa.first).to_s
      # The interceptor hands positional args as `splat_args`, and its capture is
      # lossy for splat methods (targets.rb:236, a reported src/ gap): here it
      # keeps the attribute NAME and drops the VALUE (measured: keys
      # [splat_args, kwargs, block], value=NilClass). `update_attribute(name, v)`
      # is by construction a write of a NEW value — Rails writes iff it differs,
      # and its only caller on this endpoint (`stamp!`) calls it only when the
      # old value is stale — so when the value is LOST the write is marked
      # dirty explicitly rather than compared against nil (which read a real
      # write as NO-WRITE, 62/62 stale runs). When the value is present it goes
      # through the C-5 writer like any other write.
      value_lost = !args.key?("value") && sa.length < 2
      value = args.key?("value") ? args["value"] : sa[1]
      failed = nil
      begin
        if receiver.respond_to?(:concolic_attrs) && !aname.empty?
          if value_lost
            receiver.convidx_dirty << aname unless receiver.convidx_dirty.include?(aname)
            receiver.convidx_access << aname if receiver.respond_to?(:convidx_access) && !receiver.convidx_access.include?(aname) # materialised by this write (C-16 order)
          else
            receiver[aname] = value        # the dirty-tracking writer (C-5)
          end
          receiver.save(validate: false)   # the intercepted save target -> UPDATE or NO-WRITE
        end
      rescue StandardError => e
        failed = "#{e.class}: #{e.message[0, 120]}" # NEVER silent (B-6/B-8): a swallowed write is the defect this mock exists to fix
      end
      symbool("#{name}_update_attribute_ok", true,
              note: "#{receiver.class.name}#update_attribute(#{aname.inspect}) -> save (statement carried by the save event)#{failed ? " FAILED #{failed}" : ''}#{value_lost ? ' (value lost by the interceptor: write assumed)' : ''}")
    end)

    # §8c. Base#reload — a DECLARED TARGET (coordinator harvest B-1,
    # 2026-08-28; found by this batch: `self.class.unscoped { self.class
    # .find(id) }` is DATA ACCESS, so it is a target, never a shim).
    #   (a) ONE note, the single-row read, bind = the RECEIVER's id var:
    #       SELECT "<table>".* FROM "<table>" WHERE "<table>"."id" = $(<id var>) LIMIT 1
    #       (rendered through the batch's finder-note helper, never a literal);
    #   (b) returns the RECEIVER (real `reload` returns self) with the
    #       association cache cleared, as associations.rb reload does — the
    #       rep's attribute vars keep their identity, so downstream binds
    #       still name the same row;
    #   (c) not-found semantics match `find` (RecordNotFound). On THIS
    #       endpoint the only reload is Person#fix_profile's, reached after
    #       Discovery#fetch_and_save, which either saved the row or raised
    #       DiscoveryError (a 500) — a missing row here is not an app state,
    #       so it is PINNED FOUND with this ledger entry (pin ledger,
    #       AGENT_RUN.md); no decision is minted.
    interceptor.declare_target(ActiveRecord::Base, :reload, returns: lambda do |receiver, _args, _name|
      next receiver unless receiver.respond_to?(:concolic_attrs)
      t = receiver.class.table_name
      idv = receiver.concolic_attrs["id"]
      note = %(SELECT "#{t}".* FROM "#{t}" WHERE "#{t}"."id" = #{ct.render_arg_value(idv)} LIMIT 1)
      # ONE note, carried by THIS target's own event (B-1(a)). The interceptor
      # reads `#concolic_note` off the returned value, and `reload` returns the
      # receiver — whose note is the query that BUILT it, not this re-read — so
      # the reload statement is put on the rep for this boundary. No second
      # event is emitted (an extra load-probe note would double-count the read).
      receiver.define_singleton_method(:concolic_note) { note }
      receiver.instance_variable_set(:@convidx_reloaded, true)
      receiver.instance_variable_set(:@association_cache, {})
      receiver
    end)

    # §8d. Network-I/O wall — DECLARED TARGET (cycle 3, adversary A03: the
    # real Discovery#fetch_and_save aborts the JVM natively on this JRuby;
    # in the corpus the path RECORDS: Person#name -> fix_profile ->
    # fetch_and_save (wall) -> reload (§8c) -> profile pinned found).
    # The gem class is autoloaded — load it explicitly so `defined?` is true.
    begin
      require "diaspora_federation/discovery"
    rescue LoadError, StandardError => e
      warn "[conversations_index] diaspora_federation/discovery: #{e.class}"
    end
    if defined?(DiasporaFederation::Discovery::Discovery) &&
       DiasporaFederation::Discovery::Discovery.instance_methods.include?(:fetch_and_save)
      interceptor.declare_target(DiasporaFederation::Discovery::Discovery, :fetch_and_save,
                                 returns: ->(_r, _a, _n) { nil })
      # The gem's CONSTRUCTOR normalizes the handle (discovery.rb:43
      # clean_diaspora_id: strip/sub/downcase on the symbolic
      # diaspora_handle) before fetch_and_save is ever reached — the wall
      # must sit at the object boundary. Discovery.new -> an inert discovery
      # whose fetch_and_save is the no-op wall (no network, no app logic).
      inert = Class.new do
        def fetch_and_save
          nil
        end
      end
      # B-8: the inert discovery object carries no `#concolic_note`, so this
      # wall was one of the note-less targets. It issues NO SQL, so what it
      # publishes is the WALL string, not a statement — `statement_note_lint`
      # classifies it with the other documented walls (gon, render plumbing,
      # status=) and the audit stops counting it as a lost statement.
      interceptor.declare_target(DiasporaFederation::Discovery::Discovery.singleton_class, :new,
                                 returns: lambda do |_r, _a, _n|
                                   Thread.current[:concolic_pending_note] =
                                     "DiasporaFederation::Discovery::Discovery.new WALL " \
                                     "(network federation discovery; no SQL)"
                                   inert.new
                                 end)
      warn "[conversations_index] Discovery.new / #fetch_and_save walls declared"
    else
      warn "[conversations_index] WARNING: Discovery#fetch_and_save wall NOT declared"
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
      # cycle 6 (note_fidelity LIMIT-DIFF, the judge's new LIMIT/ORDER verdicts):
      # this alias IS `FinderMethods#first`, and Rails' `first` on an unordered
      # relation issues `... ORDER BY "users"."id" ASC LIMIT 1`
      # (finder_methods.rb ordered_relation + `limit(1)`). The note rendered the
      # bare relation, losing both — the same Rule T4 defect the batch had
      # already repaired for every OTHER finder via `finder_note`. Use that one
      # builder, so there is ONE definition of a single-row finder's statement.
      # R6-NM-3: a session/cookie naming a principal that no longer exists —
      # `serialize_from_session` / `serialize_from_cookie` -> `to_adapter.get`
      # -> the users read returns nothing -> Devise fails the request (401 after
      # ONE read, no write). The finder's own not-found arm, minted like every
      # other finder's (B-8: the statement is still published).
      nf_sql = ConversationsIndexTargets.finder_note(ct, receiver, args, :first)
      nf_name = "#{name}_not_found"
      if symbool(nf_name, ct.seed_for(nf_name, false), note: nf_sql) == true
        next ConversationsIndexTargets.publish_note(nf_sql)
      end
      u = ct.symbolic_instance(ct.model_class(receiver), name, nf_sql)
      if u.respond_to?(:define_singleton_method)
        u.define_singleton_method(:persisted?)  { true }
        u.define_singleton_method(:new_record?) { false }
        # C-10 / T-x (adversary round 4) — THE AUTHENTICATION BOUNDARY WRITES.
        # With the REAL Warden::Proxy (run_dse.rb, INSTR-9) `after_set_user` runs
        # devise_lastseenable's `stamp!`: `update_attribute(:last_seen, now) if
        # last_seen.to_i < (now - 5.minutes).to_i` — an UPDATE "users" on every
        # signed-in request whose last_seen is NULL or > 5 min old, BEFORE
        # set_locale. `users.last_seen` is a column the corpus never read; it is
        # ONE decision (Rule D: the write is DERIVED from it by the real hook and
        # the C-5 dirty tracker), recorded here with the principal's own SELECT.
        note = (u.concolic_note rescue nil)
        stale_v = "#{name}_last_seen_stale"
        stale = (symbool(stale_v, ct.seed_for(stale_v, true), note: note) == true)
        u.define_singleton_method(:last_seen) { stale ? nil : Time.now.utc }
        # C-11 — a LOCKED principal (`users.locked_at`, lock/unlock strategy
        # :none => `access_locked?` is `!!locked_at`): Devise's activatable hook
        # logs it out (`before_logout` -> forgetable -> `forget_me!`, a save whose
        # write C-5 derives from `remember_created_at`) and `throw :warden` 401.
        locked_v = "#{name}_locked"
        locked = (symbool(locked_v, ct.seed_for(locked_v, false), note: note) == true)
        u.define_singleton_method(:locked_at) { locked ? Time.now.utc : nil }
        # C-11's write is DERIVED (C-5): `forget_me!` sets remember_created_at
        # to nil and saves — an UPDATE only if it WAS set. A nullable column with
        # no app-side invariant on this endpoint: one decision, the write follows.
        # R5-NM-1: `_remembered` was minted EAGERLY and so recorded on every
        # fetch-path dump although nothing there reads it (a phantom). It is a
        # decision only where `remember_created_at` is READ — `forget_me!` on
        # the locked path (C-11) and `remember_me?` on the remember-cookie login
        # (C-14) — so it is minted LAZILY on the first read, memoised (Rule D).
        rem_v = "#{name}_remembered"
        rem_memo = {}
        u.define_singleton_method(:remember_created_at) do
          unless rem_memo.key?(:v)
            # a REMEMBERED record was remembered in the PAST: `remember_me?` requires
            # the cookie's generated_at to be LATER than remember_created_at
            # (models/rememberable.rb:118); minted at "now" it rejected every
            # valid cookie (2/2 remembered cookie logins threw :warden).
            rem_memo[:v] = (symbool(rem_v, ct.seed_for(rem_v, false), note: note) == true) ? (Time.now.utc - 3600) : nil
            concolic_attrs["remember_created_at"] = rem_memo[:v] if respond_to?(:concolic_attrs)
          end
          rem_memo[:v]
        end
        # C-14: trackable's `update_tracked_fields` does `sign_in_count += 1` —
        # arithmetic a SymbolicInt refuses by design. The count keeps its symbolic
        # identity as a ConcolicIntValue (the batch's count precedent), so the
        # write goes through the C-5 dirty writer like every other column.
        if defined?(ConcolicIntValue) && u.respond_to?(:concolic_attrs) && u.concolic_attrs["sign_in_count"].respond_to?(:sym_name)
          sc = u.concolic_attrs["sign_in_count"]
          civ = ConcolicIntValue.new(sc.value, name: sc.sym_name, note: note)
          u.concolic_attrs["sign_in_count"] = civ
          u.define_singleton_method(:sign_in_count) { concolic_attrs["sign_in_count"] }
        end
        # C-12: `_drawer.mobile.haml:33 user_profile_path(current_user.username)` —
        # a ROUTE helper on the principal's username (display/URL only; no
        # statement, no access decision): the `text`/`guid`/`name` treatment,
        # PINNED (pin ledger: `username`).
        if defined?(ConcreteSymbolicString) && u.respond_to?(:concolic_attrs)
          un = ConcreteSymbolicString.build("concolicuser", name: "#{name}_username", note: note)
          u.concolic_attrs["username"] = un
          u.define_singleton_method(:username) { un }
        end
        if u.respond_to?(:concolic_attrs)
          u.concolic_attrs["last_seen"] = (stale ? nil : Time.now.utc)
          # C-14: trackable's `last_sign_in_at = current_sign_in_at || now` casts
          # the OLD value through the datetime type; a symbolic placeholder does
          # not cast (-> nil, no write), so the first-login UPDATE lost
          # `last_sign_in_at` (measured: 5 columns, real: 6). The previous
          # sign-in timestamps are real past Times: no access decision reads
          # them, they only ride along in the SET list.
          pf_v = "#{name}_prev_login_first"; pf_memo = {}
          u.concolic_attrs["current_sign_in_at"] = Time.now.utc - 86_400
          u.concolic_attrs["last_sign_in_at"]    = Time.now.utc - 172_800
          # trackable WRITES last_sign_in_at without reading it (`self.last_sign_in_at
          # = old_current || new_current`), so the decision must be taken where the
          # fact is consumed: the READ of current_sign_in_at that precedes the write
          # (cookie path only). Set the stored last_sign_in_at from it, so the C-5
          # writer's compare sees the real state.
          u.define_singleton_method(:current_sign_in_at) do
            unless pf_memo.key?(:v)
              pf_memo[:v] = (symbool(pf_v, ct.seed_for(pf_v, false), note: note) == true)
              if pf_memo[:v]
                # C-17 (adversary round 6): only the TIMESTAMP equality is what A
                # means. `users.current_sign_in_at` is a second-precision DATETIME
                # on the app's MySQL schema, so two logins in the same stored
                # second from two addresses leave the timestamps equal and the IPs
                # DIFFERENT — B (`last_sign_in_ip == current_sign_in_ip`) is a fact
                # of its own, compared by the C-5 writer, never derived from A.
                concolic_attrs["last_sign_in_at"] = concolic_attrs["current_sign_in_at"]
              end
            end
            concolic_attrs["current_sign_in_at"]
          end
          # A5-7: trackable's `last_sign_in_at = old current` is a NO-OP write
          # when the two already coincide — true after a FIRST-EVER login
          # (`last := old current || now` makes them equal). Whether the previous
          # login was the first is a real column state the request cannot
          # observe otherwise: one decision, minted lazily where trackable
          # reads it (the cookie path only), driving the SET list (the real
          # second-login shape `sign_in_count, current_sign_in_at, updated_at`).
          u.define_singleton_method(:last_sign_in_at) { concolic_attrs["last_sign_in_at"] }
          u.concolic_attrs["locked_at"] = (locked ? Time.now.utc : nil)
        end
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
