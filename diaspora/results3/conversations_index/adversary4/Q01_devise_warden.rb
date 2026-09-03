# Q01 — the REAL Warden. Every earlier round and every batch manifest put a
# stub Object in env["warden"]; production puts a Warden::Proxy built from
# Devise.warden_config there, and resolving the session user through it runs
# `Warden::Manager.after_set_user` — Devise's activatable/lockable hooks and
# devise_lastseenable's `record.stamp!`, which UPDATEs `users.last_seen` when
# it is older than 5 minutes.  Run with ADV4_DEVISE_WARDEN=1.
require_relative "_common"
adv_setup!("Q01_devise_warden"); seed_people!(alice_extra: { last_seen: nil }); seed_batch_conversations!
seed_principal!(20, 20, "erin", extra: { last_seen: (Time.now.utc - 10 * 60).strftime("%Y-%m-%d %H:%M:%S") })
seed_principal!(21, 21, "fay",  extra: { last_seen: (Time.now.utc - 60).strftime("%Y-%m-%d %H:%M:%S") })
seed_principal!(22, 22, "gus",  extra: { last_seen: nil, locked_at: Time.now.utc.strftime("%Y-%m-%d %H:%M:%S"),
                                          remember_created_at: Time.now.utc.strftime("%Y-%m-%d %H:%M:%S") })
seed_principal!(23, 23, "hal",  lang: "xx", extra: { last_seen: nil })
seed_principal!(24, 24, "ivy",  extra: { last_seen: nil })
devise_warden_ready!

def req(tag, fmt = :html, params = {}, opts = {})
  { name: "Q01_#{tag}", body: -> { adv_request(format: fmt, params: params, uid: opts.fetch(:uid, 9), session: opts.fetch(:session, {}), tag: tag, warden: opts[:warden]) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("ctl_stub_alice_html", :html, {}, warden: :stub),          # the rig every round used
  req("alice_stale_html",    :html),                             # last_seen NULL -> stamp!
  req("alice_fresh_again",   :html),                             # < 5 min -> no write
  req("alice_fresh_cid_json", :json, { conversation_id: "1" }),
  req("alice_fresh_mobile",  :html, {}, session: { mobile_view: true }),
  req("erin_10min_json",     :json, {}, uid: 20),                # 10 min old -> stamp!
  req("fay_1min_html",       :html, {}, uid: 21),                # 1 min old -> no write
  req("gus_locked_html",     :html, {}, uid: 22),                # lockable -> throw :warden
  req("hal_xx_stale_html",   :html, {}, uid: 23),                # M-5 arm with the real warden
  req("ivy_stale_page0",     :html, { page: "0" }, uid: 24),     # C-7 arm with the real warden
])
