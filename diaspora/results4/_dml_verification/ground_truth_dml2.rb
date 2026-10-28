# frozen_string_literal: true
# GROUND TRUTH, part 2: destroy, `<<` on an UNSAVED contact, update/update_attribute/touch.
require "./config/environment"
DB = File.join(File.dirname(File.expand_path(__FILE__)), "gt2.sqlite3")
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB, pool: 1)
$sql = []
ActiveSupport::Notifications.subscribe("sql.active_record") do |_n, _s, _f, _i, p|
  next if p[:name] =~ /SCHEMA/
  $sql << [p[:name].to_s, p[:sql].to_s, (p[:binds] || []).map { |b| b.respond_to?(:value) ? b.value : b }.map(&:to_s)]
end
def phase(label)
  $sql = []
  r = yield
  puts "\n#### #{label}  => #{r.inspect[0, 80]}"
  $sql.each { |n, s, b| puts(s =~ /\A\s*(INSERT|UPDATE|DELETE)/i ? "  DML [#{n}] #{s}\n       binds=#{b.inspect}" : "  sel #{s[0, 160]}") }
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "\n#### #{label} -- RAISED #{e.class}: #{e.message[0, 200]}"
  $sql.each { |n, s, b| puts(s =~ /\A\s*(INSERT|UPDATE|DELETE)/i ? "  DML [#{n}] #{s}\n       binds=#{b.inspect}" : "  sel #{s[0, 160]}") }
end
conn = ActiveRecord::Base.connection
now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
%w[contacts aspect_memberships notifications aspects people users blocks].each { |t| conn.execute("DELETE FROM #{t}") rescue nil }
conn.execute("INSERT INTO users (id,username,email,encrypted_password,created_at,updated_at) VALUES (1,'alice','a@e.com','x','#{now}','#{now}')")
conn.execute("INSERT INTO people (id,guid,diaspora_handle,serialized_public_key,owner_id,created_at,updated_at) VALUES (1,'g1','alice@pod','k',1,'#{now}','#{now}')")
conn.execute("INSERT INTO people (id,guid,diaspora_handle,serialized_public_key,owner_id,created_at,updated_at) VALUES (2,'g2','bob@other','k',NULL,'#{now}','#{now}')")
conn.execute("INSERT INTO aspects (id,name,user_id,created_at,updated_at) VALUES (7,'Friends',1,'#{now}','#{now}')")
user = User.find(1); person = Person.find(2); aspect = Aspect.find(7)

# A. `contact.aspects << aspect` on an UNSAVED contact -- exactly share_with's order.
cu = user.contacts.find_or_initialize_by(person_id: person.id)
cu.receiving = true
phase("A. UNSAVED contact.aspects << aspect") { cu.aspects << aspect }
phase("A2. then contact.save (the real share_with order)") { cu.save }
puts "[state] contact id=#{cu.id}; aspect_memberships rows=#{AspectMembership.count}"

# B. destroy a contact with NO aspect memberships (avoids the Sidekiq/Redis before_destroy)
AspectMembership.delete_all
conn.execute("INSERT INTO notifications (id,target_type,target_id,recipient_id,unread,created_at,updated_at,type) VALUES (9,'Person',2,1,1,'#{now}','#{now}','Notifications::StartedSharing')")
cd = Contact.find(cu.id)
phase("B. Contact#destroy (no aspect memberships)") { cd.destroy }

# C. update / update_attribute / touch on a persisted contact
conn.execute("INSERT INTO contacts (id,user_id,person_id,created_at,updated_at,sharing,receiving) VALUES (50,1,2,'#{now}','#{now}',0,0)")
c = Contact.find(50); phase("C1. Contact#update(receiving: true)") { c.update(receiving: true) }
c = Contact.find(50); phase("C2. Contact#update_attribute(:sharing, true)") { c.update_attribute(:sharing, true) }
c = Contact.find(50); phase("C3. Contact#touch") { c.touch }
c = Contact.find(50); phase("C4. Contact#save with NO changes") { c.save }
puts "\n== done"
