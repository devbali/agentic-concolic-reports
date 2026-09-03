# C05 — STI subclasses: a public Reshare whose root is missing, a Reshare with a root,
# and comments on them; anon json + mobile, signed-in json.
require_relative "_common"
adv_setup!("C05_sti"); seed_people!; seed_batch_post!
CE.insert("posts", id: 110, author_id: 1, guid: "reshareguid000110", type: "Reshare",
          root_guid: "gone-root-guid-000", public: 1, comments_count: 1)
CE.insert("posts", id: 111, author_id: 2, guid: "reshareguid000111", type: "Reshare",
          root_guid: "postguid100000001", public: 1, comments_count: 1)
CE.insert("comments", id: 330, commentable_id: 110, commentable_type: "Post", author_id: 2, guid: "cguid330", text: "on a rootless reshare")
CE.insert("comments", id: 331, commentable_id: 111, commentable_type: "Post", author_id: 1, guid: "cguid331", text: "on a reshare @{bob@remote.example}")
CE.insert("mentions", id: 931, mentions_container_id: 331, mentions_container_type: "Comment", person_id: 2)
CONCRETE_SCENARIOS = adv_scenario("C05_sti") do
  adv_request(post_id: "110", format: :json, tag: "json_reshare_noroot")
  adv_request(post_id: "111", format: :json, tag: "json_reshare_root")
  adv_request(post_id: "110", format: :mobile, tag: "mobile_reshare_noroot")
  adv_request(post_id: "111", format: :json, signed_in: true, tag: "auth_json_reshare")
end
