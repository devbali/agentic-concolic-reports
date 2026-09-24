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

  # 2026-09-04 (people_show adversarial repair R1, P-1): SQL-shaped note for
  # the unconditional instance-write targets (update_column/update_columns).
  # Interceptor call_args is {param_name => value} built from the original
  # method's parameters (AR 5.2 update_column: {column_name:, value:};
  # update_columns: {attributes: {…}}). Judge _is_dml keeps UPDATE notes.
  def dml_update_note(receiver, args)
    table = receiver.class.respond_to?(:table_name) ? receiver.class.table_name : receiver.class.name
    pk = receiver.class.respond_to?(:primary_key) ? receiver.class.primary_key : "id"
    pkv = begin
      receiver.respond_to?(pk) ? receiver.send(pk) : nil
    rescue StandardError
      nil
    end
    sets = if (attrs = args["attributes"]).is_a?(Hash) && !attrs.empty?
             attrs.map { |k, v| %("#{k}" = #{render_arg_value(v)}) }.join(", ")
           elsif (col = args["column_name"] || args["name"]) # AR 5.2: update_column(name, value)
             %("#{col}" = #{render_arg_value(args["value"])})
           else
             "(unknown columns)"
           end
    %(UPDATE "#{table}" SET #{sets} WHERE "#{table}"."#{pk}" = #{render_arg_value(pkv)})
  rescue StandardError => e
    "#{receiver.class.name} instance write (note render failed: #{e.class})"
  end


  # Phase A (MOCK_FIDELITY): render REAL SQL for class-level finders
  # (Model.find(id), Model.find_by(...), and dynamic finders like
  # find_by_username -- Rails' DynamicMatchers#define compiles
  # `find_by_username(x)` into a real method that calls `find_by(username: x)`,
  # see activerecord .../dynamic_matchers.rb -- so one fix here covers all of
  # them). Previously this branch printed a useless "args=..." string for
  # every call. See ../PHASE_A_PATCH.md Patch 2 for full provenance.
  # RC-1 (2026-09-19, _RAILS_ENV_MOD_FIX_20260919.md): render the model's REAL
  # default projection instead of a hardcoded `"table".*`. A default_scope that
  # narrows the select list — e.g. lazy_columns' `lazy_load :bio, :gender,
  # :birthday, :location` in app/models/profile.rb, active only when
  # `Rails.env.include?("mod")` — is otherwise invisible to the note, so the
  # corpus records a star projection that expand_star() widens to all 18
  # columns and the conditional disclosure of those 4 is lost.
  #
  # Ported VERBATIM from `_redrive_20260919/_proto/concolic_targets.rb`
  # (validated end-to-end on comments_index: disclosure_precision
  # 0.9604 -> 1.0000, 0 branching drift over 26 528 dumps).
  #
  # App-agnostic: `Profile` is the only model in this app that calls
  # `lazy_load`, and `grep -rn "default_scope" app/ lib/` finds nothing else,
  # so for every other model `select_values` is empty and this returns the
  # star unchanged.
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
      # RC-1 (2026-09-19): real default projection, not a hardcoded star.
      %(SELECT #{default_projection(klass)} FROM "#{table}" WHERE #{conditions})
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
  #
  # 2026-09-21 (people_show flip-both false-FAIL fix): a Time/Date/DateTime
  # bind (Stream::Base#max_time -- `posts.created_at < <bound>`, defaults to
  # `Time.now + 1` -- Post.for_a_stream) used to fall through to `raw.inspect`,
  # which renders UNQUOTED ("2026-09-20 23:40:14 +0000") -- and is also just
  # wrong: real emitted SQL quotes a timestamp literal. call_shape()
  # (src/concolic_engine/assumptions.py) wildcards QUOTED string literals
  # only (`'[^']*'` -> `'?'`); an unquoted literal survives into the shape
  # identity verbatim. Because max_time is freshly minted on every single
  # replay, that made the `records`/`to_a` "posts WHERE public = true ..."
  # shape carry a DIFFERENT note on every execution -- base, flip-A, flip-B
  # and flip-both each mint their own timestamp -- so the assumption gate's
  # flip-both "novel shape" check could never match it back to base/flip-A/
  # flip-B and FAILed every IndependenceAssumption whose downstream trace
  # reaches this query, regardless of the decisions actually being
  # independent. Quoting Time-likes here (same as String) makes call_shape's
  # existing wildcard collapse them to '?', same as any other literal.
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
    elsif raw.is_a?(Time) || raw.is_a?(Date) ||
          (defined?(ActiveSupport::TimeWithZone) && raw.is_a?(ActiveSupport::TimeWithZone))
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
  # STI REPRESENTATIVE FAITHFULNESS (2026-09-20, P-7 work).
  #
  # `services` is a Single-Table-Inheritance table: EVERY row is a
  # `Services::*` subclass, and base `Service` is never instantiated by the
  # app. A representative built as a base `Service` is therefore not a
  # faithful stand-in for any row the endpoint can read, and the difference is
  # not cosmetic: `publisher_helper.rb:14` does `service.class::MAX_CHARACTERS`,
  # a constant defined ONLY on the subclasses (services/twitter.rb:6,
  # tumblr.rb:4, wordpress.rb:5). With a base-`Service` rep the signed-in html
  # render dies there with `uninitialized constant Service::MAX_CHARACTERS` —
  # measured in 328 of the 332 auth_self_html dumps of the pre-reopen corpus —
  # truncating the publisher partial.
  #
  # EXPLICIT and auditable, never inferred: one entry, justified above. A rep
  # of any other class is untouched.
  STI_REP_SUBCLASS = { "Service" => "Services::Twitter" }.freeze

  def sti_faithful_class(klass)
    name = klass.respond_to?(:name) ? klass.name.to_s : nil
    sub = STI_REP_SUBCLASS[name]
    return klass unless sub
    # `constantize`, not a const_get inject: under `eager_load = false` the
    # `Services` NAMESPACE is not a loaded constant until Rails' autoloader is
    # asked for the full path, so `Object.const_get("Services")` raises and a
    # silent rescue fell back to the base class (measured 2026-09-20 — the
    # substitution appeared to do nothing and the MAX_CHARACTERS wall stayed).
    resolved = (sub.respond_to?(:safe_constantize) ? sub.safe_constantize : nil)
    resolved = (sub.constantize rescue nil) if resolved.nil?
    (resolved && resolved < klass) ? resolved : klass
  end

  def symbolic_instance(klass, base_name, sql)
    klass = sti_faithful_class(klass)
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
      # P-2 (2026-09-04, adversary R1): Profile#bio_message/#location_message
      # memoize a MessageRenderer over the SYMBOLIC bio/location columns, and
      # Processor.process's X6h mock returns the concrete column value without
      # running diaspora_links — so `Post.exists?(guid:)` (the P-2 posts.guid
      # shape from profile private_hash bio/location) never fires. Re-seed the
      # memoized renderers over PLAIN strings carrying a diaspora:// post URL:
      # the X6h conditional branch then runs diaspora_links -> Post.exists?.
      # Leaf text only (presenter JSON), no SQL semantics lost.
      obj.instance_variable_set(:@bio_message, Diaspora::MessageRenderer.new(
        "Concolic bio with a diaspora://alice@localhost/post/postguid2c0e7e1f8f600000000000001 link"))
      obj.instance_variable_set(:@location_message, Diaspora::MessageRenderer.new(
        "Concolic location diaspora://alice@localhost/post/postguid2c0e7e1f8f600000000000002"))
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
    # model DB-LOADED records (minted by finder/association mocks standing in
    # for SELECTs), so @new_record must be FALSE. With true,
    # CollectionAssociation#null_scope? short-circuits every has_many
    # association on a symbolic owner to a NullRelation — profile.tags scope
    # becomes .none!, so tags.pluck(:name) hits NullRelation#pluck -> [] and
    # never reaches the declared Calculations#pluck target (P-9: pluck frame
    # had ZERO notes; statement was minted under CollectionProxy.records).
    # false -> real Relation scope -> declared targets fire under their real
    # frames. Verified by probe (_probe_pluck3.rb).
    obj.instance_variable_set(:@new_record, false)
    obj.instance_variable_set(:@destroyed, false)
    obj.instance_variable_set(:@readonly, false)
    obj
  end

  def default_int(col)
    col == "id" ? 1 : 0
  end

  # results3/people_show FIX (ported from results3/people_stream, same
  # rationale): real `redirect_to` sets `self.response_body = ""` as its LAST
  # step (actionpack redirecting.rb `def redirect_to` -> `self.response_body
  # = ""`) — this is what marks `performed?` (== `!! response_body`) true.
  # The Y3/X6g redirect_to mocks below return a terminal marker WITHOUT ever
  # touching `response_body`, which was harmless while `default_render` (Y2)
  # was ALSO a terminal no-op (results2 and earlier) but is NOT harmless now
  # that Y2 is removed (results3 discipline — see file header):
  # `BasicImplicitRender#send_action` calls `default_render unless
  # performed?` after EVERY action, so a same-action redirect (or
  # `redirect_back`, used by the AccountClosed rescue_from) whose mock never
  # sets performed? now falls through into the REAL `default_render` ->
  # `ActionController::UnknownFormat`. Guarded (never let this crash the
  # mock) since @_response can be nil in some harness configurations.
  def mark_redirect_performed!(receiver)
    receiver.response_body = "" if receiver.respond_to?(:response_body=)
  rescue StandardError
    nil
  end

  # Shared single-record finder mock. raise_on_missing: true  -> find/!-style
  #                                   raise_on_missing: false -> find_by/take/first
  #
  # 2026-09-04 (people_show adversarial repair R1): ported from
  # notifications_index finder_note (T4 / over-emission fix 2026-08-28) — a
  # single-row finder's REAL statement carries `ORDER BY <pk>` when the
  # relation has no order of its own (Rails `find_nth` -> ordered_relation)
  # and always `LIMIT 1`. Without them note_fidelity_audit reports
  # LIMIT-DIFF/ORDER-DIFF on every finder note (blocks/contacts/
  # people.owner_id/profiles.person_id all carry `LIMIT ?` in the real
  # statements; people.diaspora_handle carries `ORDER BY people.id ASC
  # LIMIT ?`). The finder_sql kwargs merge (P-4/P-5) runs first, then the
  # ORDER/LIMIT suffixes are appended to the finished note.
  def finder_note(receiver, args, kind = :find_by)
    sql = finder_sql(receiver, args)
    begin
      if %i[first last take].include?(kind) && !sql.include?(" ORDER BY ")
        klass = model_class(receiver)
        table = klass.table_name
        pk    = (klass.primary_key || "id")
        dir = (kind == :last ? "DESC" : "ASC")
        sql = %(#{sql} ORDER BY "#{table}"."#{pk}" #{dir})
      end
    rescue StandardError
      nil
    end
    sql =~ /\sLIMIT\s/ ? sql : "#{sql} LIMIT 1"
  end

  # 2026-09-04 (people_show adversarial repair R1): real aggregate queries
  # (COUNT(*) / exists? 1 AS one) DROP the relation's ORDER BY — Rails
  # `count`/`exists?` execute against the relation without ordering. The
  # notes from sql_for keep the relation's scope order (e.g. aspects
  # default-scope `order(order_id)`, photos `created_at DESC`), producing
  # ORDER-DIFF verdicts in note_fidelity_audit. Strip `ORDER BY …` (up to
  # LIMIT/OFFSET/end) from aggregate-style notes.
  def strip_order_for_aggregate(sql)
    sql.sub(/\s+ORDER BY\s+.*?(?=\s+LIMIT\s|\s+OFFSET\s|\Z)/m, "")
  end

  def finder_mock(raise_on_missing:, kind: :find_by)
    lambda do |receiver, args, name|
      sql = finder_note(receiver, args, kind)
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

  # 2026-09-04 (people_show adversarial repair R1, P-4/P-5): find_by notes
  # must carry the real WHERE. Two gaps: (1) a Relation receiver's arel does
  # NOT include the conditions passed to find_by (they are applied INSIDE the
  # body, which the mock skips) and (2) the interceptor's wrapper is defined
  # with **kwargs so hash-call find_by(user_id: …, person_id: …) binds the
  # args into kwargs — call_args gets nil and even extract_finder_where finds
  # nothing (src/ gap documented in class_finder_sql's fallback). PeopleTargets
  # prepends PeopleShowFindByKwargs (targets.rb) which stashes the kwargs in a
  # thread-local around the call; this helper merges them into the note.
  def finder_sql(receiver, args)
    return class_finder_sql(receiver, args) if receiver.is_a?(Class)
    sql = render_relation_sql(receiver)
    wh = extract_finder_where(receiver, args)
    kw = Thread.current[:people_show_find_by_kwargs]
    wh = kw if (wh.nil? || wh.empty?) && kw.is_a?(Hash) && !kw.empty?
    return sql if wh.nil? || wh.empty?
    table = model_class(receiver).respond_to?(:table_name) ? model_class(receiver).table_name : nil
    return sql if table.nil?
    conds = wh.map { |k, v| %("#{table}"."#{k}" = #{render_arg_value(v)}) }.join(" AND ")
    if sql =~ /\bWHERE\b/
      sql.sub(/\bWHERE\b/, "WHERE #{conds} AND ")
    elsif sql =~ /\bLIMIT\b/
      sql.sub(/\bLIMIT\b/, "WHERE #{conds} LIMIT ")
    else
      "#{sql} WHERE #{conds}"
    end
  rescue StandardError => e
    "#{model_class(receiver).name} finder (note merge failed: #{e.class})"
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
      "service", # people_show R1: Service#provider/#nickname publisher leaves (attr_accessor, not a column)
      "taggable", "reshare", "person", "profile", "mentionable",
      "mentions_container", "message_renderer", "post_presenter",
      "aspect_membership", "aspect", "block",
      # results3/people_show ADDITION: PersonPresenter#description (targets.rb
      # descent) needs `defined?(PersonPresenter)` true at install! time, but
      # neither presenter was in this eager-load list — Rails autoloading
      # only resolved them on first reference DURING a real request, by which
      # point install! had already run and the descent's `defined?` guard
      # silently evaluated false, leaving `description` unmocked (found live:
      # the mock's own symbolic_call event never appeared in a scratch dump,
      # and the real body's raw `bio` SymbolicString reached Rails' HTML-
      # escape pipeline instead).
      "person_presenter", "profile_presenter",
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
      kind = { take!: :take, first!: :first, last!: :last, find_by!: :find_by }.fetch(m, :find_by)
      interceptor.declare_target(fm, m, returns: finder_mock(raise_on_missing: true, kind: kind))
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
    interceptor.declare_target(core, :find,     returns: finder_mock(raise_on_missing: true, kind: :find))
    interceptor.declare_target(core, :find_by,  returns: finder_mock(raise_on_missing: false, kind: :find_by))
    interceptor.declare_target(core, :find_by!, returns: finder_mock(raise_on_missing: true, kind: :find_by))

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
        # finder_sql (not sql_for): merges find_by/exists? kwargs/hash
        # conditions into the note (P-2: Post.exists?(guid: …) real shape is
        # SELECT 1 AS one FROM posts WHERE guid = ? LIMIT ?).
        note = (m == :exists? ? finder_sql(receiver, args) : sql_for(receiver, args))
        # 2026-09-04 (people_show adversarial repair R1, P-2, matrix T-a):
        # FinderMethods#exists? stands in for the existence probe
        # `SELECT 1 AS one FROM <t> WHERE <col> = ? LIMIT ?` — never
        # SELECT t.* (T4). Rewrite the projection + append LIMIT 1.
        if m == :exists?
          begin
            note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT 1 AS one FROM ")
            note = strip_order_for_aggregate(note)
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
        # Same idiom as the `records`/`load_target` mock below (line ~902):
        # prefer the batch-local iterable subclass when it is defined, so a
        # list produced HERE has the same `each`/`map`/`include?` surface as
        # one produced by targets.rb's rows_mock. Resolved at CALL time, so
        # targets.rb having loaded later is not a problem.
        list_class_1b = defined?(IterableSymbolicList) ? IterableSymbolicList : SymbolicList
        list_class_1b.new(seed_for(SymbolicVar.len_var_name(vn), 1), name: vn,
                       note: sql_for(receiver, args), representative: rep)
      end)
    end
    interceptor.declare_target(rel, :size, returns: lambda do |receiver, args, name|
      vn = "#{name}_size"
      note = sql_for(receiver, args)
      begin
        note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT COUNT(*) FROM ")
        note = strip_order_for_aggregate(note)
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
          note = strip_order_for_aggregate(note)
        rescue StandardError
          nil # projection rewrite must never crash the mock
        end
        symint(vn, seed_for(vn, m == :count ? 1 : 0), note: note)
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
    %i[pluck average minimum maximum calculate].each do |m|
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
    # write family's legacy notes are non-SQL strings, so `_is_dml` in both
    # judges DROPS them — no symbolic_call could carry an UPDATE, and the
    # real `UPDATE "notifications" SET "unread" = ? WHERE id = ?` (from
    # Notification#set_read_state -> Persistence#update_column, fired by
    # people_controller#show:173-177 mark_corresponding_notifications_read on
    # EVERY signed-in show) scored NOTE-MISSING. update_column/update_columns
    # are UNCONDITIONAL writes (no dirty gate — exact note, no over-emission).
    # Dirty-gated members (save/update/...) keep their legacy notes here;
    # this endpoint's show path only reaches update_column via set_read_state.
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

    # results3/people_show DESCENT (MOCK_AUDIT VIOLATION, PHASE_A_PATCH.md
    # Patch 3's note): `Post.blocked_people` used to be Gate-1b-split out of
    # `excluding_blocks` (`user.blocks.map{|b| b.person_id}`) and mocked to a
    # concrete `[]`. Its real body calls `user.blocks` — a separately
    # declared target (above) that Patch 3 gave a real SQL note — but the
    # outer mock here meant that sibling mock's note never actually fired
    # along this call path. REMOVED so `excluding_blocks` calls the real
    # (undeclared) `blocked_people` -> real `user.blocks.map{...}` -> the
    # note-fixed `User#blocks` mock -> `IterableSymbolicList#map`
    # (targets.rb). Not confirmed reached by people#show's own call graph
    # (this endpoint's html/json render doesn't chain through
    # Post.for_a_stream at all — no stream is built by #show/#index — so
    # this descent is likely DEAD here, same "descend per discipline even if
    # unreachable on this entrypoint" treatment MOCK_AUDIT.md gives
    # SingularAssociation#writer); kept removed for discipline consistency
    # with the sibling endpoints regardless.

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

    # Mobile render wall (2026-09-03, anon_mobile scenario, cycle 1):
    # shared/_stream_element.mobile.haml -> shared/_post_info.mobile.haml:31
    # reads `post.location` on every stream post. `location` is NOT a Post
    # column (the schema's `location` string lives on `profiles`); it exists
    # as a real association reader ONLY on the STI subclass StatusMessage
    # (`has_one :location`, status_message.rb:25). On a base-Post
    # symbolic_instance rep (decorated_stream_posts mints class Post
    # exactly), `post.location` hits AR method_missing -> NoMethodError,
    # killing the whole mobile render at 32/40 explored paths (cycle-1
    # corpus: ActionView::Template::Error 32x).
    #
    # NOT a declare_target: `location` does not exist on base Post, and
    # declare_target requires an existing instance_method to wrap. The shim
    # lives as a PREPEND module in targets.rb (PostSymLocation,
    # PeopleShowSymParams.install!) — SAFE against the STI reader: Rails
    # generates has_one readers on the DECLARING class (StatusMessage), so
    # StatusMessage#location wins method resolution for real StatusMessage
    # instances; the prepend only ever fires on plain-Post reps, where the
    # association does not exist. Returns nil (the rig's documented
    # nil-passthrough), so the template guard `if ... post.location` takes
    # the FALSE side — a FREE decision: this rig loads no Location rows (the
    # Location table is never seeded/queried on this entrypoint), so the
    # location-present branch (`post.location.address` render) is
    # unreachable by construction.
    # Runner-local (this endpoint's private fork), NOT a shared-boundary
    # change — Rule T untouched.

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

    # Y2. REMOVED for results3 (see file-header MOCK LEDGER) —
    # `ActionController::ImplicitRender#default_render` is the entry point
    # `format.html`/`format.all` (no block) uses, and its real body just
    # calls `render` (Z's target, also removed below). Mocking it here would
    # silently no-op the entire HTML template pipeline this endpoint exists
    # to exercise, one frame before Z's own boundary. Left undeclared so the
    # real `default_render` -> `render` chain runs.

    # Y3. redirect_to / url_for — engine/Devise routes are not loaded in the
    # ActionController::TestCase rig, so url generation raises
    # UrlGenerationError (9 crashes) after the action's real logic has run.
    # redirect_to is terminal (a 302 render); url_for is a pure URL builder
    # (not branched). Treat redirect_to as terminal render (marking
    # performed? — see mark_redirect_performed! above, results3 fix), and
    # url_for as a benign no-op returning a concrete URL string.
    if defined?(ActionController::Redirecting)
      interceptor.declare_target(ActionController::Redirecting, :redirect_to, returns: lambda do |r, _a, _n|
        mark_redirect_performed!(r)
        :redirect_reached
      end)
    end
    if defined?(ActionDispatch::Routing::UrlFor)
      # results3: ConcreteSymbolicString-wrapped (see comment above X6i) — a
      # bare String return here is NOT exempt from the interceptor's
      # re-wrap-into-SymbolicString post-processing, and this endpoint's real
      # HTML render can feed the result into native string ops.
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

    # --- Z. REMOVED for results3 (see file-header MOCK LEDGER) —
    # `ActionController::Rendering#render`/`#render_to_string`/
    # `#render_to_body` are exactly the SQL-adjacent (via the per-row target
    # fetches the templates trigger) chain this endpoint's rebuild exists to
    # let run for real — people#show's whole mission is the real view/
    # presenter pipeline (PersonPresenter/ProfilePresenter#as_json,
    # show.html.haml). Left undeclared; the real render pipeline runs and any
    # walls it hits are closed at genuine SQL-free leaves below/in
    # ./targets.rb instead (per (b): mock the leaf, never the render call
    # that encloses the query chain).

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
              # itself crash the mock (mirrors sql_for's own rescue-wraps-all
              # philosophy) -- fall back to the old junk note on any failure.
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
                # RC-1 (2026-09-19): real default projection, not a hardcoded
                # star. THIS is the site that produced all 34 884 bare
                # `SELECT "profiles".*` reads in the pre-reopen people_show
                # corpus (every single one of them came from here).
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
                                 returns: lambda do |r, _a, _n|
                                   mark_redirect_performed!(r)
                                   :redirect_reached
                                 end)
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
    # gon is pure JS-var accumulation; nothing branchable, no SQL.
    if defined?(Gon::ControllerHelpers)
      interceptor.declare_target(Gon::ControllerHelpers, :gon,
                                 returns: lambda do |receiver, _args, _name|
        # Real body, gon-6.3.2 helpers.rb:29-37 (with the rig's RequestStore
        # guard the notifications batch verified).
        req = receiver.respond_to?(:request) ? receiver.request : nil
        store = defined?(::RequestStore) ? ::RequestStore.store : nil
        if store && req && req.respond_to?(:env) && req.respond_to?(:uuid)
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

    # results3 NEW: ConcreteSymbolicString. Every "-> concrete string" mock
    # below (X6i/X6l/X6h/X8d) predates results3's render-family removal and
    # was written/verified back when `render`/`render_to_string` were mocked
    # terminal — so NONE of these concrete-string returns were ever actually
    # fed into Rails' OWN internal HTML-escaping machinery before now. A bare
    # Ruby `String` returned from a declare_target mock is NOT exempt from
    # the interceptor's `to_symbolic` return-value wrapping (only `nil` and
    # already-`SymbolicVar`-tagged values are) — so a "concrete" return gets
    # silently RE-WRAPPED into a `SymbolicString` by the interceptor, and
    # `SymbolicString#scrub`/`#gsub`/etc. are (correctly) unsupported. A real
    # `::String` subclass that also `include`s `SymbolicVar` behaves like a
    # native string for EVERY string op while still being recognized by the
    # interceptor as already-symbolic (skip re-wrap). Ported verbatim from
    # results3/people_stream (same bug, same fix).
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

    # results3/people_show DESCENT (MOCK_AUDIT: Person#name VIOLATION —
    # "profile.first_name/last_name reads route through
    # SingularAssociation#find_target... mocking the whole reader to a fixed
    # string skips that association load"). people#show renders @person.name
    # in the page title, meta tags, PersonPresenter#base_hash, and
    # PostPresenter titles — descended per the mission brief ("since the page
    # renders names everywhere, take the descent if proportionate"): Patch 1
    # (above) already gives `SingularAssociation#find_target` a real SQL
    # note, so `self.profile` now loads for real (a genuine, note-carrying
    # `SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" =
    # $$(...)` query) instead of being swallowed by an outer Person#name mock.
    # Person#name's OWN real body (person.rb:246-250) is:
    #   def name(opts = {})
    #     fix_profile if self.profile.nil?
    #     @name ||= Person.name_from_attrs(profile.first_name, profile.last_name, diaspora_handle)
    #   end
    # `self.profile.nil?` is a bare-truthiness Object#nil? check on a
    # symbolic instance (never nil, TODO.txt gap — always false, so
    # `fix_profile` — itself a SQL-free `Profile.new(person: self)` builder
    # never called by DSE-relevant runs — is skipped). `profile` itself now
    # runs for real (Patch 1). The ONLY remaining wall is
    # `Person.name_from_attrs`'s OWN body doing `.to_s.strip` on the
    # (symbolic) first_name/last_name SymbolicStrings — `strip` is
    # UNSUPPORTED. `name_from_attrs` is a class method, SQL-free, calls no
    # other declared target (pure string formatting) — exactly the
    # "smallest enclosing SQL-free leaf" the wall-fixing discipline demands,
    # narrower than mocking `Person#name` itself (which would have skipped
    # the now-real `profile` association load). Mocked here (not
    # targets.rb) since it lives in the shared discipline-descent set, same
    # as the other X6-family narrowings.
    # results3/people_show DESCENT (found live in a scratch validation run,
    # not in MOCK_AUDIT.md — a NEW wall this endpoint's real render pipeline
    # exposes that no completed sibling reaches):
    # `PersonPresenter#metas_attributes` (og_profile_firstname/lastname
    # fields, reached from show.html.haml's `content_for :meta_data` on
    # EVERY html-format run) calls `first_name`/`last_name` via
    # BasePresenter#method_missing -> Person#first_name (person.rb:258-266):
    #   def first_name
    #     @first_name ||= if profile.nil? || profile.first_name.nil? || profile.first_name.blank?
    #                 self.diaspora_handle.split('@').first
    #               else
    #                 names = profile.first_name.to_s.split(/\s/)
    #                 ...
    #               end
    #   end
    # `.split('@')` -> a SymbolicString::SplitAccessor with no `#first`
    # (ActionView::Template::Error); `.split(/\s/)` -> NotImplementedError
    # directly ("only supports single-character separators", string.rb:235).
    # `first_name` is a pure string-transform (SQL-free); the ONLY declared
    # target it touches is `profile` (SingularAssociation#find_target) via
    # its own guard clause — but on EVERY run of this endpoint's html/json
    # scenarios, `profile`'s association is ALREADY loaded for real earlier
    # in the SAME run (`gon.preloads[:person] = @presenter.as_json` /
    # `render json: @presenter.as_json` both run BEFORE metas_attributes is
    # reached, per people_controller.rb:78-89, and both walk
    # ProfilePresenter -> `profile.first_name`/`.tags` directly) — so
    # `@association_cache` already holds the row; mocking first_name loses
    # no NEW SQL, only a would-be cache hit. Computed from the receiver's OWN
    # concrete seed attrs (diaspora_handle) without touching `profile` at
    # all, to avoid ANY risk of re-triggering a load on some future/renamed
    # scenario where the ordering assumption above doesn't hold (documented
    # here explicitly so that assumption is checkable, not silent).
    if defined?(Person) && Person.instance_methods.include?(:first_name)
      interceptor.declare_target(Person, :first_name, returns: lambda do |receiver, _args, name|
        dh = receiver.respond_to?(:[]) ? receiver[:diaspora_handle] : nil
        dh_val = dh.respond_to?(:value) ? dh.value : dh.to_s
        ConcreteSymbolicString.build(dh_val.to_s.split('@').first.to_s, name: name,
                                     note: "Person#first_name (untracked profile.blank? decision, diaspora_handle fallback shape)")
      end)
    end

    # results3/people_show DESCENT — same wall family as Person#first_name
    # above, found in the same scratch validation run:
    # `Person#last_name` is `delegate :last_name, ..., to: :profile`
    # (person.rb:27-29) — a plain accessor with NO string-formatting logic,
    # unlike first_name's split/blank branch, so this is not descended from
    # any documented MOCK_AUDIT violation. It reads `profile.last_name`
    # directly — a genuine, still-tracked SymbolicString column value — and
    # that value hits Rails' real HTML-escape pipeline
    # (`PersonPresenter#metas_attributes`'s `og_profile_lastname` field ->
    # `meta_tag` -> `tag_option` -> `unwrapped_html_escape` ->
    # `ActiveSupport::Multibyte::Unicode#tidy_bytes` -> `.scrub`, UNSUPPORTED
    # by design on a tracked SymbolicString). `last_name` itself is SQL-free
    # and calls no OTHER declared target beyond the association's own
    # (already-loaded-elsewhere, per the first_name comment above) `profile`
    # read — the smallest available leaf, since it is a delegate with no
    # named sub-step to split further without editing app source.
    if defined?(Person) && Person.instance_methods.include?(:last_name)
      interceptor.declare_target(Person, :last_name, returns: lambda do |receiver, _args, name|
        ConcreteSymbolicString.build("Concolic-Last-Name", name: name,
                                     note: "Person#last_name (delegate to profile.last_name, untracked HTML-escape leaf)")
      end)
    end

    if defined?(Person) && Person.respond_to?(:name_from_attrs)
      interceptor.declare_target(
        Person.singleton_class, :name_from_attrs,
        returns: lambda do |_r, args, name|
          # NOTE (honest limitation): declare_target's param-binding loop runs
          # every captured positional arg through `to_native` (symbolic_func.rb)
          # BEFORE the mock lambda ever sees it — first_name/last_name/
          # diaspora_handle arrive as plain concrete Ruby strings, symbolic
          # identity already stripped. This is a src/ behavior (out of scope
          # to change, same family as Patch 2's documented kwargs gap), NOT
          # something this mock can recover. Consequence: the blank?/blank?
          # branch below is decided CONCRETELY off the seed value — it is not
          # a recorded, DSE-flippable PC (no `record!` call happens; nothing
          # is fabricated — this is simply not tracked, exactly the "bare-
          # truthiness... non-fatal but untracked" case results3/README.md
          # documents). The genuinely tracked/flippable branch is upstream:
          # whichever finder_mock decided the `profile`/`person` row's
          # first_name/last_name seed values in the first place.
          fn = args["first_name"].to_s
          ln = args["last_name"].to_s
          dh = args["diaspora_handle"].to_s
          if fn.strip.empty? && ln.strip.empty?
            ConcreteSymbolicString.build(dh, name: name, note: "Person.name_from_attrs (diaspora_handle fallback, untracked blank? decision)")
          else
            ConcreteSymbolicString.build("#{fn.strip} #{ln.strip}".strip, name: name, note: "Person.name_from_attrs (untracked blank? decision)")
          end
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
    #
    # P-2 (2026-09-04, adversary R1): the pipe is NOT always SQL-free —
    # diaspora_links runs `Post.exists?(guid: url[3])` for diaspora:// post
    # URLs (ProfilePresenter#private_hash bio/location on people_show). For
    # PLAIN String messages (bio/location seeded via symbolic_instance's
    # @bio_message/@location_message overrides) replicate diaspora_links so
    # the declared FinderMethods.exists? target fires (P-2 posts.guid shape:
    # SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?). For
    # SymbolicString messages keep the concrete fallback (stream post text)
    # to avoid the SymbolicString#gsub wall.
    if defined?(Diaspora::MessageRenderer::Processor) &&
       Diaspora::MessageRenderer::Processor.respond_to?(:process)
      interceptor.declare_target(
        Diaspora::MessageRenderer::Processor.singleton_class, :process,
        returns: lambda do |_r, args, name|
          m = args["message"]
          if m.is_a?(SymbolicString)
            v = m.value
          else
            v = m.to_s
            # replicate diaspora_links (message_renderer.rb) for plain text:
            # the real pipe reaches a declared target here (Post.exists?)
            if defined?(DiasporaFederation::Federation::DiasporaUrlParser::DIASPORA_URL_REGEX)
              v = v.gsub(DiasporaFederation::Federation::DiasporaUrlParser::DIASPORA_URL_REGEX) do |match_str|
                guid = Regexp.last_match(3)
                # P-2: pass the guid as a SymStr so the finder mock renders
                # `WHERE "posts"."guid" = $$(SYM_...)` (a $$ bind — the
                # concrete-quoted literal would not wildcard to the real
                # `=?` bind in mock_note_check).
                sym_guid = symstr("SYM_POSTS_GUID", guid.to_s, note: "bio/location diasporalink guid")
                (Regexp.last_match(2) == "post" && Post.exists?(guid: sym_guid)) ?
                  AppConfig.url_to("/posts/#{guid}") : match_str
              end
            end
          end
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
