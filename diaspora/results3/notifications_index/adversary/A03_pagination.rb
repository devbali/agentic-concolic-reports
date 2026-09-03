# A03 — pagination / per_page axes (both are CONCRETE PINS in run_dse.rb:
# "page 1 on every variant"). Attacks: (a) page beyond the last page =
# count > 0 with an EMPTY row list; (b) per_page is request-controlled but
# the corpus note bakes "LIMIT 25 OFFSET 0" in as a literal.
ADV_TAG = "A03"
require_relative "_common"

adv_base_fixtures!
CE.insert("posts", id: 101, author_id: 2, guid: "advpostguid000000000101", type: "StatusMessage",
          text: "a post", public: 1, likes_count: 30, comments_count: 0,
          reshares_count: 0, interacted_at: ts)

30.times do |i|
  CE.insert("notifications", id: 700 + i, recipient_id: 9, type: "Notifications::Liked",
            target_type: "Post", target_id: 101, unread: (i < 5 ? 1 : 0),
            updated_at: ts(0, -i))
  CE.insert("notification_actors", id: 800 + i, notification_id: 700 + i, person_id: 2)
end

adv_prime!

CONCRETE_SCENARIOS = [
  { name: "adv-A03-pagination",
    targets: ADV_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      adv_request("A03 html page2",        format: :html, params: {page: "2"}, body_out: "p2")
      adv_request("A03 html page3-beyond", format: :html, params: {page: "3"}, body_out: "p3")
      adv_request("A03 html per_page2",    format: :html, params: {per_page: "2"})
      adv_request("A03 json page2 pp2",    format: :json, params: {page: "2", per_page: "2"})
      adv_request("A03 mobile page2",      format: :html, params: {page: "2"},
                  session: {mobile_view: true})
      adv_request("A03 html page0",        format: :html, params: {page: "0"})
      adv_request("A03 html page-abc",     format: :html, params: {page: "abc"})
      adv_request("A03 html show=unread",  format: :html, params: {show: "unread", type: "liked"})
      adv_request("A03 html type-bogus",   format: :html, params: {type: "bogus"})
      adv_request("A03 html show-Unread",  format: :html, params: {show: "Unread"})
    end },
]
