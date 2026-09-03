# G03 — ROUND 7, brief item 2(b): can a comment's `mentions` relation ever
# repeat a person, so that the key count is NOT the row count?
# The cycle-8 rule DERIVES the mentions step's key count from the row count on
# the strength of db/schema.rb:207
#   index ["person_id","mentions_container_id","mentions_container_type"], unique: true
# Every way the adversary can think of to defeat it is tried against the REAL
# database and the REAL relation: a straight duplicate, a NULL person_id, a
# case-differing container type, a padded container type, a second container,
# and the same person mentioned on the post AND on the comment.
require_relative "_common7"
adv_setup!("G03_unique_index")
seed_core!

def post!(pid, guid, public_flag: true, author: 2, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: "StatusMessage",
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "g3cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
ERIN = "@{Erin; erin@other.example}"

post!(880, "g03guid880000000001"); comment!(940, 880, 2, "hi #{ERIN} bye")
post!(881, "g03guid881000000001"); comment!(941, 881, 2, "hi #{ERIN} bye")
post!(882, "g03guid882000000001"); comment!(942, 882, 2, "hi #{ERIN} bye")
post!(883, "g03guid883000000001"); comment!(943, 883, 2, "hi #{ERIN} bye")

CONCRETE_SCENARIOS = adv_scenario("G03-unique-index") do
  conn = ActiveRecord::Base.connection

  adv_probe("index_list(mentions)") { conn.select_all("PRAGMA index_list(mentions)").to_a }
  adv_probe("index_info(unique)") {
    conn.select_all("PRAGMA index_list(mentions)").to_a
        .select { |r| r["unique"].to_i == 1 }
        .map { |r| [r["name"], conn.select_all("PRAGMA index_info(#{conn.quote(r['name'])})").to_a] }
  }
  adv_probe("mentions_columns_notnull") {
    conn.columns("mentions").map { |c| [c.name, c.null] }
  }
  adv_probe("in_clause_length") { conn.in_clause_length }
  adv_probe("Post.descendants") { Post.descendants.map(&:name) }
  adv_probe("Mention.person reflection") {
    r = Mention.reflect_on_association(:person)
    [r.macro, r.belongs_to?, r.foreign_key, r.polymorphic?, r.klass.name,
     Comment.reflect_on_association(:mentions).macro,
     Comment.reflect_on_association(:mentions).type]
  }

  # 1. straight duplicate (person 5 twice on comment 940)
  CE.insert("mentions", id: 990, mentions_container_id: 940, mentions_container_type: "Comment", person_id: 5)
  adv_probe("dup_same_person_same_container") {
    CE.insert("mentions", id: 991, mentions_container_id: 940, mentions_container_type: "Comment", person_id: 5)
  }
  adv_probe("940_mentions_rows") { Comment.find(940).mentions.pluck(:id, :person_id) }

  # 2. NULL person_id
  adv_probe("null_person_id") {
    CE.insert("mentions", id: 992, mentions_container_id: 941, mentions_container_type: "Comment", person_id: nil)
  }
  # 3. case-differing container type + the same person
  CE.insert("mentions", id: 993, mentions_container_id: 941, mentions_container_type: "Comment", person_id: 5)
  adv_probe("case_differing_type") {
    CE.insert("mentions", id: 994, mentions_container_id: 941, mentions_container_type: "comment", person_id: 5)
  }
  adv_probe("941_mentions_rows") { Comment.find(941).mentions.pluck(:id, :person_id, :mentions_container_type) }
  adv_probe("941_raw_rows") {
    conn.select_all("SELECT id, person_id, mentions_container_type FROM mentions WHERE mentions_container_id = 941").to_a
  }

  # 4. padded container type
  CE.insert("mentions", id: 995, mentions_container_id: 942, mentions_container_type: "Comment", person_id: 5)
  adv_probe("padded_type") {
    CE.insert("mentions", id: 996, mentions_container_id: 942, mentions_container_type: "Comment ", person_id: 5)
  }
  adv_probe("942_mentions_rows") { Comment.find(942).mentions.pluck(:id, :person_id, :mentions_container_type) }

  # 5. same person mentioned on the POST and on the COMMENT (second container)
  CE.insert("mentions", id: 997, mentions_container_id: 943, mentions_container_type: "Comment", person_id: 5)
  CE.insert("mentions", id: 998, mentions_container_id: 883, mentions_container_type: "Post", person_id: 5)
  adv_probe("943_mentions_rows") { Comment.find(943).mentions.pluck(:id, :person_id, :mentions_container_type) }

  # real requests over the rows that DID land
  adv_request(post_id: "940", format: :json, tag: "G03_bogus_postid")
  adv_request(post_id: "880", format: :json,   tag: "G03_880_dup_attempt_json")
  adv_request(post_id: "880", format: :mobile, tag: "G03_880_dup_attempt_mobile")
  adv_request(post_id: "881", format: :json,   tag: "G03_881_case_type_json")
  adv_request(post_id: "882", format: :json,   tag: "G03_882_padded_type_json")
  adv_request(post_id: "883", format: :json,   tag: "G03_883_two_containers_json")
  adv_request(post_id: "883", format: :mobile, tag: "G03_883_two_containers_mobile")
end
