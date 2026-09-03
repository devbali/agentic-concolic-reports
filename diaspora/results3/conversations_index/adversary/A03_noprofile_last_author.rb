# A03 — the LAST AUTHOR (bob) has NO profiles row. _conversation.haml:34
# `conversation.last_author.name` -> Person#name -> profile.nil? -> fix_profile
# -> DiasporaFederation::Discovery::Discovery#fetch_and_save (network wall
# family declared as a target in TARGET_FUNCTIONS section 3; traced here as an
# extra depth-0 target so the probe can record it).
require_relative "_common"
adv_setup!("A03_noprofile_last_author"); seed_people!(bob_profile: false); seed_batch_conversations!
# make bob the last author of conversation 1 (swap message order)
CE.insert("messages", id: 33, conversation_id: 1, author_id: 2, guid: "msgguid3", text: "bob again, last")
CONCRETE_SCENARIOS = adv_scenario("A03_noprofile_last_author",
  targets: adv_targets([[DiasporaFederation::Discovery::Discovery, :fetch_and_save], [Person, :fix_profile]])) do
  adv_request(format: :html, params: {})
end
