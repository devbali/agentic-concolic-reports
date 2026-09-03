# R03 (= round-1 A03): the LAST AUTHOR (bob) has NO profiles row ->
# _conversation.haml:34 last_author.name -> Person#name -> fix_profile ->
# Discovery#fetch_and_save (network) -> reload. Round 1 aborted the JVM here.
require_relative "_common"
adv_setup!("R03_noprofile_last_author"); seed_people!(bob_profile: false); seed_batch_conversations!
CE.insert("messages", id: 33, conversation_id: 1, author_id: 2, guid: "msgguid3", text: "bob again, last")
CONCRETE_SCENARIOS = adv_scenario("R03_noprofile_last_author",
  targets: adv_targets([[DiasporaFederation::Discovery::Discovery, :fetch_and_save], [Person, :fix_profile],
                        [ActiveRecord::Persistence, :reload]])) do
  adv_request_rescued(format: :html, params: {}, tag: "noprofile_lastauthor")
end
