# frozen_string_literal: true
#
# Executes the DML NOTE RENDERER itself (reports/autolab/targets/endpoints/
# aspect_memberships_create.rb `dml_note` / `record_is_new?` / `dml_attrs`)
# against receivers in each state the endpoint can present, and prints the
# note plus whether the INSERT/UPDATE choice recorded a path condition.
#
# Read-only w.r.t. src_new/, the app and the shared targets.

require "./config/environment"
require "/home/dev/project/src_new/runtimes/ruby_runtime/call_interceptor"
require "/home/dev/project/src_new/runtimes/ruby_runtime/base"
require "/home/dev/project/src_new/runtimes/ruby_runtime/int"
require "/home/dev/project/src_new/runtimes/ruby_runtime/string"
require "/home/dev/project/src_new/runtimes/ruby_runtime/bool"
require "/home/dev/project/src_new/runtimes/ruby_runtime/list"
require "json"

DB = File.join(File.dirname(File.expand_path(__FILE__)), "gt3.sqlite3")
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB, pool: 1)

conn = ActiveRecord::Base.connection
now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
%w[contacts aspect_memberships notifications aspects people users].each { |t| conn.execute("DELETE FROM #{t}") rescue nil }
conn.execute("INSERT INTO users (id,username,email,encrypted_password,created_at,updated_at) VALUES (1,'alice','a@e.com','x','#{now}','#{now}')")
conn.execute("INSERT INTO people (id,guid,diaspora_handle,serialized_public_key,owner_id,created_at,updated_at) VALUES (2,'g2','bob@o','k',NULL,'#{now}','#{now}')")
conn.execute("INSERT INTO aspects (id,name,user_id,created_at,updated_at) VALUES (7,'Friends',1,'#{now}','#{now}')")
conn.execute("INSERT INTO contacts (id,user_id,person_id,created_at,updated_at,sharing,receiving) VALUES (50,1,2,'#{now}','#{now}',0,0)")

REAL_PERSISTED = Contact.find(50)         # loaded BEFORE install!, real AR state
REAL_NEW       = Contact.new(user_id: 1, person_id: 2)

require "/home/dev/project/reports/autolab/targets/core.rb"
require "/home/dev/project/reports/autolab/targets/endpoints/aspect_memberships_create.rb"

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
AspectMembershipsTargets.install!($interceptor)
AmDeviseUserNaming.install!($interceptor) if defined?(AmDeviseUserNaming)

CT = ConcolicTargets
AMT = AspectMembershipsTargets

def pc_count
  h = $interceptor.instance_variable_get(:@path_condition) ||
      $interceptor.instance_variable_get(:@pc)
  h.respond_to?(:size) ? h.size : (h.respond_to?(:conditions) ? h.conditions.size : -1)
end

def probe(label, receiver, op = :save)
  before = pc_count
  note = AMT.dml_note(CT, receiver, op)
  after = pc_count
  puts format("\n%-58s", label)
  puts "   record_is_new? = #{AMT.record_is_new?(receiver).inspect}"
  puts "   PCs recorded while deciding+rendering = #{after - before}"
  puts "   NOTE: #{note}"
end

puts "== PathCondition accessor check: pc_count=#{pc_count.inspect}"

# --- 1. symbolic instance (finder HIT arm) with a written column -----------
si = CT.symbolic_instance(Contact, "probe_contact_hit",
                          %(SELECT "contacts".* FROM "contacts" WHERE "contacts"."user_id" = 1))
si[:receiving] = true
probe("1. symbolic_instance Contact, receiving:=true, #save", si, :save)

# --- 2. symbolic instance with NO written column ---------------------------
si2 = CT.symbolic_instance(Contact, "probe_contact_clean",
                           %(SELECT "contacts".* FROM "contacts"))
probe("2. symbolic_instance Contact, NO change, #save", si2, :save)

# --- 3. symbolic instance, #touch ------------------------------------------
si3 = CT.symbolic_instance(Contact, "probe_contact_touch",
                           %(SELECT "contacts".* FROM "contacts"))
probe("3. symbolic_instance Contact, #touch", si3, :touch)

# --- 4. REAL new AR record (find_or_initialize_by MISS arm) ----------------
REAL_NEW.receiving = true
probe("4. REAL new Contact(user_id,person_id), receiving:=true, #save", REAL_NEW, :save)
puts "   before_type_cast = #{REAL_NEW.attributes_before_type_cast.reject { |_k, v| v.nil? }.inspect}"
puts "   changed_attribute_names_to_save = #{REAL_NEW.changed_attribute_names_to_save.inspect}"

# --- 5. REAL persisted AR record -------------------------------------------
REAL_PERSISTED.receiving = true
probe("5. REAL persisted Contact#50, receiving:=true, #save", REAL_PERSISTED, :save)

# --- 6. REAL new join row (AspectMembership) -------------------------------
am = AspectMembership.new(aspect_id: 7, contact_id: 50)
probe("6. REAL new AspectMembership, #save!", am, :save!)
puts "   before_type_cast = #{am.attributes_before_type_cast.reject { |_k, v| v.nil? }.inspect}"

# --- 7. destroy note (the endpoint's own DELETE renderer, verbatim) --------
t = REAL_PERSISTED.class.table_name
pk = REAL_PERSISTED.class.primary_key
puts "\n7. destroy note for Contact#50:"
puts %(   DELETE FROM "#{t}" WHERE "#{t}"."#{pk}" = #{CT.render_arg_value(REAL_PERSISTED[pk])})

# --- 8. is `persisted?` on a symbolic instance symbolic or concrete? -------
puts "\n8. symbolic_instance(Contact).persisted? -> #{si.persisted?.inspect} (#{si.persisted?.class})"
puts "   symbolic_instance(Contact).new_record? -> #{si.new_record?.inspect} (#{si.new_record?.class})"
puts "   REAL_NEW.persisted? -> #{REAL_NEW.persisted?.inspect} (#{REAL_NEW.persisted?.class})"

puts "\n== done"
