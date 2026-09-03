# R03 — cookie logins through the FULL production middleware stack
# (Rails.application.call): RemoteIp decides trackable's IP (X-Forwarded-For),
# the IP-spoof check, C-15 and the overflow terminal under real exception
# handling, .js / mobile / json with a cookie.
require_relative "_common"
adv_setup!("R03_fullstack"); seed_people!(alice_extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) }); seed_batch_conversations!; seed_layout_rows!
T = Time.now
seed_principal!(20, 20, "erin", extra: { last_seen: nil, remember_created_at: ts(T - 3600), sign_in_count: 2,
  current_sign_in_at: ts(T - 86_400), last_sign_in_at: ts(T - 172_800), current_sign_in_ip: "10.1.1.1", last_sign_in_ip: "10.1.1.1" })
seed_principal!(21, 21, "fay",  extra: { last_seen: nil, remember_created_at: ts(T - 3600) })
seed_principal!(22, 22, "gus",  extra: { last_seen: nil, remember_created_at: ts(T - 3600) })
seed_principal!(23, 23, "hal",  extra: { last_seen: nil, remember_created_at: ts(T - 3600) })
seed_principal!(24, 24, "ivy",  extra: { last_seen: nil, remember_created_at: ts(T - 3600) })
seed_principal!(25, 25, "jon",  extra: { last_seen: nil, remember_created_at: ts(T - 3600) })
devise_warden_ready!
IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.0 Mobile/15E148 Safari/604.1"
def fs(tag, path, opts = {})
  { name: "R03_#{tag}", body: -> { fullstack_request({ path: path, tag: tag }.merge(opts)) } }
end
CONCRETE_SCENARIOS = adv_scenarios([
  fs("erin_cookie_xff_newip",  "/conversations",                     remember: { uid: 20 }, headers: { "HTTP_X_FORWARDED_FOR" => "10.7.7.7" }),
  fs("erin_cookie_xff_sameip", "/conversations.json",                remember: { uid: 20 }, headers: { "HTTP_X_FORWARDED_FOR" => "10.7.7.7" }),
  fs("fay_cookie_cid_empty_array", "/conversations?conversation_id[]", remember: { uid: 21 }),
  fs("gus_cookie_js_page2_empty",  "/conversations.js?page=2",       remember: { uid: 22 }),
  fs("hal_cookie_mobile_ua",       "/conversations",                 remember: { uid: 23 }, headers: { "HTTP_USER_AGENT" => IPHONE }),
  fs("ivy_cookie_cid_2p31",        "/conversations?conversation_id=2147483648", remember: { uid: 24 }),
  fs("jon_cookie_ip_spoof",        "/conversations",                 remember: { uid: 25 }, headers: { "HTTP_X_FORWARDED_FOR" => "10.7.7.7", "HTTP_CLIENT_IP" => "10.8.8.8" }),
  fs("alice_cookie_older_fullstack", "/conversations",               remember: { uid: 9, generated_at: (T.utc - 7200).to_f.to_s }),
  fs("anon_json", "/conversations.json"),
])
