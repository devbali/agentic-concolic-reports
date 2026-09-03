# R07 (= round-1 A07): ZERO conversations in html/json/mobile, and the templateless :js format.
require_relative "_common"
adv_setup!("R07_js_and_empty"); seed_people!
CONCRETE_SCENARIOS = adv_scenario("R07_js_and_empty") do
  adv_request(format: :html, params: {}, tag: "html_empty")
  adv_request(format: :json, params: {}, tag: "json_empty")
  adv_request(format: :html, params: {}, session: { mobile_view: true }, tag: "mobile_empty")
  adv_request_rescued(format: :js, params: {}, tag: "js")
end
