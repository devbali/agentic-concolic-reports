#!/usr/bin/env jruby
# frozen_string_literal: true
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
ActiveRecord::Base.establish_connection(:concolic)
CT = ConcolicTargets
def show(l); puts "--- #{l}"; begin; puts "    #{yield}"; rescue Exception => e; puts "    CRASH #{e.class}: #{e.message[0,140]}"; end; puts; end

sym_id = symint("SYM_USER_id", 7)

show("B-2  User#person has_one scope, owner id CONCRETE") do
  u = User.new; u.id = 7
  CT.render_relation_sql(u.association(:person).scope)
end
show("B-2  User#person has_one scope, owner id SYMBOLIC") do
  u = User.new
  u.instance_variable_set(:@attributes, u.instance_variable_get(:@attributes))
  u.define_singleton_method(:[]) { |k| k.to_s == "id" ? sym_id : super(k) }
  CT.render_relation_sql(u.association(:person).scope)
end
show("B-2  the same statement via Person.where(owner_id: <symbolic>)") do
  CT.render_relation_sql(Person.where(owner_id: sym_id))
end

$interceptor = CallInterceptor.instance
CT.install!($interceptor)
show("B-3  SymbolicList receiver (note carried through)") do
  src = "SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"author_id\" = $$(SYM_USER_id)"
  lst = symlist("SRC_LIST", 1, note: src)
  lst.singleton_class.include(ActsAsApi::Collection) rescue nil
  r = lst.as_api_response(:backbone)
  "note=#{r.note.inspect}"
end
show("B-3  fallback: receiver with no reachable source") do
  o = Object.new
  o.singleton_class.include(ActsAsApi::Collection)
  r = o.as_api_response(:backbone)
  "note=#{r.note.inspect}"
end
