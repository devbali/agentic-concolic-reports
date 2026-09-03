# C02 — anonymous MOBILE format (never explored: the corpus is format :json only).
# Three switches: session[:mobile_view]=true with html (ApplicationController#mobile_switch),
# X_MOBILE_DEVICE header with html (mobile-fu set_mobile_format), explicit format :mobile.
# Same fixtures as C01 (links, tags, mentions, closed-account author).
require_relative "_common"
adv_setup!("C02_anon_mobile"); seed_people!; seed_batch_post!
CE.insert("posts", id: 105, author_id: 1, guid: "alicepostguid0105", type: "StatusMessage",
          text: "another post", public: 1, comments_count: 0)
CE.insert("comments", id: 302, commentable_id: 100, commentable_type: "Post", author_id: 2, guid: "cguid302",
          text: "see diaspora://bob@remote.example/post/postguid100000001 and " \
                "web+diaspora://bob@remote.example/post/nosuchguid0000000 and " \
                "diaspora://bob@remote.example/comment/cguid300 ok")
CE.insert("comments", id: 303, commentable_id: 100, commentable_type: "Post", author_id: 3, guid: "cguid303",
          text: "#tag **bold** http://example.com/x?y=1 <3 #<3 @{Ghost; ghost@nowhere.example} @{alice@localhost}\nsecond line\n\npara")
CONCRETE_SCENARIOS = adv_scenario("C02_anon_mobile") do
  adv_request(post_id: "100", format: :html, session: { mobile_view: true }, tag: "mobile_session")
  adv_request(post_id: "100", format: :html, headers: { "X_MOBILE_DEVICE" => "iphone", "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1" }, tag: "mobile_header")
  adv_request(post_id: "100", format: :mobile, tag: "mobile_explicit")
end
