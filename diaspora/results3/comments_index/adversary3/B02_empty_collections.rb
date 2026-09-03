# B02 — EMPTY collections: a post with zero comments, and a comment with zero
# mentions. `rows_mock` (targets.rb:389-415) calls `emit_includes_preloads`
# BEFORE it knows the list length, so the corpus mints the `people` / `profiles`
# preload notes even in the 86 json dumps where `len(records_1_rows) == 0` and
# in every dump where the mentions relation is empty. Real Rails preloads on the
# LOADED records: zero records -> zero preload statements.
require_relative "_common3"
adv_setup!("B02_empty_collections")
seed_core!

# 210: NO comments at all
CE.insert("posts", id: 210, author_id: 2, guid: "postguid2100000001", type: "StatusMessage",
          text: "p210", public: true, comments_count: 0)
# 211: one comment, NO mentions row
CE.insert("posts", id: 211, author_id: 2, guid: "postguid2110000001", type: "StatusMessage",
          text: "p211", public: true, comments_count: 1)
CE.insert("comments", id: 310, commentable_id: 211, commentable_type: "Post", author_id: 2,
          guid: "cguid310", text: "a comment with no mentions and no links")
# 212: private, shared with alice, NO comments (signed-in empty state)
CE.insert("posts", id: 212, author_id: 2, guid: "postguid2120000001", type: "StatusMessage",
          text: "p212", public: false, comments_count: 0)
CE.insert("share_visibilities", id: 420, shareable_id: 212, shareable_type: "Post", user_id: 9, hidden: false)

CONCRETE_SCENARIOS = adv_scenario("B02-empty-collections") do
  adv_request(post_id: "210", format: :json,   tag: "B02_nocomments_json")
  adv_request(post_id: "210", format: :mobile, tag: "B02_nocomments_mobile")
  adv_request(post_id: "211", format: :json,   tag: "B02_nomentions_json")
  adv_request(post_id: "211", format: :mobile, tag: "B02_nomentions_mobile")
  adv_request(post_id: "210", format: :json,   signed_in: true, tag: "B02_nocomments_json_auth")
  adv_request(post_id: "212", format: :json,   signed_in: true, tag: "B02_vis_nocomments_json_auth")
  adv_request(post_id: "212", format: :mobile, signed_in: true, tag: "B02_vis_nocomments_mobile_auth")
  adv_request(post_id: "postguid2100000001", format: :json, tag: "B02_nocomments_byguid_json")
end
