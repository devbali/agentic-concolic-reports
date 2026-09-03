# A07 — the missing-`profiles` AUTHOR path (round-1 C08/C08b: JVM SIGSEGV).
# ISOLATED: one scenario per process so a native abort names its own seed.
# Person#name -> fix_profile -> Discovery.new(handle).fetch_and_save -> reload.
require_relative "_common2"
adv_setup!("A07_noprofile_author")
seed_people!(dave: true, dave_profile: false)
CE.insert("posts", id: 140, author_id: 2, guid: "postguid1400000001", type: "StatusMessage",
          text: "public", public: true, comments_count: 1)
CE.insert("comments", id: 350, commentable_id: 140, commentable_type: "Post",
          author_id: 4, guid: "cguid350", text: "author dave has no profiles row")

CONCRETE_SCENARIOS = adv_scenario("A07-noprofile-author") do
  adv_request(post_id: "140", format: :json, tag: "A07_json")
end
