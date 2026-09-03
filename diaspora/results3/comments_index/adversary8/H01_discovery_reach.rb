# ADVERSARY ROUND 8 / H01 — is `Person#fix_profile` reachable by a REAL run?
#
# completion_config.json waives the `ActiveRecord::Base.reload` H6 family on the
# argument that reload's only call site (Person#fix_profile, person.rb:371-375)
# runs only after `DiasporaFederation::Discovery::Discovery#fetch_and_save`
# returns, and that EVERY path there aborts the JVM on the first FFI call
# (typhoeus -> Ethon -> libcurl through JFFI; DISCIPLINE 12).
#
# The gem's fetch_and_save (diaspora_federation-0.2.6 discovery/discovery.rb:19)
# is  validate_diaspora_id -> webfinger -> get(url) -> HttpClient.get ->
# Faraday::Connection#get, and Faraday parses the URL with URI.parse BEFORE the
# adapter runs. `domain` is `diaspora_id.split("@")[1]` and diaspora_handle is a
# plain `people` column with no format constraint, so a fixture handle whose
# domain contains a character URI rejects makes Faraday raise
# URI::InvalidURIError in pure Ruby -- BEFORE any curl call.
#
# PROBES ONLY (no HTTP request): one JRuby, crash-isolated, ordered
# safest-first so a native abort names the probe it died in.
require_relative "_common8"

CONCRETE_SCENARIOS = adv_scenario("H01_discovery_reach") do
  adv_probe("00 ruby URI.parse space-in-host") { URI.parse("https://ex ample.com/x") }
  adv_probe("01 ruby URI.parse bracket-in-host") { URI.parse("https://ex[ample.com/x") }
  adv_probe("02 Faraday::Utils.URI space") { Faraday::Utils.URI("https://ex ample.com/x") }
  adv_probe("03 Faraday default_adapter") { Faraday.default_adapter }
  adv_probe("04 Discovery.new clean_diaspora_id") {
    DiasporaFederation::Discovery::Discovery.new(" Acct:Ghost@Ex ample.com ").diaspora_id
  }
  adv_probe("05 webfinger_http_fallback") { DiasporaFederation.webfinger_http_fallback }

  # the real thing: a handle whose DOMAIN cannot be parsed as a URI host
  adv_probe("06 fetch_and_save space-in-domain") {
    DiasporaFederation::Discovery::Discovery.new("ghost@ex ample.com").fetch_and_save
  }
  adv_probe("07 fetch_and_save bracket-in-domain") {
    DiasporaFederation::Discovery::Discovery.new("ghost@ex[ample.com").fetch_and_save
  }
  adv_probe("08 fetch_and_save no-at-sign") {
    DiasporaFederation::Discovery::Discovery.new("ghostnoat").fetch_and_save
  }

  # now the same thing through the APP: a real people row with NO profiles row
  # and a URI-hostile handle. Person#name -> profile.nil? -> fix_profile.
  seed_core!
  CE.insert("people", id: 7, guid: "ghostguid00000007", diaspora_handle: "ghost@ex ample.com",
            serialized_public_key: "K7", owner_id: nil, closed_account: false, fetch_status: 0)
  adv_probe("09 Person(7).profile") { Person.find(7).profile.inspect }
  adv_probe("10 Person(7).name -> fix_profile") { Person.find(7).name }
  adv_probe("11 Person(7).as_api_response(:backbone)") { Person.find(7).as_api_response(:backbone) }

  # BASELINE, deliberately last: a well-formed handle must reach the network and
  # (per DISCIPLINE 12) abort the JVM. If this one aborts and 06-11 did not, the
  # waiver's premise "every path aborts" is false.
  adv_probe("99 BASELINE fetch_and_save well-formed handle") {
    DiasporaFederation::Discovery::Discovery.new("ghost@nowhere.example").fetch_and_save
  }
end
