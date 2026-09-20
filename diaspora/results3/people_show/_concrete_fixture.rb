# CONCRETE CHECKER fixture environment — people_show (RUNBOOK Phase 5).
# Built 2026-09-19 for the completion-gate build; ported in shape from
# results3/people_stream/_concrete_fixture.rb, with the rows and the dispatch
# helper changed for PeopleController#SHOW rather than #stream.
#
# Real sqlite DB (JDBC), the app schema, rows by raw INSERT. DATA ONLY: no
# code-under-test is stubbed anywhere in this rig, and no concolic target is
# declared — `targets.rb` / `concolic_targets.rb` are NEVER loaded here. That
# is the whole point: this run is the ground truth the corpus's mock notes are
# checked against.
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
require File.expand_path("../_exec_wrap.rb", __FILE__)

CE = CompletionChecker::ConcreteEnv

def ps_fixture!(db)
  CE.setup!(db: db)
  Rails.application.config.assets.check_precompiled_asset = false
  ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

  # alice = the SIGNED-IN principal; bob = the VIEWED person. Both LOCAL
  # (owner_id present) so `authenticate_if_remote_profile!` does not bounce the
  # anonymous scenarios — `Person#remote?` is `!local?`, and a remote person
  # would turn every anon request into a 401 instead of the profile page.
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
  # public_details on BOB's profile so the presenter's public/private split is
  # exercised on the viewed person rather than short-circuited.
  CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A",
            searchable: 1, nsfw: 0, public_details: 0)
  CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B",
            searchable: 1, nsfw: 0, public_details: 1,
            bio: "bob bio", location: "Berlin", gender: "n/a")

  # The profile TAG read (`profile.tags.pluck(:name)`) the batch recovers.
  CE.insert("tags", id: 900, name: "shimtag", taggings_count: 1)
  CE.insert("taggings", id: 910, tag_id: 900, taggable_id: 12,
            taggable_type: "Profile", context: "tags")

  # alice's aspect + bob as a contact in it: the signed-in arm's
  # contact_for / aspect_memberships reads, and the `contact` presenter branch.
  CE.insert("aspects", id: 951, user_id: 9, name: "Friends", order_id: 1)
  CE.insert("contacts", id: 801, user_id: 9, person_id: 2, sharing: true, receiving: true)
  CE.insert("aspect_memberships", id: 701, aspect_id: 951, contact_id: 801)

  # bob's posts: 100 PUBLIC (both arms), 101 LIMITED visible to alice (only the
  # signed-in arm), so anon and auth provably read DIFFERENT rows.
  CE.insert("posts", id: 100, author_id: 2, guid: "postguid1000000001",
            type: "StatusMessage", text: "a public post", public: true,
            comments_count: 0, likes_count: 0, interacted_at: Time.now.utc)
  CE.insert("posts", id: 101, author_id: 2, guid: "postguid1010000001",
            type: "StatusMessage", text: "a limited post", public: false,
            comments_count: 0, likes_count: 0, interacted_at: Time.now.utc)
  CE.insert("share_visibilities", id: 600, shareable_id: 101, shareable_type: "Post",
            user_id: 9, hidden: false)
  CE.insert("aspect_visibilities", id: 610, shareable_id: 101, shareable_type: "Post",
            aspect_id: 951)

  # a photo by bob: `Photo.visible(...).count` is one of the statements this
  # endpoint is specifically about, and without a row the count arm reads an
  # empty table.
  CE.insert("photos", id: 500, author_id: 2, guid: "photoguid100000001",
            status_message_guid: "postguid1000000001", public: true, pending: false,
            random_string: "r1", processed_image: "p.jpg")

  # an unread notification about bob FOR alice: the signed-in
  # `mark_corresponding_notifications_read` read + its update.
  CE.insert("notifications", id: 200, target_type: "Person", target_id: 2,
            recipient_id: 9, unread: true, type: "Notifications::StartedSharing")
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

# Drive PeopleController#show exactly as run_dse.rb does.
def ps_show_dispatch(signed_in:, format:, username:)
  CompletionChecker.new_request! if defined?(CompletionChecker) && CompletionChecker.respond_to?(:new_request!)
  ctrl, tc = make_harness(PeopleController)
  # PRINCIPAL LOADED OUTSIDE THE MEASURED BODY: `current_user` is resolved by
  # the session layer before the action, not by the action, so loading it
  # inside the probe would attribute a `SELECT "users" …` to the endpoint that
  # the endpoint never issues (people_stream hit exactly this and removed it at
  # the source). The corpus's principal is minted, not fetched, for the same
  # reason — see _REOPEN_20260919_STATUS.md §3.
  user = signed_in ? PS_PRINCIPAL : nil
  ctrl.singleton_class.define_method(:current_user)    { user }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  tc.instance_variable_get(:@request).env["warden"] = PsStubWarden.new(user) if signed_in
  ctrl.params = { username: username }.with_indifferent_access
  begin
    ctrl.request.format = format if format
  rescue StandardError => e
    warn "[concrete] could not set request format: #{e.class}"
  end
  ci_wrap do
    begin
      ctrl.dispatch("show", tc.request, tc.response)
    rescue Exception => e # rubocop:disable Lint/RescueException
      handled = (ctrl.send(:rescue_with_handler, e) rescue nil)
      raise e unless handled
      handled
    end
  end
  ctrl
end
