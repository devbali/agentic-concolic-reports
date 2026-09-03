# B10 — the widest single render: four comments by four different authors
# (one closed account with a blank-name profile, one the signed-in user's own
# person -> delete link + "self" class), markdown, a bare URL, a setext heading,
# `#tag` and `<3`, plus a comment with THREE mentions, one of them on another
# pod. anon and signed-in, json and mobile.
require_relative "_common3"
adv_setup!("B10_wide_render")
seed_core!

CE.insert("posts", id: 250, author_id: 2, guid: "postguid2500000001", type: "StatusMessage",
          text: "p250", public: true, comments_count: 4)
CE.insert("comments", id: 350, commentable_id: 250, commentable_type: "Post", author_id: 2,
          guid: "cguid350", text: "A heading\n=========\n**bold** and _em_ and http://bare.example/x " \
                                  "and #tag and <3 and `code`\n\nsecond para")
CE.insert("comments", id: 351, commentable_id: 250, commentable_type: "Post", author_id: 3,
          guid: "cguid351", text: "by a closed account with a blank-name profile")
CE.insert("comments", id: 352, commentable_id: 250, commentable_type: "Post", author_id: 1,
          guid: "cguid352", text: "alice's own comment")
CE.insert("comments", id: 353, commentable_id: 250, commentable_type: "Post", author_id: 5,
          guid: "cguid353", text: "cc @{Erin; erin@other.example} @{Frank; frank@third.example} " \
                                  "@{Bob; bob@remote.example}")
CE.insert("mentions", id: 950, mentions_container_id: 353, mentions_container_type: "Comment", person_id: 5)
CE.insert("mentions", id: 951, mentions_container_id: 353, mentions_container_type: "Comment", person_id: 6)
CE.insert("mentions", id: 952, mentions_container_id: 353, mentions_container_type: "Comment", person_id: 2)

CONCRETE_SCENARIOS = adv_scenario("B10-wide-render") do
  adv_request(post_id: "250", format: :json,   tag: "B10_json_anon")
  adv_request(post_id: "250", format: :mobile, tag: "B10_mobile_anon")
  adv_request(post_id: "250", format: :json,   signed_in: true, tag: "B10_json_auth")
  adv_request(post_id: "250", format: :mobile, signed_in: true, tag: "B10_mobile_auth")
  adv_request(post_id: "250", format: :html,   signed_in: true, session: { mobile_view: true },
              tag: "B10_session_mobile_auth")
end
