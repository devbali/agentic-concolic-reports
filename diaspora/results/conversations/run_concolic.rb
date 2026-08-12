# frozen_string_literal: true
# ============================================================================
# run_concolic.rb — "conversations" batch of the diaspora concolic experiment.
#
# Drives the REAL diaspora controller actions (ConversationsController,
# MessagesController, ConversationVisibilitiesController) through Rails' own
# controller-test machinery (ActionController::TestCase), so every
# path_condition in the dumps comes from real app code branching on symbolic
# values. No app logic is replicated here: the harness only supplies
# request / params / current_user plumbing (the same things the app's own
# spec/controllers do), then invokes the real action method.
#
# Symbolic-user note (same as posts / contacts_aspects_blocks batches):
# current_user is a symbolic User whose identity (id / person_id / person) is
# CONCRETE; its relations (contacts / conversations) are symbolic AR
# relations so finders on them return symbolic records. Association readers
# on finder-symbolic records (@conversation.conversation_visibilities,
# @vis.conversation, ...) fall through to real AR relations; where they
# crash on symbolic values the crash is captured under the dump's "error"
# key with PCs-before-crash kept (README strict-runtime / report-honestly).
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

RESULTS = "/home/dev/project/reports/diaspora/results/conversations"
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
  # Relations consumed by conversations controllers / helpers.
  user.define_singleton_method(:contacts)      { Contact.all }
  user.define_singleton_method(:conversations) { Conversation.all }
  user
end

$convo_user = symbolic_user("CONV")

# ---------------------------------------------------------------------------
# Association readers on finder-symbolic records.
#
# `ConcolicTargets.symbolic_instance` builds the record via `klass.allocate`
# (skips initialize), so AR's @association_cache is nil and ANY association
# reader (`@conversation.conversation_visibilities`, `@vis.conversation`, ...)
# crashes in active_record/associations.rb `association_instance_get` before
# reaching a symbolic op. That is a harness/plumbing artifact, not a concolic
# runtime NotImplementedError — fixed here (runner-scoped, app/src read-only)
# by supplying the association readers as symbolic `.all` relations on concolic
# instances only (guarded by `concolic_attrs`, so real records are untouched).
# The relations chain the app's `.where(...).first` / `.count` into the mocked
# finder targets, so those record genuine path conditions (README §4 intent).
module ConvoSymAssociations
  def conversation_visibilities
    if respond_to?(:concolic_attrs)
      ConversationVisibility.all
    else
      super
    end
  end

  def messages
    if respond_to?(:concolic_attrs)
      Message.all
    else
      super
    end
  end

  def conversation
    if respond_to?(:concolic_attrs)
      # belongs_to -> a single symbolic Conversation so .participants / .count
      # (real methods) chain into the mocked finder/calculation targets.
      ConcolicTargets.symbolic_instance(Conversation, "SYM_CV_BELONGS_CONVERSATION",
                                        "ConversationVisibility#conversation (belongs_to)")
    else
      super
    end
  end

  def participants
    if respond_to?(:concolic_attrs)
      Person.all
    else
      super
    end
  end
end

[Conversation, ConversationVisibility, Message].each { |k| k.prepend(ConvoSymAssociations) }

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

def drive(controller_class, action, params, ep, label, user: $convo_user, seeds: {})
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

puts "== conversations batch: harness ready =="
$start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# ---- 1) conversations#index -------------------------------------------------
# gon.contacts = contacts_data -> current_user.contacts.mutual.joins(...).
# pluck(...) — pluck is UNSUPPORTED (contents op) -> NotImplementedError
# before any branchable query result -> crash-before-PC (documented honestly).
{
  "conversations_index_default" => { seeds: {}, params: { format: :html } },
}.each do |label, cfg|
  drive(ConversationsController, :index, cfg[:params], "conversations_index", label, seeds: cfg[:seeds])
end

