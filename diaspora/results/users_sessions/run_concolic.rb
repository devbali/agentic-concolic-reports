# frozen_string_literal: true
# run_concolic.rb — "users_sessions" batch (21 entrypoints, largest batch)
# Covers UsersController, SessionsController, RegistrationsController, InvitationsController.

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "json"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)

RESULTS = "/home/dev/project/reports/diaspora/results/users_sessions"
Dir.mkdir(RESULTS) unless Dir.exist?(RESULTS)

def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user)")
  person.define_singleton_method(:id) { 1 }
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:id) { 1 }
  user.define_singleton_method(:guid) { "abc123" }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:diaspora_handle) { "alice@example.org" }
  user.define_singleton_method(:language) { "en" }
  user.define_singleton_method(:gender) { "" }
  user.define_singleton_method(:contacts) { Contact.all }
  user.define_singleton_method(:blocks) { Block.all }
  user.define_singleton_method(:aspects) { Aspect.all }
  user.define_singleton_method(:post_default_aspects) { Aspect.all }
  user.define_singleton_method(:post_default_public) { true }
  user.define_singleton_method(:invited_by) { nil }
  # followed_tags: the real relation's `.map` in getting_started hits the
  # SymbolicList#each wall; give a concrete empty Array (tag list is pure data).
  user.define_singleton_method(:followed_tags) { [] }
  user.define_singleton_method(:visible_shareables) { |*_a| Post.all }
  user.define_singleton_method(:admin?) { false }
  user.define_singleton_method(:moderator?) { false }
  user.define_singleton_method(:strip_exif) { true }
  user.define_singleton_method(:valid_password?) { |_pw| true }
  user.define_singleton_method(:close_account!) { true }
  user.define_singleton_method(:update_attributes) { |attrs| true }
  user.define_singleton_method(:email) { "alice@example.org" }
  # export / exported_photos_file are exposed attachments whose `.url` the
  # download actions call; give a stub with #url (pure data, no SQL).
  export_stub = Object.new
  def export_stub.url; "http://example.com/export.zip"; end
  user.define_singleton_method(:export) { export_stub }
  user.define_singleton_method(:exported_photos_file) { export_stub }
  user
end

$user = symbolic_user("US")

class StubWarden
  def initialize(user); @user = user; end
  def authenticate!(*_); @user; end
  def authenticated?(*_); true; end
  def authenticate?(*_); true; end
  def user(*_); @user; end
  def raw_session; {}; end
  def logout(*_); true; end
  def clear_strategies_cache!(*_); true; end
  def config; self; end
  def no_input_strategies; []; end
end

def make_harness(controller_class)
  cname = controller_class.to_s.gsub("::", "__").sub(/Controller\z/, "ControllerTest")
  Object.const_set(cname, Class.new(ActionController::TestCase)) unless Object.const_defined?(cname)
  test_class = Object.const_get(cname)
  test_class.instance_variable_set(:@concolic_ctrl, controller_class)
  def test_class.determine_default_controller_class(name)
    @concolic_ctrl
  end
  tc = test_class.new("noop")
  tc.setup_controller_request_and_response
  tc.instance_variable_set(:@routes, Rails.application.routes)
  ctrl = tc.instance_variable_get(:@controller)
  [ctrl, tc]
end

def write_dump(ep, label, dump)
  dir = File.join(RESULTS, ep)
  Dir.mkdir(dir) unless Dir.exist?(dir)
  File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
end

def pc_count(dump)
  (dump["events"] || []).count { |e| e["type"] == "path_condition" }
end

def drive(controller_class, action, params, ep, label, signed_in: true, method: "GET", format: nil, seeds: {})
  ConcolicTargets.seed_overrides = seeds
  ctrl, tc = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user)    { signed_in ? $user : nil }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  tc.instance_variable_get(:@request).env["warden"] = StubWarden.new($user)
  dump = $interceptor.run(
    -> { tc.process(action, method: method, params: params, format: format); :ok },
    {}, label: label, script: "run_concolic.rb"
  )
  write_dump(ep, label, dump)
  err = dump["error"]
  puts "  [#{label}] PCs=#{pc_count(dump)} error=#{err ? "#{err['type']}: #{err['message'][0,90]}" : 'none'}"
  dump
end

puts "== users_sessions batch: harness ready =="
$start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# --- Users ---
drive(UsersController, :edit, {}, "users_edit", "users_edit_default")
drive(UsersController, :update, { user: { email: "a@b.com", language: "en" } },
      "users_update", "users_update_default", method: "PUT")
drive(UsersController, :privacy_settings, {}, "users_privacy_settings", "users_privacy_settings_default")
drive(UsersController, :update_privacy_settings, { user: { strip_exif: true } },
      "users_update_privacy_settings", "users_update_privacy_settings_default", method: "PUT")
drive(UsersController, :getting_started, {}, "users_getting_started", "users_getting_started_default")
drive(UsersController, :getting_started_completed, {},
      "users_getting_started_completed", "users_getting_started_completed_default", method: "PUT")
drive(UsersController, :export_profile, {}, "users_export", "users_export_default", format: :json)
drive(UsersController, :export_photos, {}, "users_export_photos", "users_export_photos_default", format: :json)
drive(UsersController, :download_profile, {}, "users_download_profile", "users_download_profile_default", format: :json)
drive(UsersController, :confirm_email, { token: "abc" }, "users_confirm_email", "users_confirm_email_default")
drive(UsersController, :public, { username: "alice" }, "users_public", "users_public_default", signed_in: false, format: :html)
drive(UsersController, :destroy, { user: { current_password: "pw" } }, "users_destroy", "users_destroy_default", method: "DELETE")
drive(UsersController, :auth_token, {}, "users_auth_token", "users_auth_token_default")

# --- Sessions (Devise) ---
# sessions#create = sign-in
drive(SessionsController, :create, { user: { username: "alice", password: "pw" } },
      "sessions_create", "sessions_create_default", method: "POST", signed_in: false)
# sessions#destroy = sign-out
drive(SessionsController, :destroy, {}, "sessions_destroy", "sessions_destroy_default", method: "DELETE")
# sessions#new = sign-in form
drive(SessionsController, :new, {}, "sessions_new", "sessions_new_default", signed_in: false)

# --- Registrations (Devise) ---
drive(RegistrationsController, :create, { user: { username: "newuser", email: "new@example.com", password: "pw123" } },
      "registrations_create", "registrations_create_default", method: "POST", signed_in: false)
drive(RegistrationsController, :new, {}, "registrations_new", "registrations_new_default", signed_in: false)

# --- Invitations (Devise) ---
drive(InvitationsController, :new, {}, "invitations_new", "invitations_new_default", signed_in: false)
drive(InvitationsController, :create, { email_inviter: { emails: "friend@example.com", message: "hi" } },
      "invitations_create", "invitations_create_default", method: "POST")

$elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - $start
File.write(File.join(RESULTS, "elapsed_seconds.txt"), format("%.1f", $elapsed))
puts "== users_sessions done (elapsed #{$elapsed.round(2)}s) =="