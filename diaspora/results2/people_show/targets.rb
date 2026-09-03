# frozen_string_literal: true
#
# Per-entrypoint concolic targets — `people_show` (results2 rerun).
#
# §A `PeopleTargets` is ported VERBATIM from ../../results/people/targets.rb
# (the proven-working "people" batch overlay) — Person association readers,
# NullRelation short-circuit, asset-path stub, ConcolicDate, IterableSymbolicList,
# find_by_sql fix, gon reset, symbolic_user. None of that logic depends on
# whether params[:username] is symbolic, so it is reused unmodified.
#
# §B `PeopleShowSymParams` is NEW for results2: closes the walls that appear
# ONLY once params[:username] becomes a genuine SymbolicString (the point of
# this rerun — see results2/README.md "Symbolic entrypoint variables").
# `PeopleController#find_person` (people_controller.rb:127-140) is:
#
#   def find_person
#     username = params[:username]
#     @person = if diaspora_id?(username)
#         Person.where({ diaspora_handle: username.downcase }).first
#       else
#         Person.find_from_guid_or_username({ id: params[:id] || params[:person_id],
#                                              username: username })
#       end
#     raise ActiveRecord::RecordNotFound if @person.nil?
#     raise Diaspora::AccountClosed if @person.closed_account?
#   end
#
#   def diaspora_id?(query)
#     !(query.nil? || query.lstrip.empty?) &&
#       Validation::Rule::DiasporaId.new.valid_value?(query.downcase).present?
#   end
#
# Two walls, both in src/ruby_runtime/string.rb's UNSUPPORTED list (untracked
# ops, by design — never patched from a batch session, see main README):
#   1. `query.lstrip` / `query.downcase` inside `diaspora_id?` — `lstrip` and
#      `downcase` are both UNSUPPORTED (string.rb:326-331), so this bare `if`
#      would crash on the FIRST call, before find_person's own two SQL
#      branches are even reached.
#   2. `username.downcase` in the `diaspora_handle:` finder call, and (on the
#      "not diaspora_id" side) `params[:username].present?` inside
#      Person.find_from_guid_or_username -> String#blank? -> `=~` (also
#      UNSUPPORTED).
#
# Wall-fixing discipline applied: `diaspora_id?` is SQL-free and calls no
# other declared target, so it is a legal mock unit (README §"Wall-fixing
# discipline") — mocked as a BOUNDARY DECISION exactly like the shared
# `finder_mock` pattern (concolic_targets.rb:366): the REAL validation logic
# runs UNMODIFIED against the concrete seed value (`query.value`), and the
# boolean result is wrapped as a seedable symbolic bool so the branch is
# genuinely flippable by DSE instead of being a fabricated concrete constant.
# `downcase`/`blank?`/`present?` are fixed at the VALUE level (a batch-local
# SymbolicString SUBCLASS used only for SYM_PARAM_username — nothing shared
# changes), per the same "fix the crashing VALUE, do not mock its CONSUMER"
# principle §5a below already uses for ConcolicDate.

