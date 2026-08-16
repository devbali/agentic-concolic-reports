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
      interceptor.declare_target(btpa, :find_target, returns: lambda do |receiver, _args, _name|
        nm = receiver.reflection.name
        ct.symbolic_instance(
          poly_klass(receiver), "assoc_#{nm}",
          "BelongsToPolymorphicAssociation##{nm} (polymorphic target load)"
        )
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
          yield @representative if @representative && concrete_length != 0
          self
        end

        def map
          return to_enum(:map) unless block_given?
          @representative && concrete_length != 0 ? [yield(@representative)] : []
        end
        alias_method :collect, :map
      end)
    end

    rel      = ActiveRecord::Relation
    null_rel = defined?(ActiveRecord::NullRelation) ? ActiveRecord::NullRelation : nil

    %i[to_a to_ary records].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        # A NullRelation (`Model.none`) is DEFINED to be empty and issues no
        # SQL — there is no query to preserve, so the concrete empty result is
        # a sound over-approximation rather than a hidden query. Without this,
        # `Person.none` from §4 would materialize a phantom row.
        next [] if null_rel && receiver.is_a?(null_rel)

        vn  = "#{name}_rows"
        rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row",
                                   ct.sql_for(receiver, args))
        IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn,
                                 note: ct.sql_for(receiver, args),
                                 representative: rep)
      end)
    end

    # =====================================================================
    # 4. Diaspora::Mentionable.people_from_string -> Person.none
    #    (SHAPE-ONLY override of the shared §X6f mock)
    #
    # With §3 in place, `CommentPresenter#as_json` runs for real and reaches
    # `@comment.mentioned_people.as_api_response(:backbone)`. The shared mock
    # returns `[]`, which the interceptor converts to a SymbolicList
    # (symbolic_func.rb:165) ->
    #     NoMethodError: undefined method `as_api_response'
    #                    for <SymList ...people_from_string_2 len=0>
    #
    # Same principle as §3: fix the VALUE's shape. This changes ONLY the return
    # type of a mock that is already installed — an empty AR Relation instead
    # of `[]`. Both mean "this text mentions nobody", but a Relation carries
    # `ActsAsApi::Collection`, so the shared §X3 target handles it and the
    # render completes; `.each` in `create_mentions` is a no-op on it exactly
    # as on `[]`.
    #
    # No branch is swallowed: the real body is a pure `scan`/`map` with no
    # conditional, and it was ALREADY mocked upstream. In particular
    # `MentionsContainer#mentioned_people` — the CONSUMER, which holds
    # `if persisted?` — is deliberately NOT mocked, because that `if` is a
    # branch.
    # =====================================================================
    if defined?(Diaspora::Mentionable) && Diaspora::Mentionable.respond_to?(:people_from_string)
      interceptor.declare_target(Diaspora::Mentionable.singleton_class, :people_from_string,
                                 returns: ->(_r, _a, _n) { Person.none })
    end

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

    warn "[comments] CommentsTargets installed"
  end
end
