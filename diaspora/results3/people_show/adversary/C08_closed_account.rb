# C08 — CLOSED ACCOUNT: alice (signed in) views carol@remote.example, whose
# people.closed_account = 't'. find_person raises Diaspora::AccountClosed ->
# rescue -> redirect_back(fallback_location: ...) / head :gone (410).
# Corpus terminal census: does any dump carry AccountClosed / 410? The anon
# corpus explored carol (closed) handles... they had a closed person? The
# batch's seed had carol closed per AGENT_RUN? Let me MEASURE the real arm.
require_relative "_common"

adv_setup!("C08_closed_account")
seed_people!(dave: true, p13: {first_name: "Carol", last_name: "C"})

CONCRETE_SCENARIOS = adv_scenario("C08_closed_account") do
  adv_request(username: "carol@remote.example", format: "html", signed_in: true, tag: "C08")
end