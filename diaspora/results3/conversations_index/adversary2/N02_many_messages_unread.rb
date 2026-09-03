# N02 — MANY messages / many authors / unread counts that select a NON-last
# message: Conversation#first_unread_message does `messages.to_a[-visibility.unread]`
# (conversation.rb:34); the corpus's SampledList supports only index 0 and -1
# (one representative row) and raises NotImplementedError otherwise, so
# unread >= 2 with >= 2 messages is outside the model's domain.
#   conv 1: 4 messages (bob, alice, carol, carol), alice unread 2  -> to_a[-2] = msg 33
#   conv 2: 3 messages (bob, carol, bob), alice unread 3 == size   -> to_a[-3] = msg 41 (first)
#   conv 3: 2 messages (bob, bob), alice unread 4 > size          -> nil
#   conv 4: alice + bob + carol, 5 messages by 3 authors, unread 0 (ordered_participants 3 distinct authors)
require_relative "_common"
adv_setup!("N02_many_messages_unread"); seed_people!
CE.insert("conversations", id: 1, subject: "four msgs", guid: "convguid1", author_id: 2)
CE.insert("conversation_visibilities", id: 21, conversation_id: 1, person_id: 1, unread: 2)
CE.insert("conversation_visibilities", id: 22, conversation_id: 1, person_id: 2, unread: 0)
CE.insert("conversation_visibilities", id: 23, conversation_id: 1, person_id: 3, unread: 0)
CE.insert("messages", id: 31, conversation_id: 1, author_id: 2, guid: "m31", text: "one by bob", created_at: "2026-01-01 00:00:01")
CE.insert("messages", id: 32, conversation_id: 1, author_id: 1, guid: "m32", text: "two by alice", created_at: "2026-01-01 00:00:02")
CE.insert("messages", id: 33, conversation_id: 1, author_id: 3, guid: "m33", text: "three by carol", created_at: "2026-01-01 00:00:03")
CE.insert("messages", id: 34, conversation_id: 1, author_id: 3, guid: "m34", text: "four by carol", created_at: "2026-01-01 00:00:04")
CE.insert("conversations", id: 2, subject: "all unread", guid: "convguid2", author_id: 2)
CE.insert("conversation_visibilities", id: 24, conversation_id: 2, person_id: 1, unread: 3)
CE.insert("conversation_visibilities", id: 25, conversation_id: 2, person_id: 2, unread: 0)
CE.insert("conversation_visibilities", id: 26, conversation_id: 2, person_id: 3, unread: 0)
CE.insert("messages", id: 41, conversation_id: 2, author_id: 2, guid: "m41", text: "a", created_at: "2026-01-02 00:00:01")
CE.insert("messages", id: 42, conversation_id: 2, author_id: 3, guid: "m42", text: "b", created_at: "2026-01-02 00:00:02")
CE.insert("messages", id: 43, conversation_id: 2, author_id: 2, guid: "m43", text: "c", created_at: "2026-01-02 00:00:03")
CE.insert("conversations", id: 3, subject: "over unread", guid: "convguid3", author_id: 1)
CE.insert("conversation_visibilities", id: 27, conversation_id: 3, person_id: 1, unread: 4)
CE.insert("conversation_visibilities", id: 28, conversation_id: 3, person_id: 2, unread: 0)
CE.insert("messages", id: 51, conversation_id: 3, author_id: 2, guid: "m51", text: "x", created_at: "2026-01-03 00:00:01")
CE.insert("messages", id: 52, conversation_id: 3, author_id: 2, guid: "m52", text: "y", created_at: "2026-01-03 00:00:02")
CE.insert("conversations", id: 4, subject: "three authors", guid: "convguid4", author_id: 3)
CE.insert("conversation_visibilities", id: 29, conversation_id: 4, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 30, conversation_id: 4, person_id: 2, unread: 0)
CE.insert("conversation_visibilities", id: 35, conversation_id: 4, person_id: 3, unread: 0)
%w[3 1 2 3 2].each_with_index do |a, i|
  CE.insert("messages", id: 60 + i, conversation_id: 4, author_id: a.to_i, guid: "m6#{i}", text: "msg #{i}", created_at: "2026-01-04 00:00:0#{i}")
end
CONCRETE_SCENARIOS = adv_scenario("N02_many_messages_unread") do
  adv_request(format: :html, params: {}, tag: "html_plain")
  adv_request(format: :html, params: { conversation_id: "1" }, tag: "html_cid1")
  adv_request(format: :html, params: { conversation_id: "2" }, tag: "html_cid2")
  adv_request(format: :html, params: { conversation_id: "3" }, tag: "html_cid3")
  adv_request(format: :html, params: { conversation_id: "4" }, tag: "html_cid4")
  adv_request(format: :json, params: { conversation_id: "2" }, tag: "json_cid2")
  adv_request(format: :html, params: { conversation_id: "1" }, session: { mobile_view: true }, tag: "mobile_cid1")
  adv_request(format: :html, params: {}, session: { mobile_view: true }, tag: "mobile_plain")
end
