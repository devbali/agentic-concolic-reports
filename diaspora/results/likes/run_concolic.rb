# frozen_string_literal: true
# ============================================================================
# run_concolic.rb — "likes" batch of the diaspora concolic experiment.
#
# Drives the REAL diaspora controller actions (LikesController) through
# Rails' own controller-test machinery (ActionController::TestCase), so every
# path_condition in the dumps comes from real app code branching on symbolic
# values. No app logic is replicated here: the harness only supplies request /
# params / current_user plumbing (the same things the app's own
# spec/controllers do), then invokes the real action method.
#
# Entrypoints:
#   likes#create  -> LikesController#create -> LikeService#create ->
#                    PostService#find! (3-chained .first finders) -> user.like!
#   likes#destroy -> LikesController#destroy -> LikeService#destroy ->
#                    Like.find (raising finder) -> user.owns?(like) ->
#                    user.retract(like)
#   likes#index   -> LikesController#index (ANONYMOUS) -> LikeService#
#                    find_for_post -> PostService#find! (public path) ->
#                    post.likes.includes(...).as_api_response(:backbone)
#
# Symbolic-user note (same as posts / contacts_aspects_blocks / conversations
# batches): current_user is a symbolic User whose *identity* (id / person_id /
# person.id) is CONCRETE (needed for WHERE construction in
# EvilQuery::VisibleShareableById#post! and for delegation). Its relations are
# symbolic ActiveRecord relations so finders on them return symbolic records.
#
# Runner-local plumbing (app/src read-only):
#   * `PostLikeAssociations` prepend gives *symbolic* Post instances a `likes`
#     association reader returning `Like.all` (a symbolic relation). A
#     `klass.allocate`-built record has no association cache, so the real
#     `has_many :likes` reader would crash in AR before reaching a symbolic op.
#     Guarded by `concolic_attrs`, so real Posts are untouched. This mirrors
#     the proven `ConvoSymAssociations` prepend in the conversations batch.
#
# Coverage loop per entrypoint: defaults -> seeded not-found branches where the
# app branches on a finder -> CoverageChecker (python, run separately)
# confirms complete.
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

RESULTS = "/home/dev/project/reports/diaspora/results/likes"
Dir.mkdir(RESULTS) unless Dir.exist?(RESULTS)

require "action_controller/test_case"

# ---------------------------------------------------------------------------
# Symbolic current_user (concrete identity, symbolic query results)
# ---------------------------------------------------------------------------
def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user)")
  person.define_singleton_method(:id) { 1 } # concrete identity: WHERE build only
  user = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:id) { 1 }
  user.define_singleton_method(:guid) { "abc123" }
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  # Relations consumed by the likes controllers / services.
  user.define_singleton_method(:contacts)      { Contact.all }
  user.define_singleton_method(:participations){ Participation.all }
  user
end

$likes_user = symbolic_user("LK")

# ---------------------------------------------------------------------------
# Association readers on finder-symbolic Post instances.
#
# `ConcolicTargets.symbolic_instance(Post, ...)` builds the record via
# `klass.allocate` (skips initialize), so Post's association cache is nil and
# the real `has_many :likes` / `likes` reader would crash in
# active_record/associations.rb before reaching a symbolic op. That is a
# harness/plumbing artifact, not a concolic-runtime NotImplementedError —
# fixed here (runner-scoped, app/src read-only) by supplying the likes
# association as a symbolic `Like.all` relation on concolic instances only.
# `.includes(author: :profile)` then chains into the mocked finder targets on
# downstream materialization.
module PostLikeAssociations
  def likes
    if respond_to?(:concolic_attrs)
      Like.all
    else
      super
    end
  end
end
Post.prepend(PostLikeAssociations)

# ---------------------------------------------------------------------------
# Harness: build a controller-test instance for a controller class.
# ---------------------------------------------------------------------------
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

