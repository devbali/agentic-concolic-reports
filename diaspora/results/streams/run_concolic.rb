# frozen_string_literal: true
# ============================================================================
# run_concolic.rb — "streams" batch of the diaspora concolic experiment.
#
# Drives the REAL diaspora controller actions (StreamsController) through
# Rails' own controller-test machinery (ActionController::TestCase), so every
# path_condition in the dumps comes from real app code branching on symbolic
# values. Mirrors the proven "people" batch harness (symbolic_user with
# concrete identity, StubWarden for Devise authenticate_user!, association
# prepends for finder-symbolic records). No app/src/shared code modified.
#
# Entrypoints:
#   streams#aspects       -> Stream::Aspect (user.visible_shareables / aspect_ids)
#   streams#public        -> Stream::Public (Post.all_public -> for_a_stream)
#   streams#activity      -> EvilQuery::Participation.new(user).posts
#   streams#multi         -> EvilQuery::MultiStream (current_user.getting_started
#                              branch -> gon.preloads[:getting_started])
#   streams#commented     -> EvilQuery::CommentedPosts.new(user).posts
#   streams#liked         -> EvilQuery::LikedPosts.new(user).posts
#   streams#mentioned     -> Stream::Mention (StatusMessage.user_tag_stream)
#   streams#followed_tags -> Stream::FollowedTag (user.followed_tags)
#
# stream_responder -> @stream.stream_posts -> posts.for_a_stream(...).tap {
# like_posts_for_stream! } -> controller json: @stream.stream_posts.map { ... }
# SymbolicList#map contents-op -> NotImplementedError (crash-before-render, but
# the posts relation's own branches — e.g. EvilQuery's .first != nil / joins
# finders, Post.all_public scope — record PCs before that). html/mobile render
# 'streams/main_stream' (template boundary in the controller-test rig).
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

RESULTS = "/home/dev/project/reports/diaspora/results/streams"
Dir.mkdir(RESULTS) unless Dir.exist?(RESULTS)

require "action_controller/test_case"

# ---- symbolic current_user (concrete identity, symbolic query results) ------
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
  user.define_singleton_method(:gender)    { "" }
  user.define_singleton_method(:contacts)    { Contact.all }
  user.define_singleton_method(:blocks)      { Block.all }
  user.define_singleton_method(:aspects)     { Aspect.all }
  user.define_singleton_method(:post_default_aspects) { Aspect.all }
  user.define_singleton_method(:post_default_public)  { true }
  # getting_started is branched on in StreamsController#multi. It's a bare
  # `if` (Ruby truthiness gap) — returns a concrete bool seeded via
  # ConcolicTargets.seed_overrides so both sides can be driven/recorded.
  user.define_singleton_method(:getting_started) do
    ConcolicTargets.seed_overrides.fetch("USER_GETTING_STARTED", true)
  end
  user.define_singleton_method(:invited_by) { nil }
  user.define_singleton_method(:followed_tags) { ActsAsTaggableOn::Tag.all }
  user.define_singleton_method(:visible_shareables) do |*_a|
    Post.all
  end
  user
end

$user = symbolic_user("ST")

# ActsAsTaggableOn::Tag (app/models/acts_as_taggable_on-tag.rb) is namespaced;
# used by Stream::FollowedTag / Stream::Multi via user.followed_tags. Load the
# real model file so the constant resolves (no behavior fabricated).
begin
  ActsAsTaggableOn::Tag
rescue NameError
  require "/home/dev/project/ruby_examples/dse-apps/apps/diaspora/app/models/acts_as_taggable_on-tag.rb"
end


# ---- association readers on finder-symbolic records ------------------------
module StreamAssociations
  def followed_tags
    respond_to?(:concolic_attrs) ? ActsAsTaggableOn::Tag.all : super
  end
end
User.prepend(StreamAssociations)

# ---- StubWarden for Devise authenticate_user! ------------------------------
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

def dump_summary(label, dump)
  err = dump["error"]
  puts "  [#{label}] PCs=#{pc_count(dump)} error=#{err ? "#{err['type']}: #{err['message'][0,90]}" : 'none'}"
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
  dump_summary(label, dump)
  dump
end

puts "== streams batch: harness ready =="
$start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# All streams are authenticated except #public.
def stream_entry(ep, action, params = {})
  {
    "#{ep}_json"  => { seeds: {}, params: params, format: :json },
    "#{ep}_html"  => { seeds: {}, params: params, format: :html },
  }
end

# 1) streams#public (anonymous — except: :public)
{
  "streams_public_json" => { seeds: {}, params: {}, format: :json, signed_in: false },
  "streams_public_html" => { seeds: {}, params: {}, format: :html, signed_in: false },
}.each do |label, cfg|
  drive(StreamsController, :public, cfg[:params], "streams_public", label,
        signed_in: cfg[:signed_in], format: cfg[:format])
end

# 2) streams#aspects — save_selected_aspects + Stream::Aspect
{
  "streams_aspects_json" => { seeds: {}, params: { a_ids: [1] }, format: :json },
  "streams_aspects_html" => { seeds: {}, params: { a_ids: [1] }, format: :html },
}.each do |label, cfg|
  drive(StreamsController, :aspects, cfg[:params], "streams_aspects", label, format: cfg[:format])
end

# 3) streams#activity — EvilQuery::Participation
{
  "streams_activity_json" => { seeds: {}, params: {}, format: :json },
  "streams_activity_html" => { seeds: {}, params: {}, format: :html },
}.each do |label, cfg|
  drive(StreamsController, :activity, cfg[:params], "streams_activity", label, format: cfg[:format])
end

# 4) streams#multi — current_user.getting_started branch (real) + MultiStream
{
  "streams_multi_json" => { seeds: {}, params: {}, format: :json },
  "streams_multi_html" => { seeds: {}, params: {}, format: :html },
}.each do |label, cfg|
  drive(StreamsController, :multi, cfg[:params], "streams_multi", label, format: cfg[:format])
end

# 5) streams#commented — EvilQuery::CommentedPosts
{
  "streams_commented_json" => { seeds: {}, params: {}, format: :json },
  "streams_commented_html" => { seeds: {}, params: {}, format: :html },
}.each do |label, cfg|
  drive(StreamsController, :commented, cfg[:params], "streams_commented", label, format: cfg[:format])
end

# 6) streams#liked — EvilQuery::LikedPosts
{
  "streams_liked_json" => { seeds: {}, params: {}, format: :json },
  "streams_liked_html" => { seeds: {}, params: {}, format: :html },
}.each do |label, cfg|
  drive(StreamsController, :liked, cfg[:params], "streams_liked", label, format: cfg[:format])
end

# 7) streams#mentioned — Stream::Mention
{
  "streams_mentioned_json" => { seeds: {}, params: {}, format: :json },
  "streams_mentioned_html" => { seeds: {}, params: {}, format: :html },
}.each do |label, cfg|
  drive(StreamsController, :mentioned, cfg[:params], "streams_mentioned", label, format: cfg[:format])
end

# 8) streams#followed_tags — Stream::FollowedTag
{
  "streams_followed_tags_json" => { seeds: {}, params: {}, format: :json },
  "streams_followed_tags_html" => { seeds: {}, params: {}, format: :html },
}.each do |label, cfg|
  drive(StreamsController, :followed_tags, cfg[:params], "streams_followed_tags", label, format: cfg[:format])
end

$elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - $start
File.write(File.join(RESULTS, "elapsed_seconds.txt"), format("%.1f", $elapsed))
puts "== streams batch done (elapsed #{$elapsed.round(2)}s) =="