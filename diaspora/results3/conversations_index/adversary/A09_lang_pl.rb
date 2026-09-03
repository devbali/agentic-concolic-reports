# A09 — the session user's language is an INFLECTED locale (pl):
# ApplicationController#set_grammatical_gender reads current_user.gender
# (delegated to person -> profile) before the action runs — in the JSON
# variant, where the corpus never reads the principal's profile.
require_relative "_common"
adv_setup!("A09_lang_pl"); seed_people!(alice_lang: "pl"); seed_batch_conversations!
CONCRETE_SCENARIOS = adv_scenario("A09_lang_pl") do
  adv_request(format: :json, params: {})
  adv_request(format: :html, params: {})
end
