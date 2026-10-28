# frozen_string_literal: true

require_relative "base"
require_relative "int"

# SymbolicString — a symbolic wrapper around Ruby String.
#
# Includes SymbolicVar module. Stores a concrete @value and delegates
# non-trackable methods to it. Only ==, !=, start_with?, end_with?,
# include?, and [] (slice) record path conditions.
#
# SymbolicSubstring — returned by [] on a SymbolicString. Records PCs
# referencing SubString(parent, start, len) for Z3.

# ---------------------------------------------------------------------------
# Helper for Z3 string literal encoding
# ---------------------------------------------------------------------------

# Render a string literal exactly like Python repr() (single quotes unless
# the string contains one) — path-signature matching compares expr strings
# across runtimes, so the two mirrors must render literals identically.
def py_repr_str(s)
  s = String(s)
  if s.include?("'") && !s.include?('"')
    s.inspect
  else
    escaped = s.gsub("\\", "\\\\\\\\").gsub("'", "\\\\'")
    "'#{escaped}'"
  end
end

def z3_str_val(s)
  "StringVal(#{py_repr_str(s)})"
end

# ---------------------------------------------------------------------------
# SymbolicString
# ---------------------------------------------------------------------------

# SymbolicString is a real String subclass (mirrors py_runtime's
# SymbolicString(str, ...)). The underlying String buffer holds the concrete
# bytes; @value is a native mirror so every internal concrete read (==, [],
# z3_expr, length, split, ...) keeps working without dispatching through our
# overrides. to_s/to_str return SELF (identity): since the object IS a String,
# coercion/interpolation keeps the symbolic value instead of silently
# concretizing. Unsupported native String methods still raise via the explicit
# UNSUPPORTED stub list below (defining a String subclass makes method_missing
# never fire for inherited methods, so a blanket catch-all is impossible).
class SymbolicString < String
  include SymbolicVar

  attr_reader :value, :note

  # Z3 declaration sort — lets a named var self-register into the
  # current run when it records a PC (SymbolicVar#ensure_registered!).
  def z3_sort; "String"; end

  def initialize(value, name: nil, note: nil)
    @sym_name = name
    # Unwrap symbolic seeds via .value; call super so the real String bytes
    # are populated (a String subclass whose to_s returns self is only
    # meaningful if the underlying buffer holds the value).
    concrete = value.is_a?(SymbolicString) ? value.value : String(value)
    super(concrete)
    @value = concrete
    @note = note
  end

  # to_s / to_str are IDENTITY: str(s) / interpolation / implicit coercion
  # return the symbolic string itself (tracking stays alive). Mirrors
  # py_runtime __str__ returning self. Note this is NOT cosmetic — native
  # String#to_s/to_str do not return the receiver here, so these overrides are
  # required to avoid concretizing. Internal code uses .value, never .to_s.
  def to_s
    self
  end

  def to_str
    self
  end

  def inspect
    if @sym_name
      "<SymStr #{@sym_name} = #{@value.inspect}>"
    else
      "<SymStr #{@value.inspect}>"
    end
  end

  # --- Z3 expression for this string ---

  def z3_expr
    # Unnamed strings render via Python-repr quoting (mirror of py
    # _z3_expr's repr() fallback) for cross-runtime expr parity.
    @sym_name || py_repr_str(@value)
  end

  # --- Comparisons ---

  # Type-mismatched compares raise: Z3 rejects mixed-sort constraints, and
  # coercing via to_s would record a type-confused PC (mirrors py __eq__).
  def ==(other)
    check_string_operand!(other, "==")
    result = @value == val_of(other)
    rhs = other.is_a?(SymbolicVar) && other.respond_to?(:z3_expr) ? other.z3_expr : z3_str_val(val_of(other))
    expr = "(#{z3_expr} == #{rhs})"
    record!(expr, "==", taken: result)
    result
  end

  def !=(other)
    check_string_operand!(other, "!=")
    result = @value != val_of(other)
    rhs = other.is_a?(SymbolicVar) && other.respond_to?(:z3_expr) ? other.z3_expr : z3_str_val(val_of(other))
    expr = "(#{z3_expr} != #{rhs})"
    record!(expr, "!=", taken: result)
    result
  end

  # --- start_with? ---

  def start_with?(*prefixes)
    raise NotImplementedError, "SymbolicString#start_with? only supports one prefix" if prefixes.size != 1
    prefix = prefixes.first
    result = @value.start_with?(val_of(prefix))
    rhs = prefix.is_a?(SymbolicVar) && prefix.respond_to?(:z3_expr) ? prefix.z3_expr : z3_str_val(val_of(prefix))
    expr = "PrefixOf(#{rhs}, #{z3_expr})"
    record!(expr, "start_with?", taken: result)
    result
  end

  # --- end_with? ---

  def end_with?(*suffixes)
    raise NotImplementedError, "SymbolicString#end_with? only supports one suffix" if suffixes.size != 1
    suffix = suffixes.first
    result = @value.end_with?(val_of(suffix))
    rhs = suffix.is_a?(SymbolicVar) && suffix.respond_to?(:z3_expr) ? suffix.z3_expr : z3_str_val(val_of(suffix))
    expr = "SuffixOf(#{rhs}, #{z3_expr})"
    record!(expr, "end_with?", taken: result)
    result
  end

  # --- include? (the Ruby "contains" check) ---

  def include?(substr)
    result = @value.include?(val_of(substr))
    rhs = substr.is_a?(SymbolicVar) && substr.respond_to?(:z3_expr) ? substr.z3_expr : z3_str_val(val_of(substr))
    expr = "Contains(#{rhs}, #{z3_expr})"
    record!(expr, "include?", taken: result)
    result
  end

  # --- Slice / substring ---

  def [](*args)
    native = @value[*args]
    if args.size == 2
      # str[start, length]
      start = args[0].to_i
      length = args[1].to_i
      SymbolicSubstring.new(native, parent_expr: z3_expr, start: start, length: length)
    elsif args.size == 1 && args[0].is_a?(Range)
      # str[0..3], str[0...3], or endless str[7..]
      r = args[0]
      b = r.begin || 0
      raise NotImplementedError, "negative range begin" if b < 0
      if r.end.nil?
        # Endless range → open-ended substring (py: s[7:] → length -1)
        SymbolicSubstring.new(native, parent_expr: z3_expr, start: b, length: -1)
      else
        e = r.exclude_end? ? r.end : r.end + 1
        length = e - b
        SymbolicSubstring.new(native, parent_expr: z3_expr, start: b, length: length)
      end
    else
      # single index
      idx = args[0].to_i
      raise NotImplementedError, "negative index" if idx < 0
      SymbolicSubstring.new(native, parent_expr: z3_expr, start: idx, length: 1)
    end
  end

  # slice is an alias of [] on String; route it through our override so
  # s.slice(...) returns a SymbolicSubstring instead of native String#slice
  # (which would return a plain String and concretize).
  alias slice []

  # --- length ---

  # --- Length (symbolic) ---
  #
  # Returns a SymbolicInt named Length(<z3_expr>) so comparisons on it
  # record PCs the solver can reason about (Z3's Length function is in the
  # engine's eval namespace, applied to the already-declared string var).
  # SymbolicSubstring overrides this: substrings are constructed with a
  # concrete length, so their length IS concrete.
  def length
    SymbolicInt.new(@value.length, name: "Length(#{z3_expr})")
  end

  def size
    length
  end

  # --- empty? ---
  #
  # Records the canonical (s == '') expr with taken = current emptiness,
  # same theory as ==/start_with? already opted into. The concrete result is
  # returned so app/helper/view branches fire correctly. Mirrors list.rb's
  # empty? and the Python string truthiness semantics (bool(s) == not empty).
  def empty?
    result = @value.empty?
    expr = "(#{z3_expr} == '')"
    record!(expr, "empty?", taken: result)
    result
  end

  # --- split (symbolic; mirrors py_runtime) ---
  #
  # Returns a lazy accessor. When indexed (parts[0], parts[1]), records
  # Contains and IndexOf on the parent string as PCs so the solver can
  # find values for the split elements.
  #
  # Only supports: explicit single-character separator, strings with at
  # most one separator occurrence (2 split parts). Everything else raises.
  def split(sep = nil, limit = nil)
    if sep.nil?
      raise NotImplementedError, "SymbolicString#split without separator not supported"
    end
    unless limit.nil?
      raise NotImplementedError, "SymbolicString#split with limit not supported"
    end
    if sep.to_s.length != 1
      raise NotImplementedError, "SymbolicString#split only supports single-character separators"
    end

    sep = sep.to_s
    concrete = @value
    concrete_parts = concrete.split(sep, -1)

    if concrete_parts.length > 2
      raise NotImplementedError,
            "SymbolicString#split only supports strings with at most one separator " \
            "(got #{concrete_parts.length - 1} separators)"
    end

    SplitAccessor.new(self, sep, concrete, concrete_parts)
  end

  # Lazy split-result accessor (mirror of py_runtime's _SplitAccessor).
  class SplitAccessor
    def initialize(parent, sep, concrete, concrete_parts)
      @parent = parent
      @sep = sep
      @concrete = concrete
      @concrete_parts = concrete_parts
    end

    def [](idx)
      if idx.negative?
        raise NotImplementedError, "split result negative index not supported"
      end
      if idx >= @concrete_parts.length
        raise IndexError,
              "split result index #{idx} out of range (len=#{@concrete_parts.length})"
      end

      sep_expr = z3_str_val(@sep)
      sep_len = @sep.length
      abs_offset = 0

      idx.times do |i|
        pos = @concrete.index(@sep, abs_offset)
        if pos.nil?
          raise IndexError, "split result index #{idx} out of range at step #{i}"
        end
        suffix = suffix_expr(abs_offset)
        @parent.send(:record!, "Contains(#{sep_expr}, #{suffix})", "split_contains", taken: true)
        @parent.send(:record!, "IndexOf(#{suffix}, #{sep_expr}) == #{pos - abs_offset}", "split_indexof", taken: true)
        abs_offset = pos + sep_len
      end

      next_sep = @concrete.index(@sep, abs_offset)
      suffix = suffix_expr(abs_offset)

      if next_sep.nil?
        @parent.send(:record!, "Not(Contains(#{sep_expr}, #{suffix}))", "split_no_more", taken: true)
        SymbolicSubstring.new(
          @concrete_parts[idx],
          parent_expr: @parent.z3_expr, start: abs_offset, length: -1
        )
      else
        local_pos = next_sep - abs_offset
        @parent.send(:record!, "Contains(#{sep_expr}, #{suffix})", "split_contains", taken: true)
        @parent.send(:record!, "IndexOf(#{suffix}, #{sep_expr}) == #{local_pos}", "split_indexof", taken: true)
        SymbolicSubstring.new(
          @concrete_parts[idx],
          parent_expr: @parent.z3_expr, start: abs_offset, length: local_pos
        )
      end
    end

    private

    def suffix_expr(offset)
      return @parent.z3_expr if offset.zero?
      "SubString(#{@parent.z3_expr}, #{offset}, Length(#{@parent.z3_expr}) - #{offset})"
    end
  end

  # --- Everything else raises (strict parity with py_runtime) ---
  #
  # Previously delegated to the concrete string via method_missing — that
  # silently concretized values (a run could lose tracking with no error).
  # Now: any String method not explicitly supported raises the standard
  # unimplemented error, recorded loudly in the RunDump via the error key.

  # --- Everything else raises (strict parity with py_runtime) ---
  #
  # SymbolicString is a String subclass, so inherited native String methods
  # would silently concretize (return a plain String, losing tracking) with no
  # error. method_missing cannot intercept them (they exist on String), so we
  # explicitly stub every unsupported method to raise — mirroring
  # py_runtime string_.py `_STR_STUBS`. This list is the complete set of
  # String methods that are NOT PC-tracked and MUST fail loudly.
  UNSUPPORTED = %i[
    # Mutation / concat / format (would mutate or produce a plain copy)
    + << concat prepend % * replace sub gsub sub! gsub! succ next reverse
    squeeze delete clear insert slice! strip! lstrip! rstrip! upcase!
    downcase! capitalize! swapcase! tr tr_s tr! tr_s! chomp chomp! chop
    chop! delete_prefix delete_suffix

    # Transformations (return new plain Strings)
    upcase downcase capitalize swapcase center ljust rjust strip lstrip rstrip

    # Search / scan
    index rindex count scan match match? =~ partition rpartition

    # Encoding / bytes
    encode encode! scrub force_encoding b unpack unpack1 getbyte setbyte
    byteslice

    # Iteration (yield/return concrete collections)
    each_line lines each_char chars each_byte bytes each_codepoint codepoints

    # Ordering (intentionally untracked — see module doc)
    < > <= >= <=> casecmp casecmp?

    # Ruby-internal numeric coercion
    to_i to_f to_r to_c

    # Predicate
    ascii_only?
  ].freeze

  UNSUPPORTED.each do |m|
    define_method(m) do |*_args, **_kwargs, &_block|
      raise NotImplementedError,
            "SymbolicString##{m} is not supported in the concolic runtime"
    end
  end

  # --- Hash key use ---
  #
  # TODO(risk): hash is concretized to @value.hash so SymbolicStrings can be
  # used as Hash/Set/assoc keys without crashing (Arel's to_sql does a Set/
  # Array minus that de-dupes on #hash). This is a bucket function, not a
  # branch, and eql? still raises — so no untracked comparison can slip
  # through (same-bucket collisions hit eql? and fail loudly). UNTRACKED-USE
  # RISK: if a symbolic value's hash lands in a Set/Hash and later code
  # B R A N C H E S on membership (set.include?(sym)), that branch is decided
  # only by the CONCRETE hash, so it will NOT be recorded as a path
  # condition. Arel's WHERE minus is pure bookkeeping (no branch), but other
  # call sites could in principle branch — audit them if a set-membership
  # branch looks missing. This mirrors int.rb#hash.
  def hash
    @value.hash
  end

  def eql?(_other)
    raise NotImplementedError,
          "SymbolicString#eql? is not supported (untracked comparison); use =="
  end

  private

  def check_string_operand!(other, op)
    return if other.is_a?(SymbolicString) || other.is_a?(String)
    raise NotImplementedError,
          "SymbolicString comparison (#{op}) with non-string (#{other.class}) is not supported"
  end

  def val_of(obj)
    obj.is_a?(SymbolicString) ? obj.value : String(obj)
  end
