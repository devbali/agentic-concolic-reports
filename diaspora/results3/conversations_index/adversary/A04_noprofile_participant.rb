# A04 — a PARTICIPANT who is never an author (carol) has NO profiles row:
# people_helper.rb:37 / :43 `return "" if person.profile.nil?` guards
# (person_image_tag in the sidebar, person_image_link in _show.haml).
require_relative "_common"
adv_setup!("A04_noprofile_participant"); seed_people!(carol_profile: false); seed_batch_conversations!
CONCRETE_SCENARIOS = adv_scenario("A04_noprofile_participant") do
  adv_request(format: :html, params: {})
  adv_request(format: :html, params: { conversation_id: "1" })
  adv_request(format: :json, params: { conversation_id: "1" })
end