module PeopleTargets
  module_function

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    # ---------------------------------------------------------------------
    # 1. Person association readers for finder-symbolic Person records.
    # (ported verbatim from results/people/targets.rb §1)
    # ---------------------------------------------------------------------
    unless Person.ancestors.include?(PersonSymAssociations)
      Person.prepend(PersonSymAssociations)
    end

    # ---------------------------------------------------------------------
    # 2. NullRelation short-circuit for collection / emptiness mocks.
    # (ported verbatim from results/people/targets.rb §2)
    # ---------------------------------------------------------------------
    rel      = ActiveRecord::Relation
    null_rel = defined?(ActiveRecord::NullRelation) ? ActiveRecord::NullRelation : nil

    if null_rel
      { empty?: true, none?: true, any?: false, one?: false, many?: false }
        .each do |m, null_val|
        interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
          next null_val if receiver.is_a?(null_rel)
          vn = "#{name}_#{m.to_s.delete('?')}"
          default = case m
                    when :empty?, :none? then false
                    else true
                    end
          symbool(vn, ct.seed_for(vn, default), note: ct.sql_for(receiver, args))
        end)
      end
    else
      warn "[people_show] ActiveRecord::NullRelation undefined — short-circuit skipped"
    end

    # ---------------------------------------------------------------------
    # 3. Asset-path stub — an ENVIRONMENT wall, not a symbolic-runtime one.
    # (ported verbatim from results/people/targets.rb §3)
    # ---------------------------------------------------------------------
    begin
      h = ActionController::Base.helpers
      h.define_singleton_method(:image_path)    { |src, *| "/concolic/assets/#{src}" }
      h.define_singleton_method(:path_to_image) { |src, *| "/concolic/assets/#{src}" }
      require "app/presenters/avatar_presenter" if defined?(Rails)
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn "[people_show] asset stub: #{e.class}: #{e.message.to_s[0, 80]}"
    end

    # ---------------------------------------------------------------------
    # 5. Symbolic-shaped VALUE objects.
    # (ported verbatim from results/people/targets.rb §5a/§5b/§5c)
    # ---------------------------------------------------------------------
    unless defined?(ConcolicDate)
      ::Object.const_set(:ConcolicDate, Class.new(::Date) do
        attr_writer :sym_year
        def year
          @sym_year || super
        end
      end)
    end

    unless ConcolicTargets.respond_to?(:symbolic_instance_without_dates)
      class << ConcolicTargets
        alias_method :symbolic_instance_without_dates, :symbolic_instance
        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_without_dates(klass, base_name, sql)
          klass.columns_hash.each do |col, meta|
            next unless %i[date datetime].include?(meta.type)
            vn = "#{base_name}_#{col}_year"
            d = ConcolicDate.new(1990, 1, 1)
            d.sym_year = symint(vn, seed_for(vn, 1990), note: sql)
            obj.define_singleton_method(col) { d }
            obj.concolic_attrs[col] = d if obj.respond_to?(:concolic_attrs)
          end
          obj
        end
      end
    end

    unless defined?(IterableSymbolicList)
      ::Object.const_set(:IterableSymbolicList, Class.new(SymbolicList) do
        def each
          return to_enum(:each) unless block_given?
          yield @representative if @representative && concrete_length != 0
          self
        end

        def map
          return to_enum(:map) unless block_given?
          (@representative && concrete_length != 0) ? [yield(@representative)] : []
        end
        alias_method :collect, :map
      end)
    end

    %i[to_a to_ary records].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        next [] if null_rel && receiver.is_a?(null_rel)
        vn  = "#{name}_rows"
        rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row",
                                   ct.sql_for(receiver, args))
        IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn,
                                 note: ct.sql_for(receiver, args),
                                 representative: rep)
      end)
    end

    querying = ActiveRecord::Querying
    interceptor.declare_target(querying, :find_by_sql, returns: lambda do |receiver, args, name|
      vn  = "#{name}_rows"
      sql = args["sql"].to_s
      rep = begin
        ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", sql)
      rescue Exception # rubocop:disable Lint/RescueException,Lint/SuppressedException
        nil
      end
      IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn,
                               note: sql, representative: rep)
    end)

    warn "[people_show] PeopleTargets installed"
  end

  # 6. Per-run request-state reset (ported verbatim from results/people/targets.rb §6)
  def begin_run!
    return unless defined?(Gon::Request) && defined?(RequestStore)
    req = Gon::Request.new({})
    req.gon["preloads"] = {}
    RequestStore.store[:gon] = req
  rescue StandardError => e
    warn "[people_show] gon request-state reset failed: #{e.class}: #{e.message[0, 80]}"
  end

  # 4. Concrete overrides for the symbolic CURRENT USER (ported verbatim).
  # NOTE: people_show's canonical scenario is ANONYMOUS (signed_in: false,
  # matching the source batch — see run_dse.rb header note), so this user is
  # built but never wired as current_user; kept for parity with the source
  # harness and in case a future signed-in variant is added to this dir.
  def apply_user_overrides!(user, person)
    user.define_singleton_method(:id)              { 1 }
    user.define_singleton_method(:guid)            { "abc123" }
    user.define_singleton_method(:person)          { person }
    user.define_singleton_method(:person_id)       { 1 }
    user.define_singleton_method(:diaspora_handle) { "alice@example.org" }
    user.define_singleton_method(:language)        { "en" }
    user.define_singleton_method(:gender)          { "" }
    user.define_singleton_method(:contacts)        { Contact.all }
    user.define_singleton_method(:blocks)          { Block.all }
    user.define_singleton_method(:aspects)         { Aspect.all }
    user.define_singleton_method(:contact_for) do |p|
      Contact.includes(person: :profile).find_by(user_id: 1, person_id: p.id)
    end
    user.define_singleton_method(:block_for)  { |_p| Block.none }
    user.define_singleton_method(:posts_from) { |_p| Post.all }
    user
  end

  def symbolic_user(tag)
    person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}",
                                               "Person (current user)")
    person.define_singleton_method(:id) { 1 }
    user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
    apply_user_overrides!(user, person)
  end
end

# §1's implementation module (top-level, ported verbatim).
module PersonSymAssociations
  def posts
    respond_to?(:concolic_attrs) ? Post.all : super
  end

  def profile
    if respond_to?(:concolic_attrs)
      ConcolicTargets.symbolic_instance(Profile, "SYM_PROFILE_PERSON",
                                        "Person#profile (has_one)")
    else
      super
    end
  end

  def blocks
    respond_to?(:concolic_attrs) ? Block.all : super
  end
