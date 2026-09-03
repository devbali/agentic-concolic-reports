# ADVERSARY common harness for comments_index (modelled on the batch's
# concrete_manifest_{anon,auth}.rb: same ConcreteEnv, same real-warden
# pattern for signed-in requests, real ActionController::TestCase#process
# dispatch so every before_action runs, real templates). NO fixtures here:
# each scenario manifest seeds its own rows. Nothing in here mocks, stubs
# or patches app code — only fixture rows, session, params, headers, format.
require "/home/dev/project/src/ruby_runtime/completion_checker/concrete_env.rb"

CE = CompletionChecker::ConcreteEnv
BATCH = "/home/dev/project/reports/diaspora/results3/comments_index"
ADV_DIR = File.expand_path("..", __FILE__)
REAL_SALT_CACHE = {}

def adv_setup!(name)
  CE.setup!(db: File.join(ADV_DIR, "runs", "#{name}.sqlite3"))
  Rails.application.config.assets.check_precompiled_asset = false
  ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)
end

# Standard cast: alice (user 9 / person 1 / profile 11, local), bob (person 2,
# remote, profile 12), carol (person 3, remote, closed account, profile 13),
# dave (person 4, remote, NO profile row — only when dave_profile: false).
def seed_people!(alice_lang: "en", dave: false, dave_profile: true)
  CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: alice_lang, getting_started: 0, disable_mail: 0, sign_in_count: 1)
  CE.insert("people", id: 1, guid: "aliceguid0000000001", diaspora_handle: "alice@localhost",
            serialized_public_key: "K1", owner_id: 9, closed_account: 0, fetch_status: 0)
  CE.insert("people", id: 2, guid: "bobguid000000000002", diaspora_handle: "bob@remote.example",
            serialized_public_key: "K2", owner_id: nil, closed_account: 0, fetch_status: 0)
  CE.insert("people", id: 3, guid: "carolguid0000000003", diaspora_handle: "carol@remote.example",
            serialized_public_key: "K3", owner_id: nil, closed_account: 1, fetch_status: 0)
  CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A", searchable: 1, nsfw: 0)
  CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B", searchable: 1, nsfw: 0,
            image_url: "http://remote.example/bob.png")
  CE.insert("profiles", id: 13, person_id: 3, first_name: "", last_name: "", searchable: 0, nsfw: 1)
  if dave
    CE.insert("people", id: 4, guid: "daveguid0000000004", diaspora_handle: "dave@remote.example",
              serialized_public_key: "K4", owner_id: nil, closed_account: 0, fetch_status: 0)
    CE.insert("profiles", id: 14, person_id: 4, first_name: "Dave", last_name: "D", searchable: 1, nsfw: 0) if dave_profile
  end
  REAL_SALT_CACHE[:salt] = User.find(9).authenticatable_salt
end

# The batch's anon fixture post (public, by bob, two comments, one mention row),
# with a 17-char guid so guid-keyed requests are possible.
def seed_batch_post!
  CE.insert("posts", id: 100, author_id: 2, guid: "postguid100000001", type: "StatusMessage",
            text: "a public post", public: 1, comments_count: 2)
  CE.insert("comments", id: 300, commentable_id: 100, commentable_type: "Post",
            author_id: 2, guid: "cguid300", text: "plain comment")
  CE.insert("comments", id: 301, commentable_id: 100, commentable_type: "Post",
            author_id: 1, guid: "cguid301", text: "hi @{bob@remote.example} nice")
  CE.insert("mentions", id: 900, mentions_container_id: 301,
            mentions_container_type: "Comment", person_id: 2)
end

def make_harness(controller_class)
  cname = controller_class.to_s.sub(/Controller\z/, "ConcreteTest")
  Object.const_set(cname, Class.new(ActionController::TestCase)) unless Object.const_defined?(cname)
  test_class = Object.const_get(cname)
  test_class.instance_variable_set(:@concolic_ctrl, controller_class)
  def test_class.determine_default_controller_class(_name)
    @concolic_ctrl
  end
  tc = test_class.new("noop")
  tc.setup_controller_request_and_response
  tc.instance_variable_set(:@routes, Rails.application.routes)
  ctrl = tc.instance_variable_get(:@controller)
  ctrl.response = tc.instance_variable_get(:@response)
  [ctrl, tc]
end

