# C12 — closing probes.
#  (i)  reachability evidence for the `users.language` third arm: does any code
#       in AVAILABLE_LANGUAGE_CODES fail `I18n.locale=`? which locales are
#       INFLECTED (the corpus's `pl` witness / `en` complement)?
#  (ii) the round-2 open near-miss "`Processor.process`'s `return '' if
#       message.blank?` is never taken" — a comment whose text is '' / blank.
#  (iii) a wide comment list (5 comments, repeated authors) and a duplicate
#       profiles row; session[:mobile_view] with an explicit json format.
require_relative "_common4"
adv_setup!("C12_edges_and_probes")
seed_core!

# (ii) blank / whitespace-only comment text (schema: NOT NULL, '' allowed;
#      `validates :text, presence: true` forbids CREATING one through the app)
CE.insert("posts", id: 410, author_id: 2, guid: "edgguid41000000001", type: "StatusMessage",
          text: "p410", public: true, comments_count: 2)
CE.insert("comments", id: 510, commentable_id: 410, commentable_type: "Post", author_id: 2,
          guid: "cguid510", text: "")
CE.insert("comments", id: 511, commentable_id: 410, commentable_type: "Post", author_id: 2,
          guid: "cguid511", text: "   ")

# (iii) five comments, three distinct authors (one repeated twice)
CE.insert("posts", id: 411, author_id: 2, guid: "edgguid41100000001", type: "StatusMessage",
          text: "p411", public: true, comments_count: 5)
[[520, 2], [521, 5], [522, 2], [523, 6], [524, 5]].each_with_index do |(cid, aid), i|
  CE.insert("comments", id: cid, commentable_id: 411, commentable_type: "Post", author_id: aid,
            guid: "cguid#{cid}", text: "comment #{i} by #{aid}")
end

# a SECOND profiles row for person 6 (profiles.person_id has no unique index)
CE.insert("profiles", id: 26, person_id: 6, first_name: "Frank2", last_name: "F2",
          searchable: true, nsfw: false)

CONCRETE_SCENARIOS = adv_scenario("C12-edges-and-probes") do
  adv_probe("locales-unavailable") do
    (AVAILABLE_LANGUAGE_CODES.map(&:to_s) - I18n.available_locales.map(&:to_s)).inspect
  end
  adv_probe("available-count") { [AVAILABLE_LANGUAGE_CODES.size, I18n.available_locales.size].inspect }
  adv_probe("inflected-locales") { I18n.inflector.inflected_locales(:gender).map(&:to_s).sort.inspect }
  adv_probe("faraday-adapter") { Faraday.default_adapter.inspect }
  adv_probe("enforce-available") { I18n.enforce_available_locales.inspect }
  adv_probe("post-subclasses") { Post.descendants.map(&:name).sort.inspect }

  adv_request(post_id: "410", format: :json,   tag: "C12_blanktext_json")
  adv_request(post_id: "410", format: :mobile, tag: "C12_blanktext_mobile")
  adv_request(post_id: "411", format: :json,   tag: "C12_five_json")
  adv_request(post_id: "411", format: :mobile, tag: "C12_five_mobile")
  adv_request(post_id: "411", format: :json, session: {mobile_view: true}, tag: "C12_json_with_mobileview")
  adv_request(post_id: "411", format: :json, signed_in: true, tag: "C12_five_json_auth")
end
