# C01 — ROUND-3 WIN RE-VERIFICATION on the regenerated 46-node corpus.
#  (a) W3-1/M-3: a dangling `mentions.person_id` must render `[null]` json /
#      500 mobile and issue NO `profiles` read after the mention preload.
#  (b) W3-2/M-4: an empty comments collection must issue EXACTLY the post
#      finder plus the comments SELECT and nothing else.
require_relative "_common4"
adv_setup!("C01_dangling_and_empty")
seed_core!

# --- (a) dangling mention -------------------------------------------------
CE.insert("posts", id: 300, author_id: 2, guid: "postguid3000000001", type: "StatusMessage",
          text: "p300", public: true, comments_count: 1)
CE.insert("comments", id: 400, commentable_id: 300, commentable_type: "Post", author_id: 2,
          guid: "cguid400", text: "hello @{Ghost; ghost@remote.example} goodbye")
CE.insert("mentions", id: 800, mentions_container_id: 400, mentions_container_type: "Comment", person_id: 999)

# control: same shape, live mention
CE.insert("posts", id: 301, author_id: 2, guid: "postguid3010000001", type: "StatusMessage",
          text: "p301", public: true, comments_count: 1)
CE.insert("comments", id: 401, commentable_id: 301, commentable_type: "Post", author_id: 2,
          guid: "cguid401", text: "hello @{Bob; bob@remote.example} goodbye")
CE.insert("mentions", id: 801, mentions_container_id: 401, mentions_container_type: "Comment", person_id: 2)

# mixed: one live + one dangling
CE.insert("posts", id: 302, author_id: 2, guid: "postguid3020000001", type: "StatusMessage",
          text: "p302", public: true, comments_count: 1)
CE.insert("comments", id: 402, commentable_id: 302, commentable_type: "Post", author_id: 2,
          guid: "cguid402", text: "cc @{Bob; bob@remote.example} and @{Ghost; ghost@remote.example}")
CE.insert("mentions", id: 802, mentions_container_id: 402, mentions_container_type: "Comment", person_id: 2)
CE.insert("mentions", id: 803, mentions_container_id: 402, mentions_container_type: "Comment", person_id: 999)

# ALL mentions dangling (two of them) — bulk IN over a fully missing set
CE.insert("posts", id: 303, author_id: 2, guid: "postguid3030000001", type: "StatusMessage",
          text: "p303", public: true, comments_count: 1)
CE.insert("comments", id: 403, commentable_id: 303, commentable_type: "Post", author_id: 2,
          guid: "cguid403", text: "cc @{G1; g1@remote.example} and @{G2; g2@remote.example}")
CE.insert("mentions", id: 804, mentions_container_id: 403, mentions_container_type: "Comment", person_id: 997)
CE.insert("mentions", id: 805, mentions_container_id: 403, mentions_container_type: "Comment", person_id: 998)

# --- (b) empty collections ------------------------------------------------
CE.insert("posts", id: 310, author_id: 2, guid: "postguid3100000001", type: "StatusMessage",
          text: "p310 no comments", public: true, comments_count: 0)
CE.insert("posts", id: 311, author_id: 2, guid: "postguid3110000001", type: "StatusMessage",
          text: "p311 one comment no mentions", public: true, comments_count: 1)
CE.insert("comments", id: 410, commentable_id: 311, commentable_type: "Post", author_id: 2,
          guid: "cguid410", text: "a plain comment with no mentions and no links")
# private post shared with alice, zero comments
CE.insert("posts", id: 312, author_id: 2, guid: "postguid3120000001", type: "StatusMessage",
          text: "p312 private shared", public: false, comments_count: 0)
CE.insert("share_visibilities", id: 700, user_id: 9, shareable_id: 312, shareable_type: "Post")

CONCRETE_SCENARIOS = adv_scenario("C01-dangling-and-empty") do
  adv_request(post_id: "300", format: :json,   tag: "C01_dangle_json")
  adv_request(post_id: "300", format: :mobile, tag: "C01_dangle_mobile")
  adv_request(post_id: "301", format: :json,   tag: "C01_live_json")
  adv_request(post_id: "301", format: :mobile, tag: "C01_live_mobile")
  adv_request(post_id: "302", format: :json,   tag: "C01_mixed_json")
  adv_request(post_id: "302", format: :mobile, tag: "C01_mixed_mobile")
  adv_request(post_id: "303", format: :json,   tag: "C01_alldangle_json")
  adv_request(post_id: "303", format: :mobile, tag: "C01_alldangle_mobile")
  adv_request(post_id: "300", format: :json, signed_in: true, tag: "C01_dangle_json_auth")
  adv_request(post_id: "310", format: :json,   tag: "C01_empty_json")
  adv_request(post_id: "310", format: :mobile, tag: "C01_empty_mobile")
  adv_request(post_id: "postguid3100000001", format: :json, tag: "C01_empty_json_byguid")
  adv_request(post_id: "310", format: :json, signed_in: true, tag: "C01_empty_json_auth")
  adv_request(post_id: "311", format: :json,   tag: "C01_nomentions_json")
  adv_request(post_id: "311", format: :mobile, tag: "C01_nomentions_mobile")
  adv_request(post_id: "312", format: :json, signed_in: true, tag: "C01_vis_empty_json_auth")
  adv_request(post_id: "312", format: :mobile, signed_in: true, tag: "C01_vis_empty_mobile_auth")
end
