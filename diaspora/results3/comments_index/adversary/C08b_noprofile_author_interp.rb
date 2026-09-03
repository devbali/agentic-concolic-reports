# C08b — same as C08 (comment author dave has NO profiles row) but run with JRUBY_OPTS=-X-C
# (interpreter only; C08 died in a JIT-compiled frame, SIGSEGV/exit 134) and with a
# manifest-local sql.active_record listener that appends every statement to a file AS IT
# HAPPENS, so evidence survives a native abort. Pure observation — nothing is mocked.
require_relative "_common"
adv_setup!("C08b_noprofile_author_interp"); seed_people!(dave: true, dave_profile: false); seed_batch_post!
CE.insert("comments", id: 390, commentable_id: 100, commentable_type: "Post", author_id: 4, guid: "cguid390", text: "no profile author")
SQL_TRAIL = File.join(ADV_DIR, "runs", "C08b_sql_trail.txt")
File.write(SQL_TRAIL, "")
ActiveSupport::Notifications.subscribe("sql.active_record") do |*a|
  p = a.last
  next if p[:cached] || %w[SCHEMA TRANSACTION].include?(p[:name].to_s)
  File.open(SQL_TRAIL, "a") { |f| f.puts "[#{Thread.current[:cc_target_frame]}] #{p[:sql]}"; f.flush }
end
CONCRETE_SCENARIOS = adv_scenario("C08b_noprofile_author_interp") do
  adv_request(post_id: "100", format: :json, tag: "json_noprofile_author_interp")
end
