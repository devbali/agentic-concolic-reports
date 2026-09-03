# P07 — row-level edges the corpus PINS or never expresses.
#  * `guid = ''` on a conversation, a message and a person: the corpus PINS
#    `guid` (completion_config pc_pin_ledger) with the argument that
#    `Diaspora::Fields::Guid`'s `after_initialize :set_guid` fills a blank guid
#    on EVERY instantiation, loaded rows included. Tested on real loaded rows.
#  * `subject` NULL / '' / whitespace / longer than 31 chars
#    (`_conversation_subject.haml:9 conversation.subject[0..30]`).
#  * a PARTICIPANT with no `profiles` row who is NOT the last author
#    (`person_image_tag` returns "" before `Person#name` -> fix_profile is
#    reached, so this does not enter Discovery).
#  * a closed account, a remote pod (`people.pod_id`), a NON-contact
#    participant, a message author who is not a participant.
require_relative "_common"
adv_setup!("P07_row_edges"); seed_people!(carol_profile: false)

CE.insert("pods", id: 77, host: "remote.example", ssl: true) rescue warn "[adv3] pods insert failed"
CE.insert("people", id: 4, guid: "", diaspora_handle: "blank@remote.example",
          serialized_public_key: "K4", owner_id: nil, closed_account: true, fetch_status: 0, pod_id: 77)
CE.insert("profiles", id: 14, person_id: 4, first_name: "Blank", last_name: "Guid", searchable: true, nsfw: false)
CE.insert("people", id: 5, guid: "g5", diaspora_handle: "dave@remote.example",
          serialized_public_key: "K5", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 15, person_id: 5, first_name: "", last_name: "", searchable: true, nsfw: false)

# conv 1: blank conversation guid, NULL subject, carol (no profile) participates,
# dave authors a message but is NOT a participant
CE.insert("conversations", id: 1, subject: nil, guid: "", author_id: 4)
[1, 3, 4].each_with_index { |pid, ix| CE.insert("conversation_visibilities", id: 20 + ix, conversation_id: 1, person_id: pid, unread: (pid == 1 ? 1 : 0)) }
CE.insert("messages", id: 31, conversation_id: 1, author_id: 5, guid: "", text: "from a non participant")
CE.insert("messages", id: 32, conversation_id: 1, author_id: 4, guid: "mg32", text: "closed account speaks")
# conv 2: whitespace subject, 40-char subject conv 3
CE.insert("conversations", id: 2, subject: "   ", guid: "cg2", author_id: 2)
CE.insert("conversation_visibilities", id: 25, conversation_id: 2, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 26, conversation_id: 2, person_id: 2, unread: 0)
CE.insert("conversations", id: 3, subject: "0123456789012345678901234567890123456789", guid: "cg3", author_id: 2)
CE.insert("conversation_visibilities", id: 27, conversation_id: 3, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 28, conversation_id: 3, person_id: 2, unread: 0)
CE.insert("messages", id: 33, conversation_id: 3, author_id: 2, guid: "mg33",
          text: "see diaspora://bob@remote.example/post/nopostguid0123456789ab end")

def req(tag, fmt, params = {}, session = {})
  { name: "P07_#{tag}",
    body: -> { adv_request(format: fmt, params: params, session: session, tag: tag) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  { name: "P07_guid_probe", body: lambda do
      c = Conversation.find(1); m = Message.find(31); p = Person.find(4)
      warn "[adv3] loaded guids: conversation=#{c.guid.inspect} message=#{m.guid.inspect} person=#{p.guid.inspect}"
      warn "[adv3] blank? #{c.guid.blank?} #{m.guid.blank?} #{p.guid.blank?} subject=#{c.subject.inspect}"
    end },
  req("html_plain",   :html),
  req("mobile_plain", :html, {}, { mobile_view: true }),
  req("html_cid1",    :html, { conversation_id: "1" }),
  req("mobile_cid1",  :html, { conversation_id: "1" }, { mobile_view: true }),
  req("html_cid3",    :html, { conversation_id: "3" }),
  req("json_plain",   :json),
])
