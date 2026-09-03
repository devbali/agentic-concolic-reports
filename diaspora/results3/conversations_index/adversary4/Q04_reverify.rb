# Q04 — re-verification of the round-3 wins (C-5..C-8) and M-5 against the
# cycle-15 corpus, with the batch's own rig conventions (stub warden,
# layout(false)).  One request per scenario.
require_relative "_common"
adv_setup!("Q04_reverify"); seed_people!
# conv 1: my unread = 1 (first cid request UPDATEs, second must not)
CE.insert("conversations", id: 1, subject: "hello alice", guid: "convguid1", author_id: 2)
CE.insert("conversation_visibilities", id: 21, conversation_id: 1, person_id: 1, unread: 1)
CE.insert("conversation_visibilities", id: 22, conversation_id: 1, person_id: 2, unread: 0)
CE.insert("messages", id: 31, conversation_id: 1, author_id: 2, guid: "msgguid1", text: "hi alice, first message")
CE.insert("messages", id: 32, conversation_id: 1, author_id: 1, guid: "msgguid2", text: "hi bob reply")
# conv 2: my unread = 0 from the start
CE.insert("conversations", id: 2, subject: "", guid: "convguid2", author_id: 1)
CE.insert("conversation_visibilities", id: 24, conversation_id: 2, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 25, conversation_id: 2, person_id: 2, unread: 0)
CE.insert("messages", id: 33, conversation_id: 2, author_id: 2, guid: "msgguid3", text: "second conv")
# conv 3: my unread = -3 (legacy negative; P12)
CE.insert("conversations", id: 3, subject: "neg", guid: "convguid3", author_id: 2)
CE.insert("conversation_visibilities", id: 26, conversation_id: 3, person_id: 1, unread: -3)
CE.insert("conversation_visibilities", id: 27, conversation_id: 3, person_id: 2, unread: 0)
CE.insert("messages", id: 34, conversation_id: 3, author_id: 2, guid: "msgguid4", text: "neg msg")
# locale principals (M-5)
seed_principal!(10, 4, "dora", lang: "xx")
seed_principal!(11, 5, "eve",  lang: "")
seed_principal!(12, 6, "finn", lang: nil)
seed_principal!(13, 7, "gail", lang: "pl")

def req(tag, fmt = :html, params = {}, opts = {})
  { name: "Q04_#{tag}", body: -> { adv_request(format: fmt, params: params, uid: opts.fetch(:uid, 9), session: opts.fetch(:session, {}), tag: tag, warden: opts[:warden]) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  # C-5
  req("c5_cid1_unread1_first", :html, { conversation_id: "1" }),   # UPDATE
  req("c5_cid1_now0_again",    :html, { conversation_id: "1" }),   # no UPDATE
  req("c5_cid2_unread0_json",  :json, { conversation_id: "2" }),   # no UPDATE
  req("c5_cid3_negative_mobile", :html, { conversation_id: "3" }, session: { mobile_view: true }), # UPDATE (-3 -> 0)
  # C-6
  req("c6_cid_array_html",   :html, { conversation_id: ["1", "2"] }),
  req("c6_cid_array_miss_mobile", :html, { conversation_id: ["998", "999"] }, session: { mobile_view: true }),
  # C-7
  req("c7_page0_html",   :html, { page: "0" }),
  req("c7_pageabc_json", :json, { page: "abc" }),
  req("c7_pagearr_mobile", :html, { page: ["2"] }, session: { mobile_view: true }),
  # C-8
  req("c8_js_plain",  :js),
  req("c8_js_cid2",   :js,  { conversation_id: "2" }),
  req("c8_xml_plain", :xml),
  req("c8_xml_cid1",  :xml, { conversation_id: "1" }),
  # M-5
  req("m5_dora_xx_html",  :html, {}, uid: 10),
  req("m5_eve_empty_json", :json, {}, uid: 11),
  req("m5_finn_null_html", :html, {}, uid: 12),
  req("m5_gail_pl_html",   :html, {}, uid: 13),
])
