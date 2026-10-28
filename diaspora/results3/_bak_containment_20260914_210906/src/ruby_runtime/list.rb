# frozen_string_literal: true

require_relative "base"
require_relative "int"

# SymbolicList — a symbolic wrapper around a symbolic length plus ONE
# optional representative element.
#
# Per design (PLAN_symbolic_query_ops.md §5 + DESIGN_sampled_content_list.md
# §1–5 — Gate 1b): a SymbolicList models the "how many rows" dimension of a
# query result symbolically (unchanged) PLUS, when a `representative:` is
# supplied, holds a single representative element (typically a symbolic model
# instance). Element-ACCESS ops (first/last/[0]) return/use that one
# representative row; membership (include?/contains) is NOT implemented — see
# note below. Iteration (each/map/reject/select/find) STAYS
# unimplemented — iteration is handled by caller-wrapping at the mocked
# boundary, never executed against the list.
#
# Back-compat: a list with `representative: nil` behaves EXACTLY as before
# (every element/iteration op raises NotImplementedError).
#
# Tracked operations:
#   list.empty?   → records (SYM_LEN_X == 0) / negation
#   list.any?     → records (SYM_LEN_X != 0) / negation
#   !list         → same as empty?
#   list.length   → returns the SymbolicInt length (comparisons on it
#   list.size       record PCs; the length itself records nothing)
#   list.first / list.last / list[0] → @representative when set (else raise)
#
# ⚠️ Representative MUST be a symbolic value (SymbolicInt / SymbolicString /
#   a symbolic model instance). Element access returns that symbolic rep, so
#   `list[0] == "hello"` records a PC via the rep's own == (SymbolicString#==).
#   It must NOT be a plain concrete scalar — a concrete rep would make the
#   comparison silently concrete (no PC). The runtime never synthesizes a rep;
#   it only stores/yields whatever representative it is given.
#
# ❗ Membership (include?/contains) is NOT implemented in either runtime: there
#   is no Z3 path-condition support for set/similarity membership, so a
#   contains check can't be recorded as a sound PC. Use element access instead
#   (`list[0] == x` with a symbolic rep).
#
# Honest limits (state in reports — DESIGN §5): one rep row, not N distinct
# rows; distinct-row branching is NOT modeled; `list[i]` for i > 0 raises.
#
# ⚠️ Ruby truthiness gap (src/TODO.txt): bare `if list` is always truthy
# and records nothing. Use .empty? / .any? / explicit length compares.

