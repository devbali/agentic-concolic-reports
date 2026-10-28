# frozen_string_literal: true

require_relative "base"
require_relative "bool"

# Symbolic model instance — an instance of a REAL application class whose
# attributes are symbolic values.
#
# Per PLAN_symbolic_query_ops.md §4: query-op mocks return an instance of
# the actual model class, created via `allocate` (no initialize, no
# framework callbacks, no DB). Attribute readers return symbolic values,
# so the class's real behavior methods execute their actual bodies and
# branch on symbolic attrs → genuine path conditions from real app logic.
#
# Only the generic capability lives here (runtime). Framework-specific
# glue (deriving attrs from ActiveRecord's columns_hash, overriding
# []/read_attribute/_read_attribute) belongs in the harness.
#
# Usage:
#   post = make_symbolic_instance(Post, {
#     "id"     => symint("post_id", 1, note: sql),
#     "public" => symbool("post_public", false, note: sql),
#   })
#   post.is_a?(Post)   # => true
#   post.public        # => SymbolicBool
#   post.public?       # records PC, returns concrete bool (truthiness-safe)
#
# ⚠️ Predicate readers (`attr?`) for SymbolicBool attrs record the PC INSIDE
# the reader and return the CONCRETE boolean. Rationale: Rails app code uses
# them in bare-truthiness position (`unless post.public?`), which Ruby cannot
# intercept on a wrapper (src/TODO.txt). Recording at the reader boundary
# keeps the branch tracked while the app branches concretely + consistently.

module SymbolicInstance
  module_function

  # @param klass [Class]  the real application class
  # @param attrs [Hash{String=>SymbolicVar}]  fixed attribute list
  # @param strict [Boolean]  require all attr values to be symbolic
  # @param predicate_readers [Boolean]  define `attr?` for SymbolicBool attrs
  # @return [Object]  instance of klass with symbolic attribute readers
  def make(klass, attrs, strict: true, predicate_readers: true)
    if strict
      attrs.each do |k, v|
        unless v.is_a?(SymbolicVar)
          raise TypeError,
                "make_symbolic_instance: attr #{k.inspect} is not a symbolic " \
                "value (#{v.class}). Pass strict: false to allow concrete attrs."
        end
      end
    end

    obj = klass.allocate
    frozen_attrs = attrs.transform_keys(&:to_s)

    frozen_attrs.each do |name, sym|
      obj.define_singleton_method(name) { sym }

      next unless predicate_readers && sym.is_a?(SymbolicBool)
      obj.define_singleton_method("#{name}?") do
        val = sym.value
        sym.send(:record!, "(#{sym.sym_name || val} == True)", "#{name}?", taken: val)
        val
      end
    end

    obj.define_singleton_method(:concolic_attrs) { frozen_attrs }
    obj
  end
end

# Factory shortcut (mirrors py_runtime.make_symbolic_instance)
def make_symbolic_instance(klass, attrs, strict: true, predicate_readers: true)
  SymbolicInstance.make(klass, attrs, strict: strict, predicate_readers: predicate_readers)
end
