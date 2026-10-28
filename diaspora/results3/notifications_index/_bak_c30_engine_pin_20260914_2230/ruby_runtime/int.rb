# frozen_string_literal: true

require_relative "base"

# SymbolicInt — a symbolic wrapper around Ruby Integer.
#
# Includes SymbolicVar module. Stores a concrete @value and delegates
# arithmetic to it (returning plain Integer). Comparisons record path
# conditions on the SymbolicVar stack.

class SymbolicInt
  include SymbolicVar

  attr_reader :value, :note

  # Z3 declaration sort — lets a named var self-register into the
  # current run when it records a PC (SymbolicVar#ensure_registered!).
  def z3_sort; "Int"; end

  def initialize(value, name: nil, note: nil)
    @sym_name = name
    # Unwrap symbolic seeds via .value (to_i raises on SymbolicInt now)
    @value = value.is_a?(SymbolicInt) ? value.value : Integer(value)
    @note = note
  end

  # --- Core numeric protocol ---
  #
  # to_i / to_int raise: py_runtime stubs __int__/__index__ the same way.
  # to_int in particular enables IMPLICIT coercion (Array#[] etc.) — a
  # silent-concretization channel. Internal code uses .value instead.

  def to_i
    raise NotImplementedError,
          "SymbolicInt#to_i is not supported in the concolic runtime (use .value internally)"
  end

  def to_int
    raise NotImplementedError,
          "SymbolicInt#to_int is not supported in the concolic runtime (use .value internally)"
  end

  def to_s
    @sym_name || @value.to_s
  end

  def inspect
    if @sym_name
      "<SymInt #{@sym_name} = #{@value}>"
    else
      "<SymInt #{@value}>"
    end
  end

  # --- Unsupported operations raise (strict parity with py_runtime) ---
  #
  # Arithmetic/bitwise/numeric methods previously delegated to the concrete
  # value, silently losing symbolic tracking. Python's SymbolicInt raises
  # NotImplementedError for these — mirror that: fail loudly, recorded in
  # the RunDump via the error key.
  [:+, :-, :*, :/, :%, :**, :&, :|, :^, :<<, :>>, :~@, :+@,
   :abs, :ceil, :floor, :round, :truncate, :div, :divmod, :modulo,
   :remainder, :gcd, :lcm, :to_f, :to_r, :bit_length, :size,
   :numerator, :denominator, :succ, :pred, :next, :ord, :chr,
   :times, :upto, :downto, :odd?, :even?, :integer?].each do |m|
    define_method(m) do |*_args, **_kwargs, &_block|
      raise NotImplementedError,
            "SymbolicInt##{m} is not supported in the concolic runtime"
    end
  end

  # --- Unary minus (sound symbolic negation) ---
  #
  # `-x` on a symbolic int yields a NEW SymbolicInt wrapping the negated
  # concrete value, with name "(- name)". This keeps symbolic tracking (does
  # NOT concretize): the negated expr `(- name)` is a valid Z3/Python unary
  # minus on an Int (z3.ArithRef supports Python `-`). Used e.g. by
  # Conversation#first_unread_message: messages.to_a[-visibility.unread].
  # Sound: the result feeds comparisons (== 0 -> records PC) or array
  # indexing without losing which symbolic value it derives from. Mirrors
  # py_runtime SymbolicInt.__neg__.
  def -@
    SymbolicInt.new(-@value, name: @sym_name ? "(- #{@sym_name})" : nil, note: @note)
  end

  # --- Comparisons (record PCs) ---

  def op_cmp(other, op_sym)
    result = @value.send(op_sym, val_of(other))
    rhs = rhs_str(other)
    expr = "(#{@sym_name || @value} #{op_sym} #{rhs})"
    record!(expr, op_sym.to_s, taken: result)
    result
  end

  def ==(other)
    op_cmp(other, :==)
  end

  def !=(other)
    op_cmp(other, :!=)
  end

  def <(other)
    op_cmp(other, :<)
  end

  def <=(other)
    op_cmp(other, :<=)
  end

  def >(other)
    op_cmp(other, :>)
  end

  def >=(other)
    op_cmp(other, :>=)
  end

  # The spaceship operator raises: "(x <=> 5)" is not a valid Z3/Python
  # expression (py_runtime has no counterpart — comparisons only). This
  # also makes sort/min/max on symbolic ints fail loudly.
  def <=>(_other)
    raise NotImplementedError,
          "SymbolicInt#<=> is not supported in the concolic runtime " \
          "(no Z3 counterpart; use explicit <, <=, >, >=)"
  end

  # --- Boolean context ---

  # Records the canonical (x != 0) expr with taken = non-zero — same
  # signature as Python's __bool__ — for cross-runtime path matching.
  def zero?
    result = @value.zero?
    record!("(#{@sym_name || @value} != 0)", "zero?", taken: !result)
    result
  end

  def nonzero?
    result = !@value.zero?
    record!("(#{@sym_name || @value} != 0)", "nonzero?", taken: result)
    # Ruby's Numeric#nonzero? returns self or nil; ours returns a plain
    # boolean — truthiness-equivalent.
    result
  end

  # --- Coercion for Ruby numeric protocol ---
  #
  # Raises: `1 + x` would otherwise silently concretize the symbolic value
  # (py_runtime stubs __radd__ etc. the same way).
  def coerce(_other)
    raise NotImplementedError,
          "SymbolicInt#coerce is not supported in the concolic runtime " \
          "(reflected arithmetic would lose symbolic tracking)"
  end

  # --- Hash key use ---
  #
  # TODO(risk): hash is concretized to @value.hash so SymbolicInts can be
  # used as Hash/Set/assoc keys without crashing (Arel's to_sql computes
  # BindParam#hash during a Set/Array minus while building the WHERE AST).
  # hash is a bucket function, not a branch, and eql? still raises — so no
  # untracked comparison can slip through (same-bucket collisions hit eql?
  # and fail loudly). UNTRACKED-USE RISK: if a symbolic value's hash lands in
  # a Set/Hash and later code BRANCHES on membership (set.include?(sym)),
  # that branch is decided only by the CONCRETE hash, so it will NOT be
  # recorded as a path condition. Arel's WHERE minus is pure bookkeeping (no
  # branch), but audit other call sites if a set-membership branch looks
  # missing. Mirrors SymbolicString#hash.
  def hash
    @value.hash
  end

  def eql?(_other)
    raise NotImplementedError,
          "SymbolicInt#eql? is not supported (untracked comparison); use =="
  end

  private

  def val_of(obj)
    obj.is_a?(SymbolicVar) && obj.respond_to?(:value) ? obj.value : obj
  end

  def rhs_str(obj)
    if obj.is_a?(SymbolicVar)
      # Named symbolic rhs → its name; unnamed → concrete value (never
      # render wrapper inspect strings into exprs). Mirrors py _cmp.
      obj.sym_name || val_of(obj).inspect
    else
      obj.inspect
    end
  end
end

# Factory shortcut. `note` is arbitrary human-facing context (e.g. the SQL
# query this var stands in for) — dumped in run records, never in Z3 exprs.
def symint(name, value = 0, note: nil)
  sym = SymbolicInt.new(value, name: name, note: note)
  if defined?(SymbolicFunc) && SymbolicFunc.respond_to?(:register_var)
    SymbolicFunc.register_var(name: name, sort: "Int", value: value.to_i, note: note)
  end
  sym
end