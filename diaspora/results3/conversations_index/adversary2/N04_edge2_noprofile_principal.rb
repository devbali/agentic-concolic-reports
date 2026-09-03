# N04 — the PRINCIPAL (alice) has NO profile row and is the AUTHOR of a
# conversation (mobile _conversation.mobile.haml:6 person_image_tag(conversation
# .author) on a profile-less author -> people_helper.rb:37 guard; html
# _messages.haml:9 owner_image_tag -> same guard; person_link_class `current_user
# .person == person`), while alice is never a message author or last author (so
# Person#name never runs on her — no fix_profile). Plus: bob has a pods row
# (pod_id) and a closed account; conv 1 has FOUR participants (mobile
# `participants.size > 2` badge, html participants_count) with last author
# carol; conv 3 subject is whitespace-only ("   ": blank? true but != '' —
# the batch's documented pin); conv 4 subject NULL; conv 2 by alice, 0 msgs.
require_relative "_common"
adv_setup!("N04_edge2_noprofile_principal"); seed_people!(alice_profile: false, bob_closed: true)
CE.insert("pods", id: 77, host: "remote.example", ssl: 1)
ActiveRecord::Base.connection.execute("UPDATE people SET pod_id = 77 WHERE id IN (2, 3)")
CE.insert("people", id: 4, guid: "daveguid", diaspora_handle: "dave@remote.example",
          serialized_public_key: "K4", owner_id: nil, closed_account: 0, fetch_status: 0, pod_id: 77)
CE.insert("profiles", id: 14, person_id: 4, first_name: "Dave", last_name: "D", searchable: 1, nsfw: 0,
          image_url: "https://remote.example/uploads/images/dave.png", image_url_small: "https://remote.example/uploads/images/dave_s.png")
CE.insert("conversations", id: 1, subject: "four people", guid: "convguid1", author_id: 2)
[[21, 1, 1], [22, 2, 0], [23, 3, 0], [24, 4, 0]].each do |vid, pid, unread|
  CE.insert("conversation_visibilities", id: vid, conversation_id: 1, person_id: pid, unread: unread)
end
CE.insert("messages", id: 31, conversation_id: 1, author_id: 2, guid: "m31", text: "bob first", created_at: "2026-01-01 00:00:01")
CE.insert("messages", id: 32, conversation_id: 1, author_id: 4, guid: "m32", text: "dave second", created_at: "2026-01-01 00:00:02")
CE.insert("messages", id: 33, conversation_id: 1, author_id: 3, guid: "m33", text: "carol last", created_at: "2026-01-01 00:00:03")
CE.insert("conversations", id: 2, subject: "", guid: "convguid2", author_id: 1)
CE.insert("conversation_visibilities", id: 25, conversation_id: 2, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 26, conversation_id: 2, person_id: 2, unread: 0)
CE.insert("conversations", id: 3, subject: "   ", guid: "convguid3", author_id: 1)
CE.insert("conversation_visibilities", id: 27, conversation_id: 3, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 28, conversation_id: 3, person_id: 3, unread: 0)
CE.insert("messages", id: 34, conversation_id: 3, author_id: 3, guid: "m34", text: "carol in three")
CE.insert("conversations", id: 4, subject: nil, guid: "convguid4", author_id: 1)
CE.insert("conversation_visibilities", id: 29, conversation_id: 4, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 30, conversation_id: 4, person_id: 4, unread: 0)
CONCRETE_SCENARIOS = adv_scenario("N04_edge2_noprofile_principal") do
  adv_request(format: :html, params: {}, tag: "html_plain")
  adv_request(format: :html, params: { conversation_id: "1" }, tag: "html_cid1")
  adv_request(format: :html, params: { conversation_id: "3" }, tag: "html_cid3")
  adv_request(format: :html, params: {}, session: { mobile_view: true }, tag: "mobile_plain")
  adv_request(format: :html, params: { conversation_id: "1" }, session: { mobile_view: true }, tag: "mobile_cid1")
  adv_request(format: :json, params: {}, tag: "json_plain")
end
