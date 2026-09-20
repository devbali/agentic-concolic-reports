# CONCRETE CHECKER fixture environment — posts_show (RUNBOOK Phase 5).
# Real sqlite DB (JDBC), the app schema, rows by raw INSERT. Data only: no
# code-under-test is stubbed anywhere in this rig, and no concolic target is
# declared — `targets.rb` / `concolic_targets.rb` are NEVER loaded here.
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
require File.expand_path("../exec_wrap.rb", __FILE__)

CE = CompletionChecker::ConcreteEnv

def psh_fixture!(db)
  CE.setup!(db: db)
  Rails.application.config.assets.check_precompiled_asset = false
  ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

  # RIG-LOCAL ASSET PATH (config value, not code-under-test). The html arms
  # died with `couldn't find file 'underscore'` before the view issued its own
  # reads: this stripped app does not vendor that asset. `_concrete_assets/`
  # holds a comment-only stub so Sprockets can RESOLVE the reference and the
  # view goes on to issue the statements that are the ground truth. It changes
  # no SQL and nothing in the diaspora app tree is edited. Widening the ground
  # truth, never narrowing the check (people_stream §8.2).
  _rig_assets = File.expand_path("../_concrete_assets", __FILE__)
  if Rails.application.config.respond_to?(:assets)
    Rails.application.config.assets.paths |= [_rig_assets]
  end
  # Sprockets 3 hands `Rails.application.assets` out as a CachedEnvironment,
  # which is IMMUTABLE ("can't modify immutable cached environment" —
  # cached_environment.rb:66), and that killed the first anon_json run outright.
  # Append to the UNDERLYING environment when one is reachable; if it is not,
  # SAY SO and carry on — a resolvable asset is a nicety for the html arms, not
  # a precondition of the measurement.
  # RESOLVING THE RIG ASSET, and what to do when it cannot be resolved.
  # `Rails.application.assets` is a `Sprockets::CachedEnvironment`, which is
  # IMMUTABLE (`config=` raises, cached_environment.rb:66) and — CHECKED IN THE
  # GEM, not guessed — keeps NO reference to the environment it was built from:
  # `initialize(environment)` at cached_environment.rb:14-24 copies the
  # configuration and stores only caches. So there is no parent to append to.
  # Three attempts, most contained first, and whichever succeeds is PRINTED:
  #   (1) `config.assets.paths`, which is what a not-yet-built environment reads
  #   (2) `append_path` on the environment, if it happens to be mutable
  #   (3) a contained poke at the cached environment's own frozen config hash
  # If all three fail the run CONTINUES and says so: a resolvable asset is a
  # nicety for the html arms, not a precondition of the measurement, and a rig
  # that dies on it measures nothing at all.
  _how = nil
  begin
    _env = Rails.application.assets
    if _env.respond_to?(:append_path)
      begin
        _env.append_path(_rig_assets); _how = "append_path"
      rescue StandardError
        _cfg = _env.config
        if _cfg.is_a?(Hash) && _cfg[:paths]
          _env.instance_variable_set(:@config,
            _cfg.merge(paths: (_cfg[:paths].to_a + [_rig_assets]).freeze).freeze)
          _how = "cached-config poke"
        end
      end
    end
  rescue StandardError => e
    warn "[psh-concrete] rig asset path: #{e.class}: #{e.message[0, 120]}"
  end
  warn("[psh-concrete] rig asset path " +
       (_how ? "appended via #{_how}" :
        "NOT APPENDED - the html view render will fail on a missing asset. " \
        "That is an ENVIRONMENT wall (this stripped app does not vendor it), " \
        "declared, not a fact about the endpoint."))

  # alice = the SIGNED-IN principal; bob = the post's AUTHOR. Both LOCAL
  # (owner_id present) so nothing bounces the anonymous scenarios.
  CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
  CE.insert("users", id: 10, username: "bob", email: "bob@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
  CE.insert("people", id: 1, guid: "aliceguid000000001", diaspora_handle: "alice@localhost",
            serialized_public_key: "K1", owner_id: 9, closed_account: 0, fetch_status: 0)
  CE.insert("people", id: 2, guid: "bobguid00000000002", diaspora_handle: "bob@localhost",
            serialized_public_key: "K2", owner_id: 10, closed_account: 0, fetch_status: 0)
  CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A",
            searchable: 1, nsfw: 0, public_details: 0)
  CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B",
            searchable: 1, nsfw: 0, public_details: 0)

  # bob's aspect with alice in it, and alice's with bob: the ONLY way
  # `EvilQuery::VisibleShareableById#querent_has_visibility` can return the
  # LIMITED post for the signed-in arm.
  CE.insert("aspects", id: 950, user_id: 10, name: "Friends", order_id: 1)
  CE.insert("contacts", id: 800, user_id: 10, person_id: 1, sharing: true, receiving: true)
  CE.insert("aspect_memberships", id: 700, aspect_id: 950, contact_id: 800)
  CE.insert("aspects", id: 951, user_id: 9, name: "Friends", order_id: 1)
  CE.insert("contacts", id: 801, user_id: 9, person_id: 2, sharing: true, receiving: true)
  CE.insert("aspect_memberships", id: 701, aspect_id: 951, contact_id: 801)

  # Post 100 PUBLIC — the anonymous arm's only visible post, and the one both
  # arms read. Its text carries a mention and BOTH a resolvable and an
  # unresolvable `diaspora://` link, so `MessageRenderer` reaches
  # `Post.exists?` on both arms (the C-4/M-1/N-1 family).
  CE.insert("posts", id: 100, author_id: 2, guid: "postguid1000000001", type: "StatusMessage",
            text: "a public post mentioning @{Alice; alice@localhost} " \
                  "see diaspora://bob@localhost/post/postguid1000000001 and " \
                  "diaspora://bob@localhost/post/nosuchguid00000001",
            public: true, comments_count: 1, likes_count: 1, reshares_count: 1,
            interacted_at: Time.now.utc, o_embed_cache_id: 500, open_graph_cache_id: 510)
  # Post 101 LIMITED, visible to alice ONLY through share_visibilities — this
  # is what makes the anon and auth arms provably read DIFFERENT rows through
  # DIFFERENT scopes, and what drives `rescue_from Diaspora::NonPublic`
  # anonymously.
  CE.insert("posts", id: 101, author_id: 2, guid: "postguid1010000001", type: "StatusMessage",
            text: "a limited post, no links", public: false, comments_count: 0,
            likes_count: 0, reshares_count: 0, interacted_at: Time.now.utc)
  CE.insert("share_visibilities", id: 600, shareable_id: 101, shareable_type: "Post",
            user_id: 9, hidden: false)
  CE.insert("aspect_visibilities", id: 610, shareable_id: 101, shareable_type: "Post",
            aspect_id: 950)

  # o_embed / open_graph caches on post 100: the two belongs_to reads the
  # corpus emits under find_target. Without rows the FK is NULL, AR issues no
  # statement, and the H6 over-emission lint reports the corpus note as "never
  # issued by any concrete run" — a FIXTURE gap masquerading as over-emission
  # (people_stream §8.2). Rows widen the ground truth; they never narrow it.
  CE.insert("o_embed_caches", id: 500, url: "https://example.org/oembed",
            data: '{"html":"<i>x</i>","type":"rich"}')
  CE.insert("open_graph_caches", id: 510, title: "og title", ob_type: "article",
            image: "https://example.org/og.png", url: "https://example.org/og",
            description: "og description")

  # a real mention row on post 100: the persisted arm of
  # MentionsContainer#mentioned_people (mentions -> people -> profiles).
  CE.insert("mentions", id: 900, mentions_container_id: 100,
            mentions_container_type: "Post", person_id: 1)
  # a comment, a like and a reshare so the presenter's interaction arms
  # (LastThreeCommentsDecorator, `likes`, `reshares`) have rows to read, and so
  # `LikeService#find_for_post` / `ReshareService#find_for_post` are non-empty.
  CE.insert("comments", id: 300, commentable_id: 100, commentable_type: "Post",
            author_id: 1, guid: "cguid300000000001", text: "nice one")
  CE.insert("likes", id: 400, target_id: 100, target_type: "Post", author_id: 1,
            guid: "lguid400000000001", positive: true)
  CE.insert("posts", id: 102, author_id: 1, guid: "postguid1020000001", type: "Reshare",
            root_guid: "postguid1000000001", public: true, comments_count: 0,
            likes_count: 0, reshares_count: 0, interacted_at: Time.now.utc)
  # A POLL on post 100, with an answer and alice's participation. WHY: a
  # table-level diff of the concrete round against the corpus's notes showed
  # `polls` / `poll_answers` / `poll_participations` in the corpus and NOT in
  # the concrete run — and the cause was this fixture, not the endpoint.
  # `PostPresenter` reads the poll (`poll_participation_answer_id` ->
  # `poll_participations`, and the poll's answers for the JSON), and with no
  # poll row the FK is NULL, AR issues no statement, and H6 would report the
  # corpus's poll notes as "never issued by any concrete run" — a FIXTURE gap
  # masquerading as over-emission (people_stream §8.2). Widening the ground
  # truth, never narrowing the check.
  CE.insert("polls", id: 400, status_message_id: 100, question: "which?",
            guid: "pollguid4000000001")
  CE.insert("poll_answers", id: 410, poll_id: 400, answer: "this one",
            guid: "paguid4100000001", vote_count: 1)
  CE.insert("poll_answers", id: 411, poll_id: 400, answer: "that one",
            guid: "paguid4110000001", vote_count: 0)
  CE.insert("poll_participations", id: 420, poll_id: 400, poll_answer_id: 410,
            author_id: 1, guid: "ppguid4200000001")

  # a notification on post 100 for alice: `post_service.mark_user_notifications`
  # is the action's SECOND statement family (Notification.where(...).update_all)
  # and without a row the UPDATE has nothing to touch.
  CE.insert("notifications", id: 200, target_id: 100, target_type: "Post",
            recipient_id: 9, unread: true, type: "Notifications::Mentioned")