# ---- 2) conversations#create ------------------------------------------------
# recipients_param check is concrete (params.present?). Then
# current_user.contacts.mutual.where(...).pluck(:person_id) — pluck is
# UNSUPPORTED -> NotImplementedError before any PC -> crash-before-PC.
{
  "conversations_create_default" => { seeds: {}, params: { contact_ids: "1,2", conversation: { subject: "Hi", text: "Hello" } } },
}.each do |label, cfg|
  drive(ConversationsController, :create, cfg[:params], "conversations_create", label, seeds: cfg[:seeds])
end

# ---- 3) conversations#show --------------------------------------------------
# current_user.conversations.where(id:).first — non-raising finder ->
# symbolic Conversation (records first_1_not_found PC both sides). `if
# @conversation` is the bare-truthiness gap (documented, only one concrete
# side per run). On the found side, @conversation.first_unread_message(...)
# real impl -> conversation_visibilities.where(...).first finder (records
# first_2 PC) then messages.to_a[-visibility.unread] -> SymbolicList#[] crash.
{
  "conversations_show_default"    => { seeds: {}, params: { id: 1, format: :json } },
  "conversations_show_notfound"   => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true }, params: { id: 1, format: :json } },
}.each do |label, cfg|
  drive(ConversationsController, :show, cfg[:params], "conversations_show", label, seeds: cfg[:seeds])
end

# ---- 4) conversations#raw ---------------------------------------------------
# Same outer finder (first_1_not_found PC). On found side:
# first_unread_message -> first_2 PC then crash on messages.to_a[...]. Also
# record pc from finder. render partial crashes on render plumbing.
{
  "conversations_raw_default"   => { seeds: {}, params: { conversation_id: 1, format: :html } },
  "conversations_raw_notfound"  => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true }, params: { conversation_id: 1, format: :html } },
}.each do |label, cfg|
  drive(ConversationsController, :raw, cfg[:params], "conversations_raw", label, seeds: cfg[:seeds])
end

# ---- 5) messages#create -----------------------------------------------------
# Conversation.find(params[:conversation_id]) — RAISING finder -> records
# first_1_not_found PC both sides (RecordNotFound raised on the missing
# side). current_user.build_message(conversation, opts) real impl ->
# conversation.messages.build (real). if message.save -> symbool
# (bare-truthiness gap). logger.info interpolation of message.id (SymInt)
# -> SymbolicInt#to_s NotImplementedError (crash on success path).
{
  "messages_create_default"   => { seeds: {}, params: { conversation_id: 1, message: { text: "Hello" } } },
  "messages_create_notfound"  => { seeds: { "SYM_RESULT_ActiveRecord__Core__ClassMethods_find_1_not_found" => true }, params: { conversation_id: 1, message: { text: "Hello" } } },
}.each do |label, cfg|
  drive(MessagesController, :create, cfg[:params], "messages_create", label, seeds: cfg[:seeds])
end

# ---- 6) conversation_visibilities#destroy -----------------------------------
# ConversationVisibility.where(...).first — non-raising finder -> symbolic
# ConstructorVisibility (first_1_not_found PC). if @vis (truthiness gap).
# @vis.conversation.participants.count — belongs_to on a symbolic record ->
# real association (empty DB -> nil) -> crash. if participants == 1 -> PC
# when reachable. @vis.destroy — destroy not a declared target -> real
# destroy on symbolic -> likely crash. redirect crashes on render plumbing.
{
  "conversation_visibilities_destroy_default"   => { seeds: {}, params: { conversation_id: 1 } },
  "conversation_visibilities_destroy_notfound"  => { seeds: { "SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => true }, params: { conversation_id: 1 } },
}.each do |label, cfg|
  drive(ConversationVisibilitiesController, :destroy, cfg[:params], "conversation_visibilities_destroy", label, seeds: cfg[:seeds])
end

$elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - $start
File.write(File.join(RESULTS, "elapsed_seconds.txt"), format("%.1f", $elapsed))
puts "== conversations batch done (elapsed #{$elapsed.round(2)}s) =="