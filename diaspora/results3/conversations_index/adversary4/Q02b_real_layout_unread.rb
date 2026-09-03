# Q02b — the real layout with the principal's inbox UNREAD (badge branches of
# _header.mobile.haml render the counts a second time).  ADV4_REAL_LAYOUT=1.
require_relative "_common"
adv_setup!("Q02b_real_layout_unread"); seed_people!; seed_batch_conversations!
CE.insert("aspects", id: 1, user_id: 9, name: "Friends", order_id: 1)
CE.insert("notifications", id: 1, target_type: "Mention", target_id: 1, recipient_id: 9, unread: true, type: "Notifications::Mentioned")
CE.insert("services", id: 1, type: "Services::Twitter", user_id: 9, uid: "tw1", access_token: "t", access_secret: "s", nickname: "alice_tw")
CE.insert("services", id: 2, type: "Services::Tumblr", user_id: 9, uid: "tb1", access_token: "t", access_secret: "s", nickname: "alice_tb")

def req(tag, fmt = :html, params = {}, opts = {})
  { name: "Q02b_#{tag}", body: -> { adv_request(format: fmt, params: params, uid: opts.fetch(:uid, 9), session: opts.fetch(:session, {}), tag: tag, warden: opts[:warden]) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("alice_mobile_unread_plain", :html, {}, session: { mobile_view: true }),   # unread=1 -> both badges
  req("alice_html_unread_plain"),
  req("alice_mobile_unread_cid1", :html, { conversation_id: "1" }, session: { mobile_view: true }), # set_read runs BEFORE the layout: SUM sees 0
])
