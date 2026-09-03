# E02 — ROUND 6, brief item 2 (B-8): the four falsy arms that now publish their
# note through `Thread.current[:concolic_pending_note]`.
#   * the three `ci_*_first` visibility finders (signed-in miss/hit sequences),
#   * the anon post finder (`FinderMethods#first`) on a miss,
#   * `find_target` (has_one / FK-less belongs_to) on a miss,
#   * `exists?` returning FALSE between two finders.
# The real run supplies the GROUND TRUTH the corpus must carry on each arm: the
# statement a finder issues when it finds nothing, and the ORDER of the arms.
# Interleavings deliberately exercised: miss->hit, hit->miss, miss->miss,
# false-exists? between two finders, and the three-miss 404.
require_relative "_common6"
adv_setup!("E02_falsy_arms")
seed_core!

def post!(pid, guid, public_flag: true, author: 2)
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: "StatusMessage",
            text: "p#{pid}", public: public_flag, comments_count: 0)
end
def comment!(cid, pid, author, text)
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "e2cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end

post!(710, "e02guid710000000001")                                     # public
post!(711, "e02guid711000000001", public_flag: false)                 # private, shared with alice
CE.insert("share_visibilities", id: 21, shareable_id: 711, shareable_type: "Post", user_id: 9, hidden: false)
post!(712, "e02guid712000000001", public_flag: false, author: 1)      # alice's OWN private post
post!(713, "e02guid713000000001")                                     # public, not shared, not hers
comment!(840, 710, 2, "plain")
comment!(841, 711, 2, "plain shared")
comment!(842, 712, 1, "plain own")
comment!(843, 713, 2, "plain public")
# a text whose diaspora link guid does NOT exist -> exists? FALSE
post!(714, "e02guid714000000001")
comment!(844, 714, 2, "see diaspora://bob@remote.example/post/nosuchguid00000001 end")
# a text whose diaspora link guid DOES exist -> exists? TRUE
post!(715, "e02guid715000000001")
comment!(845, 715, 2, "see diaspora://bob@remote.example/post/e02guid710000000001 end")
# both, in one comment
post!(716, "e02guid716000000001")
comment!(846, 716, 2, "a diaspora://bob@remote.example/post/nosuchguid00000002 b " \
                      "diaspora://bob@remote.example/post/e02guid710000000001 c")

CONCRETE_SCENARIOS = adv_scenario("E02-falsy-arms") do
  # --- anon finder: miss, hit, miss, miss, hit -------------------------------
  adv_request(post_id: "999999", format: :json, tag: "E02_a1_anon_miss")
  adv_request(post_id: "710",    format: :json, tag: "E02_a2_anon_hit_after_miss")
  adv_request(post_id: "999998", format: :json, tag: "E02_a3_anon_miss_after_hit")
  adv_request(post_id: "999997", format: :json, tag: "E02_a4_anon_miss_twice")
  adv_request(post_id: "710",    format: :json, tag: "E02_a5_anon_hit")
  adv_request(post_id: "999996", format: :mobile, tag: "E02_a6_anon_miss_mobile")
  adv_request(post_id: "710",    format: :mobile, tag: "E02_a7_anon_hit_mobile")
  # --- anon, existing but NON-public: finder HIT then Diaspora::NonPublic ----
  adv_request(post_id: "711", format: :json, tag: "E02_a8_anon_nonpublic")
  # --- signed-in visibility chain -------------------------------------------
  adv_request(post_id: "711", format: :json, signed_in: true, tag: "E02_b1_auth_vis_hit")
  adv_request(post_id: "712", format: :json, signed_in: true, tag: "E02_b2_auth_vis_miss_author_hit")
  adv_request(post_id: "713", format: :json, signed_in: true, tag: "E02_b3_auth_vis_miss_author_miss_public_hit")
  adv_request(post_id: "999995", format: :json, signed_in: true, tag: "E02_b4_auth_three_misses")
  adv_request(post_id: "999994", format: :json, signed_in: true, tag: "E02_b5_auth_three_misses_again")
  adv_request(post_id: "711", format: :json, signed_in: true, tag: "E02_b6_auth_vis_hit_after_miss")
  adv_request(post_id: "999993", format: :mobile, signed_in: true, tag: "E02_b7_auth_three_misses_mobile")
  adv_request(post_id: "712", format: :mobile, signed_in: true, tag: "E02_b8_auth_author_hit_mobile")
  # --- exists? FALSE between two finders ------------------------------------
  adv_request(post_id: "714", format: :json, tag: "E02_c1_exists_false")
  adv_request(post_id: "710", format: :json, tag: "E02_c2_hit_right_after_false_exists")
  adv_request(post_id: "715", format: :json, tag: "E02_c3_exists_true")
  adv_request(post_id: "716", format: :json, tag: "E02_c4_exists_false_then_true")
  adv_request(post_id: "999992", format: :json, tag: "E02_c5_miss_right_after_exists")
  adv_request(post_id: "714", format: :mobile, tag: "E02_c6_exists_false_mobile")
  # --- guid-keyed misses and hits (the other post_key branch) ---------------
  adv_request(post_id: "nosuchguid00000009", format: :json, tag: "E02_d1_guid_miss")
  adv_request(post_id: "e02guid710000000001", format: :json, tag: "E02_d2_guid_hit")
  adv_request(post_id: "nosuchguid00000010", format: :json, signed_in: true, tag: "E02_d3_guid_miss_auth")
end
