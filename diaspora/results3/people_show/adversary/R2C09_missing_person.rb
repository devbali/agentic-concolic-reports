# C09 — MISSING PERSON: anonymous views a diaspora_handle with no people row.
# find_person raises RecordNotFound -> rescue -> render 404 (public/404 in
# with_header? the rescue is `rescue_from ActiveRecord::RecordNotFound` -> 404).
# Real arm: people.diaspora_handle query -> 0 rows -> 404. The corpus's
# "missing" terminal: does the corpus model 404 from a NON-matching handle
# (their missing stayed at 64 nodes — handle-not-found was a fixed seed)? The
# corpus's finder `Person.where(diaspora_handle:).first` note exists; the
# NOT-FOUND arm -> rescues to 404 — check if a corpus terminal carries it.
require_relative "_common"

adv_setup!("R2C09_missing_person")
seed_people!(dave: true)

CONCRETE_SCENARIOS = adv_scenario("C09_missing_person") do
  adv_request(username: "nobody@nowhere.example", format: "html", signed_in: false, tag: "C09")
end