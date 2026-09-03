# R06 (= round-1 A06): 16 conversations; page nil / 2 / 3 (beyond) / json page 2 / mobile page 3.
require_relative "_common"
adv_setup!("R06_pagination_16"); seed_people!
(1..16).each do |i|
  CE.insert("conversations", id: 100 + i, subject: "conv #{i}", guid: "pg#{i}", author_id: (i.odd? ? 1 : 2))
  CE.insert("conversation_visibilities", id: 200 + i, conversation_id: 100 + i, person_id: 1, unread: i % 3)
  CE.insert("conversation_visibilities", id: 300 + i, conversation_id: 100 + i, person_id: 2, unread: 0)
  CE.insert("messages", id: 400 + i, conversation_id: 100 + i, author_id: 2, guid: "pgm#{i}", text: "m #{i}") if i.even?
end
CONCRETE_SCENARIOS = adv_scenario("R06_pagination_16") do
  adv_request(format: :html, params: {}, tag: "html_p_nil")
  adv_request(format: :html, params: { page: "2" }, tag: "html_p2")
  adv_request(format: :html, params: { page: "3" }, tag: "html_p3")
  adv_request(format: :json, params: { page: "2" }, tag: "json_p2")
  adv_request(format: :html, params: { page: "3" }, session: { mobile_view: true }, tag: "mobile_p3")
end
