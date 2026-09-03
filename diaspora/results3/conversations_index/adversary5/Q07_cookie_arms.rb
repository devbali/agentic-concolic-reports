# Q07 — remember-cookie arms Q01 mis-specified or did not reach: a cookie whose
# generated_at is older than remember_for (2 weeks) -> 401 with no write; the
# cookie login on the InvalidLocale and invalid-page terminals (the boundary's
# two writes precede them); a cookie login on .js and .xml.
require_relative "_common"
adv_setup!("Q07_cookie_arms"); seed_people!(alice_extra: { last_seen: nil, remember_created_at: ts(Time.now - 30 * 86_400) }); seed_batch_conversations!; seed_layout_rows!
seed_principal!(20, 20, "erin", lang: "xx", extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) })
seed_principal!(21, 21, "fay",  extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) })
seed_principal!(22, 22, "gus",  extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) })
seed_principal!(23, 23, "hal",  extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) })
devise_warden_ready!
def req(tag, fmt = :html, params = {}, opts = {})
  { name: "Q07_#{tag}", body: -> { adv_request({ format: fmt, params: params, tag: tag }.merge(opts)) } }
end
CONCRETE_SCENARIOS = adv_scenarios([
  req("alice_cookie_generated_3weeks_ago", :html, {}, session_key: false, remember: { generated_at: (Time.now.utc - 21 * 86_400).to_f.to_s }), # remember_for exceeded -> 401
  req("erin_cookie_invalid_locale", :html, {}, uid: 20, session_key: false, remember: {}),   # writes then I18n::InvalidLocale
  req("fay_cookie_page0", :html, { page: "0" }, uid: 21, session_key: false, remember: {}),   # writes then RangeError
  req("gus_cookie_js", :js, {}, uid: 22, session_key: false, remember: {}),
  req("hal_cookie_xml", :xml, {}, uid: 23, session_key: false, remember: {}),
])
