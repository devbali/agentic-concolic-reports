# C10 — mobile with a no-profile AUTHOR: person_image_link returns "" (profile.nil? guard),
# then person_link -> Person#name -> fix_profile. Separate process (JVM crash risk).
require_relative "_common"
adv_setup!("C10_noprofile_mobile"); seed_people!(dave: true, dave_profile: false); seed_batch_post!
CE.insert("comments", id: 390, commentable_id: 100, commentable_type: "Post", author_id: 4, guid: "cguid390", text: "no profile author")
CONCRETE_SCENARIOS = adv_scenario("C10_noprofile_mobile") do
  adv_request(post_id: "100", format: :mobile, tag: "mobile_noprofile_author")
end
