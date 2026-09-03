# C03 — brief item 2a: the `users.language` decision, the principal `profiles`
# read that set_locale/set_grammatical_gender perform on the signed-in path
# (shape + bind), and whether the `profiles.gender` PIN is honest (does the
# statement set differ between gender values?).
require_relative "_common4"
adv_setup!("C03_locale_gender")
seed_core!                                   # user 9 alice, language "en"

seed_user!(uid: 20, username: "polly", language: "pl", person_id: 20,
           person_guid: "pollyguid000000020", handle: "polly@localhost",
           profile_id: 20, gender: "male")
seed_user!(uid: 21, username: "paula", language: "pl", person_id: 21,
           person_guid: "paulaguid000000021", handle: "paula@localhost",
           profile_id: 21)                    # gender column left NULL
seed_user!(uid: 22, username: "pablo", language: "pl", person_id: 22,
           person_guid: "pabloguid000000022", handle: "pablo@localhost",
           profile_id: 22, gender: "!()[]\"'`*=|/#.,-:")   # tr() strips it to ""
seed_user!(uid: 23, username: "petra", language: "pl", person_id: 23,
           person_guid: "petraguid000000023", handle: "petra@localhost",
           profile_id: 23, gender: "female")
seed_user!(uid: 24, username: "dieter", language: "de", person_id: 24,
           person_guid: "dieterguid00000024", handle: "dieter@localhost",
           profile_id: 24, gender: "male")
seed_user!(uid: 25, username: "france", language: "fr", person_id: 25,
           person_guid: "franceguid00000025", handle: "france@localhost",
           profile_id: 25, gender: "male")

CE.insert("posts", id: 340, author_id: 2, guid: "locguid34000000001", type: "StatusMessage",
          text: "p340", public: true, comments_count: 1)
CE.insert("comments", id: 440, commentable_id: 340, commentable_type: "Post", author_id: 2,
          guid: "cguid440", text: "a plain comment")

CONCRETE_SCENARIOS = adv_scenario("C03-locale-gender") do
  adv_request(post_id: "340", format: :json, signed_in: true, uid: 9,  tag: "C03_en_alice")
  adv_request(post_id: "340", format: :json, signed_in: true, uid: 20, tag: "C03_pl_male")
  adv_request(post_id: "340", format: :json, signed_in: true, uid: 21, tag: "C03_pl_nullgender")
  adv_request(post_id: "340", format: :json, signed_in: true, uid: 22, tag: "C03_pl_punctgender")
  adv_request(post_id: "340", format: :json, signed_in: true, uid: 23, tag: "C03_pl_female")
  adv_request(post_id: "340", format: :json, signed_in: true, uid: 24, tag: "C03_de")
  adv_request(post_id: "340", format: :json, signed_in: true, uid: 25, tag: "C03_fr")
  adv_request(post_id: "340", format: :mobile, signed_in: true, uid: 20, tag: "C03_pl_male_mobile")
  adv_request(post_id: "340", format: :mobile, signed_in: true, uid: 9,  tag: "C03_en_alice_mobile")
end
