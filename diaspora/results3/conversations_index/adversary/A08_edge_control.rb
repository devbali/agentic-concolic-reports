# A08 — edge fixture states with NO expected new shape (control): bob has a
# closed account; carol is BLOCKED by alice (blocks row); message text carries
# a named mention of a NON-EXISTENT person and a bare mention of a non-
# participant; unread (5) > messages.size; NULL subject; 18 participants
# (drop(1).take(15)); a message by a NON-participant author (dave, local);
# conversation 2 with unread 3 and zero messages.
require_relative "_common"
adv_setup!("A08_edge_control"); seed_people!(bob_closed: true)
CE.insert("users", id: 10, username: "dave", email: "dave@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789", language: "en",
          getting_started: 0, disable_mail: 0, sign_in_count: 1)
CE.insert("people", id: 4, guid: "daveguid", diaspora_handle: "dave@localhost",
          serialized_public_key: "K4", owner_id: 10, closed_account: 0, fetch_status: 0)
CE.insert("profiles", id: 14, person_id: 4, first_name: "", last_name: "", searchable: 1, nsfw: 0)
CE.insert("blocks", id: 900, user_id: 9, person_id: 3)
CE.insert("conversations", id: 1, subject: nil, guid: "convguid1", author_id: 2)
CE.insert("conversation_visibilities", id: 21, conversation_id: 1, person_id: 1, unread: 5)
CE.insert("conversation_visibilities", id: 22, conversation_id: 1, person_id: 2, unread: 0)
CE.insert("conversation_visibilities", id: 23, conversation_id: 1, person_id: 3, unread: 0)
(5..19).each do |i|
  CE.insert("people", id: i, guid: "p#{i}guid", diaspora_handle: "p#{i}@remote.example",
            serialized_public_key: "K#{i}", owner_id: nil, closed_account: 0, fetch_status: 0)
  CE.insert("profiles", id: 20 + i, person_id: i, first_name: "P#{i}", last_name: nil, searchable: 1, nsfw: 0)
  CE.insert("conversation_visibilities", id: 40 + i, conversation_id: 1, person_id: i, unread: 0)
end
CE.insert("messages", id: 31, conversation_id: 1, author_id: 2, guid: "msgguid1",
          text: "hey @{Ghost Person; ghost@nowhere.example} and @{p7@remote.example} **bold** #tag http://x.example/a.png")
CE.insert("messages", id: 32, conversation_id: 1, author_id: 4, guid: "msgguid2",
          text: "dave is not a participant\n\nsecond paragraph @{alice@localhost}")
CE.insert("conversations", id: 2, subject: "unread but empty", guid: "convguid2", author_id: 1)
CE.insert("conversation_visibilities", id: 24, conversation_id: 2, person_id: 1, unread: 3)
CE.insert("conversation_visibilities", id: 25, conversation_id: 2, person_id: 2, unread: 0)
CONCRETE_SCENARIOS = adv_scenario("A08_edge_control") do
  adv_request(format: :html, params: {})
  adv_request(format: :html, params: { conversation_id: "1" })
  adv_request(format: :html, params: { conversation_id: "2" })
  adv_request(format: :json, params: { conversation_id: "1" })
end
