# frozen_string_literal: true
#
# d7_probe.rb — executed before/after evidence for the two D7 declarations,
# which are not plain ActiveRecord operations and so are not covered by
# differential.rb's model x operation matrix.
#
#   D7a  ActiveRecord::Associations::CollectionProxy#create
#   D7b  PostService#mark_user_notifications
#
# REAL phase first (no mock installed, private DB copy, statements from
# `sql.active_record`), then the mock stack, so one process yields both sides.
#
# ENV: TARGETS_DIR (default: the live targets), OUT

require "./config/environment"
%w[call_interceptor base int string bool list].each do |f|
  require "/home/dev/project/src_new/runtimes/ruby_runtime/#{f}"
end
require "json"
require "fileutils"

HERE = File.dirname(File.expand_path(__FILE__))
TDIR = ENV["TARGETS_DIR"] || "/home/dev/project/reports/autolab/targets"
OUT  = ENV["OUT"] || File.join(HERE, "out", "d7_#{File.basename(TDIR)}.json")
FileUtils.mkdir_p(File.dirname(OUT))

DB = File.join(HERE, "out", "d7_#{Process.pid}.sqlite3")
FileUtils.cp(File.join(Rails.root, "db", "concolic.sqlite3"), DB)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB, pool: 1)
CONN = ActiveRecord::Base.connection

$sql = []
$cap = false
ActiveSupport::Notifications.subscribe("sql.active_record") do |_n, _s, _f, _i, p|
  next unless $cap
  next if p[:name].to_s =~ /SCHEMA/
  s = p[:sql].to_s
  next if s =~ /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|PRAGMA)/i
  $sql << s
end

def real(label)
  $sql = []
  $cap = true
  st = "ok"
  begin
    yield
  rescue Exception => e # rubocop:disable Lint/RescueException
    st = "raised #{e.class}: #{e.message[0, 140]}"
  ensure
    $cap = false
  end
  { "label" => label, "status" => st, "statements" => $sql.dup }
end

def mocked(label)
  before = SymbolicFunc.get_call_records.size
  st = "ok"
  r = nil
  begin
    r = yield
  rescue Exception => e # rubocop:disable Lint/RescueException
    st = "raised #{e.class}: #{e.message[0, 140]}"
  end
  notes = SymbolicFunc.get_call_records[before..-1].to_a.map do |rec|
    [rec.target_name.to_s, rec.note.to_s] if rec.respond_to?(:note) && rec.note
  end.compact
  n = (r.respond_to?(:note) && r.note) ? r.note.to_s : nil
  notes << ["(return value)", n] if n && notes.none? { |_t, x| x == n }
  { "label" => label, "status" => st, "notes" => notes }
end

now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
%w[contacts aspect_memberships aspects notifications people users posts mentions comments]
  .each { |t| CONN.execute("DELETE FROM #{t}") rescue nil }
CONN.execute("INSERT INTO users (id,username,email,encrypted_password,created_at,updated_at) VALUES (1,'a','a@e','x','#{now}','#{now}')")
CONN.execute("INSERT INTO people (id,guid,diaspora_handle,serialized_public_key,owner_id,created_at,updated_at) VALUES (1,'g1','a@pod','k',1,'#{now}','#{now}')")
CONN.execute("INSERT INTO people (id,guid,diaspora_handle,serialized_public_key,created_at,updated_at) VALUES (2,'g2','b@o','k','#{now}','#{now}')")
CONN.execute("INSERT INTO aspects (id,name,user_id,created_at,updated_at) VALUES (7,'F',1,'#{now}','#{now}')")
CONN.execute("INSERT INTO contacts (id,user_id,person_id,created_at,updated_at,sharing,receiving) VALUES (50,1,2,'#{now}','#{now}',0,0)")
CONN.execute("INSERT INTO people (id,guid,diaspora_handle,serialized_public_key,created_at,updated_at) VALUES (3,'g3','c@o','k','#{now}','#{now}')")
CONN.execute("INSERT INTO contacts (id,user_id,person_id,created_at,updated_at,sharing,receiving) VALUES (51,1,3,'#{now}','#{now}',0,0)")
CONN.execute("INSERT INTO posts (id,author_id,public,guid,type,created_at,updated_at) VALUES (99,1,1,'pg','StatusMessage','#{now}','#{now}')")
CONN.execute("INSERT INTO notifications (id,target_type,target_id,recipient_id,unread,created_at,updated_at,type) VALUES (5,'Post',99,1,1,'#{now}','#{now}','Notifications::CommentOnPost')")

RES = { "targets_dir" => TDIR, "rails_env" => Rails.env.to_s, "real" => [], "mock" => [] }

# ---- REAL --------------------------------------------------------------
c_real = Contact.find(50)
RES["real"] << real("D7a CollectionProxy#create — contact.aspect_memberships.create(aspect_id: 7)") do
  c_real.aspect_memberships.create(aspect_id: 7)
end
user = User.find(1)
svc = PostService.new(user)
RES["real"] << real("D7b PostService#mark_user_notifications(99)") { svc.mark_user_notifications(99) }

# receivers for the MOCK phase, built BEFORE install! (finders are mocked)
C_MOCK   = Contact.find(51)
SVC_MOCK = PostService.new(User.find(1))

# ---- INSTALL -----------------------------------------------------------
require File.join(TDIR, "core.rb")
IC = CallInterceptor.instance
ConcolicTargets.install!(IC)

# ---- MOCK --------------------------------------------------------------
RES["mock"] << mocked("D7a CollectionProxy#create") { C_MOCK.aspect_memberships.create(aspect_id: 7) }
RES["mock"] << mocked("D7b PostService#mark_user_notifications(99)") { SVC_MOCK.mark_user_notifications(99) }

File.write(OUT, JSON.pretty_generate(RES))
RES["real"].each do |r|
  puts "\n#### REAL #{r['label']}  [#{r['status']}]"
  r["statements"].each { |s| puts "   #{s}" }
end
RES["mock"].each do |r|
  puts "\n#### MOCK #{r['label']}  [#{r['status']}]"
  r["notes"].each { |t, n| puts "   [#{t}] #{n}" }
  puts "   (no note)" if r["notes"].empty?
end
puts "\nwrote #{OUT}"
