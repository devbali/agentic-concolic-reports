# A06 — TEXT-content edges: the corpus models comment text as three booleans
# (has_mention / has_dlink / dlink_is_post). These are the states it does not
# state: BLANK text (Processor.process returns '' before diaspora_links ever
# runs), whitespace-only text, a setext/atx heading, a bare URL, a mention with
# no matching mentions row, a mentions row pointing at a MISSING person on the
# MOBILE path (Mentionable.format's nil branch), and an author whose guid is ''
# (person_path / to_param).
require_relative "_common2"
adv_setup!("A06_text_edges")
seed_people!(extra_people: true)

CE.insert("posts", id: 130, author_id: 2, guid: "postguid1300000001", type: "StatusMessage",
          text: "public", public: true, comments_count: 5)
CE.insert("comments", id: 340, commentable_id: 130, commentable_type: "Post",
          author_id: 2, guid: "cguid340", text: "")
CE.insert("comments", id: 341, commentable_id: 130, commentable_type: "Post",
          author_id: 2, guid: "cguid341", text: "   ")
CE.insert("comments", id: 342, commentable_id: 130, commentable_type: "Post",
          author_id: 2, guid: "cguid342", text: "Heading\n=======\nbody with http://bare.example/x and #tag")
CE.insert("comments", id: 343, commentable_id: 130, commentable_type: "Post",
          author_id: 2, guid: "cguid343",
          text: "only a comment link diaspora://bob@remote.example/comment/cguid340 and nothing else")
CE.insert("comments", id: 344, commentable_id: 130, commentable_type: "Post",
          author_id: 2, guid: "cguid344",
          text: "mention markup with NO mentions row @{Nobody; nobody@nowhere.example}")

# post 131: a mentions row pointing at a MISSING person, rendered on MOBILE
CE.insert("posts", id: 131, author_id: 2, guid: "postguid1310000001", type: "StatusMessage",
          text: "public", public: true, comments_count: 1)
CE.insert("comments", id: 345, commentable_id: 131, commentable_type: "Post",
          author_id: 2, guid: "cguid345", text: "hi @{Ghost; ghost@nowhere.example}")
CE.insert("mentions", id: 920, mentions_container_id: 345, mentions_container_type: "Comment", person_id: 999)

# post 132: comment author with a BLANK guid (posts/people.guid is NOT NULL but '' is a value)
CE.insert("people", id: 7, guid: "", diaspora_handle: "hank@remote.example",
          serialized_public_key: "K7", owner_id: nil, closed_account: 0, fetch_status: 0)
CE.insert("profiles", id: 17, person_id: 7, first_name: "Hank", last_name: "H", searchable: 1, nsfw: 0)
CE.insert("posts", id: 132, author_id: 2, guid: "postguid1320000001", type: "StatusMessage",
          text: "public", public: true, comments_count: 1)
CE.insert("comments", id: 346, commentable_id: 132, commentable_type: "Post",
          author_id: 7, guid: "cguid346", text: "author has a blank guid")

CONCRETE_SCENARIOS = adv_scenario("A06-text-edges") do
  adv_request(post_id: "130", format: :json, tag: "A06_text_json")
  adv_request(post_id: "130", format: :mobile, tag: "A06_text_mobile")
  adv_request(post_id: "131", format: :mobile, tag: "A06_dangling_mention_mobile")
  adv_request(post_id: "132", format: :json, tag: "A06_blank_guid_json")
  adv_request(post_id: "132", format: :mobile, tag: "A06_blank_guid_mobile")
end