def drive(controller_class, action, params, ep, label, user: $likes_user, anon: false, seeds: {})
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(controller_class)
  # For authenticated actions, current_user is the symbolic user. For
  # anonymous actions (likes#index, authenticate_user! except: :index) it is
  # genuinely nil so LikeService `PostService.new(nil)` takes the public
  # find_public! path (faithful). Defining it explicitly (not nil-default)
  # also avoids falling through to Devise's helper, which would raise
  # Devise::MissingWarden in the controller-test rig (no warden proxy).
  ctrl.singleton_class.define_method(:current_user) { anon ? nil : user }
  ctrl.singleton_class.define_method(:user_signed_in?) { !anon }
  ctrl.params = params.with_indifferent_access
  dump = $interceptor.run(-> { ctrl.send(action); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump(ep, label, dump)
  dump_summary(label, dump)
  dump
end

puts "== likes batch: harness ready =="
$start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# ---- 1) likes#create -------------------------------------------------------
# LikeService#create -> PostService#find! -> user.find_visible_shareable_by_id
# -> EvilQuery::VisibleShareableById#post! -> three chained `.first` finders;
# the FIRST one (querent_has_visibility) branches: found -> symbolic Post,
# not-found (seed) -> RecordNotFound, rescued in the controller -> render
# status 422 (controller-test response boundary). On the found side:
# user.like! -> Like::Generator#create! -> Like.new(...).save! (symbool,
# bare-truthiness gap) -> logger.info interpolation of the symbolic guid
# (SymStr) -> SymbolicString#to_s NotImplementedError. The find! finder PC is
# recorded before the crash.
{
  "likes_create_default" => { seeds: {}, params: { post_id: 1 } },
  "likes_create_post_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true }, params: { post_id: 1 } },
  # post! = q1.first || q2.first || q3.first; .first is NON-raising, so a
  # not-found first finder yields nil and the app falls through to the next
  # finder. Closing the q2-not-found leaf (checker: prefix first_1=True,
  # missing first_2=True) requires seeding both first_1 and first_2 true.
  "likes_create_chain_notfound" => { seeds: {
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true,
    "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => true,
  }, params: { post_id: 1 } },
  # Close the third (public_post) finder leaf: seed the full chain so each
  # `.first` returns nil and post! falls through to public_post.first
  # (checker: prefix first_1=True, first_2=True, missing first_3=True).
  "likes_create_leaf3_notfound" => { seeds: {
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true,
    "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => true,
    "SYM_RESULT_ActiveRecord__FinderMethods_first_3_not_found" => true,
  }, params: { post_id: 1 } },
}.each do |label, cfg|
  drive(LikesController, :create, cfg[:params], "likes_create", label, seeds: cfg[:seeds])
end

# ---- 2) likes#destroy ------------------------------------------------------
# LikeService#destroy -> Like.find(like_id) (RAISING finder) -> records the
# find_1_not_found PC on both sides (RecordNotFound raised on the missing
# side, propagates out of the controller — destroy has no rescue). On the
# found side: user.owns?(like) -> person.owns?(like) -> person.id ==
# like.author_id. person.id is the concrete `1` (identity, needed for the
# find path); like.author_id is a symbolic SymInt, so `1 == symint` is a
# concrete Integer#== on a symbolic arg — the comparison emits no PC (the
# concrete-arg gap, documented honestly) and yields false, so the app takes
# the "not owns" branch -> returns false -> render status 404
# (controller-test response boundary). The finder PC is recorded.
{
  "likes_destroy_default" => { seeds: {}, params: { id: 1 } },
  "likes_destroy_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_1_not_found" => true }, params: { id: 1 } },
}.each do |label, cfg|
  drive(LikesController, :destroy, cfg[:params], "likes_destroy", label, seeds: cfg[:seeds])
end

# ---- 3) likes#index (ANONYMOUS — authenticate_user! except: :index) --------
# LikeService#find_for_post -> PostService#find! (user is nil) ->
# find_public! -> Post.where(id:...).first (non-raising finder mock) ->
# symbolic Post (first_1_not_found PC) or nil. `unless post` — bare
# truthiness gap. On the found side: post.likes (symbolic relation from the
# prepend) .includes(author: :profile).as_api_response(:backbone) — the
# relation materializes via to_a -> SymbolicList -> acts_as_api maps over it
# -> SymbolicList contents-op NotImplementedError. The index action has no
# rescue, so a seeded not-found raises RecordNotFound out of the controller
# (finder PC still recorded).
{
  "likes_index_default" => { seeds: {}, params: { post_id: 1, format: :json } },
  "likes_index_post_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true }, params: { post_id: 1, format: :json } },
  # Close the public?=True branch (checker: prefix first_1 not_found=False,
  # missing public=True): seed a FOUND post that is public, so no
  # Diaspora::NonPublic is raised and the app proceeds to post.likes.
  "likes_index_public" => { seeds: {
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false,
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_public" => true,
  }, params: { post_id: 1, format: :json } },
}.each do |label, cfg|
  drive(LikesController, :index, cfg[:params], "likes_index", label, anon: true, seeds: cfg[:seeds])
end

$elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - $start
File.write(File.join(RESULTS, "elapsed_seconds.txt"), format("%.1f", $elapsed))
puts "== likes batch done (elapsed #{$elapsed.round(2)}s) =="