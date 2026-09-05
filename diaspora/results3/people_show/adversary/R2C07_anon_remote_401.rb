# C07 — anon REMOTE profile: anonymous viewing bob (remote person).
# authenticate_if_remote_profile! -> authenticate_user! -> real warden
# (anon) -> throw :warden -> 401. BOUNDARY observation: the corpus's remote
# anon runs (bob handle) never reached the real app's 401 gate — their
# StubWarden returned a user unconditionally. This documents what the real
# app does at the entrypoint's front door. Boundary-stage item only (the
# _auth_boundary policy owns it), filed as an observation, not an endpoint
# win.
require_relative "_common"

adv_setup!("R2C07_anon_remote_401")
seed_people!(dave: true, p12: {image_url: "http://remote.example/bob.png"})

CONCRETE_SCENARIOS = adv_scenario("C07_anon_remote_401") do
  adv_request(username: "bob@remote.example", format: "html", signed_in: false, tag: "C07")
end