# frozen_string_literal: true
# ============================================================================
# run_concolic.rb — "contacts_aspects_blocks" batch of the diaspora concolic
# experiment.
#
# Drives the REAL diaspora controller actions (ContactsController,
# AspectsController, AspectMembershipsController, BlocksController,
# ShareVisibilitiesController) through Rails' own controller-test machinery
# (ActionController::TestCase), so every path_condition in the dumps comes
# from real app code branching on symbolic values. No app logic is
# replicated here: the harness only supplies request / params / current_user
# plumbing (the same things the app's own spec/controllers do), then invokes
# the real action method.
#
# Symbolic-user note (same as posts/photos batches): current_user is a
# symbolic User whose *identity* (id / person_id) is CONCRETE; its relations
# (aspects/contacts/blocks) are symbolic ActiveRecord relations so finders
# on them return symbolic records. Helper methods the controllers call
# (share_with, contact_for, mine?, toggle_hidden_shareable, auto_follow_back*)
# run the REAL app implementations; where they crash on symbolic values the
# crash is captured under the dump's "error" key with PCs-before-crash kept.
# Association readers not materialized as simple columns
# (auto_follow_back_aspect) are supplied as a symbolic Aspect so the app's
# comparisons on them stay symbolic (this mirrors what the real association
# would return).
#
# Coverage loop per entrypoint: defaults -> seeded not-found branches where
# the app branches on a finder -> CoverageChecker (python, run separately)
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

RESULTS = "/home/dev/project/reports/diaspora/results/contacts_aspects_blocks"
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
  user.define_singleton_method(:contacts)      { Contact.all }
  user.define_singleton_method(:blocks)        { Block.all }
  # auto_follow_back_aspect is an association reader (not a simple column).
  # Supply a symbolic Aspect so the controller's comparison
  # aspect.id == auto_follow_back_aspect.id stays symbolic (mirrors the real
  # association).
  user.define_singleton_method(:auto_follow_back_aspect) do
    ConcolicTargets.symbolic_instance(Aspect, "SYM_AUTO_FOLLOW_ASPECT", "auto_follow_back_aspect")
  end
  user
end

$cab_user = symbolic_user("CAB")

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

def drive(controller_class, action, params, ep, label, user: $cab_user, seeds: {})
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(controller_class)
  ctrl.singleton_class.define_method(:current_user) { user }
  ctrl.singleton_class.define_method(:user_signed_in?) { true }
  if params.key?(:format)
    ctrl.request.format = params.delete(:format).to_sym
  end
  ctrl.params = params.with_indifferent_access
  dump = $interceptor.run(-> { ctrl.send(action); :ok }, {}, label: label, script: "run_concolic.rb")
  write_dump(ep, label, dump)
  dump_summary(label, dump)
  dump
end

puts "== contacts_aspects_blocks batch: harness ready =="

# ---- 1) contacts#index (html) ----------------------------------------------
# set_up_contacts: current_user.aspects.find(params[:a_id]) finder ->
# symbolic Aspect; current_user.contacts.size -> symint. No finder branch PC
# beyond the aspect finder (size is a query result used as data). Rendering
# of the html template will likely crash (no template in controller-test).
{
  "contacts_index_default" => { seeds: {}, params: { a_id: 1 } },
  "contacts_index_aspect_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_find_1_not_found" => true }, params: { a_id: 1 } },
}.each do |label, cfg|
  drive(ContactsController, :index, cfg[:params].merge(format: :html), "contacts_index", label, seeds: cfg[:seeds])
end

# ---- 2) contacts#spotlight -------------------------------------------------
# Person.community_spotlight -> relation (no iteration/branch in action).
# 0 PCs expected (simple assignment).
{
  "community_spotlight_default" => { seeds: {} },
}.each do |label, cfg|
  drive(ContactsController, :spotlight, { format: :html }, "community_spotlight", label, seeds: cfg[:seeds])
end

# ---- 3) aspects#create -----------------------------------------------------
# current_user.aspects.build -> real Aspect; @aspect.save intercepted ->
# symbool (records save ok). Branch on save: render result vs head
# :unprocessable_entity. If a person_id is given, connect_person_to_aspect:
# Person.find finder -> symbolic. Branch on @contact.
{
  "aspects_create_default" => { seeds: {}, params: { aspect: { name: "Family" } } },
  "aspects_create_save_fail" => { seeds: { "SYM_RESULT_ActiveRecord__Persistence_save_1_ok" => false }, params: { aspect: { name: "Family" } } },
  "aspects_create_with_person" => { seeds: {}, params: { aspect: { name: "Family" }, person_id: 2 } },
}.each do |label, cfg|
  drive(AspectsController, :create, cfg[:params], "aspects_create", label, seeds: cfg[:seeds])
end

# ---- 4) aspects#show -------------------------------------------------------
# private `aspect` -> current_user.aspects.where(id:).first (non-raising
# finder) -> returns symbolic Aspect (truthy) or nil. `if aspect` is the
# bare-truthiness gap (documented) — only one concrete side is taken.
{
  "aspects_show_default" => { seeds: {}, params: { id: 1 } },
}.each do |label, cfg|
  drive(AspectsController, :show, cfg[:params], "aspects_show", label, seeds: cfg[:seeds])
end

