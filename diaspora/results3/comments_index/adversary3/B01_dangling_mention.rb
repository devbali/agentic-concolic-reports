# B01 — a `mentions` row whose `person_id` has NO `people` row.
# `mentions` carries NO foreign key at all (db/schema.rb:202-209), so this is a
# database state. Round 1 found it (N3), round 2 verified it CLEAN against the
# 59-node corpus (`records_2/3_row_person_not_found` decisions + a recorded
# `ActionView::Template::Error <- NoMethodError` terminal). On the REGENERATED
# 31-node corpus neither the decision nor the terminal exists any more.
# Three shapes: dangling mention with NO markup (json [null] / mobile 200),
# dangling mention WITH markup (json [null] / mobile 500 at mentionable.rb:35),
# and an all-present control.
require_relative "_common3"
adv_setup!("B01_dangling_mention")
seed_core!

# 200: dangling mention, no mention markup in the text
CE.insert("posts", id: 200, author_id: 2, guid: "postguid2000000001", type: "StatusMessage",
          text: "p200", public: true, comments_count: 1)
CE.insert("comments", id: 300, commentable_id: 200, commentable_type: "Post", author_id: 2,
          guid: "cguid300", text: "plain comment with no mention markup at all")
CE.insert("mentions", id: 900, mentions_container_id: 300, mentions_container_type: "Comment", person_id: 999)

# 201: dangling mention WITH markup
CE.insert("posts", id: 201, author_id: 2, guid: "postguid2010000001", type: "StatusMessage",
          text: "p201", public: true, comments_count: 1)
CE.insert("comments", id: 301, commentable_id: 201, commentable_type: "Post", author_id: 2,
          guid: "cguid301", text: "hello @{Ghost; ghost@remote.example} goodbye")
CE.insert("mentions", id: 901, mentions_container_id: 301, mentions_container_type: "Comment", person_id: 999)

# 202: control — mention row present AND person present
CE.insert("posts", id: 202, author_id: 2, guid: "postguid2020000001", type: "StatusMessage",
          text: "p202", public: true, comments_count: 1)
CE.insert("comments", id: 302, commentable_id: 202, commentable_type: "Post", author_id: 2,
          guid: "cguid302", text: "hello @{Bob; bob@remote.example} goodbye")
CE.insert("mentions", id: 902, mentions_container_id: 302, mentions_container_type: "Comment", person_id: 2)

# 203: TWO mentions, one dangling one present, with markup for both
CE.insert("posts", id: 203, author_id: 2, guid: "postguid2030000001", type: "StatusMessage",
          text: "p203", public: true, comments_count: 1)
CE.insert("comments", id: 303, commentable_id: 203, commentable_type: "Post", author_id: 2,
          guid: "cguid303", text: "cc @{Bob; bob@remote.example} and @{Ghost; ghost@remote.example}")
CE.insert("mentions", id: 903, mentions_container_id: 303, mentions_container_type: "Comment", person_id: 2)
CE.insert("mentions", id: 904, mentions_container_id: 303, mentions_container_type: "Comment", person_id: 999)

CONCRETE_SCENARIOS = adv_scenario("B01-dangling-mention") do
  adv_request(post_id: "200", format: :json,   tag: "B01_nomarkup_json")
  adv_request(post_id: "200", format: :mobile, tag: "B01_nomarkup_mobile")
  adv_request(post_id: "201", format: :json,   tag: "B01_markup_json")
  adv_request(post_id: "201", format: :mobile, tag: "B01_markup_mobile")
  adv_request(post_id: "202", format: :json,   tag: "B01_control_json")
  adv_request(post_id: "202", format: :mobile, tag: "B01_control_mobile")
  adv_request(post_id: "203", format: :json,   tag: "B01_mixed_json")
  adv_request(post_id: "203", format: :mobile, tag: "B01_mixed_mobile")
  adv_request(post_id: "201", format: :json,   signed_in: true, tag: "B01_markup_json_auth")
end
