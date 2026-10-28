# frozen_string_literal: true
#
# Per-entrypoint concolic targets — `people_stream` (results2 rerun).
#
# Ported from ../../results/people/targets.rb (module PeopleTargets, §1-§6),
# renamed PeopleStreamTargets since results2 layout is one self-contained dir
# per entrypoint. Installs AFTER `ConcolicTargets.install!` — `declare_target`
# uses `define_method`, so a later declaration REPLACES an earlier one.
#
#   ConcolicTargets.install!(interceptor)         # shared generic AR interception
#   PeopleStreamTargets.install!(interceptor)     # this file — entrypoint-local fixes
#
# Contents (§1-§6 ported verbatim from the source batch, unchanged rationale):
#   §1  Person association readers (symbolic-instance gap)          [prepend]
#   §2  NullRelation short-circuit for the emptiness predicates      [targets]
#   §3  Asset-path stub — Sprockets/AvatarPresenter environment wall
#   §4  `symbolic_user` / `apply_user_overrides!` — module_functions the
#       RUNNER calls (see source rationale: symbolic_instance's
#       define_singleton_method column readers beat both declare_target and
#       prepend, so current-user overrides must be applied post-construction)
#   §5  Symbolic-shaped VALUE objects — ConcolicDate, IterableSymbolicList,
#       iterable+seedable find_by_sql
#   §6  `begin_run!` — per-run gon RequestStore reset
#
# NEW in this rerun (results2 requirement: entrypoint arguments must be
# symbolic — see run_dse.rb and REPORT.md):
#   §7  PeopleController#diaspora_id? boundary mock — the wall a symbolic
#       params[:username] hits immediately (see §7 comment below)
#   §4 REVISED — pins removed per results2/README.md item 2/3 (user.id,
#       person.id, person_id, guid, diaspora_handle now flow symbolic where
#       the source batch pinned them), associations rescoped to real FKs
#       with the symbolic id (item 5, mirrors results2/posts_show).
#
# Every mock wraps the SMALLEST enclosing method whose real body contains NO
# SQL and calls NO other declared target (README wall-fixing discipline).
# Producing queries still run for real.

