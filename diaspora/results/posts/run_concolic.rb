# frozen_string_literal: true
# ============================================================================
# run_concolic.rb — "posts" batch of the diaspora concolic experiment.
#
# Drives the REAL diaspora controller actions (PostsController,
# ResharesController, StatusMessagesController) through Rails' own
# controller-test machinery (ActionController::TestCase), so every
# path_condition in the dumps comes from real app code branching on
# symbolic values. No app logic is replicated here: the harness only
# supplies request / params / current_user plumbing (the same things the
# app's own spec/controllers do), then invokes the real action method.
#
# Symbolic-user note (same as photos batch): current_user is a symbolic
# User whose *identity* (id / person_id / guid) is CONCRETE. Those values
# only appear inside ActiveRecord WHERE clauses or .to_sql (never branched
# on); if symbolic, to_sql crashes with NotImplementedError during
# query-predicate normalization. Branch-relevant values (query results,
# not_found, boolean columns) stay symbolic, so every PC still comes from
# real app branching.
#
# The coverage loop per entrypoint: drive the default branch (finder
# returns a symbolic record) and the seeded not-found branch where the app
# branches on it, then CoverageChecker (run separately, python) confirms.
# Entrypoints whose actions crash deep in unsupported symbolic machinery
# (Dispatcher / Federation / carrier-wave / presenter rendering) record
# their PCs-before-crash under the dump's "error" key and are reported
# honestly as incomplete-with-error.
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

interceptor = CallInterceptor.instance
ConcolicTargets.install!(interceptor)

RESULTS = "/home/dev/project/reports/diaspora/results/posts"
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
  user.define_singleton_method(:aspects)       { Aspect.all }
  user.define_singleton_method(:aspect_ids)    { [1] }
  user.define_singleton_method(:photos)        { Photo.all }
  user.define_singleton_method(:participations){ Participation.all }
  user.define_singleton_method(:contacts)      { Contact.all }
  user.define_singleton_method(:blocks)        { Block.all }
  user
end

$posts_user = symbolic_user("PO")

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
  puts "  [#{label}] PCs=#{pc_count(dump)} error=#{err ? "#{err['type']}: #{err['message'][0,80]}" : 'none'}"
end

def drive(controller_class, action, params, ep, label, signed_in: true, user: $posts_user, seeds: {})
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user) { user }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  ctrl.params = params.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(action); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump(ep, label, dump)
  dump_summary(label, dump)
  dump
end

puts "== posts batch: harness ready =="

# ---- 1) posts#show (anonymous :show path) ---------------------------------
# PostService#find! (anonymous) -> find_public! -> Post.where(...).first
# then post.public? -> Diaspora::NonPublic -> authenticate_user!. Branches:
#   finder not_found (RecordNotFound), public? true/false.
{
  "posts_show_default"   => { seeds: {} },
  "posts_show_notfound"  => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true } },
  "posts_show_public"    => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false,
                                       "SYM_RESULT_ActiveRecord__FinderMethods_first_1_public" => true } },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(PostsController)
  ctrl.singleton_class.define_method(:current_user) { $posts_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { false }
  ctrl.params = { id: 1 }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:show); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("posts_show", label, dump)
  dump_summary(label, dump)
end

