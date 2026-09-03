# Verification probe for the 4 applied Rule T3 boundary fixes
# (docs/_BOUNDARY_FIX_DRAFT_20260903.md) in the SHARED concolic_targets.rb.
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require_relative "concolic_targets"

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)

RESULTS = {}
def check(name, ok, detail = "")
  RESULTS[name] = { ok: ok, detail: detail.to_s[0, 300] }
  puts "[#{ok ? "OK" : "FAIL"}] #{name}#{detail.empty? ? "" : " -- #{detail}"}"
end

def with_run(label)
  $interceptor.run(->(**) { yield }, {}, label: label)
end

# ------------------------------------------------------------------
# Fix 1 + Fix 3: count / sum / size notes via the fixed mocks
# ------------------------------------------------------------------
dump = with_run("fix13_probe") do
  rel = User.where(id: 1)
  _ = rel.size
  _ = rel.count
  _ = rel.sum(:id)
end
abort "fix13 run crashed: #{dump["error"]}" if dump["error"]
events = dump["events"].select { |e| e["type"] == "symbolic_call" }
def find_note(events, suffix)
  ev = events.find { |e| e["target"].to_s.end_with?(suffix) }
  ev && ev["note"]
end
size_note  = find_note(events, "Relation.size")
count_note = find_note(events, "Calculations.count")
sum_note   = find_note(events, "Calculations.sum")
check("Fix3 size -> SELECT COUNT(*)", size_note.to_s.start_with?("SELECT COUNT(*) FROM"), size_note.to_s)
check("Fix1 count -> SELECT COUNT(*)", count_note.to_s.start_with?("SELECT COUNT(*) FROM"), count_note.to_s)
check("Fix1 sum -> SELECT SUM(<tbl>.<col>)", sum_note.to_s =~ /\ASELECT SUM\("users"\."id"\) FROM / ? true : false, sum_note.to_s)

# ------------------------------------------------------------------
# Fix 2: gon runs the real body
# ------------------------------------------------------------------
require "action_controller/test_case"
gon_klass = Class.new(ActionController::Base) do
  include Gon::ControllerHelpers
  attr_accessor :request
  def initialize
    @request = ActionController::TestRequest.create(self.class)
  end
end
gon_controller = gon_klass.new
gon_out = {}
dump2 = with_run("fix2_gon_probe") do
  g1 = gon_controller.gon
  g2 = gon_controller.gon
  gon_out[:g1] = g1
  gon_out[:g2] = g2
  gon_out[:store_gon] = defined?(::RequestStore) ? ::RequestStore.store[:gon] : nil
end
check("Fix2 no run crash", !dump2["error"], (dump2["error"] || {}).to_s[0, 200])
check("Fix2 returns Gon module", gon_out[:g1] == ::Gon && gon_out[:g2] == ::Gon,
      "g1=#{gon_out[:g1].class} g2=#{gon_out[:g2].class}")
check("Fix2 RequestStore[:gon] set (real body ran)", !gon_out[:store_gon].nil?,
      gon_out[:store_gon] ? "class=#{gon_out[:store_gon].class}" : "nil")
gon_calls = dump2["events"].select { |e| e["type"] == "symbolic_call" && e["target"].to_s.include?("Gon::ControllerHelpers.gon") }
check("Fix2 interceptor records gon call", gon_calls.length == 2, "calls=#{gon_calls.length}")

# ------------------------------------------------------------------
# Fix 4: find_target loaded-target memo (same association read twice)
# ------------------------------------------------------------------
d4 = with_run("fix4_memo_probe") do
  owner = ConcolicTargets.symbolic_instance(User, "probe_owner", "SELECT \"users\".* FROM \"users\" WHERE 1=0")
  assoc_obj = ActiveRecord::Associations::SingularAssociation.allocate
  assoc_obj.instance_variable_set(:@owner, owner)
  assoc_obj.instance_variable_set(:@reflection, User.reflect_on_association(:person))
  def assoc_obj.owner; @owner; end
  def assoc_obj.reflection; @reflection; end
  @first  = assoc_obj.find_target
  @second = assoc_obj.find_target
  @assoc_klass = User.reflect_on_association(:person).klass
end
check("Fix4 no run crash", !d4["error"], (d4["error"] || {}).to_s[0, 200])
check("Fix4 same instance for repeated read", @first.equal?(@second), "first=#{@first.class} second=#{@second.class}")
check("Fix4 instance is association klass", @first.class == @assoc_klass, "expected #{@assoc_klass} got #{@first.class}")
ft_events = d4["events"].select { |e| e["type"] == "symbolic_call" && e["target"].to_s.include?("find_target") }
check("Fix4 one find_target event for two reads", ft_events.length == 1, "events=#{ft_events.length}")

# ------------------------------------------------------------------
d5 = with_run("fix4_memo_probe_second_run") do
  owner2 = ConcolicTargets.symbolic_instance(User, "probe_owner2", "SELECT \"users\".* FROM \"users\" WHERE 1=0")
  assoc_obj2 = ActiveRecord::Associations::SingularAssociation.allocate
  assoc_obj2.instance_variable_set(:@owner, owner2)
  assoc_obj2.instance_variable_set(:@reflection, User.reflect_on_association(:person))
  def assoc_obj2.owner; @owner; end
  def assoc_obj2.reflection; @reflection; end
  @first2 = assoc_obj2.find_target
end
check("Fix4 second run no crash", !d5["error"], (d5["error"] || {}).to_s[0, 200])
check("Fix4 second run gets a FRESH instance", !@first2.equal?(@first), "fresh=#{@first2.class}")
ft_events2 = d5["events"].select { |e| e["type"] == "symbolic_call" && e["target"].to_s.include?("find_target") }
check("Fix4 second run mints fresh event (no cross-run memo hit)", ft_events2.length == 1, "events=#{ft_events2.length}")

puts
failed = RESULTS.values.reject { |r| r[:ok] }
puts "TOTAL: #{RESULTS.length} checks, #{failed.length} FAILED"
RESULTS.each { |k, r| puts "  #{r[:ok] ? "PASS" : "FAIL"} #{k}" }
exit(failed.empty? ? 0 : 1)