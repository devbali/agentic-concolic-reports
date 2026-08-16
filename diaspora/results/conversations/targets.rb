# frozen_string_literal: true
#
# Per-batch concolic targets — `conversations`.
#
# Installs AFTER `ConcolicTargets.install!`. `declare_target` uses
# `define_method`, so a later declaration REPLACES an earlier one:
#
#   ConcolicTargets.install!(interceptor)        # shared generic AR interception
#   ConversationsTargets.install!(interceptor)   # this file — batch-local wall fixes
#
# Nothing here edits src/, the shared concolic_targets.rb, or the app source.
#
# ---------------------------------------------------------------------------
# THE WALLS THIS BATCH HIT (2026-08-14 run) AND WHAT IS DONE ABOUT EACH
# ---------------------------------------------------------------------------
#  W1  NotImplementedError: Calculations#pluck            8 dumps  -> FIXED (§2)
#      `conversations#create` was VACUOUS (0 PCs) and `conversations#index`
#      truncated before `respond_with`, both solely because of this.
#  W2  NotImplementedError: SymbolicList#map/#to_a         (behind W1)
#      contacts_data pluck(...).map{...}; index-json @visibilities.map(&:conversation)
#                                                            -> FIXED (§1, sampled)
#  W3  NotImplementedError: SymbolicList#[] index 0 only   3 dumps -> FIXED (§1a)
#      Conversation#first_unread_message -> messages.to_a[-visibility.unread]
#      Closed for index -1 ONLY, which is provably `#last` and is the only
#      index the DSE frontier ever demands here (see §1a).
#  W4  NotImplementedError: SymbolicString#strip / #scrub  (surfaced by W1's
#      fix, inside Person.name_from_attrs / ERB::Util.h)    -> FIXED (§1c)
#  W5  NotImplementedError: SymbolicInt#to_i               (surfaced by W1's
#      fix, inside AR ids_writer's type cast)               -> FIXED (§1d),
#      but it buys ZERO path conditions — see the report.
#
# Every fix is a SUBCLASS of the runtime's own symbolic class returned from a
# batch-local mock. src/ is untouched; no other batch is affected.
# ---------------------------------------------------------------------------

