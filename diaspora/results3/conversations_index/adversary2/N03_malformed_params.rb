# N03 — parameter / header / format combinations the corpus fixes: a HASH
# conversation_id (nested where on a bogus table), page "0" / "abc" / "-1" /
# array (will_paginate InvalidPage), a SQL-ish cid string, a fractional cid,
# json with the mobile session flag, explicit :mobile without a cid, json via
# the Accept header, html with the mobile device header but session
# mobile_view=false, and a tablet user agent.
require_relative "_common"
adv_setup!("N03_malformed_params"); seed_people!; seed_batch_conversations!
UA_IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1"
UA_IPAD   = "Mozilla/5.0 (iPad; CPU OS 12_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1"
CONCRETE_SCENARIOS = adv_scenario("N03_malformed_params") do
  adv_request_rescued(format: :html, params: { conversation_id: { foo: "bar" } }, tag: "cid_hash")
  adv_request_rescued(format: :html, params: { page: "0" }, tag: "page0")
  adv_request_rescued(format: :html, params: { page: "abc" }, tag: "pageabc")
  adv_request_rescued(format: :html, params: { page: "-1" }, tag: "pageneg")
  adv_request_rescued(format: :html, params: { page: ["2"] }, tag: "pagearray")
  adv_request_rescued(format: :html, params: { conversation_id: "1 OR 1=1" }, tag: "cid_sqlish")
  adv_request_rescued(format: :html, params: { conversation_id: "1.5" }, tag: "cid_frac")
  adv_request_rescued(format: :json, params: {}, session: { mobile_view: true }, tag: "json_mobilesession")
  adv_request_rescued(format: :mobile, params: {}, tag: "fmt_mobile_plain")
  adv_request_rescued(format: nil, params: {}, headers: { "Accept" => "application/json" }, tag: "accept_json")
  adv_request_rescued(format: :html, params: {}, session: { mobile_view: false },
                      headers: { "X_MOBILE_DEVICE" => "iPhone", "User-Agent" => UA_IPHONE }, tag: "hdr_session_false")
  adv_request_rescued(format: :html, params: {}, headers: { "User-Agent" => UA_IPAD }, tag: "tablet_ua")
end
