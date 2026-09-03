# Q06 — a principal whose person has NO profile row, through the real layout
# (presenter as_api_response, drawer person_image_tag). Separate process.
require_relative "_common"
adv_setup!("Q06_no_profile"); seed_people!(alice_extra: { last_seen: ts(Time.now) }); seed_batch_conversations!
seed_principal!(32, 32, "nopro", profile: false, extra: { last_seen: ts(Time.now) })
CE.insert("conversation_visibilities", id: 26, conversation_id: 2, person_id: 32, unread: 0)
devise_warden_ready!
def req(tag, fmt = :html, params = {}, opts = {})
  { name: "Q06_#{tag}", body: -> { adv_request({ format: fmt, params: params, tag: tag }.merge(opts)) } }
end
CONCRETE_SCENARIOS = adv_scenarios([
  req("noprofile_json", :json, {}, uid: 32),
  req("noprofile_html", :html, {}, uid: 32),
  req("noprofile_mobile", :html, {}, uid: 32, session: { mobile_view: true }),
  req("noprofile_html_cid2", :html, { conversation_id: "2" }, uid: 32),
])
