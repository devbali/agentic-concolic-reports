# frozen_string_literal: true
# ============================================================================
# run_concolic.rb — "photos" batch of the diaspora concolic experiment.
#
# Drives the REAL diaspora controller actions (PhotosController,
# ParticipationsController, PollParticipationsController) through Rails'
# own controller-test machinery (ActionController::TestCase), so every
# path_condition in the dumps comes from real app code branching on
# symbolic values. No app logic is replicated here: the harness only
# supplies request / params / current_user plumbing (the same things the
# app's own spec/controllers do), then invokes the real action method.
#
# Symbolic-user note:
#   current_user is a symbolic User whose *identity* (id / person_id) is
#   kept CONCRETE. Those values only appear inside ActiveRecord WHERE
#   clauses (they're never branched on); if made symbolic, `to_sql` in the
#   finder mocks crashes with "NotImplementedError: SymbolicInt#hash"
#   (query-predicate normalization hashes bound values). Branch-relevant
#   values — query results (finder not_found), boolean columns (public?,
#   pending) — stay symbolic, so every PC still comes from real app
#   branching. This mirrors the README's verified posts#show pattern
#   (concrete id into PostService, branch on post.public?).
#
# The coverage loop per entrypoint: drive default branch (finder returns a
# symbolic record) and the seeded not-found branch (finder returns nil →
# app's other side), then run CoverageChecker to confirm no missing branch.
# ============================================================================
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "json"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
# Keep CarrierWave image processing off (the app's own spec/helpers do this).
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

interceptor = CallInterceptor.instance
ConcolicTargets.install!(interceptor)

RESULTS = "/home/dev/project/reports/diaspora/results/photos"
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
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:person_id) { 1 }
  user.define_singleton_method(:photos)        { Photo.all }
  user.define_singleton_method(:participations) { Participation.all }
  user.define_singleton_method(:aspects)       { Aspect.all }
  user
end

# Global symbolic user reused across entrypoints (fresh helpers per entrypoint).
$ph_user = symbolic_user("PH")

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

# Drive one real action. +action+ is a symbol; params already set on ctrl.
# +signed_in+ controls user_signed_in? (photo#show/index). Returns dump.
def drive(controller_class, action, params, label, signed_in: true, user: $ph_user, seeds: {}, extra: nil)
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user) { user }
  ctrl.singleton_class.define_method(:user_signed_in?) { signed_in }
  ctrl.params = params.with_indifferent_access
  dump = interceptor.run(-> {
    if extra
      extra.call(ctrl)
    else
      ctrl.send(action)
    end
    :ok
  }, {}, label: label, script: "run_concolic.rb")
  write_dump(entrypoint_for(action), label, dump)
  dump
end

def entrypoint_for(action)
  {
    show: "photos_show",
    index: "photos_index",
    create: "photos_create",
    destroy: "photos_destroy",
    make_profile_photo: "photos_make_profile_photo",
  }[action] || action.to_s
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
  (dump["events"] || []).each do |e|
    next unless e["type"] == "path_condition"
    puts "      PC #{e['expr']} |=#{e['taken']} @#{File.basename(e['file'].to_s)}:#{e['lineno']}"
  end
end

def seeds_for(finders, found: true)
  s = {}
  finders.each_with_index { |f, i| s["SYM_RESULT_ActiveRecord__#{f}_#{i + 1}_not_found"] = !found }
  s
end

puts "== photos batch: harness ready =="
# Entrypoints driven below via explicit calls.
# ===========================================================================
# Execution — drive every photos-batch entrypoint through the real action.
# ===========================================================================
puts "== photos batch: driving real controller actions =="

# ---- 1) photos#show (anonymous public-photo path) ------------------------
{
  "photos_show_anon_found"   => { seeds: {} },
  "photos_show_anon_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true } },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(PhotosController)
  ctrl.singleton_class.define_method(:user_signed_in?) { false }
  ctrl.params = { id: 1, person_id: "abc" }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:show); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("photos_show", label, dump)
  dump_summary(label, dump)
end

# ---- 2) photos#index ------------------------------------------------------
{
  "photos_index_person_found" => { seeds: {} },
  "photos_index_person_nil"   => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found" => true } },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(PhotosController)
  ctrl.singleton_class.define_method(:current_user) { $ph_user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  ctrl.params = { person_id: "abc" }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:index); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("photos_index", label, dump)
  dump_summary(label, dump)
end

# ---- 3) participations#create --------------------------------------------
{
  "participations_create_q1_found"   => { seeds: {} },
  "participations_create_q1_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true } },
  "participations_create_deep"        => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true,
                                                     "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => true } },
  "participations_create_all_nil"     => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true,
                                                     "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => true,
                                                     "SYM_RESULT_ActiveRecord__FinderMethods_first_3_not_found" => true } },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(ParticipationsController)
  ctrl.singleton_class.define_method(:current_user) { $ph_user }
  ctrl.params = { post_id: 1 }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:create); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("participations_create", label, dump)
  dump_summary(label, dump)
end

# ---- 4) participations#destroy -------------------------------------------
{
  "participations_destroy_found"   => { seeds: {} },
  "participations_destroy_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found" => true } },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(ParticipationsController)
  ctrl.singleton_class.define_method(:current_user) { $ph_user }
  ctrl.params = { post_id: 1 }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:destroy); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("participations_destroy", label, dump)
  dump_summary(label, dump)
end

# ---- 5) photos#destroy ----------------------------------------------------
{
  "photos_destroy_found"   => { seeds: {} },
  "photos_destroy_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true } },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(PhotosController)
  ctrl.singleton_class.define_method(:current_user) { $ph_user }
  ctrl.params = { id: 1 }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:destroy); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("photos_destroy", label, dump)
  dump_summary(label, dump)
end

# ---- 6) photos#make_profile_photo ----------------------------------------
{
  "photos_mkprof_found"   => { seeds: {} },
  "photos_mkprof_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true } },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(PhotosController)
  ctrl.singleton_class.define_method(:current_user) { $ph_user }
  ctrl.params = { photo_id: 1 }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:make_profile_photo); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("photos_make_profile_photo", label, dump)
  dump_summary(label, dump)
end

# ---- 7) photos#create -----------------------------------------------------
{
  "photos_create_default" => { seeds: {} },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(PhotosController)
  ctrl.singleton_class.define_method(:current_user) { $ph_user }
  ctrl.params = { photo: { aspect_ids: "all", pending: false, set_profile_photo: false } }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:create); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("photos_create", label, dump)
  dump_summary(label, dump)
end

# ---- 8) poll_participations#create ---------------------------------------
{
  "poll_participations_create_default" => { seeds: {} },
}.each do |label, cfg|
  ConcolicTargets.seed_overrides = cfg[:seeds]
  ctrl, = make_harness(PollParticipationsController)
  ctrl.singleton_class.define_method(:current_user) { $ph_user }
  ctrl.params = { post_id: 1, poll_answer_id: 1 }.with_indifferent_access
  dump = interceptor.run(-> { ctrl.send(:create); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump("poll_participations_create", label, dump)
  dump_summary(label, dump)
end

puts "== photos batch done =="
