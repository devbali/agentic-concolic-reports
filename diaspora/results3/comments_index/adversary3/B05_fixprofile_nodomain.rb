# B05 — ISOLATED (crash risk). Same as B04 but the handle has NO domain at all
# (`Discovery#domain` -> nil), so the webfinger URL is malformed and the gem
# fails before any socket work. Second, independent way to reach the discovery
# wall without the native abort.
require_relative "_common3"
adv_setup!("B05_fixprofile_nodomain")
seed_core!
CE.insert("people", id: 4, guid: "daveguid000000004", diaspora_handle: "dave@",
          serialized_public_key: "K4", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("posts", id: 261, author_id: 2, guid: "postguid2610000001", type: "StatusMessage",
          text: "p261", public: true, comments_count: 1)
CE.insert("comments", id: 361, commentable_id: 261, commentable_type: "Post", author_id: 4,
          guid: "cguid361", text: "a comment by an author with no profiles row (no domain)")

CONCRETE_SCENARIOS = adv_scenario("B05-fixprofile-nodomain") do
  adv_request(post_id: "261", format: :json, tag: "B05_noprofile_author_json")
end
