# frozen_string_literal: true
#
# Per-batch concolic targets — `contacts_aspects_blocks`.
#
# Installs AFTER ConcolicTargets.install!; `declare_target` uses define_method,
# so a later declaration REPLACES an earlier one (last-one-wins).
#
#   ConcolicTargets.install!(interceptor)              # shared generic AR mocks
#   ContactsAspectsBlocksTargets.install!(interceptor) # this file
#
# ---------------------------------------------------------------------------
# THE PROBLEM THIS FILE SOLVES: the Ruby truthiness gap at mock boundaries
# ---------------------------------------------------------------------------
# `src/TODO.txt`: a SymbolicBool is a truthy Ruby object, so `if x` on one
# always takes the true side and records nothing. Every mock in the shared file
# that returns a SymbolicBool for a predicate the app consumes in BARE
# truthiness position therefore (a) hides the branch and (b) pins the app to
# one side of it. In this batch that killed six branches (see REPORT.md).
#
# The fix is the pattern `symbolic_instance` already uses for `col?` predicate
# readers: the MOCK records the path condition itself and returns a value whose
# RUBY truthiness matches the symbolic value.
#
# ---------------------------------------------------------------------------
# WHY THE FALSE SIDE RETURNS `nil` AND NOT `false`
# ---------------------------------------------------------------------------
# `CallInterceptor#declare_target` (src/ruby_runtime/call_interceptor.rb:170-186)
# post-processes every mock result: TrueClass/FalseClass are fed through
# `to_symbolic`, which re-wraps them in a SymbolicBool. A mock literally CANNOT
# hand a concrete `false` back to the app through the body-skip path — it comes
# out as `SymbolicBool(false)`, which is truthy again. `nil` is the one falsey
# value `to_symbolic` passes through unchanged (symbolic_func.rb:151-155,
# "nil means absent — pass through").
#
# So each predicate below returns:
#   true  -> `true`  (re-wrapped as SymbolicBool(true): truthy, as intended)
#   false -> `nil`   (falsey, as intended)
#
# The PC is recorded inside the mock either way, so the branch is visible to
# the checker regardless of what the wrapper does afterwards. This is a
# runner/batch-local workaround for a `src/` gap, reported not patched: the
# clean fix is for the interceptor to pass a mock's explicit `false` through
# unwrapped (or for SymbolicBool to be falsey, which Ruby does not allow).
#
# ---------------------------------------------------------------------------
# "DOES THIS MOCK SWALLOW THE BRANCH IT GUARDS?" — checked for all four
# ---------------------------------------------------------------------------
# * User#mine?   real body is `self.id == target.user_id`. That compare CANNOT
#                record: the rig's current_user has a CONCRETE id (1), so
#                `1 == SymbolicInt` dispatches to Integer#== and returns false
#                silently — which is why the shared file hard-codes `true`.
#                The mock ADDS the branch that the real body cannot express.
# * persistence  real bodies are SQL (INSERT/UPDATE/DELETE + callbacks). No app
#                branch inside; the branch is at the CALL SITE (`if x.save`).
# * exists?/any?/empty?  real bodies are SQL. Same.
# * Base#delete  real body is SQL. Same.
# None of the four encloses the `if` that produces its own path condition.

