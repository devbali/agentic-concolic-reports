# frozen_string_literal: true
# run_concolic.rb — "search_links_reports_profiles" batch
# Covers SearchController, LinksController, ReportController, ProfilesController.
# Same ActionController::TestCase harness pattern.

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

RESULTS = "/home/dev/project/reports/diaspora/results/search_links_reports_profiles"
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
  if admin
    user.define_singleton_method(:admin?) { true }
    user.define_singleton_method(:moderator?) { true }
  else
    user.define_singleton_method(:admin?) { false }
    user.define_singleton_method(:moderator?) { false }
  end
  user
end

$user = symbolic_user("SLR")
$admin_user = symbolic_user("SLRA", admin: true)

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

puts "== search_links_reports_profiles batch: harness ready =="
$start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# 1) GET /search — search#search
drive(SearchController, :search, { q: "#ruby" }, "search", "search_default",
      format: :json)

# 2) GET /link — links#resolve
# DiasporaLinkService#find_or_fetch_entity calls Person.find_by_guid
drive(LinksController, :resolve, { q: "https://example.org/posts/abc" },
      "links_resolve", "links_resolve_default", signed_in: false)

# 3) GET /report — report#index (needs moderator)
drive(ReportController, :index, {}, "report_index", "report_index_default",
      use_admin: true)

# 4) POST /report — report#create
drive(ReportController, :create, { item_id: "1", item_type: "post" },
      "report_create", "report_create_default", method: "POST")

# 5) PUT /report/:id — report#update (moderator)
drive(ReportController, :update, { id: 1 }, "report_update", "report_update_default",
      method: "PUT", use_admin: true)

# 6) DELETE /report/:id — report#destroy (moderator)
drive(ReportController, :destroy, { id: 1 }, "report_destroy", "report_destroy_default",
      method: "DELETE", use_admin: true)

# 7) GET /profile — profiles#edit
drive(ProfilesController, :edit, {}, "profiles_edit", "profiles_edit_default")

# 8) PUT /profile — profiles#update
drive(ProfilesController, :update, { profile: { first_name: "Alice", last_name: "User", bio: "test", location: "US", searchable: true, nsfw: false, public_details: true } },
      "profiles_update", "profiles_update_default", method: "PUT")

# 9) GET /profiles/:id — profiles#show
drive(ProfilesController, :show, { id: "abc123" }, "profiles_show", "profiles_show_default",
      signed_in: false, format: :json)

$elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - $start
File.write(File.join(RESULTS, "elapsed_seconds.txt"), format("%.1f", $elapsed))
puts "== search_links_reports_profiles done (elapsed #{$elapsed.round(2)}s) =="