end

# ---------------------------------------------------------------------------
# SymbolicSubstring — a slice of a parent SymbolicString
# ---------------------------------------------------------------------------

class SymbolicSubstring < SymbolicString
  attr_reader :parent_expr, :start

  def initialize(value, parent_expr:, start:, length:)
    super(value, name: nil)
    @parent_expr = parent_expr
    @start      = start
    @sublength  = length  # length is a String method, avoid conflict
  end

  # Substrings are defined with a concrete length — return it concretely.
  def length
    @value.length
  end

  def size
    length
  end

  def z3_expr
    len_str = if @sublength < 0
                "Length(#{@parent_expr}) - #{@start}"
              else
                @sublength.to_s
              end
    "SubString(#{@parent_expr}, #{@start}, #{len_str})"
  end

  # slice aliases [] (as on String); route through our override so slicing a
  # substring keeps returning SymbolicSubstring, not a plain String.
  alias slice []

  # Further slicing chains through parent
  def [](*args)
    native = @value[*args]
    if args.size == 2
      abs_start = @start + args[0].to_i
      len = args[1].to_i
      SymbolicSubstring.new(native, parent_expr: @parent_expr, start: abs_start, length: len)
    elsif args.size == 1 && args[0].is_a?(Range)
      r = args[0]
      b = r.begin || 0
      e = r.exclude_end? ? r.end : r.end + 1
      abs_start = @start + b
      len = e - b
      SymbolicSubstring.new(native, parent_expr: @parent_expr, start: abs_start, length: len)
    else
      abs_idx = @start + args[0].to_i
      SymbolicSubstring.new(native, parent_expr: @parent_expr, start: abs_idx, length: 1)
    end
  end

  def inspect
    "<SymSubStr #{@parent_expr}[#{@start}:#{@sublength < 0 ? 'end' : @start + @sublength}] = #{@value.inspect}>"
  end
end

# Factory. `note` is arbitrary human-facing context (e.g. the SQL query this
# var stands in for) — dumped in run records, never in Z3 exprs.
def symstr(name, value = "", note: nil)
  sym = SymbolicString.new(value, name: name, note: note)
  if defined?(SymbolicFunc) && SymbolicFunc.respond_to?(:register_var)
    SymbolicFunc.register_var(name: name, sort: "String", value: value.to_s, note: note)
  end
  sym
end