# ---- 2) posts#oembed (anonymous) ------------------------------------------
# OEmbedPresenter.id_from_url -> post_service.find! (find_public!). Branch on
# post.public? -> NonPublic. Rendering OEmbedPresenter may crash (reported).
{
  "posts_oembed_default" => { seeds: {} },
  "posts_oembed_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true } },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(PostsController)
  ctrl.singleton_class.define_method(:current_user) { $posts_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { false }
  ctrl.params = { url: "http://example.com/posts/1" }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:oembed); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("posts_oembed", label, dump)
  dump_summary(label, dump)
end

# ---- 3) posts#mentionable (authenticated) ---------------------------------
# post_service.mentionable_in_comment -> find! (authenticated
# find_visible_shareable_by_id -> EvilQuery::VisibleShareableById#post!) then
# Person.allowed_to_be_mentioned_in_a_comment_to(...).where.not(...). No query
# branch yields a PC until the finder. Likely crashes deep (report honestly).
{
  "posts_mentionable_default" => { seeds: {} },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(PostsController)
  ctrl.singleton_class.define_method(:current_user) { $posts_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  ctrl.params = { id: 1, q: "bob" }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:mentionable); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("posts_mentionable", label, dump)
  dump_summary(label, dump)
end

# ---- 4) posts#destroy (authenticated) -------------------------------------
# PostService#destroy -> find! (authenticated path) -> post.author == user.person
# -> user.retract(post) (Federation, likely crashes).
{
  "posts_destroy_default" => { seeds: {} },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(PostsController)
  ctrl.singleton_class.define_method(:current_user) { $posts_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  ctrl.params = { id: 1 }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:destroy); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("posts_destroy", label, dump)
  dump_summary(label, dump)
end

# ---- 5) reshares#create (authenticated) -----------------------------------
# ReshareService#create -> post_service.find! (authenticated path) ->
# post.absolute_root if Reshare -> user.reshare!(post).
{
  "reshares_create_default" => { seeds: {} },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(ResharesController)
  ctrl.singleton_class.define_method(:current_user) { $posts_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  ctrl.params = { root_guid: "abc123" }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:create); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("reshares_create", label, dump)
  dump_summary(label, dump)
end

# ---- 6) reshares#index (public :index) ------------------------------------
# ReshareService#find_for_post -> post_service.find! (anonymous find_public!)
# -> post.reshares -> includes(...).as_api_response.
{
  "reshares_index_default" => { seeds: {} },
  "reshares_index_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true } },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(ResharesController)
  ctrl.singleton_class.define_method(:current_user) { $posts_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { false }
  ctrl.params = { post_id: 1 }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:index); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("reshares_index", label, dump)
  dump_summary(label, dump)
end

# ---- 7) status_messages#new (authenticated) --------------------------------
# params[:person_id] && fetch_person -> Person.where(id:).first branch on
# @person. Branch: person found / nil.
{
  "status_messages_new_default" => { seeds: {} },
  "status_messages_new_noperson" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true } },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(StatusMessagesController)
  ctrl.singleton_class.define_method(:current_user) { $posts_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  ctrl.params = { person_id: 1 }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:new); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("status_messages_new", label, dump)
  dump_summary(label, dump)
end

# ---- 8) status_messages#create (authenticated) -----------------------------
# StatusMessageCreationService.create(normalize_params) -> build_status_message
# -> user.build_post(:status_message) -> Post.diaspora_initialize. deep path.
{
  "status_messages_create_default" => { seeds: {} },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(StatusMessagesController)
  ctrl.singleton_class.define_method(:current_user) { $posts_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  ctrl.params = { status_message: { text: "hello" }, aspect_ids: "all_aspects" }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:create); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("status_messages_create", label, dump)
  dump_summary(label, dump)
end

# ---- 9) status_messages#bookmarklet (authenticated) ------------------------
# current_user.aspects -> gon.preloads[:bookmarklet] = {..}. Renders.
{
  "status_messages_bookmarklet_default" => { seeds: {} },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(StatusMessagesController)
  ctrl.singleton_class.define_method(:current_user) { $posts_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  ctrl.params = { content: "x", title: "t", url: "http://e.com", notes: "n" }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:bookmarklet); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("status_messages_bookmarklet", label, dump)
  dump_summary(label, dump)
end

puts "== posts batch done =="

# ===========================================================================
# Phase 2 — close remaining CoverageChecker-identified branches (seeded runs)
# prefix constraints from the first pass; omit if already present in Phase 1.
# ===========================================================================
puts "== posts batch: coverage-loop phase 2 =="

# posts_show / posts_oembed / reshares_index: take first_2 not_found branch
{
  "posts_show"   => PostsController,
  "posts_oembed" => PostsController,
  "reshares_index" => ResharesController,
}.each do |ep, ctrl|
  key = ep
  unless File.exist?(File.join(RESULTS, ep, "dump_#{ep}_deep.json"))
  seeds = { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true,
            "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => true }
  case ep
  when "posts_show"
    ConcolicTargets.seed_overrides = seeds
    c, = make_harness(ctrl)
    c.singleton_class.define_method(:current_user) { $posts_user }
    c.singleton_class.define_method(:user_signed_in?) { false }
    c.params = { id: 1 }.with_indifferent_access
    d = interceptor.run(-> { c.send(:show); :ok }, {}, label: "#{ep}_deep", script: "run_concolic.rb")
    write_dump(ep, "#{ep}_deep", d); dump_summary("#{ep}_deep", d)
  when "posts_oembed"
    ConcolicTargets.seed_overrides = seeds
    c, = make_harness(ctrl)
    c.singleton_class.define_method(:current_user) { $posts_user }
    c.singleton_class.define_method(:user_signed_in?) { false }
    c.params = { url: "http://example.com/posts/1" }.with_indifferent_access
    d = interceptor.run(-> { c.send(:oembed); :ok }, {}, label: "#{ep}_deep", script: "run_concolic.rb")
    write_dump(ep, "#{ep}_deep", d); dump_summary("#{ep}_deep", d)
  when "reshares_index"
    ConcolicTargets.seed_overrides = seeds
    c, = make_harness(ctrl)
    c.singleton_class.define_method(:current_user) { $posts_user }
    c.singleton_class.define_method(:user_signed_in?) { false }
    c.params = { post_id: 1 }.with_indifferent_access
    d = interceptor.run(-> { c.send(:index); :ok }, {}, label: "#{ep}_deep", script: "run_concolic.rb")
    write_dump(ep, "#{ep}_deep", d); dump_summary("#{ep}_deep", d)
  end
  end
end

# posts_destroy / reshares_create: not-found branch of the first finder
{
  "posts_destroy"   => PostsController,
  "reshares_create" => ResharesController,
}.each do |ep, ctrl|
  unless File.exist?(File.join(RESULTS, ep, "dump_#{ep}_notfound.json"))
  ConcolicTargets.seed_overrides = { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true }
  c, = make_harness(ctrl)
  c.singleton_class.define_method(:current_user) { $posts_user }
  c.singleton_class.define_method(:user_signed_in?) { true }
  if ep == "posts_destroy"
    c.params = { id: 1 }.with_indifferent_access
    d = interceptor.run(-> { c.send(:destroy); :ok }, {}, label: "posts_destroy_notfound", script: "run_concolic.rb")
    write_dump("posts_destroy", "posts_destroy_notfound", d); dump_summary("posts_destroy_notfound", d)
  else
    c.params = { root_guid: "abc123" }.with_indifferent_access
    d = interceptor.run(-> { c.send(:create); :ok }, {}, label: "reshares_create_notfound", script: "run_concolic.rb")
    write_dump("reshares_create", "reshares_create_notfound", d); dump_summary("reshares_create_notfound", d)
  end
  end
end

# status_messages_new: find_by_1 not-found branch (contact lookup)
ep = "status_messages_new"
unless File.exist?(File.join(RESULTS, ep, "dump_#{ep}_nofindby.json"))
ConcolicTargets.seed_overrides = {
  "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false,
  "SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found" => true,
}
c, = make_harness(StatusMessagesController)
c.singleton_class.define_method(:current_user) { $posts_user }
c.singleton_class.define_method(:user_signed_in?) { true }
c.params = { person_id: 1 }.with_indifferent_access
d = interceptor.run(-> { c.send(:new); :ok }, {}, label: "#{ep}_nofindby", script: "run_concolic.rb")
write_dump(ep, "#{ep}_nofindby", d); dump_summary("#{ep}_nofindby", d)
end

# ---------------------------------------------------------------------------
# Phase 3 — close the deepest chained-finder not-found leaves. Each remaining
# missing branch is the not-found side of the Nth finder in a chain reached
# only when the earlier finders also return nil. Seeding the full chain
# closes the leaf. max_depth = number of chained finders for that entrypoint.
# ---------------------------------------------------------------------------
puts "== posts batch: coverage-loop phase 3 (deepest leaves) =="

{
  "posts_show"        => { ctrl: PostsController,      depth: 3, anon: true  },
  "posts_oembed"      => { ctrl: PostsController,      depth: 3, anon: true  },
  "reshares_index"    => { ctrl: ResharesController,   depth: 3, anon: true  },
  "posts_destroy"     => { ctrl: PostsController,      depth: 2, anon: false },
  "reshares_create"   => { ctrl: ResharesController,   depth: 2, anon: false },
}.each do |ep, cfg|
  dst = File.join(RESULTS, ep, "dump_#{ep}_maxdepth.json")
  next if File.exist?(dst)
  seeds = {}
  cfg[:depth].times { |i| seeds["SYM_RESULT_ActiveRecord__FinderMethods_first_#{i + 1}_not_found"] = true }
  ConcolicTargets.seed_overrides = seeds
  c, = make_harness(cfg[:ctrl])
  c.singleton_class.define_method(:user_signed_in?) { !cfg[:anon] }
  c.singleton_class.define_method(:current_user) { $posts_user }
  c.params =
    case ep
    when "posts_show" then { id: 1 }
    when "posts_oembed" then { url: "http://example.com/posts/1" }
    when "reshares_index" then { post_id: 1 }
    when "posts_destroy" then { id: 1 }
    when "reshares_create" then { root_guid: "abc123" }
    end.with_indifferent_access
  action = { posts_destroy: :destroy, reshares_create: :create,
             posts_show: :show, posts_oembed: :oembed,
             reshares_index: :index }[ep.to_sym]
  d = interceptor.run(-> { c.send(action); :ok }, {}, label: "#{ep}_maxdepth", script: "run_concolic.rb")
  write_dump(ep, "#{ep}_maxdepth", d); dump_summary("#{ep}_maxdepth", d)
end

puts "== posts batch phase 3 done =="