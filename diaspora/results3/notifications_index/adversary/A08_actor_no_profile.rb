# A08 — an ACTOR with no `profiles` row (profiles.person_id carries no FK
# constraint from people, so this is a real state). person_link ->
# Person#name -> fix_profile -> DiasporaFederation Discovery. Isolated in
# its own process: the sibling adversaries all hit a native JVM abort here.
ADV_TAG = "A08"
require_relative "_common"

adv_base_fixtures!
CE.insert("people", id: 8, guid: "advpersonguid8", diaspora_handle: "ghost@remote.example",
          serialized_public_key: "K8", owner_id: nil, closed_account: 0, fetch_status: 0)
CE.insert("posts", id: 101, author_id: 2, guid: "advpostguid000000000101", type: "StatusMessage",
          text: "a post", public: 1, likes_count: 1, comments_count: 0,
          reshares_count: 0, interacted_at: ts)
CE.insert("notifications", id: 550, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 101, unread: 1, updated_at: ts(0, -10))
CE.insert("notification_actors", id: 680, notification_id: 550, person_id: 8)

adv_prime!

CONCRETE_SCENARIOS = [
  { name: "adv-A08-actor-no-profile",
    targets: ADV_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      adv_request("A08 html plain", format: :html, params: {}, body_out: "html")
      adv_request("A08 json plain", format: :json, params: {})
    end },
]
