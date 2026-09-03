# R04 — re-verification of C-14 (six login histories, each a real cookie login)
# and C-15 (conversation_id[] on html/json/mobile), plus the brief's combo:
# cookie + page beyond + empty inbox on .js.
require_relative "_common"
adv_setup!("R04_reverify"); seed_people!(alice_extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) }); seed_batch_conversations!; seed_layout_rows!
T = Time.now
H = { last_seen: nil, remember_created_at: ts(T - 3600), sign_in_count: 3 }
# h1 all five: times differ, ips differ, new ip
seed_principal!(20, 20, "h1", extra: H.merge(current_sign_in_at: ts(T - 86_400), last_sign_in_at: ts(T - 172_800), current_sign_in_ip: "10.1.1.1", last_sign_in_ip: "10.2.2.2"))
# h2 {count, current_at}: prev login first-ever (times equal, ips equal), same ip
seed_principal!(21, 21, "h2", extra: H.merge(current_sign_in_at: ts(T - 86_400), last_sign_in_at: ts(T - 86_400), current_sign_in_ip: "10.1.1.1", last_sign_in_ip: "10.1.1.1"))
# h3 {count, current_at, last_at}: times differ, ips equal, same ip
seed_principal!(22, 22, "h3", extra: H.merge(current_sign_in_at: ts(T - 86_400), last_sign_in_at: ts(T - 172_800), current_sign_in_ip: "10.1.1.1", last_sign_in_ip: "10.1.1.1"))
# h4 {count, current_at, last_at, current_ip}: times differ, ips equal, new ip
seed_principal!(23, 23, "h4", extra: H.merge(current_sign_in_at: ts(T - 86_400), last_sign_in_at: ts(T - 172_800), current_sign_in_ip: "10.1.1.1", last_sign_in_ip: "10.1.1.1"))
# h5 {count, current_at, last_at, last_ip}: times differ, ips differ, same ip
seed_principal!(24, 24, "h5", extra: H.merge(current_sign_in_at: ts(T - 86_400), last_sign_in_at: ts(T - 172_800), current_sign_in_ip: "10.1.1.1", last_sign_in_ip: "10.2.2.2"))
# h6 {count, current_at, current_ip}: prev first-ever (equal, equal), new ip
seed_principal!(25, 25, "h6", extra: H.merge(current_sign_in_at: ts(T - 86_400), last_sign_in_at: ts(T - 86_400), current_sign_in_ip: "10.1.1.1", last_sign_in_ip: "10.1.1.1"))
seed_principal!(26, 26, "kim", extra: { last_seen: nil, remember_created_at: ts(T - 3600) })  # empty inbox
seed_principal!(27, 27, "lee", extra: { last_seen: nil, remember_created_at: ts(T - 3600) })
devise_warden_ready!
def req(tag, fmt = :html, params = {}, opts = {})
  { name: "R04_#{tag}", body: -> { adv_request({ format: fmt, params: params, tag: tag }.merge(opts)) } }
end
CONCRETE_SCENARIOS = adv_scenarios([
  req("h1_allfive",            :html, {}, uid: 20, session_key: false, remember: {}, remote_addr: "10.3.3.3"),
  req("h2_count_currentat",    :html, {}, uid: 21, session_key: false, remember: {}, remote_addr: "10.1.1.1"),
  req("h3_plus_lastat",        :html, {}, uid: 22, session_key: false, remember: {}, remote_addr: "10.1.1.1"),
  req("h4_plus_lastat_curip",  :html, {}, uid: 23, session_key: false, remember: {}, remote_addr: "10.3.3.3"),
  req("h5_plus_lastat_lastip", :html, {}, uid: 24, session_key: false, remember: {}, remote_addr: "10.1.1.1"),
  req("h6_plus_curip",         :html, {}, uid: 25, session_key: false, remember: {}, remote_addr: "10.3.3.3"),
  req("c15_cid_empty_array_html",   :html, {}, query_string: "conversation_id[]"),
  req("c15_cid_empty_array_json",   :json, {}, query_string: "conversation_id[]"),
  req("c15_cid_empty_array_mobile", :html, {}, query_string: "conversation_id[]", session: { mobile_view: true }),
  req("kim_cookie_js_page2_empty",  :js,   { page: "2" }, uid: 26, session_key: false, remember: {}),
  req("lee_cookie_mobile_cid1_page2", :html, { conversation_id: "1", page: "2" }, uid: 27, session_key: false, remember: {}, session: { mobile_view: true }),
])
