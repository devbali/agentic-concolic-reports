# frozen_string_literal: true
#
# measure_destroy.rb — REAL ActiveRecord, no concolic mocks, a PRIVATE copy of
# db/concolic.sqlite3 under this box's batch/. Replays the data-access body of
# ConversationVisibilitiesController#destroy (app rev 0760b6a, controller lines
# 12-16) statement for statement and captures every `sql.active_record` event,
# tagged with which controller step issued it.
#
# Two scenarios, differing ONLY in how many participants the conversation has:
#   two_participants  -> after_destroy reads, finds 1 left, does not cascade
#   last_participant  -> after_destroy reads, finds 0 left, destroys conversation
#
# Writes only BATCH/measure_destroy.sqlite3 and BATCH/measure_destroy.json.

require "./config/environment"
require "json"
require "fileutils"

BATCH = ENV.fetch("BATCH")
DB = File.join(BATCH, "measure_destroy.sqlite3")
FileUtils.cp(File.join(Rails.root, "db", "concolic.sqlite3"), DB)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB, pool: 1)
CONN = ActiveRecord::Base.connection

$sql = []
$step = nil
ActiveSupport::Notifications.subscribe("sql.active_record") do |_n, _s, _f, _i, p|
  next unless $step
  next if p[:name].to_s =~ /SCHEMA/
  $sql << { "step" => $step, "sql" => p[:sql].to_s }
end

NOW = "2026-10-05 00:00:00"
def ins(sql)
  CONN.execute(sql)
end

def seed!(n_participants)
  %w[messages conversation_visibilities conversations people].each { |t| ins("DELETE FROM #{t}") }
  (1..3).each do |i|
    ins(%(INSERT INTO people (id, guid, diaspora_handle, serialized_public_key, owner_id, created_at, updated_at) VALUES (#{i}, 'g#{i}', 'p#{i}@x', 'k', #{i}, '#{NOW}', '#{NOW}')))
  end
  ins(%(INSERT INTO conversations (id, subject, guid, author_id, created_at, updated_at) VALUES (5, 's', 'cg5', 1, '#{NOW}', '#{NOW}')))
  (1..n_participants).each do |i|
    ins(%(INSERT INTO conversation_visibilities (id, conversation_id, person_id, unread, created_at, updated_at) VALUES (#{10 + i}, 5, #{i}, 0, '#{NOW}', '#{NOW}')))
  end
  ins(%(INSERT INTO messages (id, conversation_id, author_id, guid, text, created_at, updated_at) VALUES (21, 5, 1, 'mg21', 'hi', '#{NOW}', '#{NOW}')))
end

def step(name)
  $step = name
  yield
ensure
  $step = nil
end

out = {}
{ "two_participants" => 2, "last_participant" => 1 }.each do |label, n|
  seed!(n)
  $sql = []
  status = "ok"
  begin
    person_id = 1
    vis = nil
    participants = nil
    step("controller:where.first") { vis = ConversationVisibility.where(person_id: person_id, conversation_id: "5").first }
    step("controller:vis.conversation") { vis.conversation }
    step("controller:participants.count") { participants = vis.conversation.participants.count }
    step("controller:vis.destroy") { vis.destroy }
    out["#{label}_participants_before"] = participants
  rescue Exception => e # rubocop:disable Lint/RescueException
    status = "raised #{e.class}: #{e.message[0, 200]}"
  end
  after = {}
  %w[conversations conversation_visibilities messages].each { |t| after[t] = CONN.select_value("SELECT COUNT(*) FROM #{t}") }
  out[label] = { "status" => status, "statements" => $sql, "rows_after" => after }
end

File.write(File.join(BATCH, "measure_destroy.json"), JSON.pretty_generate(out))
puts JSON.pretty_generate(out)
