# A05 — SIGNED-IN edges the corpus pins or never states.
#  (a) alice language "pl": I18n.inflector.inflected_locale? -> set_grammatical_gender
#      -> current_user.gender -> Person#profile  (a profiles read bound to the
#      DEVISE PRINCIPAL, BEFORE the action; round-1 N4)
#  (b) a signed-in User with NO people row (users.id 8, gina) — `people.owner_id`
#      has no uniqueness/NOT NULL tie to users; EvilQuery#querent_is_author does
#      `@querent.person.id`
#  (c) a blocks row alice->bob (does the endpoint read it at all?)
#  (d) STI: a Reshare whose root_guid points at nothing, and a Photo-typed row
#  (e) the signed-in PUBLIC branch (querent_has_visibility miss, querent_is_author
#      miss, public_post hit)
require_relative "_common2"
adv_setup!("A05_auth_edges")
seed_people!(alice_lang: "pl", orphan_user: true)

CE.insert("blocks", id: 500, user_id: 9, person_id: 2)

# (e) bob's PUBLIC post — alice neither shares nor owns it
CE.insert("posts", id: 120, author_id: 2, guid: "postguid1200000001", type: "StatusMessage",
          text: "bob public", public: true, comments_count: 1)
CE.insert("comments", id: 330, commentable_id: 120, commentable_type: "Post",
          author_id: 2, guid: "cguid330", text: "on a public post diaspora://bob@remote.example/post/postguid1200000001")

# (d) Reshare with a DANGLING root_guid, and one with a real root
CE.insert("posts", id: 121, author_id: 2, guid: "postguid1210000001", type: "Reshare",
          public: true, root_guid: "nosuchrootguid00001", comments_count: 1)
CE.insert("comments", id: 331, commentable_id: 121, commentable_type: "Post",
          author_id: 2, guid: "cguid331", text: "on a rootless reshare")
CE.insert("posts", id: 122, author_id: 2, guid: "postguid1220000001", type: "Photo",
          public: true, comments_count: 1)
CE.insert("comments", id: 332, commentable_id: 122, commentable_type: "Post",
          author_id: 2, guid: "cguid332", text: "on a Photo-typed posts row")

# (b) a post gina (user 8, NO person row) CAN see via share_visibilities, and one she cannot
CE.insert("posts", id: 123, author_id: 2, guid: "postguid1230000001", type: "StatusMessage",
          text: "shared with gina", public: false, comments_count: 1)
CE.insert("share_visibilities", id: 401, shareable_id: 123, shareable_type: "Post", user_id: 8, hidden: false)
CE.insert("comments", id: 333, commentable_id: 123, commentable_type: "Post",
          author_id: 2, guid: "cguid333", text: "gina can see this")
CE.insert("posts", id: 124, author_id: 2, guid: "postguid1240000001", type: "StatusMessage",
          text: "gina cannot see", public: false, comments_count: 0)

CONCRETE_SCENARIOS = adv_scenario("A05-auth-edges") do
  warn "[adv2] I18n.locale=#{I18n.locale} inflected_locale?=#{(I18n.inflector.inflected_locale? rescue 'n/a')}"
  adv_request(post_id: "120", format: :json, signed_in: true, tag: "A05_pl_public_json")
  adv_request(post_id: "120", format: :mobile, signed_in: true, tag: "A05_pl_public_mobile")
  adv_request(post_id: "121", format: :json, signed_in: true, tag: "A05_reshare_rootless_json")
  adv_request(post_id: "122", format: :json, signed_in: true, tag: "A05_photo_typed_json")
  adv_request(post_id: "123", format: :json, signed_in: true, uid: 8, tag: "A05_orphan_user_vis_json")
  adv_request(post_id: "124", format: :json, signed_in: true, uid: 8, tag: "A05_orphan_user_author_json")
  adv_request(post_id: "120", format: :json, signed_in: true, uid: 8, tag: "A05_orphan_user_public_json")
end
