# frozen_string_literal: true
# ============================================================================
# run_concolic.rb — "people" batch of the diaspora concolic experiment.
#
# Drives the REAL diaspora controller actions (PeopleController) through
# Rails' own controller-test machinery (ActionController::TestCase), so every
# path_condition in the dumps comes from real app code branching on symbolic
# values. The harness only supplies request / params / current_user plumbing
# (the same things the app's own spec/controllers do), then invokes the real
# action method.
#
# Entrypoints:
#   people#index          -> Person.search / Person.where(...).first (html &
#                            json branches in Person.search), render as_json
#   people#show           -> find_person -> Person.find_from_guid_or_username
#                            (find_by) OR Person.where(...).first via
#                            diaspora_id?(username); closed_account? predicate;
#                            PersonPresenter render
#   people#stream         -> find_person + Stream::Person#posts ->
#                            @person.posts.where(public: true) ->
#                            for_a_stream -> stream_posts.map
#   people#hovercard      -> find_person + PersonPresenter#hovercard render
#   people#refresh_search -> Person.where(...); @people.empty? (Relation
#                            empty? symbolic) -> hashes_for_people .map
#   people#retrieve_remote-> params[:diaspora_handle] ->
#                            Workers::FetchWebfinger.perform_async (Sidekiq)
#                            or head :ok / :unprocessable_entity
#
# Symbolic-user note (same as posts / conversations / likes batches):
# current_user and the found @person are symbolic but their *identity*
# (id / person_id / person.id) is CONCRETE (needed for WHERE construction and
# delegation). All query results / boolean columns stay symbolic so every PC
# comes from real app branching.
#
# Association plumbing (runner-scoped, app/src read-only): finder-symbolic
# records are built via klass.allocate, so AR's @association_cache is nil and
# association readers (person.posts, person.profile, person.blocks) would
# crash in active_record/associations.rb before reaching a symbolic op. A
# Person prepend supplies those readers as symbolic `.all` relations (guarded
# by concolic_attrs so real records are untouched), letting the app's real
# Stream::Person / presenter code chain into the mocked finder targets.
#
# Coverage loop per entrypoint: defaults -> seeded not-found / empty? branches
# where the app branches on a finder/relation -> CoverageChecker (python, run
# separately) confirms. Pure-presenter-render entrypoints that crash after the
# finder PC (unsupported symbolic machinery) keep the PCs-before-crash under
# the dump's "error" key and are reported honestly.
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

RESULTS = "/home/dev/project/reports/diaspora/results/people"
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
  user.define_singleton_method(:diaspora_handle) { "alice@example.org" }
  # language is read in the REAL ApplicationController#set_locale before_action
  # (I18n.locale = current_user.language); if symbolic it crashes in i18n's
  # enforce_available_locales! (`locale != false`) before the action runs. It is
  # a branch-irrelevant identity setting, so make it concrete (same rationale as
  # concrete id/guid). gender is read (only on inflected locales, English is
  # skipped) — keep it concrete too to avoid a latent crash.
  user.define_singleton_method(:language) { "en" }
  user.define_singleton_method(:gender)    { "" }
  # Relations consumed by PeopleController / helpers.
  user.define_singleton_method(:contacts)    { Contact.all }
  user.define_singleton_method(:blocks)      { Block.all }
  user.define_singleton_method(:aspects)     { Aspect.all }
  user.define_singleton_method(:contact_for) do |p|
    # u.contact_for -> contact_for_person_id -> Contact.includes(...).find_by
    Contact.includes(person: :profile).find_by(user_id: 1, person_id: p.id)
  end
  user.define_singleton_method(:block_for)  { |_p| Block.none }
  user.define_singleton_method(:posts_from) { |_p| Post.all }
  user
end

$people_user = symbolic_user("PE")

# ---------------------------------------------------------------------------
# Association readers on finder-symbolic Person instances (allocated records
# have a nil @association_cache, so the real has_many/belongs_to readers would
# crash in active_record/associations.rb before reaching a symbolic op). This
# is the same runner-scoped "supply symbolic association" pattern used by the
# posts / conversations / likes batches; guarded by concolic_attrs so real
# persisted records are untouched.
module PersonSymAssociations
  def posts
    if respond_to?(:concolic_attrs)
      Post.all
    else
      super
    end
  end

  def profile
    if respond_to?(:concolic_attrs)
      ConcolicTargets.symbolic_instance(Profile, "SYM_PROFILE_PERSON",
                                        "Person#profile (has_one)")
    else
      super
    end
  end

  def blocks
    if respond_to?(:concolic_attrs)
      Block.all
    else
      super
    end
  end
end
Person.prepend(PersonSymAssociations)

