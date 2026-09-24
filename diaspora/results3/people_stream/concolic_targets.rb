# frozen_string_literal: true
#
# concolic_targets.rb — target-function configuration for the diaspora
# concolic experiment (Ruby has no decorators; this file is the equivalent
# of the Python `@target` annotations, collected in one place).
#
# Companion to RAILS_CONCOLIC_MOCKING.md. Load AFTER the Rails environment
# and the concolic runtime:
#
#   require "config/environment"
#   require ".../ruby_runtime/call_interceptor"
#   require ".../ruby_runtime/bool"        # SymbolicBool (planned)
#   require ".../ruby_runtime/list"        # SymbolicList (length-only)
#   require_relative "concolic_targets"
#
# Every declare_target below SKIPS the real body and returns a symbolic
# value. Mock lambdas receive (receiver, args, result_name) — receiver is
# needed for to_sql (query string -> note) and klass.columns_hash (attrs).
#
# All runtime features this file relies on are LANDED (commits 2af4c17,
# fb0559c, 7c39ac0, 598a0cd, 5707edb, 7ba55d2 in ~/project/src):
#   - symbool factory + SymbolicBool; note: kwarg on all factories
#   - length-only SymbolicList; 3-arity (receiver, args, name) mocks
#   - Z3-safe SYM_RESULT names; run error capture
# Verified end-to-end by scripts/test_framework_targets.rb (3 PCs from the
# real PostService#find! path).
#
# ===========================================================================
# MOCK CLASSIFICATION (two populations — see the numbered sections below)
# ---------------------------------------------------------------------------
# **Design mocks (ours — the SQL-query interceptions), numbered #1..#11:**
#   These intercept ActiveRecord query entry points and return *symbolic*
#   values (a symbolic model instance / SymbolicInt / SymbolicBool /
#   SymbolicList) so real app code branches on them and records path
#   conditions. They ARE the concolic query layer. Sections A..G, I, H.
#
#     #1  Single-record finders   (FinderMethods find/take/first/last/find_by)
#     #2  Class-level finders     (Core::ClassMethods Model.find / find_by)
#     #3  Existence / emptiness   (exists? any? none? one? many? empty?)
#     #4  Collection materialize  (Relation#to_a / to_ary / records; size)
#     #5  Calculations            (count / sum)
#     #6  (unsupported contents ops: pluck/ids/average/... and Batches)
#     #7  Relation DML            (update_all / delete_all / destroy_all)
#     #8  Instance persistence    (save / update / destroy / touch)
#     #9  Raw SQL entry points    (find_by_sql / count_by_sql)
#     #10 Gate 1b call-site mocks (decorated_stream_posts, tag_ids, ...)
#     #11 Redis / Sidekiq enqueue (Sidekiq::Client push / push_bulk)
#
# **Agent crash-stopper mocks (added to stop runs crashing — NOT query
#    design):** sections Y, Z, W, and X/X6. These return nil / render markers /
#    concrete stubs to clear nil-plumbing, render, and framework walls. They
#    are intentionally NOT numbered with #1..#11 (they are workarounds, not
#    the query layer). Their section comments keep their categories
#    (Y=framework walls, Z=render boundary, W=crash-free walls round 2,
#    X/X6=wall-fixing discipline mocks).
#
# Rule of thumb: a mock is a *design* (SQL-query) mock iff it returns a
# symbolic value whose `note` carries the real SQL (`sql_for`) that app code
# would have run; a mock is a *crash-stopper* iff it returns nil/concrete/
# render-marker to get past a wall that would otherwise raise.
# ===========================================================================

