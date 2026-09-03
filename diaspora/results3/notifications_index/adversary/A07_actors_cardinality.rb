# A07 — notification_people_link's >= 4 actors branch (helpers line 61-72),
# multi-day / multi-year @group_days, closed-account and remote actors.
ADV_TAG = "A07"
require_relative "_common"

adv_base_fixtures!
(3..7).each do |pid|
  CE.insert("people", id: pid, guid: "advpersonguid#{pid}",
            diaspora_handle: "p#{pid}@remote.example", serialized_public_key: "K#{pid}",
            owner_id: nil, closed_account: (pid == 5 ? 1 : 0), fetch_status: 0)
  CE.insert("profiles", id: 10 + pid, person_id: pid,
            first_name: (pid == 6 ? "" : "P#{pid}"), last_name: (pid == 6 ? "" : "L#{pid}"),
            diaspora_handle: "p#{pid}@remote.example",
            image_url: (pid == 7 ? "https://remote.example/a.jpg" : nil),
            searchable: 1, nsfw: 0, public_details: (pid == 4 ? 1 : 0))
end
CE.insert("posts", id: 101, author_id: 2, guid: "advpostguid000000000101", type: "StatusMessage",
          text: "a post", public: 1, likes_count: 5, comments_count: 0,
          reshares_count: 0, interacted_at: ts)

# 540 — FOUR actors (others.count == 1 branch)
CE.insert("notifications", id: 540, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 101, unread: 1, updated_at: ts(0, -10))
[2, 3, 4, 5].each_with_index { |p, i| CE.insert("notification_actors", id: 640 + i, notification_id: 540, person_id: p) }
# 541 — FIVE actors (others.count == 2), one day earlier
CE.insert("notifications", id: 541, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 101, unread: 1, updated_at: ts(1, -10))
[2, 3, 4, 5, 6].each_with_index { |p, i| CE.insert("notification_actors", id: 650 + i, notification_id: 541, person_id: p) }
# 542 — ONE actor, LAST YEAR (display_year? true)
CE.insert("notifications", id: 542, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 101, unread: 0, updated_at: ts(400, -10))
CE.insert("notification_actors", id: 660, notification_id: 542, person_id: 7)
# 543 — THREE actors (< 4 branch, to_sentence three-way)
CE.insert("notifications", id: 543, recipient_id: 9, type: "Notifications::Reshared",
          target_type: "Post", target_id: 101, unread: 0, updated_at: ts(2, -10))
[2, 3, 4].each_with_index { |p, i| CE.insert("notification_actors", id: 670 + i, notification_id: 543, person_id: p) }

adv_prime!

CONCRETE_SCENARIOS = [
  { name: "adv-A07-actors-cardinality",
    targets: ADV_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      adv_request("A07 html plain", format: :html, params: {}, body_out: "html")
      adv_request("A07 mobile",     format: :html, params: {}, session: {mobile_view: true},
                  body_out: "mobile")
      adv_request("A07 json plain", format: :json, params: {})
      adv_request("A07 xml plain",  format: :xml,  params: {})
    end },
]
