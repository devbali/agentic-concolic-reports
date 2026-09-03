# C08 — a comment whose AUTHOR (dave) has NO profiles row: Person#name -> fix_profile ->
# Discovery#fetch_and_save (network) -> reload. Anon json. Separate process (JVM crash risk).
require_relative "_common"
adv_setup!("C08_noprofile_author"); seed_people!(dave: true, dave_profile: false); seed_batch_post!
CE.insert("comments", id: 390, commentable_id: 100, commentable_type: "Post", author_id: 4, guid: "cguid390", text: "no profile author")
CONCRETE_SCENARIOS = adv_scenario("C08_noprofile_author") do
  adv_request(post_id: "100", format: :json, tag: "json_noprofile_author")
end
