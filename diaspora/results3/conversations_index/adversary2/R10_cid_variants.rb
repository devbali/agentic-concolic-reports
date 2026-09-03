# R10 (= round-1 A10): conversation_id shapes — not a participant, non-existent, non-numeric, empty, array.
require_relative "_common"
adv_setup!("R10_cid_variants"); seed_people!; seed_batch_conversations!
CE.insert("conversations", id: 5, subject: "not yours", guid: "convguid5", author_id: 2)
CE.insert("conversation_visibilities", id: 28, conversation_id: 5, person_id: 2, unread: 0)
CE.insert("conversation_visibilities", id: 29, conversation_id: 5, person_id: 3, unread: 1)
CONCRETE_SCENARIOS = adv_scenario("R10_cid_variants") do
  adv_request(format: :html, params: { conversation_id: "5" }, tag: "cid5")
  adv_request(format: :html, params: { conversation_id: "999" }, tag: "cid999")
  adv_request(format: :html, params: { conversation_id: "abc" }, tag: "cidabc")
  adv_request(format: :html, params: { conversation_id: "" }, tag: "cidempty")
  adv_request_rescued(format: :json, params: { conversation_id: ["1", "2"] }, tag: "cidarray")
  adv_request(format: :html, params: { conversation_id: "5" }, session: { mobile_view: true }, tag: "mobile_cid5")
end
