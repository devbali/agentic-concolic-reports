#!/usr/bin/env jruby
# frozen_string_literal: true
#
# close_residual.rb — targeted residual-closing runs (COMPLETION_BRIEF.md's
# "close by execution" step), NOT the main exploration driver (run_dse.rb is
# that). Feeds each blocking missing combo's `concrete_values` (from a
# cap=4 coverage_report.py pass) straight in as `ConcolicTargets.
# seed_overrides` and records a real dump if the app actually reaches that
# combination — closing it in the corpus rather than by assumption. Combos
# that turn out infeasible (a seeded run produces a DIFFERENT path, proving
# the requested combination cannot co-occur) are left for
# coverage_assumptions.py instead, with the dump as evidence.
#
# Reuses run_dse.rb's exact controller-harness fixes (response wiring,
# action_name=, default_render-unless-performed fallback — see that file's
# comments for the full why); duplicated rather than required, since
# requiring run_dse.rb would immediately re-run its own top-level DSE loop.
#
# Usage:
#   /home/dev/.claude/jobs/302ac302/tmp/concolic-slot \
#       /home/dev/project/reports/diaspora/results3/notifications_index/close_residual.rb \
#       '[{"SYM_PARAM_show":"unread", ...}, {...}]'
#
# The single argument is a JSON array of seed-override hashes (one per
# combo to attempt), typically copy-pasted from coverage_summary.json's
# `missing[].concrete_values`.

require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require_relative "concolic_targets"
require_relative "targets"
require "json"
require "digest"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
NotificationsIndexTargets.install!($interceptor)
NotificationsController.layout(false)

HERE = File.dirname(File.expand_path(__FILE__))

def symbolic_user(tag)
  person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_#{tag}", "Person (current user's person)")
  user   = ConcolicTargets.symbolic_instance(User, "SYM_USER_#{tag}", "User (current)")
  user.define_singleton_method(:person) { person }
  user.define_singleton_method(:language) { "en" }
  user.define_singleton_method(:gender)   { "" }
  user.define_singleton_method(:unread_notifications) do
    Notification.where(recipient_id: user.id, unread: true)
  end
  user
end

def make_harness(controller_class)
  cname = controller_class.to_s.sub(/Controller\z/, "ControllerTest")
  Object.const_set(cname, Class.new(ActionController::TestCase)) unless Object.const_defined?(cname)
  test_class = Object.const_get(cname)
  test_class.instance_variable_set(:@concolic_ctrl, controller_class)
  def test_class.determine_default_controller_class(_name)
    @concolic_ctrl
  end
  tc = test_class.new("noop")
  tc.setup_controller_request_and_response
  tc.instance_variable_set(:@routes, Rails.application.routes)
  ctrl = tc.instance_variable_get(:@controller)
  ctrl.response = tc.instance_variable_get(:@response)
  [ctrl, tc]
end

def path_conditions(dump)
  (dump["events"] || [])
    .select { |e| e["type"] == "path_condition" }
    .map { |e| [e["expr"], e["taken"] ? true : false] }
end

combos = JSON.parse(ARGV[0] || "[]")
if combos.empty?
  warn "usage: close_residual.rb '<json array of seed-override hashes>'"
  exit 1
end

written = 0
combos.each_with_index do |seeds, i|
  ConcolicTargets.seed_overrides = seeds
  ctrl, = make_harness(NotificationsController)

  body = lambda do
    user = symbolic_user("NI")
    ctrl.singleton_class.define_method(:current_user)    { user }
    ctrl.singleton_class.define_method(:user_signed_in?) { true }
    ctrl.request.format = :html
    ctrl.send(:action_name=, "index")

    show_seed = ConcolicTargets.seed_for("SYM_PARAM_show", "unread")
    sym_show  = symstr("SYM_PARAM_show", show_seed)
    ctrl.params = { show: sym_show }.with_indifferent_access

    begin
      ctrl.send(:index)
      ctrl.send(:default_render) unless ctrl.performed?
    rescue Exception => e # rubocop:disable Lint/RescueException
      handled = begin
        ctrl.send(:rescue_with_handler, e)
      rescue Exception
        nil
      end
      raise e unless handled
      handled
    end
    :ok
  end

  label = format("residual%04d", i + 1)
  dump = $interceptor.run(body, {}, label: label, script: "close_residual.rb")
  hist = $interceptor.instance_variable_get(:@all_calls)
  hist.clear if hist.respond_to?(:clear)

  pcs = path_conditions(dump)
  dump["concolic_seeds"] = seeds
  dump["concolic_scenario"] = { "name" => "residual", "note" => "targeted close-by-execution run, seeded from a cap=4 missing combo" }
  File.write(File.join(HERE, "dump_#{label}.json"), JSON.pretty_generate(dump))
  written += 1
  puts format("  [%s] pcs=%d %s", label, pcs.size, dump["error"] ? "error=#{dump['error']['type']}" : "ok")
end

puts "wrote #{written} residual dumps"
