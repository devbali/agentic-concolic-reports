# C07 — GO WIDER: blocked / ignored authors when signed in, contacts, closed
# accounts, a mention of a person on another pod, markdown and bare URLs, and
# the third mobile ENTRY POINT (mobile User-Agent + X_MOBILE_DEVICE), which
# round 2 recorded as still unexercised.
require_relative "_common4"
adv_setup!("C07_blocks_contacts")
seed_core!

CE.insert("posts", id: 380, author_id: 2, guid: "blkguid38000000001", type: "StatusMessage",
          text: "p380", public: true, comments_count: 4)
CE.insert("comments", id: 480, commentable_id: 380, commentable_type: "Post", author_id: 2,
          guid: "cguid480", text: "by BLOCKED bob: **bold** _em_ http://bare.example/x #tag <3 `code`")
CE.insert("comments", id: 481, commentable_id: 380, commentable_type: "Post", author_id: 3,
          guid: "cguid481", text: "by a CLOSED account with a blank-name profile")
CE.insert("comments", id: 482, commentable_id: 380, commentable_type: "Post", author_id: 1,
          guid: "cguid482", text: "alice's own comment\nA heading\n=========\nsecond para")
CE.insert("comments", id: 483, commentable_id: 380, commentable_type: "Post", author_id: 5,
          guid: "cguid483", text: "cc @{Erin; erin@other.example} @{Frank; frank@third.example}")
CE.insert("mentions", id: 880, mentions_container_id: 483, mentions_container_type: "Comment", person_id: 5)
CE.insert("mentions", id: 881, mentions_container_id: 483, mentions_container_type: "Comment", person_id: 6)

# alice BLOCKS bob (person 2) and IGNORES carol (person 3); alice has a contact with erin
CE.insert("blocks", id: 600, user_id: 9, person_id: 2)
CE.insert("blocks", id: 601, user_id: 9, person_id: 3)
CE.insert("contacts", id: 610, user_id: 9, person_id: 5, sharing: true, receiving: true)

CONCRETE_SCENARIOS = adv_scenario("C07-blocks-contacts") do
  adv_request(post_id: "380", format: :json,   tag: "C07_json_anon")
  adv_request(post_id: "380", format: :mobile, tag: "C07_mobile_anon")
  adv_request(post_id: "380", format: :json,   signed_in: true, tag: "C07_json_auth_blocked")
  adv_request(post_id: "380", format: :mobile, signed_in: true, tag: "C07_mobile_auth_blocked")
  # the session switch (known-working entry point)
  adv_request(post_id: "380", format: :html, signed_in: true, session: {mobile_view: true},
              tag: "C07_session_mobile")
  # entry point 3: a real mobile User-Agent + the Rack::MobileDetect header
  adv_request(post_id: "380", format: :html,
              headers: {"X_MOBILE_DEVICE" => "iPhone",
                        "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) " \
                                             "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"},
              tag: "C07_ua_mobile_anon")
  adv_request(post_id: "380", format: :html, signed_in: true,
              headers: {"X_MOBILE_DEVICE" => "iPhone",
                        "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) " \
                                             "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"},
              tag: "C07_ua_mobile_auth")
  # Accept-header negotiation with no explicit format
  adv_request(post_id: "380", format: nil, headers: {"HTTP_ACCEPT" => "application/json"},
              tag: "C07_accept_json")
end
