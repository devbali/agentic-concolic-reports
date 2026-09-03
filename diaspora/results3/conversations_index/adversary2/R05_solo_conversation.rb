# R05 (= round-1 A05): conversations whose ONLY participant is the current user.
require_relative "_common"
adv_setup!("R05_solo_conversation"); seed_people!
CE.insert("conversations", id: 3, subject: "solo empty", guid: "convguid3", author_id: 1)
CE.insert("conversation_visibilities", id: 26, conversation_id: 3, person_id: 1, unread: 0)
CE.insert("conversations", id: 4, subject: "solo with msg", guid: "convguid4", author_id: 1)
CE.insert("conversation_visibilities", id: 27, conversation_id: 4, person_id: 1, unread: 2)
CE.insert("messages", id: 34, conversation_id: 4, author_id: 1, guid: "msgguid4", text: "talking to myself")
CONCRETE_SCENARIOS = adv_scenario("R05_solo_conversation") do
  adv_request(format: :html, params: {}, tag: "html_plain")
  adv_request(format: :html, params: { conversation_id: "3" }, tag: "html_cid3")
  adv_request(format: :html, params: { conversation_id: "4" }, tag: "html_cid4")
  adv_request(format: :json, params: {}, tag: "json_plain")
  adv_request(format: :html, params: {}, session: { mobile_view: true }, tag: "mobile_plain")
end
