# frozen_string_literal: true
# Fix the last missing branch: profiles#show needs
# SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by__1_not_found == True

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

$user = symbolic_user("FX")

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

BASE = "/home/dev/project/reports/diaspora/results/search_links_reports_profiles"

ctrl, tc = make_harness(ProfilesController)
ctrl.singleton_class.define_method(:current_user)    { $user }
ctrl.singleton_class.define_method(:user_signed_in?) { true }
tc.instance_variable_get(:@request).env["warden"] = StubWarden.new($user)

ConcolicTargets.seed_overrides = {
  "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by__1_not_found" => true
}

dump = $interceptor.run(
  -> { tc.process(:show, method: "GET", params: { id: "abc123" }, format: :json); :ok },
  {}, label: "slrp_ps_v2_03", script: "rerun_new_mocks.rb"
)
dir = File.join(BASE, "profiles_show")
Dir.mkdir(dir) unless Dir.exist?(dir)
File.write(File.join(dir, "dump_slrp_ps_v2_03.json"), JSON.pretty_generate(dump))
err = dump["error"]
pcs = (dump["events"] || []).count { |e| e["type"] == "path_condition" }
puts "[slrp_ps_v2_03] PCs=#{pcs} error=#{err ? "#{err['type']}: #{err['message'][0,100]}" : 'none'}"