# ---------------------------------------------------------------------------
# Devise/warden stub for authenticated entrypoints (index, refresh_search,
# retrieve_remote). authenticate_user! -> warden.authenticate!(scope: :user)
# would hit Devise::MissingWarden in the controller-test rig (no warden env).
# This is a runner-local plumbing substitute for Devise only (same class of
# workaround as the symbolic user's concrete identity): it makes the REAL
# authenticate_user! before_action pass so the real action body runs and its
# real finders/Pcs get recorded. No app logic is replicated.
# ---------------------------------------------------------------------------
class StubWarden
  def initialize(user)
    @user = user
  end
  def authenticate!(*_args)
    @user
  end
  def authenticated?(*_args)
    true
  end
  def user(*_args)
    @user
  end
end

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

def drive(controller_class, action, params, ep, label, signed_in: true, method: "GET", format: nil, seeds: {})
  ConcolicTargets.seed_overrides = seeds
  ctrl, tc = make_harness(controller_class)
  # authenticate_user! gates index/refresh_search/retrieve_remote; show/stream/
  # hovercard are exempt (:show :stream :hovercard in the except list).
  ctrl.singleton_class.define_method(:current_user)    { signed_in ? $people_user : nil }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  # Let Devise's real authenticate_user! pass for signed-in entrypoints.
  tc.instance_variable_get(:@request).env["warden"] = StubWarden.new($people_user)
  # Use Rails' own request cycle (TestRequest#process -> dispatch) so the real
  # before_action chain (incl. find_person) and respond_to/render run for real.
  # action is the controller action symbol; params/format go through the
  # route-generator exactly as a controller spec would.
  dump = $interceptor.run(
    -> { tc.process(action, method: method, params: params, format: format); :ok },
    {}, label: label, script: "run_concolic.rb"
  )
  write_dump(ep, label, dump)
  dump_summary(label, dump)
  dump
end

puts "== people batch: harness ready =="
$start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# ---- 1) people#index (authenticated) --------------------------------------
# Person.search(search_query, current_user). Two concrete-param search paths
# (diaspora_id? and find_by_substring) branch on concrete strings, not
# symbolic values, so those record no PC. The result relation is then
# materialized for render (as_json) -> SymbolicList -> contents-op crash in
# acts_as_api (crash-before-PC). A diaspora_handle query also routes through
# Person.where(diaspora_handle: ..., closed_account: false).empty? inside the
# controller (Relation empty? symbolic -> records a PC) before the failover
# background_search.
{
  # q is a plain substring (<2 chars => Person.search returns NullRelation) ->
  # @people.paginate on a NullRelation; json render materializes SymbolicList.
  "people_index_shortq_json" => { seeds: {}, params: { q: "a" }, format: :json },
  "people_index_shortq_html" => { seeds: {}, params: { q: "a" }, format: :html },
  # q is a valid diaspora handle -> diaspora_id? true -> in html branch the
  # controller does Person.where(...).empty? (symbolic Relation empty?) then
  # paginate -> hashes_for_people .map (SymbolicList#each crash). empty?
  # records a PC.
  "people_index_handle_html" => { seeds: {}, params: { q: "bob@example.org" }, format: :html },
  # close the empty?=True (failover background_search) leaf: seed the relation
  # empty. background_search -> sidekiq perform_async + gon preload; may crash
  # in the rig after the empty? PC.
  "people_index_handle_empty" => { seeds: {
    "SYM_RESULT_ActiveRecord__Relation_empty_1" => true,
  }, params: { q: "bob@example.org" }, format: :html },
  "people_index_found_json" => { seeds: {}, params: { q: "bob", limit: 5 }, format: :json },
}.each do |label, cfg|
  drive(PeopleController, :index, cfg[:params], "people_index", label, seeds: cfg[:seeds], format: cfg[:format])
end

# ---- 2) people#show (anonymous — find_person before_action) ---------------
# find_person with a diaspora-ID username -> Person.where(...).first
# (first_1_not_found PC) -> raise AccountClosed if @person.closed_account?
# (predicate PC) -> PersonPresenter render (unsupported symbolic machinery,
# honest crash). The GUID find_by path (params[:id]) hits the AR StatementCache
# wall -> SymbolicList#first crash-before-PC (documented below).
{
  # diaspora_id?(username) true -> Person.where(...).first -> symbolic Person
  # (first_1_not_found=False PC) -> closed_account? False -> presenter crash.
  "people_show_diasporaid_first" => { seeds: {}, params: { username: "bob@example.org" } },
  # seed first_1_not_found=True -> find_person raises RecordNotFound ->
  # rescue_from renders public/404 (MissingTemplate rig crash after PC).
  "people_show_diasporaid_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true }, params: { username: "bob@example.org" } },
  # close the closed_account?=True (AccountClosed) leaf: seed found + closed.
  "people_show_diasporaid_closed" => { seeds: {
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false,
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account" => true,
  }, params: { username: "bob@example.org" } },
  # GUID find_by path (params[:id]) -> Person.find_from_guid_or_username ->
  # find_by -> AR StatementCache wall -> SymbolicList#first (0 PCs, honest
  # crash-before-PC like likes#destroy).
  "people_show_findby_statementcache" => { seeds: {}, params: { id: 1 } },
}.each do |label, cfg|
  drive(PeopleController, :show, cfg[:params], "people_show", label, signed_in: false, seeds: cfg[:seeds])
