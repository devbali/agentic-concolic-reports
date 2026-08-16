# frozen_string_literal: true
#
# Per-batch concolic targets — `search_links_reports_profiles`.
#
# Installs AFTER ConcolicTargets.install!. `declare_target` uses define_method,
# so a later declaration REPLACES an earlier one (last-one-wins).
#
#   ConcolicTargets.install!(interceptor)                    # shared
#   SearchLinksReportsProfilesTargets.install!(interceptor)  # this file
#
# NOTHING under src/, nothing in the shared concolic_targets.rb, and nothing in
# the app is modified. Two mechanisms are used:
#
#   * MOCKS (declare_target) for walls that are really "this leaf does I/O we
#     cannot do here" — §1, §2.
#   * SUBCLASSES of the runtime's symbolic types for walls that are really
#     "the runtime does not implement operation X" — §3. The runtime's classes
#     are ordinary Ruby classes with public readers, so a batch-local subclass
#     adds the operation without touching anything shared.
#
# THE RULE THAT SHAPED THIS FILE: a wall mock that swallows the branch it
# guards is a regression, not a fix. §4 documents the one place where the
# obvious mock target had to be rejected for exactly that reason.
#
# Env switches (default ON; used to produce the BEFORE/AFTER evidence files):
#   SLR_NEW_RECORD_FIX=0   disable §6 symbolic_instance @new_record overlay

