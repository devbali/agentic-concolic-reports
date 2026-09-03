# R01 (= round-1 A01, re-run with the salt primed outside the capture window):
# MOBILE via the app's own session switch. Batch fixtures unchanged.
require_relative "_common"
adv_setup!("R01_mobile_session"); seed_people!; seed_batch_conversations!
CONCRETE_SCENARIOS = adv_scenario("R01_mobile_session") do
  adv_request(format: :html, params: {}, session: { mobile_view: true }, tag: "mobile_plain")
  adv_request(format: :html, params: { conversation_id: "1" }, session: { mobile_view: true }, tag: "mobile_cid1")
end
