# A01 — RE-VERIFY W1 (Post.exists? from diaspora:// links) + W2 (:mobile) on the
# REGENERATED corpus, anonymous, on all three ways of reaching :mobile.
# Also probes CARDINALITY: one comment carrying THREE `post` links (2 hit, 1 miss)
# plus a `comment` link and a `web+diaspora://` post link.
require_relative "_common2"
adv_setup!("A01_links_anon")
seed_people!

CE.insert("posts", id: 100, author_id: 2, guid: "postguid1000000001", type: "StatusMessage",
          text: "a public post", public: true, comments_count: 4)
CE.insert("posts", id: 101, author_id: 1, guid: "postguid1010000001", type: "StatusMessage",
          text: "another public post", public: true, comments_count: 0)
CE.insert("comments", id: 300, commentable_id: 100, commentable_type: "Post",
          author_id: 2, guid: "cguid300", text: "plain comment")
CE.insert("comments", id: 302, commentable_id: 100, commentable_type: "Post",
          author_id: 2, guid: "cguid302",
          text: "see diaspora://bob@remote.example/post/postguid1000000001 and " \
                "diaspora://alice@localhost/post/postguid1010000001 and " \
                "web+diaspora://bob@remote.example/post/nosuchguid00000001 and " \
                "diaspora://bob@remote.example/comment/cguid300 ok")
CE.insert("comments", id: 303, commentable_id: 100, commentable_type: "Post",
          author_id: 1, guid: "cguid303",
          text: "hi @{Bob; bob@remote.example} #tag **bold** <3 http://bare.example/x and &lt;3")
CE.insert("mentions", id: 900, mentions_container_id: 303, mentions_container_type: "Comment", person_id: 2)
CE.insert("comments", id: 304, commentable_id: 100, commentable_type: "Post",
          author_id: 3, guid: "cguid304", text: "closed account author comment")

CONCRETE_SCENARIOS = adv_scenario("A01-anon-links-json-and-mobile") do
  adv_request(post_id: "100", format: :json, tag: "A01_json")
  adv_request(post_id: "100", format: :html, session: { mobile_view: true }, tag: "A01_mobile_session")
  adv_request(post_id: "100", format: :mobile, tag: "A01_mobile_explicit")
  adv_request(post_id: "100", format: :html, tag: "A01_mobile_header",
              headers: { "HTTP_X_MOBILE_DEVICE" => "iPhone",
                         "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X)" })
  adv_request(post_id: "postguid1000000001", format: :json, tag: "A01_json_by_guid")
end
