# CONCRETE CHECKER fixture environment — people_stream (RUNBOOK Phase 5).
# Real sqlite DB (JDBC), the app schema, rows by raw INSERT. Data only: no
# code-under-test is stubbed anywhere in this rig, and no concolic target is
# declared — `targets.rb` / `concolic_targets.rb` are NEVER loaded here.
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
require File.expand_path("../exec_wrap.rb", __FILE__)

CE = CompletionChecker::ConcreteEnv

def ps_fixture!(db)
  CE.setup!(db: db)
  Rails.application.config.assets.check_precompiled_asset = false
  ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

  # alice = the SIGNED-IN principal; bob = the VIEWED person. Both LOCAL
  # (owner_id present) so `authenticate_if_remote_profile!` does not bounce the
  # anonymous scenarios — `Person#remote?` is `!local?`, and a remote person
  # would make every anon request an auth redirect instead of the stream.
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

  # bob's aspect + alice as a contact in it: the ONLY way `posts_from` (the
  # signed-in arm, Post.from_person_visible_by_user) can return a LIMITED post.
  CE.insert("aspects", id: 950, user_id: 10, name: "Friends", order_id: 1)
  CE.insert("contacts", id: 800, user_id: 10, person_id: 1, sharing: true, receiving: true)
  CE.insert("aspect_memberships", id: 700, aspect_id: 950, contact_id: 800)
  CE.insert("aspects", id: 951, user_id: 9, name: "Friends", order_id: 1)
  CE.insert("contacts", id: 801, user_id: 9, person_id: 2, sharing: true, receiving: true)
  CE.insert("aspect_memberships", id: 701, aspect_id: 951, contact_id: 801)

  # bob's posts. 100 PUBLIC (both arms see it), 101 LIMITED with an
  # aspect_visibility for alice (only the signed-in arm sees it) — so the anon
  # and auth scenarios provably read DIFFERENT rows through different scopes.
  CE.insert("posts", id: 100, author_id: 2, guid: "postguid1000000001", type: "StatusMessage",
            text: "a public post mentioning @{Alice; alice@localhost} " \
                  "see diaspora://bob@localhost/post/postguid1000000001 and " \
                  "diaspora://bob@localhost/post/nosuchguid00000001",
            public: true, comments_count: 1, likes_count: 1, interacted_at: Time.now.utc,
            o_embed_cache_id: 500, open_graph_cache_id: 510)
  CE.insert("posts", id: 101, author_id: 2, guid: "postguid1010000001", type: "StatusMessage",
            text: "a limited post, no links", public: false, comments_count: 0,
            likes_count: 0, interacted_at: Time.now.utc)
  CE.insert("share_visibilities", id: 600, shareable_id: 101, shareable_type: "Post",
            user_id: 9, hidden: false)
  CE.insert("aspect_visibilities", id: 610, shareable_id: 101, shareable_type: "Post",
            aspect_id: 950)

  # o_embed / open_graph caches on post 100: the two belongs_to reads the
  # corpus emits under find_target. Without rows the FK is NULL, AR issues no
  # statement, and the H6 over-emission lint reports the corpus note as
  # "never issued by any concrete run" — a FIXTURE gap masquerading as
  # over-emission. Rows make the ground truth cover them (widening the
  # differential, never weakening it).
  CE.insert("o_embed_caches", id: 500, url: "https://example.org/oembed",
            data: '{"html":"<i>x</i>","type":"rich"}')
  CE.insert("open_graph_caches", id: 510, title: "og title", ob_type: "article",
            image: "https://example.org/og.png", url: "https://example.org/og",
            description: "og description")

  # a real mention row on post 100: the persisted arm of
  # MentionsContainer#mentioned_people (mentions -> people -> profiles).
  CE.insert("mentions", id: 900, mentions_container_id: 100,
            mentions_container_type: "Post", person_id: 1)
  # a comment and a like so the LastThreeCommentsDecorator and
  # `like_posts_for_stream!` arms have rows to read.
  CE.insert("comments", id: 300, commentable_id: 100, commentable_type: "Post",
            author_id: 1, guid: "cguid300000000001", text: "nice one")
  CE.insert("likes", id: 400, target_id: 100, target_type: "Post", author_id: 1,
            guid: "lguid400000000001", positive: true)
end

# The DSE runner's harness, verbatim in shape (run_dse.rb make_harness): an
# ActionController::TestCase controller driven through `ctrl.dispatch`, so the
# before_action chain (find_person, authenticate_if_remote_profile!) and
# rescue_from run exactly as they do in the corpus.
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

class PsStubWarden
  def initialize(user); @user = user; end
  def user(*); @user; end
  def authenticate!(*); @user; end
  def authenticated?(*); !@user.nil?; end
  def authenticate(*); @user; end
end

# Drive PeopleController#stream exactly as run_dse.rb does.
def ps_dispatch(signed_in:, format:, person_id:, username:)
  CompletionChecker.new_request! if defined?(CompletionChecker) && CompletionChecker.respond_to?(:new_request!)
  ctrl, tc = make_harness(PeopleController)
  # PRINCIPAL LOADED OUTSIDE THE MEASURED BODY: `current_user` is resolved by
  # the session layer before the action, not by the action, so loading it
  # inside the probe would attribute a `SELECT "users" …` to the endpoint that
  # the endpoint never issues (it showed up as an "outside any target frame"
  # statement on the first run — rig noise, removed at the source).
  user = signed_in ? PS_PRINCIPAL : nil
  ctrl.singleton_class.define_method(:current_user)    { user }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  tc.instance_variable_get(:@request).env["warden"] = PsStubWarden.new(user) if signed_in
  ctrl.params = {person_id: person_id, username: username}.with_indifferent_access
  begin
    ctrl.request.format = format if format
  rescue StandardError => e
    warn "[concrete] could not set request format: #{e.class}"
  end
  ci_wrap do
    begin
      ctrl.dispatch("stream", tc.request, tc.response)
    rescue Exception => e # rubocop:disable Lint/RescueException
      handled = (ctrl.send(:rescue_with_handler, e) rescue nil)
      raise e unless handled
      handled
    end
  end
  ctrl
end
