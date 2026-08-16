# frozen_string_literal: true
#
# Per-batch concolic targets — `likes`.
#
# Installed AFTER `ConcolicTargets.install!` (declare_target uses define_method,
# so a later declaration replaces an earlier one — last-one-wins):
#
#   ConcolicTargets.install!(interceptor)   # shared generic AR interception
#   LikesTargets.install!(interceptor)      # this file — batch-local wall fixes
#
# The `likes` batch hit exactly three walls. Two are closed here, batch-locally,
# with NO change to src/ruby_runtime and no change to the shared targets file.
# The third is deliberately left open because it is a real app bug.
#
#   W-A  SymbolicInt#next     (3 dumps, likes_create) -> CLOSED (§1, subclass)
#   W-B  SymbolicInt#to_i     (1 dump,  likes_create) -> CLOSED (§2, cast passthrough)
#   W-C  NoMethodError post_id (1 dump, likes_create) -> genuine APP DEFECT, kept
#
# THE GOVERNING RULE (addendum): a wall mock that swallows the branch it guards
# is a regression, not a fix. Neither fix below mocks an app method at all —
# both make a VALUE carry the operation the app performs on it, which is the
# pattern that closes walls without closing branches.
#
# ENV switches (defaults = the delivered configuration):
#   LIKES_WA_FIX=0          disable §1
#   LIKES_WB_FIX=cast       §2 via ActiveModel::Type::Integer passthrough (default)
#   LIKES_WB_FIX=to_i       §2 via SuccIntValue#to_i  (measured alternative)
#   LIKES_WB_FIX=off        leave W-B open (reproduces the BEFORE run)

