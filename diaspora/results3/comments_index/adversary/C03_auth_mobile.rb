# C03 — SIGNED-IN mobile (alice): own comment (comment.author == current_user.person ->
# delete link + comment_path), person_link_class 'self'/'hovercardable' branches, mention of
# the current user, diaspora links; on a private post visible via share_visibilities
# (hidden: true — post! does not filter hidden) and on alice's own private post.
require_relative "_common"
adv_setup!("C03_auth_mobile"); seed_people!
CE.insert("posts", id: 101, author_id: 2, guid: "postguid101000001", type: "StatusMessage",
          text: "bob's limited post", public: 0, comments_count: 3)
CE.insert("share_visibilities", id: 400, shareable_id: 101, shareable_type: "Post", user_id: 9, hidden: 1)
CE.insert("posts", id: 102, author_id: 1, guid: "postguid102000001", type: "StatusMessage",
          text: "alice's own private post", public: 0, comments_count: 1)
CE.insert("comments", id: 310, commentable_id: 101, commentable_type: "Post", author_id: 2, guid: "cguid310",
          text: "hey @{alice@localhost} look diaspora://bob@remote.example/post/postguid101000001")
CE.insert("mentions", id: 910, mentions_container_id: 310, mentions_container_type: "Comment", person_id: 1)
CE.insert("comments", id: 311, commentable_id: 101, commentable_type: "Post", author_id: 1, guid: "cguid311",
          text: "my own comment @{Bob; bob@remote.example} #tag")
CE.insert("mentions", id: 911, mentions_container_id: 311, mentions_container_type: "Comment", person_id: 2)
CE.insert("comments", id: 312, commentable_id: 101, commentable_type: "Post", author_id: 3, guid: "cguid312",
          text: "closed account says hi")
CE.insert("comments", id: 313, commentable_id: 102, commentable_type: "Post", author_id: 1, guid: "cguid313",
          text: "alone on my own post")
CONCRETE_SCENARIOS = adv_scenario("C03_auth_mobile") do
  adv_request(post_id: "101", format: :html, signed_in: true, session: { mobile_view: true }, tag: "auth_mobile_session_101")
  adv_request(post_id: "102", format: :mobile, signed_in: true, tag: "auth_mobile_explicit_102")
  adv_request(post_id: "101", format: :json, signed_in: true, tag: "auth_json_101")
end