end

# ---- 3) people#stream (anonymous — find_person + authenticate_if_remote) --
# find_person via the diaspora-ID username param (query string sets
# params[:username]) -> Person.where(...).first PC + closed_account? predicate
# PC -> stream action json -> person_stream -> Stream::Person#posts ->
# @person.posts.where(public: true) (posts relation supplied) -> for_a_stream
# -> stream_posts.map len-1 SymbolicList -> map (contents-op) crash in
# LastThreeCommentsDecorator iteration. Finder + closed PCs kept.
{
  "people_stream_default"  => { seeds: {}, params: { person_id: 1, username: "bob@example.org" }, format: :json },
  # seed closed_account?=true -> find_person raises AccountClosed before the
  # stream action (PC recorded).
  "people_stream_closed"   => { seeds: {
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false,
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account" => true,
  }, params: { person_id: 1, username: "bob@example.org" }, format: :json },
  "people_stream_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true }, params: { person_id: 1, username: "bob@example.org" }, format: :json },
}.each do |label, cfg|
  drive(PeopleController, :stream, cfg[:params], "people_stream", label, signed_in: false, seeds: cfg[:seeds], format: cfg[:format])
end

# ---- 4) people#hovercard (anonymous — find_person) -------------------------
# find_person via diaspora-ID username -> Person.where(...).first PC +
# closed_account? predicate PC -> PersonPresenter#hovercard ->
# base_hash_with_contact + ProfilePresenter.new(profile).for_hovercard ->
# profile association supplied, ProfilePresenter render -> image_url / name
# interpolation of symbolic strings -> SymStr#to_s / arithmetic
# NotImplementedError (crash after the finder PCs).
{
  "people_hovercard_default"  => { seeds: {}, params: { person_id: 1, username: "bob@example.org" } },
  "people_hovercard_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true }, params: { person_id: 1, username: "bob@example.org" } },
  # close the closed_account?=True (AccountClosed) leaf for hovercard (checker
  # missing): seed found + closed -> find_person raises AccountClosed ->
  # rescue_from Diaspora::AccountClosed -> respond_to head (rig boundary).
  "people_hovercard_closed" => { seeds: {
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false,
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account" => true,
  }, params: { person_id: 1, username: "bob@example.org" } },
}.each do |label, cfg|
  drive(PeopleController, :hovercard, cfg[:params], "people_hovercard", label, signed_in: false, seeds: cfg[:seeds])
end

# ---- 5) people#refresh_search (authenticated) ------------------------------
# Person.where(diaspora_handle:, closed_account: false) then
# unless @people.empty? (Relation empty? symbolic -> PC) -> hashes_for_people
# -> .map on SymbolicList (contents-op crash). Empty side -> render json
# {search_html: "", ...}.to_json (render boundary).
{
  "people_refresh_search_default" => { seeds: {},    params: { q: "bob@example.org" } },
  "people_refresh_search_empty"   => { seeds: { "SYM_RESULT_ActiveRecord__Relation_empty_1" => true }, params: { q: "bob@example.org" } },
}.each do |label, cfg|
  drive(PeopleController, :refresh_search, cfg[:params], "people_refresh_search", label, seeds: cfg[:seeds])
end

# ---- 6) people#retrieve_remote (authenticated) -----------------------------
# params[:diaspora_handle] present -> Workers::FetchWebfinger.perform_async
# (Sidekiq producer; likely crash-before-PC in the controller-test rig without
# a live Sidekiq/Redis) -> head :ok. Missing handle -> head :unprocessable_entity.
# No branchable symbolic finder -> crash-before-PC is expected/honest.
{
  "people_retrieve_remote_default" => { seeds: {}, params: { diaspora_handle: "bob@example.org" } },
  "people_retrieve_remote_nohandle" => { seeds: {}, params: {} },
}.each do |label, cfg|
  drive(PeopleController, :retrieve_remote, cfg[:params], "people_retrieve_remote", label, method: "POST", seeds: cfg[:seeds])
end

$elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - $start
File.write(File.join(RESULTS, "elapsed_seconds.txt"), format("%.1f", $elapsed))
puts "== people batch done (elapsed #{$elapsed.round(2)}s) =="
