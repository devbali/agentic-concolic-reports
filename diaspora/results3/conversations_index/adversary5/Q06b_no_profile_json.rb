# Q06 — a principal whose person has NO profile row, through the real layout
# (presenter as_api_response, drawer person_image_tag). Separate process.
require_relative "_common"
adv_setup!("Q06b_no_profile_json"); seed_people!(alice_extra: { last_seen: ts(Time.now) }); seed_batch_conversations!
seed_principal!(32, 32, "nopro", profile: false, extra: { last_seen: ts(Time.now) })
CE.insert("conversation_visibilities", id: 26, conversation_id: 2, person_id: 32, unread: 0)
devise_warden_ready!
def req(tag, fmt = :html, params = {}, opts = {})
  { name: "Q06_#{tag}", body: -> { adv_request({ format: fmt, params: params, tag: tag }.merge(opts)) } }
end
CONCRETE_SCENARIOS = adv_scenarios([
  req("noprofile_json", :json, {}, uid: 32),



])
# (json only: the html/mobile layouts hit Person#fix_profile -> Discovery, which aborts the JVM — DISCIPLINE §12; Q06 log)