end

# The DSE runner's harness, verbatim in shape (run_dse.rb make_harness): an
# ActionController::TestCase controller driven through `ctrl.dispatch`, so the
# before_action chain (set_format_if_malformed_from_status_net) and the two
# `rescue_from` handlers (Diaspora::NonPublic -> authenticate_user!,
# Diaspora::NotMine -> 403) run exactly as they do in the corpus.
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

# A stub Warden that FAILS for an anonymous user, because that is what the
# real one does and it is the arm under test. The first anon_nonpublic run
# returned 200: `rescue_from Diaspora::NonPublic { authenticate_user! }` ran,
# reached `warden.authenticate!(scope: :user)`, and the stub handed back nil
# as if authentication had SUCCEEDED — so the action carried on and rendered.
# `Warden::Proxy#authenticate!` throws `:warden` on failure; the Warden
# MIDDLEWARE catches that throw and turns it into the redirect/401. There is no
# middleware in this rig, so `psh_dispatch` catches it instead and records that
# it happened.
class PshStubWarden
  def initialize(user); @user = user; end
  def user(*); @user; end
  def authenticated?(*); !@user.nil?; end
  def authenticate(*); @user; end
  def authenticate!(*args)
    return @user if @user
    opts = args.last.is_a?(Hash) ? args.last : {}
    throw(:warden, scope: opts[:scope] || :user)
  end
