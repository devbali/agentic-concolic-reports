# C09 — a comment MENTIONING dave, who has NO profiles row: mentioned_people.as_api_response
# -> Person#name -> fix_profile. Also the mobile variant (person_image_link's profile.nil?
# guard vs person_link's name). Separate process (JVM crash risk).
require_relative "_common"
adv_setup!("C09_noprofile_mention"); seed_people!(dave: true, dave_profile: false); seed_batch_post!
CE.insert("comments", id: 391, commentable_id: 100, commentable_type: "Post", author_id: 1, guid: "cguid391", text: "hi @{dave@remote.example}")
CE.insert("mentions", id: 950, mentions_container_id: 391, mentions_container_type: "Comment", person_id: 4)
CONCRETE_SCENARIOS = adv_scenario("C09_noprofile_mention") do
  adv_request(post_id: "100", format: :json, tag: "json_noprofile_mention")
end