module ContactsAspectsBlocksTargets
  module_function

  # Mint a seedable symbolic bool, RECORD ITS PATH CONDITION, and return a
  # value with matching Ruby truthiness (see header for why false -> nil).
  #
  # `vn` is the seed key, so run_dse.rb's flip_seed inverts the branch by
  # seeding {vn => true/false}: the recorded expr is exactly `(vn == True)`.
  def seedable_flag(vn, default, note, op)
    val = ConcolicTargets.seed_for(vn, default) ? true : false
    sym = symbool(vn, val, note: note)
    sym.send(:record!, "(#{vn} == True)", op, taken: val)
    val ? true : nil
  end

  # Ablation switch, used to MEASURE each mock's own contribution (REPORT.md
  # "per-mock attribution"): CAB_DISABLE_MOCKS=mine,persist,exists,delete,
  # blocks,castable_int skips those sections. Empty by default — a normal run
  # installs everything. Kept in the shipped file so the per-mock before/after
  # numbers in the report are reproducible.
  def disabled?(tag)
    (ENV["CAB_DISABLE_MOCKS"] || "").split(",").map(&:strip).include?(tag.to_s)
  end

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets
    me = self
    warn "[contacts_aspects_blocks] ABLATION: disabled=#{ENV['CAB_DISABLE_MOCKS']}" if ENV["CAB_DISABLE_MOCKS"].to_s != ""

    # =====================================================================
    # 1. User#mine? — seedable, PC-recording. REPLACES shared §X7b's `true`.
    #
    # aspect_memberships#destroy:
    #   raise Diaspora::NotMine unless current_user.mine?(aspect) &&
    #                                  current_user.mine?(contact)
    # §X7b hard-codes true so the NotMine -> 403 branch is unreachable BY
    # CONSTRUCTION. Default stays true, so the previously-explored subtree is
    # preserved exactly; the false side is now reachable by seeding.
    #
    # SQL-free leaf: `self.id == target.user_id`, no other declared target.
    # =====================================================================
    if defined?(User) && !disabled?(:mine)
      interceptor.declare_target(User, :mine?, returns: lambda do |_r, args, name|
        vn = "#{name}_mine"
        me.seedable_flag(vn, true, "User#mine? #{args.inspect}", "mine?")
      end)
    end

    # =====================================================================
    # 2. Instance persistence — seedable + PC-recording, and `delete` added.
    #
    # Shared concolic_targets.rb:504-510 returns
    #   symbool("#{name}_#{m}_ok", true, ...)
    # with a LITERAL true and no seed_for — the exact "permanently inert var"
    # anti-pattern the addendum warns about (DSE emits the flip, the mock
    # ignores it). Combined with the truthiness gap that made every
    # `if record.save` / `if success` branch dead in this batch.
    #
    # Two further fixes:
    #  a) `delete` joins the body-skip list. blocks#destroy does
    #     `if block&.delete` on a symbolic (allocated) Block, so the REAL AR
    #     delete ran — the `blocks.destroy.failure` branch was unreachable.
    #  b) the var name strips `!`/`?`. The shared name for `save!` was
    #     `..._save!_ok`, which is not a legal Z3/Python identifier: the engine
    #     logs "Failed to eval var decl" and run_dse.rb's operand parser
    #     rejects it, so it could never have been flipped even if seeded.
    #     The `name` prefix already encodes the method (SYM_RESULT_..._save__1),
    #     so stripping the bang collides with nothing.
    #
    # Defaults stay `true` -> previously-explored success subtrees replay
    # identically; only the failure sides are new.
    # =====================================================================
    base = ActiveRecord::Base
    persist_methods = %i[save save! update update! update_attribute touch destroy destroy!]
    persist_methods <<= :delete unless disabled?(:delete)
    persist_methods = [] if disabled?(:persist)
    persist_methods.each do |m|
      next unless base.instance_methods.include?(m) ||
                  base.private_instance_methods.include?(m) ||
                  base.protected_instance_methods.include?(m)
      interceptor.declare_target(base, m, returns: lambda do |receiver, args, name|
        vn = "#{name}_#{m.to_s.delete('!').delete('?')}_ok"
        me.seedable_flag(vn, true, "#{receiver.class.name}##{m} args=#{args.inspect}", m.to_s)
      end)
    end

    # =====================================================================
    # 3. Existence / emptiness — seedable + PC-recording. HIGHEST VALUE.
    #
    # `User#share_with` (app/models/user/connecting.rb:14) opens with
    #   return if blocks.where(person_id: person.id).exists?
    # The shared mock returns a SymbolicBool, which is truthy, so share_with
    # returned nil UNCONDITIONALLY: its whole body was dead, taking with it
    # aspect_memberships#create's entire success path and aspects#create's
    # share_with fallback (which then died with `NoMethodError:
    # aspect_memberships for nil` — a mock-induced error, not an app one).
    #
    # Seed defaults are IDENTICAL to the shared file's (exists? false, any?
    # true, none? false, one? true, many? false, empty? false), so nothing is
    # forced; the difference is that the value now steers Ruby control flow and
    # both sides are reachable.
    #
    # NullRelation short-circuit (same reasoning as photos/targets.rb §4): a
    # `.none` relation is DEFINED to be empty and issues no SQL, so returning
    # the concrete answer is a sound over-approximation rather than a hidden
    # query. Without it the symbolic answer sends the app into branches that
    # are unreachable in production.
    # =====================================================================
    fm       = ActiveRecord::FinderMethods
    rel      = ActiveRecord::Relation
    null_rel = defined?(ActiveRecord::NullRelation) ? ActiveRecord::NullRelation : nil

    {
      exists?: [fm,  false, false],
      any?:    [rel, true,  false],
      none?:   [rel, false, true],
      one?:    [rel, true,  false],
      many?:   [rel, false, false],
      empty?:  [rel, false, true],
    }.each do |m, (mod, seed, null_val)|
      next if disabled?(:exists)
      interceptor.declare_target(mod, m, returns: lambda do |receiver, args, name|
        next(null_val ? true : nil) if null_rel && receiver.is_a?(null_rel)
        vn = "#{name}_#{m.to_s.delete('?')}"
        me.seedable_flag(vn, seed, ct.sql_for(receiver, args), m.to_s)
      end)
    end

    # =====================================================================
    # 4. User#blocks -> real Relation (same override photos/targets.rb §3 makes,
    #    for the same reason, and it still cannot live in the shared file).
    #
    # Unblocking `exists?` (mock 3) made `User#share_with`'s body run for the
    # first time, which reaches `contact.valid?` -> Contact#not_blocked_user
    # (app/models/contact.rb:100):
    #     if receiving && user && user.blocks.where(person_id: person_id).exists?
    # Here `user` is `contact.user` — a symbolic User from the association, NOT
    # the rig's current_user (which the runner already gives a `blocks` ->
    # `Block.all` singleton). It therefore hits shared concolic_targets.rb:546,
    # which returns a length-only SymbolicList -> `NoMethodError: where` in
    # every run that got past exists? (113 of 400 in the first smoke run).
    #
    # `Block.all` routes the call into the declared FinderMethods/exists?
    # targets, so the query stays REAL. streams/posts need the SymbolicList
    # shape (they read it through Post.blocked_people), which is exactly why
    # this must be batch-local.
    # Caveat (as in photos): the association's `WHERE blocks.user_id = ?` scope
    # is dropped, so that query renders unscoped.
    # =====================================================================
    interceptor.declare_target(User, :blocks, returns: ->(_r, _a, _n) { Block.all }) unless disabled?(:blocks)

    # =====================================================================
    # 5. CastableSymbolicInt — give the VALUE the shape the app expects
    #    (subclass technique, same as photos/targets.rb §6).
    #
    # Second wall revealed by mock 3: with share_with's body alive,
    #     contacts.find_or_initialize_by(person_id: person.id)
    # builds a REAL Contact whose person_id attribute holds a SymbolicInt.
    # `contact.valid?` -> belongs_to(:person).foreign_key_present? ->
    # _read_attribute -> ActiveModel::Type::Integer#cast_value -> `value.to_i`
    # -> NotImplementedError (src/ruby_runtime/int.rb:30). 44 of 227 runs.
    #
    # The fix is NOT to mock the consumer (`valid?` holds the app's own
    # validation branches — mocking it would swallow them). It is to give the
    # int the shape AR needs: a SymbolicInt subclass that answers `to_i` with
    # its concrete value. All comparison/PC behaviour is inherited unchanged,
    # so tracking is preserved.
    #
    # `to_int` is deliberately left RAISING. int.rb's comment is right that
    # to_int is the implicit-coercion channel (Array#[], String#*); only the
    # explicit `to_i` that AR's type cast calls is opened.
    #
    # Wiring mirrors photos §6a: alias-wrap the shared module_function at
    # runtime (the shared FILE is untouched) and rewrite the integer columns
    # of every symbolic instance. `concolic_attrs` is the same Hash the
    # generated readers close over, so in-place replacement is enough.
    # =====================================================================
    unless defined?(CastableSymbolicInt) || disabled?(:castable_int)
      ::Object.const_set(:CastableSymbolicInt, Class.new(SymbolicInt) do
        def to_i
          value
        end
      end)
    end

    unless ConcolicTargets.respond_to?(:symbolic_instance_without_castable_ints) || disabled?(:castable_int)
      class << ConcolicTargets
        alias_method :symbolic_instance_without_castable_ints, :symbolic_instance
        def symbolic_instance(klass, base_name, sql)
          obj = symbolic_instance_without_castable_ints(klass, base_name, sql)
          return obj unless obj.respond_to?(:concolic_attrs)
          attrs = obj.concolic_attrs
          attrs.each do |col, v|
            next unless v.instance_of?(SymbolicInt)
            attrs[col] = CastableSymbolicInt.new(v.value, name: v.sym_name, note: v.note)
          end
          obj
        end
      end
    end

    warn "[contacts_aspects_blocks] ContactsAspectsBlocksTargets installed"
  end
end
