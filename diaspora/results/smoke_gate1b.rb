# frozen_string_literal: true
# Gate 1b smoke — validate the new SCSM targets fire and reduce the each-wall
# for the streams batch, without a full 13-batch rerun.
# Launch: scripts/diaspora-concolic reports/diaspora/results/smoke_gate1b.rb
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

OUT = "/home/dev/project/reports/diaspora/results/smoke_gate1b"
Dir.mkdir(OUT) unless Dir.exist?(OUT)

def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person")
  person.define_singleton_method(:id) { 1 }
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User")
  user.define_singleton_method(:id) { 1 }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:getting_started) { true }
  user.define_singleton_method(:invited_by) { nil }
  user.define_singleton_method(:post_default_public) { true }
  user.define_singleton_method(:visible_shareables) { |*_a| Post.all }
  user.define_singleton_method(:aspects) { Aspect.all }
  user.define_singleton_method(:followed_tags) { ActsAsTaggableOn::Tag.all }
  user
end
$user = symbolic_user("SMOKE")

begin
  ActsAsTaggableOn::Tag
rescue NameError
  require "/home/dev/project/ruby_examples/dse-apps/apps/diaspora/app/models/acts_as_taggable_on-tag.rb"
end

class StubWarden
  def initialize(u); @u = u; end
  def authenticate!(*_); @u; end
  def authenticated?(*_); true; end
  def user(*_); @u; end
end

def make_harness(klass)
  cname = klass.to_s.sub(/Controller\z/, "SmokeTest")
  Object.const_set(cname, Class.new(ActionController::TestCase)) unless Object.const_defined?(cname)
  tc = Object.const_get(cname).new("noop")
  tc.setup_controller_request_and_response
  tc.instance_variable_set(:@routes, Rails.application.routes)
  [tc.instance_variable_get(:@controller), tc]
end

def pc_count(d); (d["events"] || []).count { |e| e["type"] == "path_condition" }; end
def sym_targets(d)
  (d["events"] || []).select { |e| e["type"] == "symbolic_call" }.map { |e| e["target"] }
end

def run_one(klass, action, label, params: {})
  ctrl, tc = make_harness(klass)
  ctrl.singleton_class.define_method(:current_user) { $user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  tc.instance_variable_get(:@request).env["warden"] = StubWarden.new($user)
  d = $interceptor.run(-> { tc.process(action, params: params, format: :json); :ok }, {},
                       label: label, script: "smoke_gate1b.rb")
  err = d["error"]
  puts "[#{label}] PCs=#{pc_count(d)} err=#{err ? err['type'] : 'none'}"
  puts "    targets: #{sym_targets(d).select { |t| t =~ /Stream|excluding_blocks|blocks/ }.uniq.inspect}"
  File.write(File.join(OUT, "#{label}.json"), JSON.pretty_generate(d))
end

run_one(StreamsController, :multi, "smoke_multi")
run_one(StreamsController, :aspects, "smoke_aspects")
puts "smoke_gate1b done"
