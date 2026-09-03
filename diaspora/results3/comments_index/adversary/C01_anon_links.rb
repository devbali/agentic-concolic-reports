# C01 — anonymous JSON on the batch's public post, plus comments whose text carries
# diaspora:// post/comment links (MessageRenderer#diaspora_links -> Post.exists?(guid:)),
# markdown, URLs and #tags. Batch fixtures otherwise unchanged.
require_relative "_common"
adv_setup!("C01_anon_links"); seed_people!; seed_batch_post!
CE.insert("posts", id: 105, author_id: 1, guid: "alicepostguid0105", type: "StatusMessage",
          text: "another post", public: 1, comments_count: 0)
CE.insert("comments", id: 302, commentable_id: 100, commentable_type: "Post", author_id: 2, guid: "cguid302",
          text: "see diaspora://bob@remote.example/post/postguid100000001 and " \
                "diaspora://alice@localhost/post/alicepostguid0105 and " \
                "web+diaspora://bob@remote.example/post/nosuchguid0000000 and " \
                "diaspora://bob@remote.example/comment/cguid300 ok")
CE.insert("comments", id: 303, commentable_id: 100, commentable_type: "Post", author_id: 3, guid: "cguid303",
          text: "#tag **bold** http://example.com/x?y=1 <3 #<3 @{Ghost; ghost@nowhere.example} @{alice@localhost}")
CONCRETE_SCENARIOS = adv_scenario("C01_anon_links") do
  adv_request(post_id: "100", format: :json)
end
