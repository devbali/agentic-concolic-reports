# DBG — direct query fidelity probe: does Notification.where(unread: true)
# match rows in the JDBC-sqlite rig? The C01 run's UPDATE never fired; the
# suspicion is the boolean bind serialization (true -> 1 vs 't').
require_relative "_common"

adv_setup!("DBG_notification_bind")
seed_people!

CE.insert("notifications", id: 501, recipient_id: 9, target_type: "Person", target_id: 1,
         unread: 1, created_at: Time.now.to_s, updated_at: Time.now.to_s, type: nil)

CONCRETE_SCENARIOS = adv_scenario("DBG_notification_bind") do
  ActiveSupport::Notifications.subscribe("sql.active_record") do |*sargs|
    payload = sargs.last
    next if payload[:cached]
    warn "SQL: #{payload[:sql]}"
    warn "BIND: #{payload[:type_casted_binds].inspect}" if payload[:type_casted_binds]
  end
  n = Notification.where(recipient_id: 9, target_type: "Person", target_id: 1, unread: true)
  warn "COUNT = #{n.count}"
  warn "FIRST = #{n.first.inspect}" if n.first
  n.each { |x| warn "EACH row #{x.id}: set_read_state -> #{x.set_read_state(true).inspect}" }
  after = Notification.find(501)
  warn "AFTER unread=#{after.unread.inspect}"
end