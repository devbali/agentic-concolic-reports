# B-4 reproduction: render_relation_sql crashes on Arel::Nodes::Casted (arel 9.0.0)
require "arel"

puts "arel #{Arel::VERSION}"
puts "Casted instance methods (own): #{Arel::Nodes::Casted.instance_methods(false).sort.inspect}"
puts "Casted responds to :value?  #{Arel::Nodes::Casted.method_defined?(:value)}"
puts "BindParam responds to :value? #{Arel::Nodes::BindParam.method_defined?(:value)}"
puts

# --- stub connection good enough for Arel::Visitors::ToSql -------------
class StubConn
  def quote(v);              v.is_a?(String) ? "'#{v}'" : v.to_s; end
  def quote_table_name(n);   %("#{n}"); end
  def quote_column_name(n);  %("#{n}"); end
  def sanitize_as_sql_comment(c); c; end
  def schema_cache;          nil; end
end

# --- a QueryAttribute-alike, as AR 5.2 puts inside a BindParam ---------
class QAttr
  attr_reader :value_before_type_cast
  def initialize(v); @value_before_type_cast = v; end
end

# --- a symbolic-looking value -----------------------------------------
class FakeSym
  attr_reader :sym_name
  def initialize(n); @sym_name = n; end
end

# --- the AST the Reshare query produces --------------------------------
# where(root_guid: <bind>)  -> BindParam        (emits "?")
# .where(table[:public].eq(true)) raw-Arel      -> Casted (inlined, NO "?")
table = Arel::Table.new("posts")
sm = table.project(Arel.star)
sm.where(table[:root_guid].eq(Arel::Nodes::BindParam.new(QAttr.new(FakeSym.new("SYM_POST_root_guid")))))
sm.where(table[:public].eq(true))          # -> Arel::Nodes::Casted
sm.take(1)

class Rel
  attr_reader :arel, :connection
  def initialize(arel, connection); @arel = arel; @connection = connection; end
  def klass; Struct.new(:name).new("Reshare"); end
end
rel = Rel.new(sm, StubConn.new)

# ---------------------------------------------------------------------
# Load the helper methods VERBATIM out of the live concolic_targets.rb
# ---------------------------------------------------------------------
SRC = "/home/dev/project/reports/diaspora/concolic_targets.rb"
lines = File.readlines(SRC)
def slice_methods(lines, from, to) lines[(from - 1)...to].join end

module Before; module_function; end
Before.instance_eval { }
Before.module_eval(slice_methods(lines, 221, 286).sub(/\A/, "module_function\n"))

puts "--- BEFORE (current live code) ---"
begin
  puts Before.render_relation_sql(rel)
rescue Exception => e
  klass = rel.klass.name
  note = "#{klass} query (render_relation_sql failed: #{e.class}#{e.message[0, 40]}), args="
  puts "CRASH: #{e.class}: #{e.message}"
  puts "backtrace: #{e.backtrace.first(3).join(' | ')}"
  puts "note stored -> #{note.inspect}"
end
