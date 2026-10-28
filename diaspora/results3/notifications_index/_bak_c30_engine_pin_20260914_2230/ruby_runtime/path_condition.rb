# frozen_string_literal: true

# PathCondition — one recorded branch constraint from a symbolic execution.
#
# Instances are created automatically by SymbolicVar subclasses whenever a
# comparison operator is used. They are pushed onto a thread-safe class-level
# stack and retrieved by the call_interceptor after each run.
#
# @attr_reader expr     [String]  Human-readable expression, e.g. "(x > 10)"
# @attr_reader op_name  [String]  Ruby method name, e.g. :>, :==
# @attr_reader frame    [Array]   [file, lineno, function]
# @attr_reader taken    [Boolean] Whether the comparison evaluated to true

class PathCondition
  attr_reader :expr, :op_name, :frame, :taken

  def initialize(expr:, op_name:, frame:, taken: true)
    @expr    = expr
    @op_name = op_name.to_s
    @frame   = frame  # [file, lineno, function]
    @taken   = taken
  end

  # @return [String] "file:lineno in func()"
  def location
    fn, ln, func = @frame
    "#{fn}:#{ln} in #{func}()"
  end

  # @return [Hash] JSON-serializable dict for the RunDump IR.
  def to_dict
    {
      "expr"     => @expr,
      "op_name"  => @op_name,
      "file"     => @frame[0],
      "lineno"   => @frame[1],
      "function" => @frame[2],
      "taken"    => @taken,
    }
  end

  # Deserialize from a Hash (e.g. from JSON).
  # @param d [Hash]  Dict with "expr", "op_name", "file", "lineno", "function", "taken"
  # @return [PathCondition]
  def self.from_dict(d)
    new(
      expr:    d["expr"],
      op_name: d["op_name"],
      frame:   [d["file"], d["lineno"], d["function"]],
      taken:   d.fetch("taken", true),
    )
  end

  def to_s
    mark = @taken ? "✓" : "✗"
    "PathCondition(#{@expr.inspect} #{mark} @ #{location})"
  end

  def inspect
    to_s
  end
end