module ConcolicTargets
  UNSUPPORTED = ->(op) {
    raise NotImplementedError, "unimplemented concolic operation: #{op} (contents out of scope)"
  }

  # -----------------------------------------------------------------
  # Seed overrides — the multi-run coverage loop.
  #
  # Mocks seed their symbolic vars with defaults (found, public=false, …).
  # CoverageChecker reports missing branches WITH suggested concrete values
  # keyed by var name (e.g. "SYM_RESULT_ActiveRecord__FinderMethods_first_1
  # _not_found" => true). Set them here before the next run to drive the
  # other branch. Var names are stable across runs because the interceptor
  # call counter resets per run.
  # -----------------------------------------------------------------
  class << self
    attr_accessor :seed_overrides
  end
  self.seed_overrides = {}

  module_function

  # Sentinel distinguishing "seeded with nil/false" from "not seeded at all".
  SEED_MISS = Object.new.freeze

  # ------------------------------------------------------------------
  # NAME BOUNDARY (2026-09-14) — seed keys accept BOTH length spellings
  # ------------------------------------------------------------------
  #
  # The runtimes used to mint a container's cardinality variable literally as
  # `len(X)`, and every batch renamed it to `SYM_LEN_X` at load because
  # `len(X)` is not a legal PYTHON identifier and `concolic_engine/solver.py`
  # transports Z3 terms as Python source it `exec`/`eval`s. The runtimes now
  # mint the solver-legal spelling directly (`SymbolicVar.len_var_name`), so
  # the second dialect is gone going forward.
  #
  # But `seed_for` matches EXACTLY and falls back to `default` SILENTLY. Every
  # seed file and every dump snapshot written before that change keys its
  # length seeds `len(X)`, so without this shim a pre-change seed replayed
  # under the new runtime would be quietly IGNORED — no error, no log, just an
  # inert knob and a flip that "did not take". That is the same silent-miss
  # failure the rename was made to end, so both spellings are accepted here.
  # The asked-for spelling always wins; the sibling is only consulted on a
  # miss. See reports/diaspora/docs/NAME_BOUNDARY_PLAN_20260914.md.
  LEGACY_LEN_RE  = /\Alen\((.+)\)\z/.freeze
  SYM_LEN_PREFIX = "SYM_LEN_"

  # True when `var_name` names a container's cardinality, in either spelling.
  def length_var?(var_name)
    s = var_name.to_s
    s.start_with?(SYM_LEN_PREFIX) || !LEGACY_LEN_RE.match(s).nil?
  end

  # Every spelling a seed dict might key `var_name` by, asked-for form FIRST.
  def seed_aliases(var_name)
    s = var_name.to_s
    m = LEGACY_LEN_RE.match(s)
    if m
      [var_name, "#{SYM_LEN_PREFIX}#{m[1]}"]
    elsif s.start_with?(SYM_LEN_PREFIX)
      [var_name, "len(#{s[SYM_LEN_PREFIX.length..-1]})"]
    else
      [var_name]
    end
  end

  # The seed override for `var_name` under any accepted spelling, or the
  # sentinel `miss` when none is present.
  def seed_lookup(var_name, miss)
    ov = ConcolicTargets.seed_overrides
    seed_aliases(var_name).each { |k| return ov[k] if ov.key?(k) }
    miss
  end

  def seed_for(var_name, default)
    v = seed_lookup(var_name, SEED_MISS)
    v.equal?(SEED_MISS) ? default : v
  end

  # ---------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------

  # Render the query this call stands in for (goes into var notes + the
  # symbolic_call note). Handles both a Relation receiver (FinderMethods
  # targets — receiver.klass) and a Class receiver (Core::ClassMethods
  # targets — receiver IS the model).
  #
  # Wall-fixing discipline: a symbolic int/string column fed into a REAL
  # where clause (e.g. `Notification.where(recipient_id: user.id)` with
  # user.id symbolic) crashes `receiver.to_sql` at Arel quote ->
  # value_for_database -> SymbolicInt#to_i. We MUST NOT crash while rendering
  # the note (that turns the note into a wall inside our own mock). Instead
  # render SQL with symbolic binds shown as $$(SYMNAME) — readable, and each
  # $$(...) resolves back to the producing query via the var's note.
  def sql_for(receiver, args)
    return class_finder_sql(receiver, args) if receiver.is_a?(Class)
    base = render_relation_sql(receiver)
    # Statement-shape fidelity (2026-08-21, the severed contacts chain):
    # `relation.find_by(conditions)` — e.g. contact_for_person_id's
    # `Contact.includes(person: :profile).find_by(user_id:, person_id:)`
    # (user/querying.rb:43) — carries its WHERE in ARGS, which the Relation
    # branch never rendered: the note collapsed to the bare relation SQL
    # (`SELECT "contacts".* FROM "contacts"`), severing the producer chain
    # from the notification target and mis-chaining every downstream
    # person/profile/tags read. Append hash-shaped conditions from args
    # (only a non-empty Hash arg qualifies — records/to_a/pluck calls carry
    # none, so their notes are untouched; no pk fallback here, unlike
    # class_finder_sql, to avoid fabricating a WHERE for non-finder calls).
    extra = relation_args_where(receiver, args)
    if extra
      base.include?(" WHERE ") ? "#{base} AND #{extra}" : "#{base} WHERE #{extra}"
    else
      base
    end
  rescue Exception => e # rubocop:disable Lint/RescueException
    # Never let note-rendering crash a mock. NotImplementedError < ScriptError
    # < Exception, so a bare `rescue StandardError` would let the wall escape.
    klass = if receiver.respond_to?(:klass) && receiver.klass.is_a?(Class)
              receiver.klass.name
            else
              receiver.class.name
            end
    "#{klass} query (render_relation_sql failed: #{e.class}#{e.message[0,40]}), args=#{render_args(args)}"
  end

  # Render args for class-level finders / fallbacks (readable, no inspect noise).
  def render_args(args)
    args.is_a?(Hash) ? args.map { |k, v| "#{k}=#{render_arg_value(v)}" }.join(", ") : args.inspect
  end

  def render_arg_value(v)
    if v.respond_to?(:sym_name) && v.sym_name
      "$$(#{v.sym_name})"
    else
      raw = v.respond_to?(:value) ? v.value : v
      # SQL literal quoting: Ruby String#inspect double-quotes, which SQL
      # parses as an IDENTIFIER (the extraction rendered
      # `people`.`concolic_mention@example.org` as a column — caught by the
      # comments_index first extraction, 2026-08-25). Single-quote strings.
      raw.is_a?(String) ? "'#{raw.gsub("'", "''")}'" : raw.inspect
    end
  end

  # results3 Phase A Patch 2: render REAL SQL for class-level finders
  # (Model.find(id), Model.find_by(...), dynamic finders). See
  # ../PHASE_A_PATCH.md Patch 2 for the full derivation and the documented,
  # unfixable-here declare_target kwargs-binding gap (call_interceptor.rb,
  # out of scope for a results3 batch — raise to Bali, do not patch src/).
  # RC-1 (2026-09-19, _RAILS_ENV_MOD_FIX_20260919.md): render the model's REAL
  # default projection instead of a hardcoded `"table".*`. A default_scope that
  # narrows the select list — e.g. lazy_columns' `lazy_load :bio, :gender,
  # :birthday, :location` in app/models/profile.rb, active only when
  # Rails.env.include?("mod") — is otherwise invisible to the note, so the
  # corpus records a star projection that expand_star() widens to every column
  # and the conditional disclosure of those 4 columns is lost. App-agnostic:
  # falls back to `.*` whenever the model has no select-narrowing default
  # scope (which is every model in this app except Profile).
  def default_projection(klass)
    tbl = klass.respond_to?(:table_name) ? klass.table_name : nil
    star = tbl ? %("#{tbl}".*) : "*"
    return star unless klass.respond_to?(:all)
    sel = klass.all.select_values
    return star if sel.nil? || sel.empty?
    sel.map(&:to_s).join(", ")
  rescue Exception # rubocop:disable Lint/RescueException
    tbl ? %("#{tbl}".*) : "*"
  end

  def class_finder_sql(klass, args)
    table = klass.respond_to?(:table_name) ? klass.table_name : klass.name
    where_hash = extract_finder_where(klass, args)
    if where_hash && !where_hash.empty?
      conditions = where_hash.map { |k, v| %("#{table}"."#{k}" = #{render_arg_value(v)}) }.join(" AND ")
      %(SELECT #{default_projection(klass)} FROM "#{table}" WHERE #{conditions})
    else
      "#{klass.name} query (class-level finder; WHERE unavailable -- interceptor " \
      "drops kwargs for *rest-signature finder methods called with keyword " \
      "syntax, see call_interceptor.rb param binding), args=#{render_args(args)}"
    end
  end

  # Relation-receiver companion to extract_finder_where: render the first
  # non-empty Hash in args as table-qualified conditions, nil otherwise.
  # Deliberately NO primary-key fallback — a bare scalar arg on a relation
  # call is not evidence of a WHERE.
  def relation_args_where(receiver, args)
    return nil unless args.is_a?(Hash)
    table = receiver.respond_to?(:klass) && receiver.klass.respond_to?(:table_name) &&
            receiver.klass.table_name
    return nil unless table
    args.each_value do |v|
      if v.is_a?(Hash) && !v.empty?
        return v.map { |k, vv| %("#{table}"."#{k}" = #{render_arg_value(vv)}) }.join(" AND ")
      end
    end
    # Fallback: the ConcolicKwargsToPositional thread-local (see its header —
    # the interceptor's param binding drops the re-packed hash on this Ruby).
    tc = Thread.current[:concolic_finder_conds]
    if tc.is_a?(Hash) && !tc.empty?
      return tc.map { |k, vv| %("#{table}"."#{k}" = #{render_arg_value(vv)}) }.join(" AND ")
    end
    nil
  end

  # Best-effort recovery of a {column => value} condition hash from whatever
  # declare_target's param-binding actually captured. Returns nil (never {})
  # when nothing usable was found, so the caller can render the honest
  # fallback rather than claiming an (empty) WHERE.
  def extract_finder_where(klass, args)
    return nil unless args.is_a?(Hash)
    args.each_value do |v|
      return v.map { |k, vv| [k.to_s, vv] }.to_h if v.is_a?(Hash) && !v.empty?
    end
    # Fallback: the ConcolicKwargsToPositional thread-local (see its header).
    tc = Thread.current[:concolic_finder_conds]
    return tc.map { |k, vv| [k.to_s, vv] }.to_h if tc.is_a?(Hash) && !tc.empty?
    pk = klass.respond_to?(:primary_key) ? klass.primary_key : "id"
    args.each_value do |v|
      next if v.nil?
      return { pk => v }
    end
    nil
  end

  # 2026-09-04 (people_show adversarial repair R1, P-1): SQL-shaped note for
  # the unconditional instance-write targets (update_column/update_columns).
  # The interceptor's call_args is a {param_name => value} hash built from
  # the ORIGINAL method's parameters — for AR 5.2 update_column that is
  # {column_name:, value:}; for update_columns it is {attributes: {…}}.
  # Renders UPDATE "<t>" SET "<col>" = <val> WHERE "<t>"."<pk>" = <pkval>
  # so the judge's _is_dml filter keeps it (writes are now witnessable).
  def dml_update_note(receiver, args)
    table = receiver.class.respond_to?(:table_name) ? receiver.class.table_name : receiver.class.name
    pk = receiver.class.respond_to?(:primary_key) ? receiver.class.primary_key : "id"
    pkv = begin
      receiver.respond_to?(pk) ? receiver.send(pk) : nil
    rescue StandardError
      nil
    end
    sets = if (attrs = args["attributes"]).is_a?(Hash) && !attrs.empty?
             attrs.map { |k, v| %("#{table}"."#{k}" = #{render_arg_value(v)}) }.join(", ")
           elsif (col = args["column_name"])
             %("#{table}"."#{col}" = #{render_arg_value(args["value"])})
           else
             "(unknown columns)"
           end
    %(UPDATE "#{table}" SET #{sets} WHERE "#{table}"."#{pk}" = #{render_arg_value(pkv)})
  rescue StandardError => e
    "#{receiver.class.name} instance write (note render failed: #{e.class})"
  end


  # (the batch's older render_arg_value was removed by the 2026-09-11 bug-2a
  # re-sync: it double-quoted String literals, which SQL parses as an
  # IDENTIFIER -- the donor version single-quotes. Keeping both meant the old
  # one, defined later in the file, silently won.)

  # Render a Relation's SQL with symbolic bind values substituted as
  # $$(SYMNAME). Uses Arel's SQLString collector to get `?` placeholders
  # (never calling quote on a symbolic value), then substitutes each `?` in
  # order from the corresponding BindParam's raw value.
  # BIND-ROTATION FIX (2026-09-11, people_stream X7 drive; coordinator-directed
  # boundary fix, TO PROPAGATE — see _COMPLETION_20260910.md §19/§21).
  #
  # This used to render in TWO passes: Arel's SQLString collector emitted `?`
  # placeholders, then `collect_binds` walked the AST BY `node.instance_variables`
  # ORDER and the `?`s were substituted positionally from that list. The two
  # orders are not the same order, so every value could land one or more slots
  # out of place — MEASURED on the real `User#posts_from` relation:
  #
  #   WHERE "posts"."author_id" = 15                  <- 15 is for_a_stream's LIMIT
  #     AND "posts"."created_at" < $$(SYM_USER_PS_id)  <- an id where a time belongs
  #     AND "posts"."type" IN (<a timestamp>, 'StatusMessage')
  #   ORDER BY … LIMIT 'Reshare'                       <- a type where the limit belongs
  #
  # `transform.py::_repair_rotation` un-rotates such a note only when exactly one
  # rotation is type-admissible; the share_visibilities join adds slots whose
  # column types it cannot pin, several rotations become admissible, and it
  # correctly REFUSES to guess — 1 689 of 1 817 views came back
  # `bind-rotation-UNRESOLVED`, i.e. unshippable.
  #
  # The fix removes the second pass entirely: `ConcolicSymbolicToSql` (footer)
  # now renders each BindParam INLINE, in the visitor's own emission order, so
  # there is no `?`-to-bind pairing left to get wrong. `collect_binds` /
  # `render_bind_value` are kept — `render_bind_value` is what the visitor calls,
  # and `collect_binds` is retained (unused by this path) so the diff against the
  # shared master stays readable.
  def render_relation_sql(rel)
    return "#{rel.class.name} (no arel)" unless rel.respond_to?(:arel) && rel.arel

    visitor = ConcolicSymbolicToSql.new(rel.connection) # results3 bug-2b fix (file footer)
    collector = Arel::Collectors::SQLString.new
    visitor.accept(rel.arel.ast, collector).value
  end

  # Recursively collect BindParam values in AST order (matching the `?`
  # placeholder order from the SQLString collector). Walks instance variables
  # because this Arel version's `each_child` does not recurse into e.g.
  # Arel::Nodes::And#@children.
  def collect_binds(node, out)
    if defined?(Arel::Nodes::BindParam) && node.is_a?(Arel::Nodes::BindParam)
      out << node.value
      return
    end
    if defined?(Arel::Nodes::Casted) && node.is_a?(Arel::Nodes::Casted)
      # results3 bug-2b fix (2026-08-19, ../../docs/history/BUGFIXES_20260819.md):
      # arel-9 Casted has #val, not #value -- the old `out << node.value` raised
      # NoMethodError HERE, losing the whole note to sql_for's rescue fallback
      # for any relation carrying a Casted. And Casted renders INLINE via
      # #quoted (never as a `?` placeholder), so it must not join the
      # `?`-substitution list at all -- appending would misalign every later
      # bind. Inline rendering of symbolic values is ConcolicSymbolicToSql's
      # job (file footer).
      return
    end
    # Recurse into any object ivar that itself looks like an Arel node tree.
    node.instance_variables.each do |iv|
      v = node.instance_variable_get(iv)
      if v.is_a?(Array)
        v.each { |el| collect_binds(el, out) if node_like?(el) }
      elsif node_like?(v)
        collect_binds(v, out)
      end
    end
  end

  def node_like?(obj)
    obj.is_a?(Arel::Nodes::Node) || obj.is_a?(Arel::Attributes::Attribute)
  end

  # Render one bind value: symbolic -> $$(SYMNAME); else inspect. The raw
  # value may be wrapped in a QueryAttribute (value_before_type_cast) or be
  # the bare value.
  def render_bind_value(v)
    raw = if v.respond_to?(:value_before_type_cast)
            v.value_before_type_cast
          elsif v.respond_to?(:value)
            v.value
          else
            v
          end
    if raw.respond_to?(:sym_name) && raw.sym_name
      "$$(#{raw.sym_name})"
    elsif raw.is_a?(String)
      "'#{raw}'"
    else
      raw.inspect
    end
  end

  # The model class behind a finder receiver: a Relation exposes #klass; a
  # Core::ClassMethods receiver IS the model class itself.
  def model_class(receiver)
    receiver.is_a?(Class) ? receiver : receiver.klass
  end

  # Build a symbolic instance of the REAL model class (plan §4):
  # allocate (no initialize / callbacks / DB), then singleton readers per
  # column returning symbolic values chosen by column type. All attr vars
  # carry note: sql. Also overrides []/read_attribute/_read_attribute so
  # every access path bypasses AR type-casting.
  def symbolic_instance(klass, base_name, sql)
    obj = klass.allocate
    attrs = {}
    klass.columns_hash.each do |col, meta|
      var_name = "#{base_name}_#{col}"
      attrs[col] = case meta.type
                   when :integer, :bigint
                     symint(var_name, seed_for(var_name, default_int(col)), note: sql)
                   when :boolean
                     symbool(var_name, seed_for(var_name, false), note: sql)
                   else
                     symstr(var_name, seed_for(var_name, "#{var_name}_v"), note: sql)
                   end
      obj.define_singleton_method(col) { attrs[col] }
      # Boolean predicate readers (post.public?) are used in bare-truthiness
      # position throughout Rails (`unless post.public?`) — unhookable on a
      # wrapper (src/TODO.txt). The predicate itself records the PC and
      # returns the CONCRETE bool: branch recorded at the reader boundary,
      # app branches concretely + consistently.
      next unless meta.type == :boolean
      sym = attrs[col]
      obj.define_singleton_method("#{col}?") do
        val = sym.value
        sym.send(:record!, "(#{sym.sym_name} == True)", "#{col}?", taken: val)
        val
      end
    end
    obj.define_singleton_method(:[])              { |k| attrs.fetch(k.to_s) }
    obj.define_singleton_method(:read_attribute)  { |k| attrs.fetch(k.to_s) }
    obj.define_singleton_method(:_read_attribute) { |k| attrs.fetch(k.to_s) }
    obj.define_singleton_method(:concolic_attrs)  { attrs }
    # SQL/context note for the target_call: CallInterceptor.extract_note reads
    # #concolic_note on non-SymbolicVar returns, so the finder mocks' SQL lands
    # on the symbolic_call event (not only on each column var's note).
    obj.define_singleton_method(:concolic_note)   { sql }

    # --- nil-@attributes family (wall-fixing discipline) ---
    # klass.allocate leaves @attributes nil, so AR's `attributes` (to_hash),
    # `write_attribute`/generated writers (`=`), and `inspect` all crash with
    # NoMethodError for nil. Override the accessors to read/write the attrs
    # Hash directly (the symbolic values are already there). This clears the
    # to_hash / write_from_user / []-writer walls on symbolic records.
    obj.define_singleton_method(:attributes)      { attrs }
    obj.define_singleton_method(:write_attribute) { |k, v| attrs[k.to_s] = v }
    obj.define_singleton_method(:_write_attribute) { |k, v| attrs[k.to_s] = v }
    obj.define_singleton_method(:[]=)             { |k, v| attrs[k.to_s] = v }
    # Profile#image_url is BOTH a DB column AND a real method (takes a size
    # arg, builds a URL). The column reader above returns a symbolic var with
    # arity 0, breaking `profile.image_url(:thumb_small)` in the avatar
    # template. Override to a fixed URL (pure, no SQL — matches X6j intent).
    if klass == Profile
      obj.define_singleton_method(:image_url) { |_size = :thumb_large| "/concolic/image.jpg" }
    end

    # User#hidden_shareables is a REAL method (serialized Hash column, returned
    # via `self[:hidden_shareables] ||= {}`), but the generic column reader
    # above shadows it with a SymbolicString var — so `toggle_hidden_shareable`
    # hits `SymbolicString#has_key?` (the share_visibilities wall). Restore a
    # working mutable Hash (pure data — used only in the hidden-shareable
    # bookkeeping, never a query / not branch-relevant to a query).
    if klass == User
      obj.define_singleton_method(:hidden_shareables) { @hs ||= {} }
    end

    # PostPresenter#non_directly_retrieved_attributes calls @post.post_location
    # UNCONDITIONALLY, but only Reshare defines it (base Post doesn't) — the
    # presenter is used for posts that have a location. Give symbolic instances
    # a safe default (Reshare's shape: address/lat/lng) so a bare Post from the
    # finder mock doesn't NoMethodError. Pure, no SQL.
    if klass.name.split('::').last == "Post"
      obj.define_singleton_method(:post_location) do
        { address: nil, lat: nil, lng: nil }
      end
    end
    # inspect -> AR serializes @attributes; give it the attrs so logging/
    # debugging doesn't crash (devise authenticatable#inspect reaches here).
    obj.define_singleton_method(:inspect) { "<Sym#{klass.name.split('::').last} #{base_name} attrs=#{attrs.keys.inspect}>" }

    # AR association readers (user.person, user.blocks, post.status_message,
    # profile, ...) go through ActiveRecord::Associations and index
    # @association_cache — which is nil on an allocated (non-initialized)
    # record, crashing with `undefined method [] for nil:NilClass` before any
    # symbolic op is reached. Initialize the cache to {} so the AR machinery
    # proceeds: reader -> find_target -> the declared FinderMethods/reference
    # mocks -> symbolic instance, instead of crashing. (Runner-local prepends
    # in some batches already shadow specific readers; this makes the generic
    # path safe for ALL batches.)
    obj.instance_variable_set(:@association_cache, {})
    obj.instance_variable_set(:@association_cache_builder_enabled, false)

    # AR instance-persistence/transaction state that real .save/.destroy/.update
    # read during the transaction wrapper (remember_transaction_record_state does
    # @_start_transaction_state.reverse_merge! — nil on an allocated record ->
    # NoMethodError). Pre-seed empty hashes/flags so destroy/update paths proceed
    # and the mocked persistence targets (section F) fire instead of crashing.
    obj.instance_variable_set(:@_start_transaction_state, {})
    obj.instance_variable_set(:@start_transaction_state, {})
    obj.instance_variable_set(:@_trigger_transaction_callback, false)
    # 2026-09-04 (people_show adversarial repair R1, P-9): symbolic instances
    # model DB-LOADED records (every one is minted by a finder/association
    # mock standing in for a SELECT), so @new_record must be FALSE.
    # With true, CollectionAssociation#null_scope? (owner.new_record? &&
    # !foreign_key_present?) short-circuits every has_many association on a
    # symbolic owner to a NullRelation: `profile.tags` scope is `.none!`
    # (where!("1=0").extending!(NullRelation)), so `tags.pluck(:name)`
    # dispatches to NullRelation#pluck -> [] and NEVER reaches the declared
    # ActiveRecord::Calculations#pluck target — the tags statement was being
    # minted under CollectionProxy.records instead (adversary P-9). With
    # new_record? == false the association scope is a real Relation and the
    # declared pluck/records/count/exists? targets fire under their real
    # frames (verified probe: Calculations.pluck note now minted).
    obj.instance_variable_set(:@new_record, false)
    obj.instance_variable_set(:@destroyed, false)
    obj.instance_variable_set(:@readonly, false)
    obj
  end

  def default_int(col)
    col == "id" ? 1 : 0
  end

  # DISCIPLINE Rule T4 (2026-08-27): "finders carry `ORDER BY pk` + `LIMIT 1`".
  # RE-SYNCED into this batch 2026-09-11 (X7 drive) from the two copies that
  # already satisfy it — notifications_index/concolic_targets.rb:709 and
  # people_show/concolic_targets.rb — after `note_fidelity_audit` scored EIGHT
  # LIMIT-DIFF rows on this endpoint, every one of them a finder whose real
  # statement ends in `LIMIT ?` and whose note did not. This is the boundary's
  # own written contract, not a new declaration.
  def finder_note(receiver, args, kind)
    sql = sql_for(receiver, args)
    return sql unless %i[first last find_by find take find_by! take! first! last!].include?(kind)
    begin
      klass = model_class(receiver)
      table = klass.table_name
      pk    = (klass.primary_key || "id")
      if %i[first last first! last!].include?(kind) && !sql.include?(" ORDER BY ")
        dir = (%i[last last!].include?(kind) ? "DESC" : "ASC")
        sql = %(#{sql} ORDER BY "#{table}"."#{pk}" #{dir})
      end
    rescue StandardError
      nil
    end
    sql =~ /\sLIMIT\s/ ? sql : "#{sql} LIMIT 1"
  end

  # Shared single-record finder mock. raise_on_missing: true  -> find/!-style
  #                                   raise_on_missing: false -> find_by/take/first
  def finder_mock(raise_on_missing:, kind: :find_by)
    lambda do |receiver, args, name|
      sql = finder_note(receiver, args, kind)
      nf_name = "#{name}_not_found"
      not_found = symbool(nf_name, seed_for(nf_name, false), note: sql)
      if not_found == true # explicit compare — bare truthiness records no PC (TODO.txt)
        raise ActiveRecord::RecordNotFound, "concolic: empty result for: #{sql}" if raise_on_missing
        # B-8 HARVEST APPLIED BATCH-LOCALLY (people_stream, 2026-09-10). The
        # finder ISSUED its statement and got no row — `nil` cannot carry the
        # note (CallInterceptor.extract_note takes it from the RETURNED value),
        # so publish it out of band on the channel the interceptor reads once
        # (call_interceptor.rb:243-250). Without this the statement vanishes
        # from the corpus and therefore from the extracted policy: measured on
        # this batch's 1109-dump corpus, 709 finder events over 511 dumps
        # carried no note, 354 dumps lost a statement they issued, and 12 dumps
        # extracted to "no SELECT queries recorded for this endpoint" while the
        # request really read `people` (the comments_index M-9 signature).
        # Identical to the repair notifications_index (concolic_targets.rb:754)
        # and comments_index (targets.rb:521) already carry. The SHARED file
        # reports/diaspora/concolic_targets.rb still lacks it — RAISED, not
        # edited here (DISCIPLINE Rule T3).
        Thread.current[:concolic_pending_note] = sql
        nil # PC already recorded at this boundary; app branches concretely+consistently
      else
        symbolic_instance(model_class(receiver), name, sql)
      end
    end
  end

  # ---------------------------------------------------------------------
  # Target declarations
  # Selection rule: any framework method that could downstream issue SQL.
  # See STEP0_query_targets.md for the full annotated table.
  # ---------------------------------------------------------------------

  def install!(interceptor = CallInterceptor.instance)
    # ---- people_stream DESCENTS (Rule T re-sync, 2026-09-09) --------------
    # This file is a VERBATIM copy of the shared boundary
    # reports/diaspora/concolic_targets.rb, so it can be diffed against
    # upstream and inherits the P-1/P-2/P-9/P-10 repairs. The five targets
    # this batch DESCENDS (documented in run_dse.rb's header: the app runs
    # them for real) are removed by FILTERING THE DECLARATION, not by editing
    # the declaration sites — a structural edit would make this file diverge
    # from the boundary again, which is how it fell 5 repairs behind.
    _descend = %i[default_render pluck blocked_people
                  render render_to_string render_to_body post_ids attach_user_likes
                  build_mentioned_people_json process]
    unless interceptor.singleton_class.method_defined?(:__descend_filter__)
      interceptor.define_singleton_method(:__descend_filter__) { true }
      _orig_declare = interceptor.method(:declare_target)
      interceptor.define_singleton_method(:declare_target) do |klass, method, **kw|
        next nil if _descend.include?(method)
        _orig_declare.call(klass, method, **kw)
      end
    end
    # Some mocked targets live in controllers / lib classes that load lazily
    # (e.g. StreamsController#decorated_stream_posts). Eager-load JUST those
    # files (not the whole app — full Rails.application.eager_load! crashes on
    # the asset pipeline during load). Each require is rescued so one missing/
    # failing file cannot abort the batch; non-loadable targets simply don't
    # register (honest — reported as a non-firing mock).
    eager_files = [
      "streams_controller", "likes_controller", "tags_controller",
      "people_controller", "notifications_controller",
      "stream/base", "stream/multi", "stream/aspect", "stream/followed_tag",
      "status_message", "photo", "poll", "poll_answer",
      # Wall-fix targets (§X) live on services / taggable / federation — load
      # them so `defined?(…)` is true when install! registers the targets.
      "post_service", "reshare_service", "status_message_creation_service",
      "taggable", "reshare", "person", "profile", "mentionable",
      "mentions_container", "message_renderer", "post_presenter",
      "aspect_membership", "aspect", "block",
    ]
    if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
      %w[app/controllers app/models app/presenters app/services lib].each do |dir|
        next unless File.directory?(File.join(Rails.root, dir))
        eager_files.each do |f|
          path = File.join(Rails.root, dir, "#{f}.rb")
          next unless File.exist?(path)
          begin
            require_relative path
          rescue LoadError, StandardError => e
            warn "[GATE1B] could not load #{path}: #{e.class} #{e.message[0,80]}"
          end
        end
      end
    end

    fm  = ActiveRecord::FinderMethods

    # Devise controllers are engine controllers (app/controllers in the
    # devise gem) — not under Rails.root, so the eager_files loop above never
    # loads them, and the Y4 assert_is_devise_resource! target silently stays
    # dormant (session/registration actions then hit ActionNotFound). Load them
    # explicitly so the Devise boundary can fire. Each require is rescued so a
    # missing file cannot abort the batch.
    %w[devise_controller sessions_controller registrations_controller].each do |dev_f|
      dev_path = "/home/dev/.gem/jruby/2.6.0/gems/devise-4.7.1/app/controllers/#{dev_f}.rb"
      next unless File.exist?(dev_path)
      begin
        require_relative dev_path
      rescue LoadError, StandardError => e
        warn "[CRASHFREE] could not load #{dev_path}: #{e.class} #{e.message[0,80]}"
      end
    end

    rel = ActiveRecord::Relation
    calc = ActiveRecord::Calculations
    batches = ActiveRecord::Batches

    # --- [ DESIGN #1 ] A. Single-record finders -> symbolic model instance --
    %i[find take! first! last! find_by!].each do |m|
      interceptor.declare_target(fm, m, returns: finder_mock(raise_on_missing: true, kind: m))
    end
    %i[find_by take first last].each do |m|
      interceptor.declare_target(fm, m, returns: finder_mock(raise_on_missing: false, kind: m))
    end
    # Ordinal finders (second..forty_two) — declare only if diaspora uses them.

    # --- [ DESIGN #2 ] A2. Single-id class-level finders (Core::ClassMethods) ---
    # Model.find(id) / Model.find_by(...) / Model.find_by!(...) are REAL
    # cached-statement methods on Core::ClassMethods (NOT Querying delegates),
    # so they bypass the FinderMethods relation mocks above and would route
    # through find_by_sql -> SymbolicList#first (NotImplementedError). Declare
    # them with the same finder_mock so class-level single-record lookups
    # return a symbolic instance (or the proper not-found result).
    # Multi-id form (Post.find([1,2]) / find(a,b,c)) is not exercised by the
    # app today (verified: 0 multi-id/IN queries in current dumps) — if it ever
    # fires, route it to the collection mock (a length-only SymbolicList).
    core = ActiveRecord::Core::ClassMethods
    interceptor.declare_target(core, :find,     returns: finder_mock(raise_on_missing: true,  kind: :find))
    interceptor.declare_target(core, :find_by,  returns: finder_mock(raise_on_missing: false, kind: :find_by))
    interceptor.declare_target(core, :find_by!, returns: finder_mock(raise_on_missing: true,  kind: :find_by!))

    # --- [ DESIGN #3 ] B. Existence / emptiness -> SymbolicBool -------------
    # NOTE: `if Post.exists?(...)` hits the Ruby truthiness gap (TODO.txt) —
    # only explicit compares record PCs. Returned anyway per decision 2026-08-05.
    {
      exists?: [fm, false], # concrete seed: does not exist
      any?:    [rel, true],
      none?:   [rel, false],
      one?:    [rel, true],
      many?:   [rel, false],
      empty?:  [rel, false],
    }.each do |m, (mod, seed)|
      interceptor.declare_target(mod, m, returns: lambda do |receiver, args, name|
        vn = "#{name}_#{m.to_s.delete('?')}"
        note = sql_for(receiver, args)
        # 2026-09-04 (people_show adversarial repair R1, P-2, matrix T-a):
        # FinderMethods#exists? stands in for the existence probe
        # `SELECT 1 AS one FROM <t> WHERE <col> = ? LIMIT ?` — never
        # `SELECT t.*` (T4). Render the probe shape so the note is faithful
        # even though the judge would accept the t.* form (projection {} ⊆
        # {"*"}). sql_for on the relation gives `SELECT t.* …`; rewrite the
        # projection and append LIMIT 1 (the judge ignores LIMIT, T4 wants it).
        if m == :exists?
          begin
            note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT 1 AS one FROM ")
            note = "#{note} LIMIT 1" unless note =~ /LIMIT\s+\?/i
          rescue StandardError
            nil
          end
        end
        symbool(vn, seed_for(vn, seed), note: note)
      end)
    end

    # --- [ DESIGN #4 ] C. Collection materialization -> SymbolicList (length + rep, Gate 1b)
    # `records` is REQUIRED: each/map route through it via Delegation, not to_a.
    # Gate 1b (Bali directive): attach a single representative model row so
    # SQL-free display/serialisation iteration completes (sampled-content);
    # the representative is a symbolic instance of the relation's klass.
    %i[to_a to_ary records].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        vn = "#{name}_rows"
        rep = symbolic_instance(model_class(receiver), "#{name}_row", sql_for(receiver, args))
        SymbolicList.new(seed_for(SymbolicVar.len_var_name(vn), 1), name: vn,
                       note: sql_for(receiver, args), representative: rep)
      end)
    end
    interceptor.declare_target(rel, :size, returns: lambda do |receiver, args, name|
      vn = "#{name}_size"
      note = sql_for(receiver, args)
      begin
        note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT COUNT(*) FROM ")
      rescue StandardError
        nil
      end
      symint(vn, seed_for(vn, 1), note: note)
    end)

    # --- [ DESIGN #5 ] D. Calculations -> SymbolicInt -----------------------
    %i[count sum].each do |m|
      interceptor.declare_target(calc, m, returns: lambda do |receiver, args, name|
        vn = "#{name}_#{m}"
        note = sql_for(receiver, args)
        begin
          if m == :sum
            vals = args.is_a?(::Hash) ? args.values : Array(args)
            col = vals.flatten.compact.find { |a| a.is_a?(::Symbol) || a.is_a?(::String) }
            if col
              tbl = (receiver.respond_to?(:table_name) && receiver.table_name) ||
                    (receiver.respond_to?(:klass) && receiver.klass.table_name)
              proj = tbl ? %(SUM("#{tbl}"."#{col}")) : %(SUM("#{col}"))
              note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT #{proj} FROM ")
            else
              note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT SUM(*) FROM ")
            end
          else
            note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT COUNT(*) FROM ")
          end
        rescue StandardError
          nil # projection rewrite must never crash the mock
        end
        symint(vn, seed_for(vn, m == :count ? 1 : 0), note: note)
      end)
    end
    # --- [ DESIGN #5b ] D2. Calculations#pluck -> IterableSymbolicList -------
    # 2026-09-04 (people_show adversarial repair R1, P-9, matrix T-ag): pluck
    # was declared UNSUPPORTED, so the `ProfilePresenter tags.pluck(:name)`
    # statement (fires on EVERY show) was minted under CollectionProxy.records
    # instead — the pluck frame carried zero notes and mock_note_check scored
    # NOTE-MISSING on every run incl. the anon control. pluck IS the query
    # boundary (same role as records/to_a — see results2/conversations_index
    # targets.rb §1b and results3/people_show targets.rb for the identical
    # descent), so the shared boundary now declares it as a real design mock:
    # length-only IterableSymbolicList with a per-column representative, and a
    # SQL note carrying the projection (SELECT "t"."col1", "t"."col2" …)
    # instead of SELECT t.* — matches the real pluck statements.
    # The pluck column list is recovered via the PluckArgs-style prepend each
    # batch already installs (PeopleShowPluckArgs / conversations PluckArgs);
    # if no column was captured, fall back to "*"-shaped note + one value rep.
    if calc.method_defined?(:pluck)
      interceptor.declare_target(calc, :pluck, returns: lambda do |receiver, args, name|
        vn   = "#{name}_plucked"
        cols = (Thread.current[:people_show_pluck_cols] ||
                Thread.current[:conversations_pluck_cols] ||
                []).map(&:to_s)
        note = sql_for(receiver, args)
        begin
          unless cols.empty?
            tbl = (receiver.respond_to?(:table_name) && receiver.table_name) ||
                  (receiver.respond_to?(:klass) && receiver.klass.table_name)
            proj = cols.map { |c| %("#{tbl}"."#{c.split('.').last}") }.join(", ")
            note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT #{proj} FROM ")
          end
        rescue StandardError
          nil # projection rewrite must never crash the mock
        end
        cols = ["value"] if cols.empty?
        vals = cols.each_with_index.map do |c, i|
          var = cols.size == 1 ? "#{name}_pluck_#{c.split('.').last}" : "#{name}_pluck#{i}_#{c.split('.').last}"
          # self-contained column symboliser (root has no PeopleTargets.
          # sym_for_column — each batch's copy may reuse its own). Type comes
          # from the relation klass's columns_hash; untyped -> string.
          begin
            klass = model_class(receiver)
            bare  = c.to_s.split('.').last.to_s
            type  = klass.respond_to?(:columns_hash) ? klass.columns_hash[bare]&.type : nil
          rescue StandardError
            type = nil
          end
          case type
          when :integer, :bigint, :float, :decimal then symint(var, seed_for(var, 1),  note: note)
          when :boolean                           then symbool(var, seed_for(var, false), note: note)
          else                                         symstr(var, seed_for(var, "sym_#{bare}"), note: note)
          end
        end
        rep = cols.size == 1 ? vals.first : vals
        IterableSymbolicList.new(seed_for(SymbolicVar.len_var_name(vn), 1), name: vn,
                                 note: note, representative: rep)
      end)
    end
    # --- [ DESIGN #5c ] D3. Calculations#ids -> symbolic id list ------------
    # Boundary gap B-5 (docs/BOUNDARY_NOTE_GAPS_20260915.md), repaired
    # 2026-09-15. `ids` was UNSUPPORTED in the shared boundary, so it recorded
    # NOTHING and any batch needing it had to redeclare it locally.
    #
    # WHAT B-5 ACTUALLY IS (measured on results3/posts_show, whose targets.rb
    # carries such a local declaration): the statement IS recorded -- on the
    # `Calculations.ids` call event and on the representative
    # `<result>_id`/`len(<result>_ids)` vars. What is missing is a RESOLVABLE
    # NAME. That local mock names the LIST `<result>_ids`, and `ids` is not a
    # column of the relation, so when the list is handed to a later
    # `where(...)` as a bind, render_bind_value emits `$$(<result>_ids)` --
    # and transform.py's bind recursion resolves `<producer>_<column>` only,
    # so it stays an unresolved placeholder
    # (`"notifications"."target_id" = $$(SYM_RESULT_ActiveRecord__
    # Calculations_ids_1_ids)`, 72 notes / 150 dumps).
    #
    # So the shared declaration names the list after the relation's REAL
    # primary key (`<result>_<pk>`), which is exactly the column the list
    # holds; a bind naming it then resolves as that column of THIS query by
    # the ordinary recursion, with no new config regex. The representative
    # carries the same name -- list and representative ARE the same column --
    # and the length var (`len(...)` / `SYM_LEN_...`) stays distinct by
    # construction. The note carries the real projection
    # (`SELECT "t"."id" FROM ...`) rather than `SELECT "t".*`: `ids` reads one
    # column, and `SELECT *` would overstate it. Same descent §5b took for
    # `pluck`.
    if calc.method_defined?(:ids)
      interceptor.declare_target(calc, :ids, returns: lambda do |receiver, args, name|
        note = sql_for(receiver, args)
        pk = begin
          k = model_class(receiver)
          (k.respond_to?(:primary_key) && k.primary_key) || "id"
        rescue StandardError
          "id"
        end
        begin
          tbl = (receiver.respond_to?(:table_name) && receiver.table_name) ||
                (receiver.respond_to?(:klass) && receiver.klass.table_name)
          proj = tbl ? %("#{tbl}"."#{pk}") : %("#{pk}")
          note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT #{proj} FROM ")
        rescue StandardError
          nil # projection rewrite must never crash the mock
        end
        vn  = "#{name}_#{pk}"
        rep = symint(vn, seed_for(vn, 1), note: note)
        list_class = defined?(IterableSymbolicList) ? IterableSymbolicList : SymbolicList
        list_class.new(seed_for(SymbolicVar.len_var_name(vn), 1), name: vn,
                       note: note, representative: rep)
      end)
    end
    %i[average minimum maximum calculate].each do |m|
      interceptor.declare_target(calc, m, returns: ->(_r, _a, _n) { UNSUPPORTED.call("Calculations##{m}") })
    end

    # --- [ DESIGN #6 ] Batches + contents ops -> unsupported ----------------
    %i[find_each find_in_batches in_batches].each do |m|
      interceptor.declare_target(batches, m, returns: ->(_r, _a, _n) { UNSUPPORTED.call("Batches##{m}") })
    end

    # --- [ DESIGN #7 ] E. Relation-level DML --------------------------------
    %i[update_all delete_all].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        symint("#{name}_#{m}_count", 1, note: sql_for(receiver, args))
      end)
    end
    interceptor.declare_target(rel, :destroy_all, returns: lambda do |receiver, args, name|
      SymbolicList.new(1, name: "#{name}_destroyed", note: sql_for(receiver, args))
    end)

    # --- [ DESIGN #8 ] F. Instance persistence -> SymbolicBool --------------
    # note = operation description (no relation to render for instance DML).
    #
    # Targeting ActiveRecord::Base (NOT ActiveRecord::Persistence): the mocks
    # must win the method-resolution race against the modules that shadow the
    # Persistence definitions higher in every model's ancestor chain —
    #   * save/save!        are redefined by ActiveRecord::Suppressor (then
    #                        Validations runs the validate callbacks, which
    #                        hit the app's before_validation `name.strip!` and
    #                        before_create SQL walls on symbolic records)
    #   * destroy           is redefined by ActiveRecord::Transactions
    #   * update!/save!     were never in the Persistence list at all
    # define_method on Base puts the mock directly in Base's method table, which
    # precedes every included module in the MRO, so the body-skip always fires.
    # save! / update! too (the !-variants are what update!/toggle actions call).
    base = ActiveRecord::Base
    %i[save save! update update! update_attribute touch destroy destroy!].each do |m|
      next unless base.instance_methods.include?(m) ||
                  base.private_instance_methods.include?(m) ||
                  base.protected_instance_methods.include?(m)
      interceptor.declare_target(base, m, returns: lambda do |receiver, args, name|
        symbool("#{name}_#{m}_ok", true, note: "#{receiver.class.name}##{m} args=#{args.inspect}")
      end)
    end

    # --- [ DESIGN #8b ] F2. Unconditional instance writes -> SQL DML notes ---
    # 2026-09-04 (people_show adversarial repair R1, P-1, matrix T-af): the
    # write family was declared but its notes were non-SQL strings
    # ("Model#save args=..."), so `_is_dml` in both judges DROPPED every
    # write note — no symbolic_call could carry an UPDATE, and a real
    # `UPDATE "notifications" SET "unread" = ? WHERE id = ?` (from
    # Notification#set_read_state -> ActiveRecord::Persistence#update_column)
    # scored NOTE-MISSING on every signed-in run.
    #
    # update_column/update_columns are UNCONDITIONAL writes (no dirty-state
    # gate — the write fires even when the value is unchanged), so a plain
    # UPDATE note is exact for them. The dirty-gated members (save/update/
    # touch/update_attribute) KEEP their legacy notes here; the dirty-state
    # write modeling (both polarities + negative row) is the conversations_index
    # copy's local responsibility (C-5/C-14 closed), and this shared root is
    # never loaded by a batch runner (each batch carries a private copy).
    # Rendering: UPDATE "<table>" SET "<col>" = <val> WHERE "<table>""."<pk>" = <pkval>
    # — matches the judge's normalization (DML shapes compare on WHERE
    # predicate columns; SET rendering is not part of the shape).
    %i[update_column update_columns].each do |m|
      next unless base.instance_methods.include?(m) ||
                  base.private_instance_methods.include?(m) ||
                  base.protected_instance_methods.include?(m)
      interceptor.declare_target(base, m, returns: lambda do |receiver, args, name|
        symbool("#{name}_#{m}_ok", true, note: dml_update_note(receiver, args))
      end)
    end

    # --- [ DESIGN #9 ] G. Raw SQL entry points ------------------------------
    querying = ActiveRecord::Querying
    interceptor.declare_target(querying, :find_by_sql, returns: lambda do |receiver, args, name|
      SymbolicList.new(1, name: "#{name}_rows", note: args["sql"].to_s)
    end)
    interceptor.declare_target(querying, :count_by_sql, returns: lambda do |receiver, args, name|
      symint("#{name}_count", 1, note: args["sql"].to_s)
    end)

    # --- [ DESIGN #10 ] I. Gate 1b — sampled-content call-site mocks (SCSM) ---
    # Per DESIGN_sampled_content_list.md §8.3/§8.4 (Bali-approved). Each target
    # is declared on the smallest SQL-free enclosure whose RESULT is the
    # iterated collection, so the enclosing `.map`/`.each` in real app code
    # never runs against a SymbolicList (which would raise — iteration is
    # caller-wrapped by design, D4/D5/D7/D8). Repeats declared with the
    # standard interceptor.declare_target mechanism (NOT ad-hoc monkey-patching).
    #
    # Honest limit (DESIGN §5): these model/helper iteration walls in the
    # ACTION path are the achievable Gate 1b wins. Rows 9/10/14 (the
    # controller/gem `.map` inside the respond_with *format block*) fire before
    # `render` and are NOT clearable without implementing `.map` on a
    # SymbolicList — that stays unimplemented by design, so they remain a
    # documented wall (reported honestly in STATUS, not silently dropped).

    # Rows 1-3: Post.excluding_blocks -> user.blocks.map{|b| b.person_id}.
    # DESIGN table targets user.blocks (the association), NOT excluding_blocks:
    # excluding_blocks' real body has BOTH `.map` AND `.where` (SQL) — mocking
    # it returns a SymbolicList that `for_a_stream` then chains
    # `.excluding_hidden_shareables` onto, cascading into a NEW NoMethodError
    # (strictly worse than the original). Per D7 we do NOT mock a method whose
    # body queries; the protected form is to keep the association mock only
    # and let the each/where cascade surface honestly as a documented limit.
    # user.blocks -> SymbolicList of Block reps (design rows 1-3 association).
    # Declared so any direct `user.blocks` read yields rep-carrying rows too.
    interceptor.declare_target(User, :blocks, returns: lambda do |receiver, args, name|
      rep = symbolic_instance(Block, "#{name}_block", "User#blocks")
      symlist(name, 1, representative: rep, note: "User#blocks")
    end)

    # Post.blocked_people (Gate 1b split): the SQL-free `user.blocks.map{|b|
    # b.person_id}` extracted from Post.excluding_blocks. Its result feeds the
    # `if people.any? ... where("posts.author_id NOT IN (?)", people)` branch in
    # excluding_blocks. The mock returns a CONCRETE EMPTY array `[]` so that
    # `people.any?` is false and the NOT-IN SQL branch is SKIPPED entirely
    # (representative user has no blocked people). Returning a non-empty list
    # ([1]) or a SymbolicList makes Arel try to quote it during bind-var
    # sanitisation, which crashes on SymbolicList#map. The SQL itself stays in
    # excluding_blocks (never mocked).
    interceptor.declare_target(Post.singleton_class, :blocked_people, returns: lambda do |_r, _a, _name|
      []
    end)

    # Rows 4-5: Stream::Aspect#aspect_ids -> aspects.map(&:id). Pure transform.
    # Returns a CONCRETE array [1] so that when the result feeds a `where(...
    # IN (?), aspect_ids)` bind-var sanitisation, Arel does NOT try to quote a
    # SymbolicList (which would crash on SymbolicList#map). Aspect#posts calls
    # user.visible_shareables(..., :by_members_of => aspect_ids) — the concrete
    # [1] lets that SQL path stay real without a list-quote cascade.
    if defined?(Stream::Aspect)
      interceptor.declare_target(Stream::Aspect, :aspect_ids, returns: lambda do |_r, _a, _name|
        [1]
      end)
    end

    # Row 6: Stream::FollowedTag#tag_ids -> tags.map{|x| x.id}. Pure transform.
    # Its real result would be a SymbolicList (tags.map on a symbolic relation)
    # and its value flows into StatusMessage.tag_stream
    # `where("taggings.tag_id IN (?)", tag_ids)` — a STRING where, which Arel
    # sanitises via replace_bind_variable -> quote_bound_value -> value.map
    # (crash on SymbolicList#map). Returning a numeric Array won't help: the
    # interceptor re-symbolises any Array return into a SymbolicList. Returning
    # `nil` is the one value the interceptor passes through UNCHANGED (see
    # to_symbolic: nil passthrough), and `where("IN (?)", nil)` quotes to a
    # benign NULL. user_tag_stream/tag_stream then run for REAL (SQL stays
    # real), returning a real relation that for_a_stream can chain — exactly
    # like the Aspect stream's real visible_shareables path.
    if defined?(Stream::FollowedTag)
      interceptor.declare_target(Stream::FollowedTag, :tag_ids, returns: lambda do |_r, _a, _name|
        nil
      end)
    end

    # Stream::Base#post_ids (Gate 1b split) = `posts.map(&:id)` (SQL-free).
    # Called at the top of like_posts_for_stream! to feed
    # `Like.where(:target_id => post_ids(posts))`. Return a CONCRETE [1] so
    # the Like.where IN bind-var is plain and no SymbolicList#map cascade fires.
    if defined?(Stream::Base)
      interceptor.declare_target(Stream::Base, :post_ids, returns: lambda do |_r, _a, _name|
        [1]
      end)
    end

    # Stream::Base#attach_user_likes (Gate 1b split) = the SQL-free
    # inject+each that attaches like rows to posts. Wrapped to bypass the
    # iteration; returns the posts unchanged (behaviour-preserving: the method
    # is a no-op for coverage purposes — side effects mutate the post rows).
    if defined?(Stream::Base)
      interceptor.declare_target(Stream::Base, :attach_user_likes, returns: lambda do |receiver, args, _name|
        args["posts"]
      end)
    end

    # Rows 9-10 terminal display (Bali directive): the streams controller's
    # JSON decoration is now a separate SQL-free method, StreamsController
    # #decorated_stream_posts (pure `posts.map { presenter }` — no SQL). This
    # is the function-boundary split: we wrap ONLY the SQL-free display step.
    # The producer (Stream::Base#stream_posts / Stream::Person#stream_posts
    # etc.) is intentionally NOT mocked here — it contains SQL
    # (like_posts_for_stream! behind `posts`), so per the D7/no-SQL-in-mock
    # rule it must run for real.
    if defined?(StreamsController)
      warn "[GATE1B] StreamsController defined; decorating target #{StreamsController.name}"
      interceptor.declare_target(StreamsController, :decorated_stream_posts, returns: lambda do |receiver, args, name|
        rep = symbolic_instance(Post, "#{name}_decorated", "StreamsController#decorated_stream_posts")
        symlist(name, 1, representative: rep, note: "StreamsController#decorated_stream_posts")
      end)
    end

    # Row 6 consumption: StatusMessage.tag_stream / .user_tag_stream are CLASS
    # methods (def self.xxx). They are intentionally NOT mocked here: their body
    # is SQL (where IN), and the followed-tags posts must come back as a REAL
    # relation so Stream::Base#stream_posts can chain `.for_a_stream(...)` on it
    # (mocking the consumer to a SymbolicList breaks that chain — NoMethodError
    # for_a_stream). Instead Stream::FollowedTag#tag_ids is stubbed to nil (see
    # above) so the real string-where sanitises to NULL and full real-path runs.
    # (StatusMessage is loaded eagerly above so the constant resolves.)

    # Rows 7-8: Stream::Multi#publisher_prefill -> followed_tags.map{...} +
    # invited_by.try(:person). Pure string-building (no SQL); the string result
    # is supplied symbolically.
    if defined?(Stream::Multi)
      interceptor.declare_target(Stream::Multi, :publisher_prefill, returns: lambda do |_r, _a, name|
        symstr("#{name}_prefill", seed_for("#{name}_prefill", ""), note: "Stream::Multi#publisher_prefill")
      end)
    end

    # Rows 12-13: TagsController#prep_tags_for_javascript -> @tags.map{...};
    # uniq!. Pure transform (no SQL). Mock the transform so @tags is supplied
    # symbolically as a SymbolicList of tag-hash reps.
    if defined?(TagsController)
      interceptor.declare_target(TagsController, :prep_tags_for_javascript, returns: lambda do |receiver, args, name|
        rep = symbolic_instance(ActsAsTaggableOn::Tag, "#{name}_tag", "TagsController#prep_tags_for_javascript")
        symlist(name, 1, representative: rep, note: "TagsController#prep_tags_for_javascript")
      end)
    end

    # --- [ DESIGN #11 ] H. Redis / Sidekiq enqueue (fire-and-forget) ---
    # intercepted as a symbolic no-op instead of hitting the real Redis
    # connection (which is not running in the rig -> Redis::CannotConnectError
    # in background_search / export_photos / ReportWorker / etc).
    #
    # perform_async -> Sidekiq::Worker#client_push -> Sidekiq::Client.new(pool)
    # .push(item). Intercepting Sidekiq::Client#push (and #push_bulk) covers
    # every worker enqueue with ONE framework-level target; the mock returns
    # nil (a real push returns a job-id String, but the app never consumes it —
    # it is fire-and-forget — and nil passes through interceptor unchanged,
    # so no downstream SymbolicString coercion can fire on it). No method here
    # contains the app SQL (enqueue is strictly a queue write), so this is not
    # a D7 violation — nothing SQL-bearing is mocked.
    if defined?(Sidekiq::Client)
      interceptor.declare_target(Sidekiq::Client, :push, returns: ->(_r, _a, _n) { nil })
      interceptor.declare_target(Sidekiq::Client, :push_bulk, returns: ->(_r, _a, _n) { nil })
    end

    # --- [ CRASH-STOP (agent) ] Y. Generic framework-level walls ---
    # These kill the largest crash families at the framework boundary, before
    # any downstream symbolic op can fire. All are ignored-result (fire-and-
    # forget) or terminal markers; none carries app SQL, so no D7 violation.

    # Y1. ActionController::Metal#status= — controllers set response status
    # (self.status = :not_found etc.) BEFORE any render, and with no @_response
    # built (controller-test rig) this delegates to nil.status= and raises
    # Module::DelegationError (13+ crashes). status= only writes a header; the
    # value is not branched on. No-op it.
    if defined?(ActionController::Metal)
      interceptor.declare_target(ActionController::Metal, :status=, returns: ->(_r, _a, _n) { nil })
    end

    # Y2. Implicit render (UnknownFormat, 14 crashes). An action that runs its
    # logic and falls through with NO explicit `render`/`redirect_to` calls
    # hits default_render -> template lookup -> UnknownFormat. Render is
    # terminal (decision A); these actions have completed their concolic
    # logic, so the missing-template raise is an artifact. Make implicit render
    # a terminal marker, mirroring the explicit-render boundary.
    # (default_render lives on ActionController::ImplicitRender, included into
    # Metal; explicit `render` is already handled in section Z.)
    if defined?(ActionController::ImplicitRender)
      interceptor.declare_target(ActionController::ImplicitRender, :default_render, returns: ->(_r, _a, _n) { :render_reached })
    end

    # Y3. redirect_to / url_for — engine/Devise routes are not loaded in the
    # ActionController::TestCase rig, so url generation raises
    # UrlGenerationError (9 crashes) after the action's real logic has run.
    # redirect_to is terminal (a 302 render); url_for is a pure URL builder
    # (not branched). Treat redirect_to as terminal render, and url_for as a
    # benign no-op returning a concrete URL string (Symbol passes through
    # unchanged).
    if defined?(ActionController::Redirecting)
      interceptor.declare_target(ActionController::Redirecting, :redirect_to, returns: ->(_r, _a, _n) { :redirect_reached })
    end
    if defined?(ActionDispatch::Routing::UrlFor)
      interceptor.declare_target(ActionDispatch::Routing::UrlFor, :url_for, returns: ->(_r, _a, _n) { "/concolic_url" })
    end

    # Y4. Devise controllers call assert_is_devise_resource! up-front, which
    # looks up the path in Devise.mappings — not configured in the rig ->
    # ActionNotFound (4 crashes). Skip the check (the rig already supplies
    # current_user plumbing; the check is routing config, not concolic logic).
    if defined?(DeviseController)
      interceptor.declare_target(DeviseController, :assert_is_devise_resource!, returns: ->(_r, _a, _n) { true })
    end

    # --- [ CRASH-STOP (agent) ] Z. Render boundary — render is TERMINAL ---
    # Treat reaching a render call as the completion signal and short-circuit
    # the real view/serialization machinery, which crashes on symbolic data
    # (template lookup, presenter each/map over SymbolicLists, status= on nil
    # @_response -> devise inspect -> serializable_hash -> to_hash/[] for nil).
    # Concolic value lives in controller/service/model logic, not templates =>
    # sound, and honest (the render call event is the completion marker;
    # reports say "reached render", not "rendered a page").
    # See DESIGN_render_boundary.md. All runners call install! => applies to all.
    # Note: respond_with is deliberately NOT declared — it's not present in this
    # Action Pack and render covers the terminal render path.
    render_mod = ActionController::Rendering
    {
      render:              :render_reached,
      render_to_string:    :render_to_string_reached,
      render_to_body:      :render_to_body_reached,
    }.each do |m, marker|
      interceptor.declare_target(render_mod, m, returns: lambda do |receiver, args, name|
        # Guard against nil @_response for controllers that set status/headers
        # before/after render. (render's own _process_options is never reached
        # because we skip the body.)
        unless receiver.instance_variable_get(:@_response)
          reply = receiver.respond_to?(:reply) ? receiver.reply : nil
          receiver.instance_variable_set(:@_response, reply) if reply
        end
        marker # Symbol passes through the interceptor unchanged (not wrapped)
      end)
    end

    # --- [ CRASH-STOP (agent) ] W. Crash-free walls round 2 ---
    # These close the biggest remaining families. See STATUS.md inventory.

    # W1. SymbolicInt#to_i via belongs_to association writers (~8 crashes).
    # When app code does `comment.author = person` (or assign_attributes with
    # an association key), AR routes through SingularAssociation#writer ->
    # BelongsToAssociation#replace -> replace_keys -> `owner[fk] = record.id`,
    # and record.id is a SymbolicInt that gets type-cast via cast_value -> to_i
    # (NotImplementedError). The task directive: cannot mock the Integer cast;
    # mock the caller. The association writer is a single framework chokepoint
    # that all these create paths flow through, so we no-op it (return the
    # record unchanged; the in-memory foreign-key write is not needed for
    # concolic coverage and the eventual save is already symbolic). This is a
    # framework wall equivalent to section Y/Z (no app SQL is mocked).
    if defined?(ActiveRecord::Associations::SingularAssociation)
      interceptor.declare_target(
        ActiveRecord::Associations::SingularAssociation, :writer,
        returns: ->(_r, args, _n) { args["record"] }
      )
    end

    # W2. ActionController::Metal#head -> terminal marker. `head` sets
    # self.status = ... (status= delegates to @_response.status=, @_response
    # nil in the controller-test rig -> Module::DelegationError). head is the
    # terminal response for many destroy/member actions (rescue_from
    # RecordNotFound -> head :not_found), so treat it as a completion marker.
    if defined?(ActionController::Metal) &&
       ActionController::Metal.instance_methods.include?(:head)
      interceptor.declare_target(ActionController::Metal, :head,
                                 returns: ->(_r, _a, _n) { :head_reached })
    end

    # W3. SingularAssociation#find_target -> symbolic instance.
    # When a symbolic record's belongs_to/has_one reader is first touched
    # (post.author, poll_participation.poll, status_message.author, ...) and
    # @association_cache is empty, AR calls find_target, which does
    # `scope.take` -> SymbolicList#first w/o representative (NotImplementedError).
    # Mock find_target to return a symbolic instance of the association's klass
    # (family 4 generic reader wall). Covers photos_destroy/poll/parts_create
    # `author` reader crashes and similar. (The real SQL never runs.)
    if defined?(ActiveRecord::Associations::SingularAssociation)
      interceptor.declare_target(
        ActiveRecord::Associations::SingularAssociation, :find_target,
        returns: lambda do |receiver, _args, _name|
          begin
            refl = receiver.reflection
            klass = refl.klass
            if klass && klass.respond_to?(:allocate)
              # 2026-09-04 (people_show adversarial repair R1, P-10, matrix
              # T-ah): render the real SQL find_target stands in for, derived
              # from the association reflection (target table + FK + owner
              # key), instead of the junk "SingularAssociation#<name>" note.
              # belongs_to: FK col lives on the OWNER; target queried by its
              # own primary key. has_one: FK col lives on the TARGET table,
              # queried by the owner's primary key — the missing
              # `people.owner_id = <user.id>` direction (User -> Person).
              # Never let note-building crash the mock.
              sql = begin
                owner = receiver.owner
                table = klass.table_name
                if refl.belongs_to?
                  col = refl.association_primary_key(klass)
                  fk_raw = owner[refl.foreign_key]
                else
                  col = refl.foreign_key
                  fk_raw = owner[refl.active_record_primary_key]
                end
                # ` LIMIT 1` (Rule T4: a SINGULAR association read is a
                # LIMIT 1 read). RE-SYNCED 2026-09-11 from
                # people_show/concolic_targets.rb:1145, the one copy that
                # already carries it; without it note_fidelity_audit scored
                # every has_one/belongs_to read LIMIT-DIFF against the real
                # `SELECT … LIMIT ?` the app issues.
                # RC-1 (2026-09-19): real default projection, not a hardcoded star.
                %(SELECT #{default_projection(klass)} FROM "#{table}" WHERE "#{table}"."#{col}" = #{render_arg_value(fk_raw)} LIMIT 1)
              rescue StandardError
                "SingularAssociation##{refl.name}"
              end
              symbolic_instance(klass, "assoc_#{refl.name}", sql)
            else
              nil
            end
          rescue StandardError
            nil
          end
        end
      )

      # W3-memo. SingularAssociation#find_target loaded-target memo (by
      # PREPEND, never a second declare_target — that would capture the first
      # wrapper as its "original" and nest the wrappers). A second read of the
      # same has_one/belongs_to in one request re-issues the statement; the
      # real app loads once (TARGET_FUNCTIONS.md #4: conversations 696
      # repetitions, ONE shape; comments 0). Keyed on [owner.object_id,
      # reflection.name]; the per-run scope comes from the interceptor's run
      # label (unique per run in every batch runner — %s_dse%04d%s with a
      # per-run counter), and the whole cache resets when the label changes:
      # the same "clear per run" contract as the CollectionProxy
      # loaded-target memo (notifications targets.rb §5b-CP). super reaches
      # the W3 interceptor wrapper above.
      unless defined?(@singular_loaded_target_memo) && @singular_loaded_target_memo
        singular_loaded_target_memo = Module.new do
          def find_target(*args)
            state = (Thread.current[:concolic_loaded_target_memo] ||= { label: nil, entries: {} })
            label = CallInterceptor.instance.instance_variable_get(:@current_run_label)
            if state[:label] != label
              state[:label] = label
              state[:entries] = {}
            end
            entries = state[:entries]
            key = [owner.object_id, reflection.name]
            return entries[key] if entries.key?(key)
            entries[key] = super
          end
        end
        ActiveRecord::Associations::SingularAssociation.prepend(singular_loaded_target_memo)
        @singular_loaded_target_memo = true
      end
    end

    # W4. ActionController::Rendering#_set_rendered_content_type -> no-op.
    # photos_index respond_to hits `response.content_type = ...` where the
    # rig's @_response is nil (NoMethodError content_type for nil), before the
    # Z render marker is reached. No-op it (it only sets a header on the not-yet
    # existing response object).
    if defined?(ActionController::Rendering) &&
       ActionController::Rendering.private_instance_methods.include?(:_set_rendered_content_type)
      interceptor.declare_target(ActionController::Rendering, :_set_rendered_content_type,
                                 returns: ->(_r, _a, _n) { _a || nil })
    end

    # W5. Photo#url -> SymbolicString. PhotosController#make_profile_photo and
    # #show call photo.url(...) which string-concatenates (SymbolicString#+,
    # NotImplementedError). URL assembly is display-only; return a symstr.
    if defined?(Photo) &&
       (Photo.instance_methods.include?(:url) || Photo.private_instance_methods.include?(:url))
      interceptor.declare_target(Photo, :url, returns: lambda do |receiver, _args, name|
        symstr("#{name}_url", "/uploads/#{name}_thumb.jpg", note: "Photo#url")
      end)
    end

    # W6. Photo.diaspora_initialize -> symbolic Photo. PhotosController#create's
    # legacy_create calls Photo.diaspora_initialize (via user.build_post), whose
    # real body does `photo.author.owner.strip_exif` — author is a symbolic
    # person whose .owner is nil -> `owner for nil`. Mock the builder to return
    # a symbolic Photo (the eventual .save is mocked in section F).
    if defined?(Photo) && Photo.respond_to?(:diaspora_initialize)
      interceptor.declare_target(
        Photo.singleton_class, :diaspora_initialize,
        returns: lambda do |_r, args, name|
          symbolic_instance(Photo, name, "Photo.diaspora_initialize params=#{args.inspect}")
        end
      )
    end

    # W7. DeviseController#devise_mapping -> stub. In the controller-test rig the
    # Devise mapping is never registered, so devise_mapping returns nil and
    # require_no_authentication / set_minimum_password_length crash with
    # `no_input_strategies/validatable? for nil`. Return a stub mapping whose
    # methods return benign concrete values (no-input strategies = none,
    # not a validatable scope). The stub is a plain Object (not re-symbolized).
    if defined?(DeviseController)
      dev_stub = Object.new
      def dev_stub.no_input_strategies; []; end
      def dev_stub.validatable?; false; end
      def dev_stub.strategies; []; end
      def dev_stub.modules; []; end
      def dev_stub.name; :user; end
      def dev_stub.singular; :user; end
      def dev_stub.plural; :users; end
      def dev_stub.path; "/users"; end
      def dev_stub.fullpath; "/users"; end
      def dev_stub.singular?; true; end
      def dev_stub.to(*_); self; end
      interceptor.declare_target(DeviseController, :devise_mapping,
                                 returns: ->(_r, _a, _n) { dev_stub })
    end

    # --- [ CRASH-STOP (agent) ] X. Wall-fixing discipline mocks (posts batch) ---
    # Systematic discipline (README "Wall-fixing discipline"): each target is
    # the SMALLEST method whose real body contains NO SQL and calls NO other
    # declared target. Mocking a unit that internally fires another target
    # would hide the symbolic query chain beneath it — the invariant. Real
    # SQL on the enclosing path (find! -> EvilQuery, aspects_from_ids,
    # target.subscribers, persistence) still runs.

    # X1. PostService#mark_user_notifications -> nil. Clears the posts_show
    # to_i wall: its body (Notification.where(recipient_id: user.id).update_all)
    # feeds a symbolic int into a real where -> to_sql -> Arel quote -> to_i.
    # Result is discarded by posts_controller; nil passes through unchanged.
    if defined?(PostService)
      interceptor.declare_target(PostService, :mark_user_notifications,
                                 returns: ->(_r, _a, _n) { nil })
    end

    # X6g. ActionController::Instrumentation#redirect_to -> terminal. Y3 mocks
    # ActionController::Redirecting#redirect_to, but a controller's #redirect_to
    # resolves to the Instrumentation WRAPPER (instrumentation.rb:64), whose
    # body accesses @_response.status (nil in the rig) -> NoMethodError.
    # redirect_to is terminal (a 302); mock the wrapper that's actually
    # called. (Y3 kept for receivers that resolve through Redirecting.)
    if defined?(ActionController::Instrumentation) &&
       ActionController::Instrumentation.instance_methods.include?(:redirect_to)
      interceptor.declare_target(ActionController::Instrumentation, :redirect_to,
                                 returns: ->(_r, _a, _n) { :redirect_reached })
    end

    # X2. Post.diaspora_initialize -> symbolic instance. Clears the
    # reshares_create local?/to_i wall (reshare.rb:10 validates author.local?
    # before the writer mock sets author_id). Pure object construction — no
    # query. Reshare/StatusMessage inherit Post's, so one declaration covers
    # all builds (analogue of W6 Photo.diaspora_initialize).
    if defined?(Post) && Post.respond_to?(:diaspora_initialize)
      interceptor.declare_target(
        Post.singleton_class, :diaspora_initialize,
        returns: lambda do |_r, args, name|
          symbolic_instance(_r || Post, name,
                            "Post.diaspora_initialize params=#{args.inspect}")
        end
      )
    end

    # X3. ActsAsApi::Collection#as_api_response -> symlist with rep. Clears
    # the reshares_index each wall (acts_as_api does `collect` over the
    # SymbolicList). Pure transform, no SQL; mixed into Relation/Array/
    # CollectionProxy/AssociationRelation, so one declaration covers all
    # receivers. Value flows only into terminal render json:.
    if defined?(ActsAsApi::Collection)
      interceptor.declare_target(
        ActsAsApi::Collection, :as_api_response,
        returns: lambda do |receiver, _args, name|
          klass = begin
            model_class(receiver)
          rescue StandardError
            receiver.is_a?(Array) ? receiver.first.class : Post
          end
          # Boundary gap B-3 (docs/BOUNDARY_NOTE_GAPS_20260915.md), repaired
          # 2026-09-15. This is a SERIALIZER, not a query, and it must NOT be
          # given an invented statement -- but the rows it serialises were
          # fetched by a query that IS in hand on the receiver, and dropping
          # that link is what made every `<name>_row_<col>` unaccountable
          # (people_stream `_row_id` 122 + 65 / 150 dumps). So CARRY THE
          # SOURCE'S NOTE THROUGH rather than mint one:
          #   * a Relation / CollectionProxy / AssociationRelation -> render
          #     its own SQL (the same helper B-4 fixed; before that fix this
          #     branch would have raised and fallen back to prose);
          #   * a SymbolicList -> the note it already carries;
          #   * an Array of already-minted symbolic rows -> the row's
          #     #concolic_note (set by symbolic_instance).
          # The guard keeps the change ADDITIVE: anything that is not a
          # SELECT falls back BYTE-IDENTICALLY to today's prose note, so no
          # existing note shape can move.
          src_note = begin
            if receiver.respond_to?(:arel) && receiver.arel
              render_relation_sql(receiver)
            elsif receiver.respond_to?(:note) && receiver.note
              receiver.note
            elsif receiver.is_a?(Array) && receiver.first.respond_to?(:concolic_note)
              receiver.first.concolic_note
            end
          rescue Exception # rubocop:disable Lint/RescueException
            nil # note-carrying must never crash the mock (NotImplementedError)
          end
          note = src_note.to_s.start_with?("SELECT") ? src_note.to_s : "ActsAsApi::Collection#as_api_response"
          rep = symbolic_instance(klass, "#{name}_row", note)
          symlist(name, 1, representative: rep, note: note)
        end
      )
    end

    # X4a. Diaspora::Taggable#build_tags -> nil. Clears the status_messages_
    # create each wall: tag_list= -> tag_list_on -> tags_on(context).map(&:name)
    # over a SymbolicList. One assignment, no SQL.
    if defined?(Diaspora::Taggable)
      interceptor.declare_target(Diaspora::Taggable, :build_tags,
                                 returns: ->(_r, _a, _n) { nil })
    end

    # X4b. StatusMessage#tag_name_max_length -> nil. Same wall: the
    # before_validation callback is mocked in X4a, but the @tag_list memo
    # stays unset and the tag_name_max_length validator re-enters
    # tag_list_cache_on -> the identical each. One comparison, no SQL.
    if defined?(StatusMessage)
      interceptor.declare_target(StatusMessage, :tag_name_max_length,
                                 returns: ->(_r, _a, _n) { nil })
    end

    # X5. DiasporaFederation::Entity#validate -> nil. Clears the posts_destroy
    # =~ wall: Retraction's diaspora_id rule does `value =~ DIASPORA_ID` on a
    # symbolic string. Gem-boundary (section-Y style), no app SQL involved, so
    # no D7 conflict; keeps retraction_data_for running for real so `data`
    # stays a genuine Hash (no stub object needed). Clears every federation-
    # validator wall in all batches.
    if defined?(DiasporaFederation::Entity)
      interceptor.declare_target(DiasporaFederation::Entity, :validate,
                                 returns: ->(_r, _a, _n) { nil })
    end

    # --- [ CRASH-STOP (agent) ] X6. posts batch round 2 walls (nil-@attributes family, render
    # plumbing, pure-iteration each). Same discipline: smallest SQL-free unit,
    # no other target called within the mocked body. ---

    # X6a. ActionController::Head#head -> terminal marker. `head` is NOT on
    # Metal in this Rails 5.2 (it lives in the Head module mixed into Base),
    # so W2's Metal guard never fired and the real `head` -> response_body=
    # -> nil @_response crashed (posts_mentionable reset_body!). head is a
    # terminal response (W2's intent); no app SQL.
    if defined?(ActionController::Head) &&
       ActionController::Head.instance_methods.include?(:head)
      interceptor.declare_target(ActionController::Head, :head,
                                 returns: ->(_r, _a, _n) { :head_reached })
    end

    # X6b. Gon::ControllerHelpers#gon -> run the REAL body, no stub. The real
    # body (gon-6.3.2 helpers.rb:29-37, read at apply time) is:
    #   def gon
    #     if wrong_gon_request?
    #       gon_request = Request.new(request.env)
    #       gon_request.id = gon_request_uuid
    #       RequestStore.store[:gon] = gon_request
    #     end
    #     Gon
    #   end
    # with wrong_gon_request? == (current_gon.blank? || current_gon.id !=
    # gon_request_uuid), current_gon == RequestStore.store[:gon], and
    # gon_request_uuid == request.uuid. Four lines, no SQL. The old stub's
    # justification ("needs a RequestStore dump missing in the rig") is stale:
    # the missing piece is a request.uuid that ActionController::TestCase
    # supplies, and RequestStore IS present in the rig (the notifications batch
    # verified this exact shape as RealGonShim, results3/notifications_index/
    # targets.rb). Keep the declare_target (the interceptor still must see the
    # call), inline the real body (calling receiver.gon from inside the mock
    # would re-enter the declared method — infinite recursion), no no-op stub.
    # gon is pure JS-var accumulation; nothing branchable, no SQL. (Note:
    # `Gon.preloads` is NOT a real method in gon-6.3.2 — it routes through
    # method_missing; see the X6b-preloads shim below.)
    if defined?(Gon::ControllerHelpers)
      interceptor.declare_target(Gon::ControllerHelpers, :gon,
                                 returns: lambda do |receiver, _args, _name|
        # Real body, gon-6.3.2 helpers.rb:29-37 (with the rig's RequestStore
        # guard the notifications batch verified).
        req = receiver.request
        store = defined?(::RequestStore) ? ::RequestStore.store : nil
        if store && req.respond_to?(:env) && req.respond_to?(:uuid)
          cur = store[:gon]
          if cur.nil? || cur.id != req.uuid
            gr = ::Gon::Request.new(req.env)
            gr.id = req.uuid
            store[:gon] = gr
          end
        end
        ::Gon
      end)

      # X6b-preloads. `Gon.preloads` (people_controller.rb:78/147,
      # gon_helper.rb:5 gon_load_contact) is NOT a real method in gon-6.3.2
      # (grep the vendored gem: zero `preloads` in lib/) — it routes through
      # Gon.method_missing -> get_variable -> current_gon.gon['preloads'],
      # which is nil unless something pre-seeds that key, and the real gon
      # body REBUILDS the stored request (fresh empty gon hash) on every id
      # mismatch. `nil[:person] = ...` would crash. Same remedy as
      # notifications §gen2 (GonPreloadsShim): prepend a `preloads` accessor
      # on the Gon singleton so `gon.preloads[...]` is a real mutable Hash
      # channel, independent of RequestStore. The RHS of
      # `gon.preloads[:person] = @presenter.as_json` still evaluates eagerly
      # (presenter reads fire at action time — unchanged from the old stub).
      unless defined?(@gon_preloads_shim) && @gon_preloads_shim
        gon_preloads_shim = Module.new do
          def preloads
            @concolic_preloads ||= {}
          end
        end
        ::Gon.singleton_class.prepend(gon_preloads_shim)
        @gon_preloads_shim = true
      end
    end

    # X6c. User#add_to_streams -> nil. status_messages_create does
    # `aspects_to_insert.each { |aspect| aspect << post }` over a SymbolicList
    # (the each wall). Body is pure iteration over already-materialized
    # aspects (aspects_from_ids ran for real earlier) — no SQL inside. The
    # aspect collection `<<` is a persistence write (mocked at F); returning
    # nil skips the loop only.
    if defined?(User)
      interceptor.declare_target(User, :add_to_streams,
                                 returns: ->(_r, _a, _n) { nil })
    end

    # X6e. StatusMessageCreationService#add_to_streams -> nil. The service's OWN
    # add_to_streams (status_message_creation_service.rb:70) iterates
    # `status_message.photos.each` over a SymbolicList (the remaining each
    # wall on status_messages_create). Body is pure iteration orchestration
    # (the user.add_to_streams call inside is already X6c-mocked; photos
    # iteration has no SQL). Return nil skips the loop.
    if defined?(StatusMessageCreationService)
      interceptor.declare_target(StatusMessageCreationService, :add_to_streams,
                                 returns: ->(_r, _a, _n) { nil })
    end

    # X6e. User#retract -> nil. posts_destroy's remaining crash is the
    # federation OUTGOING-message plumbing: Retraction.for ->
    # retraction_data_for -> entity construction/validation/serialization
    # (gsub / RelatedEntity). This serialization drives no path conditions;
    # the concolic-relevant branches (find! -> RecordNotFound/NonPublic,
    # post.author == user.person) run BEFORE retract and stay real. The
    # result (retraction.perform -> target.destroy!) is already a persistence
    # mock (F). User#retract is the smallest SQL-free orchestration unit that
    # encloses the whole wall; its one real query (target.subscribers) feeds
    # the already-mocked Sidekiq dispatch, not branch logic.
    if defined?(User)
      interceptor.declare_target(User, :retract, returns: ->(_r, _a, _n) { nil })
    end

    # X6f. Diaspora::Mentionable.people_from_string -> nil. posts_show's
    # mention scan: mentioned_people (unpersisted branch, mentions_container.rb
    # :21) -> people_from_string -> text.scan(REGEX) on a SymbolicString (scan
    # wall). Pure string scan/parse, no SQL. Mocking to nil makes the mention
    # list empty (representative post mentions nobody) — the caller
    # (filter_mentions / message renderer) handles an empty array.
    if defined?(Diaspora::Mentionable) && Diaspora::Mentionable.respond_to?(:people_from_string)
      interceptor.declare_target(Diaspora::Mentionable.singleton_class, :people_from_string,
                                 returns: ->(_r, _a, _n) { [] })
    end

    # X6i. Person#name -> concrete string. posts_show's remaining author-render
    # wall: acts_as_api `t.add :name` -> Person#name -> #name_from_attrs ->
    # first_name/last_name .strip on SymbolicString (strip wall). Person#name
    # is the SQL-free instance boundary the API template actually calls (the
    # singleton class-method variant didn't reliably intercept — dispatch
    # subtlety on def-self methods). Return a concrete "First Last" string so
    # the whole name-building chain is skipped; the name feeds presenter JSON.
    if defined?(Person) && Person.instance_methods.include?(:name)
      interceptor.declare_target(
        Person, :name,
        returns: lambda do |_r, _args, _name|
          "Concolic Person Name"
        end
      )
    end

    # (Profile#image_url handled as a per-instance override in symbolic_instance
    # — it is both a DB column and a URL method, and the per-instance column
    # reader would otherwise shadow the class method with arity 0.)

    # X6k. PostPresenter#build_mentioned_people_json -> []. posts_show's
    # mentioned-people render: @post.mentioned_people.as_api_response(:backbone)
    # — mentioned_people is a SymbolicList (people_from_string mock returns [],
    # re-wrapped), and a SymbolicList has no as_api_response. The presenter
    # method is the smallest SQL-free terminal that wraps the serialization;
    # returning [] yields an empty mentioned_people key for the JSON.
    if defined?(PostPresenter) &&
       (PostPresenter.instance_methods.include?(:build_mentioned_people_json) ||
        PostPresenter.private_instance_methods.include?(:build_mentioned_people_json))
      interceptor.declare_target(PostPresenter, :build_mentioned_people_json,
                                 returns: ->(_r, _a, _n) { [] })
    end

    # X6l. MessageRenderer#title -> concrete string. posts_show title render:
    # PostPresenter#title -> MessageRenderer#title -> @text.lstrip (lstrip
    # wall). Pure string heading extraction, no SQL. Return a concrete title.
    if defined?(Diaspora::MessageRenderer) &&
       Diaspora::MessageRenderer.instance_methods.include?(:title)
      interceptor.declare_target(Diaspora::MessageRenderer, :title,
                                 returns: ->(_r, _a, _n) { "Concolic title" })
    end

    # X6h. MessageRenderer::Processor.process -> concrete text. posts_show text
    # rendering: PostPresenter#build_text -> MessageRenderer#process ->
    # Processor.process(@text, opts, &block) which runs the renderer pipe
    # (normalize -> gsub on a SymbolicString; diaspora_links; camo). Processor
    # .process is the single SQL-free pipe entry; mocking it to return the
    # concrete text skips the whole formatting chain (pure string transforms,
    # no SQL). The rendered text feeds presenter JSON — not branch logic.
    if defined?(Diaspora::MessageRenderer::Processor) &&
       Diaspora::MessageRenderer::Processor.respond_to?(:process) &&
       !Diaspora::MessageRenderer::Processor.singleton_class.ancestors.include?(ConcolicProcessConcretizeShim)
      Diaspora::MessageRenderer::Processor.singleton_class.prepend(ConcolicProcessConcretizeShim)
    end

    # X6d. DiasporaFederation::Entity#normalize_property -> JSON-safe. With X5
    # clearing validate, posts_destroy now reaches `to_h` ->
    # normalized_properties -> normalize_property. The real body does
    # `value.to_s.gsub(...)` on a :string prop — hitting the SymbolicString
    # gsub wall — and passes OTHER prop types (e.g. RelatedEntity) through
    # unchanged. But a returned RelatedEntity lands in symbolic_results and
    # breaks JSON.pretty_generate (its to_json takes 0 args; JSON passes one).
    # Mirror the real branches AND keep dumps serializable: concrete string
    # for a SymbolicString, plain String unchanged, else nil (federation's own
    # to_xml/to_json return nil for RelatedEntity — "never add to json").
    if defined?(DiasporaFederation::Entity)
      interceptor.declare_target(
        DiasporaFederation::Entity, :normalize_property,
        returns: lambda do |_receiver, args, _name|
          v = args["value"]
          if v.is_a?(SymbolicString)
            v.value
          elsif v.is_a?(String) || v.nil?
            v
          end
        end
      )
    end

    # X7a. ActiveRecord::Associations::CollectionProxy#create -> symbolic
    # membership. aspects#create with person_id: connect_person_to_aspect ->
    # `@contact.aspect_memberships.create(aspect: @aspect)` where @aspect is a
    # NEW record whose save is now mocked (section F body-skip, so the parent
    # is never persisted) — the real association create raises
    # "You cannot call create unless the parent is saved". The membership
    # result feeds only AspectMembershipPresenter (JSON), never a query. Return
    # a symbolic AspectMembership (SQL-free; the join bookkeeping is data).
    if defined?(ActiveRecord::Associations::CollectionProxy) &&
       defined?(AspectMembership)
      interceptor.declare_target(
        ActiveRecord::Associations::CollectionProxy, :create,
        returns: lambda do |_receiver, args, name|
          symbolic_instance(AspectMembership, "#{name}_membership",
                            "aspect_memberships.create #{args.inspect}")
        end
      )
    end

    # X7b. User#mine? -> true. aspect_memberships#destroy:
    # `raise Diaspora::NotMine unless current_user.mine?(aspect) && ...`.
    # mine? is a SQL-free accessor compare (self.id == target.user_id) whose
    # not-mine side is a DELIBERATE hard raise (NotMine) — reaching it gives
    # no further coverage, so the ruby-side default (symbolic 1 == symint
    # seeding to false) turns the run into a crashed NotMine dump. Force the
    # success side so the real destroy path + json render are explored. No SQL.
    if defined?(User)
      interceptor.declare_target(User, :mine?,
                                 returns: ->(_r, _a, _n) { true })
    end

    # --- X8: users_sessions batch (Devise / URL-builder / profile walls) -----
    # X8a. ApplicationController#after_sign_in_path_for -> "/". The devise
    # sign-in redirect (current_user_redirect_path) calls
    # `current_user.getting_started? && !current_user.basic_profile_present?`
    # — with signed_in:false the current_user is nil and `getting_started? for
    # nil` crashes (4 sessions/registrations runs). after_sign_in_path_for is
    # the SQL-free orchestration unit enclosing the whole redirect decision
    # (only nil-guard + route helpers). Return a concrete path.
    if defined?(ApplicationController)
      interceptor.declare_target(ApplicationController, :after_sign_in_path_for,
                                 returns: ->(_r, _a, _n) { "/" })
    end

    # X8b. ApplicationController#configure_permitted_parameters -> nil. It
    # builds Devise::ParameterSanitizer, whose initialize reads
    # resource_class.authentication_keys — the rig's resource is a bare Object
    # with no authentication_keys -> NoMethodError (sessions#destroy).
    # configure_permitted_parameters is a SQL-free no-op permit hook; mock it
    # to skip the Devise sanitizer construction.
    if defined?(ApplicationController)
      interceptor.declare_target(ApplicationController, :configure_permitted_parameters,
                                 returns: ->(_r, _a, _n) { nil })
    end

    # X8c. User#confirm_email -> true. users#confirm_email:
    # `if current_user.confirm_email(params[:token])` -> user.rb:233 reads
    # `confirm_email_token`, a DSL method not defined on User (NameError) even
    # before any SQL. confirm_email is SQL-free (blank-check + assign + save,
    # and save is already a persistence mock). Return true.
    if defined?(User)
      interceptor.declare_target(User, :confirm_email,
                                 returns: ->(_r, _a, _n) { true })
    end

    # X8d. ActionDispatch::Journey::Router::Utils.escape_segment -> concrete.
    # users#public: `redirect_to person_path(@user.person)` drives real route
    # generation, whose journey formatter escapes a SymbolicString path segment
    # -> SymbolicString#gsub. escape_segment is the SQL-free leaf that gsubs
    # segments; return the concrete value (pure URL building, not branched, no
    # SQL). Class method -> target the singleton_class.
    if defined?(ActionDispatch::Journey::Router::Utils) &&
       ActionDispatch::Journey::Router::Utils.respond_to?(:escape_segment)
      interceptor.declare_target(
        ActionDispatch::Journey::Router::Utils.singleton_class, :escape_segment,
        returns: lambda do |_r, args, _name|
          s = args["segment"]
          s.respond_to?(:value) ? s.value : s
        end
      )
    end
  end
end

# ===========================================================================
# results3 shared bug fixes (2026-08-19) -- rationale + blast radius in
# ../../docs/history/BUGFIXES_20260819.md, which calls this footer "identical
# in all six endpoint copies".  people_stream's copy carried NONE of it: the
# file was re-synced to the boundary on 2026-09-09 from a source that predated
# the footer, and the drift was invisible because both bugs fail CLOSED (the
# note is lost to sql_for's rescue fallback, not an error).  Re-synced verbatim
# from results3/comments_index/concolic_targets.rb on 2026-09-11 (X7 drive).
# BUGFIXES_20260819.md names THIS batch's own `find_by_2` = post.rb reshare_for
# as the bug-2b witness.
#
# (bug 2a) Ruby-3/JRuby keyword semantics land `find_by(guid: x)` in the
# interceptor wrapper's **kwargs, and its param-binding loop drops them for
# Rails' *rest-signature finders (notes said "WHERE unavailable ...
# args=nil"; extraction kept unresolved placeholders instead of producer
# joins). These prepends convert keyword calls back to Ruby-2-style trailing
# positional hashes BEFORE method lookup reaches the interceptor's
# define_method, so its binding captures the conditions and
# class_finder_sql/sql_for render the real WHERE into the note. `super`
# continues into the interceptor unchanged; methods without keyword args are
# untouched.
module ConcolicKwargsToPositional
  # 2026-08-21 (the severed contacts chain): the positional re-pack below is
  # UNDONE at the next boundary on this Ruby — 2.6 auto-splits a trailing
  # symbol-keyed hash back into the interceptor wrapper's **kwargs, whose
  # param-binding then drops it (the documented call_interceptor.rb gap), so
  # Relation-receiver finder notes rendered bare (`SELECT "contacts".* FROM
  # "contacts"`, no user_id/person_id — 806/806 events in gen8). Stash the
  # conditions in a thread-local at THIS boundary (same pattern as the pluck
  # column capture in targets.rb), where values still carry their symbolic
  # identity; sql_for/class_finder_sql read it as a fallback.
  %i[find_by find_by! exists?].each do |m|
    define_method(m) do |*args, **kwargs, &blk|
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
ActiveRecord::Base.singleton_class.prepend(ConcolicKwargsToPositional) # Model.find_by / exists?
ActiveRecord::Relation.prepend(ConcolicKwargsToPositional)            # relation / association find_by

# (bug 2b) arel-9 renders Casted/Quoted nodes inline via ToSql#quoted, which
# calls connection.quote on the raw value -- a wall for symbolic values (and
# the reason association-scope notes died even after the Casted #val fix
# above whenever the owner key itself was symbolic). Render symbolic values
# as $$(name) inline, matching the note convention used for `?` binds.
class ConcolicSymbolicToSql < Arel::Visitors::ToSql
  private

  def quoted(val, attribute)
    if val.respond_to?(:sym_name) && val.sym_name
      "$$(#{val.sym_name})"
    else
      super
    end
  end

  # BIND-ROTATION FIX (2026-09-11) — see ConcolicTargets.render_relation_sql.
  # arel-9's own body is `collector.add_bind(o.value) { "?" }`, which is what
  # created the `?`-slot sequence the caller then had to re-pair with a
  # separately-collected bind list. Emit the value INLINE instead, in the
  # visitor's emission order, so the pairing cannot be wrong. The rendering is
  # byte-identical to what `render_bind_value` produced for a correctly paired
  # bind — symbolic -> `$$(NAME)`, String -> `'…'`, else `#inspect` — so note
  # TEXT is unchanged wherever the old path happened to align.
  def visit_Arel_Nodes_BindParam(o, collector)
    collector << ConcolicTargets.render_bind_value(o.value).to_s
  end
end

# X6h REPLACED 2026-09-11 — `Processor.process` is a SHIM, not a target.
# The old declaration returned the concrete text and SWALLOWED the whole
# renderer pipe, including `diaspora_links` (message_renderer.rb:100-105),
# whose body is
#     @message.gsub(DIASPORA_URL_REGEX) { … Post.exists?(guid: guid) … }
# so `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ?` — a statement the
# concrete round issues 12 times — had no note anywhere in the corpus
# (note_fidelity's STAR-OVER row; Rule S §9.8: a stub over a body that issues a
# query is not a shim, it is a target).
#
# The real body cannot run on a SymbolicString (`gsub` is UNSUPPORTED by design,
# src/ruby_runtime/string.rb). Same shape as boundary harvest B-2
# (`escape_segment`, which comments_index and notifications_index already carry
# as a shim): CONCRETIZE the argument in a prepend and `super` into the REAL
# pipe. Nothing is lost relative to the old mock — it returned the concrete text
# too — and the SQL the pipe issues is now real and noted.
module ConcolicProcessConcretizeShim
  # NOTE (measured, not assumed): the first attempt guarded with
  # `!message.is_a?(::String)` and did NOT concretize — `SymbolicString < String`
  # (src/ruby_runtime/string.rb), so the guard was false and the real pipe still
  # got the wrapper and died on `gsub` at message_renderer.rb:21. Concretize
  # whenever the argument carries a symbolic `.value`, and re-wrap to a PLAIN
  # String (instance_of?, not is_a?).
  def process(message, opts = {}, &block)
    message = message.value if message.respond_to?(:value)
    message = message.to_s unless message.instance_of?(::String)
    super(message, opts, &block)
  end
end
