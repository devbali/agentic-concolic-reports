# B08 — the full visibility matrix for `EvilQuery::VisibleShareableById#post!`
# (lib/evil_query.rb:100-118) with the FIXED `ConcreteEnv.quote`: `public: true`
# is now written as the adapter's own `'t'`, so the signed-in PUBLIC arm
# (`ci_public_first`) is exercised by a FIXTURE row for the first time on any
# batch (round 2 could only reach it by re-writing the column through AR).
#  240 public, alice neither owns nor shares      -> vis MISS, author MISS, public HIT
#  241 private, share_visibilities(alice)          -> vis HIT
#  242 private, author_id = alice's person         -> vis MISS, author HIT
#  243 private, nothing                            -> all three MISS -> 404
#  9999 no such post                               -> 404
# anon on 241 -> Diaspora::NonPublic -> authenticate_user!
require_relative "_common3"
adv_setup!("B08_visibility_matrix")
seed_core!

def vpost(id, guid, author, pub, ncomments = 1)
  CE.insert("posts", id: id, author_id: author, guid: guid, type: "StatusMessage",
            text: "p#{id}", public: pub, comments_count: ncomments)
  ncomments.times do |i|
    CE.insert("comments", id: id * 10 + i, commentable_id: id, commentable_type: "Post", author_id: 2,
              guid: "cg#{id}#{i}", text: "comment #{i} on post #{id}")
  end
end

vpost(240, "postguid2400000001", 2, true)
vpost(241, "postguid2410000001", 2, false)
CE.insert("share_visibilities", id: 441, shareable_id: 241, shareable_type: "Post", user_id: 9, hidden: false)
vpost(242, "postguid2420000001", 1, false)
vpost(243, "postguid2430000001", 2, false)

CONCRETE_SCENARIOS = adv_scenario("B08-visibility-matrix") do
  adv_request(post_id: "240", format: :json,   signed_in: true, tag: "B08_public_json_auth")
  adv_request(post_id: "240", format: :mobile, signed_in: true, tag: "B08_public_mobile_auth")
  adv_request(post_id: "postguid2400000001", format: :json, signed_in: true, tag: "B08_public_byguid_json_auth")
  adv_request(post_id: "241", format: :json,   signed_in: true, tag: "B08_vis_json_auth")
  adv_request(post_id: "242", format: :json,   signed_in: true, tag: "B08_author_json_auth")
  adv_request(post_id: "242", format: :mobile, signed_in: true, tag: "B08_author_mobile_auth")
  adv_request(post_id: "243", format: :json,   signed_in: true, tag: "B08_none_json_auth")
  adv_request(post_id: "9999", format: :json,  signed_in: true, tag: "B08_missing_json_auth")
  adv_request(post_id: "240", format: :json,   tag: "B08_public_json_anon")
  adv_request(post_id: "241", format: :json,   tag: "B08_nonpublic_json_anon")
  adv_request(post_id: "241", format: :mobile, tag: "B08_nonpublic_mobile_anon")
  adv_request(post_id: "9999", format: :json,  tag: "B08_missing_json_anon")
  adv_request(post_id: "240", format: :html,   signed_in: true, tag: "B08_public_html_auth")
end
