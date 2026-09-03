# N01 — message text carrying diaspora:// entity links. Diaspora::MessageRenderer
# #diaspora_links (lib/diaspora/message_renderer.rb:100-105) runs in BOTH
# renderers this endpoint uses — plain_text_without_markdown (html sidebar,
# _conversation.haml:38 on messages.last) and markdownified (_message.html.haml:10,
# every message of the selected conversation) — and for every diaspora://<id>/<type>/<guid>
# match with type == "post" issues `Post.exists?(guid: guid)`. The corpus pins
# message text to two concrete strings (targets.rb symbolic_instance: "hello
# world…" / a mention), so this branch family can never be taken there.
#   conv 1 (alice unread 1): msg 31 by bob links an EXISTING post (posts row 500),
#   msg 32 by carol (LAST message -> sidebar) links a MISSING post guid plus a
#   `comment` type link (type != "post": no query) and a web+diaspora:// form.
#   conv 2: 1 message by bob with a link whose author part has a port.
require_relative "_common"
adv_setup!("N01_diaspora_post_links"); seed_people!
CE.insert("posts", id: 500, author_id: 2, guid: "postguid0123456789abcdef", type: "StatusMessage", public: 1, text: "linked post")
CE.insert("conversations", id: 1, subject: "links", guid: "convguid1", author_id: 2)
CE.insert("conversation_visibilities", id: 21, conversation_id: 1, person_id: 1, unread: 1)
CE.insert("conversation_visibilities", id: 22, conversation_id: 1, person_id: 2, unread: 0)
CE.insert("conversation_visibilities", id: 23, conversation_id: 1, person_id: 3, unread: 0)
CE.insert("messages", id: 31, conversation_id: 1, author_id: 2, guid: "msgguid1",
          text: "see diaspora://bob@remote.example/post/postguid0123456789abcdef please")
CE.insert("messages", id: 32, conversation_id: 1, author_id: 3, guid: "msgguid2",
          text: "gone: diaspora://carol@remote.example/post/missingguid0123456789xyz and " \
                "web+diaspora://bob@remote.example/comment/commentguid0123456789ab and " \
                "web+diaspora://alice@localhost/post/postguid0123456789abcdef")
CE.insert("conversations", id: 2, subject: "port", guid: "convguid2", author_id: 1)
CE.insert("conversation_visibilities", id: 24, conversation_id: 2, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 25, conversation_id: 2, person_id: 2, unread: 0)
CE.insert("messages", id: 33, conversation_id: 2, author_id: 2, guid: "msgguid3",
          text: "diaspora://bob@remote.example:3000/post/anotherguid0123456789ab end")
CONCRETE_SCENARIOS = adv_scenario("N01_diaspora_post_links") do
  adv_request(format: :html, params: {}, tag: "html_plain")
  adv_request(format: :html, params: { conversation_id: "1" }, tag: "html_cid1")
  adv_request(format: :html, params: { conversation_id: "2" }, tag: "html_cid2")
  adv_request(format: :html, params: {}, session: { mobile_view: true }, tag: "mobile_plain")
  adv_request(format: :html, params: { conversation_id: "1" }, session: { mobile_view: true }, tag: "mobile_cid1")
  adv_request(format: :json, params: { conversation_id: "1" }, tag: "json_cid1")
end
