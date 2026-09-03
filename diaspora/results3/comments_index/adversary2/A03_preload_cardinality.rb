# A03 — RE-VERIFY near-miss N2 (per-row `= $(…)` notes vs the real bulk
# `IN (…)` preload, and the preload mock's RETURN KIND) with THREE DISTINCT
# comment authors, and N3 (a mentions row whose person_id has no people row).
# Also: a post with ZERO comments (empty-collection state) and a comment with
# THREE mentions.
require_relative "_common2"
adv_setup!("A03_preload_cardinality")
seed_people!(extra_people: true)

# post 110: three comments by three distinct authors (people.id IN (2,1,5))
CE.insert("posts", id: 110, author_id: 2, guid: "postguid1100000001", type: "StatusMessage",
          text: "public", public: true, comments_count: 3)
CE.insert("comments", id: 310, commentable_id: 110, commentable_type: "Post",
          author_id: 2, guid: "cguid310", text: "by bob")
CE.insert("comments", id: 311, commentable_id: 110, commentable_type: "Post",
          author_id: 1, guid: "cguid311", text: "by alice")
CE.insert("comments", id: 312, commentable_id: 110, commentable_type: "Post",
          author_id: 5, guid: "cguid312", text: "by erin")

# post 111: ZERO comments
CE.insert("posts", id: 111, author_id: 2, guid: "postguid1110000001", type: "StatusMessage",
          text: "public empty", public: true, comments_count: 0)

# post 112: one comment with THREE mentions -> people.id IN (2,5,6)
CE.insert("posts", id: 112, author_id: 2, guid: "postguid1120000001", type: "StatusMessage",
          text: "public", public: true, comments_count: 1)
CE.insert("comments", id: 313, commentable_id: 112, commentable_type: "Post",
          author_id: 2, guid: "cguid313",
          text: "hi @{Bob; bob@remote.example} @{Erin; erin@other.example} @{Frank; frank@third.example}")
CE.insert("mentions", id: 910, mentions_container_id: 313, mentions_container_type: "Comment", person_id: 2)
CE.insert("mentions", id: 911, mentions_container_id: 313, mentions_container_type: "Comment", person_id: 5)
CE.insert("mentions", id: 912, mentions_container_id: 313, mentions_container_type: "Comment", person_id: 6)

# post 113: a DANGLING mentions.person_id (999 — no people row); mentions has no FK
CE.insert("posts", id: 113, author_id: 2, guid: "postguid1130000001", type: "StatusMessage",
          text: "public", public: true, comments_count: 1)
CE.insert("comments", id: 314, commentable_id: 113, commentable_type: "Post",
          author_id: 2, guid: "cguid314", text: "hi @{Ghost; ghost@nowhere.example}")
CE.insert("mentions", id: 913, mentions_container_id: 314, mentions_container_type: "Comment", person_id: 999)

CONCRETE_SCENARIOS = adv_scenario("A03-preload-cardinality") do
  adv_request(post_id: "110", format: :json, tag: "A03_three_authors_json")
  adv_request(post_id: "110", format: :mobile, tag: "A03_three_authors_mobile")
  adv_request(post_id: "111", format: :json, tag: "A03_empty_json")
  adv_request(post_id: "111", format: :mobile, tag: "A03_empty_mobile")
  adv_request(post_id: "112", format: :json, tag: "A03_three_mentions_json")
  adv_request(post_id: "112", format: :mobile, tag: "A03_three_mentions_mobile")
  adv_request(post_id: "113", format: :json, tag: "A03_dangling_mention_json")
end
