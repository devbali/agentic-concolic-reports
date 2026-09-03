# G04 — ROUND 7, brief item 3: every FORMAT x AUTH-STATE x VISIBILITY the
# action can be driven into, plus the negotiation entry points.
# `respond_to :html, :mobile, :json` and `respond_with` in the action mean
# html/xml/js all end WITHOUT a template while the post finder (and, signed in,
# the three visibility finders) have already run — a truncated statement
# multiset the corpus models only for the json/mobile arms.
require_relative "_common7"
adv_setup!("G04_formats_auth")
seed_core!
seed_user!(uid: 20, username: "dave", language: "en", person_id: 20,
           person_guid: "daveguid000000020", handle: "dave@localhost", profile_id: 20)

def post!(pid, guid, public_flag: true, author: 2, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: "StatusMessage",
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "g4cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end

# 900 public post, 2 comments 2 authors
post!(900, "g04guid900000000001"); comment!(950, 900, 2); comment!(951, 900, 5)
# 901 PRIVATE post, shared with user 9
post!(901, "g04guid901000000001", public_flag: false)
CE.insert("share_visibilities", id: 31, shareable_id: 901, shareable_type: "Post", user_id: 9, hidden: false)
comment!(952, 901, 2); comment!(953, 901, 5)
# 902 PRIVATE post authored by user 9's own person (querent_is_author arm)
post!(902, "g04guid902000000001", public_flag: false, author: 1); comment!(954, 902, 2)
# 903 PRIVATE post, NOT shared with anyone (404 for user 9, NonPublic for anon)
post!(903, "g04guid903000000001", public_flag: false, author: 2); comment!(955, 903, 2)
# 904 public post reached through the PUBLIC arm when signed in
post!(904, "g04guid904000000001", public_flag: true, author: 2); comment!(956, 904, 5)
# 905 empty comment collection
post!(905, "g04guid905000000001")

MOBILE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 " \
            "(KHTML, like Gecko) Version/12.0 Mobile/15E148 Safari/604.1"

CONCRETE_SCENARIOS = adv_scenario("G04-formats-auth") do
  # ---- formats, anonymous ------------------------------------------------
  adv_request(post_id: "900", format: :json,   tag: "G04_900_json_anon")
  adv_request(post_id: "900", format: :mobile, tag: "G04_900_mobile_anon")
  adv_request(post_id: "900", format: :html,   tag: "G04_900_html_anon")
  adv_request(post_id: "900", format: :xml,    tag: "G04_900_xml_anon")
  adv_request(post_id: "900", format: :js,     tag: "G04_900_js_anon")
  adv_request(post_id: "900", format: :atom,   tag: "G04_900_atom_anon")
  # ---- mobile entry points ----------------------------------------------
  adv_request(post_id: "900", format: :html, session: {mobile_view: true},
              tag: "G04_900_session_mobile_anon")
  adv_request(post_id: "900", format: :html,
              headers: {"X_MOBILE_DEVICE" => "1", "HTTP_USER_AGENT" => MOBILE_UA},
              tag: "G04_900_hdr_mobile_anon")
  adv_request(post_id: "900", format: :html, headers: {"HTTP_USER_AGENT" => MOBILE_UA},
              tag: "G04_900_ua_only_anon")
  adv_request(post_id: "900", format: :html, headers: {"X_MOBILE_DEVICE" => "1"},
              tag: "G04_900_hdr_only_anon")
  # ---- formats, signed in (each principal used once per uid) -------------
  adv_request(post_id: "901", format: :json,   signed_in: true, uid: 9,  tag: "G04_901_json_auth")
  adv_request(post_id: "901", format: :mobile, signed_in: true, uid: 9,  tag: "G04_901_mobile_auth")
  adv_request(post_id: "901", format: :html,   signed_in: true, uid: 9,  tag: "G04_901_html_auth")
  adv_request(post_id: "901", format: :xml,    signed_in: true, uid: 9,  tag: "G04_901_xml_auth")
  adv_request(post_id: "902", format: :json,   signed_in: true, uid: 9,  tag: "G04_902_own_post_auth")
  adv_request(post_id: "903", format: :json,   signed_in: true, uid: 9,  tag: "G04_903_not_shared_auth_404")
  adv_request(post_id: "904", format: :json,   signed_in: true, uid: 20, tag: "G04_904_public_arm_auth")
  adv_request(post_id: "904", format: :mobile, signed_in: true, uid: 20, tag: "G04_904_public_arm_auth_mobile")
  # ---- anonymous on a non-public post: Diaspora::NonPublic -> warden -----
  adv_request(post_id: "903", format: :json,   tag: "G04_903_nonpublic_anon")
  adv_request(post_id: "903", format: :mobile, tag: "G04_903_nonpublic_anon_mobile")
  adv_request(post_id: "901", format: :json,   tag: "G04_901_nonpublic_anon")
  # ---- missing post / key shapes ----------------------------------------
  adv_request(post_id: "999999", format: :json, tag: "G04_missing_by_id_json")
  adv_request(post_id: "g04guid900000000001", format: :json, tag: "G04_by_guid_json")
  adv_request(post_id: "g04guid9000000", format: :json, tag: "G04_15char_key_json")
  adv_request(post_id: "g04guid90000000", format: :json, tag: "G04_15char_b_json")
  adv_request(post_id: "g04guid900000000", format: :json, tag: "G04_17char_key_json")
  adv_request(post_id: "", format: :json, tag: "G04_empty_postid_json")
  # ---- empty collection --------------------------------------------------
  adv_request(post_id: "905", format: :json,   tag: "G04_905_empty_json")
  adv_request(post_id: "905", format: :mobile, tag: "G04_905_empty_mobile")
end
