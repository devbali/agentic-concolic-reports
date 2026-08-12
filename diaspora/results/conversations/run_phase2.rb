# frozen_string_literal: true
# ============================================================================
# run_phase2.rb — close the `first_2_not_found=True` leaf for
# conversations#show / conversations#raw (CoverageChecker missing branch).
#
# The found-path of both actions calls real Conversation#first_unread_message,
# which does `conversation_visibilities.where(...).first` (a second finder).
# CoverageChecker reports the `taken` side of that `first_2_not_found` leaf
# under prefix first_1_not_found=False. Recommended concrete_values:
#   SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found = False  (outer found)
#   SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found = True   (no visibility)
# Seed exactly that (values from the checker, verbatim). Same harness as
# run_concolic.rb — app + runtime source read-only, no fabricated PCs.
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

RESULTS = "/home/dev/project/reports/diaspora/results/conversations"
Dir.mkdir(RESULTS) unless Dir.exist?(RESULTS)
require "action_controller/test_case"

# --- same symbolic user + association readers as run_concolic.rb -----------
def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user)")
  person.define_singleton_method(:id) { 1 }
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:id) { 1 }
  user.define_singleton_method(:guid) { "abc123" }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:diaspora_handle) { "alice@example.org" }
  user.define_singleton_method(:contacts)      { Contact.all }
  user.define_singleton_method(:conversations) { Conversation.all }
  user
end

module ConvoSymAssociations
  def conversation_visibilities
    respond_to?(:concolic_attrs) ? ConversationVisibility.all : super
  end
  def messages
    respond_to?(:concolic_attrs) ? Message.all : super
  end
  def conversation
    if respond_to?(:concolic_attrs)
      ConcolicTargets.symbolic_instance(Conversation, "SYM_CV_BELONGS_CONVERSATION",
                                        "ConversationVisibility#conversation (belongs_to)")
    else
      super
    end
  end
  def participants
    respond_to?(:concolic_attrs) ? Person.all : super
  end
end
[Conversation, ConversationVisibility, Message].each { |k| k.prepend(ConvoSymAssociations) }

$convo_user = symbolic_user("CONV")

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

def drive(controller_class, action, params, ep, label, seeds:)
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user) { $convo_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  ctrl.request.format = params.delete(:format).to_sym if params.key?(:format)
  ctrl.params = params.with_indifferent_access
  dump = $interceptor.run(-> { ctrl.send(action); :ok }, {}, label: label, script: "run_phase2.rb")
  write_dump(ep, label, dump)
  dump_summary(label, dump)
  dump
end

puts "== conversations phase2: close first_2_not_found leaf =="

# first_1 found, first_2 (inner visibility) not found -> taken side of leaf.
seeds_vis_missing = {
  "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false,
  "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => true,
}

drive(ConversationsController, :show, { id: 1, format: :json },
      "conversations_show", "conversations_show_vis_missing", seeds: seeds_vis_missing)

drive(ConversationsController, :raw, { conversation_id: 1, format: :html },
      "conversations_raw", "conversations_raw_vis_missing", seeds: seeds_vis_missing)

puts "== conversations phase2 done =="