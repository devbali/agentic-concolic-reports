# B09 — round-2 D2: `set_grammatical_gender` (application_controller.rb:118-122)
# reads `current_user.gender` -> `Person#profile` for an INFLECTED locale,
# BEFORE the action body. The auth corpus pins `users.language` to "en", so no
# corpus note is bound to the principal's profile. Also exercises
# `gon_set_current_user` (UserPresenter) on both renderable formats.
require_relative "_common3"
adv_setup!("B09_locale_principal")
seed_core!(alice_lang: "pl")
CE.insert("posts", id: 270, author_id: 2, guid: "postguid2700000001", type: "StatusMessage",
          text: "p270", public: false, comments_count: 1)
CE.insert("share_visibilities", id: 470, shareable_id: 270, shareable_type: "Post", user_id: 9, hidden: false)
CE.insert("comments", id: 370, commentable_id: 270, commentable_type: "Post", author_id: 2,
          guid: "cguid370", text: "comment under an inflected locale")

CONCRETE_SCENARIOS = adv_scenario("B09-locale-principal") do
  adv_request(post_id: "270", format: :json,   signed_in: true, tag: "B09_pl_json_auth")
  adv_request(post_id: "270", format: :mobile, signed_in: true, tag: "B09_pl_mobile_auth")
end
