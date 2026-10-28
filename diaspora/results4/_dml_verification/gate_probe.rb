# frozen_string_literal: true
# (a) Does the INSERT-vs-UPDATE choice record a path condition?  MEASURED.
# (b) What note does the CORE-ONLY stack (all 161 candidate-tier endpoints)
#     give a real `record.save`?  MEASURED.
require "./config/environment"
%w[call_interceptor base int string bool list].each { |f| require "/home/dev/project/src_new/runtimes/ruby_runtime/#{f}" }
DB = File.join(File.dirname(File.expand_path(__FILE__)), "gt4.sqlite3")
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB, pool: 1)
conn = ActiveRecord::Base.connection
now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
%w[contacts people users aspects].each { |t| conn.execute("DELETE FROM #{t}") rescue nil }
conn.execute("INSERT INTO users (id,username,email,encrypted_password,created_at,updated_at) VALUES (1,'a','a@e','x','#{now}','#{now}')")
conn.execute("INSERT INTO people (id,guid,diaspora_handle,serialized_public_key,created_at,updated_at) VALUES (2,'g','b@o','k','#{now}','#{now}')")
conn.execute("INSERT INTO contacts (id,user_id,person_id,created_at,updated_at,sharing,receiving) VALUES (50,1,2,'#{now}','#{now}',0,0)")
PERSISTED = Contact.find(50)
NEWREC    = Contact.new(user_id: 1, person_id: 2)

MODE = ENV["MODE"] || "core"
require "/home/dev/project/reports/autolab/targets/core.rb"
require "/home/dev/project/reports/autolab/targets/endpoints/aspect_memberships_create.rb" if MODE == "override"
ic = CallInterceptor.instance
ConcolicTargets.install!(ic)
if MODE == "override"
  AspectMembershipsTargets.install!(ic)
  AmDeviseUserNaming.install!(ic) if defined?(AmDeviseUserNaming)
end

def pcs
  SymbolicVar.get_path_conditions
end
def show(label, rec, op = :save)
  before = pcs.size
  r = rec.public_send(op)
  after = pcs
  puts "\n#### #{label}"
  puts "   returned #{r.class} name=#{r.respond_to?(:sym_name) ? r.sym_name : '-'}"
  puts "   NOTE: #{r.respond_to?(:note) ? r.note : '(none)'}"
  puts "   path conditions added by this call: #{after.size - before}"
  after[before..-1].to_a.each { |p| puts "     PC #{p.inspect[0, 160]}" }
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "\n#### #{label} RAISED #{e.class}: #{e.message[0, 160]}"
end

puts "== MODE=#{MODE}  RAILS_ENV=#{Rails.env}"
SymbolicVar.clear_path_conditions
show("REAL new Contact#save  (should be INSERT)", NEWREC)
show("REAL persisted Contact#save (should be UPDATE)", (PERSISTED.receiving = true; PERSISTED))
si = ConcolicTargets.symbolic_instance(Contact, "gp_hit", %(SELECT "contacts".* FROM "contacts"))
si[:receiving] = true
show("symbolic_instance Contact#save (finder HIT arm)", si)
si2 = ConcolicTargets.symbolic_instance(Contact, "gp_touch", %(SELECT "contacts".* FROM "contacts"))
show("symbolic_instance Contact#touch", si2, :touch)
puts "\n== done"
