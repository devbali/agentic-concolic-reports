# E03 — ROUND 6, brief item 3 "go wider": STI posts and a Reshare whose ROOT IS
# MISSING; guid vs numeric keys across the key-length boundary; remote / closed
# authors; a mention of someone on another pod; blocked or ignored authors when
# signed in; and format x auth-state x visibility combinations.
require_relative "_common6"
adv_setup!("E03_wider")
seed_core!

# an "ignored"/blocked author and a contact, so the signed-in render sees them
CE.insert("blocks", id: 1, user_id: 9, person_id: 2)
CE.insert("aspects", id: 1, user_id: 9, name: "Friends", order_id: 1)
CE.insert("contacts", id: 1, user_id: 9, person_id: 5, sharing: true, receiving: true)
CE.insert("aspect_memberships", id: 1, aspect_id: 1, contact_id: 1)

def post!(pid, guid, type: "StatusMessage", public_flag: true, author: 2, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: type,
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "e3cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

# --- STI: a Reshare whose ROOT IS MISSING, and one with a live root ---------
post!(720, "e03guid720000000001", type: "Reshare", extra: {root_guid: "no_such_root_guid01"})
comment!(850, 720, 2, "comment on a rootless reshare")
comment!(851, 720, 5, "second author here")
post!(721, "e03guid721000000001")                                  # the root
post!(722, "e03guid722000000001", type: "Reshare", extra: {root_guid: "e03guid721000000001"})
comment!(852, 722, 2, "comment on a reshare with a live root")
# a Reshare whose root is PRIVATE (root_must_be_public is a create-time validation only)
post!(723, "e03guid723000000001", public_flag: false)
post!(724, "e03guid724000000001", type: "Reshare", extra: {root_guid: "e03guid723000000001"})
comment!(853, 724, 2, "reshare of a private root")
# out-of-tree type (M-6 re-verify), by id AND by guid
post!(725, "e03guid725000000001", type: "Photo"); comment!(854, 725, 2)
# --- guid vs numeric keys, across the length-16 boundary --------------------
post!(726, "e03guid726000000001"); comment!(855, 726, 2)
CE.insert("posts", id: 727, author_id: 2, guid: "1234567890123456", type: "StatusMessage",
          text: "p727", public: true, comments_count: 0)          # 16-char NUMERIC guid
comment!(856, 727, 2)
CE.insert("posts", id: 123456789012345, author_id: 2, guid: "e03guidbignum000001",
          type: "StatusMessage", text: "pbig", public: true, comments_count: 0)  # 15-digit id
comment!(857, 123456789012345, 2)
# --- remote / closed authors, other-pod mention ----------------------------
post!(728, "e03guid728000000001")
comment!(858, 728, 3, "closed account author")                     # person 3, closed, blank-name profile
comment!(859, 728, 5, "other pod author with a mention of @{Frank; frank@third.example}")
comment!(860, 728, 1, "local author (alice)")
mention!(910, 859, 6)                                              # frank, third pod
# --- blocked author when signed in -----------------------------------------
post!(729, "e03guid729000000001", public_flag: false)
CE.insert("share_visibilities", id: 31, shareable_id: 729, shareable_type: "Post", user_id: 9, hidden: false)
comment!(861, 729, 2, "comment by a BLOCKED author")                # person 2 is blocked by alice
comment!(862, 729, 5, "comment by a contact")

CONCRETE_SCENARIOS = adv_scenario("E03-wider") do
  # STI / reshare
  adv_request(post_id: "720", format: :json,   tag: "E03_720_reshare_missing_root")
  adv_request(post_id: "720", format: :mobile, tag: "E03_720_reshare_missing_root_mobile")
  adv_request(post_id: "720", format: :json, signed_in: true, tag: "E03_720_reshare_missing_root_auth")
  adv_request(post_id: "722", format: :json,   tag: "E03_722_reshare_live_root")
  adv_request(post_id: "724", format: :json,   tag: "E03_724_reshare_private_root")
  adv_request(post_id: "725", format: :json,   tag: "E03_725_photo_type_by_id")
  adv_request(post_id: "e03guid725000000001", format: :json, tag: "E03_725_photo_type_by_guid")
  # guid vs numeric keys
  adv_request(post_id: "726", format: :json, tag: "E03_726_by_id")
  adv_request(post_id: "e03guid726000000001", format: :json, tag: "E03_726_by_guid_19")
  adv_request(post_id: "1234567890123456", format: :json, tag: "E03_727_numeric_guid_16")
  adv_request(post_id: "123456789012345", format: :json, tag: "E03_big_numeric_id_15")
  adv_request(post_id: "0000000000000726", format: :json, tag: "E03_726_padded_16")
  adv_request(post_id: "726 ", format: :json, tag: "E03_726_trailing_space")
  # remote / closed / other-pod
  adv_request(post_id: "728", format: :json,   tag: "E03_728_remote_closed_otherpod")
  adv_request(post_id: "728", format: :mobile, tag: "E03_728_remote_closed_otherpod_mobile")
  adv_request(post_id: "728", format: :mobile, signed_in: true, tag: "E03_728_remote_closed_otherpod_auth_mobile")
  # blocked author, signed in
  adv_request(post_id: "729", format: :json, signed_in: true, tag: "E03_729_blocked_author_auth")
  adv_request(post_id: "729", format: :mobile, signed_in: true, tag: "E03_729_blocked_author_auth_mobile")
  adv_request(post_id: "729", format: :json, tag: "E03_729_anon_private")
  # format x auth-state
  adv_request(post_id: "726", format: :html, tag: "E03_726_html_anon")
  adv_request(post_id: "726", format: :html, signed_in: true, tag: "E03_726_html_auth")
  adv_request(post_id: "726", format: :xml,  tag: "E03_726_xml")
  adv_request(post_id: "726", format: :js,   tag: "E03_726_js")
  adv_request(post_id: "726", format: :html, session: {mobile_view: true}, tag: "E03_726_session_mobile_anon")
  adv_request(post_id: "726", format: :html,
              headers: {"X_MOBILE_DEVICE" => "iPhone",
                        "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"},
              tag: "E03_726_xmobile_anon")
  adv_request(post_id: "726", format: :json, headers: {"Accept" => "*/*"}, tag: "E03_726_accept_star")
end
