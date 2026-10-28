#!/usr/bin/env ruby
# frozen_string_literal: true

# _replay_missing.rb — directive 04:49 step 3: for every SAT missing item,
# feed the z3 model's concrete_values into the runner and execute that
# concrete run; record whether the run actually covers the branch.
#
# Model keys -> seed_overrides mapping (verified vs targets.rb):
#   SYM_LEN_X   -> "len(X)"        (lengths seed under len(<vn>))
#   everything else (SYM_PERSON_*, SYM_RESULT_*, assoc_*) as-is.
#
# For each of the 64 SAT items we run the DUAL-format scenario
# (anon_mobile_presenter equivalent: html presenter leg + mobile stream leg
# in one interceptor block) with ConcolicTargets.seed_overrides set from the
# model. Because both var families (bare records_1/2 + records_N_rows) are
# minted in one dump, a cross-format combo that co-occurs WILL be witnessed.
# After the run we check whether the dump's path conditions satisfy the item
# combo (all clauses present, len names renamed). Writes:
#   dump_replay_<idx>.json  (evidence; NOT deleting the corpus)
#   /tmp/replay_missing.json (per-item table: covered? / pcs / cmd)

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require_relative "concolic_targets"
require_relative "targets"
require_relative "dse_compose"
require "json"
require "set"
require "digest"
require "fileutils"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
PeopleTargets.install!($interceptor)
PeopleShowSymParams.install!($interceptor)

HERE = File.dirname(File.expand_path(__FILE__))
MAX_ITEMS = (ENV["MAX_ITEMS"] || 64).to_i

class StubWarden
  def initialize(user); @user = user; end
  def authenticate!(*_a); @user; end
  def authenticated?(*_a); true; end
  def user(*_a); @user; end
end

def make_harness(controller_class)
  cname = controller_class.to_s.sub(/Controller\z/, "ControllerTest")
  Object.const_set(cname, Class.new(ActionController::TestCase)) unless Object.const_defined?(cname)
  test_class = Object.const_get(cname)
  test_class.instance_variable_set(:@concolic_ctrl, controller_class)
  def test_class.determine_default_controller_class(_name); @concolic_ctrl; end
  tc = test_class.new("noop")
  tc.setup_controller_request_and_response
  tc.instance_variable_set(:@routes, Rails.application.routes)
  [tc.instance_variable_get(:@controller), tc]
end

PARAM_DEFAULT = "bob@example.org"

def run_dual(prefix, label, seeds)
  ConcolicTargets.seed_overrides = seeds
  PeopleTargets.begin_run!
  if defined?(::Gon) && ::Gon.instance_variable_defined?(:@concolic_preloads)
    ::Gon.instance_variable_set(:@concolic_preloads, {})
  end
  user        = PeopleTargets.symbolic_user("PE")
  sym_username = PeopleShowSymParams.symbolic_username(PARAM_DEFAULT)

  dual_render = lambda do
    [:html, :mobile].map do |leg|
      c2, t2 = make_harness(PeopleController)
      c2.singleton_class.define_method(:current_user)    { nil }
      c2.singleton_class.define_method(:user_signed_in?) { false }
      t2.instance_variable_get(:@request).env["warden"] = StubWarden.new(user)
      fmt = leg == :html ? nil : :mobile
      begin
        t2.process(:show, method: "GET", params: { username: sym_username }, format: fmt)
      rescue Exception => e # rubocop:disable Lint/RescueException
        handled = begin
          c2.send(:rescue_with_handler, e)
        rescue Exception # rubocop:disable Lint/RescueException
          nil
        end
        raise e unless handled
      end
      c2
    end
  end

  dump = $interceptor.run(
    -> { dual_render.call; :ok },
    {}, label: label, script: "_replay_missing.rb"
  )
  $interceptor.instance_variable_get(:@all_calls).clear
  dump
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

LEN_RE = /len\(([^()]+)\)/
def rename_len(s)
  s.gsub(LEN_RE) { "SYM_LEN_#{Regexp.last_match(1)}" }
end

# Map model keys -> seed_overrides keys.
def seeds_from_model(model)
  out = {}
  model.each do |k, v|
    key = k.start_with?("SYM_LEN_") ? "len(#{k.sub(/\ASYMLEN_/, "")})" : k
    out[key] = v
  end
  out
end

# Does a dump's path conditions satisfy the item combo?
# The combo is "C1 AND C2 AND ..." where each Ci is either EXPR (taken true)
# or Not(EXPR) (taken false). The dump covers it iff EVERY Ci has a matching
# PC (expr renamed len->SYM_LEN_, outcome == implied).
def combo_covered?(dump, node_constraint)
  clauses = node_constraint.split(" AND ").map(&:strip)
  pcs = path_conditions(dump).map { |expr, taken| [rename_len(expr), taken] }
  clauses.all? do |clause|
    if clause.start_with?("Not(") && clause.end_with?(")")
      inner  = clause[4..-2]
      wanted = false
      # defensive: only treat as Not(...) at top level; else it's a clause
      # naming a var whose negation is demanded — handle by plain expr match
      pcs.any? { |pe, pt| pe == inner && pt == wanted } ||
        pcs.any? { |pe, pt| pe == clause && pt == true }
    else
      pcs.any? { |pe, pt| pe == clause && pt == true }
    end
  end
end

data = JSON.parse(File.read("/tmp/per_item_sat.json"))
rows = data["rows"].first(MAX_ITEMS)
puts "== replay #{rows.size} SAT models through dual-format anon_mobile_presenter =="
results = []
covered_count = 0

rows.each_with_index do |row, idx|
  model = row["model"]
  if model.nil? || model.empty?
    puts "  [#{idx}] SKIP (no model)"
    results << { "idx" => idx, "verdict" => row["verdict"], "covered" => false, "reason" => "no_model" }
    next
  end
  label = format("replay_%03d", idx)
  begin
    dump = run_dual("anon_mobile_presenter", label, seeds_from_model(model))
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts "  [#{idx}] HARNESS FAILURE #{e.class}: #{e.message.to_s[0,160]}"
    results << { "idx" => idx, "verdict" => row["verdict"], "covered" => false, "reason" => "harness_failure:#{e.class}" }
    next
  end

  # write evidence dump
  File.write(File.join(HERE, "dump_#{label}.json"), JSON.pretty_generate(dump))

  nc   = row["node_constraint"]
  covered = combo_covered?(dump, nc)
  covered_count += 1 if covered
  pcs  = path_conditions(dump).size
  err  = dump["error"] ? dump["error"]["type"] : nil
  puts format("  [%3d] pcs=%-4d covered=%-5s err=%s", idx, pcs, covered, err)
  results << {
    "idx" => idx, "verdict" => row["verdict"], "covered" => covered,
    "pcs" => pcs, "dump" => "dump_#{label}.json", "error" => err,
  }
end

summary = {
  "items_attempted" => results.size,
  "covered" => covered_count,
  "uncovered" => results.size - covered_count,
  "results" => results,
}
File.write("/tmp/replay_missing.json", JSON.pretty_generate(summary))
puts "== replay summary: covered=#{covered_count}/#{results.size} =="
puts "wrote /tmp/replay_missing.json"