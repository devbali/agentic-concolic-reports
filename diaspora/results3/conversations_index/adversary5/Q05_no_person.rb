# Q05 — a principal whose users row has NO people row (people.owner_id read
# returns nil): every delegate to :person raises. Separate process (abort risk).
require_relative "_common"
adv_setup!("Q05_no_person"); seed_people!(alice_extra: { last_seen: ts(Time.now) }); seed_batch_conversations!
seed_principal!(30, 30, "nop", person: false, extra: { last_seen: ts(Time.now) })
seed_principal!(31, 31, "nop2", person: false, extra: { last_seen: nil })
devise_warden_ready!
def req(tag, fmt = :html, params = {}, opts = {})
  { name: "Q05_#{tag}", body: -> { adv_request({ format: fmt, params: params, tag: tag }.merge(opts)) } }
end
CONCRETE_SCENARIOS = adv_scenarios([
  req("noperson_html", :html, {}, uid: 30),
  req("noperson_json", :json, {}, uid: 30),
  req("noperson_mobile", :html, {}, uid: 30, session: { mobile_view: true }),
  req("noperson_stale_html", :html, {}, uid: 31),
])
