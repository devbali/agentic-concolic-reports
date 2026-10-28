# frozen_string_literal: true

require_relative "path_condition"
require_relative "base"
require_relative "int"
require_relative "string"

# symbolic_func — makes a method's return value symbolic.
#
# When a function is wrapped with #symbolic_func! or the CallInterceptor
# decorator, its return value becomes a SymbolicInt or SymbolicString.
# A SymbolicCallRecord is pushed onto a global call stack, recording
# the function name, arguments, result name, and source location.
#
# The CallInterceptor later consumes these records to emit
# "symbolic_call" events in the RunDump.

module SymbolicFunc
  @call_counter = {}
  @call_records = []
  @registered_vars = []
  @mutex = Mutex.new

  class << self
    attr_reader :call_records

    # Reset state for a new run
    def reset!
      @mutex.synchronize do
        @call_counter.clear
        @call_records.clear
        @registered_vars.clear
      end
    end

    # Register a declared symbolic variable (created by a factory inside a
    # mock / source function) so the interceptor can emit it in the RunDump's
    # symbolic_vars. `note` is arbitrary human-facing context (e.g. the SQL
    # query this var stands in for) — dumped, never part of Z3 names/exprs.
    def register_var(name:, sort:, value:, note: nil)
      v = { "name" => name, "sort" => sort, "value" => value }
      v["note"] = note if note
      @mutex.synchronize { @registered_vars << v }
    end

    # Register a declared var into the CURRENT run unless a var of that
    # name is already registered. Called from SymbolicVar#record! so any
    # named symbolic value that participates in this run (records a PC)
    # appears in this run's symbolic_vars — regardless of whether the
    # object was constructed before CallInterceptor#run (whose reset!
    # clears the per-run table) or during it. Mirrors py_runtime.
    def ensure_var_registered(name:, sort:, value:, note: nil)
      @mutex.synchronize do
        return if @registered_vars.any? { |v| v["name"] == name }
        v = { "name" => name, "sort" => sort, "value" => value }
        v["note"] = note if note
        @registered_vars << v
      end
    end

    def save_and_clear_registered_vars
      @mutex.synchronize do
        snapshot = @registered_vars.dup
        @registered_vars.clear
        snapshot
      end
    end

    # Snapshot and clear call records
    # @return [Array<SymbolicCallRecord>]
    def save_and_clear
      @mutex.synchronize do
        snapshot = @call_records.dup
        @call_records.clear
        snapshot
      end
    end

    def get_call_records
      @mutex.synchronize { @call_records.dup }
    end

    # Push a call record
    def push_record(record)
      @mutex.synchronize { @call_records << record }
    end

    # Next call index for a given function name
    # @param func_name [String]
    # @return [Integer]
    def next_call_idx(func_name)
      @mutex.synchronize do
        idx = (@call_counter[func_name] || 0) + 1
        @call_counter[func_name] = idx
        idx
      end
    end
  end
end

# ---------------------------------------------------------------------------
# SymbolicCallRecord
# ---------------------------------------------------------------------------

# @attr_reader target_name [String]
# @attr_reader args        [Hash<String, Object>]  concrete arg values
# @attr_reader result_name [String]   generated symbolic var name
# @attr_reader result_value [Object]  concrete return value
# @attr_reader result_sort [String]   "Int" or "String"
# @attr_reader source      [Array]    [file, lineno, function]
# @attr_reader note        [String, nil]  optional SQL/context note (same
#   semantics as SymbolicVar#note) — dumped on the symbolic_call event so the
#   query a mock stands in for is traceable from the dive events, not only from
#   the returned variables' notes.
class SymbolicCallRecord
  attr_reader :target_name, :args, :result_name, :result_value, :result_sort, :source, :note

  def initialize(target_name:, args:, result_name:, result_value:, result_sort:, source:, note: nil)
    @target_name  = target_name
    @args         = args
    @result_name  = result_name
    @result_value = result_value
    @result_sort  = result_sort
    @source       = source
    @note         = note
  end

  def to_dict
    d = {
      "target_name"  => @target_name,
      "args"         => @args,
      "result_name"  => @result_name,
      "result_value" => @result_value,
      "result_sort"  => @result_sort,
      "file"         => @source[0],
      "lineno"       => @source[1],
      "function"     => @source[2],
    }
    d["note"] = @note if @note
    d
  end

  def inspect
    "#<SymbolicCallRecord #{@target_name} -> #{@result_name}=#{@result_value}>"
  end
end

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def sort_of(value)
  case value
  when TrueClass, FalseClass then "Bool"
  when Integer then "Int"
  when String  then "String"
  when Float   then "Real"
  when Array   then "Int"   # len(result) tracked as Int
  when Hash    then "Int"   # len(result) tracked as Int
  else "Int"
  end
