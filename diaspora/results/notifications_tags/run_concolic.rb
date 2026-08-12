# frozen_string_literal: true
# run_concolic.rb — "notifications_tags" batch
# Drives NotificationsController, TagsController, TagFollowingsController through
# ActionController::TestCase. Same pattern as the proved people/streams batches.

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

RESULTS = "/home/dev/project/reports/diaspora/results/notifications_tags"
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
  user.define_singleton_method(:followed_tags) { ActsAsTaggableOn::Tag.all }
  user.define_singleton_method(:visible_shareables) { |*_a| Post.all }
  user
end

$user = symbolic_user("NT")

class StubWarden
  def initialize(user); @user = user; end
  def authenticate!(*_); @user; end
  def authenticated?(*_); true; end
  def user(*_); @user; end
end

def make_harness(controller_class)
  cname = controller_class.to_s.sub(/Controller\z/, "ControllerTest")
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

puts "== notifications_tags batch: harness ready =="
$start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# ---- notifications#index ----
drive(NotificationsController, :index, {}, "notifications_index", "notifications_index_default",
      format: :json, seeds: {})

# ---- notifications#update ----
drive(NotificationsController, :update, { id: 1 }, "notifications_update", "notifications_update_default",
      method: "PUT", format: :json, seeds: {})

# ---- notifications#read_all ----
drive(NotificationsController, :read_all, {}, "notifications_read_all", "notifications_read_all_default",
      format: :json, seeds: {})

# ---- tags#index ----
drive(TagsController, :index, { q: "ruby" }, "tags_index", "tags_index_default",
      format: :json, seeds: {})

# ---- tags#show ----
drive(TagsController, :show, { name: "testtag", page: 1 }, "tags_show", "tags_show_default",
      format: :json, seeds: {})

# ---- tag_followings#index ----
drive(TagFollowingsController, :index, {}, "tag_followings_index", "tag_followings_index_default",
      format: :json, seeds: {})

# ---- tag_followings#create ----
drive(TagFollowingsController, :create, { name: "cooltag" }, "tag_followings_create", "tag_followings_create_default",
      method: "POST", format: :json, seeds: {})

# ---- tag_followings#destroy ----
drive(TagFollowingsController, :destroy, { id: "1" }, "tag_followings_destroy", "tag_followings_destroy_default",
      method: "DELETE", format: :json, seeds: {})

# ---- tag_followings#manage ----
drive(TagFollowingsController, :manage, {}, "tag_followings_manage", "tag_followings_manage_default",
      format: :html, seeds: {})

$elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - $start
File.write(File.join(RESULTS, "elapsed_seconds.txt"), format("%.1f", $elapsed))
puts "== notifications_tags batch done (elapsed #{$elapsed.round(2)}s) =="