end

# Drive PostsController#show exactly as run_dse.rb does.
def psh_dispatch(signed_in:, format:, id:)
  CompletionChecker.new_request! if defined?(CompletionChecker) && CompletionChecker.respond_to?(:new_request!)
  ctrl, tc = make_harness(PostsController)
  # PRINCIPAL LOADED OUTSIDE THE MEASURED BODY: `current_user` is resolved by
  # the session layer before the action, not by the action, so loading it
  # inside the probe would attribute a `SELECT "users" …` to the endpoint that
  # the endpoint never issues (people_stream §8.2 — rig noise, removed at the
  # source).
  user = signed_in ? PSH_PRINCIPAL : nil
  ctrl.singleton_class.define_method(:current_user)    { user }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  # A WARDEN IS ALWAYS INSTALLED, signed in or not. This action's
  # `rescue_from Diaspora::NonPublic { authenticate_user! }` re-enters Devise on
  # an ANONYMOUS request, and Devise raises `Devise::MissingWarden` when the
  # request env has no `Warden::Proxy` — a RIG artefact (a real Rack request
  # always has one, installed by the Warden middleware), not the endpoint's
  # behaviour. Measured: the first anon_nonpublic run died with exactly that
  # after 7 target calls. The anonymous warden carries a NIL user, so
  # `authenticate_user!` still fails to authenticate — which is the arm under
  # test.
  tc.instance_variable_get(:@request).env["warden"] = PshStubWarden.new(user)
  ctrl.params = {id: id}.with_indifferent_access
  begin
    ctrl.request.format = format if format
  rescue StandardError => e
    warn "[concrete] could not set request format: #{e.class}"
  end
  thrown = catch(:warden) do
    ci_wrap do
      begin
        ctrl.dispatch("show", tc.request, tc.response)
      rescue Exception => e # rubocop:disable Lint/RescueException
        handled = (ctrl.send(:rescue_with_handler, e) rescue nil)
        raise e unless handled
        handled
      end
    end
    nil
  end
  # Stand in for the Warden middleware's own catch. `thrown` is non-nil exactly
  # when the action demanded authentication and could not get it — for this
  # controller that is the `Diaspora::NonPublic` escape on an anonymous
  # request, and a scenario asserts on it.
  ctrl.instance_variable_set(:@psh_warden_thrown, thrown)
  ctrl.singleton_class.define_method(:psh_warden_thrown) { @psh_warden_thrown }
  ctrl
end
