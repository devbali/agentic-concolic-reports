# ROUND 10 / K02 — IS THERE A SECOND ROUTE TO THE DECLARED GAP'S TABLES, AND
# DO THE UNPINNED FORMATS / PRINCIPAL STATES ADD A STATEMENT?
#
# The cycle-12 policy header declares ONE gap: the discovery-success arm, whose
# statements would add `pods`, `tags`⋈`taggings`, `people.guid`,
# `people.diaspora_handle` and three writes. That declaration is justified
# PER PATH. If any of those tables is reachable from this endpoint by ANOTHER
# route, the declaration is too narrow and the statements are simply missing.
#
# This manifest tries to reach them WITHOUT discovery:
#   * a comment author on a real `pods` row (people.pod_id set) — `Person#url`
#     / `#url_to` is the app's only `pods` reader outside the callback;
#   * every format the controller declares plus the ones it does not
#     (html / xml / js / atom), and the `session[:mobile_view]` route into the
#     mobile branch, in case an unpinned format renders something the two
#     pinned ones do not;
#   * a comment text carrying #hashtags (Taggable.format_tags) — the only
#     other renderer stage that names `tags`.
# It also sweeps principal states the corpus's four scenarios do not fix:
# an inflected locale (the `set_grammatical_gender` -> profiles chain), a
# principal whose `people` row is absent, and a mention/author that IS the
# principal.
#
# Every profile-less person carries a URI-HOSTILE handle: 0 JVM aborts by
# construction. No mocks, stubs or patches — fixture rows, session, params,
# headers and format only.
require_relative "_common10"
require_relative "_frames10"
adv_setup!("K02_formats_pods_and_principal")
seed_core!

# --- extra cast -------------------------------------------------------------
CE.insert("pods", id: 3, host: "pod3.example", ssl: true)
# person 30: remote, ON A POD (pod_id 3), has a profile
CE.insert("people", id: 30, guid: "podguid0000000030", diaspora_handle: "pete@pod3.example",
          serialized_public_key: "K30", owner_id: nil, pod_id: 3, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 30, person_id: 30, first_name: "Pete", last_name: "P",
          searchable: true, nsfw: false)
# person 31: remote, ON A POD, NO profile, URI-hostile handle
CE.insert("people", id: 31, guid: "podguid0000000031", diaspora_handle: "pat@ba[d4.example",
          serialized_public_key: "K31", owner_id: nil, pod_id: 3, closed_account: false, fetch_status: 0)
# user 40 / person 40: an inflected-locale principal WITH a profile
seed_user!(uid: 40, username: "pola", language: "pl", person_id: 40,
           person_guid: "polaguid000000040", handle: "pola@localhost", profile_id: 40)
# user 41: a principal whose `people` row does NOT exist
CE.insert("users", id: 41, username: "orphan", email: "orphan@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "en", getting_started: false, disable_mail: false, sign_in_count: 1)
prime_salts!(41)
# user 42 / person 42: a principal with NO profiles row, inflected locale
seed_user!(uid: 42, username: "gerda", language: "pl", person_id: 42,
           person_guid: "gerdaguid00000042", handle: "gerda@ba[d5.example")

def post!(pid, guid, public_flag: true, author: 2, type: "StatusMessage")
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: type,
            text: "p#{pid}", public: public_flag, comments_count: 0)
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "k2cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

E = "@{erin@other.example}"
P = "@{pete@pod3.example}"

