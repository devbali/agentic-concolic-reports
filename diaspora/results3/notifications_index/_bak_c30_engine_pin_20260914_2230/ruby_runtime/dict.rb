# frozen_string_literal: true

require_relative "base"
require_relative "int"

# SymbolicDict — symbolic wrapper around Ruby Hash for concolic testing.
#
# Only #empty?, #length, #size, and #any? are tracked symbolically.
# Everything else raises NotImplementedError.
#
# Common usage:
#   if result          # empty? → records (len(X) != 0)
#   if !result         # empty? → records (len(X) == 0)
#   if result.empty?   # empty? → records (len(X) == 0)

# Path condition expressions use the symbolic_len SymbolicInt so Z3
# can reason about "length > 0" vs "length == 0".

class SymbolicDict
  include SymbolicVar

  attr_reader :symbolic_len

  def initialize(items = {}, name: nil)
    @sym_name = name
    @items = items.to_h
    len_name = SymbolicVar.len_var_name(name)
    if len_name && defined?(SymbolicFunc) && SymbolicFunc.respond_to?(:register_var)
      # Register the length var so dumps declare it — otherwise
      # (len(X) != 0) PCs reference an undeclared var and the engine's
      # Z3 eval fails with "name not defined". (Mirrors SymbolicList.)
      SymbolicFunc.register_var(name: len_name, sort: "Int", value: @items.length)
    end
    @symbolic_len = SymbolicInt.new(@items.length, name: len_name)
  end

  # --- Length (not PC-recording by itself) ---

  def length
    @items.length
  end
  alias size length

  # --- Boolean context (records PC on length) ---

  # Canonical (len(X) != 0) expr, taken = non-empty — parity with Python
  # __bool__ for cross-runtime path-signature matching.
  def empty?
    result = @items.empty?
    expr = "(#{@symbolic_len} != 0)"
    record!(expr, "empty?", taken: !result)
    result
  end

  def any?
    result = !@items.empty?
    expr = "(#{@symbolic_len} != 0)"
    record!(expr, "any?", taken: result)
    result
  end

  # --- Ruby truthy/falsy protocol ---

  def !
    empty?
  end

  # --- Representation ---

  def to_s
    @sym_name || @items.to_s
  end

  def inspect
    if @sym_name
      "<SymDict #{@sym_name} = #{@items.inspect}>"
    else
      "<SymDict #{@items.inspect}>"
    end
  end

  # --- Everything else raises ---

  DICT_STUBS = %i[
    [] []= fetch key keys values items each_key each_value each_pair
    merge merge! update
    select select! reject reject!
    has_key? key? include? member?
    has_value? value?
    delete delete_if keep_if
    flatten invert compact compact!
    transform_keys transform_keys! transform_values transform_values!
    slice except
    to_a to_h to_hash
    assoc rassoc
    default default=
    compare_by_identity compare_by_identity?
  ].freeze

  DICT_STUBS.each do |m|
    define_method(m) do |*_args, **_kwargs, &_block|
      raise NotImplementedError,
            "SymbolicDict##{m} is not supported. " \
            "Only #empty?, #any?, #length, #size, and #! are tracked."
    end
  end
end

# Factory shortcut
def symdict(name, items = {})
  SymbolicDict.new(items, name: name)
end