module LikesTargets
  module_function

  # =======================================================================
  # Symbolic-shaped VALUE objects — closing "the runtime is missing method X"
  # walls WITHOUT touching src/ruby_runtime.
  #
  # The runtime's symbolic classes are ordinary Ruby classes with public
  # readers (`SymbolicInt#value` / `#sym_name` / `#note`), so a missing method
  # is not a src/ blocker: a batch-local SUBCLASS adds it and batch-local
  # wiring hands that subclass to the app. Same pattern as photos §6.
  #
  # SuccIntValue is a SymbolicInt in every other respect — it inherits all the
  # comparison operators, so every path condition it takes part in is recorded
  # exactly as before, under the SAME var name (so DSE seeds still reach it).
  # =======================================================================
  def define_succ_int!
    return if defined?(::SuccIntValue)

    ::Object.const_set(:SuccIntValue, Class.new(SymbolicInt) do
      # `#next` / `#succ` — see §1. Semantics mirror SymbolicInt#-@
      # (src/ruby_runtime/int.rb:78), which already returns a sound symbolic
      # result rather than raising: the operand count is fixed, so there is no
      # second symbolic value to lose, and "(x + 1)" is a valid Z3 Int expr.
      def next
        SuccIntValue.new(value + 1,
                         name: (sym_name ? "(#{sym_name} + 1)" : nil), note: note)
      end
      alias_method :succ, :next

      def pred
        SuccIntValue.new(value - 1,
                         name: (sym_name ? "(#{sym_name} - 1)" : nil), note: note)
      end

      # `#to_i` — see §2, MEASURED ALTERNATIVE, off by default. Defining it
      # re-opens the implicit-concretization channel that int.rb:29 closes on
      # purpose, so it is only installed when LIKES_WB_FIX=to_i.
      def self.enable_to_i!
        define_method(:to_i) { value }
      end
    end)
  end

  # Batch-local WRAPPER around the shared `symbolic_instance` — the shared file
  # itself is untouched. After the generic build, every integer/bigint column
  # var is re-wrapped as a SuccIntValue carrying the SAME name, value and note.
  #
  # This is the wiring that matters for W-A: `symbolic_instance` installs a
  # SINGLETON reader per column (concolic_targets.rb:229), which shadows every
  # class-level method, so `participation.count` never reaches the
  # `ActiveRecord::Calculations#count` target — it returns the column var
  # directly. Upgrading the var in `concolic_attrs` is therefore the only place
  # the value can be given a `#next`.
  #
  # `module_function` keeps TWO copies of the method (a private instance method
  # and a singleton method) and internal callers use the instance copy, so both
  # are replaced with the same wrapper.
  def install_symbolic_instance_wrapper!
    return if ConcolicTargets.respond_to?(:symbolic_instance_without_likes)

    orig = ConcolicTargets.method(:symbolic_instance)
    ConcolicTargets.define_singleton_method(:symbolic_instance_without_likes, &orig)

    wrapper = lambda do |klass, base_name, sql|
      obj = orig.call(klass, base_name, sql)
      LikesTargets.upgrade_int_attrs!(obj)
      obj
    end
    ConcolicTargets.define_singleton_method(:symbolic_instance, &wrapper)
    ConcolicTargets.send(:define_method, :symbolic_instance, &wrapper)
    ConcolicTargets.send(:private, :symbolic_instance)
  end

  # The column readers built by `symbolic_instance` close over the `attrs` hash
  # (`define_singleton_method(col) { attrs[col] }`), so replacing the entry in
  # `concolic_attrs` changes what the reader returns. Boolean predicate readers
  # capture their var separately and are not touched.
  def upgrade_int_attrs!(obj)
    return obj unless obj.respond_to?(:concolic_attrs)
    attrs = obj.concolic_attrs
    attrs.each do |col, v|
      next unless v.is_a?(SymbolicInt) && !v.is_a?(::SuccIntValue)
      attrs[col] = ::SuccIntValue.new(v.value, name: v.sym_name, note: v.note)
    end
    obj
  end

  def install!(interceptor = CallInterceptor.instance)
    ct = ConcolicTargets
    wa = ENV.fetch("LIKES_WA_FIX", "1") == "1"
    wb = ENV.fetch("LIKES_WB_FIX", "cast")

    define_succ_int! if wa || wb == "to_i"

    # =====================================================================
    # 1. W-A — SymbolicInt#next, via a successor-capable symbolic value.
    #
    # THE WALL (3 dumps in likes_create, on the deepest paths in the batch)
    #     src/ruby_runtime/int.rb:63           block in next -> NotImplementedError
    #     app/models/user/social_actions.rb:56 update_or_create_participation!
    #     app/models/user/social_actions.rb:16 block in like!
    #
    #     def update_or_create_participation!(target)
    #       return if target.author == person                          # branch 1
    #       participation = participations.find_by(target_id: target)  # SQL
    #       if participation.present?                                  # branch 2
    #         participation.update!(count: participation.count.next)   # <-- wall
    #       else
    #         participate!(target)
    #       end
    #     end
    #
    # WHY NO APP-METHOD MOCK IS LEGAL HERE
    #   * `update_or_create_participation!` is the smallest method enclosing the
    #     expression, but its body ISSUES SQL (`participations.find_by`) and
    #     calls another declared target — the README forbids mocking it — and it
    #     holds BOTH branches above, so mocking it would delete the coverage
    #     along with the wall (the addendum's exact regression).
    #   * `like!` / `Like::Generator#create!` are further out and issue more SQL.
    #   There is no SQL-free, branch-free leaf between the raise and the query.
    #
    # THE FIX IS ON THE VALUE, NOT THE METHOD. `participations.find_by(...)`
    # keeps running for real; its result is still a symbolic Participation with
    # the same seedable `..._count` var; that var simply now knows how to
    # produce its own successor. Nothing is mocked away, no branch is skipped,
    # and `if participation.present?` still records its PC on both sides.
    # =====================================================================
    if wa
      install_symbolic_instance_wrapper!

      # Relation-level `count` for completeness: when the receiver IS a relation
      # (not a symbolic record) the shared Calculations#count target fires
      # instead of a column reader. Same value semantics as the shared mock
      # (concolic_targets.rb:465) — same var name, same seed_for, so it stays
      # seedable — only the class changes.
      interceptor.declare_target(ActiveRecord::Calculations, :count,
                                 returns: lambda do |receiver, args, name|
        vn = "#{name}_count"
        ::SuccIntValue.new(ct.seed_for(vn, 1), name: vn, note: ct.sql_for(receiver, args))
      end)

      warn "[likes] W-A: SuccIntValue wired into symbolic_instance + Calculations#count"
    end

    # =====================================================================
    # 2. W-B — SymbolicInt#to_i inside ActiveModel's integer type cast.
    #
    # THE WALL (likes_create, json format)
    #     src/ruby_runtime/int.rb:30                     to_i -> NotImplementedError
    #     activemodel/type/integer.rb:47                 cast_value
    #     activemodel/attribute.rb:175                   type_cast
    #     activerecord/attribute_methods/read.rb:73      _read_attribute
    #     .../belongs_to_association.rb:106              foreign_key_present?
    #     acts_as_api/api_template.rb:119                process_value (t.add :author)
    #
    #   `like.author_id` holds a symbolic int (assigned from the symbolic
    #   current_user's person.id by Like::Generator). `like` is a REAL AR record
    #   — not a `symbolic_instance` — so it has no singleton `_read_attribute`
    #   and the value goes through AR's real type-cast path, where
    #   `ActiveModel::Type::Integer#cast_value` does `value.to_i`. The json
    #   branch of likes#create therefore dies before `render json:`.
    #
    # A declare_target MOCK OF cast_value IS IMPOSSIBLE (measured, not assumed):
    #   `declare_target` natively-converts arguments before the mock lambda sees
    #   them — `call_args[name.to_s] = to_native(val)` (call_interceptor.rb:123)
    #   and `to_native(SymbolicInt) -> Integer` (symbolic_func.rb:177) — so the
    #   lambda receives `{"value" => 1}` and cannot tell a symbolic value from a
    #   plain one. Worse, its return is re-wrapped as
    #   `to_symbolic(result, name: "SYM_RESULT_..._cast_value_<n>")`
    #   (call_interceptor.rb:181), so EVERY integer attribute read in the app
    #   would mint a fresh call-ordinal var that no `seed_for` ever reads — the
    #   inert-var anti-pattern — and would sever `like.author_id` from
    #   `SYM_PERSON_LKC_id`, the var this batch's only cross-var branch compares.
    #   That is the "expensive mock" this batch previously worried about; it is
    #   not merely expensive, it is unimplementable. Neither option below is one.
    #
    # OPTION "cast" (DEFAULT, DELIVERED) — teach the TYPE, not the value.
    #   A prepend shim on ActiveModel::Type::Integer returns a SymbolicInt
    #   unchanged and defers everything else to `super`. cast_value's contract is
    #   "coerce a raw attribute value to Integer"; a SymbolicInt IS an
    #   Int-sorted value, so returning it unchanged is strictly MORE faithful
    #   than `.to_i`, which concretizes. Real casting semantics (including
    #   true->1 / false->0) are untouched for every non-symbolic value.
    #   It emits no symbolic_call events, so it costs nothing in the dumps.
    #
    # OPTION "to_i" (MEASURED ALTERNATIVE, NOT DELIVERED) — teach the VALUE.
    #   `SuccIntValue#to_i -> value`. Cheaper to state, but it re-opens exactly
    #   the implicit-concretization channel int.rb:25-32 closes on purpose: the
    #   cast then returns a PLAIN Integer, so `like.author_id` is concretized on
    #   every read. Measured consequence (REPORT.md §W-B): the author association
    #   reload's SQL note degrades from the symbolic bind `$$(SYM_PERSON_LKC_id)`
    #   to a literal, losing the traceability the README's §4 requires — and any
    #   future branch on that attribute would go UNRECORDED instead of raising.
    #   A silent loss is worse than a loud one, so "cast" is the delivered fix.
    # =====================================================================
    case wb
    when "cast"
      mod = Module.new do
        # NB: `next` is rejected by JRuby inside a define_method body
        # ("Invalid next"), hence the plain if/else.
        define_method(:cast_value) do |value|
          if value.is_a?(SymbolicInt) then value else super(value) end
        end

        # Same one-line concretization on the from-database path
        # (integer.rb:23). Not on the observed traceback, same argument.
        define_method(:deserialize) do |value|
          if value.is_a?(SymbolicInt) then value else super(value) end
        end
      end
      ActiveModel::Type::Integer.prepend(mod)
      warn "[likes] W-B: ActiveModel::Type::Integer SymbolicInt passthrough installed"
    when "to_i"
      install_symbolic_instance_wrapper!
      ::SuccIntValue.enable_to_i!
      warn "[likes] W-B: SuccIntValue#to_i enabled (measurement alternative)"
    else
      warn "[likes] W-B: left OPEN (LIKES_WB_FIX=#{wb})"
    end

    # =====================================================================
    # 3. W-C — NoMethodError: post_id for #<Like>. DELIBERATELY NOT MOCKED.
    #
    #   app/controllers/likes_controller.rb:26
    #     format.mobile { redirect_to post_path(like.post_id) }
    #
    # This is a GENUINE LATENT APP DEFECT, not a framework wall:
    #   * db/schema.rb:178-190 — the `likes` table has `target_id` + `target_type`
    #     (polymorphic) and NO `post_id` column.
    #   * lib/diaspora/fields/target.rb declares `belongs_to :target, polymorphic:`
    #     and app/models/like.rb aliases only `parent` -> `target`.
    #   * grep over app/ and lib/ finds no `post_id` attribute, alias or method
    #     on Like anywhere.
    # So `like.post_id` reaches AR's method_missing and raises for EVERY like,
    # symbolic or real — the mobile-format branch of likes#create is dead code
    # that 500s in production. Concolic execution found it; adding a `post_id`
    # reader to Like would erase the finding and fake a passing branch.
    # Kept as a reported defect. See REPORT.md.
    # =====================================================================

    warn "[likes] LikesTargets installed"
  end
end
