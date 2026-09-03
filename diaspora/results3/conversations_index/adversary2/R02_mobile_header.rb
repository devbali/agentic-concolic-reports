# R02 (= round-1 A02): MOBILE via mobile-fu's device header and via an explicit format: :mobile.
require_relative "_common"
adv_setup!("R02_mobile_header"); seed_people!; seed_batch_conversations!
CONCRETE_SCENARIOS = adv_scenario("R02_mobile_header") do
  adv_request(format: :html, params: {}, headers: { "X_MOBILE_DEVICE" => "iPhone",
    "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1" }, tag: "hdr_plain")
  adv_request(format: :mobile, params: { conversation_id: "1" }, tag: "fmt_mobile_cid1")
end
