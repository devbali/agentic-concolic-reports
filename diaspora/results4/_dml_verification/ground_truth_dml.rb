# frozen_string_literal: true
#
# GROUND TRUTH for the aspect_memberships_create DML notes.
#
# Boots the REAL diaspora app with NO concolic interceptor installed, against a
# PRIVATE COPY of db/concolic.sqlite3, and records the statements ActiveRecord
# actually emits for the four writes `User#share_with` performs:
#
#   1. contact.save            -- NEW record  (find_or_initialize_by MISS arm)
#   2. contact.save            -- PERSISTED   (find_or_initialize_by HIT arm)
#   3. contact.aspects << a    -- join row
#   4. Notifications::StartedSharing.where(...).update_all(unread: false)
#   5. contact.destroy
#
# Nothing under src/, src_new/, the app, or the shared targets is touched.

require "./config/environment"
require "json"

DB = File.join(File.dirname(File.expand_path(__FILE__)), "gt.sqlite3")
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB, pool: 1)

$sql = []
ActiveSupport::Notifications.subscribe("sql.active_record") do |_n, _s, _f, _i, payload|
  next if payload[:name] =~ /SCHEMA|TRANSACTION/
  $sql << { name: payload[:name].to_s, sql: payload[:sql].to_s,
            binds: (payload[:binds] || []).map { |b| b.respond_to?(:value) ? b.value : b }.map(&:to_s) }
end

def phase(label)
  $sql = []
  yield
  puts "\n#### #{label}"
  $sql.each do |r|
    next unless r[:sql] =~ /\A\s*(INSERT|UPDATE|DELETE)\b/i
    puts "  DML  [#{r[:name]}] #{r[:sql]}"
    puts "       binds=#{r[:binds].inspect}" unless r[:binds].empty?
  end
  $sql.each do |r|
    next if r[:sql] =~ /\A\s*(INSERT|UPDATE|DELETE)\b/i
    puts "  sel  #{r[:sql][0, 200]}"
  end
rescue StandardError, NotImplementedError => e
  puts "\n#### #{label}  -- RAISED #{e.class}: #{e.message[0, 300]}"
  $sql.each { |r| puts "  ... #{r[:sql][0, 200]}" }
end

conn = ActiveRecord::Base.connection

# ---------------------------------------------------------------- fixtures
now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
conn.execute("DELETE FROM contacts"); conn.execute("DELETE FROM aspect_memberships")
conn.execute("DELETE FROM notifications"); conn.execute("DELETE FROM aspects")
conn.execute("DELETE FROM people WHERE 1=1"); conn.execute("DELETE FROM users WHERE 1=1")
conn.execute(<<~SQL)
  INSERT INTO users (id, username, email, encrypted_password, created_at, updated_at)
  VALUES (1, 'alice', 'a@example.com', 'x', '#{now}', '#{now}')
SQL
conn.execute(<<~SQL)
  INSERT INTO people (id, guid, diaspora_handle, serialized_public_key, owner_id, created_at, updated_at)
  VALUES (1, 'g-alice', 'alice@pod', 'k', 1, '#{now}', '#{now}')
SQL
conn.execute(<<~SQL)
  INSERT INTO people (id, guid, diaspora_handle, serialized_public_key, owner_id, created_at, updated_at)
  VALUES (2, 'g-bob', 'bob@otherpod', 'k', NULL, '#{now}', '#{now}')
SQL
conn.execute(<<~SQL)
  INSERT INTO aspects (id, name, user_id, created_at, updated_at)
  VALUES (7, 'Friends', 1, '#{now}', '#{now}')
SQL

user   = User.find(1)
person = Person.find(2)
aspect = Aspect.find(7)

puts "== ActiveRecord #{ActiveRecord::VERSION::STRING} / adapter #{conn.adapter_name} / RAILS_ENV=#{Rails.env}"
puts "== Contact.record_timestamps=#{Contact.record_timestamps} AspectMembership.record_timestamps=#{AspectMembership.record_timestamps}"

# ------------------------------------------------- 1. NEW contact -> INSERT
c_new = user.contacts.find_or_initialize_by(person_id: person.id)
puts "\n[state] new contact: new_record?=#{c_new.new_record?} persisted?=#{c_new.persisted?} " \
     "attributes_before_type_cast(non-nil)=#{c_new.attributes_before_type_cast.reject { |_k, v| v.nil? }.inspect}"
puts "[state] changed_attribute_names_to_save=#{c_new.changed_attribute_names_to_save.inspect}"
c_new.receiving = true
puts "[state] after receiving=true: before_type_cast=#{c_new.attributes_before_type_cast.reject { |_k, v| v.nil? }.inspect}"
phase("1. NEW Contact#save (find_or_initialize_by MISS arm)") { c_new.save }
puts "[state] saved id=#{c_new.id}"

# --------------------------------- 2. join row via has_many :through on a
#                                      PERSISTED contact -> INSERT
c = Contact.find(c_new.id)
phase("2. persisted contact.aspects << aspect (join row)") { c.aspects << aspect }

# ------------------------------- 3. PERSISTED contact save -> UPDATE
c2 = Contact.find(c_new.id)
c2.update_columns(receiving: false)
c2 = Contact.find(c_new.id)
puts "\n[state] persisted contact: new_record?=#{c2.new_record?} persisted?=#{c2.persisted?}"
c2.receiving = true
puts "[state] changes=#{c2.changes.inspect} changed_attribute_names_to_save=#{c2.changed_attribute_names_to_save.inspect}"
phase("3. PERSISTED Contact#save with receiving=true (HIT arm)") { c2.save }

# ------------------------------- 4. update_all on notifications
conn.execute(<<~SQL)
  INSERT INTO notifications (id, target_type, target_id, recipient_id, unread, created_at, updated_at, type)
  VALUES (1, 'Person', 2, 1, 1, '#{now}', '#{now}', 'Notifications::StartedSharing')
SQL
phase("4. Notifications::StartedSharing.where(recipient_id:, target:, unread: true).update_all(unread: false)") do
  Notifications::StartedSharing.where(recipient_id: user.id, target: person.id, unread: true)
                               .update_all(unread: false)
end

# ------------------------------- 5. destroy
c3 = Contact.find(c_new.id)
phase("5. Contact#destroy") { c3.destroy }

# ------------------------------- 6. new contact WITHOUT touching receiving,
#                                    to expose the DB-default column set
c4 = user.contacts.find_or_initialize_by(person_id: person.id)
puts "\n[state] fresh new contact before_type_cast=#{c4.attributes_before_type_cast.inspect}"
phase("6. NEW Contact#save, no attribute assigned beyond the finder key") { c4.save }

puts "\n== done"
