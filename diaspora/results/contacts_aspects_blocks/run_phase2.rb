# frozen_string_literal: true
# ============================================================================
# run_phase2.rb — close the CoverageChecker-identified missing branches for
# the "contacts_aspects_blocks" batch. The checker's concrete_values (fed as
# seed_overrides) drive the app to record the missing taken/not_taken sides
# of each finder / comparison node. App + runtime are read-only; only the
# harness seeds + invocation live here.
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
  dump = $interceptor.run(-> { ctrl.send(action); :ok }, {}, label: label, script: "run_phase2.rb")
  write_dump(ep, label, dump)
  dump_summary(label, dump)
end

puts "== contacts_aspects_blocks phase2: close checker-identified branches =="

# aspects_show: first_1_not_found=True (aspect finder -> nil -> redirect paths_path)
drive(AspectsController, :show, { id: 1 }, "aspects_show", "aspects_show_notfound",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true })

# aspects_update: first_1_not_found=True (aspect nil -> NoMethodError on update!, PC recorded)
drive(AspectsController, :update, { id: 1, aspect: { name: "New" } }, "aspects_update", "aspects_update_notfound",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true })

# aspects_destroy: first_1_not_found=True (RecordNotFound branch of finder was
# non-raising `.first`? no — first is non-raising -> aspect nil -> `.id` crash;
# PC recorded for the not_found=True side)
drive(AspectsController, :destroy, { id: 1 }, "aspects_destroy", "aspects_destroy_notfound",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true })

# aspects_destroy: close id-match not_taken side (auto_follow aspect id != aspect id)
drive(AspectsController, :destroy, { id: 1 }, "aspects_destroy", "aspects_destroy_nomatch",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_1_id" => 7,
               "SYM_AUTO_FOLLOW_ASPECT_id" => 3 })

# aspects_toggle_chat_privilege: first_1_not_found=True
drive(AspectsController, :toggle_chat_privilege, { id: 1 }, "aspects_toggle_chat_privilege", "aspects_toggle_notfound",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true })

# aspects_update_order: find_1_not_found=True; and find_2 under prefix find_1=False
drive(AspectsController, :update_order, { ordered_aspect_ids: [1, 2] }, "aspects_update_order", "aspects_update_order_find1nf",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_find_1_not_found" => true })
drive(AspectsController, :update_order, { ordered_aspect_ids: [1, 2] }, "aspects_update_order", "aspects_update_order_find2nf",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_find_1_not_found" => false,
               "SYM_RESULT_ActiveRecord__FinderMethods_find_2_not_found" => true })

# aspect_memberships_destroy:
#   - first_2_not_found=True under prefix first_1=True
drive(AspectMembershipsController, :destroy, { id: 1 }, "aspect_memberships_destroy", "aspect_memberships_destroy_a1nf_a2nf",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => true })
#   - first_2_not_found=True under prefix first_1=False
drive(AspectMembershipsController, :destroy, { id: 1 }, "aspect_memberships_destroy", "aspect_memberships_destroy_a1ok_a2nf",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => true })
#   - mine?(aspect): first_1_user_id == 1 taken under prefix first_1=False, first_2=False
drive(AspectMembershipsController, :destroy, { id: 1 }, "aspect_memberships_destroy", "aspect_memberships_destroy_mine_ok",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => false,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_1_user_id" => 1 })

# share_visibilities_update: first_2_not_found=True under prefix first_1=True
# (find! chain: post_service.find! -> find_public! -> second finder leaf)
drive(ShareVisibilitiesController, :update, { post_id: 1 }, "share_visibilities_update", "share_visibilities_update_find2nf",
      seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true,
               "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => true })

puts "== phase2 done =="