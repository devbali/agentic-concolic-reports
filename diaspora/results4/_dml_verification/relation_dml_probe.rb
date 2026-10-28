# frozen_string_literal: true
# What note does the CORE-ONLY stack give the RELATION-level writes
# (update_all / delete_all / destroy_all) and CollectionProxy#create?
# Compared against the statement the real ORM emits for the same relation.
require "./config/environment"
%w[call_interceptor base int string bool list].each { |f| require "/home/dev/project/src_new/runtimes/ruby_runtime/#{f}" }
DB = File.join(File.dirname(File.expand_path(__FILE__)), "gt5.sqlite3")
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB, pool: 1)
conn = ActiveRecord::Base.connection
now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
%w[contacts people users aspects notifications aspect_memberships].each { |t| conn.execute("DELETE FROM #{t}") rescue nil }
conn.execute("INSERT INTO users (id,username,email,encrypted_password,created_at,updated_at) VALUES (1,'a','a@e','x','#{now}','#{now}')")
conn.execute("INSERT INTO people (id,guid,diaspora_handle,serialized_public_key,created_at,updated_at) VALUES (2,'g','b@o','k','#{now}','#{now}')")
conn.execute("INSERT INTO contacts (id,user_id,person_id,created_at,updated_at,sharing,receiving) VALUES (50,1,2,'#{now}','#{now}',0,0)")
conn.execute("INSERT INTO notifications (id,target_type,target_id,recipient_id,unread,created_at,updated_at,type) VALUES (9,'Person',2,1,1,'#{now}','#{now}','Notifications::StartedSharing')")

# --- REAL statements first, before any mock is installed -------------------
$sql = []
ActiveSupport::Notifications.subscribe("sql.active_record") do |_n, _s, _f, _i, p|
  next if p[:name] =~ /SCHEMA/
  $sql << p[:sql].to_s
end
def real(label)
  $sql = []
  yield
  puts "\n[REAL] #{label}"
  $sql.each { |s| puts "   #{s}" if s =~ /\A\s*(INSERT|UPDATE|DELETE)/i }
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "\n[REAL] #{label} RAISED #{e.class}: #{e.message[0, 120]}"
  $sql.each { |s| puts "   #{s}" }
end
real("Notification.where(recipient_id: 1, unread: true).update_all(unread: false)") do
  Notification.where(recipient_id: 1, unread: true).update_all(unread: false)
end
conn.execute("INSERT INTO aspect_memberships (id,aspect_id,contact_id,created_at,updated_at) VALUES (3,7,50,'#{now}','#{now}')")
real("AspectMembership.where(contact_id: 50).delete_all") { AspectMembership.where(contact_id: 50).delete_all }

# --- now the MOCK notes ----------------------------------------------------
require "/home/dev/project/reports/autolab/targets/core.rb"
ic = CallInterceptor.instance
ConcolicTargets.install!(ic)
def noted(label)
  r = yield
  puts "\n[MOCK] #{label}"
  puts "   returned #{r.class}  NOTE: #{r.respond_to?(:note) ? r.note : '(none)'}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "\n[MOCK] #{label} RAISED #{e.class}: #{e.message[0, 160]}"
end
noted("Relation#update_all") { Notification.where(recipient_id: 1, unread: true).update_all(unread: false) }
noted("Relation#delete_all") { AspectMembership.where(contact_id: 50).delete_all }
noted("Relation#destroy_all") { AspectMembership.where(contact_id: 50).destroy_all }
c = Contact.find_by(id: 50) || Contact.new(id: 50)
noted("CollectionProxy#create (aspect_memberships.create)") { c.aspect_memberships.create(aspect_id: 7) }
puts "\n== done"
