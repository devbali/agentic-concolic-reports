# frozen_string_literal: true
#
# Per-batch concolic targets — `photos`.
#
# WHY PER-BATCH TARGET FILES EXIST
# --------------------------------
# `reports/diaspora/concolic_targets.rb` is shared by all 13 batches. Wall-fixing
# mocks are inherently batch-specific, and some are actively WRONG elsewhere:
# `User#blocks` must stay a length-only SymbolicList for streams/posts (they read
# it through `Post.blocked_people`) but must be a real Relation here (photos calls
# `blocks.find_by(person_id:)`). With one shared file, every local wall fix needs a
# cross-batch decision — so walls stayed open and dumps kept NotImplementedError.
#
# This overlay installs AFTER `ConcolicTargets.install!`. `declare_target` uses
# `define_method`, so a later declaration replaces an earlier one: overrides are
# last-one-wins and need no registry support.
#
#   ConcolicTargets.install!(interceptor)   # shared generic AR interception
#   PhotosTargets.install!(interceptor)     # this file — batch-local wall fixes
#
# Every mock wraps the SMALLEST enclosing method whose real body contains NO SQL
# and calls NO other declared target (README wall-fixing discipline). Producing
# queries still run for real.

module PhotosTargets
  module_function

  # =====================================================================
  # 6d. ConcolicRegexString — regex predicates on a symbolic string.
  #     PORTED VERBATIM from results/services_admin/targets.rb §2b, whose
  #     comment cites THIS batch's `Profile#build_image_url` as its motivating
  #     case. It was written there and never carried across; this is that.
  #
  # profile.rb:169-173
  #     def build_image_url(url)
  #       return nil if url.blank? || url.match(/user\/default/)
  #       return url if url.match(%r{^https?://})
  #       "#{AppConfig.pod_uri...}#{url}"
  #     end
  # and `SymbolicString#match` / `#match?` / `#=~` are all in the runtime's
  # UNSUPPORTED list (string.rb:335) — strings track only `==`/`!=` by design.
  #
  # build_image_url CANNOT be mocked: its body IS the branch — §2 of this file
  # measured that mocking it takes photos_create from genuine to VACUOUS. So
  # fix the VALUE, with the same batch-local-subclass technique as §6a-6c.
  #
  # A regex match is not expressible in the `(VAR op LITERAL)` PC grammar this
  # rig uses, so the predicate is abstracted as a FRESH seedable boolean,
  # recorded at the predicate boundary (the sanctioned boundary-decided
  # pattern, src/TODO.txt) and answered concretely so the app branches for real.
  #
  # SOUNDNESS CAVEAT, stated plainly:
  #   the fresh boolean is INDEPENDENT of the string's concrete value. Its
  #   DEFAULT is the true concrete answer (`value =~ re`), so an unflipped run
  #   is exact. When DSE flips it, the path explored is one that some URL could
  #   take, but the concrete witness in that dump no longer satisfies the
  #   regex. The path is reachable; the witness is not a model of it. This is
  #   an over-approximation — false positives, never false negatives.
  # =====================================================================
  def define_regex_string!
    return if defined?(::ConcolicRegexString)

    ::Object.const_set(:ConcolicRegexString, Class.new(SymbolicString) do
      def as_regexp(re)
        re.is_a?(Regexp) ? re : Regexp.new(Regexp.escape(re.to_s))
      end

      def regex_predicate(re, label)
        rx   = as_regexp(re)
        slug = rx.source.gsub(/[^A-Za-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")[0, 40]
        slug = "re" if slug.nil? || slug.empty?
        vn   = "#{sym_name || 'str'}_match_#{slug}"
        sym  = symbool(vn, ConcolicTargets.seed_for(vn, !(value =~ rx).nil?), note: note)
        ans  = sym.value
        sym.send(:record!, "(#{vn} == True)", label, taken: ans)
        ans
      end

      def match(re, *_a)
        return nil unless regex_predicate(re, "match")

        value.match(as_regexp(re)) || true
      end

      def match?(re, *_a)
        regex_predicate(re, "match?")
      end

      def =~(re)
        regex_predicate(re, "=~") ? ((value =~ as_regexp(re)) || 0) : nil
      end
    end)
  end

  # Build a ConcolicRegexString that is registered exactly like `symstr` would
  # register it — same name, value and note, so seeding is untouched.
  def regex_str(name, val, note: nil)
    SymbolicFunc.register_var(name: name, sort: "String", value: val, note: note) if defined?(SymbolicFunc)
    ::ConcolicRegexString.new(val, name: name, note: note)
  end

  module_function :define_regex_string!, :regex_str

  # Shared by both module_function copies of the patched symbolic_instance.
  #   integer/bigint -> SuccIntValue  (adds #next/#succ; see 6c note)
  #   date/datetime  -> ConcolicDate  (real Date, symbolic seedable #year)
  #
  # String columns are deliberately NOT upgraded to ConcolicRegexString here.
  # Tried and reverted, measured both ways on photos_index (50 dumps):
  #   * re-installing a singleton reader -> 46 ArgumentError. The reader is
  #     0-arity and shadows app readers that take an argument, e.g.
  #     `Profile#image_url(size=:thumb_large)` reached via AvatarPresenter#small.
  #   * writing only into concolic_attrs -> 34 NoMethodError, 533 -> 468 PCs.
  # The wall this batch actually has is Photo#url (§1), which is a MOCK RETURN,
  # not a column. Narrow the fix to that; a blanket column upgrade buys nothing
  # here and costs coverage.
  # Same var name / seed / note in both cases, so the value stays the SAME
  # seedable symbolic variable — only its Ruby shape changes.
  def decorate_columns!(obj, klass, base_name, sql)
    klass.columns_hash.each do |col, meta|
      vn  = "#{base_name}_#{col}"
      cur = obj.respond_to?(:concolic_attrs) ? obj.concolic_attrs[col] : nil

      if %i[integer bigint].include?(meta.type) && cur.is_a?(SymbolicInt)
        sv = SuccIntValue.new(cur.value, name: vn, note: sql)
        obj.define_singleton_method(col) { sv }
        obj.concolic_attrs[col] = sv if obj.respond_to?(:concolic_attrs)
      elsif %i[date datetime].include?(meta.type)
        yn = "#{vn}_year"
        d  = ConcolicDate.new(1990, 1, 1)
        d.sym_year = symint(yn, ConcolicTargets.seed_for(yn, 1990), note: sql)
        obj.define_singleton_method(col) { d }
        obj.concolic_attrs[col] = d if obj.respond_to?(:concolic_attrs)
      end
    end
    obj
  rescue StandardError => e
    warn "[photos] decorate_columns! #{klass}: #{e.class}: #{e.message.to_s[0,60]}"
    obj
  end

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets
    define_regex_string!

    # ---------------------------------------------------------------------
    # 1. Photo#url — make the shared §W5 target SEED-AWARE.
    #
    # concolic_targets.rb:829 hard-codes its symstr and never calls seed_for, so
    # `(SYM_RESULT_Photo_url_1_url == '')` is inert: DSE generates the flip, runs
    # the child, and the mock ignores it. Sole cause of BOTH missing branches in
    # this batch (photos_create, photos_make_profile_photo).
    #
    # SQL-free leaf: builds a path from the mounted uploader. Default unchanged,
    # so behaviour is identical when no seed is supplied.
    # ---------------------------------------------------------------------
    interceptor.declare_target(Photo, :url, returns: lambda do |_r, _a, name|
      v = "#{name}_url"
      # §6d: regex-capable, so build_image_url's two `url.match(...)` branches
      # record instead of raising. Same name/value/note as the symstr it replaces.
      PhotosTargets.regex_str(v, ct.seed_for(v, "/uploads/#{name}_thumb.jpg"),
                              note: "Photo#url")
    end)

    # ---------------------------------------------------------------------
    # 2. DELIBERATELY NOT MOCKED: Profile#build_image_url
    #
    # It is a legal SQL-free leaf and mocking it DOES clear the
    # SymbolicString#match wall — but its body IS the branch
    # (`return nil if url.blank?`), which is the only path condition
    # photos_create records. Mocking it took that entrypoint from
    # genuine (1 PC) to VACUOUS (0 PCs): the wall closed and the coverage
    # went with it.
    #
    # A wall mock that swallows the branch it guards is a regression, not a
    # fix. With mock #1 seedable, the `url == ""` side returns nil BEFORE the
    # regex, so that side is wall-free and both sides of the branch are
    # observable; only the non-empty side still walls on
    # `SymbolicString#match` — a src/ruby_runtime gap, reported not patched.
    # ---------------------------------------------------------------------

    # ---------------------------------------------------------------------
    # 3. User#blocks -> real Relation. THE OVERRIDE THAT COULD NOT BE SHARED.
    #
    # concolic_targets.rb:546 returns a SymbolicList, on which the
    # association-scoped `blocks.find_by(person_id:)` in `User#block_for` cannot
    # fire -> NoMethodError in PersonPresenter#is_blocked? (8 dumps).
    #
    # `Block.all` routes that call into the declared FinderMethods#find_by target,
    # so the query stays REAL and yields a symbolic Block — strictly better
    # traceability than hiding it behind a length-only list.
    #
    # Scoped here precisely because streams/posts depend on the SymbolicList shape.
    # Caveat: drops the association's `WHERE blocks.user_id = <user>` scope, so
    # that query's rendered SQL is unscoped.
    # ---------------------------------------------------------------------
    interceptor.declare_target(User, :blocks, returns: ->(_r, _a, _n) { Block.all })

    # ---------------------------------------------------------------------
    # 4. NullRelation short-circuit for collection / emptiness mocks.
    #
    # PersonPresenter#current_user_person_contact returns `Contact.none` when
    # current_user is nil. The shared symbolic mocks make `Contact.none.present?`
    # TRUE, so the app enters a branch UNREACHABLE in production and dies with
    # `NoMethodError: id for Contact::ActiveRecord_Relation`.
    #
    # A NullRelation is DEFINED to be empty and issues no SQL — there is no query
    # to preserve and no declared target beneath it, so returning the concrete
    # empty result is a sound over-approximation, not a hidden query. Every other
    # receiver falls through to the shared symbolic behaviour.
    # ---------------------------------------------------------------------
    rel = ActiveRecord::Relation
    null_rel = defined?(ActiveRecord::NullRelation) ? ActiveRecord::NullRelation : nil

    if null_rel
      %i[to_a to_ary records].each do |m|
        interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
          next [] if receiver.is_a?(null_rel)
          vn  = "#{name}_rows"
          rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row",
                                     ct.sql_for(receiver, args))
          SymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn,
                           note: ct.sql_for(receiver, args), representative: rep)
        end)
      end

      { empty?: true, any?: false, one?: false, many?: false }.each do |m, null_val|
        interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
          next null_val if receiver.is_a?(null_rel)
          vn = "#{name}_#{m.to_s.delete('?')}"
          symbool(vn, ct.seed_for(vn, m == :empty? ? false : true),
                     note: ct.sql_for(receiver, args))
        end)
      end
    end

    # ---------------------------------------------------------------------
    # 5. Asset-path stub — environment wall, not a symbolic-runtime one.
    #
    # AvatarPresenter's CLASS BODY evaluates
    # `ActionController::Base.helpers.image_path("user/default.png")`, which
    # drives Sprockets through manifest.js -> `require underscore`. The minimal
    # rig has no compiled assets, so it raises Sprockets::FileNotFound WHILE THE
    # CLASS BODY IS STILL EXECUTING, leaving AvatarPresenter half-defined —
    # every later run in the same process then dies with
    # `NoMethodError: undefined method 'base_hash' for #<Profile>` (45 dumps
    # once photos_index exploration deepened). Order-dependent and misleading.
    #
    # Stubbing a pure display-URL builder makes the rig deterministic. Same fix
    # the `people` batch adopted.
    # ---------------------------------------------------------------------
    begin
      h = ActionController::Base.helpers
      h.define_singleton_method(:image_path)    { |src, *| "/concolic/assets/#{src}" }
      h.define_singleton_method(:path_to_image) { |src, *| "/concolic/assets/#{src}" }
      require "app/presenters/avatar_presenter" if defined?(Rails)
    rescue Exception => e
      warn "[photos] asset stub: #{e.class}: #{e.message.to_s[0,60]}"
    end

    # ---------------------------------------------------------------------
    # 6. Symbolic-shaped VALUE objects — closing "runtime gap" walls WITHOUT
    #    touching src/ruby_runtime.
    #
    # The runtime's symbolic classes are ordinary Ruby classes with public
    # readers (`SymbolicList#representative`, `SymbolicInt#value`). A missing
    # method is therefore NOT a src/ blocker: a batch-local SUBCLASS can add it
    # and a batch-local mock can return that subclass. No shared code changes.
    #
    # This replaces three "needs a src/ change" claims from the previous round.
    # ---------------------------------------------------------------------

    # 6a. Date-shaped symbolic value.
    #
    # `symbolic_instance` maps every non-integer/boolean column to SymbolicString,
    # so `profiles.birthday` (a `date` column) has no #year and
    # `PeopleHelper#birthday_format` dies with
    # `NoMethodError: undefined method 'year' for <SymStr ...>` (33 dumps).
    #
    # Mocking birthday_format is NOT allowed here: its body IS the branch
    # (`if bday.year <= 1004`). Instead give it a value that is a REAL Date
    # (so `I18n.l` and its `Date === obj` check still work, and strftime is
    # inherited) whose #year returns a seedable SymbolicInt — so the comparison
    # records a genuine, flippable path condition instead of crashing.
    unless defined?(ConcolicDate)
      ::Object.const_set(:ConcolicDate, Class.new(::Date) do
        attr_writer :sym_year
        def year
          @sym_year || super
        end
      end)
    end

    # 6a-wiring: route date/datetime columns through ConcolicDate.
    #
    # Batch-local WRAPPER around the shared symbolic_instance (the shared file
    # itself is untouched): after the generic build, replace each date-column
    # reader with a ConcolicDate whose #year is the seedable symint
    # "<base>_<col>_year". The comparison in birthday_format then records
    # `(<var> <= 1004)` as a real PC instead of crashing.
    # NOTE: `module_function` keeps TWO copies of every method — a public
    # singleton copy and a PRIVATE INSTANCE copy — and ConcolicTargets' own
    # internal callers (e.g. the lambda returned by `finder_mock`) invoke the
    # INSTANCE copy. Patching only `class << ConcolicTargets` therefore misses
    # every instance built inside the shared file: measured 1577 decorated vs
    # **54 leaked** raw `SymbolicString` birthdays. Redefine the instance copy
    # and re-run `module_function` so BOTH copies are regenerated from it.
    # (Credit: the `likes` batch hit the same trap.)
    unless ConcolicTargets.respond_to?(:symbolic_instance_undecorated)
      ConcolicTargets.singleton_class.send(:alias_method,
                                           :symbolic_instance_undecorated,
                                           :symbolic_instance)
      ConcolicTargets.send(:alias_method,
                           :symbolic_instance_undecorated_i,
                           :symbolic_instance)

      ConcolicTargets.module_eval do
        define_method(:symbolic_instance) do |klass, base_name, sql|
          # Call the SINGLETON alias explicitly. `module_function` below makes
          # the instance copy private, so a bare call to the instance-level
          # alias is unreachable from the regenerated singleton copy.
          obj = ConcolicTargets.symbolic_instance_undecorated(klass, base_name, sql)
          PhotosTargets.decorate_columns!(obj, klass, base_name, sql)
        end
        module_function :symbolic_instance
      end
    end

    # 6b. Iterable symbolic list.
    #
    # The shared collection mock already attaches `representative:`, and
    # #first/#last/#[0] honour it — only #each/#map raise. Yielding the
    # representative once is the same Gate 1b "one sampled row" semantics those
    # readers already implement, so this is consistency, not new modelling.
    unless defined?(IterableSymbolicList)
      ::Object.const_set(:IterableSymbolicList, Class.new(SymbolicList) do
        def each
          return to_enum(:each) unless block_given?
          yield @representative if @representative && concrete_length != 0
          self
        end
        # DELIBERATELY NOT `include Enumerable`: a module included into a
        # subclass inserts BEFORE the superclass in the ancestor chain, so
        # Enumerable#any?/#none?/#count would SHADOW the PC-recording
        # SymbolicList#any? — silently destroying path conditions on an
        # otherwise green, zero-error run. (Found by the notifications_tags
        # batch: 8 PCs -> 4 on a clean run, caught only by diffing per dump.)
        def map
          return to_enum(:map) unless block_given?
          (@representative && concrete_length != 0) ? [yield(@representative)] : []
        end
        alias_method :collect, :map
      end)
    end

    # Declare on CollectionProxy TOO, not just Relation. CollectionProxy has
    # its OWN #records (collection_proxy.rb:1003) which SHADOWS
    # Relation#records, so an association like `contact.aspect_memberships`
    # never reaches the Relation declaration — measured here as 2 photos_index
    # dumps still dying on SymbolicList#each at contact_presenter.rb:12
    # (`aspect_memberships.map`), and found first by the posts batch, where the
    # same shadow left 259 dumps erroring after its first overlay attempt.
    list_receivers = [rel]
    list_receivers << ActiveRecord::Associations::CollectionProxy if
      defined?(ActiveRecord::Associations::CollectionProxy)

    list_receivers.product(%i[to_a to_ary records]).each do |recv, m|
      interceptor.declare_target(recv, m, returns: lambda do |receiver, args, name|
        next [] if null_rel && receiver.is_a?(null_rel)
        vn  = "#{name}_rows"
        rep = ConcolicTargets.symbolic_instance(ConcolicTargets.model_class(receiver),
                                                "#{name}_row",
                                                ConcolicTargets.sql_for(receiver, args))
        IterableSymbolicList.new(ConcolicTargets.seed_for("len(#{vn})", 1), name: vn,
                                 note: ConcolicTargets.sql_for(receiver, args),
                                 representative: rep)
      end)
    end

    # 6c. Successor-capable symbolic int.
    #
    # `participation.count.next` in User#update_or_create_participation! raises
    # NotImplementedError. The enclosing method issues SQL, so it cannot legally
    # be mocked — but the VALUE can carry #next. Mirrors SymbolicInt#-@, which
    # already returns a sound symbolic result rather than raising.
    unless defined?(SuccIntValue)
      ::Object.const_set(:SuccIntValue, Class.new(SymbolicInt) do
        def next
          SuccIntValue.new(value + 1, name: (sym_name ? "(#{sym_name} + 1)" : nil), note: note)
        end
        alias_method :succ, :next
      end)
    end

    # NOTE (corrected after audit): an earlier version of this file overrode
    # `ActiveRecord::Calculations#count` to return SuccIntValue. That was WRONG.
    # The crash site is `participation.count`, where `count` is an INTEGER COLUMN
    # (db/schema.rb:303, `t.integer "count", default: 1`) produced by
    # symbolic_instance's column reader — `Calculations#count` never runs there.
    # The override therefore fixed nothing and retyped every genuine aggregate
    # count in the batch as a side effect. It is removed; integer columns are
    # minted as SuccIntValue in the symbolic_instance wrapper below instead.

    warn "[photos] PhotosTargets installed"
  end
end
