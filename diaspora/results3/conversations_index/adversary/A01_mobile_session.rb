# A01 — MOBILE format via the app's own session switch (ApplicationController#mobile_switch:
# session[:mobile_view] == true && html -> request.format = :mobile). Batch fixtures unchanged.
require_relative "_common"
adv_setup!("A01_mobile_session"); seed_people!; seed_batch_conversations!
CONCRETE_SCENARIOS = adv_scenario("A01_mobile_session") do
  adv_request(format: :html, params: {}, session: { mobile_view: true })
  adv_request(format: :html, params: { conversation_id: "1" }, session: { mobile_view: true })
end
