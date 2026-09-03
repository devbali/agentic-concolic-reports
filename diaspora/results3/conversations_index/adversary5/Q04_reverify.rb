# Q04 — re-verification of C-10..C-13 and NM-5(mobile) against the cycle-18
# corpus, plus the page-beyond x inbox x format grid (the withdrawn
# independence's territory) and the `_remembered` phantom on a non-locked
# principal. TestCase rig, real warden, real layout.
require_relative "_common"
adv_setup!("Q04_reverify"); seed_people!(alice_extra: { last_seen: nil }); seed_batch_conversations!; seed_layout_rows!(services: 2)
seed_principal!(10, 4, "dora", extra: { last_seen: ts(Time.now) })                       # empty inbox, moderator, no tags
CE.insert("roles", id: 2, person_id: 4, name: "moderator")
seed_principal!(11, 5, "fay",  extra: { last_seen: ts(Time.now - 60) })                  # fresh, non-admin, no tags, no aspects
seed_principal!(12, 6, "gus",  extra: { last_seen: nil, locked_at: ts(Time.now), remember_created_at: ts(Time.now) })   # C-11 with remember set
seed_principal!(13, 7, "hal",  extra: { last_seen: nil, locked_at: ts(Time.now), remember_created_at: nil })            # C-11 with remember NULL
seed_principal!(14, 8, "ivy",  extra: { last_seen: nil, remember_created_at: ts(Time.now) })                           # NOT locked, remembered, stale
CE.insert("services", id: 10, type: "Services::Twitter", user_id: 11, uid: "twf", access_token: "t", access_secret: "s", nickname: "f")
devise_warden_ready!

def req(tag, fmt = :html, params = {}, opts = {})
  { name: "Q04_#{tag}", body: -> { adv_request({ format: fmt, params: params, tag: tag }.merge(opts)) } }
end
MOB = { session: { mobile_view: true } }

CONCRETE_SCENARIOS = adv_scenarios([
  # C-10
  req("c10_alice_stale_html"),
  req("c10_alice_fresh_json", :json),
  req("c10_fay_fresh_mobile", :html, {}, MOB.merge(uid: 11)),
  req("c10_ivy_stale_remembered_notlocked_html", :html, {}, uid: 14),   # _remembered phantom: no remember read/write expected
  # C-11
  req("c11_gus_locked_remembered_html", :html, {}, uid: 12),
  req("c11_hal_locked_notremembered_mobile", :html, {}, MOB.merge(uid: 13)),
  # C-12 / NM-5 mobile
  req("c12_alice_admin_mobile", :html, {}, MOB),
  req("c12_dora_moderator_mobile_empty", :html, {}, MOB.merge(uid: 10)),
  req("c12_fay_nonadmin_mobile", :html, {}, MOB.merge(uid: 11)),
  req("c12_alice_mobile_cid1", :html, { conversation_id: "1" }, MOB),
  # C-13
  req("c13_alice_2services_html"),
  req("c13_fay_1service_html", :html, {}, uid: 11),
  # page beyond x empty/non-empty x format
  req("pg_dora_beyond_html", :html, { page: "2" }, uid: 10),
  req("pg_dora_beyond_json", :json, { page: "2" }, uid: 10),
  req("pg_dora_beyond_mobile", :html, { page: "2" }, MOB.merge(uid: 10)),
  req("pg_dora_beyond_js", :js, { page: "2" }, uid: 10),
  req("pg_alice_beyond_html", :html, { page: "2" }),
  req("pg_alice_beyond_json", :json, { page: "2" }),
  req("pg_alice_beyond_mobile", :html, { page: "2" }, MOB),
  req("pg_alice_beyond_js", :js, { page: "2" }),
  req("pg_alice_page1_js", :js, {}),
  req("pg_alice_xml_cid1", :xml, { conversation_id: "1" }),
])
