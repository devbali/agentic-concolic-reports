# A09 — A05 re-run with two harness defects fixed:
#   * the signed-in warden memo is now PER-UID (A05's `@concolic_user ||=` was a
#     top-level ivar, so every request in the process reused the FIRST user);
#   * both salts are primed at fixture-load time, so no `User.find` runs inside
#     the scenario body (A05's 3 "OUTSIDE any target frame" statements were mine).
# Plus a direct probe of the `posts.public = ?` bind (round-1 N8: the signed-in
# PUBLIC branch has only ever been observed MISSING on this rig).
require_relative "_common2"
adv_setup!("A10_auth_edges3")
seed_people!(alice_lang: "pl", orphan_user: true)
SALTS = { 9 => User.find(9).authenticatable_salt, 8 => User.find(8).authenticatable_salt }
USERS = {}
def install_real_warden(tc, uid = 9) # rubocop:disable Lint/DuplicateMethods
  salt = SALTS.fetch(uid)
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  wuser = lambda { |*_a| USERS[uid] ||= User.serialize_from_session(uid, salt) }
  warden.define_singleton_method(:authenticate!) { |*a| wuser.call(*a) || raise("devise resolve failed") }
  warden.define_singleton_method(:authenticate)  { |*a| wuser.call(*a) }
  warden.define_singleton_method(:authenticated?) { |*_a| true }
  warden.define_singleton_method(:user) { |*a| wuser.call(*a) }
  warden.define_singleton_method(:session) { |*_a| {} }
  tc.instance_variable_get(:@request).env["warden"] = warden
end

# 120: bob's PUBLIC post, alice neither shares nor owns  -> public_post branch
CE.insert("posts", id: 120, author_id: 2, guid: "postguid1200000001", type: "StatusMessage",
          text: "bob public", public: true, comments_count: 1)
CE.insert("comments", id: 330, commentable_id: 120, commentable_type: "Post", author_id: 2,
          guid: "cguid330", text: "on a public post diaspora://bob@remote.example/post/postguid1200000001")
# 121: Reshare with a DANGLING root_guid, visible to alice through share_visibilities
CE.insert("posts", id: 121, author_id: 2, guid: "postguid1210000001", type: "Reshare",
          public: false, root_guid: "nosuchrootguid00001", comments_count: 1)
CE.insert("share_visibilities", id: 402, shareable_id: 121, shareable_type: "Post", user_id: 9, hidden: false)
CE.insert("comments", id: 331, commentable_id: 121, commentable_type: "Post", author_id: 2,
          guid: "cguid331", text: "on a rootless reshare @{Bob; bob@remote.example}")
CE.insert("mentions", id: 940, mentions_container_id: 331, mentions_container_type: "Comment", person_id: 2)
# 122: a `Photo`-typed posts row (Photo is NOT a Post subclass in this app)
CE.insert("posts", id: 122, author_id: 2, guid: "postguid1220000001", type: "Photo",
          public: false, comments_count: 1)
CE.insert("share_visibilities", id: 403, shareable_id: 122, shareable_type: "Post", user_id: 9, hidden: false)
CE.insert("comments", id: 332, commentable_id: 122, commentable_type: "Post", author_id: 2,
          guid: "cguid332", text: "on a Photo-typed posts row")
# 123: shared with gina (user 8, who has NO people row)
CE.insert("posts", id: 123, author_id: 2, guid: "postguid1230000001", type: "StatusMessage",
          text: "shared with gina", public: false, comments_count: 1)
CE.insert("share_visibilities", id: 401, shareable_id: 123, shareable_type: "Post", user_id: 8, hidden: false)
CE.insert("comments", id: 333, commentable_id: 123, commentable_type: "Post", author_id: 2,
          guid: "cguid333", text: "gina can see this")
# 124: gina can neither see nor own  -> querent_is_author -> @querent.person.id
CE.insert("posts", id: 124, author_id: 2, guid: "postguid1240000001", type: "StatusMessage",
          text: "gina cannot see", public: false, comments_count: 0)
# 125: a share_visibilities row with hidden = true
CE.insert("posts", id: 125, author_id: 2, guid: "postguid1250000001", type: "StatusMessage",
          text: "hidden share", public: false, comments_count: 1)
CE.insert("share_visibilities", id: 404, shareable_id: 125, shareable_type: "Post", user_id: 9, hidden: true)
CE.insert("comments", id: 334, commentable_id: 125, commentable_type: "Post", author_id: 2,
          guid: "cguid334", text: "hidden-visibility comment")

CONCRETE_SCENARIOS = adv_scenario("A10-auth-edges-3") do
  # A09 proved the "JDBC boolean artefact" is a FIXTURE representation mismatch:
  # ActiveRecord quotes `true` as 't' for this adapter, ConcreteEnv.insert writes 1.
  # Re-writing the column through AR's own quoting makes the public branch match.
  # (A09 additionally ran pluck/count PROBES, which are harness statements and made
  #  its judge RED; this run issues none, so the verdict is about the endpoint only.)
  Post.where(id: 120).update_all(public: true)


  adv_request(post_id: "120", format: :json, signed_in: true, tag: "A10_public_branch_json")
  adv_request(post_id: "120", format: :mobile, signed_in: true, tag: "A10_public_branch_mobile")
  adv_request(post_id: "121", format: :json, signed_in: true, tag: "A10_reshare_rootless_json")
  adv_request(post_id: "121", format: :mobile, signed_in: true, tag: "A10_reshare_rootless_mobile")
  adv_request(post_id: "122", format: :json, signed_in: true, tag: "A10_photo_typed_json")
  adv_request(post_id: "125", format: :json, signed_in: true, tag: "A10_hidden_share_json")
  adv_request(post_id: "120", format: :html, signed_in: true, tag: "A10_html_after_chain")
  adv_request(post_id: "120", format: :xml, signed_in: true, tag: "A10_xml")
  # gina (user 8): no people row
  adv_request(post_id: "123", format: :json, signed_in: true, uid: 8, tag: "A10_orphan_vis_json")
  adv_request(post_id: "124", format: :json, signed_in: true, uid: 8, tag: "A10_orphan_author_json")
end

