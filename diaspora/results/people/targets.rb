# frozen_string_literal: true
#
# Per-batch concolic targets — `people`.
#
# WHY THIS FILE EXISTS
# --------------------
# `reports/diaspora/concolic_targets.rb` is shared by all 13 batches, so every
# batch-local wall fix used to need a cross-batch decision — and some fixes are
# actively wrong elsewhere. The result was that walls stayed open and the fixes
# that *were* applied lived as ad-hoc monkey-patches inside `run_dse.rb`, mixed
# in with request-scenario wiring.
#
# This overlay installs AFTER `ConcolicTargets.install!`. `declare_target` uses
# `define_method`, so a later declaration replaces an earlier one: overrides are
# last-one-wins and need no registry support.
#
#   ConcolicTargets.install!(interceptor)   # shared generic AR interception
#   PeopleTargets.install!(interceptor)     # this file — batch-local wall fixes
#
# Contents
# Contents — `install!` (called once, after ConcolicTargets.install!):
#   §1  Person association readers (symbolic-instance gap)          [prepend]
#   §2  NullRelation short-circuit for the emptiness predicates     [targets]
#   §3  Asset-path stub — Sprockets/AvatarPresenter environment wall
#   §5  Symbolic-shaped VALUE objects — ConcolicDate, IterableSymbolicList,
#       iterable+seedable find_by_sql (close "the runtime is missing method X"
#       walls WITHOUT touching src/)
#
# Module functions the RUNNER calls (they need per-instance / per-run access,
# which `declare_target` cannot give — see each section for why):
#   §4  `symbolic_user` / `apply_user_overrides!` — concrete current-user
#       language / gender / guid + association readers
#   §6  `begin_run!` — per-run gon RequestStore reset
#
# Every mock wraps the SMALLEST enclosing method whose real body contains NO SQL
# and calls NO other declared target (README wall-fixing discipline). Producing
# queries still run for real.

