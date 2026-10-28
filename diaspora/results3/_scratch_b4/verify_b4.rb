# B-4 verification: BEFORE (backup) crashes, AFTER (patched) renders a SELECT.
require "arel"

class StubConn
  def quote(v);              v.is_a?(String) ? "'#{v}'" : v.to_s; end
  def quote_table_name(n);   %("#{n}"); end
  def quote_column_name(n);  %("#{n}"); end
  def sanitize_as_sql_comment(c); c; end
  def schema_cache;          nil; end
end
class QAttr
  attr_reader :value_before_type_cast
  def initialize(v); @value_before_type_cast = v; end
end
class FakeSym < String                       # mirrors SymbolicString < String
  attr_reader :sym_name
  def initialize(v, n); super(v); @sym_name = n; end
end

def build_rel(conn)
  t = Arel::Table.new("posts")
  sm = t.project(Arel.star)
  # 1. a real bind  -> emits "?"
  sm.where(t[:root_guid].eq(Arel::Nodes::BindParam.new(
             QAttr.new(FakeSym.new("g-1", "SYM_POST_root_guid")))))
  # 2. STI type condition, exactly as ActiveRecord builds it -> Casted, inline
  sm.where(t[:type].in(["Reshare"]))
  # 3. a SYMBOLIC Casted (association scope with a symbolic owner key)
  sm.where(t[:author_id].eq(FakeSym.new("42", "SYM_PERSON_PO_id")))
  sm.take(1)
  rel = Object.new
  rel.define_singleton_method(:arel) { sm }
  rel.define_singleton_method(:connection) { conn }
  rel.define_singleton_method(:klass) { Struct.new(:name).new("Reshare") }
  rel
end

def load_helpers(mod_name, path)
  lines = File.readlines(path)
  a = lines.index { |l| l =~ /^  def render_relation_sql\(rel\)/ } + 1
  b = lines.index { |l| l =~ /^  def model_class\(receiver\)/ }
  # include the footer visitor class when present
  foot = lines.join[/^class ConcolicSymbolicToSql < Arel::Visitors::ToSql.*?\nend\n/m]
  m = Module.new
  Object.const_set(mod_name, m)
  eval(foot) if foot && !Object.const_defined?(:ConcolicSymbolicToSql)
  m.module_eval("module_function\n" + lines[(a - 1)...(b - 1)].join)
  m
end

DIR = "/home/dev/project/reports/diaspora"
After  = load_helpers(:After,  "#{DIR}/concolic_targets.rb")            # patched
Before = load_helpers(:Before, "#{DIR}/concolic_targets.rb.bak_pre_b4_20260915")

[["BEFORE (backup, pre-B-4)", Before], ["AFTER  (patched canonical)", After]].each do |label, m|
  rel = build_rel(StubConn.new)
  puts "--- #{label} ---"
  begin
    puts m.render_relation_sql(rel)
  rescue Exception => e
    puts "note stored -> #{("Reshare query (render_relation_sql failed: " \
                            "#{e.class}#{e.message[0, 40]}), args=").inspect}"
  end
  puts
end
