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
#
# ===========================================================================
# results3/conversations_index MOCK LEDGER (discipline rebuild, see
# ../README.md + ../PHASE_A_PATCH.md + ../results2/MOCK_AUDIT.md). Ported
# from results2/conversations_index's private copy. Applies PHASE_A_PATCH.md
# Patches 1 (SingularAssociation#find_target real SQL), 2 (class-level finder
# real SQL via class_finder_sql/extract_finder_where), and 3 (User#blocks
# real SQL) verbatim — none are conversations-specific, all three close note-
# fidelity gaps. Patch 1b (BelongsToPolymorphicAssociation) and Patch 4
# (CollectionProxy) are NOT applied: PHASE_A_PATCH.md's applicability table
# states conversations_index needs neither (verified independently against
# app/controllers/conversations_controller.rb#index — `ConversationVisibility
# .includes(...)`/`Conversation.joins(...)` are class-level Relations; no
# bare collection-association read reachable in this action; conversations_
# index has no batch-local BelongsToPolymorphicAssociation override).
#
# REMOVED (violates (b) — real body reaches SQL/another target, and this
# endpoint's whole point — conversations#index with the render/serializer
# layer REAL — is to let it):
#
#   - Section Z (render/render_to_string/render_to_body terminal markers).
#     conversations#index's `respond_with do |format| format.html { render
#     "index", locals: {no_contacts: ...} }; format.json { render json:
#     @visibilities.map(&:conversation) } end` is the entire per-conversation-
#     row partial pipeline (index.haml -> N x `render partial: "conversations/
#     conversation"` -> participant/author/message association reads) this
#     rerun exists to exercise. REMOVED so `ActionController::Rendering#render`/
#     `#render_to_string`/`#render_to_body` run for real.
#   - Y2 (`ActionController::ImplicitRender#default_render`). Verified NOT on
#     this endpoint's actual call path (conversations#index always explicitly
#     calls `render` from inside the `respond_with`/`Responder#to_html`/
#     `#to_format` -> `Responder#default_render` -> `@default_response.call`
#     chain — a DIFFERENT `default_render`, on `ActionController::Responder`,
#     never on `ImplicitRender`; see responders-2.4.1 gem source) — but
#     removed anyway for discipline-wide consistency with the other results3
#     endpoints (it is a render no-op one frame out, same violation class as
#     Z, regardless of whether this specific action's control flow reaches
#     it).
#   - `Post.singleton_class.blocked_people` (Gate-1b split below, right after
#     the now-real-SQL-noted `User#blocks`) — MOCK_AUDIT's documented VIOLATION
#     (its real body just calls the sibling `user.blocks` mock + a pure `.map`,
#     so keeping BOTH mocked means `User#blocks`'s own now-correct note never
#     fires along that path). Verified NOT reached by conversations#index (no
#     `blocked_people` call anywhere in ConversationsController/Conversation/
#     Message/ConversationVisibility) — removed anyway for discipline
#     consistency and because a future endpoint sharing this copy could reach
#     it.
#
# NOT removed, and not violations: every other W/X/Y/Z leaf (status= header
# write, redirect_to/url_for terminal + string builder, Devise mapping stub,
# association writer no-op, ActionController::Head#head terminal, gon stub,
# Photo/Post builder/name/federation leaves for OTHER batches' endpoints) —
# same reasoning as the notifications_index/people_stream MOCK LEDGERs.
#
# ConcreteSymbolicString (X6i/X6l/X6h/X8d wrapping, url_for wrapping): ported
# verbatim from results3/notifications_index — a bare String return from ANY
# declare_target mock is NOT exempt from the interceptor's to_symbolic re-wrap
# (only nil and already-SymbolicVar-tagged values are), so every "-> concrete
# string" mock that used to be safe only because render was a terminal no-op
# needs this wrap now that real Haml/ERB/URL-helper code can feed the return
# value into native string ops (.scrub, interpolation, ...).
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
    render_relation_sql(receiver)
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
    elsif v.respond_to?(:value)
      v.value.inspect
    else
      v.inspect
    end
  end

  # Phase A (MOCK_FIDELITY): render REAL SQL for class-level finders
  # (Model.find(id), Model.find_by(...), and dynamic finders like
  # find_by_username -- Rails' DynamicMatchers#define compiles
  # `find_by_username(x)` into a real method that calls `find_by(username: x)`,
  # see activerecord .../dynamic_matchers.rb -- so one fix here covers all of
  # them). Previously this branch printed a useless "args=..." string for
  # every call.
  #
  # KNOWN, UNFIXABLE-HERE GAP (src/ruby_runtime/call_interceptor.rb, out of
  # scope -- raise to Bali, do not patch src/ from results3): declare_target's
  # param-binding loop matches captured call args by the ORIGINAL method's
  # *rest parameter NAME (e.g. `:args` for `find_by(*args)`). Ruby routes a
  # keyword-syntax call (`find_by(username: x)`) into **kwargs, not
  # *splat_args (verified empirically on this Ruby's arg-binding semantics --
  # `def m(*a, **kw); end; m(username: "x")` binds kw, not a). The binding loop
  # then does `kwargs[name]` i.e. `kwargs[:args]`, which is never present, so
  # `call_args["args"]` is always nil for this (the app's actual and apparently
  # exclusive) call style. When no usable WHERE data survives at all, say so
  # honestly instead of printing a blank args=nil that looks like real
  # information.
  def class_finder_sql(klass, args)
    table = klass.respond_to?(:table_name) ? klass.table_name : klass.name
    where_hash = extract_finder_where(klass, args)
    if where_hash && !where_hash.empty?
      conditions = where_hash.map { |k, v| %("#{table}"."#{k}" = #{render_arg_value(v)}) }.join(" AND ")
      %(SELECT "#{table}".* FROM "#{table}" WHERE #{conditions})
    else
      "#{klass.name} query (class-level finder; WHERE unavailable -- interceptor " \
      "drops kwargs for *rest-signature finder methods called with keyword " \
      "syntax, see call_interceptor.rb param binding), args=#{render_args(args)}"
    end
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
    pk = klass.respond_to?(:primary_key) ? klass.primary_key : "id"
    args.each_value do |v|
      next if v.nil?
      return { pk => v }
    end
    nil
  end

  # Render a Relation's SQL with symbolic bind values substituted as
  # $$(SYMNAME). Uses Arel's SQLString collector to get `?` placeholders
  # (never calling quote on a symbolic value), then substitutes each `?` in
  # order from the corresponding BindParam's raw value.
  def render_relation_sql(rel)
    return "#{rel.class.name} (no arel)" unless rel.respond_to?(:arel) && rel.arel

    visitor = ConcolicSymbolicToSql.new(rel.connection) # results3 bug-2b fix (file footer)
    collector = Arel::Collectors::SQLString.new
    sql = visitor.accept(rel.arel.ast, collector).value

    binds = []
    collect_binds(rel.arel.ast, binds)
    i = 0
    sql.gsub("?") do
      v = binds[i]
      i += 1
      render_bind_value(v)
    end
  end

  # Recursively collect BindParam values in AST order (matching the `?`
  # placeholder order from the SQLString collector). Walks instance variables
  # because this Arel version's `each_child` does not recurse into e.g.
  # Arel::Nodes::And#@children.
  #
  # PRIVATE-COPY FIX (results2/conversations_index, not applied to the shared
  # concolic_targets.rb): `Object#instance_variables` on JRuby does NOT
  # reliably return ivars in assignment/definition order for these Arel node
  # classes — observed for a paginated relation's `Arel::Nodes::SelectStatement`
  # (`ConversationVisibility....where(person_id: sym).paginate(...)`):
  #   ast.instance_variables => [:@limit, :@lock, :@offset, :@cores, :@with, :@orders]
  # instead of the definition order [:@cores, :@orders, :@limit, :@lock,
  # :@offset, :@with] (arel-9.0.0 lib/arel/nodes/select_statement.rb). The
  # generic ivar-walk therefore visited LIMIT/OFFSET's binds BEFORE the WHERE
  # clause's bind, so `gsub("?")` (which substitutes in SQL-text left-to-right
  # order: WHERE, then LIMIT, then OFFSET) attached the wrong bind to each
  # placeholder — e.g. the symbolic person_id landed in the rendered OFFSET
  # position and a concrete LIMIT value (15) rendered where person_id
  # belonged. This is a rendering-only bug (the `note` field) — it does not
  # affect the interceptor's actual PC recording, which happens independently
  # per mock — but it corrupts the very `$$(SYMNAME)` audit trail the note
  # exists for, so it is fixed here.
  #
  # Fix: special-case the two node types whose SQL-text bind order does not
  # match a generic child walk (`SelectStatement`, `SelectCore`) with an
  # EXPLICIT visit order matching `Arel::Visitors::ToSql`'s rendering order
  # (FROM/JOIN -> WHERE -> GROUP BY -> HAVING -> ORDER BY -> LIMIT -> OFFSET).
  # Everything else (And/Grouping/Equality trees, arrays) keeps the original
  # generic ivar-walk, which is order-safe because Ruby Arrays always
  # preserve element order regardless of ivar ordering.
  def collect_binds(node, out)
    if defined?(Arel::Nodes::BindParam) && node.is_a?(Arel::Nodes::BindParam)
      out << node.value
      return
    end
    if defined?(Arel::Nodes::Casted) && node.is_a?(Arel::Nodes::Casted)
      # results3 bug-2b fix (2026-08-19, ../BUGFIXES_20260819.md): arel-9
      # Casted has #val, not #value -- the old `out << node.value` raised
      # NoMethodError HERE, losing the whole note to sql_for's rescue
      # fallback for any relation carrying a Casted (association scopes with
      # symbolic owner keys). And Casted renders INLINE via #quoted (never as
      # a `?` placeholder), so it must not join the `?`-substitution list at
      # all -- appending would misalign every later bind. Inline rendering of
      # symbolic values is handled by ConcolicSymbolicToSql (file footer).
      return
    end
    if defined?(Arel::Nodes::SelectStatement) && node.is_a?(Arel::Nodes::SelectStatement)
      Array(node.cores).each { |c| collect_binds(c, out) }
      Array(node.orders).each { |o| collect_binds(o, out) if node_like?(o) }
      collect_binds(node.limit, out) if node.limit
      collect_binds(node.offset, out) if node.offset
      return
    end
    if defined?(Arel::Nodes::SelectCore) && node.is_a?(Arel::Nodes::SelectCore)
      collect_binds(node.source, out) if node.source
      Array(node.wheres).each { |w| collect_binds(w, out) if node_like?(w) }
      Array(node.groups).each { |g| collect_binds(g, out) if node_like?(g) }
      Array(node.havings).each { |h| collect_binds(h, out) if node_like?(h) }
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
    obj.instance_variable_set(:@new_record, true)
    obj.instance_variable_set(:@destroyed, false)
    obj.instance_variable_set(:@readonly, false)
    obj
  end

  def default_int(col)
    col == "id" ? 1 : 0
  end

  # Shared single-record finder mock. raise_on_missing: true  -> find/!-style
  #                                   raise_on_missing: false -> find_by/take/first
  def finder_mock(raise_on_missing:)
    lambda do |receiver, args, name|
      sql = sql_for(receiver, args)
      nf_name = "#{name}_not_found"
      not_found = symbool(nf_name, seed_for(nf_name, false), note: sql)
      if not_found == true # explicit compare — bare truthiness records no PC (TODO.txt)
        raise ActiveRecord::RecordNotFound, "concolic: empty result for: #{sql}" if raise_on_missing
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
      interceptor.declare_target(fm, m, returns: finder_mock(raise_on_missing: true))
    end
    %i[find_by take first last].each do |m|
      interceptor.declare_target(fm, m, returns: finder_mock(raise_on_missing: false))
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
    interceptor.declare_target(core, :find,     returns: finder_mock(raise_on_missing: true))
    interceptor.declare_target(core, :find_by,  returns: finder_mock(raise_on_missing: false))
    interceptor.declare_target(core, :find_by!, returns: finder_mock(raise_on_missing: true))

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
        symbool(vn, seed_for(vn, seed), note: sql_for(receiver, args))
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
      symint(vn, seed_for(vn, 1), note: sql_for(receiver, args))
    end)

    # --- [ DESIGN #5 ] D. Calculations -> SymbolicInt -----------------------
    %i[count sum].each do |m|
      interceptor.declare_target(calc, m, returns: lambda do |receiver, args, name|
        vn = "#{name}_#{m}"
        symint(vn, seed_for(vn, m == :count ? 1 : 0), note: sql_for(receiver, args))
      end)
    end
    %i[pluck ids average minimum maximum calculate].each do |m|
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
      # Phase A (MOCK_FIDELITY): render the real SQL this stands in for
      # (Block belongs_to :user, default FK "user_id") instead of the junk
      # "User#blocks" note. Never let note-building crash the mock.
      sql = begin
        owner_id = receiver.respond_to?(:[]) ? receiver[:id] : receiver.id
        %(SELECT "blocks".* FROM "blocks" WHERE "blocks"."user_id" = #{render_arg_value(owner_id)})
      rescue StandardError
        "User#blocks"
      end
      rep = symbolic_instance(Block, "#{name}_block", sql)
      symlist(name, 1, representative: rep, note: sql)
    end)

    # Post.blocked_people REMOVED for results3 (see file-header MOCK LEDGER
    # and results2/MOCK_AUDIT.md "worst violations" #5): its real body
    # (app/models/post.rb:105) just calls `user.blocks.map{|b| b.person_id}` —
    # a SQL-free `.map` over the now-correctly-noted `User#blocks` mock above.
    # Mocking it separately meant `User#blocks`'s own note never fired along
    # this call path. Verified NOT reached by conversations#index; removed
    # anyway for discipline consistency. Left undeclared so it falls through
    # to the real (SQL-free) method body.

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

    # Y2. REMOVED for results3/conversations_index (see file-header MOCK
    # LEDGER) — `ActionController::ImplicitRender#default_render` is not on
    # this endpoint's actual call path (conversations#index always explicitly
    # renders via `respond_with`'s `Responder#default_render` -> block.call,
    # a DIFFERENT method), but removed for discipline-wide consistency: it is
    # a render no-op one frame out, same violation class as Z below. Left
    # undeclared so the real chain (never reached here) would run for real.

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
      # results3: ConcreteSymbolicString-wrapped (see comment above X6i) — a
      # bare String return here is NOT exempt from the interceptor's
      # re-wrap-into-SymbolicString post-processing, and this endpoint's real
      # HTML render (will_paginate link generation, conversation_path, etc.)
      # can feed the result into native string ops.
      interceptor.declare_target(ActionDispatch::Routing::UrlFor, :url_for, returns: lambda do |_r, _a, name|
        if defined?(ConcreteSymbolicString)
          ConcreteSymbolicString.build("/concolic_url", name: name, note: "ActionDispatch::Routing::UrlFor#url_for")
        else
          "/concolic_url"
        end
      end)
    end

    # Y4. Devise controllers call assert_is_devise_resource! up-front, which
    # looks up the path in Devise.mappings — not configured in the rig ->
    # ActionNotFound (4 crashes). Skip the check (the rig already supplies
    # current_user plumbing; the check is routing config, not concolic logic).
    if defined?(DeviseController)
      interceptor.declare_target(DeviseController, :assert_is_devise_resource!, returns: ->(_r, _a, _n) { true })
    end

    # --- Z. REMOVED for results3/conversations_index (see file-header MOCK
    # LEDGER) — `ActionController::Rendering#render`/`#render_to_string`/
    # `#render_to_body` are exactly the SQL-adjacent (via the per-conversation-
    # row partial's participant/author/message association reads) chain this
    # endpoint's rebuild exists to let run for real. Left undeclared; the real
    # render pipeline runs and any walls it hits are closed at genuine
    # SQL-free leaves below/in ./targets.rb instead (per (b): mock the leaf,
    # never the render call that encloses the query chain). `respond_with`
    # (responders gem, actually used by this endpoint's #index despite the
    # stale comment this replaced) is likewise never mocked — it is real
    # framework dispatch, not a query-adjacent boundary.

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
              # Phase A (MOCK_FIDELITY): render the real SQL find_target stands
              # in for, derived from association.reflection (target table + FK +
              # owner key), instead of the junk "SingularAssociation#name" note.
              # belongs_to: FK column lives on the OWNER, target queried by its
              # own primary key. has_one: FK column lives on the TARGET table,
              # queried by the owner's primary key. Never let note-building
              # itself crash the mock -- fall back to the old junk note on any
              # failure.
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
                %(SELECT "#{table}".* FROM "#{table}" WHERE "#{table}"."#{col}" = #{render_arg_value(fk_raw)})
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
          rep = symbolic_instance(klass, "#{name}_row", "ActsAsApi::Collection#as_api_response")
          symlist(name, 1, representative: rep, note: "ActsAsApi::Collection#as_api_response")
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

    # X6b. Gon::ControllerHelpers#gon -> stub with #preloads => {}. status_
    # messages bookmarklet does `gon.preloads[:bookmarklet] = {...}` — the
    # real gon helper needs a RequestStore dump missing in the rig, so
    # gon.preloads is nil -> `[]= for nil`. Mock the `gon` accessor (the
    # smallest SQL-free unit the app calls) to return a plain stub whose
    # preloads is a mutable Hash. gon is pure JS-var accumulation — nothing
    # branchable, no SQL.
    if defined?(Gon::ControllerHelpers)
      gon_stub = Object.new
      def gon_stub.preloads; @preloads ||= {}; end
      # gon uses method_missing for `gon.foo = ...` (posts_controller:27 does
      # `gon.post = presenter.with_initial_interactions`). Swallow arbitrary
      # setters/readers so the assignments proceed (gon is pure JS-var
      # accumulation, no SQL, not branchable).
      def gon_stub.method_missing(*_args); nil; end
      def gon_stub.respond_to_missing?(*_args); true; end
      interceptor.declare_target(Gon::ControllerHelpers, :gon,
                                 returns: ->(_r, _a, _n) { gon_stub })
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

    # results3 NEW: ConcreteSymbolicString. Every "-> concrete string" mock
    # below (X6i/X6l/X6h/X8d) predates this endpoint's render-family removal
    # and was written/verified back when `render`/`render_to_string` were
    # mocked terminal — so NONE of these concrete-string returns were ever
    # actually fed into Rails' OWN internal HTML-escaping machinery before
    # now. A bare Ruby `String` returned from a declare_target mock is NOT
    # exempt from the interceptor's `to_symbolic` return-value wrapping (only
    # `nil` and already-`SymbolicVar`-tagged values are) — so a "concrete"
    # `"Concolic Person Name"` return was silently getting RE-WRAPPED into a
    # `SymbolicString` by the interceptor, and `SymbolicString#scrub` (etc.)
    # is (correctly) in the unsupported-op list. Ported verbatim from
    # results3/notifications_index.
    unless defined?(ConcreteSymbolicString)
      ::Object.const_set(:ConcreteSymbolicString, Class.new(::String) do
        include SymbolicVar
        attr_reader :note

        def self.build(str, name:, note:)
          s = new(str)
          s.instance_variable_set(:@sym_name, name)
          s.instance_variable_set(:@note, note)
          s
        end
      end)
    end

    # X6i. Person#name -> concrete string. posts_show's remaining author-render
    # wall: acts_as_api `t.add :name` -> Person#name -> #name_from_attrs ->
    # first_name/last_name .strip on SymbolicString (strip wall). Person#name
    # is the SQL-free instance boundary the API template actually calls (the
    # singleton class-method variant didn't reliably intercept — dispatch
    # subtlety on def-self methods). Return a concrete "First Last" string so
    # the whole name-building chain is skipped; the name feeds presenter JSON.
    # results3: ConcreteSymbolicString-wrapped (see comment above) — this
    # endpoint's `person_image_tag`/`person_link` genuinely feed this return
    # value into `image_tag`/`html_escape`.
    if defined?(Person) && Person.instance_methods.include?(:name)
      interceptor.declare_target(
        Person, :name,
        returns: lambda do |_r, _args, name|
          ConcreteSymbolicString.build("Concolic Person Name", name: name, note: "Person#name")
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
                                 returns: lambda do |_r, _a, name|
                                   ConcreteSymbolicString.build("Concolic title", name: name,
                                                                note: "Diaspora::MessageRenderer#title")
                                 end)
    end

    # X6h. MessageRenderer::Processor.process -> concrete text. posts_show text
    # rendering: PostPresenter#build_text -> MessageRenderer#process ->
    # Processor.process(@text, opts, &block) which runs the renderer pipe
    # (normalize -> gsub on a SymbolicString; diaspora_links; camo). Processor
    # .process is the single SQL-free pipe entry; mocking it to return the
    # concrete text skips the whole formatting chain (pure string transforms,
    # no SQL). The rendered text feeds presenter JSON — not branch logic.
    if defined?(Diaspora::MessageRenderer::Processor) &&
       Diaspora::MessageRenderer::Processor.respond_to?(:process)
      interceptor.declare_target(
        Diaspora::MessageRenderer::Processor.singleton_class, :process,
        returns: lambda do |_r, args, name|
          m = args["message"]
          v = m.respond_to?(:value) ? m.value : String(m)
          ConcreteSymbolicString.build(v.to_s, name: name,
                                       note: "Diaspora::MessageRenderer::Processor.process")
        end
      )
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
        returns: lambda do |_r, args, name|
          s = args["segment"]
          v = s.respond_to?(:value) ? s.value : s
          if defined?(ConcreteSymbolicString)
            ConcreteSymbolicString.build(v.to_s, name: name,
                                         note: "ActionDispatch::Journey::Router::Utils.escape_segment")
          else
            v
          end
        end
      )
    end
  end
end

# ===========================================================================
# results3 shared bug fixes (2026-08-19) -- rationale + blast radius in
# ../BUGFIXES_20260819.md. Identical footer in all six endpoint copies.
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
  %i[find_by find_by! exists?].each do |m|
    define_method(m) do |*args, **kwargs, &blk|
      args += [kwargs] unless kwargs.empty?
      super(*args, &blk)
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
end
