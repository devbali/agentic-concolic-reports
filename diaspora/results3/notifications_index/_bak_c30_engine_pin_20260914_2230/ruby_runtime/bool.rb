# frozen_string_literal: true

require_relative "base"

# SymbolicBool — a symbolic wrapper around a Ruby boolean.
#
# Includes SymbolicVar module. Stores a concrete true/false in @value.
# Records path conditions on ==, != and ! (logical negation).
#
# ⚠️ Ruby truthiness gap (see src/TODO.txt): bare `if sym_bool` cannot be
# intercepted — a SymbolicBool wrapping `false` is still a truthy Ruby
# object. Code under test must use explicit compares (`== true`, `!x`) for
# path conditions to be recorded. The Python mirror does not have this gap
# (`__bool__` is hookable).

class SymbolicBool
  include SymbolicVar

  attr_reader :value, :note

  # Z3 declaration sort — lets a named var self-register into the
  # current run when it records a PC (SymbolicVar#ensure_registered!).
  def z3_sort; "Bool"; end

  def initialize(value, name: nil, note: nil)
    @sym_name = name
    @value = !!value
    @note = note
  end

  def to_s
    @sym_name || @value.to_s
  end

  def inspect
    if @sym_name
      "<SymBool #{@sym_name} = #{@value}>"
    else
      "<SymBool #{@value}>"
    end
  end

  # --- Comparisons (record PCs) ---

  def ==(other)
    other_val = val_of(other)
    result = @value == other_val
    expr = "(#{lhs_str} == #{rhs_str(other)})"
    record!(expr, "==", taken: result)
    result
  end

  def !=(other)
    other_val = val_of(other)
    result = @value != other_val
    expr = "(#{lhs_str} != #{rhs_str(other)})"
    record!(expr, "!=", taken: result)
    result
  end

  # Logical negation — the one truthiness-adjacent hook Ruby allows.
  # Records the same canonical expr as Python's __bool__ — (x == True)
  # with taken = the underlying value — so path signatures match across
  # runtimes (semantically-equal-but-syntactically-different exprs would
  # break signature matching).
  def !
    expr = "(#{lhs_str} == True)"
    record!(expr, "!", taken: @value)
    !@value
  end

  # --- Hash key use ---
  #
  # NOTE (deliberate py asymmetry): Python's SymbolicBool defines __hash__
  # (hash of the concrete value), so hashing is allowed there. But Ruby's
  # eql? would be an untracked comparison — raise on eql?, keep hash.
  def hash
    @value.hash
  end

  def eql?(_other)
    raise NotImplementedError,
          "SymbolicBool#eql? is not supported (untracked comparison); use =="
  end

  private

  def val_of(obj)
    obj.is_a?(SymbolicBool) ? obj.value : obj
  end

  # Exprs live in the engine's Python/Z3 eval language — render booleans as
  # True/False (matching the py_runtime mirror), not Ruby's true/false.
  def z3_literal(val)
    case val
    when true then "True"
    when false then "False"
    else val.inspect
    end
  end

  def lhs_str
    @sym_name || z3_literal(@value)
  end

  def rhs_str(obj)
    if obj.is_a?(SymbolicVar) && obj.respond_to?(:sym_name) && obj.sym_name
      obj.sym_name
    else
      z3_literal(obj)
    end
  end
end

# Factory shortcut — registers the declared var (with optional note) so it
# is emitted in the RunDump's symbolic_results.
def symbool(name, value = false, note: nil)
  sym = SymbolicBool.new(value, name: name, note: note)
  SymbolicFunc.register_var(name: name, sort: "Bool", value: !!value, note: note) if defined?(SymbolicFunc)
  sym
end
