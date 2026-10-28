require_relative "_common"
adv_setup!("DBG_notification_bind3")
seed_people!
# insert through the REAL model (AR type-casts the boolean)
n = Notification.new(recipient_id: 9, target_type: "Person", target_id: 1, unread: true)
n.id = 501
n.save!
warn "inserted unread raw: #{Notification.find(501).unread.inspect}"
warn "count via AR create + bind true: #{Notification.where(recipient_id: 9, target_type: 'Person', target_id: 1, unread: true).count}"
warn "count via AR create + bind 1: #{Notification.where(recipient_id: 9, target_type: 'Person', target_id: 1, unread: 1).count}"
warn "count via raw AR sql: #{Notification.count_by_sql("SELECT COUNT(*) FROM notifications WHERE unread = 1")}"
warn "arel sql: #{Notification.where(recipient_id: 9, target_type: 'Person', target_id: 1, unread: true).to_sql.inspect}"