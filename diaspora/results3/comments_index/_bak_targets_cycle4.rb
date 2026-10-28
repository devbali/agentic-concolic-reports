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
  # D8 (adversary round 2, 2026-08-28): the preload now ATTACHES the loaded
  # association target to the owner rep, so the app's later `comment.author` /
  # `author.profile` read hits AR's association CACHE and never reaches
  # `find_target` — exactly what real AR does after `includes(author: :profile)`
  # (verified across A01/A02/A03/A06/A10: the only real find_target on this
  # endpoint is `User has_one :person`). Before this, 13 626 dumps emitted BOTH
  # the bulk preload note and a per-row find_target note with the identical
  # bind: the same read counted twice, and a second producer edge for the fold.
  #
  # The decisions the preload can express are KEPT, not dropped: a has_one step
  # mints `<child>_not_found` (a person with no profiles row is a real state —
  # the FK runs profiles -> people, schema.rb:643, not people -> profiles), and
  # attaches nil on that side, which is what the real Preloader leaves behind.
  def mark_loaded(owner_rep, name, target)
    a = owner_rep.association(name)
    a.target = target
    a.loaded!
    true
  rescue StandardError
    nil
  end

  def emit_includes_preloads(ct, receiver, rep)
    iv = receiver.respond_to?(:includes_values) ? Array(receiver.includes_values) : []
    return if iv.empty?
    owner_klass = ct.model_class(receiver)
    emit = nil
    emit = lambda do |owner_rep, klass, spec|
      return if owner_rep.nil?
      pairs = spec.is_a?(Hash) ? spec.to_a : [[spec, nil]]
      pairs.each do |aname, nested|
        r2 = (klass.reflect_on_association(aname.to_sym) rescue nil)
        next unless r2 && !r2.polymorphic?
        attrs = owner_rep.respond_to?(:concolic_attrs) ? owner_rep.concolic_attrs : {}
        base  = ct.assoc_base_name(owner_rep, r2.name)
        if r2.belongs_to?
          bindv = attrs[r2.foreign_key.to_s]
          next if bindv.nil?
          col = (r2.association_primary_key(r2.klass) rescue "id")
          psql = %(SELECT "#{r2.table_name}".* FROM "#{r2.table_name}" WHERE "#{r2.table_name}"."#{col}" IN (#{ct.render_arg_value(bindv)}))
        else
          bindv = attrs["id"]
          next if bindv.nil?
          thr = (r2.respond_to?(:through_reflection) && r2.through_reflection) || nil
          t   = thr || r2
          psql = %(SELECT "#{t.table_name}".* FROM "#{t.table_name}" WHERE "#{t.table_name}"."#{t.foreign_key}" IN (#{ct.render_arg_value(bindv)}))
        end
        ConcolicThroughLoadProbe.load_intermediate(psql)
        child = nil
        if r2.belongs_to? || r2.macro == :has_one
          if r2.macro == :has_one
            nf = "#{base}_not_found"
            child = (symbool(nf, ct.seed_for(nf, false), note: psql) == true) ? nil : ct.symbolic_instance(r2.klass, base, psql)
          else
            child = ct.symbolic_instance(r2.klass, base, psql)
          end
          mark_loaded(owner_rep, r2.name, child)
        end
        emit.call(child, r2.klass, nested) if nested && child
      end
    end
    iv.each { |spec| emit.call(rep, owner_klass, spec) }
  rescue StandardError
    nil # note-side extra must never crash the mock (M-family rule)
  end

  # cycle 3: concrete-text -> symbolic-var map (per run; run_dse.rb resets).
  # A comment's text is a concrete String (the scan/gsub pipes need one) but
  # the values the app extracts from it and feeds into queries (a mention
  # handle, a diaspora-link guid) are symbolic vars whose concrete value is
  # embedded in the text; the query boundary maps the extracted String back
  # to its var so the note binds `$$(var)`.
  def text_binds
    Thread.current[:comments_text_binds] ||= {}
  end

  def reset_text_binds!
    Thread.current[:comments_text_binds] = {}
  end

  def rebind_text_values(obj)
    case obj
    when Hash then obj.each_with_object({}) { |(k, v), h| h[k] = rebind_text_values(v) }
    when Array then obj.map { |v| rebind_text_values(v) }
    when String
      sv = text_binds[obj] || text_binds[obj.strip.downcase]
      sv || obj
    else obj
    end
  end

  # `exists?` statement (finder_methods.rb exists?): the relation with
  # select/distinct/order stripped, `SELECT 1 AS one`, `LIMIT 1`.
  def exists_sql_for(ct, receiver, args)
    sql = ct.sql_for(receiver, args)
    sql = sql.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT 1 AS one FROM ")
    sql = sql.sub(/\s+ORDER BY\s.*\z/m, "")
    sql =~ /\sLIMIT\s/ ? sql : "#{sql} LIMIT 1"
  rescue StandardError
    sql
  end

  # Faithful single-row finder statement (adversary N7; CHECKS.md F7):
  # Rails' `first`/`last` order by the primary key when the relation has no
  # order, and every single-row finder appends LIMIT 1.
  def finder_note(ct, receiver, args, kind)
    sql = ct.sql_for(receiver, args)
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
    sql
  end

  # Shared finder_mock with the faithful note (same decision, same return).
  def finder_mock_faithful(ct, raise_on_missing:, kind:)
    lambda do |receiver, args, name|
      sql = CommentsTargets.finder_note(ct, receiver, args, kind)
      nf_name = "#{name}_not_found"
      not_found = symbool(nf_name, ct.seed_for(nf_name, false), note: sql)
      if not_found == true
        raise ActiveRecord::RecordNotFound, "concolic: empty result for: #{sql}" if raise_on_missing
        next nil
      end
      ct.symbolic_instance(ct.model_class(receiver), name, sql)
    end
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
          # D9: `BasePresenter.as_collection` (base_presenter.rb:14) reaches the
          # list through Enumerable#map, which iterates with `each` — so the
          # collection-length decision has to be recorded HERE as well as in
          # #map, or the json variants carry none at all (which is exactly what
          # the adversary found). Same canonical expr the runtime's
          # `any?`/`none?` record (list.rb:163-172).
          nonempty = concrete_length != 0
          record!("(#{@symbolic_len} != 0)", "each", taken: nonempty)
          yield @representative if @representative && nonempty
          self
        end

        def map
          return to_enum(:map) unless block_given?
          # D9 (adversary round 2, 2026-08-28): the JSON path materializes
          # through `Array#map` (BasePresenter.as_collection), which never
          # compares the length — so the json variants carried NO
          # collection-length decision while the mobile ones did (H4 held for
          # half the corpus). The empty-list state is a real, data-dependent
          # outcome (a `[]` body issuing only the post finder and the comments
          # SELECT), so `map` records the SAME canonical compare `any?`/`none?`
          # record in the runtime (list.rb:163-172) — the decision, not new
          # modelling.
          nonempty = concrete_length != 0
          record!("(#{@symbolic_len} != 0)", "map", taken: nonempty)
          @representative && nonempty ? [yield(@representative)] : []
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
          # cycle 3 (adversary N2, return-kind fidelity): a preload step
          # returns a ROW LIST, not a count. Length-only sampled list (no
          # representative — the preloaded rows are reached through the
          # owner's association readers, which mint their own reps).
          IterableSymbolicList.new(ConcolicTargets.seed_for("len(#{name}_rows)", 1),
                                   name: "#{name}_rows", note: args["sql"].to_s, representative: nil)
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
          isql = %(SELECT "#{tr.table_name}".* FROM "#{tr.table_name}" WHERE "#{tr.table_name}"."#{tr.foreign_key}" IN (#{ct.render_arg_value(oid)}))
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
          # cycle 3 (ADVERSARY_REPORT W1 + N5): the text-content decision
          # family, COMMENT reps only (a Post's text is never read on this
          # endpoint — the post reps' flags were pure untracked noise).
          #   _text_has_mention  -> "@{Name; <handle>}" markup; the handle is a
          #                         SYMBOLIC var whose concrete value is embedded
          #                         in the text and mapped back at the finder
          #                         boundary (text_binds), so the people-by-handle
          #                         lookup binds `$$(<rep>_text_mention_handle)`
          #                         instead of a literal pin (N5).
          #   _text_has_dlink    -> a `diaspora://<handle>/<entity>/<guid>` link
          #                         (DiasporaUrlParser::DIASPORA_URL_REGEX):
          #                         MessageRenderer#diaspora_links then runs
          #                         for real, and on the "post" entity issues
          #                         Post.exists?(guid:) — the existence probe
          #                         the corpus lacked (W1). The guid is likewise
          #                         a symbolic var mapped back at exists?.
          #   _text_dlink_is_post-> the link's entity is "post" (exists? fires)
          #                         vs "comment" (`Regexp.last_match(2) == "post"`
          #                         false — no query). Recorded at the shim
          #                         boundary because the renderer's compare is
          #                         on a concrete String.
          if attrs.key?("text") && klass.name == "Comment"
            hm_name = "#{base_name}_text_has_mention"
            has_mention = symbool(hm_name, seed_for(hm_name, false), note: sql)
            dl_name = "#{base_name}_text_has_dlink"
            has_dlink = symbool(dl_name, seed_for(dl_name, false), note: sql)
            parts = ["hello world, a concolic message"]
            if has_mention == true
              # FREE VALUE, not a row column (bind_resolution RED, 2026-08-28):
              # a handle parsed out of the comment's TEXT has no producer
              # column, so a `$$()` bind carrying a SELECT note is
              # UNRESOLVABLE to the fold and the people-by-handle query would
              # become a placeholder view at extraction. It is a free value of
              # the policy — the same category as a request parameter — so it
              # is minted in the SYM_PARAM_* family with a NON-SQL note, which
              # the fold classifies `param/leaf` and renders as a parameter
              # placeholder. (No PC anywhere references this var, so the name
              # change touches no decision.)
              hv = "SYM_PARAM_mention_handle_#{base_name.sub('SYM_RESULT_ActiveRecord__', '')}"
              handle = symstr(hv, seed_for(hv, "concolic_mention@example.org"),
                              note: "free value: diaspora handle parsed out of the comment text " \
                                    "(policy parameter; no producer column)")
              CommentsTargets.text_binds[handle.value.to_s.strip.downcase] = handle
              parts << "@{Concolic Mention; #{handle.value}}"
            end
            if has_dlink == true
              # D6 (adversary round 2, 2026-08-28): CARDINALITY. A real
              # link-bearing comment issues ONE `Post.exists?(guid:)` per
              # `post`-entity link (A01: three links -> three probes per
              # render); the corpus capped at ONE per run. The text now carries
              # THREE post links, each with its own free-value guid parameter,
              # plus a `comment`-entity link — the entity compare
              # (`Regexp.last_match(2) == "post"`, message_renderer.rb:121) is
              # what makes that one issue no query, and it stays a recorded
              # decision on the first link.
              ip_name = "#{base_name}_text_dlink_is_post"
              is_post = symbool(ip_name, seed_for(ip_name, true), note: sql)
              short = base_name.sub("SYM_RESULT_ActiveRecord__", "")
              3.times do |k|
                gv = "SYM_PARAM_dlink_guid#{k}_#{short}"
                guid = symstr(gv, seed_for(gv, "concolicguid000000000#{k}"),
                              note: "free value: diaspora:// link guid parsed out of the comment text " \
                                    "(policy parameter; no producer column)")
                CommentsTargets.text_binds[guid.value.to_s] = guid
                entity = (k.zero? && is_post != true) ? "comment" : "post"
                parts << "diaspora://concolic_link@example.org/#{entity}/#{guid.value}"
              end
              cgv = "SYM_PARAM_dlink_comment_guid_#{short}"
              cguid = symstr(cgv, seed_for(cgv, "concolicguid0000000009"),
                             note: "free value: diaspora:// link guid parsed out of the comment text " \
                                   "(policy parameter; no producer column)")
              CommentsTargets.text_binds[cguid.value.to_s] = cguid
              parts << "diaspora://concolic_link@example.org/comment/#{cguid.value}"
            end
            parts << "welcome"
            attrs["text"] = parts.join(" ")
          end
          next_obj
        end
      end
    end

    # (b) network-I/O wall: SUPERSEDED by §8e (cycle 3) — the wall now sits
    #     at `Discovery.new` and `fetch_and_save` is a declared target with
    #     the real return kind (Person or DiscoveryError).

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

    # =====================================================================
    # 8. cycle 3 (2026-08-27, ADVERSARY_REPORT.md) — W1/W2 + fidelity repairs
    # =====================================================================
    fm = ActiveRecord::FinderMethods

    # 8a. Faithful single-row finder notes (N7): ORDER BY pk + LIMIT 1.
    %i[first last take find_by].each do |m|
      interceptor.declare_target(fm, m, returns: finder_mock_faithful(ct, raise_on_missing: false, kind: m))
    end

    # 8b. W1 — `FinderMethods#exists?` as the existence-probe target
    # (TARGET_FUNCTIONS §1 "existence"): note = `SELECT 1 AS one … LIMIT 1`
    # (never `posts.*`), the guid extracted from the comment text mapped back
    # to its symbolic var. `if Post.exists?(...)` is bare truthiness (no PC
    # on the caller's side), so the mock does the explicit compare itself
    # and returns the CONCRETE bool — the decision `<name>_exists` is recorded
    # at the boundary, both polarities explored by DSE.
    # The existence decision is minted through a dedicated probe target so
    # the EVENT carries the statement note (a bare Ruby bool — which the app's
    # `if Post.exists?` needs — carries no note); the var keeps the exists?
    # call's own name. concrete_aliases.json maps the real exists? frame to
    # the probe's event name.
    unless defined?(::ConcolicExistsProbe)
      ::Object.const_set(:ConcolicExistsProbe, Module.new do
        def self.exists_probe(sql, vn)
          [sql, vn]
        end
      end)
      interceptor.declare_target(::ConcolicExistsProbe.singleton_class, :exists_probe,
                                 returns: lambda do |_r, args, _n|
                                   symbool(args["vn"].to_s, ct.seed_for(args["vn"].to_s, false), note: args["sql"].to_s)
                                 end)
    end
    interceptor.declare_target(fm, :exists?, returns: lambda do |receiver, args, name|
      # keyword conditions reach sql_for through the ConcolicKwargsToPositional
      # thread-local (the interceptor drops **kwargs) — rebind those too.
      prev = Thread.current[:concolic_finder_conds]
      begin
        Thread.current[:concolic_finder_conds] = CommentsTargets.rebind_text_values(prev) if prev
        note = CommentsTargets.exists_sql_for(ct, receiver, CommentsTargets.rebind_text_values(args))
      ensure
        Thread.current[:concolic_finder_conds] = prev
      end
      ex = ::ConcolicExistsProbe.exists_probe(note, "#{name}_exists")
      ex == true
    end)

    # 8c. SingularAssociation#find_target — batch redeclaration of the shared
    # W3 mock: (a) `LIMIT 1` (the real load is `… LIMIT ?`); (b) has_one loads
    # carry a `<base>_not_found` DECISION — `profiles.person_id` has no FK and
    # nothing forces a profile row to exist (adversary "Unreachable": the
    # FACT CORRECTION (adversary round 2, D9): schema.rb:643 DOES carry
    # `add_foreign_key "profiles", "people"` — it constrains profiles -> people,
    # NOT people -> profiles, so nothing forces a profiles row to exist and the
    # conclusion below stands; the earlier wording ("profiles.person_id has no
    # foreign key") was wrong and is corrected here before it is reused.
    # no-profile author/mention path was BLIND, and its real run SIGSEGVs the
    # JVM); (c) `Mention belongs_to :person` carries a `<base>_not_found`
    # decision too — `mentions.person_id` has no FK in schema.rb (adversary
    # N3: a dangling mentions row renders `[null]` / 500s on mobile);
    # (d) other belongs_to loads on this endpoint stay pinned found:
    # `comments.author_id` -> people (FK, ON DELETE CASCADE), `posts`
    # commentable (not read on index) — pin ledger; (e) `User has_one :person`
    # pinned found (sign-up creates both rows); (f) a rep that went through
    # `reload` after federation discovery (Person#fix_profile) has its
    # profile pinned found (Discovery saves the profile or raises).
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
        reloaded = owner.respond_to?(:instance_variable_get) && owner.instance_variable_get(:@ci_reloaded)
        decided =
          if refl.belongs_to?
            owner.is_a?(Mention) && refl.name == :person # mentions.person_id: no FK
          else
            # D5 (adversary round 2, 2026-08-28): `User has_one :person` is NO
            # LONGER PINNED. The old argument ("sign-up creates both rows") is
            # factually wrong — `people.owner_id` carries no foreign key to
            # `users` and `Person#destroy` does not destroy its owner, so a
            # user row with no person row is a real database state. The
            # adversary reached it (A10, user `gina`): the share-visibility
            # SELECT is issued, then evil_query.rb:116 (`@querent.person.id`)
            # raises NoMethodError and the author/public SELECTs are NEVER
            # issued. Pinning it found made the corpus assert a statement
            # sequence the app cannot produce in that state.
            !reloaded
          end
        if decided
          nf_name = "#{base}_not_found"
          not_found = symbool(nf_name, ct.seed_for(nf_name, false), note: sql)
          next nil if not_found == true
        end
        ct.symbolic_instance(klass, base, sql)
      rescue StandardError
        nil
      end
    end)

    # 8d. BOUNDARY HARVEST B-1 (coordinator, 2026-08-28): `reload` is a TARGET,
    # not a shim. Its real body (`self.class.unscoped { self.class.find(id) }`,
    # persistence.rb) is a single-row READ, so it mints exactly one note — the
    # statement that read issues — with the bind taken from the RECEIVER's own
    # id var (never a literal):
    #
    #   SELECT "people".* FROM "people" WHERE "people"."id" = $$(<rep>_id) LIMIT 1
    #
    # (b) RETURN: `reload` returns self, so the target returns the RECEIVER.
    #     The rep's attribute vars are NOT re-minted: this batch models a row
    #     as one var family, and a fresh family for the same row would fork the
    #     fold's producer chain (the identity is the evidence). Documented, not
    #     incidental.
    # (c) NOT-FOUND: `find` raises RecordNotFound on a missing row. On this
    #     endpoint reload is reached only from `Person#fix_profile`, i.e. AFTER
    #     the person row was returned by a finder in the same request and after
    #     discovery either saved it or raised — the row cannot be gone.
    #     PINNED FOUND, ledger entry below; no `_not_found` decision is minted.
    #     PIN LEDGER: `<rep>_reload_not_found` — pinned false. Neutrality: the
    #     only caller is fix_profile (person.rb:371-375); its receiver is a rep
    #     produced by a finder target in this same run, so "row vanished
    #     mid-request" is not an app state this endpoint can take.
    if defined?(ActiveRecord::Base)
      interceptor.declare_target(ActiveRecord::Base, :reload, returns: lambda do |receiver, _args, _name|
        next receiver unless receiver.respond_to?(:concolic_attrs)
        table = begin
          receiver.class.table_name
        rescue StandardError
          "records"
        end
        idv = receiver.concolic_attrs["id"]
        sql = %(SELECT "#{table}".* FROM "#{table}" WHERE "#{table}"."id" = #{ct.render_arg_value(idv)} LIMIT 1)
        # the event's note comes from the returned object's concolic_note
        receiver.define_singleton_method(:concolic_note) { sql }
        # associations.rb Base#reload clears the association cache; and the rep
        # is marked reloaded-after-discovery, which pins its profile found (8c).
        receiver.instance_variable_set(:@ci_reloaded, true)
        receiver.instance_variable_set(:@association_cache, {})
        receiver
      end)
    end

    # 8e. Federation discovery wall at the OBJECT boundary (the gem's
    # constructor normalizes the symbolic handle — strip/downcase — before
    # fetch_and_save is reached; the real fetch_and_save aborts the JVM
    # natively on this JRuby). `Discovery.new` -> an inert discovery whose
    # `fetch_and_save` is a DECLARED target with the real RETURN KIND
    # (adversary N6): a `<name>_failed` decision — False: returns the
    # discovered Person (a symbolic rep; callers ignore the value and re-read
    # the row: retry finder / reload); True: raises DiscoveryError, which
    # `find_or_fetch_person_by_identifier` rescues to nil (no retry lookup)
    # and `fix_profile` propagates (a real 500 — recorded by run_dse.rb as an
    # app-error terminal, not a harness failure).
    begin
      require "diaspora_federation/discovery"
    rescue LoadError, StandardError => e
      warn "[comments] diaspora_federation/discovery: #{e.class}"
    end
    if defined?(DiasporaFederation::Discovery::Discovery)
      unless defined?(::CommentsInertDiscovery)
        ::Object.const_set(:CommentsInertDiscovery, Class.new do
          attr_reader :concolic_base
          def initialize(base = nil)
            @concolic_base = base
          end

          def fetch_and_save
            nil
          end
        end)
      end
      # The decision is NAMED BY THE REP that triggers the discovery (the
      # handle argument's owner: `<rep>_diaspora_handle` -> `<rep>_discovery_
      # failed`; a handle scanned out of a comment text -> the mention-lookup
      # site's chain), not by a per-run ordinal — the same rep's discovery is
      # the same decision in every run (no ordinal shift across paths).
      # `Discovery.new`'s argument is NOT bound by the interceptor (a `new`
      # target receives args = {}), so the base is handed down by the two
      # CALLERS through a thread-local: Person#fix_profile (a byte-faithful
      # prepend tagging the rep's own var prefix) and the mention-lookup
      # site's find_or_fetch (PersonFindOrFetchNaming, the site's prefix).
      discovery_base = lambda do |_arg|
        Thread.current[:comments_discovery_base] ||
          "SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_#{defined?(CommentsMentionLookupNaming) ? CommentsMentionLookupNaming.current_ctx : 'json'}"
      end
      unless Person.instance_variable_get(:@ci_fix_profile_tag)
        Person.prepend(Module.new do
          # byte-faithful: only tags the discovery decision with THIS rep's
          # var prefix around the real body (person.rb:371-375)
          def fix_profile
            idv = respond_to?(:concolic_attrs) ? concolic_attrs["id"] : nil
            base = idv.respond_to?(:sym_name) && idv.sym_name ? idv.sym_name.to_s.sub(/_id\z/, "") : nil
            prev = Thread.current[:comments_discovery_base]
            Thread.current[:comments_discovery_base] = base
            begin
              super
            ensure
              Thread.current[:comments_discovery_base] = prev
            end
          end
        end)
        Person.instance_variable_set(:@ci_fix_profile_tag, true)
      end
      unless defined?(::ConcolicDiscoveryNewShim)
        ::Object.const_set(:ConcolicDiscoveryNewShim, Module.new do
          def new(*args)
            base = Thread.current[:comments_discovery_base] ||
                   "SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_" \
                   "#{defined?(CommentsMentionLookupNaming) ? CommentsMentionLookupNaming.current_ctx : 'json'}"
            ::CommentsInertDiscovery.new(base)
          end
        end)
      end
      discovery_returns = lambda do |r, _a, name|
        base = (r.respond_to?(:concolic_base) && r.concolic_base) || name
        vn = "#{base}_discovery_failed"
        failed = symbool(vn, ct.seed_for(vn, false),
                         note: "DiasporaFederation::Discovery#fetch_and_save (webfinger network wall; no SQL)")
        if failed == true
          raise DiasporaFederation::Discovery::DiscoveryError, "concolic: webfinger discovery failed"
        end
        ct.symbolic_instance(Person, "#{base}_discovered", "DiasporaFederation::Discovery#fetch_and_save (discovered person; network wall, no SQL)")
      end
      interceptor.declare_target(::CommentsInertDiscovery, :fetch_and_save, returns: discovery_returns)
      interceptor.declare_target(DiasporaFederation::Discovery::Discovery, :fetch_and_save, returns: discovery_returns)
      # H3 (hardening lint, 2026-08-28): `Discovery.new` is NO LONGER A TARGET.
      # Constructing the discovery client is not data access — the WALL that
      # matters is `fetch_and_save` (still a declared target, still carrying
      # the `<rep>_discovery_failed` decision). As a target, `new` minted an
      # opaque note under the illegible name `Anonymous.new` (the interceptor
      # names a singleton-class target "Anonymous"), which is precisely the
      # shape H3 flags: a note that is not SQL over a body that could reach
      # SQL. It is now a SHIM — a prepend that returns the inert client, so
      # the gem's constructor (which normalizes the handle with strip/downcase
      # on a SymbolicString, and whose real fetch aborts this JVM) never runs
      # in the corpus and mints nothing. Same treatment as B-2.
      DiasporaFederation::Discovery::Discovery.singleton_class.prepend(ConcolicDiscoveryNewShim)
      warn "[comments] Discovery.new / #fetch_and_save walls declared (decision: _failed)"
    end

    # 8f. Mobile partial VALUE fixes (W2 — `_comment.mobile.haml`):
    #   - `timeago(comment.created_at ? … : Time.now)`: datetime columns are a
    #     ConcolicDate (a real Date whose year is the symbolic var) so
    #     `timeago_tag`'s `iso8601`/`to_time` run for real (ported from
    #     notifications/conversations §5c);
    #   - `person_path(person)` / `comment_path(comment)` resolve through
    #     `to_param` (`id && id.to_s`) — a leaf shim on symbolic reps returns
    #     the id var's concrete value as a String (SymbolicInt#to_s renders
    #     the var name, which the journey formatter escapes).
    unless defined?(ConcolicDate)
      ::Object.const_set(:ConcolicDate, Class.new(::Date) do
        attr_writer :sym_year
        def year
          @sym_year || super
        end
      end)
    end
    unless ct.respond_to?(:symbolic_instance_without_comments_dates)
      class << ConcolicTargets
        alias_method :symbolic_instance_without_comments_dates, :symbolic_instance
        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_without_comments_dates(klass, base_name, sql)
          return obj unless obj.respond_to?(:concolic_attrs)
          attrs = obj.concolic_attrs
          klass.columns_hash.each do |col, meta|
            next unless %i[date datetime].include?(meta.type)
            vn = "#{base_name}_#{col}_year"
            d = ConcolicDate.new(1990, 1, 1)
            d.sym_year = symint(vn, seed_for(vn, 1990), note: sql)
            attrs[col] = d
            obj.define_singleton_method(col) { d }
          end
          obj
        end
      end
    end
    unless ActiveRecord::Base.instance_variable_get(:@ci_to_param_shim)
      to_param_shim = Module.new do
        def to_param
          return super unless respond_to?(:concolic_attrs)
          v = concolic_attrs["id"]
          v = v.value if v.respond_to?(:value)
          v && v.to_s
        end
      end
      ActiveRecord::Base.prepend(to_param_shim)
      ActiveRecord::Base.instance_variable_set(:@ci_to_param_shim, true)
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
      interceptor.declare_target(fm, name, returns: CommentsTargets.finder_mock_faithful(ct, raise_on_missing: false, kind: :first))
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
      u = ct.symbolic_instance(ct.model_class(receiver), name, CommentsTargets.finder_note(ct, receiver, args, :first))
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
            # cycle 3 (N5): the handle scanned out of the comment text maps
            # back to the rep's symbolic `_text_mention_handle` var, so the
            # note binds `$$(var)` rather than a literal pin.
            cond = CommentsTargets.rebind_text_values(cond) if cond
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
      prev_base = Thread.current[:comments_discovery_base]
      Thread.current[:comments_discovery_base] = "SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_#{site}"
      begin
        DiasporaFederation::Discovery::Discovery.new(diaspora_id).fetch_and_save
      ensure
        Thread.current[:comments_discovery_base] = prev_base
      end

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
