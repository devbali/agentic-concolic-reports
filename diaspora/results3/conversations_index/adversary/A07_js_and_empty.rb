# A07 — ZERO conversations (count == 0 branch) in html/json, and the
# declared-but-templateless :js format (respond_to :html, :mobile, :json, :js;
# responders' to_js = default_render -> MissingTemplate).
require_relative "_common"
adv_setup!("A07_js_and_empty"); seed_people!
CONCRETE_SCENARIOS = adv_scenario("A07_js_and_empty") do
  adv_request(format: :html, params: {})
  adv_request(format: :json, params: {})
  begin
    adv_request(format: :js, params: {})
  rescue StandardError => e
    warn "[adversary] js format raised #{e.class}: #{e.message[0, 120]}"
  end
end
