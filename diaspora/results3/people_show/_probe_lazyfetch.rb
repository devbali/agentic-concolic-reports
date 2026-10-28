#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_lazyfetch.rb — RC-1 follow-up. Under concolic_mod the app's REAL
# Profile gains lazy accessors that call `self.reload` when the attribute is
# absent, producing a second, full-width `profiles` statement gated on the
# disclosure branch. Does that second statement ever fire on a SYMBOLIC
# Profile row (the only kind this harness produces)?
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require_relative "concolic_targets"

ActiveRecord::Base.establish_connection(:concolic)
$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)

puts "Rails.env                       = #{Rails.env}"
puts "Profile.default_scopes.size     = #{Profile.default_scopes.size}"
puts "Profile.column_names.size       = #{Profile.column_names.size}"
puts "lazy accessor :bio on class?    = #{Profile.instance_methods(false).include?(:bio)}"
puts "default_projection(Profile)     = #{ConcolicTargets.default_projection(Profile)[0, 90]}..."

p = ConcolicTargets.symbolic_instance(Profile, "PROBE_PROFILE", "probe")
puts "symbolic row singleton :bio?    = #{p.singleton_methods.include?(:bio)}"
puts "  -> singleton SHADOWS the lazy accessor = #{p.singleton_methods.include?(:bio)}"
begin
  v = p.bio
  puts "p.bio                           = #{v.class} #{(v.respond_to?(:sym_name) ? v.sym_name : v).inspect[0, 60]}"
  puts "  -> read WITHOUT any reload / second statement"
rescue StandardError => e
  puts "p.bio raised #{e.class}: #{e.message[0, 80]}"
end
puts "PROBE DONE"
