# C06 — comment cardinality: 0 comments, 1 comment, 12 comments by one author, a comment
# with three mentions (local/remote/closed), a comment with a mentions row pointing at a
# NONEXISTENT person id, and a comment with an empty mentions set but mention markup.
require_relative "_common"
adv_setup!("C06_cardinality"); seed_people!
CE.insert("posts", id: 120, author_id: 2, guid: "postguid120000001", type: "StatusMessage", text: "zero", public: 1, comments_count: 0)
CE.insert("posts", id: 121, author_id: 2, guid: "postguid121000001", type: "StatusMessage", text: "one", public: 1, comments_count: 1)
CE.insert("comments", id: 340, commentable_id: 121, commentable_type: "Post", author_id: 1, guid: "cguid340", text: "single")
CE.insert("posts", id: 122, author_id: 1, guid: "postguid122000001", type: "StatusMessage", text: "many", public: 1, comments_count: 12)
(0...12).each do |i|
  CE.insert("comments", id: 350 + i, commentable_id: 122, commentable_type: "Post", author_id: 2, guid: "cguid#{350 + i}",
            text: "comment number #{i}", likes_count: i)
end
CE.insert("comments", id: 370, commentable_id: 122, commentable_type: "Post", author_id: 1, guid: "cguid370",
          text: "@{alice@localhost} @{bob@remote.example} @{carol@remote.example} three")
CE.insert("mentions", id: 940, mentions_container_id: 370, mentions_container_type: "Comment", person_id: 1)
CE.insert("mentions", id: 941, mentions_container_id: 370, mentions_container_type: "Comment", person_id: 2)
CE.insert("mentions", id: 942, mentions_container_id: 370, mentions_container_type: "Comment", person_id: 3)
CE.insert("comments", id: 371, commentable_id: 122, commentable_type: "Post", author_id: 1, guid: "cguid371",
          text: "@{nobody@nowhere.example} markup without a mentions row")
CE.insert("posts", id: 123, author_id: 1, guid: "postguid123000001", type: "StatusMessage", text: "dangling", public: 1, comments_count: 1)
CE.insert("comments", id: 372, commentable_id: 123, commentable_type: "Post", author_id: 1, guid: "cguid372",
          text: "@{gone@remote.example} dangling mention row")
CE.insert("mentions", id: 943, mentions_container_id: 372, mentions_container_type: "Comment", person_id: 999)
CE.insert("likes", id: 500, positive: 1, target_id: 340, target_type: "Comment", author_id: 2, guid: "likeguid500")
CONCRETE_SCENARIOS = adv_scenario("C06_cardinality") do
  adv_request(post_id: "120", format: :json, tag: "json_zero")
  adv_request(post_id: "120", format: :mobile, tag: "mobile_zero")
  adv_request(post_id: "121", format: :json, tag: "json_one")
  adv_request(post_id: "122", format: :json, tag: "json_many")
  adv_request(post_id: "122", format: :mobile, tag: "mobile_many")
  adv_request(post_id: "123", format: :json, tag: "json_dangling_mention")
  adv_request(post_id: "123", format: :mobile, tag: "mobile_dangling_mention")
end
