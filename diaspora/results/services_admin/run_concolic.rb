# frozen_string_literal: true
# run_concolic.rb — "services_admin" batch
# Covers ServicesController and AdminsController.
# AdminsController inherits from Admin::AdminController which checks `authenticate_user!`
# and `redirect_unless_admin`. We drive with an admin-level symbolic_user.

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

RESULTS = "/home/dev/project/reports/diaspora/results/services_admin"
Dir.mkdir(RESULTS) unless Dir.exist?(RESULTS)

def symbolic_user(tag, admin: false)
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
  user.define_singleton_method(:admin?) { admin }
  user.define_singleton_method(:moderator?) { admin }
  user
end

$user = symbolic_user("SA")
$admin_user = symbolic_user("SAA", admin: true)

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

def write_dump(ep, label, dump)
  dir = File.join(RESULTS, ep)
  Dir.mkdir(dir) unless Dir.exist?(dir)
  File.write(File.join(dir, "dump_#{label}.json"), JSON.pretty_generate(dump))
end

def pc_count(dump)
  (dump["events"] || []).count { |e| e["type"] == "path_condition" }
end

def drive(controller_class, action, params, ep, label, use_admin: false, signed_in: true, method: "GET", format: nil, seeds: {})
  ConcolicTargets.seed_overrides = seeds
  the_user = use_admin ? $admin_user : $user
  ctrl, tc = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user)    { signed_in ? the_user : nil }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  tc.instance_variable_get(:@request).env["warden"] = StubWarden.new(the_user)
  dump = $interceptor.run(
    -> { tc.process(action, method: method, params: params, format: format); :ok },
    {}, label: label, script: "run_concolic.rb"
  )
  write_dump(ep, label, dump)
  err = dump["error"]
  puts "  [#{label}] PCs=#{pc_count(dump)} error=#{err ? "#{err['type']}: #{err['message'][0,90]}" : 'none'}"
  dump
end

puts "== services_admin batch: harness ready =="
$start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# 1) POST /services/:provider/invite — services#invite
# This is inviter action, not in the controller. Let me check: services_controller
# has index, create, failure, inviter, destroy — the route is to services#inviter
drive(ServicesController, :inviter, { provider: "twitter" },
      "services_invite", "services_invite_default", method: "POST")

# 2) GET /services/:provider/failure — services#failure
drive(ServicesController, :failure, { provider: "twitter" },
      "services_failure", "services_failure_default")

# 3) GET /admin/user_search — admin#user_search
drive(AdminsController, :user_search, {},
      "admin_user_search", "admin_user_search_default", use_admin: true)

# 4) GET /admin/dashboard — admin#dashboard
drive(AdminsController, :dashboard, {},
      "admin_dashboard", "admin_dashboard_default", use_admin: true)

# 5) GET /admin/stats — admin#weekly_user_stats
drive(AdminsController, :weekly_user_stats, {},
      "admin_stats", "admin_stats_default", use_admin: true)

# 6) POST /admin/users/:id/close_account
# Appears to be in Admin::UsersController, not AdminsController
# Use admin/users_controller
begin
  admin_users_ctrl = Admin::UsersController
rescue NameError
  begin
    require "/home/dev/project/ruby_examples/dse-apps/apps/diaspora/app/controllers/admin/users_controller.rb"
    admin_users_ctrl = Admin::UsersController
  rescue => e
    puts "  WARN: can't load Admin::UsersController: #{e.message}"
    admin_users_ctrl = AdminsController
  end
end
drive(admin_users_ctrl, :close_account, { id: 1 },
      "admin_close_account", "admin_close_account_default", method: "POST", use_admin: true)

# 7) lock_account
drive(admin_users_ctrl, :lock_account, { id: 1 },
      "admin_lock_account", "admin_lock_account_default", method: "POST", use_admin: true)

# 8) unlock_account
drive(admin_users_ctrl, :unlock_account, { id: 1 },
      "admin_unlock_account", "admin_unlock_account_default", method: "POST", use_admin: true)

# 9) add_invites
drive(AdminsController, :add_invites, { invite_code_id: "abc" },
      "admin_add_invites", "admin_add_invites_default", method: "POST", use_admin: true)

$elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - $start
File.write(File.join(RESULTS, "elapsed_seconds.txt"), format("%.1f", $elapsed))
puts "== services_admin done (elapsed #{$elapsed.round(2)}s) =="