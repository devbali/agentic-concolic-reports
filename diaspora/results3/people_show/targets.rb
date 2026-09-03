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

# results3/people_show ADDITION: recover pluck's real column list.
# CallInterceptor's call_args zip is lossy/mislabelled for splat methods
# (src/ gap, reported, worked around runner-locally) — ported verbatim from
# results2/conversations_index/targets.rb's PluckArgs (renamed to avoid any
# cross-file constant collision, though each results3 endpoint's targets.rb
# is independently loaded so a collision was never actually possible).
module PeopleShowPluckArgs
  def pluck(*column_names)
    prev = Thread.current[:people_show_pluck_cols]
    Thread.current[:people_show_pluck_cols] = column_names.flatten.map(&:to_s)
    super
  ensure
    Thread.current[:people_show_pluck_cols] = prev
  end
end

module PeopleTargets
  module_function

  # Column -> symbolic scalar of the right sort, seeded through seed_for so
  # DSE can actually flip it. Ported verbatim from
  # results2/conversations_index/targets.rb's `sym_for_column` (same bug fix:
  # SampledList-style representative construction bypasses the `symstr`
  # factory, which is the ONLY thing that calls SymbolicFunc.register_var —
  # register explicitly so the expr appears in the dump's `symbolic_vars` and
  # stays inside the checker's evaluable universe, not `unevaluable_exprs`).
  def sym_for_column(receiver, col, var, note)
    bare = col.to_s.split(".").last.to_s
    type =
      begin
        ConcolicTargets.model_class(receiver).columns_hash[bare]&.type
      rescue StandardError
        nil
      end
    type ||= (bare == "id" || bare.end_with?("_id")) ? :integer : :string

    case type
    when :integer, :bigint, :float, :decimal
      symint(var, ConcolicTargets.seed_for(var, 1), note: note)
    when :boolean
      symbool(var, ConcolicTargets.seed_for(var, false), note: note)
    else
      val = ConcolicTargets.seed_for(var, "sym_#{bare}")
      symstr(var, val, note: note)
    end
  end

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
    # results3/people_show ADDITION: javascript_include_tag/stylesheet_link_tag
    # stub — SAME "Sprockets/environment wall" category as §3 above
    # (image_path/path_to_image), found live once render became real:
    # `app/views/layouts/application.html.haml:11` (`= javascript_include_tag
    # :main`, reached by `respond_with @presenter, layout: "with_header"` on
    # every html-format run) drives Sprockets to compile `main.js`, which
    # `//= require`s `underscore`/`backbone`/etc — vendor JS files this
    # stripped-down concolic sandbox does not carry (verified: raised
    # `Sprockets::FileNotFound couldn't find file 'underscore'`, NOT an app-
    # logic exception). This happens strictly AFTER all controller/presenter/
    # template logic has already run — by the time the layout's own markup is
    # rendering, every path condition and query this endpoint's mission cares
    # about has already fired, so stubbing it costs no coverage, only removes
    # a guaranteed-every-run crash the app's own real deployment (with
    # precompiled assets) would never hit either. `ActionView::Helpers::
    # AssetTagHelper` is the module actually mixed into view context (unlike
    # `ActionController::Base.helpers`, which only affects helper calls made
    # FROM controllers/presenters like AvatarPresenter above — the layout
    # calls this from within the VIEW's own binding).
    # ---------------------------------------------------------------------
    begin
      require "action_view/helpers/asset_tag_helper" if defined?(Rails)
      if defined?(ActionView::Helpers::AssetTagHelper)
        ActionView::Helpers::AssetTagHelper.module_eval do
          define_method(:javascript_include_tag) { |*_sources, **_opts| "".html_safe }
          define_method(:stylesheet_link_tag)    { |*_sources, **_opts| "".html_safe }
        end
      end
      # The stub above alone is NOT enough: `Sprockets::Rails::Helper`
      # (sprockets-rails gem) redefines `javascript_include_tag`/
      # `stylesheet_link_tag` ITSELF (sprockets/rails/helper.rb) and is mixed
      # into `ActionView::Base` with HIGHER ancestor-chain precedence than
      # the base `ActionView::Helpers::AssetTagHelper` (included later, by a
      # Railtie, during boot) — so it shadows the patch above and the
      # Sprockets-backed implementation still runs, still hits the missing-
      # vendor-JS wall. Patch the ACTUAL shadowing module directly too.
      if defined?(Sprockets::Rails::Helper)
        Sprockets::Rails::Helper.module_eval do
          define_method(:javascript_include_tag) { |*_sources, **_opts| "".html_safe }
          define_method(:stylesheet_link_tag)    { |*_sources, **_opts| "".html_safe }
          # THE ACTUAL FIX: `compute_asset_path` (sprockets/rails/helper.rb)
          # is the universal chokepoint EVERY OTHER asset helper funnels
          # through — `image_path`/`path_to_image`/`javascript_path`/
          # `stylesheet_path`/`image_tag`'s src attribute — all call
          # `path_to_asset` -> `compute_asset_path`. `_head.haml`'s
          # `image_path("apple-touch-icon.png")` (called BEFORE the
          # javascript_include_tag/stylesheet_link_tag stubs above ever run,
          # per the layout's own line order) hits this UNPATCHED, and
          # `resolve_asset_path` -> `resolve_asset` triggers Sprockets to
          # lazily build/memoize `Rails.application.assets` for the FIRST
          # time — which, as a side effect, walks `app/assets/config/
          # manifest.js`'s own `//= link`/`//= link_tree` directives
          # (pulling in `main.js` -> `//= require underscore`) REGARDLESS of
          # which specific asset was actually being resolved. This is why
          # patching javascript_include_tag/stylesheet_link_tag ALONE did
          # NOT clear the wall (verified via a probe reproducing the exact
          # tc.process dispatch) — `image_path` was the actual first-touch
          # trigger, an entirely different, unstubbed method. Patching this
          # one chokepoint closes ALL of them at once.
          define_method(:compute_asset_path) { |source, _options = {}| "/concolic/assets/#{source}" }
        end
      end
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn "[people_show] asset-tag stub: #{e.class}: #{e.message.to_s[0, 80]}"
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

    # results3/people_show ADDITION (PHASE_A_PATCH.md Patch 4, applicability
    # table: "people_show — yes"). `ActiveRecord::Associations::CollectionProxy`
    # (a Relation subclass) OVERRIDES `records` itself (collection_proxy.rb:
    # 1003, `def records; load_target; end` -> `@association.load_target`), so
    # a target declared only on `ActiveRecord::Relation` never fires for a bare
    # collection-association read (`profile.tags`, `person.posts`, ...) — it
    # would run the real, unmocked load path against a symbolic owner id.
    cproxy = defined?(ActiveRecord::Associations::CollectionProxy) ? ActiveRecord::Associations::CollectionProxy : nil
    if cproxy
      %i[to_a to_ary records load_target].each do |m|
        next unless cproxy.method_defined?(m) || cproxy.private_method_defined?(m)
        interceptor.declare_target(cproxy, m, returns: rows_mock)
      end
      # results3/people_show MOBILE-FORMAT FIX (found live, anon_mobile
      # scenario): CollectionProxy#size is its OWN method (collection_proxy.rb:783
      # -> CollectionAssociation#size, collection_association.rb:218), so the
      # shared `rel :size` target (declared on ActiveRecord::Relation) never
      # fires for a bare collection-association read. The real body does
      # `unsaved_records.size + count_records` on the NOT-loaded path
      # (target.is_a?(Array) && !distinct) -> `0 + SymbolicInt` ->
      # SymbolicInt#coerce NotImplementedError (int.rb:152) BEFORE any mock
      # can record the count. Everyone on the mobile stream element hits it:
      # mobile_reshare_icon (post.reshares.size), mobile_comment_icon
      # (post.comments.size), mobile_like_icon (post.likes.size). Fix mirrors
      # the shared rel:size target EXACTLY (same COUNT(*) note rewrite, same
      # symint seeding) so size semantics stay evidence-equivalent to the
      # relation-level mock — the count query is the same, only the dead
      # `0 +` transform (unsaved_records is ALWAYS empty on symbolic target
      # arrays) is elided.
      interceptor.declare_target(cproxy, :size, returns: lambda do |receiver, args, name|
        vn = "#{name}_size"
        note = ct.sql_for(receiver, args)
        begin
          note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT COUNT(*) FROM ")
        rescue StandardError
          nil
        end
        symint(vn, ct.seed_for(vn, 1), note: note)
      end)
    end

    # ---------------------------------------------------------------------
    # results3/people_show ADDITION: Calculations#pluck -> length-only
    # IterableSymbolicList with a representative. Needed by
    # ProfilePresenter#public_hash/#for_hovercard:
    #   tags.pluck(:name)
    # ("tags" = profile.tags, an acts_as_taggable_on association, single
    # column). Shared file declares pluck UNSUPPORTED (concolic_targets.rb
    # design #6/5b) — same rationale as results2/conversations_index's
    # identical descent (see that file's targets.rb): pluck IS the query
    # boundary, same role as records/to_a, not a new hole in the "contents
    # ops raise" policy. This is the "profile section" query the mission
    # brief specifically calls out recovering.
    #
    # PluckArgs recovers pluck's real column list — CallInterceptor's
    # call_args zip is lossy/mislabelled for splat methods (src/ gap,
    # reported, worked around runner-locally, ported verbatim from
    # results2/conversations_index/targets.rb §1b).
    # ---------------------------------------------------------------------
    unless rel < PeopleShowPluckArgs
      rel.prepend(PeopleShowPluckArgs)
    end

    calc = ActiveRecord::Calculations
    interceptor.declare_target(calc, :pluck, returns: lambda do |receiver, args, name|
      note = ct.sql_for(receiver, args)
      vn   = "#{name}_plucked"
      cols = Thread.current[:people_show_pluck_cols] || []
      cols = ["value"] if cols.empty?
      vals = cols.each_with_index.map do |c, i|
        var = cols.size == 1 ? "#{name}_pluck_#{c.split('.').last}" : "#{name}_pluck#{i}_#{c.split('.').last}"
        PeopleTargets.sym_for_column(receiver, c, var, note)
      end
      rep = cols.size == 1 ? vals.first : vals
      IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn, note: note, representative: rep)
    end)

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
    # results3/people_show DESCENT (found live in a scratch validation run):
    # `PersonPresenter#description` (a PRIVATE presenter method,
    # app/presenters/person_presenter.rb ~124-126):
    #   def description
    #     public_details? ? bio : ""
    #   end
    # is reached from `metas_attributes`'s `og_description`/`description`
    # fields, rendered by `show.html.haml`'s `content_for :meta_data ->
    # metas_tags` on EVERY html-format run. `public_details?` is a real
    # boolean-predicate delegate (Person -> profile.public_details, already
    # handled by symbolic_instance's boolean-predicate-reader convention —
    # records its own PC, returns a concrete bool). `bio` (Person -> delegate
    # -> profile.bio) is a GENUINE, still-tracked SymbolicString column — no
    # SQL is skipped by mocking `description` (bio's SELECT already fired via
    # `profile`'s association load), the wall is downstream Rails HTML-escape
    # machinery (`ERB::Util`/`ActiveSupport::Multibyte::Unicode#tidy_bytes`
    # calling `.scrub`, UNSUPPORTED by design on a tracked SymbolicString —
    # same class of wall as X6h/X6i, ConcreteSymbolicString-wrapped here
    # too). `description` is SQL-free and calls no OTHER declared target
    # besides the already-safe `public_details?` boolean predicate, making it
    # the smallest enclosing leaf.
    # ---------------------------------------------------------------------
    if defined?(PersonPresenter) &&
       (PersonPresenter.instance_methods.include?(:description) ||
        PersonPresenter.private_instance_methods.include?(:description))
      interceptor.declare_target(PersonPresenter, :description, returns: lambda do |receiver, _args, name|
        pub = receiver.public_details?
        ConcreteSymbolicString.build(pub ? "Concolic bio" : "", name: name,
                                     note: "PersonPresenter#description (untracked bio HTML-escape leaf)")
      end)
    end

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

  # results3/people_show DESCENT (found live in a scratch validation run —
  # a NEW violation this rerun's Patch 1 exposes, not present in results2):
  # this override used to be NEEDED because a symbolic `klass.allocate`
  # instance had no usable `@association_cache`, so the REAL `profile`
  # has_one reader crashed before any symbolic op was reached — see
  # `symbolic_instance`'s own comment in ../concolic_targets.rb. That gap was
  # closed GENERICALLY (not per-endpoint) by `symbolic_instance` initializing
  # `@association_cache = {}` on every symbolic instance, which is already
  # present in this file's ported base — so the REAL `profile` reader now
  # works fine on its own, falling through to `SingularAssociation#find_target`
  # (PHASE_A_PATCH.md Patch 1, applied in ../concolic_targets.rb), which
  # renders a REAL SQL note (`SELECT "profiles".* FROM "profiles" WHERE
  # "profiles"."person_id" = $$(...)`) instead of this override's junk
  # "Person#profile (has_one)" string. Keeping this override was an outer
  # mock preventing Patch 1's fix from ever firing along this call path —
  # the exact "Post.blocked_people vs User#blocks" pattern PHASE_A_PATCH.md
  # Patch 3 documents. REMOVED (verified live: `self.profile.nil?`/
  # `self.profile.first_name` etc. all still work correctly without it, and
  # the dump now carries the real find_target-rendered SQL note).
  #
  # `posts`/`blocks` above are a DIFFERENT association shape (has_many, not
  # has_one) that never reaches `find_target` at all — Patch 1 does not
  # apply to them, and neither is reached by people#show's own call graph,
  # so both are left untouched (minimal-changes discipline).

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

  # `Post#location` mobile-render wall (2026-09-03, cycle 1):
  # shared/_post_info.mobile.haml:31 reads `post.location` on every stream
  # post; `location` exists only as StatusMessage's has_one (STI), so a
  # base-Post symbolic rep (decorated_stream_posts) NoMethodErrors. Prepend
  # (NOT declare_target — the method doesn't exist on base Post) returning
  # nil; StatusMessage's own has_one reader still wins for real
  # StatusMessage instances. Full rationale in this fork's
  # concolic_targets.rb (stream section).
  module PostSymLocation
    def location
      respond_to?(:concolic_attrs) ? nil : super
    end
  end

  def install!(_interceptor = CallInterceptor.instance)
    PeopleController.prepend(DiasporaIdBoundaryMock) unless PeopleController.ancestors.include?(DiasporaIdBoundaryMock)
    User.prepend(UserSymPersonAssociation) unless User.ancestors.include?(UserSymPersonAssociation)
    Post.prepend(PostSymLocation) unless Post.ancestors.include?(PostSymLocation)
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
