# P06 — per-render MULTIPLICITY and the Rule D (DISCIPLINE §13) claim that the
# distinct-key machinery is INERT here.
#  * `_conversation.mobile.haml` renders `_conversation_subject.haml:3
#    conversation.messages.size` (a COUNT) and then `:16
#    conversation.last_author.present?` -> `conversation.rb:55 messages.size > 0`
#    (a SECOND COUNT of the same relation, because the first one only calls
#    `loaded!` when the count is ZERO — activerecord collection_association.rb
#    #count_records). The corpus emits ONE `COUNT(*) FROM "messages"` note per
#    conversation representative.
#  * `_conversation.haml:38 other_participants.drop(1).take(15).each` issues one
#    `profiles.person_id = ? LIMIT 1` per rendered participant.
#  * also traces escape_segment / Base#reload / Discovery.new / Person#fix_profile
#    at depth 0 (B-1 / B-2 verification on a path that does NOT abort the JVM).
require_relative "_common"
adv_setup!("P06_cardinality"); seed_people!

EXTRA = []
EXTRA << [ActionDispatch::Journey::Router::Utils, :escape_segment]
EXTRA << [ActiveRecord::Base, :reload]
EXTRA << [Person, :fix_profile]
begin
  require "diaspora_federation/discovery"
  EXTRA << [DiasporaFederation::Discovery::Discovery, :new]
rescue Exception => e # rubocop:disable Lint/RescueException
  warn "[adv3] discovery not loadable: #{e.class}"
end

# conv 1 — 5 messages by 2 authors, 6 participants (people 2,3,4,5,6 + alice)
(4..6).each do |i|
  CE.insert("people", id: i, guid: "g#{i}", diaspora_handle: "p#{i}@remote.example",
            serialized_public_key: "K#{i}", owner_id: nil, closed_account: false, fetch_status: 0)
  CE.insert("profiles", id: 20 + i, person_id: i, first_name: "P#{i}", last_name: "L", searchable: true, nsfw: false)
end
CE.insert("conversations", id: 1, subject: "five messages", guid: "cg1", author_id: 2)
[1, 2, 3, 4, 5, 6].each_with_index do |pid, ix|
  CE.insert("conversation_visibilities", id: 40 + ix, conversation_id: 1, person_id: pid, unread: (pid == 1 ? 2 : 0))
end
5.times do |i|
  CE.insert("messages", id: 50 + i, conversation_id: 1, author_id: (i.even? ? 2 : 3),
            guid: "mg#{i}", text: "message number #{i}")
end
# conv 2 — ZERO messages (the count-records `loaded!` short-circuit)
CE.insert("conversations", id: 2, subject: "no messages", guid: "cg2", author_id: 2)
CE.insert("conversation_visibilities", id: 60, conversation_id: 2, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 61, conversation_id: 2, person_id: 2, unread: 0)
# conv 3 — ONE message, TWO participants (the minimal shape)
CE.insert("conversations", id: 3, subject: "solo", guid: "cg3", author_id: 2)
CE.insert("conversation_visibilities", id: 62, conversation_id: 3, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 63, conversation_id: 3, person_id: 2, unread: 0)
CE.insert("messages", id: 70, conversation_id: 3, author_id: 2, guid: "mg70", text: "only one")

def req(tag, fmt, params = {}, session = {})
  { name: "P06_#{tag}",
    body: -> { adv_request(format: fmt, params: params, session: session, tag: tag) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("html_plain",   :html),
  req("mobile_plain", :html, {}, { mobile_view: true }),
  req("html_cid1",    :html, { conversation_id: "1" }),
  req("mobile_cid1",  :html, { conversation_id: "1" }, { mobile_view: true }),
  req("json_plain",   :json),
  req("html_cid2",    :html, { conversation_id: "2" }),
  req("html_cid3",    :html, { conversation_id: "3" }),
], targets: adv_targets(EXTRA))
