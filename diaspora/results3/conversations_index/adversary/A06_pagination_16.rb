# A06 — 16 conversations (per_page 15): page 1 full (will_paginate
# total_entries re-COUNTs because size == limit), params[:page]=2 (OFFSET 15),
# page=3 (beyond the end: empty page -> total_entries re-COUNT), json page=2.
require_relative "_common"
adv_setup!("A06_pagination_16"); seed_people!
(1..16).each do |i|
  CE.insert("conversations", id: 100 + i, subject: "conv #{i}", guid: "pg#{i}", author_id: (i.odd? ? 1 : 2))
  CE.insert("conversation_visibilities", id: 200 + i, conversation_id: 100 + i, person_id: 1, unread: i % 3)
  CE.insert("conversation_visibilities", id: 300 + i, conversation_id: 100 + i, person_id: 2, unread: 0)
  CE.insert("messages", id: 400 + i, conversation_id: 100 + i, author_id: 2, guid: "pgm#{i}", text: "m #{i}") if i.even?
end
CONCRETE_SCENARIOS = adv_scenario("A06_pagination_16") do
  adv_request(format: :html, params: {})
  adv_request(format: :html, params: { page: "2" })
  adv_request(format: :html, params: { page: "3" })
  adv_request(format: :json, params: { page: "2" })
end
