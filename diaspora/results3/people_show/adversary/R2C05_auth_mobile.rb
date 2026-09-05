# C05 — signed-in MOBILE, other person (bob remote): the corpus's anon_mobile
# path (6000-run campaign) was ANON-ONLY. Signed-in mobile:
#  - Stream::Person#posts USER arm -> user.posts_from(bob) ->
#    Post.from_person_visible_by_user -> ShareVisibility LEFT JOIN +
#    DISTINCT posts.* (new shape; corpus stream notes are all
#    `public = TRUE AND created_at < TS` anon shapes)
#  - for_a_stream -> includes_for_a_stream (o_embed_cache, open_graph_cache,
#    author:profile, mentions:person:profile EAGER LOADS) +
#    excluding_hidden_content -> excluding_blocks -> blocked_people ->
#    user.blocks -> CollectionProxy Block rows SELECT (corpus: ZERO Block
#    targets) [+ excluding_hidden_shareables -> has_hidden_shareables_of_type?
#    serialized column check]
#  - like_posts_for_stream! -> Like.where(author_id:, target_id: in (...),
#    target_type: "Post") (new shape; corpus Like note is only the anon
#    post_stats COUNT)
#  - stream_posts.length > 0 branch + has_not_shared_with_you_yet empty branch
#  - @person.tag_string + Diaspora::Taggable.format_tags (bio tags render)
#  - block link / aspect-membership-dropdown branch (not blocked here)
require_relative "_common"

adv_setup!("R2C05_auth_mobile")
seed_people!(
  p12: {image_url: "http://remote.example/bob.png", gender: "human",
        bio: "hello #bobtag world", location: "Berlin"}
)

# contact receiving (alice follows bob — needed for shared private posts)
CE.insert("contacts", id: 63, user_id: 9, person_id: 2, sharing: 'f', receiving: 't',
         created_at: Time.now.to_s, updated_at: Time.now.to_s)

# bob's posts: 1 public, 1 private shared with alice (share_visibility row),
# 1 private NOT shared (must be excluded — proves the JOIN predicates)
CE.insert("posts", id: 110, author_id: 2, guid: "postguid110000000", type: "StatusMessage",
         text: "bob public post", public: 't', created_at: Time.now.to_s, updated_at: Time.now.to_s)
CE.insert("posts", id: 111, author_id: 2, guid: "postguid111000000", type: "StatusMessage",
         text: "bob private shared", public: 'f', created_at: Time.now.to_s, updated_at: Time.now.to_s)
CE.insert("posts", id: 112, author_id: 2, guid: "postguid112000000", type: "StatusMessage",
         text: "bob private not-shared", public: 'f', created_at: Time.now.to_s, updated_at: Time.now.to_s)
CE.insert("share_visibilities", id: 83, shareable_id: 111, shareable_type: "Post",
         user_id: 9, hidden: 'f')

# a like by alice on bob's public post (like_posts_for_stream! finds it)
CE.insert("likes", id: 151, author_id: 1, target_id: 110, target_type: "Post",
         guid: "likeguid1510000001", created_at: Time.now.to_s, updated_at: Time.now.to_s)

# a comment on bob's public post (stream_element mobile renders comments)
CE.insert("comments", id: 160, commentable_id: 110, commentable_type: "Post",
         author_id: 2, guid: "cguid160", text: "bob comment", created_at: Time.now.to_s, updated_at: Time.now.to_s)
CE.insert("comments", id: 161, commentable_id: 110, commentable_type: "Post",
         author_id: 1, guid: "cguid161", text: "alice comment", created_at: Time.now.to_s, updated_at: Time.now.to_s)

# bob's photos (mobile photo_area render inside stream_element)
CE.insert("photos", id: 741, author_id: 2, guid: "pguid7410000000001", public: 't', pending: 'f',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "bob photo", status_message_guid: "postguid110000000")

# bob's profile tags (tag_string -> format_tags)
CE.insert("tags", id: 35, name: "bobtag")
CE.insert("taggings", id: 45, tag_id: 35, taggable_id: 12, taggable_type: "Profile",
         context: "tags", created_at: Time.now.to_s)

# block row for blocked_people (CollectionProxy Block SELECT). NOTE: bob is
# NOT blocked (block is on carol) -> blocked_people returns [] but still
# loads the blocks relation.
CE.insert("blocks", id: 92, user_id: 9, person_id: 3)

CONCRETE_SCENARIOS = adv_scenario("C05_auth_mobile") do
  adv_request(username: "bob@remote.example", format: "mobile", signed_in: true, tag: "C05")
end