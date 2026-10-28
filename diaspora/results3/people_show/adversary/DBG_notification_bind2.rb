require_relative "_common"
adv_setup!("DBG_notification_bind2")
seed_people!
CE.insert("notifications", id: 501, recipient_id: 9, target_type: "Person", target_id: 1,
         unread: 1, created_at: Time.now.to_s, updated_at: Time.now.to_s, type: nil)
CE.insert("notifications", id: 502, recipient_id: 9, target_type: "Person", target_id: 1,
         unread: 0, created_at: Time.now.to_s, updated_at: Time.now.to_s, type: nil)
CONCRETE_SCENARIOS = adv_scenario("DBG_notification_bind2") do
  warn "count unread=1 literal: #{Notification.where("unread = 1").count}"
  warn "count unread=? bind int: #{Notification.where(unread: 1).count}"
  warn "count unread=? bind true: #{Notification.where(unread: true).count}"
  warn "count unread=? bind false: #{Notification.where(unread: false).count}"
  warn "loaded unread vals: #{Notification.pluck(:unread).inspect}"
  warn "column type: #{Notification.columns_hash['unread'].type.inspect}"
end
