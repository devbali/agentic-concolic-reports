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
  # -------------------------------------------------------------------
  # W3-1 (adversary round 3, M-3 — Class B with an S consequence):
  # ONE predicate, BOTH modelling sites.
  #
  # A `belongs_to` whose foreign-key column carries NO database FOREIGN KEY
  # can point at a row that is not there, so the load has TWO outcomes and
  # the not-found one is a DECISION, not a pin. The regression the adversary
  # caught was precisely a DISAGREEMENT between the two places that model
  # such a load: §8c `find_target` decided it, while `emit_includes_preloads`
  # (the D8 preload attach) always returned a rep — and once the attach
  # landed, `find_target` was never reached and the decision became dead
  # code. Both sites now ask THIS predicate, so they cannot drift apart
  # again (rule P: the repair is the class, not the instance).
  #
  # On this endpoint the FK-unconstrained belongs_to is `Mention#person`:
  # db/schema.rb:202-209 declares `mentions(mentions_container_id, person_id,
  # mentions_container_type)` and NO `add_foreign_key "mentions", …` exists
  # anywhere in schema.rb:615-645. A dangling `mentions.person_id` renders
  # `"mentioned_people":[null]` with 200 on json and a real 500 on mobile
  # (`mentionable.rb:35` calls `diaspora_handle` on nil), and in that state
  # the real run issues the `people` preload and NOTHING after it — no
  # `profiles` step (adversary B01: 8 of 14 mention loads dangle, 0 of them
  # followed by a profiles read).
  #
  # `comments.author_id` is deliberately NOT here: schema.rb:624 carries
  # `add_foreign_key "comments", "people", column: "author_id", on_delete:
  # :cascade`, so a comment row whose author is gone cannot exist — pin
  # ledger entry, not a decision.
  FK_UNCONSTRAINED_BELONGS_TO = { "Mention" => %w[person] }.freeze

  def dangling_belongs_to?(owner, refl)
    return false unless refl.respond_to?(:belongs_to?) && refl.belongs_to?
    ar = begin
      refl.active_record && refl.active_record.name
    rescue StandardError
      nil
    end
    ar ||= begin
      owner.class.name
    rescue StandardError
      nil
    end
    Array(FK_UNCONSTRAINED_BELONGS_TO[ar.to_s]).include?(refl.name.to_s)
  end

  # DISCIPLINE §13, Rule D (adversary round 6, 2026-08-29): DERIVE WHAT IS
  # DETERMINED, DECIDE ONLY WHAT IS FREE. A preload step's distinct-key count
  # is a free decision only where the data can genuinely repeat a key across
  # the owner rows:
  #
  #   Comment belongs_to :author  — FREE. Two comments can share an author;
  #     ten comments by one author really do give `people.id = ?` (adversary
  #     D01/D05). This is the one step on this endpoint that gets a decision.
  #   Mention belongs_to :person  — DETERMINED BY THE ROW COUNT.
  #     db/schema.rb:207 is UNIQUE on (person_id, mentions_container_id,
  #     mentions_container_type); a comment's `mentions` relation fixes the
  #     last two, so every row of it has a DIFFERENT person_id. Key count IS
  #     row count — the adversary's probe got `RecordNotUnique` trying to
  #     build the other state (M-11).
  #   any has_one / has_many step — DETERMINED: it binds the owner's PRIMARY
  #     KEY, which is distinct per owner row by definition.
  #   any NESTED step — DETERMINED by the parents the step above actually
  #     loaded, and it binds THE SAME key values (M-10, M-12).
  DETERMINED_BY_ROWS = { "Mention" => %w[person] }.freeze

  def key_count_free?(refl)
    return false unless refl.respond_to?(:belongs_to?) && refl.belongs_to?
    ar = begin
      refl.active_record && refl.active_record.name
    rescue StandardError
      nil
    end
    !Array(DETERMINED_BY_ROWS[ar.to_s]).include?(refl.name.to_s)
  end

  # M-14 (adversary round 7, 2026-08-29) — A BOUND IS NOT A DETERMINATION.
  # Cycle 8 derived a keys-driven relation's ROW count from its distinct-KEY
  # count. But `keys <= rows` only BOUNDS it: ten comments by one author is
  # trivially real, issues `people.id = ?` AND twenty `mentions` reads, and
  # the corpus could not say so — `(len(comments) > 1)` had vanished corpus
  # wide. The row count is a free fact of its own and is recorded for EVERY
  # list again; only the KEY count is derived where a schema constraint or a
  # parent step determines it. `preload_rows_driven?` is gone with it.
  #
  # M-13 (same round) — ONE VARIABLE, ONE FACT. A partially loaded FK-less
  # `belongs_to` welded two facts onto `_not_found`: *which* child is missing
  # AND *whether* anything loaded. With one representative row the attached
  # child was always the LIVE one, so `mentioned_people` could never hold a
  # nil BESIDE a live Person — the one list shape `Mentionable.format` raises
  # on (real run G07: 7 statements and a Template::Error, vs 11 for the
  # control). A relation whose rows carry such a step therefore materializes a
  # SECOND representative row once its row count says "two or more": the two
  # rows get INDEPENDENT child outcomes, so `[live, nil]` and `[nil, live]`
  # are both reachable, and the second row's own FK column IS the second key
  # (one variable, one fact — no synthesized `_row2_` value needed).
  # Elsewhere the one-representative limit stands (N5-2, declared): a second
  # row is minted only where a per-row outcome differs observably.
  # M-16 (adversary round 8, 2026-09-01) — A SECOND KEY NEEDS A SECOND OWNER
  # OBJECT. Cycle 9 minted a second representative row only where the step was
  # an FK-less `belongs_to`, and only at the TOP of the includes tree. Every
  # other step recorded the second key's outcome as a bare `_k2_not_found`
  # boolean whose only effect was `loaded_keys << keys[1] unless …` — and
  # `loaded_keys` is consumed solely by the NESTED step, so on the DEEPEST step
  # of a tree the True arm reached nothing: no child attached, `Person#name`
  # never called on key 2, no `_discovery_failed` decision, no terminal. The
  # corpus asserted a clean 200 and the statements of a full render in 1 345
  # dumps (429 author + 916 mentions) where the real request 500s after fewer
  # statements — a PHANTOM decision (over-emission and a missing branch at
  # once). Real differential: adversary8 H06 posts 870/871 and 872/873,
  # byte-identical fixtures differing only in WHICH key lacks its `profiles`
  # row; both orders return DiscoveryError for real.
  #
  # So the rule is no longer "an FK-less belongs_to at the top": a list needs a
  # second representative row whenever ANY step of its includes tree — at ANY
  # depth — has an OUTCOME THAT IS A DECISION, i.e. can attach nil. Those are
  # exactly `has_one` (no FK forces the child row to exist) and an
  # FK-unconstrained `belongs_to`. The decision is per KEY; without a second
  # owner object the second key's outcome is observable by nothing.
  def needs_second_row?(ct, receiver)
    iv = receiver.respond_to?(:includes_values) ? Array(receiver.includes_values) : []
    return false if iv.empty?
    klass = ct.model_class(receiver)
    walk = nil
    walk = lambda do |k, spec|
      pairs = spec.is_a?(Hash) ? spec.to_a : [[spec, nil]]
      pairs.each do |aname, nested|
        r2 = (k.reflect_on_association(aname.to_sym) rescue nil)
        next unless r2 && !r2.polymorphic?
        return true if r2.macro == :has_one || dangling_belongs_to?(nil, r2)
        return true if nested && walk.call(r2.klass, nested)
      end
      false
    end
    iv.each { |spec| return true if walk.call(klass, spec) }
    false
  end

  # W5-1 / M-7 (adversary round 5, 2026-08-29): the preload predicate follows
  # the DISTINCT KEY COUNT, not the row count. `Preloader::Association` does
  #     owners.group_by { |o| o[owner_key_name] }   # -> UNIQUE keys
  #     records_for(owners_by_key.keys)
  # and `PredicateBuilder::ArrayHandler` then picks
  #     0 keys -> NullPredicate | 1 key -> equality | 2+ -> IN
  # so ten comments by ONE author give `people.id = ?` (measured: adversary
  # D05 post 651), and two comments by TWO authors give `IN (?, ?)`. Cycle 6
  # tied the operator to the LIST LENGTH, which is a different fact, and got
  # the commonest multi-comment state exactly wrong.
  #
  # `keys` is the modelled distinct-key SET for this step: one bind, or two
  # (2 stands for "two or more", the same convention as the link chain's 4).
  # ---------------------------------------------------------------------
  # with_through_load_sql — the preload step's statement, WITHOUT duplicating it
  # into an argument literal.
  # ---------------------------------------------------------------------
  # The probe's SQL used to be passed positionally
  # (`load_intermediate(psql)`) and the mock read it back as `args["sql"]`
  # to note the row list it returns. That made the SAME text land in TWO
  # places on the event:
  #   note -> sealed:   {"refs":{"p0":"SYM_…_row_author_id"},
  #                      "text":"… \"people\".\"id\" = $$(p0)"}    ✔
  #   args.sql -> Lit:  "… \"people\".\"id\" = $$(SYM_…_row_author_id)"  ✘
  # An ARGUMENT gets no envelope, so `CallInterceptor` (call_interceptor.rb,
  # "A `$$(pN)` PLACEHOLDER MAY NOT BE RECORDED AS AN ARGUMENT") correctly
  # unresolves the placeholder back to the raw symbol name rather than
  # recording a key nothing defines. The result is a string literal that
  # LOOKS like it binds `SYM_…_row_author_id` while nothing in the rendered
  # document declares that name there — a reader cannot tell it from a bind
  # that resolves, and `_canon_note` cannot canonicalise it because it is
  # opaque argument data, not a note.
  #
  # The note is the ONLY place this statement belongs, and it already
  # carries it. So hand the mock its text out of band and call the probe
  # with NO arguments: one statement, one home, zero undefined references.
  # Same thread-local hand-off the finder-conditions channel uses.
  #
  # TAKES A BLOCK, and the block makes the call: `file`/`lineno`/`function`
  # on the recorded event are the CALLER's frame, so calling the probe from
  # inside this helper would stamp every emission with this helper's own
  # line and collapse the two emission sites (the preload walk and the
  # join-table fetch) onto one source. `PathSource` participates in
  # canonicalisation (`concolic/model/run.py::_canon`), so that is a real
  # loss of provenance, not cosmetics. With a block the frame stays at the
  # call site, exactly where it was before this change.
  def with_through_load_sql(sql)
    prev = Thread.current[:concolic_through_load_sql]
    Thread.current[:concolic_through_load_sql] = sql
    yield
  ensure
    Thread.current[:concolic_through_load_sql] = prev
  end

  def pred_for(ct, keys)
    rendered = keys.map { |k| ct.render_arg_value(k) }
    rendered.length > 1 ? "IN (#{rendered.join(', ')})" : "= #{rendered.first}"
  end

  # The SECOND distinct value of the column this step binds. The corpus models
  # one representative ROW, so the second row is represented by the ONE column
  # this statement needs — minted with the OWNER's own producing query as its
  # note, so the fold resolves it to that column of that query (it is a real
  # column value of a real row, not a policy parameter: Rule V does not apply).
  # Named `<owner-prefix>2_<column>` so the fold's longest-suffix column match
  # still finds `<column>`.
  def second_key(ct, owner_rep, col)
    idv = owner_rep.concolic_attrs["id"]
    pre = (idv.sym_name.sub(/_id\z/, "") if idv.respond_to?(:sym_name) && idv.sym_name)
    return nil unless pre
    vn = "#{pre}2_#{col}"
    note = (owner_rep.concolic_note rescue nil)
    symint(vn, ct.seed_for(vn, 2), note: note)
  end

  def mark_loaded(owner_rep, name, target)
    a = owner_rep.association(name)
    a.target = target
    a.loaded!
    true
  rescue StandardError
    nil
  end

  # N4-3 (adversary round 4, INSTRUMENT->batch): the preload note's PREDICATE
  # OPERATOR is part of the statement's identity, and the judges could not see
  # it until round 4 taught them. `Associations::Preloader` emits
  # `WHERE "t"."col" = ?` for ONE owner row and `WHERE "t"."col" IN (?, ?, …)`
  # for two or more — measured both ways in this batch's own concrete runs
  # (12 real `IN (?, ?)` preloads and 19 real `= ?` ones). A note that always
  # says `IN` asserts a bulk access in the state the corpus actually models
  # (a single sampled row); a note that always says `=` cannot express the
  # bulk one. So the operator follows `many`, which is the collection's own
  # cardinality decision (`(len(X) > 1)`, recorded in rows_mock).
  # `owner_rows` is the concrete row count of the relation being preloaded.
  # It bounds the distinct-key count but does NOT determine it (M-7).
  # Returns the largest key-set size any step used, so a KEYS-DRIVEN relation
  # can set its row count from it (a second distinct key implies a second row).
  def emit_includes_preloads(ct, receiver, rep, rep2: nil, owner_rows: 1)
    iv = receiver.respond_to?(:includes_values) ? Array(receiver.includes_values) : []
    return 1 if iv.empty?
    owner_klass = ct.model_class(receiver)
    max_keys = 1
    emit = nil
    # `n_keys` — how many DISTINCT values of the bound column this level has.
    # At the TOP level it is a DECISION (bounded by the row count); at a NESTED
    # level it is DERIVED from how many parents the step above actually
    # loaded — never inherited (W5-2 / M-8: two mentions, one dangling, gives
    # `people.id IN (?, ?)` and then `profiles.person_id = ?`).
    # `in_keys` is nil at the TOP level (the key set is computed here) and an
    # ARRAY at a nested level (M-10/M-12: the key set IS the parents the step
    # above loaded, bound to THE SAME variables — not re-decided, not renamed).
    emit = lambda do |owner_rep, owner_rep2, klass, spec, in_keys|
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
          owner_col = r2.foreign_key.to_s
          col = (r2.association_primary_key(r2.klass) rescue "id")
          table = r2.table_name
          pcol = col
        else
          bindv = attrs["id"]
          next if bindv.nil?
          owner_col = "id"
          thr = (r2.respond_to?(:through_reflection) && r2.through_reflection) || nil
          t   = thr || r2
          table = t.table_name
          pcol = t.foreign_key
        end
        onote = (owner_rep.concolic_note rescue nil)
        base2 = (owner_rep2 ? ct.assoc_base_name(owner_rep2, r2.name) : nil)
        # the second key: the SECOND ROW's own column where a second row is
        # materialized (M-13 — one variable, one fact), otherwise a
        # synthesized value of the same column (the declared one-row limit).
        k2cand =
          if owner_rep2
            (owner_rep2.concolic_attrs[owner_col] rescue nil)
          else
            second_key(ct, owner_rep, owner_col)
          end
        keys =
          if in_keys                       # NESTED — determined (M-10, M-12)
            in_keys
          elsif key_count_free?(r2)        # TOP, free — the one decision
            # BOUNDED by the row count (M-14, the other direction): two
            # DISTINCT authors need two comments, so the decision exists only
            # where a second row does. `keys <= rows` is a bound both ways —
            # it does not determine the rows, and the rows do cap the keys.
            if owner_rows > 1
              km = "#{base}_keys_many"
              many_k = (symbool(km, ct.seed_for(km, false), note: onote) == true) && !k2cand.nil?
              unless many_k
                # N8-5 (adversary round 8) / Rule D, closed in cycle 11.
                # `keys_many == False` ASSERTS that the owner rows share one
                # value of this column, and the note it emits binds only the
                # first row's symbol (`people.id = $(…_row_author_id)`). The
                # second row's `…_row2_author_id` was a SEPARATE free symbol
                # that appeared in 0 path conditions and 0 assumptions, so a
                # solver was free to give it a DIFFERENT value — a model in
                # which two rendered comments have two authors while the
                # corpus reads only one of them. That direction is not benign:
                # the extracted policy loses an access-control read.
                # So in the one-key state the second row's column IS the first
                # row's variable — one fact, one symbol, nothing left to
                # contradict. (The mirror residue on the `IN` side is benign
                # and is reported, not fixed: two binds that a model happens to
                # make equal still describe the same result set.)
                begin
                  owner_rep2.concolic_attrs[owner_col] = bindv if owner_rep2 && owner_rep2.respond_to?(:concolic_attrs)
                rescue StandardError
                  nil
                end
              end
              many_k ? [bindv, k2cand] : [bindv]
            else
              [bindv]
            end
          else                             # TOP, determined by the row count
            (owner_rows > 1 && k2cand) ? [bindv, k2cand] : [bindv]
          end
        max_keys = keys.length if keys.length > max_keys
        psql = %(SELECT "#{table}".* FROM "#{table}" WHERE "#{table}"."#{pcol}" #{pred_for(ct, keys)})
        with_through_load_sql(psql) { ConcolicThroughLoadProbe.load_intermediate }
        child = nil
        loaded_keys = keys
        if r2.belongs_to? || r2.macro == :has_one
          # W3-1: the preload step's outcome is a DECISION whenever the row
          # it points at is not guaranteed to exist — a has_one (no FK forces
          # the child row to exist) or an FK-unconstrained belongs_to
          # (`dangling_belongs_to?`). The step's own statement IS still
          # emitted above (the real preload issues the SELECT and gets zero
          # rows back); what the not-found arm removes is the CHILD: nil is
          # attached (exactly what the real Preloader leaves behind) and the
          # NESTED step below is skipped, because AR preloads the next level
          # from the records it actually loaded.
          child2 = nil
          if r2.macro == :has_one || dangling_belongs_to?(owner_rep, r2)
            # M-13: the two facts are now two variables.
            #  (i) WHICH child is missing — one `_not_found` decision PER ROW,
            #      on that row's own association base. With a second row
            #      materialized these are independent, so the representative's
            #      child can be nil WHILE the other row's is live: the
            #      `[nil, live]` shape `Mentionable.format` raises on.
            #  (ii) HOW MANY loaded — the union of the surviving keys, which
            #      is what the NESTED step binds. It no longer collapses to
            #      zero just because the representative's child is missing.
            nf = "#{base}_not_found"
            missing = (symbool(nf, ct.seed_for(nf, false), note: psql) == true)
            child = missing ? nil : ct.symbolic_instance(r2.klass, base, psql)
            loaded_keys = missing ? [] : [keys[0]]
            if keys.length > 1
              if base2
                nf2 = "#{base2}_not_found"
                missing2 = (symbool(nf2, ct.seed_for(nf2, false), note: psql) == true)
                child2 = missing2 ? nil : ct.symbolic_instance(r2.klass, base2, psql)
                loaded_keys << keys[1] unless missing2
              else
                # M-16: there is no second OWNER OBJECT to attach the second
                # key's child to, so its outcome is observable by nothing —
                # and a decision whose True arm changes no note, no downstream
                # decision and no terminal is a PHANTOM, not a decision. The
                # old `_k2_not_found` boolean lived here; it is gone.
                # `needs_second_row?` now guarantees the object for every tree
                # that contains a decision step, so this arm is unreachable on
                # any relation that has one. Where it is reached (a tree with
                # no decision step at all) the key is simply LOADED: the corpus
                # never claims an outcome it cannot exhibit.
                loaded_keys << keys[1]
              end
            end
          else
            # FK-constrained belongs_to (`comments.author_id`, schema.rb:624):
            # every key matches, so the loaded key set IS the key set.
            child = ct.symbolic_instance(r2.klass, base, psql)
            # cycle 11: a SECOND child exists only where there is a SECOND KEY.
            # With one distinct key the preloader attaches the SAME record to
            # both owner rows — minting a second Person rep there would give
            # the corpus a second author that does not exist, and (measured on
            # the cycle-11 smoke) a second `profiles.person_id = ?` read no
            # real request issues. This is the other half of N8-5: with one key
            # there is one author SYMBOL, not two unconstrained ones.
            child2 = (keys.length > 1 && base2) ? ct.symbolic_instance(r2.klass, base2, psql) : nil
          end
          mark_loaded(owner_rep, r2.name, child)
          # one key -> both rows point at the SAME child (what AR's Preloader
          # does); two keys -> each row gets its own.
          mark_loaded(owner_rep2, r2.name, (child2 || (keys.length > 1 ? nil : child))) if owner_rep2
        end
        # the nested step binds the keys of the parents ACTUALLY LOADED — the
        # SAME values, so one fact has one variable all the way down (M-12).
        # It recurses from whichever parent survived, so a missing FIRST
        # parent no longer suppresses the nested read (M-13).
        # M-16: BOTH surviving parents go down, not just the first. Passing
        # only `child || child2` was the other half of the phantom: the nested
        # step then had two KEYS and one OWNER, so its second key fell into the
        # `_k2_not_found` branch above and its outcome reached nothing. With
        # both parents the deepest step gets a per-object `_not_found` on its
        # own base (`…_row2_author_profile_not_found`), the render calls
        # `Person#name` on the second author, and the missing profile produces
        # the `…_row2_author_discovery_failed` decision and its DiscoveryError
        # terminal — which is what the real request does (R8 H06).
        survivors = [child, child2].compact
        if nested && survivors.any? && loaded_keys.any?
          emit.call(survivors[0], survivors[1], r2.klass, nested, loaded_keys)
        end
      end
    end
    iv.each { |spec| emit.call(rep, rep2, owner_klass, spec, nil) }
    max_keys
  rescue StandardError
    1 # note-side extra must never crash the mock (M-family rule)
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
        # M-9 / B-8 (adversary round 5): THE FINDER STILL RAN ITS QUERY. This
        # is the arm the adversary measured: the three `ci_*_first` visibility
        # finders and the anon post finder all end here on a miss, and `nil`
        # carries no note, so the corpus lost the two reads that ARE this
        # endpoint's access control and the anon 404 dump extracted to an
        # EMPTY policy. The engine's one-shot channel carries it instead.
        Thread.current[:concolic_pending_note] = sql
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

      # type: opaque -- returns a Ruby Class; examined, and it has no §5 structure.
      interceptor.declare_target(btpa, :klass, kind: CallInterceptor::SHIM, type: "opaque", returns: lambda do |receiver, _args, _name|
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
      interceptor.declare_target(btpa, :find_target, kind: CallInterceptor::TARGET_FUNCTION, type: "obj<?>", returns: lambda do |receiver, _args, name|
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
    # W4-2 / M-6 (adversary round 4): a row whose STI `type` is outside the
    # Post tree is NEVER INSTANTIATED — `find_sti_class` raises while the
    # finder is turning the result set into objects. The statement, however,
    # HAS been issued: the corpus must keep the finder's note and then make
    # the run die on first use.
    #
    # The runtime records a target's symbolic_call event (and its note) only
    # AFTER the mock's `returns` lambda comes back, so raising from inside the
    # mock would SWALLOW the post finder's own statement — the Class-S defect
    # M-3 and M-4 were about, introduced while fixing a Class-B one. So the
    # mock returns THIS object instead: the interceptor reads its
    # `concolic_note` (the finder SQL), records the event, hands it to the
    # app, and the first thing the app does with it raises.
    #
    # It poisons EVERY method rather than the two the current call sites
    # happen to touch (`public?` on the anon path, `comments` on the
    # signed-in one). Enumerating call sites is the instance-shaped fix rule P
    # forbids; "an object that does not exist cannot be used at all" is the
    # class-shaped one, and it stays correct when a new path reaches it.
    # Only the handful of methods the RUNTIME itself calls on a mock's return
    # value are answered: `concolic_note` (the note), plus the Object
    # protocol `is_a?` / `class` / `nil?` / `respond_to?` / `to_s` / `inspect`
    # / `hash` / `==` used by `extract_note`, `to_native`, `sort_of` and the
    # dump's JSON serialization.
    unless defined?(UninstantiableRow)
      ::Object.const_set(:UninstantiableRow, Class.new do
        # N5-1 (adversary round 5): the poison must be complete BY
        # CONSTRUCTION, not by enumerating the methods that leak. Round 4's
        # version inherited all of Object/ActiveSupport, so `try` answered
        # nil, `is_a?` answered false and `present?` answered true — three
        # silent ways for app code to route around a row that does not exist.
        # Everything is undefined except the few methods the RUNTIME itself
        # calls on a mock's return value; anything else reaches
        # `method_missing` and raises. A method the runtime needs and this
        # list forgets fails LOUDLY (a run error), never silently.
        keep = %i[
          __id__ __send__ object_id class frozen?
          nil? is_a? kind_of? instance_of? respond_to? respond_to_missing?
          method_missing concolic_note to_s inspect to_json
        ]
        (instance_methods - keep).each { |m| undef_method(m) }

        # the classes the runtime type-tests a return value against
        # (call_interceptor's pass-through check, to_native, extract_note)
        define_singleton_method(:runtime_types) do
          t = [::Integer, ::String, ::Float, ::Array, ::Hash, ::TrueClass, ::FalseClass, ::NilClass]
          t << ::SymbolicVar if defined?(::SymbolicVar)
          t << ::SymbolicList if defined?(::SymbolicList)
          t << ::SymbolicDict if defined?(::SymbolicDict)
          t
        end

        def initialize(sql, message)
          @sql = sql
          @message = message
        end

        def concolic_note
          @sql
        end

        def nil?
          false # extract_note's first guard; the object is not nil, it is unusable
        end

        def to_s
          "<UninstantiableRow #{@message}>"
        end
        alias_method :inspect, :to_s

        def to_json(*_a)
          to_s.inspect
        end

        # The runtime may ask what this is; the APPLICATION may not — an
        # `is_a?`/`kind_of?` that quietly answers false is exactly how a type
        # check routes around a row that cannot exist.
        def is_a?(mod)
          return false if ::UninstantiableRow.runtime_types.any? { |c| mod.equal?(c) }
          raise ActiveRecord::SubclassNotFound, @message
        end
        alias_method :kind_of?, :is_a?
        alias_method :instance_of?, :is_a?

        def respond_to?(name, _priv = false)
          return true if name.to_sym == :concolic_note
          return false if name.to_sym == :note
          raise ActiveRecord::SubclassNotFound, @message
        end

        def respond_to_missing?(_name, _priv = false)
          false
        end

        def method_missing(_name, *_args, &_blk)
          raise ActiveRecord::SubclassNotFound, @message
        end
      end)
    end

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

        # M-13 (round 7): a list may carry a SECOND representative row. It is
        # minted only where two rows' outcomes can differ observably (an
        # FK-less belongs_to preload), so the one-row limit still stands
        # everywhere else — and `mentioned_people` can now hold a nil BESIDE a
        # live Person, which is the shape `Mentionable.format` raises on.
        attr_accessor :second_representative

        def reps
          r = []
          r << @representative if @representative
          r << @second_representative if @second_representative && concrete_length > 1
          r
        end

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
          reps.each { |r| yield r } if nonempty
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
          nonempty ? reps.map { |r| yield r } : []
        end
        alias_method :collect, :map

        # W3-2: an EMPTY relation now carries NO representative row (the
        # mock stops minting one once the length is known to be 0 — a query
        # that returned no rows has no row to represent). `SymbolicList`'s
        # element readers raise without a representative, which is the right
        # behaviour for "one rep row is modeled and you asked for another",
        # but the wrong one for "the list is empty": Ruby's own `[].first` is
        # `nil`, and so is AR's. Return nil ONLY in that exact case; every
        # other rep-less access still raises loudly (honesty §5.3).
        def first(*args)
          return nil if args.empty? && @representative.nil? && concrete_length.zero?
          super
        end

        def last(*args)
          return nil if args.empty? && @representative.nil? && concrete_length.zero?
          super
        end

        def [](*args)
          if @representative.nil? && concrete_length.zero? &&
             args.length == 1 && args[0].is_a?(Integer)
            return nil
          end
          super
        end
      end)
    end

    rel      = ActiveRecord::Relation
    null_rel = defined?(ActiveRecord::NullRelation) ? ActiveRecord::NullRelation : nil

    # T1b helper: a declared no-op target whose sole purpose is generating
    # a symbolic_call EVENT carrying the through-load intermediate SQL as
    # its note (extraction emits queries from events, transform.py:225).
    unless defined?(::ConcolicThroughLoadProbe)
      # NO PARAMETER (2026-09-25): the SQL arrives on
      # `Thread.current[:concolic_through_load_sql]` (see
      # `CommentsTargets.with_through_load_sql`). A parameter would put the
      # statement into the event's `args` as a Lit string carrying raw
      # `$$(SYM_…)` markers that nothing in the document defines, while the
      # note already carries the same statement sealed with real refs.
      ::Object.const_set(:ConcolicThroughLoadProbe, Module.new do
        def self.load_intermediate
          Thread.current[:concolic_through_load_sql]
        end
      end)
      interceptor.declare_target(
        ::ConcolicThroughLoadProbe.singleton_class, :load_intermediate,
        kind: CallInterceptor::TARGET_FUNCTION, type: "[?]", returns: lambda do |_r, args, name|
          # cycle 3 (adversary N2, return-kind fidelity): a preload step
          # returns a ROW LIST, not a count. Length-only sampled list (no
          # representative — the preloaded rows are reached through the
          # owner's association readers, which mint their own reps).
          IterableSymbolicList.new(ConcolicTargets.seed_for("len(#{name}_rows)", 1),
                                   name: "#{name}_rows",
                                   note: (Thread.current[:concolic_through_load_sql] ||
                                          args["sql"]).to_s,
                                   representative: nil)
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
      # W3-2 (adversary round 3, M-4 — Class S, over-emission).
      # The real counterpart of the preload step is
      # `ActiveRecord::Associations::Preloader#preload`, which preloads FROM
      # THE RECORDS THIS QUERY RETURNED: zero records => zero statements.
      # This mock used to mint the representative row and call
      # `emit_includes_preloads` BEFORE the list length existed, so the
      # corpus asserted a `people` read and a `profiles` read — plus every
      # decision of a row that was never returned — in 2 619 empty-relation
      # states across 47 % of the corpus, where the real endpoint issues
      # nothing at all (adversary B02: six empty-list requests, two
      # statements each; B10: 21 of 28 mention loads produce zero preloads).
      #
      # The length is a seeded CONCRETE row count (it is the value
      # IterableSymbolicList is about to be built with, and the same value
      # the `(len(X) != 0)` decision reports when the app iterates), so it is
      # available here: read it FIRST and mint nothing below the list until
      # it is known non-empty. Cardinality: one bulk statement per preload
      # step per non-empty page, which is exactly what the real Preloader
      # issues and what the sampled list's domain {0, 1} can express.
      #
      # N4-3 (adversary round 4): the length is now 0 / 1 / MANY, not 0 / 1.
      # `Preloader` emits `col = ?` for one owner row and `col IN (?, …)` for
      # two or more, so a corpus that models only "one row" can express only
      # one of the two real preload shapes — and this batch's own concrete
      # runs contain both (19 real `= ?`, 12 real `IN (?, ?)`). The list still
      # carries ONE representative row (the runtime's Gate-1b limit on row
      # CONTENT is unchanged and undiminished); what is now modelled is its
      # CARDINALITY, which is what the statement shape depends on. 2 stands
      # for "two or more", the same convention as the link chain's 4.
      # M-16b (cycle 11, found while verifying M-16) — ONE RELATION READ TWICE
      # IS ONE FACT. `Diaspora::MentionsContainer#mentioned_people` is called
      # TWICE per comment on this endpoint (once by the text pipeline through
      # `Mentionable.format`, once by `CommentPresenter#as_json:15`), and each
      # call rebuilds `mentions.includes(person: :profile)`, so the app really
      # issues the SELECT twice (R8 N8-2: 10 comments -> 20 `mentions` reads).
      # It gets the SAME ROWS both times. The rig minted an INDEPENDENT list
      # per call (`…_records_2`, `…_records_3`), each with its own length
      # decision and its own per-row outcomes, so the corpus could assert that
      # one comment's `mentions` relation has two rows in the first read and
      # one in the second — a state no database produces. Measured on the
      # cycle-11 smoke corpus: 1 661 relations read twice, **654** of them with
      # DISAGREEING `len > 1` decisions. It also MASKED the M-16 repair on the
      # mention tree: the read that carried the missing profile was not the
      # read the presenter serialized (smoke `dump_anon_json_dse0136`).
      #
      # So the materialized list is MEMOIZED by its own SQL for the life of the
      # run: the second read re-emits every statement (multiplicity is real and
      # stays exact) and re-records the same decisions under the same variable
      # names, but it is the SAME list with the SAME rows. One fact, one
      # variable — the same rule M-12 applies down a preload chain, applied
      # across two reads of one relation.
      memo = (Thread.current[:comments_rows_memo] ||= {})
      hit  = memo[sql]
      len = begin
        Integer(ct.seed_for("len(#{vn})", 1))
      rescue StandardError, TypeError
        1
      end
      len = hit[:len] if hit
      rep = nil
      rep = (hit ? hit[:rep] : ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", sql)) if len.positive?
      # Rule D (round 6): WHICH cardinality fact this relation records depends
      # on what determines its preload keys.
      #  ROWS-DRIVEN (every step determined by the row count — the `mentions`
      #    relation, whose UNIQUE index makes key count == row count): the row
      #    count IS the fact, so `(len(X) > 1)` is recorded and the key set is
      #    DERIVED from it. M-11 was the corpus asserting `len > 1` beside a
      #    one-bind note, a state the database rejects.
      #  KEYS-DRIVEN (a FREE step — the `comments` relation's author preload):
      #    the distinct-key count is the fact, the row count FOLLOWS from it
      #    (a second distinct author implies a second comment), and recording
      #    both would be two variables for one fact (cross-endpoint rule 7).
      #    Only empty-vs-non-empty is a separate decision here.
      # M-14: the ROW COUNT is recorded for EVERY list — it is a free fact that
      # the distinct-key count only bounds. M-13: a list whose rows carry an
      # FK-less belongs_to preload materializes a SECOND representative row
      # once that decision says "two or more", so the two rows' children can
      # differ (a nil beside a live Person).
      # the memoized list keeps the FIRST read's variable names (`vn` of the
      # first call), so the second read binds the same symbols in its notes.
      lst = hit ? hit[:lst] : IterableSymbolicList.new(len, name: vn, note: sql, representative: rep)
      if len.positive?
        many = (lst.length > 1)
        rep2 = hit ? hit[:rep2] : nil
        if !hit && many && needs_second_row?(ct, receiver)
          rep2 = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row2", sql)
          lst.second_representative = rep2
        end
        # re-emitted on EVERY read: the preload statements are issued again by
        # the real app, and re-recording an identical decision is idempotent.
        emit_includes_preloads(ct, receiver, rep, rep2: rep2,
                               owner_rows: (many ? 2 : 1)) # T1b repair #2 (ported)
        memo[sql] ||= { len: len, rep: rep, rep2: rep2, lst: lst }
      else
        memo[sql] ||= { len: len, rep: nil, rep2: nil, lst: lst }
      end
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
          CommentsTargets.with_through_load_sql(isql) { ConcolicThroughLoadProbe.load_intermediate }
        end
      rescue StandardError
        nil # note-side extra must never crash the mock (M-family rule)
      end
      lst
    end

    %i[to_a to_ary records].each do |m|
      interceptor.declare_target(rel, m, kind: CallInterceptor::TARGET_FUNCTION, type: "[?]", returns: rows_mock)
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
        interceptor.declare_target(cp, m, kind: CallInterceptor::TARGET_FUNCTION, type: "[?]", returns: rows_mock)
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
              # N3-3 (adversary round 3): the mention's DISPLAY NAME is a
              # DECISION, not a pin. `Mentionable::REGEX` makes the name
              # optional (`@{handle}` as well as `@{Name; handle}`), and
              # `MentionsInternal.mention_link` passes it to
              # `PeopleHelper#person_link`, which uses
              # `opts[:display_name] || person.name` (people_helper.rb:28-33).
              # With the name always present, `Person#name` — and therefore
              # `Person#fix_profile` -> Discovery -> reload -> the profiles
              # re-read — was UNREACHABLE for a MOBILE mention person, so the
              # `…_row_person_profile_not_found == True` arm minted no
              # consequence at all while the json side (as_api_response calls
              # `name` unconditionally) carried the whole chain.
              dn_name = "#{base_name}_text_mention_has_name"
              has_name = symbool(dn_name, seed_for(dn_name, true), note: sql)
              parts << (has_name == true ? "@{Concolic Mention; #{handle.value}}" : "@{#{handle.value}}")
            end
            if has_dlink == true
              # D6 (round 2) / N3-2 (round 3): CARDINALITY. A real
              # link-bearing comment issues ONE `Post.exists?(guid:)` per
              # `post`-entity link. Round 2 fixed the cap of one by writing a
              # FIXED text of three post links plus a comment link, which made
              # the only expressible per-dump probe counts {0, 2, 3} — while
              # real renders issue 0, 1, 2, 3 and 5 (adversary B03), and ONE
              # is the commonest real shape. A fixed count is a pin over a
              # multiset, so the count is now a DECISION CHAIN: the text
              # carries at least one link (`_text_has_dlink`), and each
              # further link is its own nested decision
              # (`_text_dlink_ge2/ge3/ge4`). Combined with the entity decision
              # on the first link (`_text_dlink_is_post`, message_renderer.rb:
              # 121 `Regexp.last_match(2) == "post"` — a `comment` entity
              # issues no query), the expressible per-rep probe counts are
              # {0, 1, 2, 3, 4}.
              # HONEST LIMIT, stated like the sampled list's {0, 1}: 4 stands
              # for "four or more" — the text is unbounded in reality, and a
              # chain long enough to express every real count does not exist.
              # The comment-entity link that round 2 appended unconditionally
              # is gone: `is_post == False` already turns the FIRST link into
              # a `comment` one, so the extra link only added a guid parameter
              # and a text fragment no decision depended on.
              ip_name = "#{base_name}_text_dlink_is_post"
              is_post = symbool(ip_name, seed_for(ip_name, true), note: sql)
              short = base_name.sub("SYM_RESULT_ActiveRecord__", "")
              nlinks = 1
              (2..4).each do |k|
                ge = "#{base_name}_text_dlink_ge#{k}"
                break unless symbool(ge, seed_for(ge, false), note: sql) == true
                nlinks = k
              end
              nlinks.times do |k|
                gv = "SYM_PARAM_dlink_guid#{k}_#{short}"
                guid = symstr(gv, seed_for(gv, "concolicguid000000000#{k}"),
                              note: "free value: diaspora:// link guid parsed out of the comment text " \
                                    "(policy parameter; no producer column)")
                CommentsTargets.text_binds[guid.value.to_s] = guid
                entity = (k.zero? && is_post != true) ? "comment" : "post"
                parts << "diaspora://concolic_link@example.org/#{entity}/#{guid.value}"
              end
            end
            parts << "welcome"
            attrs["text"] = parts.join(" ")
          end
          # N3-1 (adversary round 3) + Rule G (DISCIPLINE §11):
          # `users.language` is a column the application BRANCHES on, and it
          # was in neither the gate list nor the pin ledger. The chain is
          #   application_controller.rb:100-108  set_locale
          #     I18n.locale = current_user.language
          #   application_controller.rb:118-122  set_grammatical_gender
          #     if user_signed_in? && I18n.inflector.inflected_locale?
          #       current_user.gender  ->  User#gender -> Person#gender
          #       (user.rb:59 / person.rb:27-28, both plain `delegate`)
          #       -> `person.profile` -> SingularAssociation#find_target
          #       -> SELECT "profiles".* WHERE "profiles"."person_id" = ? LIMIT 1
          # — a read on the DEVISE PRINCIPAL, issued BEFORE the action body,
          # that the corpus never contained (adversary B09 `pl` vs B11 `en`,
          # a clean real differential). The corpus minted `language` as the
          # placeholder string `<var>_v`, which is not an inflected locale,
          # so the branch was never true and never recorded.
          #
          # The column is therefore a DECISION recorded on the column's own
          # var (`(<rep>_language == StringVal('pl'))`), and its concrete
          # value is one of two real locale codes so that `I18n.locale=` and
          # the inflector run for real: `pl` (config/locales/inflections/
          # pl.yml — the app's ONLY inflected locale) or `en` (no
          # inflections). The decision's meaning is "the user's language is
          # an inflected locale", and `pl` is its witness.
          # `language` is in `pc_gate_columns`; `gender` is in the PIN LEDGER
          # (both arms of `gender.empty?` reach only in-memory I18n inflector
          # lookups — the profiles READ is the evidence, and it is minted on
          # both arms).
          # W4-1 / M-5 (adversary round 4): `users.language` has THREE
          # outcomes, not two. `set_locale` runs `I18n.locale =
          # current_user.language` with `I18n.enforce_available_locales ==
          # true`, so a NON-NIL code that is not an available locale raises
          # `I18n::InvalidLocale` BEFORE the action body: the real run issues
          # exactly one statement (the `users` SELECT) and 500s — no post
          # finder, no visibility join, no comments read (adversary C04,
          # `language = "xx"` and `""`). The two-literal domain {"pl","en"}
          # pinned that state out of existence with no ledger entry, which
          # DISCIPLINE §11 forbids for a decision's DOMAIN as much as for its
          # column. The arms and their witnesses:
          #   "pl" — an AVAILABLE and INFLECTED locale. `config/locales/
          #          inflections/pl.yml` is the app's only one, so `pl` is not
          #          merely a witness, it is the whole inflected set
          #          (`I18n.inflector.inflected_locales(:gender)` is
          #          ["all", "pl"], measured by the adversary's C12 probe) —
          #          set_grammatical_gender runs and reads the principal's
          #          profile.
          #   "xx" — a syntactically fine code that is NOT in
          #          `I18n.available_locales`; `I18n.locale=` raises.
          #   "en" — available, not inflected; the callback does nothing.
          # NULL is deliberately NOT a fourth arm: i18n treats nil as "use the
          # default" and the real run 200s (C04 control), so a nil language is
          # behaviourally the "en" arm.
          if klass.name == "User" && attrs["language"].respond_to?(:value)
            lang = attrs["language"]
            attrs["language"] = if lang == "pl"
                                  "pl"
                                elsif lang == "xx"
                                  "xx"
                                else
                                  "en"
                                end
          end
          # W4-2 / M-6 (adversary round 4): `posts.type` is the STI dispatch
          # and was a placeholder string in neither the gate list nor the pin
          # ledger — 29 087 blind mints. `t.string "type", limit: 40, null:
          # false` (schema.rb:411) has no CHECK, no FK and no application
          # validation, and `Photo` / `ActivityStreams::Photo` are ordinary
          # LEGACY row values on an upgraded pod (`lib/diaspora/shareable.rb:
          # 7-8` records that Photo and Post used to be the same class). A row
          # whose type is outside the Post STI tree makes ActiveRecord raise
          # `SubclassNotFound` while INSTANTIATING it — inside `.first`,
          # before `post.public?` and before `post.comments.for_a_stream` — so
          # the real run issues the post finder and NOTHING else (adversary
          # C06: 7 such 500s, one `posts` statement each, no comments SELECT,
          # no preloads, no exists? probes).
          #
          # This is minted HERE, in symbolic_instance, because instantiation
          # is exactly what symbolic_instance stands for and exactly where the
          # real raise happens; every post finder (anon `first`, and the three
          # `ci_*` visibility finders) inherits it for free, and the finder
          # mock has already decided `_not_found` BEFORE calling us, so a
          # finder that returns no row cannot raise — as in the real code.
          #
          # The decision is two-valued because the IN-TREE subclass choice is
          # evidence-neutral: C06 rendered `StatusMessage`, a `Reshare` with a
          # dangling `root_guid` and a `Reshare` with a real root, json and
          # mobile, anon and signed-in, and every one produced an IDENTICAL
          # statement set (`#index` never touches the post beyond `public?`
          # and `comments`). `Photo` is the out-of-tree witness.
          if klass.name == "Post" && attrs["type"].respond_to?(:value)
            out_of_tree = (attrs["type"] == "Photo")
            attrs["type"] = out_of_tree ? "Photo" : "StatusMessage"
            if out_of_tree
              next_obj = UninstantiableRow.new(
                sql, "Invalid single-table inheritance type: Photo is not a subclass of Post"
              )
            end
          end
          # PIN LEDGER `profiles.gender` — pinned CONCRETE, non-blank.
          # `set_grammatical_gender` is the only reader on this endpoint and
          # it does `current_user.gender.to_s.tr('…', '').downcase`, then
          # `unless gender.empty?` and `I18n.inflector.true_token(gender, …)`.
          # NEUTRALITY: both arms of that compare reach ONLY in-memory I18n
          # inflector lookups — no statement, no association, no difference in
          # data access; the only effect is which translation token
          # `@grammatical_gender` holds, and neither renderable format of this
          # action reads it. The EVIDENCE this column exists to produce — the
          # principal's `SELECT "profiles".* … WHERE "person_id" = ? LIMIT 1`
          # — is issued before the compare and is therefore minted on BOTH
          # arms. Pinning also keeps the value a real String: `String#tr` on a
          # `SymbolicString` returns a bare allocation of the subclass with no
          # @value, so a symbolic gender turns the callback into a wall rather
          # than a decision.
          if klass.name == "Profile" && attrs["gender"].respond_to?(:value)
            attrs["gender"] = "male"
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
      # type: obj<?>? -- the not-found arm returns nil.
      interceptor.declare_target(fm, m, kind: CallInterceptor::TARGET_FUNCTION, type: "obj<?>?", returns: finder_mock_faithful(ct, raise_on_missing: false, kind: m))
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
    # M-9 / B-8 (adversary round 5, 2026-08-29): the paired probe is GONE.
    # It existed only because a bare Ruby bool cannot carry a note, so the
    # statement had to ride a second event — which cost a phantom target
    # (`Anonymous.exists_probe`), a second producer edge for one read, and a
    # standing boundary question. The engine now offers the one-shot
    # `Thread.current[:concolic_pending_note]` channel that
    # `CallInterceptor.extract_note` reads, so the `exists?` event carries its
    # own statement and the decision var keeps the same note it always had.
    # type: bool -- returns a bare Ruby bool (`ex == true`), never nil.
    interceptor.declare_target(fm, :exists?, kind: CallInterceptor::TARGET_FUNCTION, type: "bool", returns: lambda do |receiver, args, name|
      # keyword conditions reach sql_for through the ConcolicKwargsToPositional
      # thread-local (the interceptor drops **kwargs) — rebind those too.
      prev = Thread.current[:concolic_finder_conds]
      begin
        Thread.current[:concolic_finder_conds] = CommentsTargets.rebind_text_values(prev) if prev
        note = CommentsTargets.exists_sql_for(ct, receiver, CommentsTargets.rebind_text_values(args))
      ensure
        Thread.current[:concolic_finder_conds] = prev
      end
      vn = "#{name}_exists"
      ex = symbool(vn, ct.seed_for(vn, false), note: note)
      # publish the statement for the EVENT before returning the bare bool:
      # a `true`/`false` return carries no note of its own (B-8's falsy-arm
      # class — and `true` is just as note-less as `false`).
      Thread.current[:concolic_pending_note] = note
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
    # type: obj<?>? -- a symbolic instance, or nil on the not-found / no-class arms.
    interceptor.declare_target(sa, :find_target, kind: CallInterceptor::TARGET_FUNCTION, type: "obj<?>?", returns: lambda do |receiver, _args, _name|
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
            # W3-1: same predicate the preload attach uses (see the header
            # near `mark_loaded`) — the two sites can no longer disagree.
            CommentsTargets.dangling_belongs_to?(owner, refl)
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
          if not_found == true
            # M-9 / B-8: the association load ISSUED its SELECT and got zero
            # rows; publish it before returning nil, or the statement is lost.
            Thread.current[:concolic_pending_note] = sql
            next nil
          end
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
      # type: obj<?> -- hands back the receiver record.
      interceptor.declare_target(ActiveRecord::Base, :reload, kind: CallInterceptor::TARGET_FUNCTION, type: "obj<?>", returns: lambda do |receiver, _args, _name|
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
      # ==================================================================
      # M-17 (adversary round 9, 2026-09-01) — RESOLUTION (b): THE SUCCESS ARM
      # IS NOT EXPLORED AT ALL.
      #
      # What round 9 measured: the corpus took `_discovery_failed == False`
      # (i.e. `fetch_and_save` RETURNS) in 7 272 of 26 931 dumps and asserted
      # exactly TWO statements there — `reload`'s `people … LIMIT 1` and the
      # profile `find_target` — 7 972 times each, plus a clean 200. But
      # `fetch_and_save` (discovery.rb:19-31) cannot RETURN until
      # `DiasporaFederation.callbacks.trigger(:save_person_after_webfinger,
      # person)` has completed, and diaspora's own callback
      # (config/initializers/diaspora_federation.rb:59-77) issues THIRTEEN
      # statements first — a `pods` read, `Pod.find_or_create_by`'s INSERT, a
      # `people.diaspora_handle` pluck, `people.guid`/`diaspora_handle`
      # uniqueness probes, two `tags`⋈`taggings` joins, `INSERT INTO people`,
      # `INSERT INTO profiles`, `UPDATE profiles`, inside two transactions.
      # The corpus carried 0 DML notes and no `pods`/`tags`/`taggings` note.
      # So the arm was modelled with 2 of 15 statements, and the 2 kept were
      # the LAST two. Cycle 11's claim that "no statement is asserted for that
      # arm" was false.
      #
      # WHY (b) AND NOT (a) — MODEL THE 13 STATEMENTS. Because every note in
      # this project is verified against a REAL ENDPOINT statement: that is
      # what `mock_note_check` and `note_fidelity_audit` do. Those 13
      # statements have real counterparts only as SCENARIO-BODY probes (the
      # callback invoked directly), and can never have an endpoint counterpart
      # in this environment — `fetch_and_save`'s success needs TWO live HTTP
      # fetches (discovery.rb:73 `webfinger`, :84 `hcard`, both
      # `HttpClient.get`, no local short circuit) and this JRuby/typhoeus/JFFI
      # stack SIGSEGVs on any parseable URL (measured twice: cycle-11
      # `_c11/probe_parseable.log` status 134 vs `_c11/probe_uri_hostile.log`
      # exit 0; R8 H01 probe 08 independently). Modelling them would create 13
      # permanently unverifiable note families, each needing an H6 waiver whose
      # only argument is a code reading — exactly the mechanism DISCIPLINE §14
      # forbids — and would assert WRITE semantics (T-t/T-v dirty state) that
      # no run could ever exercise.
      #
      # (b) is also the rule this batch already applied to itself in cycle 11
      # when it deleted `_k2_not_found`: THE CORPUS NEVER CLAIMS AN OUTCOME IT
      # CANNOT EXHIBIT. A single-valued decision is a phantom, so the decision
      # is gone too, not merely pinned.
      #
      # WHAT THE POLICY THEN CLAIMS, EXACTLY: it describes this endpoint's data
      # access on every path a real request in THIS environment can take. On
      # the `fix_profile` path it claims the reads that precede the wall and
      # the DiscoveryError terminal, and NOTHING after the wall. It does NOT
      # claim that discovery performs no data access — it declines to describe
      # it. The measured statement set of the undescribed arm is recorded in
      # `_c12/_discovery_gap_evidence.json` and in AGENT_RUN.md so extraction
      # or a future rig with a working HTTP adapter can union it in.
      # ==================================================================
      discovery_returns = lambda do |r, _a, name|
        base = (r.respond_to?(:concolic_base) && r.concolic_base) || name
        # No decision: in THIS environment `fetch_and_save` never returns a
        # value. The wall raises, always, and the note says what it is.
        _unused_base = base
        # B-8 / T-n: a mock that RAISES must still publish its note, or the
        # wall it stands for disappears from the corpus entirely.
        Thread.current[:concolic_pending_note] =
          "DiasporaFederation::Discovery#fetch_and_save (webfinger network wall; raises before " \
          "any data access — the success arm is NOT MODELLED, see M-17)"
        raise DiasporaFederation::Discovery::DiscoveryError,
              "concolic: webfinger discovery failed (wall: no HTTP adapter in this environment; " \
              "the success arm and its :save_person_after_webfinger statements are NOT MODELLED)"
      end
      # type: void -- the mock raises, so no return value is ever recorded.
      interceptor.declare_target(::CommentsInertDiscovery, :fetch_and_save, kind: CallInterceptor::SHIM, type: "void", returns: discovery_returns)
      # type: void -- the mock raises, so no return value is ever recorded.
      interceptor.declare_target(DiasporaFederation::Discovery::Discovery, :fetch_and_save, kind: CallInterceptor::SHIM, type: "void", returns: discovery_returns)
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
      # type: obj<?>? -- the not-found arm returns nil.
      interceptor.declare_target(fm, name, kind: CallInterceptor::TARGET_FUNCTION, type: "obj<?>?", returns: CommentsTargets.finder_mock_faithful(ct, raise_on_missing: false, kind: :first))
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
    interceptor.declare_target(fm, :devise_user_first, kind: CallInterceptor::TARGET_FUNCTION, type: "obj<?>", returns: lambda do |receiver, args, name|
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
        # type: obj<?>? -- the not-found arm returns nil.
        interceptor.declare_target(core, name, kind: CallInterceptor::TARGET_FUNCTION, type: "obj<?>?", returns: ct.finder_mock(raise_on_missing: false))
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
