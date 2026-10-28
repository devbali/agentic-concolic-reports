#!/usr/bin/env jruby
# frozen_string_literal: true
# probe_after.rb — exercise B-4 / B-5 / B-3 against the PATCHED canonical
# concolic_targets.rb on the real diaspora Rails environment.
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
def show(label, &blk)
  puts "--- #{label}"
  begin
    puts "    #{blk.call}"
  rescue Exception => e
    puts "    CRASH #{e.class}: #{e.message[0, 120]}"
  end
  puts
end

sym_guid = symstr("SYM_POST_guid", "g-1")
sym_id   = symint("SYM_PERSON_PO_id", 7)

# --- B-4: the exact posts_show shape — an STI relation (Reshare) -----------
show("B-4  Reshare.where(root_guid: <symbolic>)  [STI => Casted]") do
  CT.render_relation_sql(Reshare.where(root_guid: sym_guid))
end
show("B-4  post.reshares  (has_many, CollectionProxy, STI)") do
  p = Post.new
  p.define_singleton_method(:guid) { "g-1" }
  CT.render_relation_sql(Reshare.where(root_guid: "g-1").where(author_id: sym_id))
end
show("B-4  non-STI control: Notification.where(recipient_id: <symbolic>)") do
  CT.render_relation_sql(Notification.where(recipient_id: sym_id))
end

# --- B-2 dependency: the User#person has_one association scope -------------
show("B-2  User#person has_one association scope") do
  u = User.new
  u.define_singleton_method(:id) { sym_id }
  CT.render_relation_sql(u.association(:person).scope)
end

# --- B-5: Calculations#ids -------------------------------------------------
$interceptor = CallInterceptor.instance
CT.install!($interceptor)
SymbolicFunc.save_and_clear_registered_vars
show("B-5  Mention.where(person_id: <symbolic>).ids") do
  rel = Mention.where(person_id: sym_id)
  lst = rel.ids
  vars = SymbolicFunc.save_and_clear_registered_vars
  out = ["list class=#{lst.class} sym_name=#{lst.sym_name.inspect}",
         "note=#{lst.note.inspect}"]
  vars.each { |v| out << "var #{v['name'].inspect} sort=#{v['sort']} note=#{(v['note'] || '')[0, 70].inspect}" }
  out << "as a bind -> #{CT.render_bind_value(lst)}"
  out.join("\n    ")
end

# --- B-3: as_api_response carries the source relation's note ---------------
SymbolicFunc.save_and_clear_registered_vars
show("B-3  Relation#as_api_response (source note carried?)") do
  rel = Post.where(author_id: sym_id)
  r = rel.as_api_response(:backbone)
  "note=#{r.note.inspect}"
end
SymbolicFunc.save_and_clear_registered_vars
show("B-3  Array-of-rows receiver (fallback path)") do
  r = [].as_api_response(:backbone) rescue nil
  r ? "note=#{r.note.inspect}" : "(no Array receiver available)"
end