module PeopleStreamTargets
  module_function

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets

    # ---------------------------------------------------------------------
    # 1. Person association readers for finder-symbolic Person records.
    # (verbatim port of results/people/targets.rb §1 — see there for the
    # full rationale: symbolic `klass.allocate` instances have no usable
    # association state, so Stream::Person / the person presenters need
    # person.posts / #profile / #blocks to be symbolic but chainable.)
    # ---------------------------------------------------------------------
    unless Person.ancestors.include?(PersonSymAssociations)
      Person.prepend(PersonSymAssociations)
    end

    # ---------------------------------------------------------------------
    # 2. NullRelation short-circuit (verbatim port of §2). Anonymous is the
    # canonical scenario for people_stream too: PersonPresenter isn't reached
    # by the `stream` action, but Contact.none/Block.none patterns recur
    # elsewhere in this controller family and the short-circuit is harmless
    # (falls through to shared behaviour for every other receiver).
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
      warn "[people_stream] ActiveRecord::NullRelation undefined — short-circuit skipped"
    end

    # ---------------------------------------------------------------------
    # 3. Asset-path stub (verbatim port of §3) — AvatarPresenter's class body
    # drives Sprockets, which has no compiled assets in the concolic rig.
    # ---------------------------------------------------------------------
    begin
      h = ActionController::Base.helpers
      h.define_singleton_method(:image_path)    { |src, *| "/concolic/assets/#{src}" }
      h.define_singleton_method(:path_to_image) { |src, *| "/concolic/assets/#{src}" }
      require "app/presenters/avatar_presenter" if defined?(Rails)
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn "[people_stream] asset stub: #{e.class}: #{e.message.to_s[0, 80]}"
    end

    # ---------------------------------------------------------------------
    # results3/people_stream ADDITION §4b: SymbolicList#as_api_response.
    #
    # Found live on the json scenarios once the render family (Section Z) was
    # removed: `CommentPresenter#as_json` calls
    # `@comment.mentioned_people.as_api_response(:backbone)` (comment_
    # presenter.rb:15, reached via LastThreeCommentsDecorator ->
    # last_three_comments -> real comment rows). `mentioned_people` comes from
    # the shared `Diaspora::Mentionable.people_from_string` mock (X6f), which
    # returns a plain Ruby `[]` — re-wrapped by the interceptor's `to_symbolic`
    # into a bare `SymbolicList` (NOT `IterableSymbolicList`, no
    # `representative`). `ActsAsApi::Collection#as_api_response` (X3) is
    # declared on that acts_as_api MODULE, which a bare `SymbolicList` never
    # includes, so the call falls through to NoMethodError instead of the
    # existing (deferred-violation) mock.
    #
    # Semantically this list is ALWAYS seeded empty by X6f's design (people_
    # from_string's own comment: "mocking to nil makes the mention list empty
    # ... the caller handles an empty array") — a real `as_api_response` on a
    # genuinely empty AR collection returns `[]`, so the 0-length case is not
    # a simplification, it is the correct value. The non-zero branch (only
    # reachable if a future seed forces `len(...)` non-zero) is a documented,
    # narrow placeholder — a minimal Hash, not a query — since no
    # representative Person is attached to this particular list to render a
    # real one from.
    unless SymbolicList.method_defined?(:as_api_response)
      SymbolicList.class_eval do
        def as_api_response(*_args)
          concrete_length.zero? ? [] : [{ concolic_placeholder: true }]
        end
      end
    end

    # ---------------------------------------------------------------------
    # 5. Symbolic-shaped VALUE objects (verbatim port of §5a/§5b/§5c).
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

        # results3/people_stream ADDITION: `.reverse` — needed now that the
        # render family (Section Z) is REMOVED (../concolic_targets.rb header)
        # and the json scenarios' real `render json:
        # LastThreeCommentsDecorator.new(...)` path reaches
        # `Diaspora::Commentable#last_three_comments`
        # (`self.comments.order(...).limit(3).includes(...).reverse`) for
        # real. Plain `SymbolicList#reverse` is UNSUPPORTED (src/ruby_runtime/
        # list.rb — a genuine "contents op", same family as #map/#each before
        # this file added them). Representative-sampling semantics make
        # reversal a no-op (a 0-or-1-element sample has no order to reverse) —
        # returns self so the immediately-following `.map` (CommentPresenter.
        # as_collection) still works.
        def reverse
          self
        end

        # results3/people_stream ADDITION: `.inject`/`.reduce` — needed now
        # that Stream::Base#attach_user_likes is DESCENDED (its real body is
        # `likes.inject({}) { |hash, like| hash[like.target_id] = like; hash
        # }`). Representative-element shape: same one-element semantics as
        # #each/#map above — zero iterations when the list is seeded empty,
        # one (representative) iteration otherwise. Mirrors Enumerable#inject's
        # two call shapes (initial value given vs. not).
        def inject(*args)
          return to_enum(:inject, *args) unless block_given?
          if @representative && concrete_length != 0
            if args.empty?
              @representative
            else
              yield args.first, @representative
            end
          else
            args.first
          end
        end
        alias_method :reduce, :inject
      end)
    end

    # results3/people_stream ADDITION (PHASE_A_PATCH.md Patch 4, applicability
    # table: "people_stream — yes — stream rendering reads person/post
    # associations directly"). `ActiveRecord::Associations::CollectionProxy`
    # (a Relation subclass) OVERRIDES `records` itself (collection_proxy.rb:
    # 1003, `def records; load_target; end` -> `@association.load_target`), so
    # a target declared only on `ActiveRecord::Relation` never fires for a bare
    # collection-association read (`person.posts`, `user.contacts`, ...) — it
    # would run the real, unmocked load path against a symbolic owner id.
    # Extract the existing to_a/to_ary/records body into a named lambda and
    # declare it a second time on CollectionProxy.
    rows_mock = lambda do |receiver, args, name|
      next [] if null_rel && receiver.is_a?(null_rel)
      vn  = "#{name}_rows"
      rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row",
                                 ct.sql_for(receiver, args))
      IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn,
                               note: ct.sql_for(receiver, args),
                               representative: rep)
    end

    %i[to_a to_ary records].each do |m|
      interceptor.declare_target(rel, m, returns: rows_mock)
    end

    cproxy = defined?(ActiveRecord::Associations::CollectionProxy) ? ActiveRecord::Associations::CollectionProxy : nil
    if cproxy
      %i[to_a to_ary records load_target].each do |m|
        next unless cproxy.method_defined?(m) || cproxy.private_method_defined?(m)
        interceptor.declare_target(cproxy, m, returns: rows_mock)
      end
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

    # ---------------------------------------------------------------------
    # 7. PeopleController#diaspora_id? boundary mock — NEW for results2.
    #
    # results2's whole point is params[:username] symbolic. The real body is
    #   def diaspora_id?(query)
    #     !(query.nil? || query.lstrip.empty?) &&
    #       Validation::Rule::DiasporaId.new.valid_value?(query.downcase).present?
    #   end
    # `lstrip`/`downcase` are on SymbolicString's UNSUPPORTED list
    # (src/ruby_runtime/string.rb — "Transformations (return new plain
    # Strings)"), and Validation::Rule::DiasporaId's own regex match against
    # whatever survives is unverified/out-of-our-control gem code. A symbolic
    # username therefore crashes on `query.lstrip` on the FIRST call, before
    # any SQL, on every run — a src/ runtime gap (String transforms are
    # deliberately untracked, see CLAUDE.md), not something fixable by
    # subclassing the crashing VALUE (unlike ConcolicDate's #year, the
    # crashing call chain runs INTO third-party gem code we cannot safely
    # assume the semantics of).
    #
    # `diaspora_id?` is a PRIVATE PeopleController predicate: NO SQL, calls NO
    # declared target (Validation::Rule::DiasporaId is a plain regex object,
    # not an AR target) — exactly the "smallest enclosing SQL-free leaf" the
    # main README's wall-fixing discipline calls for (§ Wall-fixing
    # discipline). Mocking it is a boundary decision in the same idiom as the
    # shared finder_mock (63.7% of this experiment's PCs are recorded exactly
    # this way, main README §"Declaring assumptions"), and it has a genuine
    # upside over crash-avoidance alone: it makes the branch DSE-flippable,
    # so BOTH of find_person's finder paths (diaspora_handle lookup vs
    # find_from_guid_or_username) get explored instead of the request
    # hard-crashing at 0 PCs every single run.
    # ---------------------------------------------------------------------
    interceptor.declare_target(PeopleController, :diaspora_id?, returns: lambda do |_receiver, _args, name|
      vn = "#{name}_result"
      note = "diaspora_id?(username) boundary decision " \
             "(people_controller.rb private predicate — no SQL, no target calls beneath it)"
      # EXPLICIT compare inside the mock, mirroring the shared finder_mock
      # (concolic_targets.rb:371, "if not_found == true # explicit compare —
      # bare truthiness records no PC"). find_person calls this as bare
      # `if diaspora_id?(username)` — returning the raw SymbolicBool wrapper
      # would hit the Ruby truthiness gap (src/TODO.txt: any non-nil/non-false
      # OBJECT is truthy, so the app would ALWAYS take the true branch and
      # DSE could never flip it). Deciding with `== true` HERE records the PC
      # and lets the mock return a plain concrete Ruby bool instead.
      #
      # FIX (results2 completion pass): a plain concrete Ruby bool is not
      # enough here. declare_target's own "Body-skip mode" return path
      # (call_interceptor.rb ~171-182) re-wraps ANY of Integer/String/
      # Float/true/false/Array/Hash/nil through to_symbolic before handing
      # it back to the caller. to_symbolic(false) produces a SymbolicBool
      # OBJECT (symbolic_func.rb:171-173) -- a non-nil Ruby object, hence
      # bare-truthy -- so `if diaspora_id?(username)` ALWAYS took the true
      # branch regardless of `decided`'s value (verified: a False-PC dump
      # issued the identical diaspora_handle SQL as a True dump; see
      # REPORT.md "Central finding", now superseded by this fix).
      # to_symbolic(nil) is the ONE case to_symbolic passes through
      # unchanged (symbolic_func.rb:166-170, "nil means absent -- pass
      # through unchanged"), so nil reaches `if diaspora_id?(username)` as
      # a real falsy value. This is the same steering pattern people_show/
      # targets.rb Section B's DiasporaIdBoundaryMock uses -- there via
      # `prepend`, which bypasses declare_target's wrapper entirely, so
      # plain `decided == true` was already correct there. declare_target's
      # extra wrap is why people_stream needs the explicit ternary here.
      decided = symbool(vn, ct.seed_for(vn, true), note: note)
      (decided == true) ? true : nil
    end)

    # ---------------------------------------------------------------------
    # 8. `User#person` association reader — NEW for the results2 completion
    # pass, ported VERBATIM (rationale unchanged) from
    # results2/people_show/targets.rb §B's UserSymPersonAssociation. Same
    # documented src/ gap as §1's PersonSymAssociations: a symbolic
    # `klass.allocate` instance has no usable @association_cache, so plain
    # `user.person` raises NoMethodError. Needed ONLY now that diaspora_id?
    # genuinely flips false (§7 fix, above): find_person's false branch ->
    # find_from_guid_or_username (person.rb:196-206) -> its `elsif
    # params[:username].present? && u = User.find_by_username(...)` arm ->
    # `u.person` on the symbolic User the shared find_by finder_mock
    # returns.
    # ---------------------------------------------------------------------
    unless User.ancestors.include?(UserSymPersonAssociation)
      User.prepend(UserSymPersonAssociation)
    end

    warn "[people_stream] PeopleStreamTargets installed"
  end

  # -----------------------------------------------------------------------
  # 6. Per-run request-state reset (verbatim port of §6) — Gon.preloads uses
  # the CLASS-level Gon, not the `gon` helper the shared file stubs.
  # -----------------------------------------------------------------------
  def begin_run!
    return unless defined?(Gon::Request) && defined?(RequestStore)
    req = Gon::Request.new({})
    req.gon["preloads"] = {}
    RequestStore.store[:gon] = req
  rescue StandardError => e
    warn "[people_stream] gon request-state reset failed: #{e.class}: #{e.message[0, 80]}"
  end

  # -----------------------------------------------------------------------
  # 4. Concrete overrides for the symbolic CURRENT USER — REVISED for
  # results2. Cannot be `declare_target`s: `symbolic_instance` installs
  # per-column readers with `define_singleton_method`, which beats both a
  # class-level `define_method` and any prepend, so overrides must be
  # applied to the built instance (why this is a module_function the runner
  # calls, not part of `install!`).
  #
  # PINS REMOVED (results2/README.md item 2/3 — "no user.id/person.id
  # pins"): id, person_id, guid, diaspora_handle. `guid`/`diaspora_handle`
  # are `delegate :guid, :diaspora_handle, ..., to: :person` on the REAL
  # User model (user.rb:57-58) — with no singleton override they now resolve
  # through that real delegate to person.guid / person.diaspora_handle,
  # i.e. SYM_PERSON_<tag>_guid / SYM_PERSON_<tag>_diaspora_handle,
  # symbolically. `person_id` is a real `users` column, so
  # `symbolic_instance` already gives it its own independent SymbolicInt
  # (SYM_USER_<tag>_person_id) — NOT constrained equal to person.id (see
  # REPORT.md, same caveat results2/posts_show already documented).
  #
  # PINS KEPT, documented as FORCED (not identity attributes):
  #   language  users.language IS a column -> symbolic by default. Read by
  #             the REAL `set_locale` before_action, and a SymbolicString
  #             crashes i18n's `enforce_available_locales!` BEFORE the
  #             action body runs — walls every entrypoint at 0 PCs. Not
  #             branched on by people#stream. Ported verbatim from
  #             results/people/targets.rb §4 (unchanged root cause).
  #   gender    delegated to person -> profile; read by the
  #             layout/presenter chain only, never branched on.
  #
  # Association scoping (results2 item 5): rescoped from the source batch's
  # unscoped `Klass.all` to the real FK with the SYMBOLIC id, mirroring
  # results2/posts_show's identical treatment, so the query's WHERE clause
  # carries a genuine $$() bind instead of being dropped by an unscoped
  # relation.
  # -----------------------------------------------------------------------
  def apply_user_overrides!(user, person)
    user.define_singleton_method(:person) { person }
    user.define_singleton_method(:language) { "en" }
    user.define_singleton_method(:gender)   { "" }

    user.define_singleton_method(:contacts) { Contact.where(user_id: user.id) }
    user.define_singleton_method(:blocks)   { Block.where(user_id: user.id) }
    user.define_singleton_method(:aspects)  { Aspect.where(user_id: user.id) }
    user.define_singleton_method(:contact_for) do |p|
      Contact.includes(person: :profile).find_by(user_id: user.id, person_id: p.id)
    end
    user.define_singleton_method(:block_for) { |_p| Block.none }

    # posts_from: the ONE association people_stream's signed-in scenario
    # actually calls (Stream::Person#posts -> user.posts_from(@person) when
    # user.present?). The REAL User#posts_from (user/querying.rb:70) is
    # `Post.from_person_visible_by_user(self, person).order(...)` — a
    # multi-join visibility query needing real aspects/contacts association
    # state the symbolic instance does not have (§1's documented gap).
    # Overridden here, rescoped to the real FK (`author_id: person.id`)
    # rather than the source batch's unscoped `Post.all`, so the symbolic
    # person id lands in the SQL as a genuine $$() bind.
    user.define_singleton_method(:posts_from) { |p| Post.where(author_id: p.id) }
    user
  end

  # Build the symbolic current user used by the signed-in scenario. Built
  # FRESH per run (ported rationale from results/people/targets.rb §4's
  # runner-called module_function) so seed_overrides apply to the current
  # user's symbolic columns too — a user built once at boot would freeze
  # its vars at whatever seed_for returned at construction time, which
  # matters here because §7's mocks and person.id (now unpinned) can be
  # compared/flipped across runs.
  def symbolic_user(tag)
    # person.id: PIN REMOVED (results2 item 3 — try symbolic first). See
    # REPORT.md for whether this held up or hit the documented AR
    # integer-cast wall.
    person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user's person)")
    user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
    apply_user_overrides!(user, person)
  end
