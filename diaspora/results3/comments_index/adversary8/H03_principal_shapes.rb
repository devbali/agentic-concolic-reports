# ROUND 8 / H03 — brief item 2: a signed-in principal whose `person` is nil.
# The corpus has 28 dumps terminating on `NoMethodError: undefined method 'id'
# for nil` and on `Module::DelegationError: User#gender delegated to
# person.gender, but person is nil`. Question 1: is that state reachable for a
# principal that passes authentication?  Question 2: if it is, does the corpus
# model everything the real run then issues -- in particular WHERE the run stops
# (which filter / which action line) and therefore which statement multiset it
# leaves behind.
#
# `set_grammatical_gender` (application_controller.rb:120-136) is a before_action
# that runs `current_user.gender` only when `I18n.inflector.inflected_locale?`,
# i.e. only for an INFLECTED locale (users.language). So the DelegationError arm
# needs BOTH an inflected language AND a nil person -- two columns, one terminal.
# Five principals, each its own uid so the harness's per-uid warden memo
# (ADVERSARY_WINS R4-N4-5) cannot hide a principal read.
require_relative "_common8"
require_relative "_frames8"
adv_setup!("H03_principal_shapes")
seed_core!

# 30: en + person + profile           (control)
seed_user!(uid: 30, username: "u30", language: "en", person_id: 30,
           person_guid: "u30guid0000000030", handle: "u30@localhost", profile_id: 40)
# 31: en + NO people row              (D5 / row 65 shape)
seed_user!(uid: 31, username: "u31", language: "en")
# 32: pl + NO people row              (inflected locale x nil person)
seed_user!(uid: 32, username: "u32", language: "pl")
# 33: pl + person + profile           (R3 row 76: principal profiles read)
seed_user!(uid: 33, username: "u33", language: "pl", person_id: 33,
           person_guid: "u33guid0000000033", handle: "u33@localhost", profile_id: 43, gender: "male")
# 34: pl + person, NO profiles row    (Person#gender -> profile nil)
seed_user!(uid: 34, username: "u34", language: "pl", person_id: 34,
           person_guid: "u34guid0000000034", handle: "u34@ex ample.com")

def post!(pid, guid, public_flag: true, author: 2, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: "StatusMessage",
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "h3cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end

post!(830, "h03guid830000000001"); comment!(840, 830, 2)
# a post that is NOT public and NOT shared with anyone: the signed-in 404 arm
post!(831, "h03guid831000000001", public_flag: false); comment!(841, 831, 2)

CONCRETE_SCENARIOS = adv_scenario("H03-principal-shapes") do
  [30, 31, 32, 33, 34].each do |u|
    req!(post_id: "830", format: :json,   signed_in: true, uid: u, tag: "H03_830_u#{u}_json")
    req!(post_id: "830", format: :mobile, signed_in: true, uid: u, tag: "H03_830_u#{u}_mobile")
  end
  # the non-public post: the visibility finders run for a principal whose
  # person is nil -- EvilQuery::VisibleShareableById#post! uses @querent.person.id
  req!(post_id: "831", format: :json, signed_in: true, uid: 31, tag: "H03_831_u31_nonpublic_json")
  req!(post_id: "831", format: :json, signed_in: true, uid: 32, tag: "H03_831_u32_nonpublic_json")
  req!(post_id: "831", format: :json, signed_in: true, uid: 30, tag: "H03_831_u30_nonpublic_json")
  # probes: what exactly raises, and is the locale inflected at all?
  adv_probe("I18n.inflector.inflected_locale?(:pl)") { I18n.inflector.inflected_locale?(:pl) }
  adv_probe("I18n.inflector.inflected_locales(:gender)") { I18n.inflector.inflected_locales(:gender).inspect }
  adv_probe("User(31).person") { User.find(31).person.inspect }
  adv_probe("User(32).gender") { User.find(32).gender.inspect }
  adv_probe("User(34).gender") { User.find(34).gender.inspect }
  dump_frames!("H03")
end
