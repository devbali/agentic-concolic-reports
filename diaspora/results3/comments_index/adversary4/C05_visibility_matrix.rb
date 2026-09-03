# C05 — GO WIDER: every format (html, json, mobile) x (anon, signed-in) x
# (public, private-shared, private-not-shared, own, missing post), by numeric
# id and by 16+ char guid. With the repaired `ConcreteEnv.quote` the signed-in
# PUBLIC arm (`public_post.first`) exercises for real.
require_relative "_common4"
adv_setup!("C05_visibility_matrix")
seed_core!

def commented!(pid, guid, author, public_flag)
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: "StatusMessage",
            text: "p#{pid}", public: public_flag, comments_count: 1)
  CE.insert("comments", id: pid + 100, commentable_id: pid, commentable_type: "Post",
            author_id: 2, guid: "cguid#{pid}", text: "comment on #{pid}")
end

commented!(360, "visguid36000000001", 2, true)    # public, bob's
commented!(361, "visguid36100000001", 2, false)   # private, not shared with alice
commented!(362, "visguid36200000001", 2, false)   # private, shared with alice
CE.insert("share_visibilities", id: 760, user_id: 9, shareable_id: 362, shareable_type: "Post")
commented!(363, "visguid36300000001", 1, false)   # private, ALICE is the author
commented!(365, "visguid36500000001", 2, true)    # public AND shared with alice
CE.insert("share_visibilities", id: 765, user_id: 9, shareable_id: 365, shareable_type: "Post")

CONCRETE_SCENARIOS = adv_scenario("C05-visibility-matrix") do
  %i[json mobile html].each do |fmt|
    adv_request(post_id: "360", format: fmt, tag: "C05_pub_anon_#{fmt}")
    adv_request(post_id: "360", format: fmt, signed_in: true, tag: "C05_pub_auth_#{fmt}")
    adv_request(post_id: "361", format: fmt, tag: "C05_priv_anon_#{fmt}")
    adv_request(post_id: "361", format: fmt, signed_in: true, tag: "C05_priv_auth_#{fmt}")
    adv_request(post_id: "362", format: fmt, signed_in: true, tag: "C05_shared_auth_#{fmt}")
    adv_request(post_id: "363", format: fmt, signed_in: true, tag: "C05_own_auth_#{fmt}")
    adv_request(post_id: "999999", format: fmt, tag: "C05_missing_anon_#{fmt}")
    adv_request(post_id: "999999", format: fmt, signed_in: true, tag: "C05_missing_auth_#{fmt}")
  end
  # guid key (16+ chars) on each arm
  adv_request(post_id: "visguid36000000001", format: :json, tag: "C05_pub_anon_guid")
  adv_request(post_id: "visguid36000000001", format: :json, signed_in: true, tag: "C05_pub_auth_guid")
  adv_request(post_id: "visguid36200000001", format: :json, signed_in: true, tag: "C05_shared_auth_guid")
  adv_request(post_id: "visguid36300000001", format: :mobile, signed_in: true, tag: "C05_own_auth_guid")
  adv_request(post_id: "visguid36100000001", format: :json, tag: "C05_priv_anon_guid")
  adv_request(post_id: "nosuchguid00000001", format: :json, signed_in: true, tag: "C05_missing_auth_guid")
  adv_request(post_id: "visguid36500000001", format: :json, signed_in: true, tag: "C05_pubshared_auth_guid")
  adv_request(post_id: "365", format: :json, signed_in: true, tag: "C05_pubshared_auth_id")
  # boundary of post_key: exactly 15 and exactly 16 characters
  adv_request(post_id: "123456789012345",  format: :json, tag: "C05_key_len15")
  adv_request(post_id: "1234567890123456", format: :json, tag: "C05_key_len16")
end
