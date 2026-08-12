# frozen_string_literal: true
# Seed-based re-run for the 2 incomplete streams entrypoints (aspects, multi).
# The base runner produced 18 dumps across 8 entrypoints; CoverageChecker
# found 2 missing branches. This script feeds those concrete values back
# through seed_overrides and writes the extra dumps.

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

RESULTS = "/home/dev/project/reports/diaspora/results/streams"

# --- symbolic_user (same as base runner) ----------------------------------
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
  user.define_singleton_method(:getting_started) do
    ConcolicTargets.seed_overrides.fetch("USER_GETTING_STARTED", true)
  end
  user.define_singleton_method(:invited_by) { nil }
  user.define_singleton_method(:followed_tags) { ActsAsTaggableOn::Tag.all }
  user.define_singleton_method(:visible_shareables) { |*_a| Post.all }
  user
end

$user = symbolic_user("ST")

begin
  ActsAsTaggableOn::Tag
rescue NameError
  require "/home/dev/project/ruby_examples/dse-apps/apps/diaspora/app/models/acts_as_taggable_on-tag.rb"
end

module StreamAssociations
  def followed_tags
    respond_to?(:concolic_attrs) ? ActsAsTaggableOn::Tag.all : super
  end
end
User.prepend(StreamAssociations)

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
    {}, label: label, script: "run_concolic_seeds.rb"
  )
  write_dump(ep, label, dump)
  err = dump["error"]
  puts "  [#{label}] PCs=#{pc_count(dump)} error=#{err ? "#{err['type']}: #{err['message'][0,80]}" : 'none'}"
  dump
end

puts "== streams seed re-runs =="

# --- aspects: sizes NOT equal (missing not_taken from eq check) ----------
puts "aspects: seed (sizes unequal)"
drive(StreamsController, :aspects, { a_ids: [1] }, "aspects", "streams_aspects_seeded",
      format: :json, seeds: {
        "SYM_RESULT_ActiveRecord__Relation_size_1_size" => 1,
        "SYM_RESULT_ActiveRecord__Relation_size_2_size" => 0,
      })

# --- multi: size = 0 (missing not_taken from > 0 check) -----------------
puts "multi: seed (size = 0)"
drive(StreamsController, :multi, {}, "multi", "streams_multi_seeded",
      format: :json, seeds: {
        "SYM_RESULT_ActiveRecord__Relation_size_1_size" => 0,
      })

puts "== streams seed re-runs done =="