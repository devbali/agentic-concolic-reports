# A08 — the missing-`profiles` MENTIONED-PERSON path (round-1 C09). ISOLATED.
require_relative "_common2"
adv_setup!("A08_noprofile_mention")
seed_people!(dave: true, dave_profile: false)
CE.insert("posts", id: 141, author_id: 2, guid: "postguid1410000001", type: "StatusMessage",
          text: "public", public: true, comments_count: 1)
CE.insert("comments", id: 351, commentable_id: 141, commentable_type: "Post",
          author_id: 2, guid: "cguid351", text: "hi @{Dave; dave@remote.example}")
CE.insert("mentions", id: 930, mentions_container_id: 351, mentions_container_type: "Comment", person_id: 4)

CONCRETE_SCENARIOS = adv_scenario("A08-noprofile-mention") do
  adv_request(post_id: "141", format: :json, tag: "A08_json")
end
