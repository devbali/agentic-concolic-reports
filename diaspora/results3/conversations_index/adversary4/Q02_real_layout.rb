# Q02 — the REAL layout (ADV4_REAL_LAYOUT=1): no `layout(false)`, asset
# resolvers emptied so sprockets cannot raise.  html renders
# with_header_with_footer (gon block = UserPresenter#to_json); mobile renders
# application.mobile.haml: _head (gon) + _header.mobile (unread badges) +
# _drawer.mobile (aspects, followed tags, admin/moderator, owner avatar).
require_relative "_common"
adv_setup!("Q02_real_layout"); seed_people!; seed_batch_conversations!
# layout-only tables
CE.insert("aspects", id: 1, user_id: 9, name: "Friends", order_id: 1)
CE.insert("aspects", id: 2, user_id: 9, name: "Work", order_id: 2)
CE.insert("notifications", id: 1, target_type: "Mention", target_id: 1, recipient_id: 9, unread: true, type: "Notifications::Mentioned")
CE.insert("notifications", id: 2, target_type: "Mention", target_id: 2, recipient_id: 9, unread: false, type: "Notifications::Mentioned")
CE.insert("services", id: 1, type: "Services::Twitter", user_id: 9, uid: "tw1", access_token: "t", access_secret: "s", nickname: "alice_tw")
CE.insert("tags", id: 1, name: "ruby", taggings_count: 0)
CE.insert("tags", id: 2, name: "art", taggings_count: 0)
CE.insert("tag_followings", id: 1, tag_id: 1, user_id: 9)
CE.insert("tag_followings", id: 2, tag_id: 2, user_id: 9)
CE.insert("roles", id: 1, person_id: 1, name: "admin")
CE.insert("reports", id: 1, item_id: 1, item_type: "Post", user_id: 9, reviewed: false, text: "spam")
CE.insert("reports", id: 2, item_id: 2, item_type: "Post", user_id: 9, reviewed: true, text: "ok")
# dora: nothing of the above except a moderator role and no conversations
seed_principal!(10, 4, "dora")
CE.insert("roles", id: 2, person_id: 4, name: "moderator")

def req(tag, fmt = :html, params = {}, opts = {})
  { name: "Q02_#{tag}", body: -> { adv_request(format: fmt, params: params, uid: opts.fetch(:uid, 9), session: opts.fetch(:session, {}), tag: tag, warden: opts[:warden]) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("alice_html_plain"),
  req("alice_html_cid1",    :html, { conversation_id: "1" }),
  req("alice_mobile_plain", :html, {}, session: { mobile_view: true }),   # unread=0 now (cid1 zeroed it)
  req("alice_json_plain",   :json),                                       # control: no layout
  req("dora_html_plain",    :html, {}, uid: 10),
  req("dora_mobile_plain",  :html, {}, uid: 10, session: { mobile_view: true }),
  req("alice_mobile_cid2",  :html, { conversation_id: "2" }, session: { mobile_view: true }),
])
