# C04 — early-exit controls, anonymous: html (templateless), private post (NonPublic ->
# rescue_from -> authenticate_user! -> warden throw), nonexistent id, guid key (hit + miss),
# odd post_id shapes ("", "abc", array, 16-char numeric string), public NULL post.
require_relative "_common"
adv_setup!("C04_controls"); seed_people!; seed_batch_post!
CE.insert("posts", id: 106, author_id: 2, guid: "privguid000000106", type: "StatusMessage",
          text: "private", public: 0, comments_count: 1)
CE.insert("comments", id: 320, commentable_id: 106, commentable_type: "Post", author_id: 2, guid: "cguid320", text: "secret")
# posts.public is NOT NULL in the schema (first attempt aborted on the INSERT) -> the
# `post.public?` nil branch is unreachable by schema; dropped.
CONCRETE_SCENARIOS = adv_scenario("C04_controls") do
  adv_request(post_id: "100", format: :html, tag: "html_100")
  adv_request(post_id: "106", format: :json, tag: "json_private_106")
  adv_request(post_id: "999", format: :json, tag: "json_missing_999")
  adv_request(post_id: "postguid100000001", format: :json, tag: "json_guid_hit")
  adv_request(post_id: "nosuchguid0000000", format: :json, tag: "json_guid_miss")
  adv_request(post_id: "privguid000000106", format: :json, tag: "json_guid_private")
  adv_request(post_id: "", format: :json, tag: "json_empty")
  adv_request(post_id: "abc", format: :json, tag: "json_abc")
  adv_request(post_id: "0000000000000100", format: :json, tag: "json_16digits")
  adv_request(post_id: ["100", "101"], format: :json, tag: "json_array")
end
