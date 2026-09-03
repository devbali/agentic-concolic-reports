# R09 (= round-1 A09): inflected locale (pl) -> set_grammatical_gender reads the principal's profile before the action.
require_relative "_common"
adv_setup!("R09_lang_pl"); seed_people!(alice_lang: "pl"); seed_batch_conversations!
CONCRETE_SCENARIOS = adv_scenario("R09_lang_pl") do
  adv_request(format: :json, params: {}, tag: "json_plain")
  adv_request(format: :html, params: {}, tag: "html_plain")
  adv_request(format: :html, params: {}, session: { mobile_view: true }, tag: "mobile_plain")
end
