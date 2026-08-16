# frozen_string_literal: true
#
# Per-batch concolic targets — `posts`.
#
# Installs AFTER `ConcolicTargets.install!`. `declare_target` uses
# `define_method`, so a later declaration REPLACES an earlier one (last-one-wins).
# In body-skip mode the captured `original` is never invoked, so re-declaring an
# already-instrumented method produces exactly one TargetCall + one
# SymbolicCallRecord — no double counting, no ordinal drift.
#
#   ConcolicTargets.install!(interceptor)   # shared generic AR interception
#   PostsTargets.install!(interceptor)      # this file — batch-local wall fixes
#
# THE TWO WALLS THIS BATCH HITS
# -----------------------------
#   1. NotImplementedError: SymbolicList#each   — 1536 of 1540 reshares_create
#      dumps, at PostInteractionPresenter#as_api (post_interaction_presenter.rb:29,
#      `collection.includes(author: :profile).map { ... }`).
#   2. NotImplementedError: Calculations#pluck  — status_messages_create, at
#      StatusMessage#people_allowed_to_be_mentioned (status_message.rb:121).
#
# NEITHER is fixed by mocking the enclosing app method:
#   * `as_api`'s body fires `Relation#records` (a declared target) — mocking it
#     would hide the symbolic query chain.
#   * `people_allowed_to_be_mentioned`'s body IS the branch (`if public?`), so
#     mocking it is the exact regression the addendum warns about.
#
# Both are fixed at the MOCK BOUNDARY instead — which is where src/ruby_runtime
# says they belong. list.rb's header states the design explicitly:
#
#     "Iteration (each/map/reject/select/find) STAYS unimplemented — iteration is
#      handled by caller-wrapping at the mocked boundary, never executed against
#      the list."
#
# So `SymbolicList#each` raising is NOT a src/ bug to patch; the missing piece is
# the caller-side wrapper the design calls for, and a wrapper is exactly what a
# batch-local target file is allowed to provide. Nothing under src/ is modified.

