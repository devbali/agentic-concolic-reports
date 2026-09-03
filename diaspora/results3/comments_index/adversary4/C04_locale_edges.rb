# C04 — brief item 2a, the arms the corpus's two-valued `language` decision
# cannot express: `users.language` NULL / not an available locale, and the
# principal-shape edges (no `people` row, no `profiles` row) taken on the
# INFLECTED locale, where the failure happens inside set_grammatical_gender
# BEFORE the action body.
require_relative "_common4"
adv_setup!("C04_locale_edges")
seed_core!

# language NULL (the column is nullable, no DB default — schema.rb:573)
seed_user!(uid: 30, username: "nolang", language: nil, person_id: 30,
           person_guid: "nolangguid00000030", handle: "nolang@localhost", profile_id: 30, gender: "male")
# language not an available locale
seed_user!(uid: 31, username: "badlang", language: "xx", person_id: 31,
           person_guid: "badlanguid00000031", handle: "badlang@localhost", profile_id: 31, gender: "male")
# language empty string
seed_user!(uid: 32, username: "emptylang", language: "", person_id: 32,
           person_guid: "emptylangui0000032", handle: "emptylang@localhost", profile_id: 32, gender: "male")
# pl principal whose person has NO profiles row
seed_user!(uid: 33, username: "plnoprof", language: "pl", person_id: 33,
           person_guid: "plnoprofguid000033", handle: "plnoprof@localhost", profile_id: nil)
# pl principal with NO people row at all
seed_user!(uid: 34, username: "plnoperson", language: "pl")
# en principal with NO people row at all (round-3 B11 control)
seed_user!(uid: 35, username: "ennoperson", language: "en")

CE.insert("posts", id: 350, author_id: 2, guid: "edgeguid35000000001", type: "StatusMessage",
          text: "p350", public: true, comments_count: 1)
CE.insert("comments", id: 450, commentable_id: 350, commentable_type: "Post", author_id: 2,
          guid: "cguid450", text: "a plain comment")

CONCRETE_SCENARIOS = adv_scenario("C04-locale-edges") do
  adv_request(post_id: "350", format: :json, signed_in: true, uid: 30, tag: "C04_lang_null")
  adv_request(post_id: "350", format: :json, signed_in: true, uid: 31, tag: "C04_lang_xx")
  adv_request(post_id: "350", format: :json, signed_in: true, uid: 32, tag: "C04_lang_empty")
  adv_request(post_id: "350", format: :json, signed_in: true, uid: 33, tag: "C04_pl_noprofile")
  adv_request(post_id: "350", format: :mobile, signed_in: true, uid: 33, tag: "C04_pl_noprofile_mobile")
  adv_request(post_id: "350", format: :json, signed_in: true, uid: 34, tag: "C04_pl_noperson")
  adv_request(post_id: "350", format: :json, signed_in: true, uid: 35, tag: "C04_en_noperson")
  adv_request(post_id: "350", format: :json, signed_in: true, uid: 9,  tag: "C04_control_alice")
end