end

# =============================================================================
# §B — PeopleShowSymParams: NEW for results2 — closes the walls that only
# appear once params[:username] is symbolic. See file header for the full
# analysis of `find_person`/`diaspora_id?`.
# =============================================================================
module PeopleShowSymParams
  module_function

  # A SymbolicString subclass used ONLY for SYM_PARAM_username. Overrides two
  # methods that are UNSUPPORTED on the base SymbolicString (string.rb's
  # UNSUPPORTED stub list — untracked ops, raise by design):
  #
  #   downcase — `username.downcase` is called unconditionally in
  #     find_person's true branch (`diaspora_handle: username.downcase`) and
  #     inside `diaspora_id?`. Our seed "bob@example.org" is already
  #     lower-case, so downcase is a semantic no-op for the tracked value;
  #     overridden here as IDENTITY (returns self, same z3_expr /
  #     SYM_PARAM_username), mirroring how `.to_s`/`.to_str` are ALREADY
  #     identity on the base SymbolicString (string.rb's own stated design).
  #     This is scoped to this one subclass/variable, not a global src/ patch.
  #
  #   blank?/present? — ActiveSupport's String#blank? does `self !~ /\S/`,
  #     and `=~` is UNSUPPORTED on SymbolicString (untracked regex/ordering
  #     op). Overridden with a CONCRETE check against the underlying seed
  #     value. This is the SAME Ruby-truthiness gap already documented in
  #     src/TODO.txt for bare `if`/predicate calls on symbolic values project-
  #     wide — `present?`/`blank?` here decide concretely, exactly like every
  #     other bare-truthiness call in this experiment; nothing new is
  #     fabricated, and the decision is NOT what the DSE flips (see below,
  #     that's `diaspora_id?`'s own mocked boundary).
  class SymUsernameString < SymbolicString
    def downcase
      self
    end

    def blank?
      @value.nil? || @value.strip.empty?
    end

    def present?
      !blank?
    end
  end

  # `diaspora_id?` boundary mock — SQL-free, calls no other declared target,
  # so it is a legal mock unit per the README wall-fixing discipline. Runs the
  # REAL Validation::Rule::DiasporaId logic, UNMODIFIED, against the concrete
  # seed value (`query.value`) to compute the default/seed outcome, then wraps
  # it as a seedable symbolic bool — exactly the shared `finder_mock` pattern
  # (concolic_targets.rb:366-378) applied to a non-AR boundary decision. This
  # makes "is this a diaspora-handle-shaped username" a genuine, flippable PC
  # instead of either (a) crashing on `.lstrip`/`.downcase`, both UNSUPPORTED,
  # or (b) silently hand-replicating the validation logic as fabricated app
  # behaviour (forbidden — README "Honest known limitations").
  module DiasporaIdBoundaryMock
    def diaspora_id?(query)
      return super unless query.is_a?(SymbolicVar)

      vn = "SYM_DECISION_diaspora_id_username"
      concrete = query.value
      real_result = !(concrete.nil? || concrete.lstrip.empty?) &&
        Validation::Rule::DiasporaId.new.valid_value?(concrete.downcase).present?
      decided = symbool(vn, ConcolicTargets.seed_for(vn, real_result),
                         note: "PeopleController#diaspora_id?(#{query.sym_name})")
      decided == true # explicit compare — bare truthiness records no PC (TODO.txt)
    end
  end

  # `User#person` association reader — same documented src/ gap as
  # PersonSymAssociations (symbolic klass.allocate has no usable
  # @association_cache; README "Known src/ruby_runtime gaps": "user.person
  # NoMethodError (worked around runner-locally)"). Needed ONLY on the
  # `diaspora_id?` == false path: find_from_guid_or_username's
  # `User.find_by_username(...)` branch returns a symbolic User instance via
  # the shared `find_by` finder mock, and `u.person` is called on it.
  module UserSymPersonAssociation
    def person
      respond_to?(:concolic_attrs) ? ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_via_user", "User#person (has_one)") : super
    end
  end

  def install!(_interceptor = CallInterceptor.instance)
    PeopleController.prepend(DiasporaIdBoundaryMock) unless PeopleController.ancestors.include?(DiasporaIdBoundaryMock)
    User.prepend(UserSymPersonAssociation) unless User.ancestors.include?(UserSymPersonAssociation)
    warn "[people_show] PeopleShowSymParams installed"
  end

  # Build the symbolic params[:username]. Called fresh per run so
  # seed_overrides ("SYM_PARAM_username" => "...") apply.
  def symbolic_username(default = "bob@example.org")
    SymUsernameString.new(ConcolicTargets.seed_for("SYM_PARAM_username", default),
                           name: "SYM_PARAM_username",
                           note: "PeopleController params[:username]")
  end
end