# Corpus targets (what the engine intercepted) + the real methods behind the
# batch's aliases + the families a reader of the real path expects a real
# run could reach that the corpus has NO event for (exists?, count, pluck,
# save/reload, CollectionProxy loads, fix_profile, people_from_string).
# Adding a frame label never changes behaviour — the probe only observes.
def adv_targets(extra_more = [])
  targets_from_corpus(BATCH, exclude: {
    "ActionController::Rendering.render" => "render terminal; no SQL evidence; super-chain breaks under wrap",
    "ActionController::Head.head" => "head terminal; no SQL evidence",
  }, extra: [
    [ActiveRecord::FinderMethods, :first],
    [ActiveRecord::FinderMethods, :find_by],
    [ActiveRecord::FinderMethods, :exists?],
    [ActiveRecord::Relation, :records],
    [ActiveRecord::Relation, :to_a],
    [ActiveRecord::Calculations, :count],
    [ActiveRecord::Calculations, :pluck],
    [ActiveRecord::Associations::CollectionProxy, :records],
    [ActiveRecord::Associations::CollectionProxy, :load_target],
    [ActiveRecord::Persistence, :save],
    [ActiveRecord::Persistence, :reload],
    [Person, :fix_profile],
    [Diaspora::Mentionable, :people_from_string],
  ] + extra_more)
end

# honest warden (the batch's own pattern): Devise's REAL serialize_from_session
# resolves the user from the REAL users row; salt primed at fixture load.
def install_real_warden(tc)
  real_salt = (REAL_SALT_CACHE[:salt] ||= User.find(9).authenticatable_salt)
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  wuser = lambda { |*_a| @concrete_user ||= User.serialize_from_session(9, real_salt) }
  warden.define_singleton_method(:authenticate!) { |*a| wuser.call(*a) || raise("devise resolve failed") }
  warden.define_singleton_method(:authenticate)  { |*a| wuser.call(*a) }
  warden.define_singleton_method(:authenticated?) { |*_a| true }
  warden.define_singleton_method(:user) { |*a| wuser.call(*a) }
  warden.define_singleton_method(:session) { |*_a| {} }
  tc.instance_variable_get(:@request).env["warden"] = warden
end

# anonymous warden: what Warden does for a request with no session —
# `authenticate!` throws :warden (the Warden::Manager middleware, absent from
# the TestCase rig, would turn that into Devise's failure app / 401). The
# request wrapper catches the throw and reports status 401.
def install_anon_warden(tc)
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  warden.define_singleton_method(:authenticate!) { |*_a| throw :warden, scope: :user }
  warden.define_singleton_method(:authenticate)  { |*_a| nil }
  warden.define_singleton_method(:authenticated?) { |*_a| false }
  warden.define_singleton_method(:user) { |*_a| nil }
  warden.define_singleton_method(:session) { |*_a| {} }
  tc.instance_variable_get(:@request).env["warden"] = warden
end

# One request: returns [status, body]. signed_in: false -> anonymous warden.
def adv_request(post_id:, format:, signed_in: false, params: {}, session: {}, headers: {}, tag: nil)
  ctrl, tc = make_harness(CommentsController)
  signed_in ? install_real_warden(tc) : install_anon_warden(tc)
  session.each { |k, v| tc.session[k] = v }
  headers.each { |k, v| tc.request.headers[k] = v }
  status = nil
  thrown = catch(:warden) do
    tc.process(:index, method: :get, params: { post_id: post_id }.merge(params), format: format)
    nil
  end
  status = thrown ? "401(throw :warden)" : ctrl.response.status
  body = ctrl.response.body.to_s
  warn "[adversary] #{signed_in ? 'auth' : 'anon'} #{format} post_id=#{post_id.inspect} #{params.inspect} session=#{session.inspect} headers=#{headers.keys.inspect} -> #{status} (#{body.bytesize} bytes)"
  File.write(File.join(ADV_DIR, "runs", "_last_body_#{tag || [format, post_id.to_s.gsub(/[^\w]/, '_')].join('_')}.txt"), body)
  [status, body]
rescue StandardError => e
  warn "[adversary] #{signed_in ? 'auth' : 'anon'} #{format} post_id=#{post_id.inspect} -> EXC #{e.class}: #{e.message[0, 200]}"
  ["EXC #{e.class}", e.message.to_s]
end

def adv_scenario(name, targets: adv_targets, &body)
  [{ name: name, targets: targets, coverage_filter: %r{apps/diaspora/(app|lib)/}, body: body }]
end