# 900 — author is ON A POD (pod_id 3). Does anything read `pods`?
post!(900, "k02guid900000000001"); comment!(1200, 900, 30, "podded #{P}")
mention!(1200, 1200, 30)
# 901 — author on a pod WITHOUT a profile (pod + wall together).
post!(901, "k02guid901000000001"); comment!(1201, 901, 31, "podwall")
# 902 — #hashtags in the comment text (Taggable.format_tags).
post!(902, "k02guid902000000001")
comment!(1202, 902, 2, "tagged #diaspora #ruby #a #b and text")
# 903 — plain control for the format sweep.
post!(903, "k02guid903000000001"); comment!(1203, 903, 2, "fmt #{E}")
mention!(1203, 1203, 5)
# 904 — BOTH mention persons absent: the nested profiles preload must be
#       skipped entirely (AR preloads from the parents it actually loaded).
post!(904, "k02guid904000000001")
comment!(1204, 904, 2, "gone @{a@ba[d6.example} @{b@ba[d7.example}")
mention!(1204, 1204, 97); mention!(1205, 1204, 98)
# 905 — post typed Reshare (a REAL Post subclass, unlike the modelled Photo).
post!(905, "k02guid905000000001", type: "Reshare"); comment!(1206, 905, 2, "resh")
# 906 — a post_id of EXACTLY 16 characters (the post_key boundary).
post!(906, "k02guid90600001x"); comment!(1207, 906, 2, "sixteen")
# 907 — the principal is BOTH the comment author and the mention target.
post!(907, "k02guid907000000001"); comment!(1208, 907, 40, "self @{pola@localhost}")
mention!(1208, 1208, 40)
# 908 — non-public post for the orphan-principal probe.
post!(908, "k02guid908000000001"); comment!(1209, 908, 2, "orphan")

CONCRETE_SCENARIOS = adv_scenario("K02-formats-pods-and-principal") do
  CompletionChecker.new_request! if defined?(CompletionChecker) && CompletionChecker.respond_to?(:new_request!)

  # --- the pods hunt --------------------------------------------------------
  req!(post_id: "900", format: :json,   tag: "K02_900_pod_author_json")
  req!(post_id: "900", format: :mobile, tag: "K02_900_pod_author_mobile")
  req!(post_id: "900", format: :json, signed_in: true, uid: 40, tag: "K02_900_pod_author_auth_json")
  req!(post_id: "901", format: :json,   tag: "K02_901_pod_wall_json")
  req!(post_id: "902", format: :json,   tag: "K02_902_hashtags_json")
  req!(post_id: "902", format: :mobile, tag: "K02_902_hashtags_mobile")

  # --- the format sweep (json/mobile are the two pinned scenarios) ----------
  req!(post_id: "903", format: :html,  tag: "K02_903_html_anon")
  req!(post_id: "903", format: :xml,   tag: "K02_903_xml_anon")
  req!(post_id: "903", format: :js,    tag: "K02_903_js_anon")
  req!(post_id: "903", format: :atom,  tag: "K02_903_atom_anon")
  req!(post_id: "903", format: :html,  signed_in: true, uid: 40, tag: "K02_903_html_auth")
  req!(post_id: "903", format: :html,  session: {mobile_view: true}, tag: "K02_903_html_mobileview_anon")
  req!(post_id: "903", format: :json,  tag: "K02_903_control_json")

  # --- preload-shape and STI states ----------------------------------------
  req!(post_id: "904", format: :json,   tag: "K02_904_both_mentions_gone_json")
  req!(post_id: "904", format: :mobile, tag: "K02_904_both_mentions_gone_mobile")
  req!(post_id: "905", format: :json,   tag: "K02_905_reshare_json")
  req!(post_id: "k02guid90600001x", format: :json, tag: "K02_906_guid16_json")

  # --- principal states -----------------------------------------------------
  req!(post_id: "907", format: :json,   signed_in: true, uid: 40, tag: "K02_907_principal_is_author_pl_json")
  req!(post_id: "907", format: :mobile, signed_in: true, uid: 40, tag: "K02_907_principal_is_author_pl_mobile")
  req!(post_id: "903", format: :json,   signed_in: true, uid: 42, tag: "K02_903_principal_no_profile_pl_json")
  req!(post_id: "908", format: :json,   signed_in: true, uid: 41, tag: "K02_908_principal_no_person_json")

  # --- SCENARIO-BODY PROBES (NOT endpoint statements) -----------------------
  # Evidence that the gap's tables ARE readable in this app — off this route.
  $adv_tag = "PROBE_S1_person_url_pods"
  adv_probe("S1 Person#url on a podded person -> reads pods?") { Person.find(30).url }
  $adv_tag = "PROBE_S2_profile_tags"
  adv_probe("S2 Profile#tags -> reads tags JOIN taggings?") { Profile.find(30).tags.to_a.size }
  $adv_tag = "PROBE_S3_grep_pods_callers"
  adv_probe("S3 which endpoint-reachable methods call url_to?") do
    %w[Person#url Person#profile_url Person#atom_url Person#receive_url].join(",")
  end
  $adv_tag = nil
  dump_frames!("K02")
end