module PostsTargets
  module_function

  # =====================================================================
  # IterableSymbolicList — the "caller-wrapping at the mocked boundary"
  # that src/ruby_runtime/list.rb's design mandates, implemented as a
  # runner-local SUBCLASS so that src/ is untouched.
  #
  # Semantics (a faithful extension of the Gate 1b representative model):
  #
  #   len == 0  ->  iterate zero times
  #   len != 0  ->  iterate EXACTLY ONCE over the single representative row
  #
  # and record the canonical `(len(X) != 0)` path condition on entry, with
  # taken = non-empty. That expression is identical to the one #empty? / #any?
  # already emit, so it path-signature-matches, and `len(X)` is already a
  # seedable key (the collection mock builds the length via
  # seed_for("len(NAME)", ...) — concolic_targets.rb:452). The DSE runner's
  # flip_seed already understands `(len(NAME) != 0)`, so iterate-vs-skip
  # becomes a genuinely flippable branch instead of a crash.
  #
  # HONEST LIMITS (unchanged from the base class, restated because iteration
  # makes them observable):
  #   * ONE representative row is modeled, not N. A list seeded len=3 still
  #     yields once. Distinct-row branching is not modeled.
  #   * A non-empty list with NO representative still raises loudly rather
  #     than silently yielding nothing — an unmodelable iteration must stay a
  #     visible wall, not become a silent empty loop.
  #
  # `include Enumerable` was tried first and REJECTED: Enumerable sits between
  # this class and SymbolicList in the ancestor chain, so it also shadows the
  # tracked API (first / count / include? / any? / none?), and re-binding those
  # back through a wrapper made every one of their path conditions report
  # `targets.rb` as its source frame instead of the app line. Iteration methods
  # are therefore delegated EXPLICITLY to a materialised row array, leaving
  # everything SymbolicList already tracked completely untouched and
  # byte-identical.
  #
  # `to_ary` is deliberately NOT among them and keeps raising: it is Ruby's
  # IMPLICIT array-conversion protocol, and defining it would silently change
  # destructuring / splat / puts behaviour at call sites that never asked to
  # iterate. `to_a` (explicit) is provided.
  # =====================================================================
  class IterableSymbolicList < SymbolicList
    def each(&blk)
      return to_enum(:each) unless blk
      __rows.each(&blk)
      self
    end

    ITERATION_OPS = %i[
      map collect flat_map collect_concat
      select filter find_all reject filter_map
      find detect find_index each_with_index each_with_object each_entry
      sort_by group_by partition min_by max_by
      sum reduce inject tally zip take drop to_a
    ].freeze

    ITERATION_OPS.each do |m|
      define_method(m) do |*args, &blk|
        __rows.public_send(m, *args, &blk)
      end
    end

    private

    # Materialise the modeled contents. Records the canonical emptiness PC
    # exactly once per iteration site, then returns either [] or the single
    # representative row.
    def __rows
      nonempty = !concrete_length.zero?
      record!("(#{symbolic_len} != 0)", "each", taken: nonempty)
      return [] unless nonempty

      if representative.nil?
        raise NotImplementedError,
              "IterableSymbolicList#each: list #{self} is non-empty but carries no " \
              "representative row, so its contents cannot be modeled. " \
              "(Wall kept visible on purpose — see results/posts/targets.rb.)"
      end
      [representative]
    end

    public

    # acts_as_api serialisation of a collection. `CommentPresenter#as_json`
    # calls `@comment.mentioned_people.as_api_response(:backbone)` INLINE — there
    # is no enclosing presenter method to mock the way PostPresenter's
    # `build_mentioned_people_json` is mocked (concolic_targets.rb X6k), so the
    # list itself has to answer. Iteration-shaped, same one-rep semantics.
    def as_api_response(*args)
      __rows.map { |r| r.respond_to?(:as_api_response) ? r.as_api_response(*args) : r }
    end
  end

  # =====================================================================
  # SuccIntValue — SymbolicInt plus #next / #succ.
  #
  # `User#update_or_create_participation!` (social_actions.rb:56) does
  # `participation.update!(count: participation.count.next)`. `count` is an
  # INTEGER COLUMN on a symbolic model instance, so it is a SymbolicInt, and
  # SymbolicInt lists :next/:succ among its raising arithmetic stubs
  # (int.rb:55-66).
  #
  # `+1` is exactly as soundly expressible in Z3 as the unary minus that
  # SymbolicInt#-@ (int.rb:78-80) ALREADY models symbolically rather than
  # raising — so this follows an existing runtime precedent rather than
  # inventing semantics. The naming convention matches -@'s: the result is a
  # named symbolic value whose name is the arithmetic expression.
  #
  # Scope note: only #next/#succ are added. The rest of SymbolicInt's
  # arithmetic (+ - * / ...) still raises, because those take an operand whose
  # own symbolic expression would have to be composed — a bigger change than
  # this batch needs, and the documented core design constraint.
  # =====================================================================
  class SuccIntValue < SymbolicInt
    def next
      SuccIntValue.new(value + 1,
                       name: sym_name ? "(#{sym_name} + 1)" : nil, note: note)
    end
    alias succ next
  end

  # Swap every plain SymbolicInt attribute of a symbolic model instance for a
  # SuccIntValue. Mutates the `attrs` Hash that `symbolic_instance`'s column
  # readers close over (`obj.define_singleton_method(col) { attrs[col] }`), so
  # the readers observe the swap. Booleans are SymbolicBool (a separate class,
  # not a SymbolicInt subclass) and their predicate readers capture the value
  # object directly, so they are untouched by construction.
  def upgrade_ints!(obj)
    return obj unless obj.respond_to?(:concolic_attrs)
    attrs = obj.concolic_attrs
    attrs.keys.each do |col|
      v = attrs[col]
      next unless v.instance_of?(SymbolicInt)
      attrs[col] = SuccIntValue.new(v.value, name: v.sym_name, note: v.note)
    end
    obj
  rescue Exception # rubocop:disable Lint/RescueException
    obj
  end

  # Batch-local SUBCLASS adding the one string operation this batch's last wall
  # needs. Same discipline as search_links_reports_profiles §3: implemented ONLY
  # where the answer is EXACT for the concrete witness, and raises loudly
  # otherwise. It never concretizes and never invents a Z3 term.
  #
  # THE WALL: `Diaspora::Mentionable.filter_people` (mentionable.rb:59-72) does
  #     mentioned_ppl = people_from_string(msg_text)
  #     msg_text.to_s.gsub(REGEX) {|m| ... }
  # reached from StatusMessage#filter_mentions (status_message.rb:127) on
  # status_messages#create. `gsub` is in the runtime's UNSUPPORTED table
  # (string.rb:325).
  #
  # `filter_people` CANNOT be mocked: its body calls `people_from_string`, which
  # is itself a declared target (§5), so mocking it would hide that symbolic
  # query chain — the README invariant. `filter_mentions` is worse: its body IS
  # the branch (`return if people_allowed_to_be_mentioned == :all`). So fix the
  # VALUE.
  #
  # EXACTNESS: REGEX is the mention syntax /@\{(?:([^\}]+?); )?([^\} ]+)\}/.
  # When the witness contains no mention, `gsub(REGEX)` provably returns an
  # equal string, so returning SELF is exact and preserves sym_name, note and
  # the whole constraint history. When the witness DOES contain one, the result
  # depends on the string's contents — which SymbolicString does not model — so
  # it raises, exactly as it does today. This is therefore strictly no worse
  # than the status quo: it can only turn a crash into a faithful no-op.
  def define_substitutable_string!
    return if defined?(::SubstitutableSymbolicString)

    ::Object.const_set(:SubstitutableSymbolicString, Class.new(SymbolicString) do
      def gsub(pattern, *rest, &_blk)
        rx = pattern.is_a?(Regexp) ? pattern : Regexp.new(Regexp.escape(pattern.to_s))
        return self if rest.empty? && !(value =~ rx)

        raise NotImplementedError,
              "SubstitutableSymbolicString#gsub(#{pattern.inspect}): witness " \
              "#{value.inspect} matches the pattern, so the result depends on " \
              "string contents the runtime does not model. Only the provably- " \
              "identity case (no match, no replacement argument) is supported."
      end
    end)
  end

  # Swap the `text` column of a symbolic model instance for a
  # SubstitutableSymbolicString. Mutates the same `attrs` Hash the column
  # readers close over, and installs NO new singleton — re-installing one here
  # would shadow app readers that take an argument (measured in the photos
  # batch: a blanket string upgrade that re-installed readers broke
  # `Profile#image_url(size)` across 46 dumps).
  #
  # Deliberately narrow: `text` is the only string this batch substitutes over.
  def upgrade_text!(obj)
    return obj unless obj.respond_to?(:concolic_attrs)
    attrs = obj.concolic_attrs
    v = attrs["text"]
    if v.instance_of?(SymbolicString)
      attrs["text"] = ::SubstitutableSymbolicString.new(v.value, name: v.sym_name, note: v.note)
    end
    obj
  rescue Exception # rubocop:disable Lint/RescueException
    obj
  end

  # ---------------------------------------------------------------------

  def install!(interceptor = CallInterceptor.instance)
    define_substitutable_string!
    ct  = ConcolicTargets
    rel = ActiveRecord::Relation
    calc = ActiveRecord::Calculations
    cproxy = defined?(ActiveRecord::Associations::CollectionProxy) ?
               ActiveRecord::Associations::CollectionProxy : nil
    null_rel = defined?(ActiveRecord::NullRelation) ? ActiveRecord::NullRelation : nil

    # -------------------------------------------------------------------
    # 0. Batch-local wrapper around ConcolicTargets.symbolic_instance.
    #
    # The shared file stays untouched; only the live method object is
    # re-pointed, and only inside this process. `module_function` gives
    # ConcolicTargets a SINGLETON copy of symbolic_instance, and the shared
    # mocks call it bare with `self == ConcolicTargets`, so they resolve to
    # that singleton — re-aliasing it therefore covers the shared mocks'
    # internal calls too, not just my own.
    # -------------------------------------------------------------------
    unless ct.respond_to?(:__posts_orig_symbolic_instance)
      ct.singleton_class.send(:alias_method,
                              :__posts_orig_symbolic_instance, :symbolic_instance)
      ct.singleton_class.send(:define_method, :symbolic_instance) do |klass, base_name, sql|
        PostsTargets.upgrade_text!(
          PostsTargets.upgrade_ints!(__posts_orig_symbolic_instance(klass, base_name, sql)))
      end
    end

    # -------------------------------------------------------------------
    # 1. Collection materialization -> ITERABLE symbolic list.
    #
    # Same contract as the shared §C mock (concolic_targets.rb:449-453): same
    # var names (`<name>_rows`, `len(<name>_rows)`), same seed_for key, same
    # note (rendered SQL), same symbolic_instance representative. The ONLY
    # difference is the class, which adds the caller-side iteration wrapper.
    #
    # This does NOT swallow a branch: the query still runs through the declared
    # target, the length is still symbolic and seedable, and #empty?/#any?
    # still record. It only replaces a crash with an execution.
    #
    # NullRelation short-circuit: `PostInteractionPresenter#participations`
    # returns `@post.participations.none` when there is no current_user. A
    # NullRelation is DEFINED to be empty and issues no SQL, so there is no
    # query to preserve and no declared target beneath it. Without this,
    # iteration would fabricate a representative row for a relation that can
    # never have one — an unsound over-approximation that only became
    # observable once #each stopped raising.
    # -------------------------------------------------------------------
    rows_mock = lambda do |receiver, args, name|
      next [] if null_rel && receiver.is_a?(null_rel)

      vn  = "#{name}_rows"
      sql = ct.sql_for(receiver, args)
      rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", sql)
      IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1),
                               name: vn, note: sql, representative: rep)
    end

    %i[to_a to_ary records].each do |m|
      interceptor.declare_target(rel, m, returns: rows_mock)
    end

    # ...AND on CollectionProxy, which OVERRIDES Relation#records.
    #
    # `ActiveRecord::Associations::CollectionProxy#records` (collection_proxy.rb
    # :1003) is `load_target` — its own method, so a target declared on
    # ActiveRecord::Relation never fires for it. `Relation::Delegation` sends
    # `each`/`map` to `records` (delegation.rb:71), so `@post.reshares.map` in
    # BasePresenter.as_collection (base_presenter.rb:14) went through the
    # UNMOCKED association path and produced a plain, non-iterable SymbolicList
    # — 259 of the dumps in the first overlay run still died on
    # `SymbolicList#each` for exactly this reason.
    #
    # Routing the association load through the same mock also makes it a
    # RECORDED symbolic query with rendered SQL, instead of letting
    # `load_target` wander into the statement cache.
    if cproxy
      %i[to_a to_ary records load_target].each do |m|
        next unless cproxy.method_defined?(m) || cproxy.private_method_defined?(m)
        interceptor.declare_target(cproxy, m, returns: rows_mock)
      end
    end

    # -------------------------------------------------------------------
    # 2. Calculations#pluck / #ids -> iterable symbolic list.
    #
    # The shared file declares these `UNSUPPORTED` (concolic_targets.rb:469),
    # i.e. an unconditional raise. Replacing a raise with a symbolic value can
    # only reveal branches, never swallow one — and the branch this batch cares
    # about (`if public?` inside people_allowed_to_be_mentioned) lives in the
    # app body, which is untouched. The query is still recorded via sql_for.
    #
    # Element type is resolved from the plucked column so `pluck(:person_id)`
    # yields a SymbolicInt rep rather than a string. Multi-column pluck (rows
    # of arrays) is NOT modeled — it falls back to a single scalar rep, which
    # is wrong-shaped; no call site in this batch uses it, and it stays
    # reported rather than silently right-looking.
    # -------------------------------------------------------------------
    pluck_rep = lambda do |receiver, args, name, sql|
      col = args.values.compact.flatten.first if args.is_a?(Hash)
      col = col.to_s if col
      meta = begin
        k = ct.model_class(receiver)
        (col && k.respond_to?(:columns_hash)) ? k.columns_hash[col] : nil
      rescue Exception # rubocop:disable Lint/RescueException
        nil
      end
      vn = "#{name}_val"
      case meta && meta.type
      when :integer, :bigint then symint(vn, ct.seed_for(vn, 1), note: sql)
      when :boolean          then symbool(vn, ct.seed_for(vn, false), note: sql)
      else                        symstr(vn, ct.seed_for(vn, "#{vn}_v"), note: sql)
      end
    end

    interceptor.declare_target(calc, :pluck, returns: lambda do |receiver, args, name|
      vn  = "#{name}_plucked"
      sql = ct.sql_for(receiver, args)
      IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: sql,
                               representative: pluck_rep.call(receiver, args, name, sql))
    end)

    interceptor.declare_target(calc, :ids, returns: lambda do |receiver, args, name|
      vn  = "#{name}_ids"
      sql = ct.sql_for(receiver, args)
      rv  = "#{name}_id"
      IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: sql,
                               representative: symint(rv, ct.seed_for(rv, 1), note: sql))
    end)

    # -------------------------------------------------------------------
    # 3. Diaspora::Mentionable.people_from_string -> iterable list of Person.
    #
    # The shared X6f mock (concolic_targets.rb:1041) returns a plain `[]`, and
    # declare_target's body-skip path runs a plain Array through
    # `to_symbolic`, producing a bare SymbolicList with NO representative.
    # `CommentPresenter#as_json` then calls
    # `@comment.mentioned_people.as_api_response(:backbone)` on it ->
    # `NoMethodError: undefined method 'as_api_response' for <SymList ...>`
    # (259 dumps in the first overlay run).
    #
    # Returning a symbolic value directly also bypasses the Array->SymbolicList
    # re-wrap (the interceptor passes SymbolicVar results through unchanged).
    #
    # The DEFAULT length is 0, preserving the shared mock's "mentions nobody"
    # semantics exactly — but it is now `seed_for`-able, so the DSE can flip it
    # to 1 and explore the has-mentions half that `[]` made unreachable. The
    # representative is a symbolic Person, which is what the callers
    # (`mentioned_ppl.find { |p| p.diaspora_handle == ... }`) expect.
    # -------------------------------------------------------------------
    if defined?(Diaspora::Mentionable) &&
       Diaspora::Mentionable.respond_to?(:people_from_string)
      interceptor.declare_target(
        Diaspora::Mentionable.singleton_class, :people_from_string,
        returns: lambda do |_receiver, _args, name|
          vn  = "#{name}_people"
          sql = "Diaspora::Mentionable.people_from_string (mention scan, no SQL)"
          rep = ct.symbolic_instance(Person, "#{name}_person", sql)
          IterableSymbolicList.new(ct.seed_for("len(#{vn})", 0),
                                   name: vn, note: sql, representative: rep)
        end
      )
    end

    # -------------------------------------------------------------------
    # 4. ActsAsApi::Collection#as_api_response -> iterable list.
    #
    # Byte-identical to the shared X3 mock (concolic_targets.rb:920-932) except
    # for the class: it built a plain `symlist`, which raises the moment anything
    # downstream iterates the serialized collection. Length is made seedable
    # here too — X3 hard-coded 1, which is the "permanently inert var" trap the
    # addendum calls out.
    # -------------------------------------------------------------------
    if defined?(ActsAsApi::Collection)
      interceptor.declare_target(
        ActsAsApi::Collection, :as_api_response,
        returns: lambda do |receiver, _args, name|
          note = "ActsAsApi::Collection#as_api_response"
          klass = begin
            ct.model_class(receiver)
          rescue StandardError
            receiver.is_a?(Array) ? receiver.first.class : Post
          end
          rep = ct.symbolic_instance(klass, "#{name}_row", note)
          IterableSymbolicList.new(ct.seed_for("len(#{name})", 1),
                                   name: name, note: note, representative: rep)
        end
      )
    end

    warn "[posts] PostsTargets installed"
  end
end
