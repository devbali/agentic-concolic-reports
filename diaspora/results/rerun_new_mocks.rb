# frozen_string_literal: true
# re-run seeded entrypoints that were previously blocked by
# Core::ClassMethods#find not being intercepted. New concolic_targets.rb
# lines 173-176 now declare Core::ClassMethods.find / find_by / find_by!
# which should produce PCs instead of crashing at SymbolicList#first.
#
# Affected: notifications_update (still needs seeds), tags_show,
# tag_followings_create/destroy, profiles_show, links_resolve,
# admin close/lock/unlock/add_invites, users_public, users_confirm_email

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
  user.define_singleton_method(:followed_tags) { ActsAsTaggableOn::Tag.all }
  user.define_singleton_method(:visible_shareables) { |*_a| Post.all }
  user
end

$user = symbolic_user("RR")

class StubWarden
  def initialize(user); @user = user; end
  def authenticate!(*_); @user; end
  def authenticated?(*_); true; end
  def user(*_); @user; end
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

def write_dump(base, ep, label, dump)
  dir = File.join(base, ep)
  Dir.mkdir(dir) unless Dir.exist?(dir)
  File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
end

def pc_count(dump)
  (dump["events"] || []).count { |e| e["type"] == "path_condition" }
end

def drive(base, controller_class, action, params, ep, label, signed_in: true, method: "GET", format: nil, seeds: {})
  ConcolicTargets.seed_overrides = seeds
  warden = StubWarden.new($user)
  ctrl, tc = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user)    { signed_in ? $user : nil }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  tc.instance_variable_get(:@request).env["warden"] = warden
  dump = $interceptor.run(
    -> { tc.process(action, method: method, params: params, format: format); :ok },
    {}, label: label, script: "rerun_new_mocks.rb"
  )
  write_dump(base, ep, label, dump)
  err = dump["error"]
  puts "  [#{label}] PCs=#{pc_count(dump)} error=#{err ? "#{err['type']}: #{err['message'][0,100]}" : 'none'}"
  dump
end

puts "== re-run with new Core::ClassMethods find mocks =="

NT_BASE = "/home/dev/project/reports/diaspora/results/notifications_tags"
SLRP_BASE = "/home/dev/project/reports/diaspora/results/search_links_reports_profiles"
SA_BASE = "/home/dev/project/reports/diaspora/results/services_admin"
US_BASE = "/home/dev/project/reports/diaspora/results/users_sessions"

# --- notifications_tags: re-run with seeded both-sides coverage ---
puts "--- notifications_tags: notifications_update both branches ---"
drive(NT_BASE, NotificationsController, :update, { id: 1 },
      "notifications_update", "nt_update_v2_00", method: "PUT", format: :json)
drive(NT_BASE, NotificationsController, :update, { id: 1 },
      "notifications_update", "nt_update_v2_01", method: "PUT", format: :json,
      seeds: { "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_1_not_found" => true })

puts "--- notifications_tags: tag_followings_destroy ---"
drive(NT_BASE, TagFollowingsController, :destroy, { id: "1" },
      "tag_followings_destroy", "nt_tfd_v2", method: "DELETE", format: :json)

puts "--- notifications_tags: tag_followings_create ---"
drive(NT_BASE, TagFollowingsController, :create, { name: "cooltag" },
      "tag_followings_create", "nt_tfc_v2_00", method: "POST", format: :json)
drive(NT_BASE, TagFollowingsController, :create, { name: "cooltag" },
      "tag_followings_create", "nt_tfc_v2_01", method: "POST", format: :json,
      seeds: { "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found" => true })

# --- search_links_reports_profiles: profiles#show, links#resolve ---
puts "--- slrp: profiles#show ---"
drive(SLRP_BASE, ProfilesController, :show, { id: "abc123" },
      "profiles_show", "slrp_ps_v2_00", signed_in: false, format: :json)
drive(SLRP_BASE, ProfilesController, :show, { id: "abc123" },
      "profiles_show", "slrp_ps_v2_01", signed_in: false, format: :json,
      seeds: { "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_1_not_found" => true })

puts "--- slrp: links#resolve ---"
drive(SLRP_BASE, LinksController, :resolve, { q: "https://example.org/posts/abc" },
      "links_resolve", "slrp_lr_v2", signed_in: false)

# --- services_admin ---
puts "--- services_admin: close_account ---"
drive(SA_BASE, Admin::UsersController, :close_account, { id: 1 },
      "admin_close_account", "sa_ca_v2_00", method: "POST")
drive(SA_BASE, Admin::UsersController, :close_account, { id: 1 },
      "admin_close_account", "sa_ca_v2_01", method: "POST",
      seeds: { "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_1_not_found" => true })

puts "--- services_admin: lock_account ---"
drive(SA_BASE, Admin::UsersController, :lock_account, { id: 1 },
      "admin_lock_account", "sa_la_v2_00", method: "POST")
drive(SA_BASE, Admin::UsersController, :lock_account, { id: 1 },
      "admin_lock_account", "sa_la_v2_01", method: "POST",
      seeds: { "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_1_not_found" => true })

puts "--- services_admin: unlock_account ---"
drive(SA_BASE, Admin::UsersController, :unlock_account, { id: 1 },
      "admin_unlock_account", "sa_ua_v2_00", method: "POST")
drive(SA_BASE, Admin::UsersController, :unlock_account, { id: 1 },
      "admin_unlock_account", "sa_ua_v2_01", method: "POST",
      seeds: { "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_1_not_found" => true })

puts "--- services_admin: add_invites ---"
drive(SA_BASE, AdminsController, :add_invites, { invite_code_id: "abc" },
      "admin_add_invites", "sa_ai_v2_00", method: "POST")
drive(SA_BASE, AdminsController, :add_invites, { invite_code_id: "abc" },
      "admin_add_invites", "sa_ai_v2_01", method: "POST",
      seeds: { "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found" => true })

# --- users_sessions ---
puts "--- users_sessions: users_public ---"
drive(US_BASE, UsersController, :public, { username: "alice" },
      "users_public", "us_up_v2_00", signed_in: false, format: :html)
drive(US_BASE, UsersController, :public, { username: "alice" },
      "users_public", "us_up_v2_01", signed_in: false, format: :html,
      seeds: { "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found" => true })

puts "--- users_sessions: users_confirm_email ---"
drive(US_BASE, UsersController, :confirm_email, { token: "abc" },
      "users_confirm_email", "us_ce_v2", format: :html)

puts "== re-run complete =="