end

# §1's implementation module (top-level so `Person.ancestors.include?` reads
# cleanly and a re-`install!` is idempotent).
module PersonSymAssociations
  # results3/people_stream FIX (mission item 1 — "Person#posts staying
  # unscoped Post.all was a documented association-state gap... scope it
  # properly if feasible"): rescoped from results2's unscoped `Post.all` to
  # the real FK (`author_id: self.id`), matching the same treatment
  # results2/posts_show and this file's own §4 `posts_from` already gave
  # user-side associations. Reached on the ANON json scenario:
  # `Stream::Person#posts` (lib/stream/person.rb) is `user.present? ?
  # user.posts_from(@person) : @person.posts.where(:public => true)` — the
  # anonymous (no-user) branch calls exactly this reader. Before this fix
  # the WHERE clause carried no bind at all (`Post.all.where(public: true)`
  # has no author_id condition); after it, `Post.where(author_id:
  # $$(...)).where(public: true)` carries a genuine symbolic bind.
  def posts
    respond_to?(:concolic_attrs) ? Post.where(author_id: self[:id]) : super
  end

  def profile
    if respond_to?(:concolic_attrs)
      ConcolicTargets.symbolic_instance(Profile, "SYM_PROFILE_PERSON",
                                        "Person#profile (has_one)")
    else
      super
    end
  end

  # results3/people_stream FIX: same rescoping as #posts above, for
  # consistency (Block belongs_to :person via person_id, app/models/
  # block.rb) — DEAD on this entrypoint today (verified: `person.blocks`,
  # the VIEWED person's blocks, is never read by people#stream; only
  # `user.blocks`, the SIGNED-IN user's, which §4's apply_user_overrides!
  # already scopes to `Block.where(user_id: user.id)`), kept scoped anyway
  # since it costs nothing and the association-state gap this mission item
  # names applies equally to it.
  def blocks
    respond_to?(:concolic_attrs) ? Block.where(person_id: self[:id]) : super
  end
