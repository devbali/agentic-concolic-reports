# C07 — signed-in edges: alice BLOCKS bob (blocks row) and bob authored comments; likes on
# comments; visibility row hidden; alice's own PUBLIC post (vis miss -> author hit);
# public post by bob with no visibility (vis miss, author miss -> public hit) by id and guid;
# missing id; guid miss; alice's language "pl" (inflected locale: set_grammatical_gender
# reads current_user.gender -> profile BEFORE the action); session a_ids.
require_relative "_common"
adv_setup!("C07_auth_edges"); seed_people!(alice_lang: "pl"); seed_batch_post!
CE.insert("blocks", id: 600, user_id: 9, person_id: 2)
CE.insert("posts", id: 103, author_id: 1, guid: "postguid103000001", type: "StatusMessage", text: "alice public", public: 1, comments_count: 1)
CE.insert("comments", id: 380, commentable_id: 103, commentable_type: "Post", author_id: 2, guid: "cguid380", text: "blocked bob comments")
CE.insert("likes", id: 501, positive: 1, target_id: 380, target_type: "Comment", author_id: 1, guid: "likeguid501")
CE.insert("likes", id: 502, positive: 1, target_id: 300, target_type: "Comment", author_id: 1, guid: "likeguid502")
CE.insert("posts", id: 104, author_id: 2, guid: "postguid104000001", type: "StatusMessage", text: "bob limited hidden", public: 0, comments_count: 1)
CE.insert("share_visibilities", id: 410, shareable_id: 104, shareable_type: "Post", user_id: 9, hidden: 1)
CE.insert("comments", id: 381, commentable_id: 104, commentable_type: "Post", author_id: 2, guid: "cguid381", text: "hidden vis comment")
CONCRETE_SCENARIOS = adv_scenario("C07_auth_edges") do
  adv_request(post_id: "100", format: :json, signed_in: true, session: { a_ids: ["1"] }, tag: "auth_json_public_100")
  adv_request(post_id: "postguid100000001", format: :json, signed_in: true, tag: "auth_json_public_guid")
  adv_request(post_id: "103", format: :json, signed_in: true, tag: "auth_json_own_public_103")
  adv_request(post_id: "postguid103000001", format: :json, signed_in: true, tag: "auth_json_own_public_guid")
  adv_request(post_id: "104", format: :json, signed_in: true, tag: "auth_json_hidden_vis_104")
  adv_request(post_id: "999", format: :json, signed_in: true, tag: "auth_json_missing")
  adv_request(post_id: "nosuchguid0000000", format: :json, signed_in: true, tag: "auth_json_guid_miss")
  adv_request(post_id: "100", format: :html, signed_in: true, tag: "auth_html_100")
  adv_request(post_id: "103", format: :mobile, signed_in: true, tag: "auth_mobile_103")
end
