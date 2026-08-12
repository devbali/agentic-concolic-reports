# frozen_string_literal: true
# ============================================================================
# run_phase5.rb — posts_destroy & reshares_create: close the first_3_not_found
# "not_taken" leaf under prefix (first_1=True, first_2=True). Seed
# first_1=True, first_2=True, first_3=False. Seeds only; app code unchanged.
# ============================================================================
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "json"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)

RESULTS = "/home/dev/project/reports/diaspora/results/posts"
require "action_controller/test_case"

def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user)")
  person.define_singleton_method(:id) { 1 }
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:id) { 1 }
  user.define_singleton_method(:guid) { "abc123" }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:aspects)       { Aspect.all }
  user.define_singleton_method(:aspect_ids)    { [1] }
  user.define_singleton_method(:photos)        { Photo.all }
  user.define_singleton_method(:participations){ Participation.all }
  user.define_singleton_method(:contacts)      { Contact.all }
  user.define_singleton_method(:blocks)        { Block.all }
  user
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

def dump_summary(label, dump)
  err = dump["error"]
  puts "  [#{label}] PCs=#{pc_count(dump)} error=#{err ? "#{err['type']}: #{err['message'][0,70]}" : 'none'}"
end

$posts_user = symbolic_user("PO")

CONFIG = {
  "posts_destroy" =>   { ctrl: PostsController,  params: { id: 1 }, action: :destroy },
  "reshares_create" => { ctrl: ResharesController, params: { root_guid: "abc123" }, action: :create },
}

puts "== phase5: first_3 not_taken leaf under (1,2=True) =="
CONFIG.each do |ep, cfg|
  label = "#{ep}_leaf3"
  next if File.exist?(File.join(RESULTS, ep, "dump_#{label}.json"))
  ConcolicTargets.seed_overrides = {
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true,
    "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => true,
    "SYM_RESULT_ActiveRecord__FinderMethods_first_3_not_found" => false,
  }
  c, = make_harness(cfg[:ctrl])
  c.singleton_class.define_method(:user_signed_in?) { true }
  c.singleton_class.define_method(:current_user) { $posts_user }
  c.params = cfg[:params].with_indifferent_access
  dump = $interceptor.run(-> { c.send(cfg[:action]); :ok }, {}, label: label, script: "run_phase5.rb")
  write_dump(ep, label, dump)
  dump_summary(label, dump)
end
puts "== phase5 done =="