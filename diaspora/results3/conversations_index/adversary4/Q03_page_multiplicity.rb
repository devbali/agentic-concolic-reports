# Q03 — will_paginate's loaded-relation shortcut and the COUNT multiplicity:
# empty inbox (relation never loaded -> total_entries COUNTs again), a full
# page of exactly 15 (size == per_page -> COUNT again), page 2 beyond, and a
# partial page 2 (16 rows -> 1 row on page 2 -> offset + size, no COUNT).
require_relative "_common"
adv_setup!("Q03_page_multiplicity"); seed_people!
seed_principal!(10, 4, "dora")                    # empty inbox
seed_principal!(20, 20, "erin")                   # 16 conversations
# alice: exactly 15 conversations, each 1 message from bob, participants alice+bob
(1..15).each do |i|
  CE.insert("conversations", id: 100 + i, subject: "conv #{i}", guid: "cg#{i}", author_id: 2)
  CE.insert("conversation_visibilities", id: 200 + i, conversation_id: 100 + i, person_id: 1, unread: 0)
  CE.insert("conversation_visibilities", id: 300 + i, conversation_id: 100 + i, person_id: 2, unread: 0)
  CE.insert("messages", id: 400 + i, conversation_id: 100 + i, author_id: 2, guid: "mg#{i}", text: "m#{i}")
end
(1..16).each do |i|
  CE.insert("conversations", id: 500 + i, subject: "e conv #{i}", guid: "eg#{i}", author_id: 2)
  CE.insert("conversation_visibilities", id: 600 + i, conversation_id: 500 + i, person_id: 20, unread: 0)
  CE.insert("conversation_visibilities", id: 700 + i, conversation_id: 500 + i, person_id: 2, unread: 0)
  CE.insert("messages", id: 800 + i, conversation_id: 500 + i, author_id: 2, guid: "emg#{i}", text: "e#{i}")
end

def req(tag, fmt = :html, params = {}, opts = {})
  { name: "Q03_#{tag}", body: -> { adv_request(format: fmt, params: params, uid: opts.fetch(:uid, 9), session: opts.fetch(:session, {}), tag: tag, warden: opts[:warden]) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("dora_empty_html",   :html, {}, uid: 10),
  req("dora_empty_mobile", :html, {}, uid: 10, session: { mobile_view: true }),
  req("dora_empty_js",     :js,   {}, uid: 10),
  req("alice_15_page1_html"),
  req("alice_15_page2_html", :html, { page: "2" }),
  req("alice_15_page1_mobile", :html, {}, session: { mobile_view: true }),
  req("alice_15_json", :json),
  req("erin_16_page2_html", :html, { page: "2" }, uid: 20),
  req("erin_16_page1_html", :html, {}, uid: 20),
  req("erin_16_page2_mobile", :html, { page: "2" }, uid: 20, session: { mobile_view: true }),
])