# ---- 5) aspects#update -----------------------------------------------------
# aspect.update!(aspect_params) — update! not declared as a target -> runs
# real AR update on the symbolic Aspect -> likely crashes / hits DB.
# aspect.id / aspect.name symbolic. Branch on update result.
{
  "aspects_update_default" => { seeds: {}, params: { id: 1, aspect: { name: "New" } } },
}.each do |label, cfg|
  drive(AspectsController, :update, cfg[:params], "aspects_update", label, seeds: cfg[:seeds])
end

# ---- 6) aspects#destroy ----------------------------------------------------
# aspect finder -> symbolic; current_user.auto_follow_back (bool -> symbool);
# aspect.id == auto_follow_back_aspect.id (symbolic compare). Branch on
# auto_follow_back && id-match. aspect.destroy -> persistence. request.referer
# used for redirect choice.
{
  "aspects_destroy_default" => { seeds: {}, params: { id: 1 } },
}.each do |label, cfg|
  drive(AspectsController, :destroy, cfg[:params], "aspects_destroy", label, seeds: cfg[:seeds])
end

# ---- 7) aspects#update_order ----------------------------------------------
# iterates real params array; current_user.aspects.find(id) finder ->
# symbolic Aspect; .update(order_id:) intercepted -> symbool.
{
  "aspects_update_order_default" => { seeds: {}, params: { ordered_aspect_ids: [1, 2] } },
}.each do |label, cfg|
  drive(AspectsController, :update_order, cfg[:params], "aspects_update_order", label, seeds: cfg[:seeds])
end

# ---- 8) aspects#toggle_chat_privilege -------------------------------------
# aspect.chat_enabled (bool -> symbool); !aspect.chat_enabled records PC;
# aspect.save intercepted -> symbool.
{
  "aspects_toggle_default" => { seeds: {} },
  "aspects_toggle_enabled" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_chat_enabled" => true } },
}.each do |label, cfg|
  drive(AspectsController, :toggle_chat_privilege, { id: 1 }, "aspects_toggle_chat_privilege", label, seeds: cfg[:seeds])
end

# ---- 9) aspect_memberships#create ------------------------------------------
# Person.find finder -> symbolic person; aspects.where(id:).first finder ->
# symbolic aspect; current_user.share_with(@person, @aspect) -> REAL impl:
# blocks.exists?, contacts.find_or_initialize_by (not framework-declared ->
# hits DB / crashes). Branch on @contact.present?.
{
  "aspect_memberships_create_default" => { seeds: {}, params: { person_id: 2, aspect_id: 1 } },
}.each do |label, cfg|
  drive(AspectMembershipsController, :create, cfg[:params], "aspect_memberships_create", label, seeds: cfg[:seeds])
end

# ---- 10) aspect_memberships#destroy ----------------------------------------
# Two chained finders (aspects.joins.first, contacts.joins.first), then
# mine?(a) && mine?(c) (real: self.id == target.user_id symbolic compare),
# membership = contact.aspect_memberships.where(...).first finder, then
# membership.destroy. Refused branches (RecordNotFound) via seeds.
{
  "aspect_memberships_destroy_default" => { seeds: {}, params: { id: 1 } },
  "aspect_memberships_destroy_noaspect" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true }, params: { id: 1 } },
  "aspect_memberships_destroy_nomembership" => { seeds: {
    "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false,
    "SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found" => false,
    "SYM_RESULT_ActiveRecord__FinderMethods_first_3_not_found" => false,
    "SYM_RESULT_ActiveRecord__FinderMethods_first_3_not_found2" => false, # safety
  }, params: { id: 1 } },
}.each do |label, cfg|
  drive(AspectMembershipsController, :destroy, cfg[:params], "aspect_memberships_destroy", label, seeds: cfg[:seeds])
end

# ---- 11) blocks#create -----------------------------------------------------
# current_user.blocks.new -> real Block; block.save intercepted -> symbool.
# Branch on save. On save: contact_for(block.person) real -> find_by ->
# symbolic contact/nil; branch if contact.
{
  "blocks_create_default" => { seeds: {}, params: { block: { person_id: 2 } } },
  "blocks_create_save_fail" => { seeds: { "SYM_RESULT_ActiveRecord__Persistence_save_1_ok" => false }, params: { block: { person_id: 2 } } },
}.each do |label, cfg|
  drive(BlocksController, :create, cfg[:params], "blocks_create", label, seeds: cfg[:seeds])
end

# ---- 12) blocks#destroy ----------------------------------------------------
# blocks.find_by(id:) non-raising finder -> symbolic block/nil.
# `block&.delete` — delete not declared -> real method on symbolic (likely
# crashes/DB); ContactRetraction federation likely crashes. Honest.
{
  "blocks_destroy_default" => { seeds: {}, params: { id: 1 } },
  "blocks_destroy_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found" => true }, params: { id: 1 } },
}.each do |label, cfg|
  drive(BlocksController, :destroy, cfg[:params], "blocks_destroy", label, seeds: cfg[:seeds])
end

# ---- 13) share_visibilities#update -----------------------------------------
# post_service.find!(params[:post_id]) -> POST fetch; finder (raising) ->
# records not_found PC. Then current_user.toggle_hidden_shareable(post) ->
# real impl; share.id (symint).to_s -> NotImplementedError (crash PC-before).
{
  "share_visibilities_update_default" => { seeds: {}, params: { post_id: 1 } },
  "share_visibilities_update_notfound" => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true }, params: { post_id: 1 } },
}.each do |label, cfg|
  drive(ShareVisibilitiesController, :update, cfg[:params], "share_visibilities_update", label, seeds: cfg[:seeds])
end

puts "== contacts_aspects_blocks batch done =="