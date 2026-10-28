# frozen_string_literal: true

require_relative "path_condition"

# SymbolicVar — base module for all symbolic variable types.
#
# Provides:
# - Static path condition stack (thread-safe via Mutex)
# - Caller frame detection for source-location tracking
# - A uniform #record! method that subclasses call from comparison methods
#
# In Ruby this is a **module** (not a class) because SymbolicInt subclasses
# Integer and SymbolicString subclasses String — Ruby is single-inheritance
# but supports module inclusion for shared behaviour.
#
# The PC stack lives on the module itself (class-level / module-level state).

module SymbolicVar
  # ----------------------------------------------------------
  # Skip these files when walking the stack for source location
  # ----------------------------------------------------------
  SKIP_FILES = [
    "path_condition.rb",
    "base.rb",
    "int.rb",
    "string.rb",
    "symbolic_func.rb",
    "call_interceptor.rb",
  ].freeze

  # ----------------------------------------------------------
  # Name minting — the ONE place a length variable is spelled
  # ----------------------------------------------------------
  #
  # A container's cardinality variable is named `len(X)`: what the runtime
  # genuinely means, what Z3 accepts verbatim (`Int('len(X)')` solves fine),
  # what JSON accepts, and what ~1,007,044 dumps on disk already carry.
  #
  # It is NOT a legal Python identifier, and that matters in exactly one
  # place: `concolic_engine/solver.py` transports Z3 terms as PYTHON SOURCE
  # which it `exec`/`eval`s. That constraint belongs to those few lines and
  # is CONTAINED there — solver.py sanitises any name that is not a legal
  # Python identifier on the way into the text and maps the model's keys
  # back on the way out, so every caller sees `len(X)` throughout. See
  # `concolic_engine.solver.to_py_identifier` and
  # reports/diaspora/docs/NAME_BOUNDARY_PLAN_20260914.md (§11).
  #
  # Mint through this helper rather than interpolating "len(#{name})" by
  # hand: a hand-rolled spelling that drifts produces a name the solver
  # reads as a DIFFERENT variable, and the resulting UNSAT is silent
  # (recorded: notifications_index/targets.rb, 2026-09-14).

  # Cardinality variable name for a container named `name` (nil when the
  # container is anonymous — an anonymous container has no Z3 identity).
  def self.len_var_name(name)
    s = name.to_s
    return nil if name.nil? || s.empty?
    "len(#{s})"
  end

  # ----------------------------------------------------------
  # Stack management
  # ----------------------------------------------------------

  @stack = []
  @mutex = Mutex.new

  class << self
    attr_reader :stack

    def push(pc)
      @mutex.synchronize { @stack << pc }
    end

    def get_path_conditions
      @mutex.synchronize { @stack.dup }
    end

    def clear_path_conditions
      @mutex.synchronize { @stack.clear }
    end

    # Snapshot the current path condition stack and reset it.
    # @return [Array<PathCondition>]
    def save_and_clear
      @mutex.synchronize do
        snapshot = @stack.dup
        @stack.clear
        snapshot
      end
    end
  end

  # ----------------------------------------------------------
  # Name accessor — set by subclasses in their constructors
  # ----------------------------------------------------------

  attr_reader :sym_name

  # ----------------------------------------------------------
  # Source-location helpers
  # ----------------------------------------------------------

  # Walk the stack to find the frame outside SymbolicVar internals.
  # @return [Array] [file, lineno, function]
  def caller_frame
    caller_locations.each do |loc|
      bn = File.basename(loc.path)
      unless SKIP_FILES.include?(bn) || loc.path.include?("ruby_runtime")
        return [loc.path, loc.lineno, loc.label]
      end
    end
    ["<unknown>", 0, "<unknown>"]
  end

  # Record a path condition for a comparison.
  # @param expr    [String]  Human-readable expression, e.g. "(x > 5)"
  # @param op_name [String]  Method name, e.g. ">", "=="
  # @param taken   [Boolean] Whether the comparison evaluated to true
  def record!(expr, op_name, taken:)
    loc = caller_frame
    pc = PathCondition.new(
      expr:    expr,
      op_name: op_name,
      frame:   loc,
      taken:   taken,
    )
    SymbolicVar.push(pc)
    ensure_registered!
  end

  # A named scalar var that records a PC belongs in the current run's
  # symbolic_vars, even if it was constructed before CallInterceptor#run's
  # reset! wiped the registration table (e.g. a symbolic request param
  # built just before the run). Scalar classes define #z3_sort; container
  # types don't and are skipped (their length vars register at creation).
  # Mirrors py_runtime's SymbolicVar._ensure_registered.
  def ensure_registered!
    return unless respond_to?(:sym_name) && sym_name
    return unless respond_to?(:z3_sort) && z3_sort
    val = if respond_to?(:value)
            value
          elsif is_a?(::String)
            ::String.new(self)
          elsif is_a?(::Integer)
            to_i
          end
    n = respond_to?(:note) ? note : nil
    SymbolicFunc.ensure_var_registered(name: sym_name, sort: z3_sort,
                                       value: val, note: n)
  rescue StandardError
    # registration is best-effort bookkeeping; never break a PC record
  end
end