# E06 — ROUND 6, NON-REQUEST probes only.  Kept in its own process and its own
# run file so its measurement SQL never pollutes the judged manifests
# (round-2 lesson: A09's probes produced RED "OUTSIDE any target frame" lines).
require_relative "_common6"
adv_setup!("E06_probes")
seed_core!
CE.insert("posts", id: 750, author_id: 2, guid: "e06guid750000000001", type: "StatusMessage",
          text: "p750", public: true, comments_count: 0)
CE.insert("comments", id: 890, commentable_id: 750, commentable_type: "Post", author_id: 2,
          guid: "e6cguid890", text: "a", created_at: "2020-01-01 00:00:01")
CE.insert("comments", id: 891, commentable_id: 750, commentable_type: "Post", author_id: 5,
          guid: "e6cguid891", text: "b", created_at: "2020-01-01 00:00:02")
CE.insert("mentions", id: 940, mentions_container_id: 890, mentions_container_type: "Comment", person_id: 5)

CONCRETE_SCENARIOS = adv_scenario("E06-probes") do
  # 1. is a duplicate (person_id, container_id, container_type) a DATABASE state?
  adv_probe("01-mentions-unique-index-dup") do
    CE.insert("mentions", id: 941, mentions_container_id: 890,
              mentions_container_type: "Comment", person_id: 5)
    "INSERT SUCCEEDED (index NOT enforced here)"
  end
  adv_probe("02-mentions-index-list") do
    ActiveRecord::Base.connection.indexes("mentions").map { |i| [i.name, i.columns, i.unique] }
  end
  # 2. the Preloader's key model, measured directly
  adv_probe("03-preload-two-authors") do
    sqls = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*a|
      p = a.last; sqls << p[:sql] unless p[:cached] || %w[SCHEMA TRANSACTION].include?(p[:name].to_s) }
    Comment.where(commentable_id: 750, commentable_type: "Post").includes(author: :profile).to_a
    ActiveSupport::Notifications.unsubscribe(sub)
    sqls
  end
  adv_probe("04-preload-one-author") do
    sqls = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*a|
      p = a.last; sqls << p[:sql] unless p[:cached] || %w[SCHEMA TRANSACTION].include?(p[:name].to_s) }
    Comment.where(id: [890]).includes(author: :profile).to_a
    ActiveSupport::Notifications.unsubscribe(sub)
    sqls
  end
  # 3. is `profiles.person_id = ?` reachable after `people.id IN (?,?)`?
  adv_probe("05-nested-after-IN") do
    sqls = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*a|
      p = a.last; sqls << p[:sql] unless p[:cached] || %w[SCHEMA TRANSACTION].include?(p[:name].to_s) }
    # two comments, two distinct authors, ONE of whom has no profile row
    Person.connection.execute("DELETE FROM profiles WHERE person_id = 5")
    Comment.where(commentable_id: 750, commentable_type: "Post").includes(author: :profile).to_a
    ActiveSupport::Notifications.unsubscribe(sub)
    sqls
  end
  adv_probe("06-sti-descendants") { [Post.descendants.map(&:name), Photo.superclass.name] }
  adv_probe("07-enforce-available-locales") { I18n.enforce_available_locales }
  adv_probe("08-comments-fk-enforced") do
    ActiveRecord::Base.connection.execute("PRAGMA foreign_keys")
    ActiveRecord::Base.connection.select_value("PRAGMA foreign_keys")
  end
  adv_probe("09-diaspora-url-regex") do
    DiasporaFederation::Federation::DiasporaUrlParser::DIASPORA_URL_REGEX.source[0, 300]
  end
  adv_probe("10-reshare-root-missing") do
    CE.insert("posts", id: 751, author_id: 2, guid: "e06guid751000000001", type: "Reshare",
              text: "r", public: true, comments_count: 0, root_guid: "nope0000000000000001")
    p = Post.find(751)
    [p.class.name, p.root.inspect[0, 60]]
  end
end
