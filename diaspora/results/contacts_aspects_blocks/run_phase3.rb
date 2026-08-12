# frozen_string_literal: true
# ============================================================================
# run_phase3.rb — close the final CoverageChecker-identified deep leaves for
# "contacts_aspects_blocks". All seed values come straight from the checker's
# concrete_values (real app branches on real symbolic finder results).
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

RESULTS = "/home/dev/project/reports/diaspora/results/contacts_aspects_blocks"
Dir.mkdir(RESULTS) unless Dir.exist?(RESULTS)
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
  user.define_singleton_method(:contacts)      { Contact.all }
  user.define_singleton_method(:blocks)        { Block.all }
  user.define_singleton_method(:auto_follow_back_aspect) do
    ConcolicTargets.symbolic_instance(Aspect, "SYM_AUTO_FOLLOW_ASPECT", "auto_follow_back_aspect")
  end
  user
end
$cab_user = symbolic_user("CAB")

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
def pc_count(d); (d["events"] || []).count { |e| e["type"] == "path_condition" }; end
def dump_summary(label, dump)
  err = dump["error"]
  puts "  [#{label}] PCs=#{pc_count(dump)} error=#{err ? "#{err['type']}: #{err['message'][0,80]}" : 'none'}"
end

def drive(controller_class, action, params, ep, label, seeds: {})
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user) { $cab_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  ctrl.params = params.merge(format: :html).with_indifferent_access
  dump = $interceptor.run(-> { ctrl.send(action); :ok }, {}, label: label, script: "run_phase3.rb")
  write_dump(ep, label, dump)
  dump_summary(label, dump)
end

puts "== contacts_aspects_blocks phase3: close deepest leaves =="

# aspects_toggle_chat_privilege: first_2_not_found=True under prefix first_1=True
drive(AspectsController, :toggle_chat_privilege, { id: 1 }, "aspects_toggle_chat_privilege", "aspects_toggle_double_nf",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => true })

# aspects_toggle_chat_privilege: first_2_chat_enabled=True under prefix first_1=True, first_2=False
drive(AspectsController, :toggle_chat_privilege, { id: 1 }, "aspects_toggle_chat_privilege", "aspects_toggle_chat_enabled",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => false,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_2_chat_enabled" => true })

# aspect_memberships_destroy: mine?(contact) -> first_2_user_id == 1 taken,
# under prefix first_1=False, first_2=False, first_1_user_id=1
drive(AspectMembershipsController, :destroy, { id: 1 }, "aspect_memberships_destroy", "aspect_memberships_destroy_mine_both",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_1_user_id" => 1,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => false,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_2_user_id" => 1 })

# share_visibilities_update: first_3_not_found=True under prefix first_1=True, first_2=True
drive(ShareVisibilitiesController, :update, { post_id: 1 }, "share_visibilities_update", "share_visibilities_update_find3nf",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => true,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_3_not_found" => true })

puts "== phase3 done =="