module SearchLinksReportsProfilesTargets
  # =======================================================================
  # §3. Symbolic-type subclasses — batch-local extensions of the runtime.
  #
  # Design rule for every operation added here: it is implemented ONLY for
  # the case where the answer is EXACT for the concrete witness, and raises
  # loudly otherwise. No operation silently concretizes, and none invents a
  # Z3 term the engine cannot interpret. Concretely:
  #
  #   strip           — identity when the witness has no surrounding
  #                     whitespace (then `strip` provably returns the same
  #                     string, so returning SELF preserves sym_name and the
  #                     whole constraint history exactly). Raises otherwise.
  #   split(multi)    — [self] when the witness does not contain the
  #                     separator (provably a one-element split). Raises
  #                     otherwise. This deliberately introduces NO new
  #                     symbolic terms — a term like Split(x,'::')[0] would
  #                     be unmodellable by the engine and would only add
  #                     unflippable path conditions.
  #   starts_with?/   — see §3b, a silent-tracking-loss repair rather than a
  #   ends_with?        missing operation.
  # =======================================================================
  class ConcolicString < SymbolicString
    WS = /\A\s|\s\z/.freeze

    def strip
      return self unless WS.match?(value)
      raise NotImplementedError,
            "ConcolicString#strip: witness #{value.inspect} has surrounding whitespace; " \
            "strip is only modelled where it is provably the identity"
    end

    alias lstrip strip
    alias rstrip strip

    def split(sep = nil, limit = nil)
      return super if sep.nil? || sep.to_s.length <= 1
      raise NotImplementedError, "ConcolicString#split with limit not supported" unless limit.nil?
      return [self] unless value.include?(sep.to_s)
      raise NotImplementedError,
            "ConcolicString#split(#{sep.inspect}): witness #{value.inspect} contains the " \
            "separator; multi-character split is only modelled where it is provably a no-op"
    end

    # `search_query.delete("#.")` builds the tag URL in search#search.
    # Character-class deletion is NOT expressible in the engine's string
    # theory, so there is no honest NAMED term to return. The options were:
    # raise (kills the arm after its path conditions are already recorded),
    # return a plain String (silent concretization — the exact sin the
    # UNSUPPORTED list exists to prevent), or this: a still-symbolic but
    # UNNAMED value. Unnamed means z3_expr renders the literal, so a later
    # comparison still records a path condition and still shows up as a
    # branch — it simply cannot be inverted by the solver. Nothing in
    # search#search branches on the result (it only feeds URL generation),
    # so nothing is lost here; anywhere it IS branched on, the loss is
    # visible in the dump as a literal-vs-literal condition rather than
    # hidden. Reported as a limitation, not claimed as a model.
    def delete(*args)
      self.class.new(value.dup.delete(*args.map(&:to_s)), name: nil, note: note)
    end

    # --- §3b. THE SILENT TRACKING LOSS -----------------------------------
    #
    # SymbolicString is a real String SUBCLASS (string.rb:49), and
    # ActiveSupport does, in core_ext/string/starts_ends_with.rb:
    #
    #     class String
    #       alias_method :starts_with?, :start_with?
    #       alias_method :ends_with?,   :end_with?
    #     end
    #
    # alias_method COPIES the method String#start_with? resolves to at alias
    # time — the native C implementation. Overriding `start_with?` in a
    # subclass therefore never reaches `starts_with?`. Every Rails-idiomatic
    # `sym.starts_with?(x)` reads the concrete buffer, answers correctly, and
    # RECORDS NOTHING.
    #
    # Not a loud NotImplementedError — a silently untracked branch, which is
    # precisely the failure mode the strict runtime exists to prevent. It is
    # why search#search looked "vacuous but correct": `starts_with?('#')` is
    # the outermost branch of the action.
    # ---------------------------------------------------------------------
    def starts_with?(*prefixes)
      start_with?(*prefixes)
    end

    def ends_with?(*suffixes)
      end_with?(*suffixes)
    end
  end

  # SymbolicList that can be iterated by yielding its single representative
  # element `length` times. The base class raises on every iteration op
  # (list.rb LIST_STUBS) because contents are out of scope — but the shared
  # Relation#to_a target already attaches a representative row
  # (concolic_targets.rb:448), so for a seeded length of 1 the iteration is
  # exact rather than approximate. Longer lengths yield the SAME
  # representative repeatedly, which is an over-approximation and is flagged
  # in the note.
  # SymbolicInt whose #to_i is the IDENTITY — it returns self, not a plain
  # Integer, so nothing is concretized.
  #
  # int.rb:29 makes to_i raise because it is a silent-concretization channel.
  # That is right for `to_int` (implicit coercion, Array#[] etc.) and it stays
  # raising here. But `to_i` on something that is already an integer is
  # mathematically the identity, and AR calls it as a TYPE CAST, not a
  # conversion: ActiveModel::Type::Integer#cast_value is `value.to_i`.
  # Returning self satisfies the cast and keeps the value symbolic all the way
  # into the attribute set.
  #
  # This is the report#create wall:
  #   current_user.reports.new(...) -> BelongsToAssociation#inversed_from
  #     -> Association#target= -> loaded! -> stale_state
  #     -> _read_attribute("user_id") -> Attribute#type_cast
  #     -> Type::Integer#cast_value -> SymbolicInt#to_i -> NotImplementedError
  # The owner id comes from `owner["id"]` (the symbolic attrs hash), not from
  # the runner's concrete `id` stub, which is why stubbing #id did not help
  # and the previous round had to replace the whole has_many with Report.all.
  class ConcolicInt < SymbolicInt
    def to_i
      self
    end
  end

  #
  # Enumerable is deliberately NOT included: it would insert itself ABOVE
  # SymbolicList in the lookup chain and quietly re-enable every op the
  # runtime blocks on purpose (select, sort_by, group_by, ...). Only the
  # three operations this batch actually needs are opened.
  class IterableSymbolicList < SymbolicList
    def each(&block)
      return enum_for(:each) unless block
      rep = representative
      if rep.nil?
        raise NotImplementedError,
              "IterableSymbolicList#each: no representative element to yield"
      end
      concrete_length.times { block.call(rep) }
      self
    end

    def map(&block)
      return enum_for(:map) unless block
      out = []
      each { |el| out << block.call(el) }
      out
    end

    alias collect map

    def to_a
      out = []
      each { |el| out << el }
      out
    end

    alias to_ary to_a
  end

  # §6 is consulted at CALL time, not install time, so a runner can execute
  # the same entrypoint with and without it in one process (see run_dse.rb,
  # profiles_edit) and ship both as evidence.
  class << self
    attr_accessor :new_record_fix, :int_upgrade
  end
  self.new_record_fix = ENV.fetch("SLR_NEW_RECORD_FIX", "1") != "0"
  self.int_upgrade    = ENV.fetch("SLR_INT_UPGRADE", "1") != "0"

  module_function

  # Factory mirroring the runtime's `symstr` (string.rb:457) — same var
  # registration, ConcolicString instead of SymbolicString.
  def constr(name, value = "", note: nil)
    sym = ConcolicString.new(value, name: name, note: note)
    if defined?(SymbolicFunc) && SymbolicFunc.respond_to?(:register_var)
      SymbolicFunc.register_var(name: name, sort: "String", value: value.to_s, note: note)
    end
    sym
  end

  # Re-wrap a plain SymbolicString/SymbolicInt as the batch-local subclass,
  # preserving name / note / concrete value. Anything else passes through.
  def upgrade(v)
    if v.instance_of?(SymbolicString)
      ConcolicString.new(v.value, name: v.sym_name, note: v.note)
    elsif v.instance_of?(SymbolicInt) && int_upgrade
      ConcolicInt.new(v.value, name: v.sym_name, note: v.note)
    else
      v
    end
  end

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets
    installed = []

    # =====================================================================
    # 1. DiasporaFederation::Federation::Fetcher.fetch_public -> nil
    #
    # THE MOST URGENT MOCK IN THIS BATCH: without it, links#resolve's
    # not-found side does a REAL HTTP fetch through typhoeus -> libcurl over
    # JRuby's FFI, which SIGSEGVs the whole JVM:
    #
    #   #  SIGSEGV (0xb) at pc=0x00007dd45c0a002f
    #   #  C  [libcurl.so.4+0x6e3af]  curl_easy_setopt+0x9f
    #   #  j  com.kenai.jffi.Foreign.invokeArrayReturnInt(JJ[B)I+0
    #
    # A JVM abort is not a dump — it destroys the process — so the previous
    # round had to SUPPRESS that flip and ship links_resolve as incomplete.
    #
    # Legality: the body is `entity_name` + `fetch_from_url` (HttpClient.get
    # + Receiver.receive_public). No SQL, no other declared target, and no
    # conditional on a symbolic value — the only `if`s are
    # `fetching[type].include?(guid)` (a thread-local re-entrancy guard) and
    # `response.success?` (a live HTTP status). Nothing here can produce a
    # path condition in a hermetic run.
    #
    # nil is the correct over-approximation, not a short-circuit:
    # DiasporaLinkService#fetch_entity is
    #     Fetcher.fetch_public(author, type, guid)
    #     entity_finder.find
    # so after the mock the REAL second `find_by(guid:)` still runs and is
    # still intercepted, with a fresh independently seedable `_not_found`
    # var. The branch is preserved; only the network is removed.
    # =====================================================================
    if defined?(DiasporaFederation::Federation::Fetcher)
      interceptor.declare_target(
        DiasporaFederation::Federation::Fetcher.singleton_class, :fetch_public,
        returns: ->(_r, _a, _n) { nil }
      )
      installed << "Fetcher.fetch_public"
    end

    # =====================================================================
    # 2. DiasporaFederation::Discovery::Discovery#fetch_and_save -> nil
    #
    # Same class of fix for the bare-handle input ("alice@example.org"):
    # DiasporaLinkService#find_or_fetch_person ->
    # Person.find_or_fetch_by_identifier -> Discovery.new(id).fetch_and_save,
    # which webfingers over the same HttpClient/libcurl path and crashes the
    # JVM one call later.
    #
    # Legality: body is `validate_diaspora_id` (a compare against the
    # webfinger response) plus a `save_person_after_webfinger` callback
    # trigger. No SQL of its own, no declared target. Crucially,
    # find_or_fetch_by_identifier calls `by_account_identifier(diaspora_id)`
    # AGAIN afterwards, so the real `find_by(diaspora_handle:)` query — and
    # its seedable not-found var — survives the mock.
    # =====================================================================
    if defined?(DiasporaFederation::Discovery::Discovery)
      interceptor.declare_target(
        DiasporaFederation::Discovery::Discovery, :fetch_and_save,
        returns: ->(_r, _a, _n) { nil }
      )
      installed << "Discovery#fetch_and_save"
    end

    # =====================================================================
    # 3b. Relation#to_a / #to_ary / #records -> IterableSymbolicList
    #
    # Byte-for-byte the shared declaration (concolic_targets.rb:448) except
    # for the list class, so the representative row and the SQL note are
    # unchanged. Needed because `@profile.tags.map` in profiles#edit hits
    # SymbolicList#each -> NotImplementedError once §6 makes the collection
    # association actually load.
    # =====================================================================
    rel = ActiveRecord::Relation
    %i[to_a to_ary records].each do |m|
      interceptor.declare_target(rel, m, returns: lambda do |receiver, args, name|
        vn  = "#{name}_rows"
        sql = ct.sql_for(receiver, args)
        rep = ct.symbolic_instance(ct.model_class(receiver), "#{name}_row", sql)
        IterableSymbolicList.new(ct.seed_for("len(#{vn})", 1), name: vn,
                                 note: sql, representative: rep)
      end)
    end
    installed << "Relation#to_a/to_ary/records -> IterableSymbolicList"

    # =====================================================================
    # 3c. SingularAssociation#find_target — resolve POLYMORPHIC targets.
    #
    # The shared target (concolic_targets.rb:793) builds its symbolic
    # instance from `receiver.reflection.klass`. For a polymorphic
    # belongs_to that is not a class at all — the reflection has no fixed
    # class_name — so it raises, the rescue returns nil, and `report.item`
    # comes back NIL. `case item when Post / when Comment` in
    # Report#destroy_reported_item then matches NOTHING and the whole
    # retract/destroy subtree is silently unreachable, even with a valid
    # item_type. That looked exactly like "the app took the no-op path".
    #
    # The association object itself knows better: BelongsToPolymorphicAssociation#klass
    # reads owner[item_type] and constantizes it. Prefer it, fall back to the
    # reflection for ordinary associations. No SQL is added — this only picks
    # the class the symbolic instance is allocated from.
    # =====================================================================
    if defined?(ActiveRecord::Associations::SingularAssociation)
      interceptor.declare_target(
        ActiveRecord::Associations::SingularAssociation, :find_target,
        returns: lambda do |receiver, _args, _name|
          refl  = receiver.reflection
          klass = begin
            receiver.klass
          rescue StandardError
            nil
          end
          klass ||= begin
            refl.klass
          rescue StandardError
            nil
          end
          next nil unless klass.respond_to?(:allocate)
          ct.symbolic_instance(klass, "assoc_#{refl.name}",
                               "SingularAssociation##{refl.name} (#{klass.name})")
        end
      )
      installed << "SingularAssociation#find_target (polymorphic-aware)"
    end

    # =====================================================================
    # 4. NOT MOCKED: BelongsToPolymorphicAssociation#klass, and NOT MOCKED:
    #    SearchController#search_query.
    #
    # (a) report#destroy walls at
    #       NotImplementedError: SymbolicString#split only supports
    #       single-character separators
    #         active_support/inflector/methods.rb:273  constantize  <- split("::")
    #         belongs_to_polymorphic_association.rb:9  klass
    #         report.rb:37                             destroy_reported_item
    #
    #     `klass` is a textbook SQL-free leaf:
    #         def klass
    #           type = owner[reflection.foreign_type]
    #           type.presence && type.constantize
    #         end
    #     and mocking it is WRONG. `type.presence` -> `present?` -> `blank?`
    #     -> `String#empty?`, and SymbolicString#empty? RECORDS
    #     `(<item_type> == '')` — the only path condition the polymorphic
    #     association produces, and the branch separating "item resolves to
    #     nil" from "item resolves to a model". Mocking `klass` swallows it:
    #     the photos/build_image_url regression, one method deeper.
    #
    #     Fixed instead by ConcolicString#split (§3) + §6's attribute
    #     upgrade, so the REAL constantize runs on the symbolic item_type.
    #
    # (b) search#search walls at SymbolicString#strip inside
    #         def search_query
    #           @search_query ||= (params[:q] || params[:term] || '').strip
    #         end
    #     Mocking `search_query` is legal by the letter of the rule (its body
    #     holds no branch; all three of the action's branches are in the
    #     caller) — but it is still second best, because the value would then
    #     enter one frame ABOVE the code under test. ConcolicString#strip
    #     (§3) lets the real method body run, and run_dse.rb injects the
    #     symbolic value at the actual program input, params[:q]. That
    #     injection is needed regardless of `strip`: ActionController::
    #     TestCase#process serialises params through `to_query` and re-parses
    #     them, so a symbolic value can never survive into params by itself.
    # =====================================================================

    # =====================================================================
    # 6. symbolic_instance -> @new_record = false, plus ConcolicString attrs.
    #    THE SILENT GAP.
    #
    # Not a mock — a runner-local overlay on ConcolicTargets. The shared FILE
    # is untouched; this rebinds the module function in-process only.
    #
    # concolic_targets.rb:317 ends symbolic_instance with
    # `obj.instance_variable_set(:@new_record, true)`. AR's
    # CollectionAssociation#find_target? is
    #
    #     !loaded? && (!owner.new_record? || foreign_key_present?) && klass
    #
    # and foreign_key_present? is false for a collection. So EVERY collection
    # association on EVERY symbolic record in EVERY batch short-circuits to
    # `[]` — no query issued, no target intercepted, no symbolic list built,
    # no path condition recorded. `@profile.tags` in profiles#edit is
    # silently empty; so are `user.aspects`, `post.comments`,
    # `user.contacts`, ... wherever a batch has not hand-stubbed them.
    #
    # Singular associations are unaffected (they route through the declared
    # SingularAssociation#find_target target), which is exactly why the gap
    # is easy to miss: the record looks fully wired up.
    #
    # The same wrapper upgrades every SymbolicString column value to
    # ConcolicString (§3), which is what puts a working `split` under
    # `item_type.constantize`. attrs is reachable because symbolic_instance
    # exposes the live hash via #concolic_attrs and every reader indexes it
    # at call time.
    # =====================================================================
    orig_si = ct.method(:symbolic_instance)
    ct.define_singleton_method(:symbolic_instance) do |klass, base_name, sql|
      obj = orig_si.call(klass, base_name, sql)
      if SearchLinksReportsProfilesTargets.new_record_fix
        obj.instance_variable_set(:@new_record, false)
      end
      if obj.respond_to?(:concolic_attrs)
        attrs = obj.concolic_attrs
        attrs.each_key { |k| attrs[k] = SearchLinksReportsProfilesTargets.upgrade(attrs[k]) }
      end
      obj
    end
    installed << "symbolic_instance(@new_record=#{!new_record_fix}, ConcolicString attrs)"

    # =====================================================================
    # 7. save / update / update_attribute — record the branch at the mock
    #    boundary and return a CONCRETE truth value.
    #
    # Two defects in the shared §F mock (concolic_targets.rb:503), which is
    # the single biggest source of dead branches in this batch:
    #
    #   (a) NO seed_for. `symbool("#{name}_#{m}_ok", true, ...)` hard-codes
    #       true, so the var is permanently INERT — DSE emits the flip, the
    #       mock ignores it, the branch can never close. Exactly the Photo#url
    #       defect the photos batch found, on a far more widely used target.
    #
    #   (b) It returns a SymbolicBool into `if report.save`. Bare Ruby
    #       truthiness cannot be hooked on a wrapper object (src/TODO.txt), so
    #       a SymbolicBool is ALWAYS truthy and NOTHING is recorded. That is
    #       what made `head :conflict` (report#create) and
    #       `flash[:error] = profiles.update.failed` (profiles#update)
    #       unreachable in the previous round.
    #
    # The fix is the pattern the shared file already blesses for boolean
    # column readers (concolic_targets.rb:230-241): record the path condition
    # AT THE MOCK BOUNDARY, then hand the app a concrete value so it branches
    # concretely and consistently. `true` still round-trips through the
    # interceptor as a SymbolicBool (truthy); the false side returns nil,
    # which is falsy for `if` and matches AR's own "failed" convention.
    #
    # Deliberately NOT applied to save!/update!/destroy/destroy!/touch:
    # the bang variants signal failure by raising, and destroy returns the
    # record, so a truth value is the wrong shape for them.
    # =====================================================================
    base = ActiveRecord::Base
    %i[save update update_attribute].each do |m|
      next unless base.instance_methods.include?(m)
      interceptor.declare_target(base, m, returns: lambda do |receiver, args, name|
        vn  = "#{name}_#{m}_ok"
        sym = symbool(vn, ct.seed_for(vn, true),
                      note: "#{receiver.class.name}##{m} args=#{args.inspect}")
        val = sym.value
        sym.send(:record!, "(#{vn} == True)", m.to_s, taken: val)
        val ? true : nil
      end)
    end
    installed << "Base#save/update/update_attribute (seedable + PC at boundary)"

    # =====================================================================
    # 8. FinderMethods#exists? — same boundary-record treatment.
    #
    # The shared §B mock (concolic_targets.rb:437) already seeds properly,
    # and its own comment concedes the problem: "`if Post.exists?(...)` hits
    # the Ruby truthiness gap — only explicit compares record PCs. Returned
    # anyway."
    #
    # In this batch that one gap makes the ENTIRE authorization guard
    # invisible:
    #   application_controller.rb:116  return if current_user.moderator?
    #   user.rb:473                    Role.moderator?(person)
    #   role.rb:27                     moderators.exists?(person_id: ...)
    # so `redirect_to stream_url, notice: "you need to be an admin or
    # moderator"` was unreachable on report#index, report#update and
    # report#destroy — and report#index, whose action body has no conditional
    # at all, had literally nothing left to record and was VACUOUS.
    #
    # Scoped to exists? on purpose. The sibling predicates (any?/none?/one?/
    # many?/empty?) are reached by collection code that sometimes wants a
    # SymbolicBool rather than a decision, and photos already showed that
    # forcing emptiness answers can push an app into branches unreachable in
    # production. One predicate, one guard, minimal blast radius.
    # =====================================================================
    fm = ActiveRecord::FinderMethods
    interceptor.declare_target(fm, :exists?, returns: lambda do |receiver, args, name|
      vn  = "#{name}_exists"
      sym = symbool(vn, ct.seed_for(vn, false), note: ct.sql_for(receiver, args))
      val = sym.value
      sym.send(:record!, "(#{vn} == True)", "exists?", taken: val)
      val ? true : nil
    end)
    installed << "FinderMethods#exists? (PC at boundary)"

    warn "[slr] SearchLinksReportsProfilesTargets installed: #{installed.join(', ')}"
  end
end