end

def to_symbolic(value, name:)
  case value
  when nil
    # nil means "absent" — pass through unchanged. Absence must be decided
    # (and PC-recorded) at the mock boundary, never silently converted
    # into a symbolic value. (Mirrors py _to_symbolic(None) → None.)
    nil
  when TrueClass, FalseClass
    require_relative "bool" unless Object.const_defined?(:SymbolicBool)
    SymbolicBool.new(value, name: name)
  when Integer
    SymbolicInt.new(value, name: name)
  when String
    SymbolicString.new(value, name: name)
  when Float
    SymbolicInt.new(value.to_i, name: name)
  when Array
    require_relative "list" unless Object.const_defined?(:SymbolicList)
    SymbolicList.new(value, name: name)
  when Hash
    require_relative "dict" unless Object.const_defined?(:SymbolicDict)
    SymbolicDict.new(value, name: name)
  else
    value
  end
end

def to_native(val)
  if val.is_a?(SymbolicInt)
    val.value
  elsif val.is_a?(SymbolicString)
    val.value
  elsif defined?(SymbolicBool) && val.is_a?(SymbolicBool)
    val.value
  elsif defined?(SymbolicList) && val.is_a?(SymbolicList)
    val.concrete_length
  elsif defined?(SymbolicDict) && val.is_a?(SymbolicDict)
    # private state access — #items is stubbed (mirrors py _to_native/_items)
    val.instance_variable_get(:@items).dup
  else
    val
  end
end

def caller_frame_skip(skip_list = [])
  caller_locations.each do |loc|
    bn = File.basename(loc.path)
    unless skip_list.include?(bn) || loc.path.include?("ruby_runtime")
      return [loc.path, loc.lineno, loc.label]
    end
  end
  ["<unknown>", 0, "<unknown>"]
end

# ---------------------------------------------------------------------------
# Wrap a method so its return value becomes symbolic
# ---------------------------------------------------------------------------

# Usage:
#   symbolic_func!(obj, :method_name)
#   symbolic_func!(klass, :method_name)  # for class methods
#
# After wrapping, calls to obj.method_name will:
# 1. Execute the original method
# 2. Record a SymbolicCallRecord
# 3. Return a SymbolicInt or SymbolicString
#
# @param target [Object|Class]
# @param method_name [Symbol]
def symbolic_func!(target, method_name)
  original = target.method(method_name)

  # Determine whether this is an instance method or singleton method
  if target.is_a?(Class) || target.is_a?(Module)
    # Class-level method
    target.define_singleton_method(method_name) do |*args, **kwargs, &block|
      concrete_args = original.parameters.each_with_index.each_with_object({}) do |((type, name), idx), h|
        val = args[idx]
        h[name.to_s] = to_native(val)
      end

      # Avoid the JRuby kwargs gotcha (empty **kwargs passed as spurious
      # trailing positional arg when target has no keyword params).
      result = if kwargs.empty?
                 original.call(*args, &block)
               else
                 original.call(*args, **kwargs, &block)
               end
      concrete = to_native(result)

      func_name = "#{target.name}.#{method_name}"
      idx = SymbolicFunc.next_call_idx(func_name)
      result_name = "SYM_RESULT_#{func_name}_#{idx}"

      src = caller_frame_skip(["symbolic_func.rb"])

      SymbolicFunc.push_record(
        SymbolicCallRecord.new(
          target_name:  func_name,
          args:         concrete_args,
          result_name:  result_name,
          result_value: concrete,
          result_sort:  sort_of(concrete),
          source:       src,
        )
      )

      to_symbolic(concrete, name: result_name)
    end
  else
    # Instance method
    target.define_singleton_method(method_name) do |*args, **kwargs, &block|
      concrete_args = original.parameters.each_with_index.each_with_object({}) do |((type, name), idx), h|
        val = args[idx]
        h[name.to_s] = to_native(val)
      end

      # Avoid the JRuby kwargs gotcha (empty **kwargs passed as spurious
      # trailing positional arg when target has no keyword params).
      result = if kwargs.empty?
                 original.call(*args, &block)
               else
                 original.call(*args, **kwargs, &block)
               end
      concrete = to_native(result)

      func_name = "#{target.class.name}##{method_name}"
      idx = SymbolicFunc.next_call_idx(func_name)
      result_name = "SYM_RESULT_#{func_name}_#{idx}"

      src = caller_frame_skip(["symbolic_func.rb"])

      SymbolicFunc.push_record(
        SymbolicCallRecord.new(
          target_name:  func_name,
          args:         concrete_args,
          result_name:  result_name,
          result_value: concrete,
          result_sort:  sort_of(concrete),
          source:       src,
        )
      )

      to_symbolic(concrete, name: result_name)
    end
  end
end