# R01 — the remember-cookie VALIDITY decision. The corpus's `_remembered` is one
# boolean (remember_created_at NULL or not) and the cookie it mints is always
# fresh, so `via_cookie ∧ remembered` always logs in and `¬remembered` always
# 401s. The real predicate (devise/models/rememberable.rb remember_me?) has
# three more conjuncts: generated_at within remember_for, generated_at LATER
# than remember_created_at, token == salt. Also: trackable histories the
# batch's derivation `prev_login_first ⇒ last_ip == current_ip` forecloses,
# the unsigned/foreign cookie, the deleted principal, both credentials at once.
require_relative "_common"
adv_setup!("R01_cookie_validity"); seed_people!(alice_extra: { last_seen: nil, remember_created_at: ts(Time.now - 3600) }); seed_batch_conversations!; seed_layout_rows!
T = Time.now
# remembered 20 days ago; cookie minted 15 days ago -> remember_for (2 weeks) exceeded
seed_principal!(20, 20, "brian",  extra: { last_seen: nil, remember_created_at: ts(T - 20 * 86_400) })
# NOT remembered (NULL), cookie minted 5 minutes in the FUTURE (clock skew between pod nodes)
seed_principal!(21, 21, "carl", extra: { last_seen: nil, remember_created_at: nil })
# same-second history: current_at == last_at but current_ip != last_ip (MySQL DATETIME has no
# fraction; two logins in one second from two IPs). Then a login from the CURRENT ip ...
seed_principal!(22, 22, "dan",  extra: { last_seen: nil, remember_created_at: ts(T - 3600), sign_in_count: 2,
  current_sign_in_at: ts(T - 86_400), last_sign_in_at: ts(T - 86_400), current_sign_in_ip: "10.1.1.1", last_sign_in_ip: "10.2.2.2" })
# ... and from a NEW ip
seed_principal!(23, 23, "eve",  extra: { last_seen: nil, remember_created_at: ts(T - 3600), sign_in_count: 2,
  current_sign_in_at: ts(T - 86_400), last_sign_in_at: ts(T - 86_400), current_sign_in_ip: "10.1.1.1", last_sign_in_ip: "10.2.2.2" })
seed_principal!(24, 24, "fay",  extra: { last_seen: nil, remember_created_at: ts(T - 3600) })
seed_principal!(25, 25, "gus",  extra: { last_seen: nil, remember_created_at: ts(T - 3600) })
seed_principal!(26, 26, "hal",  extra: { last_seen: ts(T), remember_created_at: ts(T - 3600) })
seed_principal!(27, 27, "ivy",  extra: { last_seen: nil, remember_created_at: ts(T - 3600) })
# never logged in at all (all trackable columns NULL) but remembered — fixture-only? (see report)
seed_principal!(28, 28, "jon",  extra: { last_seen: nil, remember_created_at: ts(T - 3600), sign_in_count: 0,
  current_sign_in_at: nil, last_sign_in_at: nil, current_sign_in_ip: nil, last_sign_in_ip: nil })
devise_warden_ready!
def req(tag, fmt = :html, params = {}, opts = {})
  { name: "R01_#{tag}", body: -> { adv_request({ format: fmt, params: params, tag: tag }.merge(opts)) } }
end
CONCRETE_SCENARIOS = adv_scenarios([
  # remembered principal, cookie OLDER than remember_created_at (signed out elsewhere, re-remembered) -> 401
  req("alice_remembered_cookie_older", :html, {}, session_key: false, remember: { generated_at: (T.utc - 7200).to_f.to_s }),
  # remembered principal, cookie inside remember_created_at but beyond remember_for -> 401
  req("brian_remembered_cookie_expired", :html, {}, uid: 20, session_key: false, remember: { generated_at: (T.utc - 15 * 86_400).to_f.to_s }),
  # NOT remembered, FUTURE cookie -> logs in (remember_created_at || Time.now < generated_at)
  req("carl_notremembered_future_cookie", :html, {}, uid: 21, session_key: false, remember: { generated_at: (T.utc + 300).to_f.to_s }),
  req("dan_sameSecond_ipsDiffer_sameIp", :html, {}, uid: 22, session_key: false, remember: {}, remote_addr: "10.1.1.1"),
  req("eve_sameSecond_ipsDiffer_newIp",  :html, {}, uid: 23, session_key: false, remember: {}, remote_addr: "10.3.3.3"),
  # unsigned garbage cookie, no session -> strategy invalid -> 401 with 0 reads
  req("fay_garbage_cookie", :html, {}, uid: 24, session_key: false, raw_cookie: "not-a-signed-cookie"),
  # signed cookie naming a principal that no longer exists -> 1 read -> 401
  req("gus_cookie_deleted_uid", :html, {}, uid: 25, session_key: false, remember: { token: "abcdefghijklmnopqrstuvwxyz012" }, remember_uid: 999),
  # session AND cookie both valid: fetch wins, no authentication event
  req("hal_session_and_cookie", :html, {}, uid: 26, session_key: true, remember: {}),
  # password changed elsewhere: stale session salt AND stale cookie token -> 401; how many users reads?
  req("ivy_stale_session_stale_cookie", :html, {}, uid: 27, salt: "stale-salt-xxxxxxxxxxxxxxxxxxxx", remember: { token: "stale-salt-xxxxxxxxxxxxxxxxxxxx" }),
  # first-ever trackable state under a cookie (fixture-only; a cookie implies a prior sign-in)
  req("jon_never_signed_in_cookie", :json, {}, uid: 28, session_key: false, remember: {}),
])
