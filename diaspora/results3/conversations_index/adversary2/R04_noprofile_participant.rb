# R04 (= round-1 A04): participant carol (never an author) has NO profile row.
require_relative "_common"
adv_setup!("R04_noprofile_participant"); seed_people!(carol_profile: false); seed_batch_conversations!
CONCRETE_SCENARIOS = adv_scenario("R04_noprofile_participant") do
  adv_request(format: :html, params: {}, tag: "html_plain")
  adv_request(format: :html, params: { conversation_id: "1" }, tag: "html_cid1")
  adv_request(format: :json, params: { conversation_id: "1" }, tag: "json_cid1")
  adv_request(format: :html, params: { conversation_id: "1" }, session: { mobile_view: true }, tag: "mobile_cid1")
end