class SymbolicList
  include SymbolicVar

  attr_reader :symbolic_len, :note, :representative

  # @param length [Integer] concrete seed for the symbolic length
  # @param name [String, nil] Z3-friendly base name; the length var is
  #   `SymbolicVar.len_var_name(name)` ("SYM_LEN_<name>" — see base.rb)
  # @param note [String, nil] human-facing context (e.g. SQL query) — dumped
  #   in run records, never part of Z3 names/exprs.
  # @param representative [Object, nil] optional single representative element
  #   (typically a symbolic model instance). When nil, element-ACCESS ops raise
  #   exactly as before (back-compat). The runtime stays generic — it merely
  #   stores and yields whatever representative it is given; it never
  #   synthesizes it or embeds task/SQL-specific behavior.
  def initialize(length = 0, name: nil, note: nil, representative: nil)
    @representative = representative
    # Back-compat: accept an Array seed and use only its length.
    length = length.length if length.respond_to?(:length) && !length.is_a?(Integer)
    @sym_name = name
    @note = note
    len_name = SymbolicVar.len_var_name(name)
    @concrete_length = Integer(length)
    @symbolic_len = if len_name
                      symint(len_name, @concrete_length, note: note)
                    else
                      SymbolicInt.new(@concrete_length, name: nil, note: note)
                    end
  end

  # Concrete length — for interceptor serialization only (to_native).
  # App-facing #length/#size return the SymbolicInt.
  def concrete_length
    @concrete_length
  end

  # --- Length (returns the symbolic length; recording happens on compares) ---

  def length
    @symbolic_len
  end
  alias size length

  # 0-arg count is Ruby's idiomatic size — symbolic length. With an
  # argument or block it means occurrence counting (contents are out of
  # scope) — raise, mirroring py's stubbed count(x).
  def count(*args, &block)
    if args.empty? && !block
      @symbolic_len
    else
      raise NotImplementedError,
            "SymbolicList#count with argument/block is not supported (contents out of scope)"
    end
  end

  # --- Element access (only with a representative; else back-compat raise) --
  #
  # DESIGN Gate 1b: with a rep these return/use the single representative row
  # (absence — "0 rows" — was already decided at the mock boundary before a
  # rep-carrying list is ever produced, so returning the rep here is safe).
  # Without a rep (default, back-compat) they raise exactly as before.

  def first(*args)
    if @representative && args.empty?
      @representative
    else
      raise NotImplementedError,
            "SymbolicList#first is not supported without a representative " \
            "or for a multi-element take (contents out of scope). " \
            "Supply representative: to a SymbolicList to read its first row."
    end
  end

  def last(*args)
    if @representative && args.empty?
      @representative
    else
      raise NotImplementedError,
            "SymbolicList#last is not supported without a representative " \
            "or for a multi-element take (contents out of scope). " \
            "Supply representative: to a SymbolicList to read its last row."
    end
  end

  # Index access. Only [0] is modeled (we hold one rep). [i] for i>0 raises
  # loudly (honesty §5.3) — a block that needs the second row crashes rather
  # than silently returning the wrong row. A range/slice arg raises too.
  def [](*args)
    if @representative && args.length == 1 && args[0] == 0
      @representative
    else
      raise NotImplementedError,
            "SymbolicList#[] only supports index 0 with a representative " \
            "(contents out of scope; a single rep row is modeled)."
    end
  end

  # Membership (contains) is NOT implemented by design: there is no Z3
  # path-condition support for set/similarity membership, so a contains check
  # cannot be recorded as a sound PC. Raise loudly rather than silently
  # concretize. The supported path is element access ([0]/first/last) which
  # returns the symbolic representative whose own == records a PC.
  def include?(_other)
    raise NotImplementedError,
          "SymbolicList#include? (contains) is not supported: membership has no " \
          "Z3 path-condition support. Use element access (list[0] == x) with a " \
          "symbolic representative instead."
  end

  # --- Boolean context (records PC on length) ---

  # Records the canonical (SYM_LEN_X != 0) expr with taken = non-empty —
  # same signature as Python's __bool__ — so cross-runtime path-signature
  # matching works (the dual "(len == 0) taken=false" form would not match).
  def empty?
    result = @concrete_length.zero?
    expr = "(#{@symbolic_len} != 0)"
    record!(expr, "empty?", taken: !result)
    result
  end

  def any?
    result = !@concrete_length.zero?
    expr = "(#{@symbolic_len} != 0)"
    record!(expr, "any?", taken: result)
    result
  end

  def none?
    empty?
  end

  # --- Ruby truthy/falsy protocol ---

  def !
    empty?
  end

  # --- Representation ---

  def to_s
    @sym_name || "<SymList len=#{@concrete_length}>"
  end

  def inspect
    if @sym_name
      "<SymList #{@sym_name} len=#{@concrete_length}>"
    else
      "<SymList len=#{@concrete_length}>"
    end
  end

  # --- Everything else raises (contents are out of scope by design) ---

  LIST_STUBS = %i[
    []= take drop each map select reject items
    index rindex find detect
    push << pop shift unshift insert delete delete_at clear
    compact flatten reverse sort uniq
    join split slice values_at
    pack combination permutation product
    zip transpose
    reduce inject
    all? one?
    grep grep_v
    chunk chunk_while slice_after slice_before slice_when
    cycle each_cons each_entry each_slice each_with_index each_with_object
    filter filter_map find_index flat_map group_by
    max max_by min min_by minmax minmax_by partition
    reverse_each sort_by sum tally to_a to_ary to_h to_set
  ].freeze

  LIST_STUBS.each do |m|
    define_method(m) do |*_args, **_kwargs, &_block|
      raise NotImplementedError,
            "SymbolicList##{m} is not supported (contents out of scope). " \
            "Only #empty?, #any?, #none?, #length/#size, #!, #first, #last, " \
            "#[] (element access with a symbolic representative) are tracked."
    end
  end
end

# Factory shortcut
# @param representative [Object, nil] optional single representative element
#   (Gate 1b) — passed through to SymbolicList.new; nil = back-compat.
def symlist(name, length = 0, note: nil, representative: nil)
  SymbolicList.new(length, name: name, note: note, representative: representative)
end
