# A01 — post/comment TEXT carrying diaspora:// links.
# Attack: Diaspora::MessageRenderer#title (a declared TARGET whose corpus
# note is the non-SQL string "Diaspora::MessageRenderer#title") runs
# plain_text_without_markdown -> Processor#diaspora_links, which issues
# Post.exists?(guid: <guid parsed out of the text>).
ADV_TAG = "A01"
require_relative "_common"

adv_base_fixtures!

EXIST_GUID = "advpostguid000000000001"  # >= 16 chars: DIASPORA_URL_REGEX guid rule
MISS_GUID  = "advmissingguid0000000009"
CGUID      = "advcommentguid00000000c1"

# post 101: the post the links point AT (exists)
CE.insert("posts", id: 101, author_id: 2, guid: EXIST_GUID, type: "StatusMessage",
          text: "the linked post", public: 1, likes_count: 0, comments_count: 1,
          reshares_count: 0, interacted_at: ts)
# post 100: Liked / MentionedInPost target; text carries three diaspora URLs
CE.insert("posts", id: 100, author_id: 2, guid: "advpostguid000000000100", type: "StatusMessage",
          text: "see diaspora://bob@remote.example/post/#{EXIST_GUID} and " \
                "web+diaspora://bob@remote.example/post/#{MISS_GUID} and " \
                "diaspora://bob@remote.example/comment/#{CGUID} end @{alice@localhost}",
          public: 1, likes_count: 1, comments_count: 1, reshares_count: 0, interacted_at: ts)
# post 102: AlsoCommented target; one link, to the existing post
CE.insert("posts", id: 102, author_id: 2, guid: "advpostguid000000000102", type: "StatusMessage",
          text: "also diaspora://alice@localhost/post/#{EXIST_GUID} ok",
          public: 1, likes_count: 0, comments_count: 1, reshares_count: 0, interacted_at: ts)

# comment 300 on post 100 — MentionedInComment container; its own link
CE.insert("comments", id: 300, commentable_id: 100, commentable_type: "Post",
          author_id: 2, guid: CGUID, likes_count: 0,
          text: "comment diaspora://bob@remote.example/post/#{EXIST_GUID} here")

CE.insert("mentions", id: 900, mentions_container_id: 100, mentions_container_type: "Post", person_id: 1)
CE.insert("mentions", id: 901, mentions_container_id: 300, mentions_container_type: "Comment", person_id: 1)

CE.insert("notifications", id: 500, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 100, unread: 1, updated_at: ts(0, -10))
CE.insert("notification_actors", id: 600, notification_id: 500, person_id: 2)
CE.insert("notifications", id: 502, recipient_id: 9, type: "Notifications::MentionedInPost",
          target_type: "Mention", target_id: 900, unread: 1, updated_at: ts(0, -20))
CE.insert("notification_actors", id: 602, notification_id: 502, person_id: 2)
CE.insert("notifications", id: 504, recipient_id: 9, type: "Notifications::MentionedInComment",
          target_type: "Mention", target_id: 901, unread: 1, updated_at: ts(0, -30))
CE.insert("notification_actors", id: 604, notification_id: 504, person_id: 2)
CE.insert("notifications", id: 505, recipient_id: 9, type: "Notifications::AlsoCommented",
          target_type: "Post", target_id: 102, unread: 0, updated_at: ts(0, -40))
CE.insert("notification_actors", id: 605, notification_id: 505, person_id: 2)
CE.insert("notifications", id: 506, recipient_id: 9, type: "Notifications::Reshared",
          target_type: "Post", target_id: 100, unread: 0, updated_at: ts(0, -50))
CE.insert("notification_actors", id: 606, notification_id: 506, person_id: 2)

adv_prime!

CONCRETE_SCENARIOS = [
  { name: "adv-A01-diaspora-links",
    targets: ADV_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      adv_request("A01 html plain",  format: :html, params: {}, body_out: "html")
      adv_request("A01 json plain",  format: :json, params: {}, body_out: "json")
      adv_request("A01 mobile",      format: :html, params: {},
                  session: {mobile_view: true}, body_out: "mobile")
      adv_request("A01 html typed",  format: :html, params: {type: "liked"})
      adv_request("A01 xml plain",   format: :xml,  params: {})
    end },
]
