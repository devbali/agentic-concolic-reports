# Q01 — the REMEMBER-ME return visit and the stale session. No principal in
# the session (the session cookie expired / a new browser) but a signed
# `remember_user_token` cookie: `authenticate_user!` -> warden.authenticate!
# -> Devise::Strategies::Rememberable -> User.serialize_from_cookie ->
# set_user(event: :authentication) -> EVERY after_set_user hook incl. the
# `except: :fetch` ones (trackable, lockable, rememberable) + lastseenable.
require_relative "_common"
adv_setup!("Q01_remember_cookie"); seed_people!(alice_extra: { last_seen: nil, remember_created_at: ts(Time.now - 86_400),
  sign_in_count: 3, current_sign_in_at: ts(Time.now - 2 * 86_400), last_sign_in_at: ts(Time.now - 3 * 86_400),
  current_sign_in_ip: "10.0.0.1", last_sign_in_ip: "10.0.0.2" }); seed_batch_conversations!; seed_layout_rows!
seed_principal!(20, 20, "erin", extra: { last_seen: ts(Time.now), remember_created_at: ts(Time.now - 3600) })          # fresh last_seen
seed_principal!(21, 21, "fay",  extra: { last_seen: nil, remember_created_at: ts(Time.now - 15 * 86_400) })           # remember expired (> 2.weeks)
seed_principal!(22, 22, "gus",  extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600), locked_at: ts(Time.now) }) # locked
seed_principal!(23, 23, "hal",  extra: { last_seen: nil, remember_created_at: nil })                                    # never remembered
seed_principal!(24, 24, "ivy",  extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) })
seed_principal!(25, 25, "jon",  extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) })
seed_principal!(26, 26, "kim",  extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) })
seed_principal!(27, 27, "lee",  extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) })
devise_warden_ready!

def req(tag, fmt = :html, params = {}, opts = {})
  { name: "Q01_#{tag}", body: -> { adv_request({ format: fmt, params: params, tag: tag }.merge(opts)) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("anon_nothing_html",        :html, {}, session_key: false),                                   # control: 0 statements, 401
  req("alice_cookie_stale_html",  :html, {}, session_key: false, remember: { }),                    # cookie login: trackable + last_seen
  req("alice_cookie_fresh_html",  :html, {}, session_key: false, remember: { }),                    # again: last_seen fresh -> trackable only
  req("erin_cookie_fresh_json",   :json, {}, uid: 20, session_key: false, remember: { }),
  req("fay_cookie_expired_html",  :html, {}, uid: 21, session_key: false, remember: { }),           # remember_for exceeded -> 401
  req("gus_cookie_locked_html",   :html, {}, uid: 22, session_key: false, remember: { }),           # locked: validate fails -> 401, writes?
  req("hal_cookie_never_html",    :html, {}, uid: 23, session_key: false, remember: { }),           # remember_created_at NULL -> 401
  req("ivy_cookie_older_html",    :html, {}, uid: 24, session_key: false, remember: { generated_at: (Time.now.utc - 7200).to_f.to_s }), # cookie older than remember_created_at -> 401
  req("jon_cookie_badtoken_html", :html, {}, uid: 25, session_key: false, remember: { token: "not-the-salt-xxxxxxxxxxxxxxxx" }),  # 401
  req("kim_stale_session_html",   :html, {}, uid: 26, salt: "stale-salt-xxxxxxxxxxxxxxxxxxxx"),      # password changed elsewhere: 401, no write
  req("kim_stale_session_cookie", :html, {}, uid: 26, salt: "stale-salt-xxxxxxxxxxxxxxxxxxxx", remember: { }), # then the cookie rescues it
  req("lee_cookie_mobile",        :html, {}, uid: 27, session_key: false, session: { mobile_view: true }, remember: { }),
  req("lee_cookie_cid1_html",     :html, { conversation_id: "1" }, uid: 27, session_key: false, remember: { }),
])
