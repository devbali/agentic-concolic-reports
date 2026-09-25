# frozen_string_literal: true
#
# Per-batch concolic targets — `aspect_memberships_create`.
#
# WHY THIS FILE EXISTS
# --------------------
# `AspectMembershipsController#create` is the FIRST INSERT endpoint in the
# diaspora corpus. Every previously-run endpoint (comments_index,
# conversations_index, notifications_index, people_show, people_stream,
# posts_show) is read-only, so the shared `concolic_targets.rb` has never had
# to render a DML statement for an ordinary `record.save` — its section-F
# persistence mocks return a symbolic bool with the note
# `"<Class>#save args={}"`, which is a *description*, not a statement. On a
# read endpoint that costs nothing (no save fires). Here the whole point of
# the run is the write, so this batch redeclares those same targets with a
# statement-shaped note (§2 below).
#
# Loaded AFTER `ConcolicTargets.install!`; `declare_target` uses
# `define_method`, so the last declaration for a given (class, method) wins.
#
# KIND DISCIPLINE (DESIGN_IR §4.1.1f change 9, enforced by
# `CallInterceptor::MissingKind`): every declaration below carries an explicit
# `kind:`.
#   TARGET_FUNCTION — the call is a real access: its real body issues SQL/DML.
#   SHIM            — the call exists only to let execution proceed past
#                     something the runtime cannot model; its real body
#                     issues no SQL.
# The reasoning for each is written at its declaration.
#
# WHAT IS *NOT* MOCKED, AND WHY (D7: never mock a unit whose body calls
# another declared target — doing so swallows the evidence the run is for)
# -----------------------------------------------------------------------
# `User#share_with` (app/models/user/connecting.rb:13-33) is the endpoint's
# entire write. Its body is:
#
#     return if blocks.where(person_id: person.id).exists?          # SELECT
#     contact = contacts.find_or_initialize_by(person_id: person.id) # SELECT
#     return false unless contact.valid?                             # SELECT (uniqueness + not_blocked_user)
#     needs_dispatch = !contact.receiving?
#     contact.receiving = true
#     contact.aspects << aspect                                      # INSERT aspect_memberships
#     contact.save                                                   # INSERT/UPDATE contacts
#     ... Dispatcher.defer_dispatch / deliver_profile_update         # federation, no SQL here
#     Notifications::StartedSharing.where(...).update_all(...)       # UPDATE notifications
#     contact
#
# EVERY line of that is either SQL or a call into an already-declared target.
# Mocking `share_with` as one opaque unit would erase all of it — the insert
# would never appear in a dump and the batch would prove nothing. So it runs
# for real, and this file only (a) restores the pieces the shared config
# broke for this flow (§1) and (b) gives the DML targets statement notes (§2).

require "json"

