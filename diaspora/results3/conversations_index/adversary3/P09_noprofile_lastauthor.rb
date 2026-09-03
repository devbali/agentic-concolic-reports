# P09 — ISOLATED (one scenario, one process): the LAST AUTHOR has no profiles
# row, so `_conversation.haml:31 conversation.last_author.name` enters
# `Person#name` (person.rb:247-252) -> `fix_profile` (person.rb:371-375) ->
# `DiasporaFederation::Discovery::Discovery.new(...).fetch_and_save` -> `reload`.
# This is the ONE path on which the corpus's B-1 `reload` note and the
# `Discovery.new` wall could be judged by a real run. Rounds 1 and 2 aborted
# the JVM here (exit 134); DISCIPLINE §12 diagnoses it as typhoeus -> Ethon ->
# libcurl through JFFI. Run alone so the abort names its own scenario.
require_relative "_common"
adv_setup!("P09_noprofile"); seed_people!(bob_profile: false)
CE.insert("conversations", id: 1, subject: "no profile last author", guid: "cg1", author_id: 2)
CE.insert("conversation_visibilities", id: 21, conversation_id: 1, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 22, conversation_id: 1, person_id: 2, unread: 0)
CE.insert("messages", id: 31, conversation_id: 1, author_id: 2, guid: "mg1", text: "bob speaks last")

EXTRA = [[ActionDispatch::Journey::Router::Utils, :escape_segment],
         [ActiveRecord::Base, :reload],
         [Person, :fix_profile]]
begin
  require "diaspora_federation/discovery"
  EXTRA << [DiasporaFederation::Discovery::Discovery, :new]
  EXTRA << [DiasporaFederation::Discovery::Discovery, :fetch_and_save]
rescue Exception => e # rubocop:disable Lint/RescueException
  warn "[adv3] discovery not loadable: #{e.class}"
end

CONCRETE_SCENARIOS = adv_scenarios([
  { name: "P09_html_plain_noprofile_lastauthor",
    body: -> { adv_request(format: :html, params: {}, tag: "P09_html") } },
], targets: adv_targets(EXTRA))
