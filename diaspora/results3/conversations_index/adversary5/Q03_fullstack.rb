# Q03 — the FULL middleware stack: Rails.application.call(env) with a real
# encrypted _diaspora_session cookie (and/or a signed remember cookie).
# Production's executor (AR query cache ON), the app's own Warden manager,
# cookie session store, exception handling, mobile-fu on the User-Agent.
require_relative "_common"
adv_setup!("Q03_fullstack"); seed_people!(alice_extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) }); seed_batch_conversations!; seed_layout_rows!
seed_principal!(10, 4, "dora", extra: { last_seen: ts(Time.now) })   # empty inbox, fresh
CE.insert("roles", id: 2, person_id: 4, name: "moderator")
seed_principal!(20, 20, "erin", extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) })
devise_warden_ready!
IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.0 Mobile/15E148 Safari/604.1"

def fs(tag, opts = {})
  { name: "Q03_#{tag}", body: -> { fullstack_request({ tag: tag }.merge(opts)) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  fs("anon_html",                path: "/conversations"),                                      # failure app: redirect, 0 statements
  fs("alice_stale_html",         path: "/conversations", uid: 9),                              # cache ON: layout counts under production
  fs("alice_fresh_html",         path: "/conversations", uid: 9),
  fs("alice_html_cid1",          path: "/conversations?conversation_id=1", uid: 9),            # set_read UPDATE clears the cache mid-request
  fs("alice_json",               path: "/conversations.json", uid: 9),
  fs("alice_mobile_session",     path: "/conversations", uid: 9, session: { mobile_view: true }),
  fs("alice_mobile_ua",          path: "/conversations", uid: 9, headers: { "HTTP_USER_AGENT" => IPHONE }),     # mobile-fu switch
  fs("alice_json_mobile_ua",     path: "/conversations.json", uid: 9, headers: { "HTTP_USER_AGENT" => IPHONE }),
  fs("dora_empty_js",            path: "/conversations.js", uid: 10),                          # the exception path under the real middleware
  fs("dora_empty_html",          path: "/conversations", uid: 10),
  fs("alice_xml",                path: "/conversations.xml", uid: 9),
  fs("erin_cookie_only_html",    path: "/conversations", remember: { uid: 20 }),               # rememberable through the real Warden::Manager
  fs("erin_session_after_cookie", path: "/conversations", uid: 20),
  fs("alice_stale_session_salt", path: "/conversations", uid: 9, salt: "stale-salt-xxxxxxxxxxxxxxxxxxxx"),
])