module PeopleTargets
  module_function

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    # ---------------------------------------------------------------------
    # 1. Person association readers for finder-symbolic Person records.
    #
    # Symbolic instances come from `klass.allocate`, so the real has_many /
    # has_one readers have no usable association state (concolic_targets
    # pre-seeds `@association_cache = {}`, which stops the NoMethodError but
    # still yields nothing chainable). `Stream::Person` and the person
    # presenters need `person.posts` / `#profile` / `#blocks` to be symbolic
    # BUT chainable.
    #
    # Implemented as a prepend rather than `declare_target` on purpose: these
    # are association readers generated into an anonymous
    # `GeneratedAssociationMethods` module that sits BELOW `Person` in the
    # ancestor chain, so a plain `define_method(Person, :posts)` would already
    # win — but the guard has to fall through to `super` for REAL records, and
    # a declared target has no `super`. `concolic_attrs` is only defined on
    # symbolic instances, so real Person rows are untouched.
    #
    # `Post.all` / `Block.all` are relations, so the queries they feed still go
    # through the shared declared targets and stay traceable; only the
    # association's implicit `WHERE person_id = ...` scope is dropped, which is
    # recorded in the rendered SQL note and reported.
    # ---------------------------------------------------------------------
    unless Person.ancestors.include?(PersonSymAssociations)
      Person.prepend(PersonSymAssociations)
    end

    # ---------------------------------------------------------------------
    # 2. NullRelation short-circuit for collection / emptiness mocks.
    #
    # `PersonPresenter#current_user_person_contact` returns `Contact.none` and
    # `#current_user_person_block` returns `Block.none` whenever `current_user`
    # is nil — which is exactly the anonymous scenario this batch explores for
    # people_show / people_stream / people_hovercard.
    #
    # The shared symbolic mocks make `Contact.none.present?` seedable, so DSE
    # happily flips it TRUE. The app then enters `contact_hash` /
    # `BlockPresenter.new(...)` — a branch that is UNREACHABLE in production,
    # because `.none` is defined empty — and immediately dies with
    #   NoMethodError: undefined method `id' for #<Contact::ActiveRecord_Relation>
    # So those PCs were not just noise: they were PHANTOM execution-tree nodes
    # standing for behaviour the deployed app can never exhibit.
    #
    # A NullRelation is DEFINED to be empty and issues NO SQL (`Relation#none`
    # is `where("1=0").extending!(NullRelation)` and NullRelation overrides every
    # loader to return the empty value without touching the connection). There
    # is therefore no query to preserve and no declared target beneath it, so
    # returning the concrete empty result is a sound over-approximation, not a
    # hidden query. Every other receiver falls through to the shared symbolic
    # behaviour, unchanged.
    #
    # NOTE vs photos/targets.rb §4: that version omits `none?`. A NullRelation
    # has no elements, so `none?` must short-circuit to TRUE (photos never hits
    # it; people would). The rest is identical.
    # ---------------------------------------------------------------------
    rel      = ActiveRecord::Relation
    null_rel = defined?(ActiveRecord::NullRelation) ? ActiveRecord::NullRelation : nil

    if null_rel
      # NOTE: the matching `records`/`to_a`/`to_ary` short-circuit is declared in
      # §5b, together with the iterable list, so those three methods have exactly
      # one declaration rather than two stacked last-one-wins overrides.
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
      warn "[people] ActiveRecord::NullRelation undefined — short-circuit skipped"
    end

    # ---------------------------------------------------------------------
    # 3. Asset-path stub — an ENVIRONMENT wall, not a symbolic-runtime one.
    #
    # `AvatarPresenter`'s CLASS BODY evaluates
    #   DEFAULT_IMAGE = ActionController::Base.helpers.image_path("user/default.png")
    # which drives Sprockets through app/assets/config/manifest.js ->
    # app/assets/javascripts/main.js -> `//= require underscore`. The minimal
    # concolic rig has no compiled assets, so Sprockets::FileNotFound is raised
    # WHILE THE CLASS BODY IS STILL EXECUTING and the class is left
    # HALF-DEFINED. Every LATER run in the same process then fails differently
    # (`NoMethodError: base_hash` / `medium` for Profile, via
    # BasePresenter#method_missing) — i.e. the reported wall depended on run
    # order, which made the whole batch non-deterministic.
    #
    # `image_path` is a pure display-URL builder: no SQL, nothing branched on.
    # Stubbing it makes the presenter path load cleanly and deterministically.
    #
    # Prepending `ActionView::Helpers::AssetUrlHelper` does NOT work: JRuby 9.3
    # is Ruby 2.6 semantics, where a module prepended AFTER the target module
    # was already included/extended somewhere is not propagated to the existing
    # includer. The helper proxy is memoized per controller class, so its
    # singleton is what has to be patched.
    #
    # This is the fix `photos/targets.rb` §5 generalises.
    # ---------------------------------------------------------------------
    begin
      h = ActionController::Base.helpers
      h.define_singleton_method(:image_path)    { |src, *| "/concolic/assets/#{src}" }
      h.define_singleton_method(:path_to_image) { |src, *| "/concolic/assets/#{src}" }
      require "app/presenters/avatar_presenter" if defined?(Rails)
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn "[people] asset stub: #{e.class}: #{e.message.to_s[0, 80]}"
    end

    # ---------------------------------------------------------------------
    # 5. Symbolic-shaped VALUE objects — closing "the runtime is missing
    #    method X" walls WITHOUT touching src/ruby_runtime.
    #
    # The runtime's symbolic classes are ordinary Ruby classes with public
    # readers (`SymbolicList#representative`, `SymbolicInt#value`, `#sym_name`,
    # `#note`). A missing method is therefore NOT a src/ blocker: a batch-local
    # SUBCLASS can add it, and a batch-local mock can hand that subclass to the
    # app. Nothing shared changes.
    #
    # General principle: fix the crashing VALUE, do not mock its CONSUMER.
    # Mocking the consumer usually swallows the very branch the wall guards
    # (the `Profile#build_image_url` regression documented in photos §2).
    #
    # Pattern taken from reports/diaspora/results/photos/targets.rb §6.
    # ---------------------------------------------------------------------

    # 5a. ConcolicDate — a real ::Date whose #year is a seedable SymbolicInt.
    #
    # `symbolic_instance` maps every non-integer/non-boolean column to
    # `symstr`, so `profiles.birthday` (a `date` column) arrives as a
    # SymbolicString and `PeopleHelper#birthday_format` dies with
    #   NoMethodError: undefined method `year' for #<SymbolicString>
    #
    #   # app/presenters/profile_presenter.rb:36
    #   def formatted_birthday; birthday_format(birthday) if birthday; end
    #   # app/helpers/people_helper.rb:20
    #   def birthday_format(bday)
    #     if bday.year <= 1004 then ... else ... end
    #   end
    #
    # `birthday_format` is a legal SQL-free leaf, but mocking it is FORBIDDEN
    # here: its body IS the branch. Fixing the value instead means the
    # comparison RECORDS a genuine, flippable path condition instead of
    # crashing. Subclassing ::Date (rather than wrapping) keeps `Date === obj`,
    # `I18n.l`, and `strftime` working unchanged.
    unless defined?(ConcolicDate)
      ::Object.const_set(:ConcolicDate, Class.new(::Date) do
        attr_writer :sym_year
        def year
          @sym_year || super
        end
      end)
    end

    # 5a-wiring: route date/datetime columns through ConcolicDate.
    #
    # A batch-local WRAPPER around the shared `symbolic_instance` — the shared
    # file itself is untouched. After the generic build, each date-column reader
    # is replaced with a ConcolicDate whose #year is the seedable symint
    # "<base>_<col>_year", so `bday.year <= 1004` records `(<var> <= 1004)`.
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

    # 5b. IterableSymbolicList — #each / #map over the representative row.
    #
    # `PeopleController#hashes_for_people` (people_controller.rb:150) walls the
    # whole of people_index with
    #   NotImplementedError: SymbolicList#each is not supported
    #
    # There is NO legal mock for the consumer: the block body calls
    # `current_user.contact_for(person)`, a real SELECT, so `hashes_for_people`
    # is not a SQL-free leaf and mocking it would hide a query. But the LIST can
    # carry `#each`. The shared collection mock already attaches
    # `representative:`, and #first/#last/#[0] already honour it — yielding that
    # same representative once is the Gate 1b "one sampled row" semantics those
    # readers implement, so this is consistency, not new modelling.
    #
    # DO NOT `include Enumerable` HERE. A module included into a SUBCLASS is
    # inserted BEFORE the superclass in the ancestor chain, so
    # `Enumerable#any?` / `#none?` / `#count` / `#first` would SHADOW the
    # PC-RECORDING implementations on SymbolicList — they would answer from
    # `each` (i.e. from the single representative) and record NOTHING. That is
    # a silent coverage loss on an otherwise green, zero-error run: it shows up
    # only as a lower path-condition count, and `missing=0` cannot catch it
    # (the checker drops Z3 queries whose prefix holds an unparseable `len(...)`
    # constraint). Found by the notifications_tags batch, which measured
    # 8 PCs -> 4. Only #each/#map are added, and both are genuinely absent from
    # SymbolicList, so neither shadows anything.
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

    # 5b-wiring: the single declaration of the collection materialisers.
    # Combines the §2 NullRelation short-circuit with the iterable list.
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

    # 5c-wiring: Querying#find_by_sql — iterable AND seedable.
    #
    # Once §5b let people_index past `hashes_for_people`, the wall moved to
    #   ContactPresenter#full_hash (contact_presenter.rb:12)
    #     aspect_memberships.map { |m| AspectMembershipPresenter.new(m).base_hash }
    # The association load goes through AR's statement cache
    # (statement_cache.rb:108) -> `Querying#find_by_sql`, and the shared target
    # (concolic_targets.rb:514) returns a bare `SymbolicList.new(1, ...)` with
    #   * NO representative -> #each/#map raise even in the iterable subclass, and
    #   * a HARD-CODED length that never calls `seed_for` -> the inert-mock
    #     antipattern: DSE emits the `len(...)` flip, the mock ignores it, and the
    #     branch can never be closed.
    # Both are fixed here; the SQL note is preserved verbatim.
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

    warn "[people] PeopleTargets installed"
  end

  # -----------------------------------------------------------------------
  # 6. Per-run request-state reset — an ENVIRONMENT wall, uncovered only once
  #    §5b let people_index past the `#map`.
  #
  # `GonHelper#gon_load_contact` (app/helpers/gon_helper.rb:4) uses the
  # CLASS-level `Gon`, not the `gon` controller helper the shared file stubs:
  #
  #   Gon.preloads[:contacts] ||= []
  #
  # `Gon.preloads` goes through `Gon.method_missing` -> `get_variable` ->
  # `current_gon.gon[...]`, and `current_gon` is `RequestStore.store[:gon]`,
  # which the controller-test rig never populates (the gon railtie sets it from
  # Rack middleware). Result: `NoMethodError: undefined method 'gon' for nil`.
  #
  # Installing a real `Gon::Request` is plumbing substitution in the same class
  # as StubWarden and the asset-path stub — gon is pure JS-variable
  # accumulation with no SQL, and letting it run FOR REAL is strictly better
  # than stubbing `Gon.preloads`, because `gon_load_contact`'s own
  # `Gon.preloads[:contacts].none? {...}` guard stays intact.
  #
  # It MUST be reset per run: RequestStore is thread-local and nothing in the
  # rig clears it, so a surviving `preloads[:contacts]` would leak rows between
  # runs and turn `stored_contact[:person][:id] == contact.person_id` into a
  # cross-run symbolic comparison — non-deterministic PCs.
  # -----------------------------------------------------------------------
  #
  # The store is also pre-seeded with `preloads => {}`. In production that is
  # done by `ApplicationController#gon_set_preloads` (application_controller.rb:190,
  # a registered before_action) via `gon.preloads = {}` — but the SHARED file
  # intercepts `Gon::ControllerHelpers#gon` and returns its own `gon_stub`, so
  # that assignment lands on the stub instead of on the store the CLASS-level
  # `Gon` reads. Without the pre-seed, `Gon.preloads` is nil and
  # `Gon.preloads[:contacts] ||= []` raises `NoMethodError: [] for nil`.
  # Pre-seeding reproduces exactly what the real before_action does; the
  # remaining `gon.*` / `Gon.*` divergence is pure JS-variable accumulation and
  # is never branched on.
  def begin_run!
    return unless defined?(Gon::Request) && defined?(RequestStore)
    req = Gon::Request.new({})
    req.gon["preloads"] = {}
    RequestStore.store[:gon] = req
  rescue StandardError => e
    warn "[people] gon request-state reset failed: #{e.class}: #{e.message[0, 80]}"
  end

  # -----------------------------------------------------------------------
  # 4. Concrete overrides for the symbolic CURRENT USER.
  #
  # These CANNOT be `declare_target`s. `ConcolicTargets.symbolic_instance`
  # installs a per-column reader with `define_singleton_method`, and a
  # singleton method beats both a class-level `define_method` (what
  # `declare_target` does) and any module prepended to `User`. So the current
  # user's overrides have to be applied to the instance, which is why this is a
  # module_function the runner calls rather than part of `install!`.
  #
  #   language  users.language IS a column -> symbolic. Read by the REAL
  #             `ApplicationController#set_locale` before_action, and a
  #             SymbolicString crashes i18n's `enforce_available_locales!`
  #             BEFORE the action body runs — i.e. it walls every entrypoint at
  #             0 PCs. Concrete "en" is not branched on by any people action.
  #   gender    delegated to person -> profile. Read by the layout/presenter
  #             chain only; not branched on.
  #   guid      delegated to person. Concrete for the CURRENT user only; the
  #             VIEWED person's guid stays symbolic, so `Person#to_param -> guid`
  #             in people_stream still records its PCs.
  #
  # The association readers below are the User-side twin of §1: symbolic User
  # instances have no association state, and every one of these returns a real
  # Relation, so the queries stay traceable through the shared targets.
  # `block_for` returns `Block.none` deliberately — that is what the app itself
  # does for a user with no block, and §2 now makes it behave like the empty
  # relation it is.
  # -----------------------------------------------------------------------
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

  # Build the symbolic current user used by every people scenario. Built FRESH
  # per run so that seed_overrides apply to its symbolic columns too (a user
  # built once at boot would freeze its vars).
  def symbolic_user(tag)
    person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}",
                                               "Person (current user)")
    person.define_singleton_method(:id) { 1 }
    user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
    apply_user_overrides!(user, person)
  end
end

# §1's implementation module (top-level so `Person.ancestors.include?` reads
# cleanly and a re-`install!` is idempotent).
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
