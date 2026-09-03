# A06 — post_page_title's PHOTOS branch (posts_helper.rb:16-18) and its
# nil fall-through. Reached when the target post's text is NULL, so
# `post.message.present?` is false.
ADV_TAG = "A06"
require_relative "_common"

adv_base_fixtures!
PG110 = "advpostguid000000000110"
PG111 = "advpostguid000000000111"
CE.insert("posts", id: 110, author_id: 2, guid: PG110, type: "StatusMessage",
          text: nil, public: 1, likes_count: 1, comments_count: 0,
          reshares_count: 0, interacted_at: ts)
CE.insert("photos", id: 210, author_id: 2, guid: "advphotoguid00000000210",
          public: 1, pending: 0, status_message_guid: PG110,
          processed_image: "a.jpg", height: 10, width: 10, comments_count: 0)
CE.insert("photos", id: 211, author_id: 2, guid: "advphotoguid00000000211",
          public: 1, pending: 0, status_message_guid: PG110,
          processed_image: "b.jpg", height: 10, width: 10, comments_count: 0)
# 111: NULL text and NO photos -> post_page_title returns nil
CE.insert("posts", id: 111, author_id: 2, guid: PG111, type: "StatusMessage",
          text: nil, public: 1, likes_count: 0, comments_count: 0,
          reshares_count: 1, interacted_at: ts)

CE.insert("notifications", id: 530, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 110, unread: 1, updated_at: ts(0, -10))
CE.insert("notification_actors", id: 630, notification_id: 530, person_id: 2)
CE.insert("notifications", id: 531, recipient_id: 9, type: "Notifications::Reshared",
          target_type: "Post", target_id: 111, unread: 0, updated_at: ts(0, -20))
CE.insert("notification_actors", id: 631, notification_id: 531, person_id: 2)
# a MentionedInPost whose container post has NULL text + photos
CE.insert("mentions", id: 910, mentions_container_id: 110, mentions_container_type: "Post", person_id: 1)
CE.insert("notifications", id: 532, recipient_id: 9, type: "Notifications::MentionedInPost",
          target_type: "Mention", target_id: 910, unread: 1, updated_at: ts(0, -30))
CE.insert("notification_actors", id: 632, notification_id: 532, person_id: 2)

adv_prime!

CONCRETE_SCENARIOS = [
  { name: "adv-A06-photos-blank-text",
    targets: ADV_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      adv_request("A06 html plain", format: :html, params: {}, body_out: "html")
      adv_request("A06 json plain", format: :json, params: {}, body_out: "json")
      adv_request("A06 mobile",     format: :html, params: {}, session: {mobile_view: true})
    end },
]
