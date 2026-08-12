# frozen_string_literal: true
# Re-run diaspora entrypoints with the new render boundary installed.
# Previously entrypoints that reached render() would crash on template lookup
# (SymbolicList#each, nil#[], ActionView::Template::Error). Now render is
# intercepted and returns :render_reached without executing the template.
#
# This should convert many "crashed with PCs" into "clean run with PCs".
# Focus: entrypoints that crashed at/after render (not routing/Devise/table-missing).

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

def symbolic_user(tag, admin: false)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person")
  person.define_singleton_method(:id) { 1 }
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User")
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
  user.define_singleton_method(:strip_exif) { true }
  user.define_singleton_method(:valid_password?) { |_pw| true }
  user.define_singleton_method(:close_account!) { true }
  user.define_singleton_method(:update_attributes) { |attrs| true }
  user.define_singleton_method(:email) { "alice@example.org" }
  user
end

$user = symbolic_user("RB")
$admin = symbolic_user("RBA", admin: true)

class StubWarden
  def initialize(user); @user = user; end
  def authenticate!(*_); @user; end
  def authenticated?(*_); true; end
  def user(*_); @user; end
  def logout(*_); end
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

def call_count(dump)
  (dump["events"] || []).count { |e| e["type"] == "symbolic_call" }
end

def drive(base, controller_class, action, params, ep, label, signed_in: true, use_admin: false, method: "GET", format: nil, seeds: {})
  ConcolicTargets.seed_overrides = seeds
  the_user = use_admin ? $admin : $user
  ctrl, tc = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user)    { signed_in ? the_user : nil }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  tc.instance_variable_get(:@request).env["warden"] = StubWarden.new(the_user)
  dump = $interceptor.run(
    -> { tc.process(action, method: method, params: params, format: format); :ok },
    {}, label: label, script: "rerun_render_boundary.rb"
  )
  write_dump(base, ep, label, dump)
  err = dump["error"]
  puts "  [#{label}] PCs=#{pc_count(dump)} calls=#{call_count(dump)} error=#{err ? "#{err['type']}: #{err['message'][0,80]}" : 'clean'}"
  dump
end

puts "== re-run with render boundary =="

NT_BASE  = "/home/dev/project/reports/diaspora/results/notifications_tags"
SLRP_BASE = "/home/dev/project/reports/diaspora/results/search_links_reports_profiles"
SA_BASE  = "/home/dev/project/reports/diaspora/results/services_admin"
US_BASE  = "/home/dev/project/reports/diaspora/results/users_sessions"

# --- notifications_tags: re-run render-crashed entrypoints ---
puts "--- notifications ---"
# tags_index: was SymbolicList#each crash during autocomplete render
drive(NT_BASE, TagsController, :index, { q: "ruby" }, "tags_index",
      "nt_ti_rb", format: :json)
# tags_show: was Arel quote crash → should have render boundary now
drive(NT_BASE, TagsController, :show, { name: "testtag", page: 1 }, "tags_show",
      "nt_ts_rb_00", format: :json)
drive(NT_BASE, TagsController, :show, { name: "testtag", page: 1 }, "tags_show",
      "nt_ts_rb_01", format: :json,
      seeds: { "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by__1_not_found" => true })
# notifications_index: was SymbolicInt#to_i crash
drive(NT_BASE, NotificationsController, :index, {}, "notifications_index",
      "nt_ni_rb", format: :json)
# notifications_read_all: was nil#[] crash on redirect
drive(NT_BASE, NotificationsController, :read_all, {}, "notifications_read_all",
      "nt_nra_rb", format: :json)

# --- search_links_reports_profiles ---
puts "--- slrp ---"
# profiles_edit: was nil#[] on person.profile
drive(SLRP_BASE, ProfilesController, :edit, {}, "profiles_edit",
      "slrp_pe_rb")
# report_create: was nil#[] on StrongParameters
drive(SLRP_BASE, ReportController, :create, { item_id: "1", item_type: "post" },
      "report_create", "slrp_rc_rb", method: "POST")

# --- services_admin ---
puts "--- services_admin ---"
# admin_user_search: was reports-table-missing → now render should short-circuit
drive(SA_BASE, AdminsController, :user_search, {}, "admin_user_search",
      "sa_aus_rb", use_admin: true)
# admin_dashboard: was reports-table-missing → render boundary
drive(SA_BASE, AdminsController, :dashboard, {}, "admin_dashboard",
      "sa_ad_rb", use_admin: true)
# admin_stats: was Batches#find_each crash → render boundary after query
drive(SA_BASE, AdminsController, :weekly_user_stats, {}, "admin_stats",
      "sa_as_rb", use_admin: true)

# --- users_sessions ---
puts "--- users_sessions ---"
# users_edit: was nil#[] on person.profile → render boundary
drive(US_BASE, UsersController, :edit, {}, "users_edit", "us_e_rb")
# users_update: was nil#[] in update_user
drive(US_BASE, UsersController, :update, { user: { email: "a@b.com", language: "en" } },
      "users_update", "us_u_rb", method: "PUT")
# users_privacy_settings: had 1 PC + SymbolicList#each crash → should be clean now
drive(US_BASE, UsersController, :privacy_settings, {}, "users_privacy_settings",
      "us_ps_rb")
# users_getting_started: was nil#[] crash
drive(US_BASE, UsersController, :getting_started, {}, "users_getting_started",
      "us_gs_rb")
# users_getting_started_completed: was nil#write_from_user
drive(US_BASE, UsersController, :getting_started_completed, {},
      "users_getting_started_completed", "us_gsc_rb", method: "PUT")
# users_destroy: was StubWarden missing logout (now added)
drive(US_BASE, UsersController, :destroy, { user: { current_password: "pw" } },
      "users_destroy", "us_d_rb", method: "DELETE")

puts "== re-run with render boundary complete =="