module ConversationsTargets
  # =========================================================================
  # 1. SampledList — batch-local SymbolicList subclass.
  #
  # Same symbolic length + single representative row as Gate 1b. It adds two
  # things, both strictly inside the sampled-content approximation the runtime
  # already commits to, and NEITHER of which removes a path condition:
  #
  #  (a) `[-1]`.  src/ruby_runtime/list.rb:134 models only `[0]`, but it ALSO
  #      models `#last` (list.rb:120) as "return the representative". `x[-1]`
  #      and `x.last` denote the SAME element, so honouring index -1 grants no
  #      capability the runtime does not already grant under a different name.
  #      It is not the case the honesty guard is protecting against — that is
  #      "a block that needs the SECOND row", i.e. |i| > 1, which still raises.
  #
  #      This is exactly what `Conversation#first_unread_message` needs:
  #        messages.to_a[-visibility.unread]
  #      The visibility comes from `.where('unread > 0').first`, so in
  #      PRODUCTION `unread >= 1` always and the index is always negative —
  #      the only path src/ can execute today (index 0) is the one that
  #      cannot happen. DSE flips `((- unread) == 0)` to unread = 1, i.e.
  #      `[-1]`, so -1 support is precisely the flip that was walling.
  #
  #      The `(idx == 0)` comparison is kept FIRST and unchanged so the
  #      existing `((- VAR) == 0)` path condition is still recorded; the -1
  #      test reads the SymbolicInt's concrete `.value` and deliberately
  #      records nothing (a second PC there would be a runtime-internal
  #      comparison, not an app branch).
  #
  #  (b) sampled iteration (`each`/`map`/`to_a`).  src/ leaves these
  #      unimplemented with the note "iteration is handled by caller-wrapping
  #      at the mocked boundary" (list.rb:15) — but no such wrapping exists for
  #      AR relations, so `relation.map { }` is an unconditional wall. Here the
  #      mocked boundary does the wrapping: iterate the ONE representative row,
  #      exactly `concrete_length.zero? ? 0 : 1` times, so the iteration agrees
  #      with the seeded length instead of contradicting it.
  #
  #      HONEST LIMIT: the iteration COUNT is concretized to 0-or-1. Any app
  #      branch that depends on seeing two DIFFERENT rows is not modeled. No
  #      such branch exists in this batch's map blocks (contacts_data's block
  #      and `map(&:conversation)` are both branch-free projections), and
  #      `empty?`/`any?`/`length` stay symbolic, so `person_ids.present?` — the
  #      branch that matters here — is still a real recorded PC.
  # =========================================================================
  class SampledList < SymbolicList
    def [](*args)
      return super unless @representative && args.length == 1

      idx = args[0]
      # Unchanged src/ semantics: records ((- VAR) == 0) when idx is symbolic.
      return @representative if idx == 0

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
  end

  # =========================================================================
  # 1c. SampledString — batch-local SymbolicString subclass.
  #
  # `SymbolicString` is a real `::String` subclass (string.rb:60 calls
  # `super(concrete)`), so the native implementations are all still there
  # behind the UNSUPPORTED stubs (string.rb:335-358). Two of those stubs wall
  # `conversations#index` once §2 lets it reach `contacts_data`:
  #
  #   Person.name_from_attrs  ->  "#{first_name.to_s.strip} ..."   -> #strip
  #   ERB::Util.h(...)        ->  html-escape of a symbolic handle -> #scrub
  #
  # Both are WHITESPACE/ENCODING NORMALISERS, not content queries: on a value
  # that is already trimmed and already valid UTF-8 they are the identity. So
  # compute the native result and, when it equals the concrete value (always,
  # for the seeds this batch produces), return SELF — tracking survives intact
  # and nothing is concretized. Only if a seed genuinely had surrounding
  # whitespace or invalid bytes would a new node be minted, and the
  # approximation `strip(X) ~ X` be visible.
  #
  # No branch is swallowed: neither method's result is ever compared. The two
  # PCs in `name_from_attrs` come from `first_name.blank?` / `last_name.blank?`
  # (SymbolicString#empty?, string.rb:208), which run BEFORE the strip and are
  # untouched — they are new genuine branches this fix exposes, not ones it
  # hides.
  # =========================================================================
  class SampledString < SymbolicString
    # `SymbolicString` is a ::String subclass and JRuby runs Ruby 2.6
    # semantics, where String#strip & co. return an instance of the RECEIVER's
    # class built by allocate+copy — i.e. a SampledString with @value still
    # nil, which then blows up as `TypeError: no implicit conversion of nil
    # into String` the moment it is re-wrapped. Rebinding the native #to_s
    # (documented to convert a String subclass to a plain String) flattens it
    # back to real bytes before any comparison or re-wrap.
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

  # =========================================================================
  # 1d. CastableInt — batch-local SymbolicInt subclass adding #to_i.
  #
  # `conversations#create` does
  #   c.participant_ids = [*person_ids] | [self.person_id]
  # and ActiveRecord's `ids_writer` type-casts each id
  # (`ActiveModel::Type::Integer#cast_value` -> `value.to_i`). src/ deliberately
  # raises there (int.rb:29) because `to_i`/`to_int` are silent-concretization
  # channels.
  #
  # This subclass restores `to_i` ONLY (never `to_int`, the implicit-coercion
  # channel that would let `Array#[]` and friends concretize behind your back).
  # The concretization is real and is stated plainly in the report: the id that
  # reaches `Person.where(id: ...)` is the seed, not a symbol. It costs no path
  # condition — nothing downstream of `build_conversation` compares it, and the
  # only branch left in `create` is `if @conversation.save`, which is the
  # documented Ruby truthiness gap and records nothing either way.
  # =========================================================================
  class CastableInt < SymbolicInt
    def to_i
      value
    end
  end

  # =========================================================================
  # 1b. PluckArgs — recover pluck's real column list.
  #
  # A mock lambda receives `call_args`, which `CallInterceptor` builds by
  # zipping the ORIGINAL method's `parameters` against the actual arguments
  # (call_interceptor.rb:115-125). For a splat method such as
  # `pluck(*column_names)` that captures only the FIRST column, and once a
  # target has been declared the "original" is itself the interceptor's
  # `|*splat_args, **kwargs, &block|` wrapper — so a 4-column pluck is dumped
  # as `{"splat_args"=>"contacts.id", "kwargs"=>"profiles.first_name",
  # "block"=>"profiles.last_name"}`, which is not just lossy but mislabelled.
  # (Reported as a src/ gap; NOT patched.)
  #
  # pluck's return SHAPE depends on its arity (1 column -> scalar rows, N
  # columns -> N-element array rows), so the arity has to come from somewhere.
  # This prepended module reads it off the real call and hands it to the mock
  # through a thread-local. Prepended to Relation (the class that actually
  # receives `.pluck`) so it runs BEFORE the interceptor's definition on the
  # included Calculations module, then `super`s straight into it — the mock
  # still runs, nothing is bypassed, no query is hidden.
  # =========================================================================
  module PluckArgs
    def pluck(*column_names)
      prev = Thread.current[:conv_pluck_cols]
      Thread.current[:conv_pluck_cols] = column_names.flatten.map(&:to_s)
      super
    ensure
      Thread.current[:conv_pluck_cols] = prev
    end
  end

  module_function

  # Column -> symbolic scalar of the right sort, seeded through seed_for so
  # DSE can actually flip it (the addendum's "missing seed_for makes the var
  # permanently inert" trap).
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
      CastableInt.new(ConcolicTargets.seed_for(var, 1), name: var, note: note)
    when :boolean
      symbool(var, ConcolicTargets.seed_for(var, false), note: note)
    else
      SampledString.new(ConcolicTargets.seed_for(var, "sym_#{bare}"), name: var, note: note)
    end
  end

  def install!(interceptor = CallInterceptor.instance)
    ct   = ConcolicTargets
    calc = ActiveRecord::Calculations
    rel  = ActiveRecord::Relation

    # =======================================================================
    # 2. Calculations#pluck -> length-only SampledList with a representative.
    #
    # Shared file declares pluck UNSUPPORTED (concolic_targets.rb:469, §D
    # "contents ops raise"). That is the right default for `average`/`minimum`/
    # `calculate`, whose VALUES are aggregates over contents. `pluck` is a
    # different animal: it IS the query boundary — it fires the SELECT and
    # returns rows — which is the exact role `records`/`to_a` already play and
    # which §C already models as "symbolic length + one representative row".
    # So this is not an extra hole in the contents policy, it is the existing
    # collection-materialization mock applied to the method that materializes.
    #
    # Shape mirrors §C exactly: `len(<name>_plucked)` seeded to 1, note = the
    # rendered SQL, plus a representative that is symbolic (never a concrete
    # scalar — a concrete `[2]` would make `present?` silently concrete and
    # destroy the very branch this fix exists to expose).
    #
    #   pluck(:person_id)              -> rep is a SymbolicInt
    #   pluck("contacts.id", "profiles.first_name", ...)
    #                                  -> rep is an ARRAY of one symbolic value
    #                                     per selected column, so the caller's
    #                                     `|contact_id, *name_attrs|`
    #                                     destructuring works
    #
    # Unlocks:
    #   conversations#create  `person_ids.present?` -> Object#blank?
    #                         -> SymbolicList#empty? -> (len != 0)   [both sides]
    #   conversations#index   contacts_data, so execution reaches respond_with
    # =======================================================================
    rel.prepend(PluckArgs) unless rel < PluckArgs

    interceptor.declare_target(calc, :pluck, returns: lambda do |receiver, args, name|
      note = ct.sql_for(receiver, args)
      vn   = "#{name}_plucked"
      cols = Thread.current[:conv_pluck_cols] || []
      cols = ["value"] if cols.empty?
      vals = cols.each_with_index.map do |c, i|
        var = cols.size == 1 ? "#{name}_pluck_#{c.split('.').last}" : "#{name}_pluck#{i}_#{c.split('.').last}"
        ConversationsTargets.sym_for_column(receiver, c, var, note)
      end
      rep = cols.size == 1 ? vals.first : vals
      SampledList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: note, representative: rep)
    end)

    # =======================================================================
    # 3. Collection materialization -> SampledList (identical to shared §C in
    #    every observable way except that the list is iterable and accepts
    #    index -1). Needed because the two remaining walls sit on lists the
    #    SHARED mock produced:
    #      Conversation#first_unread_message  messages.to_a[-unread]
    #      conversations#index (json)         @visibilities.map(&:conversation)
    #    Same var names, same seeds, same notes -> path signatures from the
    #    previous round stay comparable.
    # =======================================================================
    %i[to_a to_ary records].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        vn   = "#{name}_rows"
        note = ct.sql_for(receiver, args)
        rep  = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", note)
        SampledList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: note, representative: rep)
      end)
    end

    # =======================================================================
    # 4. DELIBERATELY NOT MOCKED
    #
    # ConversationsController#contacts_data — its body issues the query
    # itself, so it is not a SQL-free leaf; mocking it would hide a real
    # SELECT. With §2 in place it no longer needs mocking.
    #
    # Conversation#first_unread_message — its body IS the branch
    # (`if visibility = ...where('unread > 0').first`) and it issues SQL.
    # Mocking it would swallow the only unread/read distinction this batch has.
    #
    # Conversation#set_read / #local_recipients — same reason (both branch,
    # both query).
    # =======================================================================

    # =======================================================================
    # 5. Asset-path stub — ENVIRONMENT wall, not a symbolic-runtime one.
    #
    # Now that index reaches respond_with it actually RENDERS, which pulls
    # AvatarPresenter. That class's BODY calls
    # `ActionController::Base.helpers.image_path("user/default.png")` ->
    # Sprockets -> manifest.js, and the minimal rig has no compiled assets, so
    # it raises WHILE THE CLASS BODY IS EXECUTING and leaves the class
    # half-defined — every LATER run in the same process then dies with a
    # misleading `NoMethodError: base_hash`. Stubbing a pure display-URL
    # builder keeps the rig deterministic. Same fix as photos §5 / people.
    # =======================================================================
    begin
      h = ActionController::Base.helpers
      h.define_singleton_method(:image_path)    { |src, *| "/concolic/assets/#{src}" }
      h.define_singleton_method(:path_to_image) { |src, *| "/concolic/assets/#{src}" }
      require "app/presenters/avatar_presenter" if defined?(Rails)
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn "[conversations] asset stub: #{e.class}: #{e.message.to_s[0, 80]}"
    end

    warn "[conversations] ConversationsTargets installed"
  end
end
