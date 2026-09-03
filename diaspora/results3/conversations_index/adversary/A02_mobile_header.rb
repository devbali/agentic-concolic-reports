# A02 — MOBILE format via mobile-fu's device header (X_MOBILE_DEVICE is what
# Rack::MobileDetect sets from a phone User-Agent; has_mobile_fu's
# set_request_format then switches html -> mobile) and via an explicit
# format: :mobile (Mime alias registered by mobile-fu; respond_to :mobile is
# declared on the controller). Batch fixtures unchanged.
require_relative "_common"
adv_setup!("A02_mobile_header"); seed_people!; seed_batch_conversations!
CONCRETE_SCENARIOS = adv_scenario("A02_mobile_header") do
  adv_request(format: :html, params: {}, headers: { "X_MOBILE_DEVICE" => "iPhone",
    "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1" })
  adv_request(format: :mobile, params: { conversation_id: "1" })
end
