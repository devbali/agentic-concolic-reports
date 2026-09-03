# N05 — exactly 15 conversations (== per_page): page nil (a FULL first page:
# will_paginate total_entries re-COUNTs because size == limit), page "1"
# explicit, page "2" (beyond the end: `@visibilities.count > 0` is TRUE — the
# will_paginate count strips OFFSET — while the row list is EMPTY, the state the
# batch's cardinality link declares "no database produces"), mobile page 2,
# json page 2, and a conversation_id whose conversation is on page 2 would-be
# (all on page 1 here) — conv 115 is the OLDEST (updated_at ordering).
require_relative "_common"
adv_setup!("N05_pagination_15_boundary"); seed_people!
(1..15).each do |i|
  CE.insert("conversations", id: 100 + i, subject: "conv #{i}", guid: "pg#{i}", author_id: (i.odd? ? 1 : 2),
            updated_at: "2026-01-%02d 00:00:00" % (16 - i))
  CE.insert("conversation_visibilities", id: 200 + i, conversation_id: 100 + i, person_id: 1, unread: i % 2)
  CE.insert("conversation_visibilities", id: 300 + i, conversation_id: 100 + i, person_id: 2, unread: 0)
  CE.insert("messages", id: 400 + i, conversation_id: 100 + i, author_id: 2, guid: "pgm#{i}", text: "m #{i}")
end
CONCRETE_SCENARIOS = adv_scenario("N05_pagination_15_boundary") do
  adv_request(format: :html, params: {}, tag: "html_p_nil")
  adv_request(format: :html, params: { page: "1" }, tag: "html_p1")
  adv_request(format: :html, params: { page: "2" }, tag: "html_p2")
  adv_request(format: :html, params: { page: "2", conversation_id: "115" }, tag: "html_p2_cid115")
  adv_request(format: :html, params: { page: "2" }, session: { mobile_view: true }, tag: "mobile_p2")
  adv_request(format: :json, params: { page: "2" }, tag: "json_p2")
end