module AspectMembershipsTargets
  module_function

  # ---------------------------------------------------------------------
  # Shared note helpers (ported verbatim from
  # ../comments_index/targets.rb — adversary N7 / CHECKS.md F7 faithful
  # single-row finder statements). Kept batch-local rather than pushed into
  # the shared config: the shared copy is app-wide (Rule T) and a note-shape
  # change there restarts every endpoint.
  # ---------------------------------------------------------------------

  # Existence probe statement: `SELECT 1 AS one FROM … LIMIT 1`.
  def exists_sql_for(ct, receiver, args)
    sql = ct.sql_for(receiver, args)
    sql = sql.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT 1 AS one FROM ")
    sql = sql.sub(/\s+ORDER BY\s.*\z/m, "")
    sql =~ /\sLIMIT\s/ ? sql : "#{sql} LIMIT 1"
  rescue StandardError
    sql
  end

  # Rails' `first`/`last` order by the primary key when the relation carries
  # no order, and every single-row finder appends LIMIT 1.
  def finder_note(ct, receiver, args, kind)
    sql = ct.sql_for(receiver, args)
    table = begin
      ct.model_class(receiver).table_name
    rescue StandardError
      nil
    end
    if %i[first last].include?(kind) && table && !sql.include?(" ORDER BY ")
      pk = begin
        ct.model_class(receiver).primary_key
      rescue StandardError
        "id"
      end
      sql = %(#{sql} ORDER BY "#{table}"."#{pk}" #{kind == :last ? 'DESC' : 'ASC'})
    end
    sql = "#{sql} LIMIT 1" unless sql =~ /\sLIMIT\s/
    sql
  end

  def finder_mock_faithful(ct, raise_on_missing:, kind:)
    lambda do |receiver, args, name|
      sql = AspectMembershipsTargets.finder_note(ct, receiver, args, kind)
      nf_name = "#{name}_not_found"
      not_found = symbool(nf_name, ct.seed_for(nf_name, false), note: sql)
      if not_found == true
        # M-9 / B-8: the finder STILL RAN ITS QUERY on the miss arm, and `nil`
        # carries no note — publish it on the engine's one-shot channel so the
        # miss dump is not an empty policy.
        Thread.current[:concolic_pending_note] = sql
        raise ActiveRecord::RecordNotFound, "concolic: empty result for: #{sql}" if raise_on_missing
        next nil
      end
      ct.symbolic_instance(ct.model_class(receiver), name, sql)
    end
  end

  # ---------------------------------------------------------------------
  # DML statement rendering (NEW for this batch — the insert-endpoint work)
  # ---------------------------------------------------------------------
  # The shared section-F mock notes an instance save as
  # `"Contact#save args={}"`. That is not a statement, so the extraction's
  # `_is_dml` filter drops it and the corpus would contain NO evidence that
  # this endpoint writes. Render the real shape instead.
  #
  # Attribute source, in order of fidelity:
  #   1. `changes` — what a real (unsaved) AR record is about to write.
  #   2. `attributes` — the symbolic-instance path (ConcolicTargets
  #      .symbolic_instance overrides `attributes` to return its attrs hash,
  #      because `klass.allocate` leaves @attributes nil).
  # Both are rescued: a half-constructed record must degrade to an honest
  # "(attributes unavailable)" note, never abort the run.
  def dml_attrs(receiver)
    # (A) SYMBOLIC instance (`klass.allocate` — ActiveModel::Dirty cannot run
    #     on it, @attributes is nil). §4's wrapper records every written
    #     column on `concolic_dirty` and keeps the values in
    #     `concolic_attrs`, which are the SYMBOLIC values. Reading them from
    #     AR instead (`changes`, `attributes_before_type_cast`) returned nil
    #     and rendered `UPDATE "contacts" SET "contacts"."receiving" = nil`
    #     for `contact.receiving = true` — measured, probe run dse0003.
    if receiver.respond_to?(:concolic_dirty) && receiver.respond_to?(:concolic_attrs)
      d = begin
        receiver.concolic_dirty
      rescue StandardError
        nil
      end
      a = begin
        receiver.concolic_attrs
      rescue StandardError
        nil
      end
      return d.map { |k| [k.to_s, a[k.to_s]] }.to_h if d.is_a?(::Array) && a.is_a?(::Hash)
    end

    # (B) a REAL AR record — `contacts.find_or_initialize_by` missed and built
    #     one, or the has_many :through join row. Values come from
    #     `attributes_before_type_cast`, NEVER from `changes`: `changes`
    #     hands back the TYPE CAST value, which for a symbolic id is the
    #     plain Integer that CastableSymbolicInt#to_i produced (§4a), and the
    #     note would render `1` instead of `$$(SYM_…)` — a severed producer
    #     chain on the one statement this batch exists to record.
    raw = begin
      receiver.respond_to?(:attributes_before_type_cast) ? receiver.attributes_before_type_cast : nil
    rescue StandardError
      nil
    end

    # A new record INSERTs every attribute it carries a value for. Taking the
    # CHANGED set instead lost `aspect_memberships.aspect_id`: AR assigns the
    # join row's aspect through the ASSOCIATION
    # (has_many_through_association.rb:61 `attributes[source_reflection.name]
    # = record`), and the fk that the belongs_to writer derives from it is
    # not always in `changed_attribute_names_to_save` at save time — the
    # INSERT then named only `contact_id` (measured, probe run dse0003).
    if record_is_new?(receiver) == true && raw.is_a?(::Hash)
      return raw.reject { |_k, v| v.nil? }
    end

    names = begin
      if receiver.respond_to?(:changed_attribute_names_to_save)
        receiver.changed_attribute_names_to_save
      elsif receiver.respond_to?(:changed)
        receiver.changed
      end
    rescue StandardError
      nil
    end
    if names.is_a?(::Array) && !names.empty? && raw.is_a?(::Hash)
      return names.map { |k| [k.to_s, raw[k.to_s]] }.to_h
    end

    ch = begin
      receiver.respond_to?(:changes) ? receiver.changes : nil
    rescue StandardError
      nil
    end
    if ch.is_a?(::Hash) && !ch.empty?
      return ch.map { |k, v| [k.to_s, v.is_a?(::Array) ? v[1] : v] }.to_h
    end
    return raw.reject { |_k, v| v.nil? } if raw.is_a?(::Hash)
    at = begin
      receiver.respond_to?(:attributes) ? receiver.attributes : nil
    rescue StandardError
      nil
    end
    at.is_a?(::Hash) ? at.reject { |_k, v| v.nil? } : nil
  end

  # ---------------------------------------------------------------------
  # symbolic_attr — the symbol standing behind ONE NAMED COLUMN of a record.
  # ---------------------------------------------------------------------
  # Returns the SymbolicVar the application assigned to `record.<name>`, or
  # nil when that column holds no symbol. Used by §8 (the uniqueness-probe
  # binds) and safe for any other "AR handed me a concrete value but the
  # record still remembers the symbol" site.
  #
  # NAME-BASED BY CONSTRUCTION, NEVER VALUE-BASED. The column name is the
  # only key. A value->symbol lookup is inadmissible here: D8 (./REPORT.md)
  # is that EVERY id column seeds to the same `1`, so matching a concrete
  # value back to a symbol is ambiguous by construction and would attach the
  # WRONG name — strictly worse than the bare literal it replaced.
  #
  # Two sources, in fidelity order:
  #   1. `concolic_attrs` — a `ConcolicTargets.symbolic_instance` keeps its
  #      symbolic columns here (`klass.allocate` leaves @attributes nil, so
  #      `attributes_before_type_cast` would raise on it).
  #   2. `attributes_before_type_cast` — a REAL AR record (the
  #      `find_or_initialize_by` MISS arm builds one) keeps the value AS
  #      ASSIGNED here. §4a's whole point: `CastableSymbolicInt#to_i` feeds
  #      the type cast a concrete Integer WITHOUT concretizing the
  #      attribute, so the before-cast slot still holds the symbol.
  def symbolic_attr(record, name)
    col = name.to_s
    raw = nil
    if record.respond_to?(:concolic_attrs)
      raw = begin
        record.concolic_attrs[col]
      rescue StandardError
        nil
      end
    end
    if raw.nil? && record.respond_to?(:attributes_before_type_cast)
      raw = begin
        record.attributes_before_type_cast[col]
      rescue StandardError
        nil
      end
    end
    (raw.respond_to?(:sym_name) && raw.sym_name) ? raw : nil
  end

  # persisted? FIRST: on a symbolic instance (`klass.allocate`) @new_record is
  # nil, so `new_record?` returns nil (not false) while `persisted?` — which
  # is `!(@new_record || @destroyed)` — correctly returns true. A symbolic
  # instance always came out of a finder, i.e. out of a row the database
  # returned, so "persisted" is the right answer and its save is an UPDATE.
  def record_is_new?(receiver)
    if receiver.respond_to?(:persisted?)
      begin
        p = receiver.persisted?
        return !p unless p.nil?
      rescue StandardError
        nil
      end
    end
    begin
      n = receiver.new_record?
      return n unless n.nil?
    rescue StandardError
      nil
    end
    begin
      pk = receiver.class.primary_key
      receiver[pk].nil?
    rescue StandardError
      nil # unknown — the note says so
    end
  end

  def dml_note(ct, receiver, op)
    klass = receiver.class
    table = klass.respond_to?(:table_name) ? klass.table_name : klass.name.to_s
    attrs = dml_attrs(receiver)
    return %(#{klass.name}##{op} (attributes unavailable)) if attrs.nil?

    new_rec = record_is_new?(receiver)
    if new_rec == false
      pk = begin
        klass.primary_key
      rescue StandardError
        "id"
      end
      pkv = begin
        receiver[pk]
      rescue StandardError
        nil
      end
      sets = attrs.reject { |k, _| k.to_s == pk.to_s }
                  .map { |k, v| %("#{table}"."#{k}" = #{ct.render_arg_value(v)}) }.join(", ")
      sets = "(no changed columns)" if sets.empty?
      %(UPDATE "#{table}" SET #{sets} WHERE "#{table}"."#{pk}" = #{ct.render_arg_value(pkv)})
    else
      cols = attrs.keys.map { |k| %("#{k}") }.join(", ")
      vals = attrs.values.map { |v| ct.render_arg_value(v) }.join(", ")
      prefix = new_rec.nil? ? "/* new_record? unavailable, rendered as INSERT */ " : ""
      %(#{prefix}INSERT INTO "#{table}" (#{cols}) VALUES (#{vals}))
    end
  rescue StandardError => e
    %(#{receiver.class.name}##{op} (note render failed: #{e.class}))
  end

  # UPDATE-shaped note for `Relation#update_all` (the shared config renders
  # the relation's SELECT, which is the wrong verb for a write).
  def update_all_note(ct, receiver, args)
    sel = ct.sql_for(receiver, args)
    table = begin
      ct.model_class(receiver).table_name
    rescue StandardError
      nil
    end
    updates = nil
    if args.is_a?(::Hash)
      args.each_value do |v|
        if v.is_a?(::Hash) && !v.empty?
          updates = v
          break
        end
      end
    end
    # `update_all(unread: false)` reaches a `def update_all(updates)` — a
    # REQUIRED POSITIONAL, not a `*rest` — so Ruby 2.6 packs the trailing
    # hash into the wrapper's `**kwargs` and the interceptor's B-1 repair
    # (which only fills a named `*rest` slot) does not apply: `args` comes
    # back empty and the note read `SET (updates unavailable)` (measured,
    # probe run dse0001..4). §6's prepend stashes the real hash.
    tc = Thread.current[:concolic_update_all_values]
    updates ||= tc if tc.is_a?(::Hash) && !tc.empty?
    return sel unless table
    sets = if updates
             updates.map { |k, v| %("#{table}"."#{k}" = #{ct.render_arg_value(v)}) }.join(", ")
           else
             "(updates unavailable)"
           end
    where = sel[/\sWHERE\s.*\z/m]
    %(UPDATE "#{table}" SET #{sets}#{where})
  rescue StandardError
    ct.sql_for(receiver, args)
  end

  # ---------------------------------------------------------------------

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    # Lazily-loaded classes this batch's targets name.
    %w[aspect_membership aspect contact block person notification
       notifications/started_sharing].each do |f|
      path = File.join(Rails.root, "app/models", "#{f}.rb")
      next unless File.exist?(path)
      begin
        require_relative path
      rescue LoadError, StandardError => e
        warn "[am_create] could not load #{path}: #{e.class} #{e.message[0, 80]}"
      end
    end
    begin
      require_relative File.join(Rails.root, "lib/diaspora/federation/dispatcher.rb")
    rescue LoadError, StandardError => e
      warn "[am_create] could not load dispatcher: #{e.class}"
    end

    fm  = ActiveRecord::FinderMethods
    rel = ActiveRecord::Relation

    # =====================================================================
    # §0. Faithful finder / existence statements (note fidelity only — the
    #     shared declarations already exist, these change what they record,
    #     not what they return).
    # =====================================================================
    # KIND: TARGET_FUNCTION. These ARE the accesses: `Person.find`,
    # `current_user.aspects.where(id:).first`,
    # `AspectMembership.where(contact_id:, aspect_id:).first`,
    # `contacts.find_or_initialize_by(person_id:)` all bottom out here and
    # each issues a real SELECT.
    %i[first last take find_by].each do |m|
      # type: obj<?>? -- the not-found arm returns nil.
      interceptor.declare_target(fm, m, kind: CallInterceptor::TARGET_FUNCTION, type: "obj<?>?",
                                        returns: finder_mock_faithful(ct, raise_on_missing: false, kind: m))
    end
    %i[first! last! find_by!].each do |m|
      interceptor.declare_target(fm, m, kind: CallInterceptor::TARGET_FUNCTION, type: "obj<?>",
                                        returns: finder_mock_faithful(ct, raise_on_missing: true, kind: m))
    end

    # `blocks.where(person_id:).exists?` (share_with line 14) and
    # `user.blocks.where(person_id:).exists?` (Contact#not_blocked_user) are
    # this endpoint's two existence probes. `if … .exists?` is bare
    # truthiness, so the mock records the compare itself and returns a
    # concrete bool; the statement rides the one-shot note channel.
    # KIND: TARGET_FUNCTION — a real `SELECT 1 AS one … LIMIT 1`.
    #
    # RETURNING `nil`, NOT `false`, ON THE NEGATIVE ARM — see the FINDING in
    # ./REPORT.md ("bare `false` from a mock is truthy").
    # `CallInterceptor`'s body-skip path runs every plain native return
    # through `to_symbolic` (symbolic_func.rb:359), and
    # `to_symbolic(false)` is `SymbolicBool.new(false)` — a Ruby OBJECT, and
    # every Ruby object except `false`/`nil` is TRUTHY. So a mock that means
    # "no" hands the application a truthy value, and
    #   return if blocks.where(person_id: person.id).exists?   # connecting.rb:14
    # returned UNCONDITIONALLY: share_with always returned nil, @contact was
    # always blank, and every run took the 409 arm. Measured, not inferred —
    # dump_auth_json_dse0001.json of the second trial reached
    # `ActionController::Metal#status= 409` with no contacts SELECT and no
    # write of any kind after the blocks probe, and a standalone runtime
    # probe (no Rails) reproduces it in four lines.
    #   `to_symbolic(nil)` is the one native that passes through unchanged
    # ("nil means absent — pass through unchanged"), so the negative arm
    # returns nil and the positive arm returns `true` (truthy either way it
    # is wrapped). The DECISION is unaffected — it is recorded on `<name>
    # _exists` by the explicit compare above, before the return — and the
    # STATEMENT still rides the event through the one-shot note channel.
    # COST: `check_returns_symbol!` books a TOTALITY_GAP for the nil return
    # (TOTALITY is false, so it does not raise). That is the honest trade:
    # a booked gap versus a foreclosed branch.
    # type: bool? -- the negative arm returns nil, not false (see the note above).
    interceptor.declare_target(fm, :exists?, kind: CallInterceptor::TARGET_FUNCTION, type: "bool?", returns: lambda do |receiver, args, name|
      note = AspectMembershipsTargets.exists_sql_for(ct, receiver, args)
      vn = "#{name}_exists"
      ex = symbool(vn, ct.seed_for(vn, false), note: note)
      Thread.current[:concolic_pending_note] = note
      (ex == true) ? true : nil
    end)

    # =====================================================================
    # §1. Restore `User#blocks` as a REAL relation for this flow.
    # =====================================================================
    # The shared config declares `User#blocks` returning a SymbolicList (it
    # exists for `Post.excluding_blocks`'s `user.blocks.map{…}` on the stream
    # endpoints — design rows 1-3). `share_with` and `Contact
    # #not_blocked_user` do NOT map it: they chain
    # `blocks.where(person_id: …).exists?`, and `SymbolicList#where` is a
    # NoMethodError that kills the run before any write is reached.
    #
    # Returning the REAL association reader is strictly MORE evidence, not
    # less: the `where(...).exists?` then renders a genuine
    # `SELECT 1 AS one FROM "blocks" WHERE "blocks"."user_id" = $$(…) AND
    # "blocks"."person_id" = $$(…) LIMIT 1` at the §0 exists? target, instead
    # of the shared mock's hand-rolled `SELECT "blocks".*` note.
    #
    # KIND: SHIM. `association(:blocks).reader` builds a CollectionProxy and
    # issues NOTHING — the access happens downstream at `exists?`, which is
    # its own declared TARGET_FUNCTION. Per change 9 a call that is not
    # itself an access is a shim, and only a shim is exempt from
    # `check_returns_symbol!` (the return here is an AR proxy, not a symbol).
    if defined?(User)
      # type: [?] -- the real association reader hands back an AR CollectionProxy.
      interceptor.declare_target(User, :blocks, kind: CallInterceptor::SHIM, type: "[?]", returns: lambda do |receiver, _args, _name|
        receiver.association(:blocks).reader
      end)
    end

    # =====================================================================
    # §2. DML statement notes (the insert evidence).
    # =====================================================================
    # KIND: TARGET_FUNCTION for all of these — they are the writes this
    # endpoint exists to perform. `contact.save` is an INSERT (or UPDATE) on
    # `contacts`; the `contact.aspects << aspect` through-association writes
    # its join row via the same `save!` boundary; `update_all` is a real
    # UPDATE on `notifications`.
    base = ActiveRecord::Base
    %i[save save! update update! update_attribute touch destroy destroy!].each do |m|
      next unless base.instance_methods.include?(m) ||
                  base.private_instance_methods.include?(m) ||
                  base.protected_instance_methods.include?(m)
      interceptor.declare_target(base, m, kind: CallInterceptor::TARGET_FUNCTION, type: "bool", returns: lambda do |receiver, args, name|
        note = if %i[destroy destroy!].include?(m)
                 begin
                   t = receiver.class.table_name
                   pk = receiver.class.primary_key
                   %(DELETE FROM "#{t}" WHERE "#{t}"."#{pk}" = #{ct.render_arg_value(receiver[pk])})
                 rescue StandardError
                   "#{receiver.class.name}##{m}"
                 end
               else
                 AspectMembershipsTargets.dml_note(ct, receiver, m)
               end
        vn = "#{name}_#{m}_ok"
        # Seeded true: a failing write is a validation outcome, and the two
        # validation decisions this endpoint actually branches on
        # (`contact.valid?`, `@contact.present?`) are recorded at their own
        # boundaries. Kept a DECISION (not pinned) so DSE can flip it.
        symbool(vn, ct.seed_for(vn, true), note: note)
      end)
    end

    %i[update_all delete_all].each do |m|
      interceptor.declare_target(rel, m, kind: CallInterceptor::TARGET_FUNCTION, type: "int", returns: lambda do |receiver, args, name|
        note = if m == :update_all
                 AspectMembershipsTargets.update_all_note(ct, receiver, args)
               else
                 begin
                   sel = ct.sql_for(receiver, args)
                   t = ct.model_class(receiver).table_name
                   %(DELETE FROM "#{t}"#{sel[/\sWHERE\s.*\z/m]})
                 rescue StandardError
                   ct.sql_for(receiver, args)
                 end
               end
        symint("#{name}_#{m}_count", 1, note: note)
      end)
    end

    # =====================================================================
    # §3. Federation walls.
    # =====================================================================
    # KIND: SHIM for both. Neither issues SQL on this path: `defer_dispatch`
    # builds a `Diaspora::Federation::Dispatcher` and hands it to Sidekiq
    # (Sidekiq::Client#push is already a shared SHIM), and
    # `User#deliver_profile_update` is a one-line delegation to it. They are
    # walls — the runtime cannot model the federation entity graph — not
    # accesses. NOTE: `deliver_profile_update` reads `self.profile`, an
    # association load that WOULD be an access; shimming the outer method
    # elides it. That elision is recorded in the report as a known cost: the
    # alternative (letting it run) drags the whole federation entity
    # validation chain in, which is a documented wall on every batch.
    if defined?(Diaspora::Federation::Dispatcher)
      # type: str? -- the real defer_dispatch returns perform_async's job id; mock records null.
      interceptor.declare_target(Diaspora::Federation::Dispatcher.singleton_class, :defer_dispatch,
                                 kind: CallInterceptor::SHIM, type: "str?", returns: ->(_r, _a, _n) { nil })
    end
    if defined?(User) && User.method_defined?(:deliver_profile_update)
      # type: str? -- delegates to defer_dispatch (a job id); this mock records null.
      interceptor.declare_target(User, :deliver_profile_update,
                                 kind: CallInterceptor::SHIM, type: "str?", returns: ->(_r, _a, _n) { nil })
    end

    # =====================================================================
    # §4. Principal-column domains for the before_action chain.
    # =====================================================================
    # Ported from ../../results3/comments_index/targets.rb §4 (N3-1 / W4-1 /
    # Rule G). This is NOT new modelling — it is the SAME two columns, on the
    # SAME devise principal, reached by the SAME two ApplicationController
    # callbacks, and this endpoint is signed-in ONLY, so unlike comments#index
    # there is no anonymous arm that skips them. Without it the very first
    # run of this batch died at
    #   i18n.rb:382 enforce_available_locales! -> SymbolicString#!=(false)
    #   -> NotImplementedError, 0 PCs, 2 events
    # (recorded: dump_auth_json_dse0001.json of the first trial, since
    # overwritten).
    #
    # users.language — THREE arms, the domain measured by the comments_index
    # adversary (round 4, W4-1/M-5):
    #   "pl" — available AND inflected (config/locales/inflections/pl.yml is
    #          the app's only inflected locale), so set_grammatical_gender
    #          runs and reads the principal's profile:
    #          SELECT "profiles".* WHERE "person_id" = ? LIMIT 1
    #   "xx" — syntactically fine, NOT in I18n.available_locales;
    #          `I18n.locale=` raises I18n::InvalidLocale before the action
    #          body — the run issues exactly the users SELECT and 500s.
    #   "en" — available, not inflected; the callback does nothing.
    # NULL is not a fourth arm: i18n reads nil as "use the default", which is
    # behaviourally the "en" arm.
    #
    # profiles.gender — PIN LEDGER, pinned "male". Both arms of the
    # `gender.empty?` compare reach only in-memory I18n inflector lookups: no
    # statement, no association, no difference in data access. The EVIDENCE
    # the column exists to produce (the principal's profiles SELECT) is
    # issued BEFORE the compare and is minted on both arms. Pinning also
    # keeps the value a real String — `String#tr` on a SymbolicString returns
    # a bare subclass allocation with no @value, turning the callback into a
    # wall instead of a decision.
    # =====================================================================
    # §4a. CastableSymbolicInt — VALUE fix for the BUILD-A-NEW-RECORD wall.
    # =====================================================================
    # This is the wall that actually stood between this batch and the
    # insert. When `contacts.find_or_initialize_by(person_id: person.id)`
    # MISSES (the `find_by_1_not_found == True` arm — i.e. exactly the state
    # in which this endpoint creates a row), AR builds a REAL Contact and
    # assigns the symbolic person id to an integer attribute:
    #
    #   associations/association.rb:285  build_record
    #     -> :182 initialize_attributes
    #     -> dirty.rb:114 changed_attribute_names_to_save
    #     -> attribute_mutation_tracker.rb:15/49 changed?
    #     -> attribute.rb:156 changed_from_assignment? -> :42 value
    #     -> type/integer.rb:47 cast_value -> value.to_i
    #     -> NotImplementedError: SymbolicInt#to_i   (int.rb:35)
    #
    # Measured: runs 7, 20 and 35 of the 40-run pass, all three carrying the
    # `find_by_1_not_found = true` seed. The enclosing methods CANNOT be
    # mocked — `find_or_initialize_by`'s body issues the SELECT and holds the
    # found/not-found branch, and `build_record` is AR's own attribute
    # assignment — so the fix belongs on the VALUE, exactly as
    # ../../results3/comments_index/targets.rb §5 put `#next` on
    # `SuccIntValue` rather than mocking `update_or_create_participation!`.
    #
    # WHAT IT DOES AND DOES NOT CONCEDE. `#to_i` returns the concrete value,
    # so ActiveModel's *type cast* sees an Integer. It does NOT concretize
    # the attribute: AR keeps the assigned object in
    # `attributes_before_type_cast`, the cast result is used only for the
    # dirty comparison, and §2's `dml_attrs` reads the BEFORE-TYPE-CAST value
    # so the INSERT note still renders `$$(SYM_…)`. Comparisons, arithmetic
    # and naming are untouched — `CastableSymbolicInt` adds one method to
    # `SymbolicInt` and inherits everything else, reusing the SAME var name,
    # value and note, so symbolic identity is preserved exactly.
    unless defined?(CastableSymbolicInt)
      ::Object.const_set(:CastableSymbolicInt, Class.new(SymbolicInt) do
        def to_i
          value
        end
        alias_method :to_int, :to_i
      end)
    end

    unless ct.respond_to?(:symbolic_instance_without_am_principal_domains)
      class << ConcolicTargets
        alias_method :symbolic_instance_without_am_principal_domains, :symbolic_instance

        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_without_am_principal_domains(klass, base_name, sql)
          return obj unless obj.respond_to?(:concolic_attrs)
          attrs = obj.concolic_attrs

          # DIRTY TRACKING for the DML notes (§2). The shared
          # symbolic_instance overrides the attribute writers to poke the
          # attrs hash directly (ActiveModel::Dirty cannot run on an
          # allocated record), which loses WHICH columns the app assigned.
          # Re-wrap them to remember. Behaviour is otherwise identical.
          dirty = []
          obj.define_singleton_method(:concolic_dirty) { dirty }
          %i[write_attribute _write_attribute []=].each do |w|
            obj.define_singleton_method(w) do |k, v|
              ks = k.to_s
              dirty << ks unless dirty.include?(ks)
              attrs[ks] = v
            end
          end
          # ActiveModel::Dirty cannot run on `klass.allocate` (@attributes is
          # nil, so `mutations_from_database` builds an AttributeMutationTracker
          # over nil and `any_changes?` raises). AR asks for it on the WRITE
          # path this endpoint takes:
          #   has_many_through_association.rb:41
          #     if record.new_record? || record.has_changes_to_save?
          # reached from `contact.aspects << aspect` (connecting.rb:21).
          # `new_record?` is nil on an allocated record, so the second half
          # IS evaluated. Answer it from the dirty set we now maintain —
          # which is the truthful answer: a symbolic instance came out of a
          # finder with no pending changes, and has some exactly when the
          # application assigned one.
          obj.define_singleton_method(:has_changes_to_save?) { !dirty.empty? }
          obj.define_singleton_method(:changed?)             { !dirty.empty? }
          obj.define_singleton_method(:changed)              { dirty.dup }

          # §4a wiring: re-wrap every integer column as a CastableSymbolicInt,
          # reusing the SAME var name, value and note (identical symbolic
          # identity, one extra method). Same technique and same rationale as
          # ../../results3/comments_index/targets.rb's SuccIntValue wiring.
          klass.columns_hash.each do |col, meta|
            next unless %i[integer bigint].include?(meta.type)
            old = attrs[col]
            next unless old.is_a?(SymbolicInt) && !old.is_a?(CastableSymbolicInt)
            v = CastableSymbolicInt.new(old.value, name: old.sym_name, note: old.note)
            attrs[col] = v
            obj.define_singleton_method(col) { v }
          end
          if klass.name == "User" && attrs["language"].respond_to?(:value)
            lang = attrs["language"]
            # The two compares below ARE the decision — they record the PCs
            # on the column's own var before it is concretized.
            attrs["language"] = if lang == "pl"
                                  "pl"
                                elsif lang == "xx"
                                  "xx"
                                else
                                  "en"
                                end
            obj.define_singleton_method(:language) { attrs["language"] }
          end
          if klass.name == "Profile" && attrs["gender"].respond_to?(:value)
            attrs["gender"] = "male"
            obj.define_singleton_method(:gender) { attrs["gender"] }
          end
          obj
        end
      end
    end

    # =====================================================================
    # §5. `Model.find(id)` must render its id as a BIND, not a literal.
    # =====================================================================
    # MEASURED CLASS-S MIS-SHAPE. `Person.find(params[:person_id])` — the
    # endpoint's first statement and one of its two policy parameters —
    # rendered as
    #     SELECT "people".* FROM "people" WHERE "people"."id" = '5'
    # in all 32 dumps of the 40-run pass, while the SIBLING parameter came
    # out right (`"aspects"."id" = $$(SYM_PARAM_aspect_id)`). The difference
    # is where the value is read from: the aspects note is rendered from the
    # relation's Arel binds (`render_relation_sql`), which still hold the
    # symbolic object, whereas a class-level finder note is rendered from the
    # mock's `args` — and the interceptor builds `call_args` with
    # `to_native(raw)` (call_interceptor.rb, §5.6 "it replaces a symbolic
    # value with its concrete value and the identity is gone"). The mock
    # lambda never sees the symbol, so `render_arg_value` has nothing to
    # render as a bind. The dump EVENT keeps the identity in `arg_terms`;
    # only the note loses it. (Reported, not patched in src_new/.)
    #
    # `ConcolicTargets.extract_finder_where` already consults
    # `Thread.current[:concolic_finder_conds]` BEFORE its primary-key
    # fallback — the channel the kwargs-binding gap (B-1) left behind. Fill
    # it with the value AS PASSED. Prepending to the module puts this ahead
    # of the `define_method` that `declare_target` installed there, so it
    # runs first and `super` reaches the mock.
    #
    # STRICTLY ADDITIVE: a concrete id renders exactly as before, and the
    # thread-local is restored on the way out so the dynamic extent of one
    # finder cannot leak conditions into another statement's note.
    # PREPEND TARGET: `ActiveRecord::Base.singleton_class`, NOT
    # `Core::ClassMethods`. `Core::ClassMethods` reaches a model through
    # `ActiveSupport::Concern`'s `base.extend`, i.e. `singleton_class.include`
    # — and on Ruby 2.6 semantics (JRuby 9.3) a `prepend` applied to a module
    # AFTER it has been included is NOT retroactive, so prepending there is a
    # silent no-op (measured: the note still read `"people"."id" = '5'`).
    # `#<Class:ActiveRecord::Base>` is in every model's singleton ancestry
    # ahead of the included `Core::ClassMethods`, so `super` still reaches
    # the declared mock.
    unless ActiveRecord::Base.singleton_class < AmClassFinderBindNaming
      ActiveRecord::Base.singleton_class.prepend(AmClassFinderBindNaming)
    end

    # =====================================================================
    # §7. `SingularAssociation#writer` must WRITE THE FOREIGN KEY.
    # =====================================================================
    # The shared config's W1 mock (concolic_targets.rb, "Crash-free walls
    # round 2") no-ops the belongs_to writer and returns the record, on the
    # stated grounds that "the in-memory foreign-key write is not needed for
    # concolic coverage". That is true of every endpoint the corpus has run
    # so far, because they are all reads. It is FALSE HERE, and measurably:
    # AR attaches the join row's aspect through the ASSOCIATION
    #   has_many_through_association.rb:61
    #     attributes[source_reflection.name] = record   # :aspect => <Aspect>
    # so `aspect_memberships.aspect_id` is set ONLY by the belongs_to writer
    # deriving it from the record. With W1 in force the column is never
    # written and the join-row INSERT came out as
    #     INSERT INTO "aspect_memberships" ("contact_id") VALUES ($$(…))
    # — a Class-S mis-shape on the endpoint's defining statement, missing
    # the very column that says WHICH ASPECT the contact was added to
    # (measured, probe run dse0003; a `SingularAssociation#writer` event sits
    # immediately before that INSERT in the trace).
    #
    # W1's own justification was the `SymbolicInt#to_i` cast crash in
    # `replace_keys`. §4a removes that cause: every integer column is now a
    # CastableSymbolicInt. So the writer can do the real key write again.
    #
    # KIND: NOT A TARGET AT ALL ANY MORE — a plain `prepend`. It was a
    # SHIM (an in-memory attribute assignment, no SQL; the access is the
    # save that follows, which is its own TARGET_FUNCTION, §2), and the
    # change below does not alter one byte of what it DOES.
    #
    # ---------------------------------------------------------------------
    # 2026-09-24 — WHY THIS STOPPED BEING A `declare_target` SHIM
    # ---------------------------------------------------------------------
    # `src_new`'s dump-IR now REQUIRES provenance (`concolic/model/origin.py`,
    # `concolic/model/provenance.py` R2): a `symbolic_call` whose declared
    # `result_type` is structured (`obj<…>`, `[T]`) must have its parts
    # declared as relations to the symbol minted for that call —
    #     origin: {"kind": "attr", "of": "<result symbol>", "name": "<field>"}
    # — and the interceptor emits exactly those, by WALKING THE RETURNED
    # VALUE'S OWN STRUCTURE (`CallInterceptor.declare_result_structure`).
    #
    # This mock is an IDENTITY: it writes the foreign key and hands BACK THE
    # ARGUMENT, `record`. Nothing is produced. So the walk finds a value
    # whose attribute symbols ALREADY carry an origin — they are attributes
    # of the symbol that value was BUILT under (here
    # `SYM_RESULT_ActiveRecord__FinderMethods_first_1`, the aspect finder) —
    # and `declare_result_structure` correctly leaves them alone ("first
    # producer wins"). The result is a freshly minted symbol
    # `SYM_RESULT_…SingularAssociation_writer_1`, typed `obj<?>` because the
    # value has `concolic_attrs`, that NOTHING IN THE RUN EVER DECLARES A
    # PART OF — and `dumps_to_policy.build.build_policy` refuses the dump:
    #
    #   BuildError: run 'auth_json_dse0001': events[32]
    #   (ActiveRecord::Associations::SingularAssociation#writer) returns
    #   obj<?> as 'SYM_RESULT_…_writer_1', and NOT ONE symbol in this run
    #   declares itself an attribute of it.
    #
    # THE RULE IS RIGHT AND THE MOCK WAS WRONG TO BE A TARGET. Measured over
    # all four `write_path/` dumps: that minted symbol occurs EXACTLY TWICE
    # in each dump — as `events[N].result_name` and as its own
    # `symbolic_results` entry — and NOWHERE ELSE. No path condition, no
    # later argument, no note refers to it. That is not an accident of this
    # corpus: `obj.assoc = value` evaluates to `value` in Ruby whatever the
    # writer returns, and AR's own caller (`assign_attributes` ->
    # `_assign_attribute` -> `public_send("#{k}=", v)`) discards it. The run
    # never looks inside this return value, and the fields it DOES read off
    # the aspect it reads off the aspect's own symbol, where they have real,
    # checked origins.
    #
    # So the honest recording of this call is NO EVENT: an interception that
    # mints a symbol standing for a value another event already produced
    # states a fact the IR has no way to make true. `origin` has four kinds
    # (`attr`, `elem`, `result`, `input`) and none of them says "this symbol
    # IS that symbol"; `declare_target` has no pass-through/alias form (the
    # only `returns:` convention is `[value, sort]`); and re-declaring the
    # record's attributes under the new name raises `TypeConflict`
    # ("an origin … has exactly one answer", `SymbolicFunc.declare_var`).
    # Recommended generic fix, NOT applied here because `src_new` is
    # separately owned: see ./POLICY_EXAMPLE.md, "The interceptor gap".
    #
    # A `prepend` keeps the real effect (the foreign key write, D4) and
    # removes only the fabricated symbol. It also retires the RE-DECLARATION
    # ARG-NAME defect below for free: a prepended `writer(record)` is a real
    # method with a real parameter, so `record` is the Aspect, never nil.
    #
    # NOTE ON W1: the shared wall `concolic_targets.rb` W1 still calls
    # `declare_target(SingularAssociation, :writer, …)`. That declaration is
    # now INERT for this batch and is left untouched on purpose (it is the
    # shared wall text; see the re-sync defect in MEMORY). `declare_target`
    # installs its wrapper with `klass.define_method`, i.e. ON THE CLASS, and
    # a PREPENDED module sits ahead of the class in the ancestor chain — so
    # `AmSingularAssociationWriterFk#writer` wins, never calls `super`, and
    # the W1 wrapper is never entered. Verified in the regenerated dumps: no
    # `SingularAssociation#writer` event, in any of the ten.
    if defined?(ActiveRecord::Associations::SingularAssociation) &&
       !(ActiveRecord::Associations::SingularAssociation <
         AmSingularAssociationWriterFk)
      ActiveRecord::Associations::SingularAssociation
        .prepend(AmSingularAssociationWriterFk)
    end

    # §6. Same shape, same cause, for `Relation#update_all(updates)` — the
    # endpoint's UPDATE on `notifications`. See update_all_note above.
    if !(ActiveRecord::Relation < AmUpdateAllValueNaming)
      ActiveRecord::Relation.prepend(AmUpdateAllValueNaming)
    end

    # =====================================================================
    # §8. The uniqueness probe must bind SYMBOLS, not the cast Integers.
    # =====================================================================
    # MEASURED CLASS-S MIS-SHAPE — the LAST bare-literal key comparison in
    # the corpus. On the `find_or_initialize_by` MISS arm (the arm that
    # actually writes), `contact.valid?` runs `validates :person_id,
    # uniqueness: {scope: :user_id}` (app/models/contact.rb:13) and the
    # probe it issues rendered
    #     SELECT 1 AS one FROM "contacts"
    #      WHERE "contacts"."person_id" = 1 AND "contacts"."user_id" = 1
    #      LIMIT 1
    # — two concrete `1`s where both of this endpoint's producer chains
    # belong (write_path/dump_0001,0002).
    #
    # THE REAL MECHANISM (probed, not inferred — activerecord-5.2.4.3
    # validations/uniqueness.rb:19-96). The validator reads its values
    # through AR's TYPE-CAST pipeline, twice, and NEITHER read is the mock's:
    #
    #   ActiveModel::EachValidator#validate
    #     value = record.read_attribute_for_validation(:person_id)
    #       -> the generated reader -> @attributes.fetch_value
    #       -> ActiveModel::Type::Integer#cast -> CastableSymbolicInt#to_i
    #       -> 5                                     # plain Integer
    #   UniquenessValidator#validate_each(record, :person_id, 5)
    #     build_relation -> predicate_builder.build_bind_attribute("person_id", 5)
    #       -> QueryAttribute(value_before_type_cast: 5)
    #       -> connection.case_sensitive_comparison -> table[:person_id].eq(qa)
    #     scope_relation
    #       scope_value = record._read_attribute(:user_id) -> 1
    #       relation.where(user_id: 1)
    #
    # By the time `FinderMethods#exists?` (§0) renders the note from the
    # relation's binds, `value_before_type_cast` IS the cast Integer: the
    # symbol was lost one and two frames EARLIER, at the two reads above.
    # PROBED on the real record (`u.contacts.new(person_id: <sym>)`):
    #   attributes_before_type_cast -> {"user_id"=><SymInt SYM_USER_id=1>,
    #                                   "person_id"=><SymInt …=5>}
    #   read_attribute_for_validation(:person_id) -> 5
    #   _read_attribute(:user_id)                 -> 1
    # The record still holds BOTH symbols. Only the readers drop them.
    #
    # WHY THE FIX IS HERE AND NOT FURTHER DOWN. Three layers were tried:
    #   (1) render the note from the record instead of the relation —
    #       `exists?` is a RELATION-receiver target; the validator's
    #       relation is `Contact.unscoped.where!(…)`, an object with no back
    #       pointer to the record that built it. Unreachable from the mock.
    #   (2) map each rendered bind back to a symbol — REFUSED, and would be
    #       wrong: see `symbolic_attr`'s header (D8, every id seeds to 1).
    #   (3) hand the validator the symbol it is entitled to. Probed that the
    #       rest of the chain already carries a symbol end-to-end:
    #         table[:person_id].eq(build_bind_attribute("person_id", <sym>))
    #           -> "… "person_id" = $$(p0)"     (the build_relation shape)
    #         Contact.unscoped.where(person_id: <sym>)
    #           -> "… "person_id" = $$(p0)"     (the scope_relation shape)
    #       Both already render as binds today. The ONLY broken link is the
    #       two reads, so that is the only thing replaced.
    #
    # WHAT IT DOES NOT CHANGE — this is a RENDERING fix and must not move a
    # branch. `validate_each` is entered with the same record on the same
    # paths (the `allow_nil`/`allow_blank` skip in `EachValidator#validate`
    # is evaluated on the READER's value, untouched); `build_relation`'s one
    # value-dependent branch is `value.nil?`, and a symbol is substituted
    # only where the record HAS one, so nil stays nil; the enum remap is
    # skipped for any enum-backed column (a symbol is not a key of
    # `defined_enums`, so remapping would silently nil the value); and
    # `relation.exists?` is the §0 mock, whose answer comes from the
    # `<name>_exists` seed and never from the relation's contents. Verified:
    # same 4 runs, same 4 paths, same PCs.
    #
    # KIND: NOT A TARGET — a plain `prepend`, same standing as §7. It mints
    # no symbol and records no decision; it only restores the identity of a
    # value the application had already computed.
    if defined?(ActiveRecord::Validations::UniquenessValidator) &&
       !(ActiveRecord::Validations::UniquenessValidator <
         AmUniquenessSymbolicBinds)
      ActiveRecord::Validations::UniquenessValidator
        .prepend(AmUniquenessSymbolicBinds)
    end

    # =====================================================================
    # §9. `?` PLACEHOLDERS AND COLLECTED BINDS MUST BE THE SAME LIST.
    # =====================================================================
    # MEASURED CLASS-S MIS-ATTRIBUTION, and the cause of the LAST wrong
    # value in this endpoint's uniqueness probe (./REPORT.md §5 open item 4,
    # "`"contacts"."user_id" = nil` … undiagnosed"). §8 above restored the
    # symbol on BOTH sides of that probe, and the persisted arm STILL
    # rendered
    #     … "person_id" = $$(p0) AND "id" IS NOT NULL AND "user_id" = nil
    # with `SYM_…_find_by_1_user_id` sitting right there on the record.
    #
    # THE MECHANISM — `ConcolicTargets.render_relation_sql` builds the note
    # in two INDEPENDENT passes and zips them positionally:
    #   pass 1  visitor.accept(ast, SQLString)   -> "?" per emitted bind
    #   pass 2  collect_binds(ast, binds)        -> every BindParam in the tree
    #   zip     sql.gsub("?") { render_bind_value(binds[i]); i += 1 }
    # The two lists are NOT the same length. activerecord-5.2.4.3's
    # `PredicateBuilder#build_bind_attribute` wraps EVERY hash condition in a
    # BindParam — INCLUDING a nil one (`where.not(id: nil)`, which
    # `UniquenessValidator#validate_each` adds for a persisted record) —
    # while arel-9's `visit_Arel_Nodes_Equality`/`NotEqual` short-circuit a
    # bind whose `nil?` is true (`Arel::Nodes::BindParam#nil?` delegates to
    # `ActiveRecord::Relation::QueryAttribute#nil?`) and emit `IS NULL` /
    # `IS NOT NULL` with NO placeholder. Probed on the exact relation:
    #     … "person_id" = ? AND "id" IS NOT NULL AND "user_id" = ?
    #     qmarks = 2   collected = 3
    #     bind0 person_id=<sym>   bind1 id=nil   bind2 user_id=<sym>
    # So `?`#2 (user_id's) consumed bind1 — the NIL id — and rendered `nil`,
    # and the user_id symbol fell off the end. EVERY bind after the first
    # nullable condition is shifted onto the wrong value. It is luck, not
    # design, that the shifted slot here held nil rather than another
    # column's symbol: the same shift renders `$$(<wrong producer>)`, which
    # is a SILENT mis-chaining, the worst outcome in this corpus.
    # Second instance in the same dumps, same cause:
    #   AspectMembership.where(contact_id: <nil>, aspect_id: <sym>)
    #     -> "contact_id" IS NULL AND "aspect_id" = nil   (14 notes/dump)
    #
    # THE FIX — stop guessing the correspondence and take it from the one
    # place that knows: the collector. `Arel::Visitors::ToSql
    # #visit_Arel_Nodes_BindParam` is the ONLY producer of a placeholder,
    # and it calls `collector.add_bind(o.value) { "?" }`. Substituting there
    # makes the mapping exact by construction — one bind, one rendered
    # value, in emission order — and it also removes a second latent bug in
    # the `gsub("?")` zip: a literal `?` inside a quoted SQL string (a LIKE
    # pattern, a JSON value) consumed a bind and shifted the rest.
    #
    # WHY HERE AND NOT IN `concolic_targets.rb`: that file is this batch's
    # PRIVATE, byte-identical copy of `../comments_index/concolic_targets.rb`
    # (./REPORT.md §3) and the re-sync defect in MEMORY is exactly what
    # happens when a local definition is edited into such a copy. Overriding
    # from this file is the same technique §4a uses for `symbolic_instance`.
    # Nothing about WHICH values are bound changes — only which rendered
    # text each one lands in.
    unless ct.respond_to?(:render_relation_sql_without_am_bind_alignment)
      class << ConcolicTargets
        alias_method :render_relation_sql_without_am_bind_alignment,
                     :render_relation_sql

        def render_relation_sql(rel)
          return "#{rel.class.name} (no arel)" unless rel.respond_to?(:arel) && rel.arel

          visitor = ConcolicSymbolicToSql.new(rel.connection)
          visitor.accept(rel.arel.ast, AmBindSubstitutingCollector.new).value
        end
      end
    end


    # =====================================================================
    # §R. THE ROW IS A NAMED VALUE OF A FIXED TYPE (2026-09-25).
    # =====================================================================
    # DESIGN_IR §5.2 / §4.1.1c, and src_new/TODO.txt's "THE DIASPORA ROW
    # MOCKS DO NOT EXPOSE `concolic_name`" item.
    #
    # `ConcolicTargets.symbolic_instance` already builds a row's whole
    # attribute set out of `klass.columns_hash`. What it never did was SAY
    # SO, and three separate facts were lost as a result:
    #
    #   * `concolic_name` — `CallInterceptor.symbol_name_of` asks for it.
    #     Without it a row that is the ELEMENT of a SymbolicList has no
    #     symbol for the `elem` relation to point at, so the interceptor
    #     declares NOTHING rather than inventing a name. (TODO.txt measured
    #     this on comments_index dump 5: declared origins 12 -> 23.)
    #   * `concolic_type_name` — `CallInterceptor.observed_type_of` reads
    #     it. Without it a row the runtime can enumerate every attribute of
    #     still types as `obj<?>`: §5.2's fixed attribute set evaporating
    #     between the mock that knows it and the dump that records it. Every
    #     `attr` origin in results4 (1 155 of them, measured) therefore
    #     pointed at an UNFIXED parent, and §5.2's contract — "an `attr`
    #     origin names a field INSIDE the declared set" — had nothing on
    #     disk to bind to. `concolic/model/tests/test_dump_ir_corpus.py
    #     ::test_every_attr_origin_names_a_field_inside_its_fixed_set`
    #     skipped for exactly this reason.
    #   * `SymbolicFunc.register_type` — the per-dump type table (§5.2) is
    #     what makes `obj<Block>` a CONTRACT ("these are the attributes")
    #     instead of a label. Declared ONCE per type, not once per row.
    #
    # ALL THREE ARE METADATA. No path condition, no seeded value and no
    # rendered statement passes through any of them; they name and type
    # symbols `symbolic_instance` had already minted. The attribute TYPES
    # come from the same `columns_hash[col].type` the mock itself switched
    # on, so a column's declared type is BY CONSTRUCTION the type of the
    # symbol minted for it, and two rows of one model cannot declare the
    # set differently (which is what `TypeConflict` exists to catch).
    #
    # NOT DECLARED: a klass with no name (anonymous or singleton) has no
    # type to name, and `obj<?>` is the honest reading — the same rule
    # `SymbolicInstance#declare` states as change 8.
    #
    # WHY HERE AND NOT IN `concolic_targets.rb`: that file is this batch's
    # PRIVATE, byte-identical copy of the shared boundary, and editing a
    # local definition into such a copy is precisely the re-sync defect of
    # 2026-09-09. Overriding from this file is the technique §9 already
    # uses for `render_relation_sql`.
    unless ConcolicTargets.respond_to?(:symbolic_instance_without_type_declaration)
      class << ConcolicTargets
        alias_method :symbolic_instance_without_type_declaration,
                     :symbolic_instance

        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_without_type_declaration(klass, base_name, sql)
          obj.define_singleton_method(:concolic_name) { base_name }
          tname = klass.respond_to?(:name) ? klass.name.to_s : ""
          unless tname.empty?
            obj.define_singleton_method(:concolic_type_name) { tname }
            if defined?(SymbolicFunc) && SymbolicFunc.respond_to?(:register_type)
              decl = {}
              klass.columns_hash.each do |col, meta|
                decl[col] = case meta.type
                            when :integer, :bigint then "int"
                            when :boolean          then "bool"
                            else                        "str"
                            end
              end
              SymbolicFunc.register_type(tname, decl)
            end
          end
          obj
        end
      end
    end


    # =====================================================================
    # §10. `find_by_sql`'s NOTE MUST CARRY THE BINDS, NOT THE TEMPLATE.
    # =====================================================================
    # ./REPORT.md §5 open item 5, the LAST non-`$$` key column in this
    # corpus: 26 instances of
    #     SELECT "blocks".* FROM "blocks" WHERE "blocks"."user_id" = ?
    # on `SYM_RESULT_ActiveRecord__Querying_find_by_sql_1_rows`.
    #
    # THE CAUSE. The shared `find_by_sql` mock notes `args["sql"]`. When the
    # caller is AR's `StatementCache` (statement_cache.rb:108 — reached here
    # because §1 restores `User#blocks` to the real association reader, so
    # the association genuinely LOADS) that argument is a PREPARED-STATEMENT
    # TEMPLATE: AR renders the SQL once with its own `?` placeholders and
    # passes the values separately. Nothing is lost — the values are right
    # there in `args["binds"]`, as `QueryAttribute`s — the note just never
    # looked at them.
    #
    # TWO EARLIER ATTEMPTS WERE REJECTED, BOTH RIGHTLY:
    #   (a) re-declare `find_by_sql` here -> defect D5. MEASURED AGAIN
    #       2026-09-25 on a bare runtime: after a second `declare_target`,
    #       `args.keys` is ["block", "kwargs", "splat_args"] and BOTH
    #       `args["sql"]` and `args["binds"]` are nil, because
    #       `declare_target` reads `klass.instance_method(method).parameters`
    #       and on the second declaration "the method" is the FIRST mock's
    #       `|*splat_args, **kwargs, &block|` wrapper.
    #   (b) rewrite the `sql` ARGUMENT -> puts `$$(...)` inside a recorded
    #       string argument, which is the leak just removed from
    #       comments_index.
    #
    # THE THIRD WAY, and it is a general workaround for D5 rather than a
    # trick for this one target: D5 is not caused by re-declaring, it is
    # caused by `declare_target` READING THE WRONG SIGNATURE. So restore the
    # signature first. `define_method` with the target's REAL parameter list
    # gives `declare_target` the names to read; the body is never called
    # (a declaration with `returns:` never invokes the original), so the
    # stub is a signature and nothing else. Verified on a bare runtime: with
    # the restore in place the second declaration's `args` are
    # ["binds", "blk", "preparable", "sql"] with the right values in them.
    #
    # The note is then rendered from BOTH halves, and the `$$(...)` lands in
    # the NOTE — where every other mock in this file puts it — never in an
    # argument. `render_arg_value` is the shared renderer, so a symbolic
    # bind becomes `$$(<producer>)` and a concrete one a quoted literal.
    #
    # ALIGNMENT IS CHECKED, NOT ASSUMED — §9 above is what happens when a
    # placeholder list and a bind list are zipped positionally without
    # checking they are the same list. `StatementCache` builds the template
    # and the binds together, one `?` per bind, but if that ever stops being
    # true the note says so instead of mis-attributing a value.
    if defined?(ActiveRecord::Querying)
      querying = ActiveRecord::Querying
      # 1. Restore the true signature (D5 workaround).
      querying.send(:define_method, :find_by_sql) do |sql, binds = [], preparable: nil, &block|
        raise "unreachable: replaced by declare_target below"
      end
      # 2. Re-declare, same kind and type as the shared declaration.
      interceptor.declare_target(querying, :find_by_sql,
                                 kind: CallInterceptor::TARGET_FUNCTION,
                                 type: "[?]",
                                 returns: lambda do |_receiver, args, name|
        raw_sql = args["sql"].to_s
        binds   = args["binds"]
        binds   = [] unless binds.is_a?(Array)
        qmarks  = raw_sql.count("?")
        note =
          if binds.empty? || qmarks != binds.length
            # Not the same list (or nothing to substitute). Say what was
            # seen rather than guessing a correspondence.
            binds.empty? ? raw_sql
                         : "#{raw_sql} /* #{qmarks} placeholders, " \
                           "#{binds.length} binds -- not substituted */"
          else
            i = -1
            raw_sql.gsub("?") do
              i += 1
              b = binds[i]
              ConcolicTargets.render_arg_value(b.respond_to?(:value) ? b.value : b)
            end
          end
        SymbolicList.new(1, name: "#{name}_rows", note: note)
      end)
    end

    warn "[am_create] AspectMembershipsTargets installed"
  end
end

module AmUpdateAllValueNaming
  def update_all(*args, **kwargs, &block)
    prev = Thread.current[:concolic_update_all_values]
    begin
      v = if !kwargs.empty?
            kwargs
          elsif args.length == 1 && args[0].is_a?(::Hash)
            args[0]
          end
      Thread.current[:concolic_update_all_values] = v if v
      if kwargs.empty?
        super(*args, &block)
      else
        super(*args, **kwargs, &block)
      end
    ensure
      Thread.current[:concolic_update_all_values] = prev
    end
  end
end

module AmClassFinderBindNaming
  def find(*args, &block)
    if args.length == 1 && !args[0].is_a?(::Array)
      prev = Thread.current[:concolic_finder_conds]
      begin
        pk = respond_to?(:primary_key) ? primary_key : "id"
        Thread.current[:concolic_finder_conds] = { pk.to_s => args[0] }
        return super
      ensure
        Thread.current[:concolic_finder_conds] = prev
      end
    end
    super
  end
end

# =============================================================================
# `SingularAssociation#writer` — THE FOREIGN-KEY WRITE, AS APP CODE
# =============================================================================
# Was `install!` §7's `declare_target(..., kind: SHIM)`. The body is carried
# over UNCHANGED except that `record` is now a real method parameter instead
# of `args["record"] || args["splat_args"]` (the re-declaration arg-name
# defect, D4 in ./REPORT.md, cannot arise for a prepended method).
#
# WHY IT IS NOT A DECLARED TARGET: see install! §7. In one line — this method
# RETURNS ITS ARGUMENT, and an interception mints a fresh result symbol for a
# value another event already produced, which no `origin` kind can relate to
# that event, so `concolic/model/provenance.py` R2 refuses the dump (rightly:
# the symbol's fields are nowhere declared because they are not its fields).
#
# WHY THE KEY WRITE ITSELF MUST HAPPEN (D4, unchanged): AR attaches the join
# row's aspect through the ASSOCIATION (has_many_through_association.rb:61,
# `attributes[source_reflection.name] = record`), so `aspect_memberships`
# `.aspect_id` is set ONLY by the belongs_to writer deriving it from the
# record. Without it the endpoint's defining INSERT loses the column that
# says WHICH ASPECT the contact was added to.
#
# It deliberately does NOT call `super`: the real
# `BelongsToAssociation#replace` -> `replace_keys` is the `SymbolicInt#to_i`
# wall W1 was built for, and this method is that wall's replacement, not an
# addition to it.
module AmSingularAssociationWriterFk
  def writer(record)
    begin
      refl = reflection
      if refl.belongs_to? && record
        pk = begin
          refl.association_primary_key(record.class)
        rescue StandardError
          "id"
        end
        v = record.respond_to?(:_read_attribute) ? record._read_attribute(pk) : nil
        owner[refl.foreign_key] = v unless v.nil?
        if refl.polymorphic? && record.class.respond_to?(:polymorphic_name)
          owner[refl.foreign_type] = record.class.polymorphic_name
        end
      end
      self.target = record if respond_to?(:target=)
    rescue StandardError => e
      warn "[am_create][writer] #{e.class}: #{e.message.to_s[0, 120]}"
      nil # never let the key write turn a shim into a wall
    end
    if ENV["AM_DEBUG"]
      warn "[am_create][writer] refl=#{(reflection.name rescue '?')} " \
           "bt=#{(reflection.belongs_to? rescue '?')} " \
           "owner=#{owner.class} " \
           "fk=#{(reflection.foreign_key rescue '?')} " \
           "now=#{(owner[reflection.foreign_key].inspect rescue '?')} " \
           "rec=#{record.class}"
    end
    record
  end
end

# =============================================================================
# AmBindSubstitutingCollector — render each bind WHERE IT IS EMITTED.
# =============================================================================
# Derivation and the measurement: install! §9. `Arel::Collectors::SQLString
# #add_bind` is the single funnel every `?` passes through
# (`ToSql#visit_Arel_Nodes_BindParam` -> `collector.add_bind(o.value) { "?" }`),
# so substituting here is exact by construction, where the old
# walk-the-AST-then-`gsub("?")` zip silently shifted every bind that followed
# a nullable condition (arel emits `IS NULL` for it, with no placeholder).
#
# `@bind_index` is kept in step with the superclass even though nothing reads
# it here: this collector is a drop-in for `SQLString`, not a fork of it.
class AmBindSubstitutingCollector < Arel::Collectors::SQLString
  def add_bind(bind)
    self << ConcolicTargets.render_bind_value(bind)
    @bind_index += 1
    self
  end
end


# =============================================================================
# `UniquenessValidator` — THE PROBE MUST BIND SYMBOLS
# =============================================================================
# Derivation, measurements and the three candidate layers: install! §8.
# In one line — activerecord-5.2.4.3 reads the validated attribute through
# the generated reader and each scope column through `_read_attribute`, both
# of which run AR's type cast and hand back a bare Integer, so the relation
# the probe is rendered from carries concrete binds even though the record
# still holds the symbols in `attributes_before_type_cast`.
#
# Two methods, one substitution each, by COLUMN NAME (never by value — D8).
module AmUniquenessSymbolicBinds
  # The validated attribute. Rails: `validate_each(record, attribute, value)`
  # where `value` came from `record.read_attribute_for_validation(attribute)`.
  def validate_each(record, attribute, value)
    sym = AspectMembershipsTargets.symbolic_attr(record, attribute)
    # An enum-backed column is remapped by `map_enum_attribute`
    # (`mapping[value]`), and a symbol is not a key of that mapping — the
    # remap would nil it and flip `build_relation` onto its IS NULL arm.
    # Contact has no enums; the guard keeps the prepend honest app-wide.
    enum = begin
      record.class.defined_enums.key?(attribute.to_s)
    rescue StandardError
      true
    end
    value = sym if sym && !enum
    super(record, attribute, value)
  end

  private

  # FAITHFUL COPY of activerecord-5.2.4.3
  # lib/active_record/validations/uniqueness.rb:85-95, with ONE line changed:
  # the non-association branch prefers the record's own symbol over the
  # type-cast `_read_attribute` value. `super` is not usable here — the
  # substitution has to happen between the read and the `where`, and Rails
  # does both in the same expression.
  def scope_relation(record, relation)
    Array(options[:scope]).each do |scope_item|
      scope_value = if record.class._reflect_on_association(scope_item)
                      record.association(scope_item).reader
                    else
                      AspectMembershipsTargets.symbolic_attr(record, scope_item) ||
                        record._read_attribute(scope_item)
                    end
      relation = relation.where(scope_item => scope_value)
    end

    relation
  end
end


# =============================================================================
# AmDeviseUserNaming — signed-in principal through REAL Devise.
#
# Ported from ../comments_index/targets.rb's `CommentsDeviseUserNaming`
# (X8-family pattern). `AspectMembershipsController` has an unconditional
# `before_action :authenticate_user!`, so unlike comments#index there is no
# anonymous variant: every run of this endpoint has a principal.
#
# `User.serialize_from_session(id, salt)` -> `to_adapter.get(id)` ->
# `klass.where(pk => id).first`. Routing that ONE `.first` through a
# dedicated alias (`devise_user_first`) keeps the principal lookup off the
# shared `FinderMethods#first` ordinal counter, which this endpoint hits
# three more times (aspect lookup, contact find_or_initialize_by, membership
# lookup) — otherwise the principal's var name shifts with every flip.
#
# The principal is minted PERSISTED and FOUND with no recorded decision:
# Devise's middleware guarantees a persisted user reaches the action (a
# missing or failed session 401s upstream, before the controller), so a
# `not_found` decision here would inject an auth-middleware artifact into a
# universe this endpoint's logic never branches on.
# =============================================================================
module AmDeviseUserNaming
  def self.install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets
    return unless defined?(User) && defined?(OrmAdapter::ActiveRecord)

    fm = ActiveRecord::FinderMethods
    unless fm.method_defined?(:devise_user_first)
      fm.send(:alias_method, :devise_user_first, :first)
    end

    # KIND: TARGET_FUNCTION — this is the real `SELECT "users".* FROM "users"
    # WHERE "users"."id" = $$(SYM_USER_CI_id) ORDER BY … LIMIT 1` that the
    # session resolution issues. Only the not_found DECISION is suppressed
    # (see header), not the statement.
    interceptor.declare_target(fm, :devise_user_first, kind: CallInterceptor::TARGET_FUNCTION, type: "obj<?>", returns: lambda do |receiver, args, name|
      u = ct.symbolic_instance(ct.model_class(receiver), name,
                               AspectMembershipsTargets.finder_note(ct, receiver, args, :first))
      if u.respond_to?(:define_singleton_method)
        u.define_singleton_method(:persisted?)  { true }
        u.define_singleton_method(:new_record?) { false }
      end
      u
    end)

    # Salt leaf: `authenticatable_salt` slices encrypted_password[0,29], a
    # SymbolicString#[] wall. Pure string slice, no SQL — a plain prepend,
    # not a declared target (nothing to record).
    unless User.instance_variable_get(:@concolic_salt_shim)
      salt_shim = Module.new do
        def authenticatable_salt
          "concolicsalt"
        end
      end
      User.prepend(salt_shim)
      User.instance_variable_set(:@concolic_salt_shim, true)
    end

    # Route the ONE `.first` inside OrmAdapter::ActiveRecord#get to the
    # dedicated alias — byte-faithful to orm_adapter-0.5.0's #get.
    OrmAdapter::ActiveRecord.prepend(OrmAdapterGetNaming) unless
      OrmAdapter::ActiveRecord < OrmAdapterGetNaming

    warn "[am_create devise] AmDeviseUserNaming installed"
  end

  module OrmAdapterGetNaming
    def get(id)
      klass.where(klass.primary_key => wrap_key(id)).devise_user_first
    end
  end
end
