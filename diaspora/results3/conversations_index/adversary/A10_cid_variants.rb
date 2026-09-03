# A10 — params[:conversation_id] shapes: a conversation alice is NOT a
# participant of (conv 5: bob+carol), a non-existent id, a non-numeric id,
# an empty string, and an array.
require_relative "_common"
adv_setup!("A10_cid_variants"); seed_people!; seed_batch_conversations!
CE.insert("conversations", id: 5, subject: "not yours", guid: "convguid5", author_id: 2)
CE.insert("conversation_visibilities", id: 28, conversation_id: 5, person_id: 2, unread: 0)
CE.insert("conversation_visibilities", id: 29, conversation_id: 5, person_id: 3, unread: 1)
CONCRETE_SCENARIOS = adv_scenario("A10_cid_variants") do
  adv_request(format: :html, params: { conversation_id: "5" })
  adv_request(format: :html, params: { conversation_id: "999" })
  adv_request(format: :html, params: { conversation_id: "abc" })
  adv_request(format: :html, params: { conversation_id: "" })
  begin
    adv_request(format: :json, params: { conversation_id: ["1", "2"] })
  rescue StandardError => e
    warn "[adversary] array cid raised #{e.class}: #{e.message[0, 120]}"
  end
end
