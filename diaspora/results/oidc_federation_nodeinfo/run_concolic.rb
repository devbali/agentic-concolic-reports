# frozen_string_literal: true
# run_concolic.rb — "oidc_federation_nodeinfo" batch
# Covers OIDC (token_endpoint, authorizations), federation (webfinger, host_meta,
# receive), and NodeInfo. Federation controllers are from diaspora_federation-rails
# engine; OIDC from Api::OpenidConnect namespace. Same ActionController::TestCase
# harness pattern.

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

RESULTS = "/home/dev/project/reports/diaspora/results/oidc_federation_nodeinfo"
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
  user.define_singleton_method(:current_sign_in_at) { Time.now }
  user
end

$user = symbolic_user("OFC")

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

puts "== oidc_federation_nodeinfo batch: harness ready =="
$start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# 1) POST /api/openid_connect/access_tokens — TokenEndpointController#create
# This invokes Rack middleware (Api::OpenidConnect::TokenEndpoint.new.call)
drive(Api::OpenidConnect::TokenEndpointController, :create, {},
      "access_tokens", "access_tokens_default", method: "POST", signed_in: false)

# 2) POST /api/openid_connect/authorization — AuthorizationsController#create
# Needs session-restore; may crash on session access
drive(Api::OpenidConnect::AuthorizationsController, :create, { approve: "true" },
      "authorizations", "authorizations_default", method: "POST")

# 3) GET /.well-known/webfinger — DiasporaFederation::WebfingerController#webfinger
# Engine controller; needs resource param
drive(DiasporaFederation::WebfingerController, :webfinger,
      { resource: "acct:alice@example.org" }, "webfinger", "webfinger_default",
      signed_in: false)

# 4) GET /.well-known/host-meta — DiasporaFederation::WebfingerController#host_meta
drive(DiasporaFederation::WebfingerController, :host_meta, {},
      "host_meta", "host_meta_default", signed_in: false)

# 5) GET /node_info/:version — NodeInfoController#document
drive(NodeInfoController, :document, { version: "1.0" },
      "node_info", "node_info_default", signed_in: false)

# 6) POST /receive/public — DiasporaFederation::ReceiveController#public
# Needs xml param or application/magic-envelope+xml content
drive(DiasporaFederation::ReceiveController, :public,
      { xml: "<xml>test</xml>" }, "receive_public", "receive_public_default",
      method: "POST", signed_in: false)

# 7) POST /receive/private — ReceiveController#private (needs :guid)
drive(DiasporaFederation::ReceiveController, :private,
      { guid: "abc123", xml: "<xml>test</xml>" }, "receive_private", "receive_private_default",
      method: "POST", signed_in: false)

$elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - $start
File.write(File.join(RESULTS, "elapsed_seconds.txt"), format("%.1f", $elapsed))
puts "== oidc_federation_nodeinfo done (elapsed #{$elapsed.round(2)}s) =="