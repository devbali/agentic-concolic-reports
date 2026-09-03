# A02 — notification whose polymorphic TARGET is a Photo.
# Reachable state: Comment#commentable is polymorphic and Photo includes
# Diaspora::Commentable, so commenting on a photo makes
# Notifications::CommentOnPost / AlsoCommented carry target_type "Photo".
# Attack: (a) the polymorphic preload then reads the `photos` table;
# (b) posts_helper.rb:10 `post.status_message_author_name` walks
# Photo#status_message (belongs_to :status_message, foreign_key:
# :status_message_guid, primary_key: :guid) -> a posts read keyed by GUID.
ADV_TAG = "A02"
require_relative "_common"

adv_base_fixtures!

SM_GUID = "advpostguid000000000101"
CE.insert("posts", id: 101, author_id: 2, guid: SM_GUID, type: "StatusMessage",
          text: "the status message that owns the photo", public: 1,
          likes_count: 0, comments_count: 1, reshares_count: 0, interacted_at: ts)
CE.insert("photos", id: 200, author_id: 2, guid: "advphotoguid00000000200",
          public: 1, pending: 0, status_message_guid: SM_GUID,
          processed_image: "p.jpg", height: 10, width: 10, comments_count: 1)
CE.insert("comments", id: 300, commentable_id: 200, commentable_type: "Photo",
          author_id: 2, guid: "advcommentguid00000300a", likes_count: 0, text: "nice photo")

CE.insert("notifications", id: 510, recipient_id: 9, type: "Notifications::CommentOnPost",
          target_type: "Photo", target_id: 200, unread: 1, updated_at: ts(0, -10))
CE.insert("notification_actors", id: 610, notification_id: 510, person_id: 2)
CE.insert("notifications", id: 511, recipient_id: 9, type: "Notifications::AlsoCommented",
          target_type: "Photo", target_id: 200, unread: 1, updated_at: ts(0, -20))
CE.insert("notification_actors", id: 611, notification_id: 511, person_id: 2)
CE.insert("notifications", id: 512, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 101, unread: 0, updated_at: ts(0, -30))
CE.insert("notification_actors", id: 612, notification_id: 512, person_id: 2)

adv_prime!

CONCRETE_SCENARIOS = [
  { name: "adv-A02-photo-target",
    targets: ADV_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      adv_request("A02 html plain", format: :html, params: {}, body_out: "html")
      adv_request("A02 json plain", format: :json, params: {}, body_out: "json")
      adv_request("A02 mobile",     format: :html, params: {}, session: {mobile_view: true})
      adv_request("A02 xml plain",  format: :xml,  params: {})
      # orphan photo: status_message_guid points at nothing -> Photo#status_message
      # is nil -> delegate :author_name raises. Inserted LAST so the healthy
      # requests above are unaffected (fixtures are data, not code).
      CE.insert("photos", id: 201, author_id: 2, guid: "advphotoguid00000000201",
                public: 1, pending: 0, status_message_guid: nil,
                processed_image: "q.jpg", height: 10, width: 10, comments_count: 0)
      CE.insert("notifications", id: 513, recipient_id: 9, type: "Notifications::CommentOnPost",
                target_type: "Photo", target_id: 201, unread: 1, updated_at: ts(0, -5))
      CE.insert("notification_actors", id: 613, notification_id: 513, person_id: 2)
      adv_request("A02 html orphan-photo", format: :html, params: {})
    end },
]
