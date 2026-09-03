# A05 — StartedSharing with NO contact row, and a notification STI type that
# is not in NotificationsController#types (Notifications::PrivateMessage,
# whose polymorphic target is a Conversation -> a table the corpus never
# reads). Each edge is isolated with params[:type] so one 500 cannot hide
# the others.
ADV_TAG = "A05"
require_relative "_common"

adv_base_fixtures!
CE.insert("people", id: 3, guid: "advpersonguid3", diaspora_handle: "carol@localhost",
          serialized_public_key: "K3", owner_id: nil, closed_account: 0, fetch_status: 0)
CE.insert("profiles", id: 13, person_id: 3, first_name: "Carol", last_name: "C",
          searchable: 1, nsfw: 0, public_details: 0)
CE.insert("posts", id: 101, author_id: 2, guid: "advpostguid000000000101", type: "StatusMessage",
          text: "a post", public: 1, likes_count: 1, comments_count: 0,
          reshares_count: 0, interacted_at: ts)

# 529 — control: a plain Liked notification (type=liked isolates it)
CE.insert("notifications", id: 529, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 101, unread: 1, updated_at: ts(0, -10))
CE.insert("notification_actors", id: 629, notification_id: 529, person_id: 2)
# 522 — StartedSharing from carol, for whom alice has NO contacts row
CE.insert("notifications", id: 522, recipient_id: 9, type: "Notifications::StartedSharing",
          target_type: "Person", target_id: 3, unread: 1, updated_at: ts(0, -20))
CE.insert("notification_actors", id: 622, notification_id: 522, person_id: 3)

adv_prime!

CONCRETE_SCENARIOS = [
  { name: "adv-A05-sharing-and-pm",
    targets: ADV_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      adv_request("A05 html type=liked",           format: :html, params: {type: "liked"})
      adv_request("A05 html type=started_sharing", format: :html,
                  params: {type: "started_sharing"}, body_out: "ss")
      adv_request("A05 json type=started_sharing", format: :json,
                  params: {type: "started_sharing"})
      # add a PrivateMessage notification (STI class exists; not in `types`)
      CE.insert("conversations", id: 1, author_id: 2, subject: "hi", guid: "advconvguid00000000001")
      CE.insert("notifications", id: 528, recipient_id: 9, type: "Notifications::PrivateMessage",
                target_type: "Conversation", target_id: 1, unread: 1, updated_at: ts(0, -30))
      CE.insert("notification_actors", id: 628, notification_id: 528, person_id: 2)
      adv_request("A05 html plain (with PM)", format: :html, params: {}, body_out: "pm")
      adv_request("A05 json plain (with PM)", format: :json, params: {})
    end },
]