end

# §8's implementation module — NEW for the results2 completion pass, ported
# VERBATIM (rationale unchanged) from results2/people_show/targets.rb §B's
# UserSymPersonAssociation. Top-level so `User.ancestors.include?` reads
# cleanly and a re-`install!` is idempotent (mirrors §1's PersonSymAssociations
# above). See §8's `install!` comment for why this is needed now.
module UserSymPersonAssociation
  def person
    respond_to?(:concolic_attrs) ? ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_via_user", "User#person (has_one)") : super
  end
end

# A SymbolicString subclass for the two entrypoint params (person_id,
# username), ported from results2/people_show/targets.rb §B's
# SymUsernameString. NEW for the results2 completion pass: once §7's fix
# lets diaspora_id? genuinely flip false, find_person's false branch runs
# `Person.find_from_guid_or_username({ id: params[:id] || params[:person_id],
# username: username })` (person.rb:196-206):
#
#   def self.find_from_guid_or_username(params)
#     p = if params[:id].present?
#           Person.find_by(guid: params[:id])
#         elsif params[:username].present? && u = User.find_by_username(params[:username])
#           u.person
#         else
#           nil
#         end
#     raise ActiveRecord::RecordNotFound unless p.present?
#     p
#   end
#
# Both `params[:id]` (== `params[:person_id]` here — `stream`'s route never
# sets `:id`, see run_dse.rb build_params) and `params[:username]` need
# `.present?`/`.blank?`, and `find_person`'s TRUE branch already calls
# `username.downcase` directly (people_controller.rb:132). All three are on
# SymbolicString's UNSUPPORTED list (string.rb) because SymbolicString < String
# and ActiveSupport patches `String#blank?` with `self !~ /\S/` — `=~` is
# UNSUPPORTED (untracked regex op); `downcase` is UNSUPPORTED outright
# (string.rb's "Transformations" stub list). Same Ruby-truthiness gap
# documented in src/TODO.txt: blank?/present? here decide CONCRETELY off the
# underlying seed, exactly like every other bare-truthiness call in this
# experiment (people_show's SymUsernameString, the shared finder_mock's
# `not_found == true` compares, and this file's own §7 fix above) — NOT a
# symbolic decision var, so (like people_show) it is not what DSE flips.
class SymEntrypointString < SymbolicString
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
