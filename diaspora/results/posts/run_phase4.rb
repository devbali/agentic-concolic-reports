# frozen_string_literal: true
# ============================================================================
# run_phase4.rb — close the deepest chained-finder not-found leaves for the
# "posts" batch. The CoverageChecker wants first_N_not_found=True with an
# all-True prefix chain (1..N-1). We seed the full chain and re-run so the
# app records the leaf. Independent of app/runtime source: only the
# harness seeds + invocation live here (app code unchanged, seed names come
# from the checker's own concrete_values).
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
  "posts_show" =>       { ctrl: PostsController,  anon: true,  action: :show,   params: { id: 1 } },
  "posts_oembed" =>     { ctrl: PostsController,  anon: true,  action: :oembed, params: { url: "http://example.com/posts/1" } },
  "reshares_index" =>   { ctrl: ResharesController, anon: true, action: :index, params: { post_id: 1 } },
  "posts_destroy" =>    { ctrl: PostsController,  anon: false, action: :destroy, params: { id: 1 } },
  "reshares_create" =>  { ctrl: ResharesController, anon: false, action: :create, params: { root_guid: "abc123" } },
}

# Drive one entrypoint with a chain of not_found=True seeds of given depth.
def run_chain(ep, depth, label)
  cfg = CONFIG.fetch(ep)
  seeds = {}
  depth.times { |i| seeds["SYM_RESULT_ActiveRecord__FinderMethods_first_#{i + 1}_not_found"] = true }
  ConcolicTargets.seed_overrides = seeds
  c, = make_harness(cfg[:ctrl])
  c.singleton_class.define_method(:user_signed_in?) { !cfg[:anon] }
  c.singleton_class.define_method(:current_user) { $posts_user }
  c.params = cfg[:params].with_indifferent_access
  dump = $interceptor.run(-> { c.send(cfg[:action]); :ok }, {}, label: label, script: "run_phase4.rb")
  write_dump(ep, label, dump)
  dump_summary(label, dump)
  dump
end

# Try depths 4..10 for each remaining entrypoint (the chain may be longer
# than the 3 previously assumed). We run a few depths and keep whichever
# reveals the missing prefix; CoverageChecker is run separately.
puts "== phase4: deep-chain seeds =="
{
  "posts_show"       => [3, 4, 5],
  "posts_oembed"     => [3, 4, 5],
  "reshares_index"   => [3, 4, 5],
  "posts_destroy"    => [3, 4],
  "reshares_create"  => [3, 4],
}.each do |ep, depths|
  depths.each do |depth|
    label = "#{ep}_chain#{depth}"
    next if File.exist?(File.join(RESULTS, ep, "dump_#{label}.json"))
    run_chain(ep, depth, label)
  end
end
puts "== phase4 done =="