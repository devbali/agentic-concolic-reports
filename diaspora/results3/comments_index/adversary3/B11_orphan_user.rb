# B11 — (2c) `User has_one :person` is NO LONGER PINNED (cycle-4 D5 repair): the
# corpus now carries `devise_user_first_1_person_not_found` (240 True / 2 016
# False) and a `NoMethodError` terminal in 4 dumps. Real check: user 8 `gina`
# has NO `people` row (`people.owner_id` carries no FK to `users`).
#   * a post she CAN see through share_visibilities -> 200, `person` never read;
#   * a post she cannot see -> the vis SELECT, then evil_query.rb:116-118
#     `@querent.person.id` raises, and the author/public SELECTs are never
#     issued;
#   * MOBILE, where `person_link_class` / the delete link compare
#     `current_user.person` against each comment author.
require_relative "_common3"
adv_setup!("B11_orphan_user")
seed_core!
CE.insert("users", id: 8, username: "gina", email: "gina@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "en", getting_started: false, disable_mail: false, sign_in_count: 1)
prime_salts!(8)
# 280: private, shared with gina
CE.insert("posts", id: 280, author_id: 2, guid: "postguid2800000001", type: "StatusMessage",
          text: "p280", public: false, comments_count: 1)
CE.insert("share_visibilities", id: 480, shareable_id: 280, shareable_type: "Post", user_id: 8, hidden: false)
CE.insert("comments", id: 380, commentable_id: 280, commentable_type: "Post", author_id: 2,
          guid: "cguid380", text: "gina can see this one")
# 281: private, gina can neither see nor own
CE.insert("posts", id: 281, author_id: 2, guid: "postguid2810000001", type: "StatusMessage",
          text: "p281", public: false, comments_count: 0)
# 282: PUBLIC, gina neither shares nor owns -> vis MISS then querent_is_author
CE.insert("posts", id: 282, author_id: 2, guid: "postguid2820000001", type: "StatusMessage",
          text: "p282", public: true, comments_count: 1)
CE.insert("comments", id: 382, commentable_id: 282, commentable_type: "Post", author_id: 2,
          guid: "cguid382", text: "public post, gina is not the author")

CONCRETE_SCENARIOS = adv_scenario("B11-orphan-user") do
  adv_request(post_id: "280", format: :json,   signed_in: true, uid: 8, tag: "B11_vis_json")
  adv_request(post_id: "280", format: :mobile, signed_in: true, uid: 8, tag: "B11_vis_mobile")
  adv_request(post_id: "281", format: :json,   signed_in: true, uid: 8, tag: "B11_notvis_json")
  adv_request(post_id: "281", format: :mobile, signed_in: true, uid: 8, tag: "B11_notvis_mobile")
  adv_request(post_id: "282", format: :json,   signed_in: true, uid: 8, tag: "B11_public_json")
  # control: alice (person 1 exists) on the same rows
  adv_request(post_id: "282", format: :mobile, signed_in: true, uid: 9, tag: "B11_public_mobile_alice")
end
