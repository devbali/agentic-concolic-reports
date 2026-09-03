# A04 — notification TARGET rows that are missing / null / actor-less.
# notifications.target_id + target_type carry NO foreign key (schema.rb),
# and notification_actors.person_id has an FK only to notifications, not to
# people -> every state below is a real database state.
ADV_TAG = "A04"
require_relative "_common"

adv_base_fixtures!
CE.insert("posts", id: 101, author_id: 2, guid: "advpostguid000000000101", type: "StatusMessage",
          text: "a post", public: 1, likes_count: 1, comments_count: 0,
          reshares_count: 0, interacted_at: ts)

# 520: Liked whose target post row is GONE -> linked_object nil -> deleted key
CE.insert("notifications", id: 520, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 999_999, unread: 1, updated_at: ts(0, -10))
CE.insert("notification_actors", id: 620, notification_id: 520, person_id: 2)
# 521: Liked with NULL polymorphic target (no type, no id)
CE.insert("notifications", id: 521, recipient_id: 9, type: "Notifications::Liked",
          target_type: nil, target_id: nil, unread: 1, updated_at: ts(0, -20))
CE.insert("notification_actors", id: 621, notification_id: 521, person_id: 2)
# 523: StartedSharing whose target PERSON is gone -> note.target.present? false
CE.insert("notifications", id: 523, recipient_id: 9, type: "Notifications::StartedSharing",
          target_type: "Person", target_id: 999_999, unread: 1, updated_at: ts(0, -30))
CE.insert("notification_actors", id: 623, notification_id: 523, person_id: 2)
# 524: ZERO notification_actors -> actors.first nil, actors.size 0
CE.insert("notifications", id: 524, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 101, unread: 0, updated_at: ts(0, -40))
# 525: an actor row whose person row does not exist
CE.insert("notifications", id: 525, recipient_id: 9, type: "Notifications::Reshared",
          target_type: "Post", target_id: 101, unread: 0, updated_at: ts(0, -50))
CE.insert("notification_actors", id: 625, notification_id: 525, person_id: 9_999)
# 526: ContactsBirthday (opts_for_birthday)
CE.insert("notifications", id: 526, recipient_id: 9, type: "Notifications::ContactsBirthday",
          target_type: "Person", target_id: 2, unread: 1, updated_at: ts(0, -60))
CE.insert("notification_actors", id: 626, notification_id: 526, person_id: 2)
# 527: Liked whose target post is a RESHARE -> post_page_title's Reshare branch
CE.insert("posts", id: 103, author_id: 2, guid: "advpostguid000000000103", type: "Reshare",
          text: nil, public: 1, root_guid: "advpostguid000000000101",
          likes_count: 1, comments_count: 0, reshares_count: 0, interacted_at: ts)
CE.insert("notifications", id: 527, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 103, unread: 0, updated_at: ts(0, -70))
CE.insert("notification_actors", id: 627, notification_id: 527, person_id: 2)

adv_prime!

CONCRETE_SCENARIOS = [
  { name: "adv-A04-missing-targets",
    targets: ADV_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      adv_request("A04 html plain", format: :html, params: {}, body_out: "html")
      adv_request("A04 json plain", format: :json, params: {}, body_out: "json")
      adv_request("A04 mobile",     format: :html, params: {}, session: {mobile_view: true})
      adv_request("A04 xml plain",  format: :xml,  params: {})
    end },
]
