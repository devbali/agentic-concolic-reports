# A02 — RE-VERIFY W1 + W2 SIGNED-IN. alice sees post 100 through a
# share_visibilities row (querent_has_visibility branch), owns post 103
# (querent_is_author branch) and owns comment 305 (delete link / `self` class).
require_relative "_common2"
adv_setup!("A02_links_auth")
seed_people!

CE.insert("posts", id: 100, author_id: 2, guid: "postguid1000000001", type: "StatusMessage",
          text: "bob private post", public: false, comments_count: 3)
CE.insert("share_visibilities", id: 400, shareable_id: 100, shareable_type: "Post", user_id: 9, hidden: false)
CE.insert("posts", id: 103, author_id: 1, guid: "postguid1030000001", type: "StatusMessage",
          text: "alice own private post", public: false, comments_count: 1)
CE.insert("comments", id: 300, commentable_id: 100, commentable_type: "Post",
          author_id: 2, guid: "cguid300", text: "plain comment")
CE.insert("comments", id: 302, commentable_id: 100, commentable_type: "Post",
          author_id: 2, guid: "cguid302",
          text: "see diaspora://bob@remote.example/post/postguid1000000001 and " \
                "diaspora://bob@remote.example/comment/cguid300 and " \
                "diaspora://bob@remote.example/post/nosuchguid00000001 ok")
CE.insert("comments", id: 305, commentable_id: 100, commentable_type: "Post",
          author_id: 1, guid: "cguid305", text: "alice own comment @{Bob; bob@remote.example} #tag")
CE.insert("mentions", id: 901, mentions_container_id: 305, mentions_container_type: "Comment", person_id: 2)
CE.insert("comments", id: 306, commentable_id: 103, commentable_type: "Post",
          author_id: 1, guid: "cguid306", text: "own post own comment diaspora://alice@localhost/post/postguid1030000001")

CONCRETE_SCENARIOS = adv_scenario("A02-auth-links-json-and-mobile") do
  adv_request(post_id: "100", format: :json, signed_in: true, tag: "A02_vis_json")
  adv_request(post_id: "100", format: :mobile, signed_in: true, tag: "A02_vis_mobile")
  adv_request(post_id: "100", format: :html, signed_in: true, session: { mobile_view: true }, tag: "A02_vis_mobile_sess")
  adv_request(post_id: "103", format: :json, signed_in: true, tag: "A02_author_json")
  adv_request(post_id: "103", format: :mobile, signed_in: true, tag: "A02_author_mobile")
  adv_request(post_id: "postguid1030000001", format: :json, signed_in: true, tag: "A02_author_json_guid")
end
