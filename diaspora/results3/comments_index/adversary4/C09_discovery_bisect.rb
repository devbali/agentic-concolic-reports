# C09 — ISOLATED. Round 3 recorded three different JVM aborts on the
# `Person#fix_profile` -> Discovery path and concluded the standing "network
# wall" explanation was unestablished. This manifest bisects it OUTSIDE the
# render pipeline: each step prints START before it runs, so whichever step is
# last in the log is the one that killed the JVM. No HTTP request is made by
# the app here; only real gem/app calls.
require_relative "_common4"
adv_setup!("C09_discovery_bisect")
seed_core!

# a person with NO profiles row (people.owner_id/profile has no FK either way)
CE.insert("people", id: 40, guid: "daveguid000000040", diaspora_handle: "dave@127.0.0.1",
          serialized_public_key: "K40", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("people", id: 41, guid: "eveguid0000000041", diaspora_handle: "eve@",
          serialized_public_key: "K41", owner_id: nil, closed_account: false, fetch_status: 0)

CONCRETE_SCENARIOS = adv_scenario("C09-discovery-bisect") do
  adv_probe("00-baseline-find") { Person.find(40).diaspora_handle }
  adv_probe("01-profile-nil") { Person.find(40).profile.inspect }
  adv_probe("02-discovery-const") { DiasporaFederation::Discovery::Discovery.name }
  adv_probe("03-discovery-new-ip") { DiasporaFederation::Discovery::Discovery.new("dave@127.0.0.1").diaspora_id }
  adv_probe("04-discovery-new-nodomain") { DiasporaFederation::Discovery::Discovery.new("eve@").diaspora_id }
  adv_probe("05-faraday-adapter") { Faraday.default_adapter.inspect }
  adv_probe("06-httpclient-connection") { DiasporaFederation::HttpClient.connection.class.name }
  adv_probe("07-httpclient-get-loopback") { DiasporaFederation::HttpClient.get("https://127.0.0.1:1/x").status }
  adv_probe("08-fetch-and-save-nodomain") { DiasporaFederation::Discovery::Discovery.new("eve@").fetch_and_save }
  adv_probe("09-fetch-and-save-ip") { DiasporaFederation::Discovery::Discovery.new("dave@127.0.0.1").fetch_and_save }
  adv_probe("10-fix-profile-nodomain") { Person.find(41).send(:fix_profile) }
  adv_probe("11-fix-profile-ip") { Person.find(40).send(:fix_profile) }
  adv_probe("12-person-name") { Person.find(40).name }
  adv_probe("13-reload") { Person.find(40).reload.id }
end
